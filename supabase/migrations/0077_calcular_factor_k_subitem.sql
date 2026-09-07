-- Factor K, Paso B: precio final de una partida puntual, con la cascada completa de 6 conceptos +
-- impuestos aplicada sobre el Costo-Costo real de esa partida. Diagnóstico completo en la
-- conversación (no hay doc nuevo en docs/ para esta pieza puntual -- docs/factor_k_apu_decisiones.md
-- sigue siendo la referencia del Paso A, esto es su continuación).
--
-- `language sql`, no `plpgsql` -- a propósito, después de toda la sesión de hoy con ambigüedades de
-- columna en PL/pgSQL (0075/0076). Una función SQL pura no tiene variables declaradas, así que esa
-- clase entera de bug no puede pasar acá. La cascada se arma con CTEs encadenadas (cada paso agrega
-- una sola columna sobre el paso anterior), no con variables `v_*`.
--
-- Mismos dos parámetros que calcular_composicion_detalle_subitem -- la llama internamente para el
-- Costo-Costo en vez de que Dart se lo pase ya sumado. Es la única forma de que la cuenta viva en
-- un solo lugar: si Dart pasara el total, esta función confiaría en un número que no controló.
--
-- Devuelve una fila por línea (concepto), no una fila con veinte columnas -- mismo criterio que
-- calcular_valor_hora_mano_obra (una fila por categoría UOCRA). Las columnas de resumen
-- (costo_costo/costo_total_trabajo/precio_final/insumos_con_precio/insumos_total/cierra_ok) van
-- repetidas en cada fila de la misma vista -- desnormalizado a propósito, Postgres no da "una fila
-- de cabecera + muchas de detalle" en una sola relación sin jsonb, y acá no hace falta jsonb.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor), después de 0076. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

-- =====================================================================
-- Chequeo de cierre: cómo se hace que sea un chequeo real, no una tautología
-- =====================================================================
--
-- Si costo_total_trabajo se definiera como "costo_costo + gg_monto + imprevistos_monto + ... +
-- beneficio_monto" y el chequeo comparara esa misma suma contra sí misma, el chequeo daría true
-- SIEMPRE, sin importar si alguna línea individual está mal calculada -- no serviría para nada.
--
-- Por eso costo_total_trabajo_cm y precio_final_cm se calculan acá con una fórmula DISTINTA
-- (producto de factores: costo_costo * (1+gg_pct/100) * (1+imprevistos_pct/100) * ...), matemáticamente
-- equivalente a la suma acumulada si todo está bien, pero derivada de manera independiente. El
-- chequeo de cierre compara las dos: si alguna línea individual usa la base equivocada (ej.
-- Imprevistos calculado sobre Costo-Costo en vez de Costo-Costo + GG), las dos fórmulas divergen y
-- cierra_ok da false. Mismo truco para sin_materiales, con el producto acotado a los dos pasos que
-- de verdad son porcentaje-sobre-base (Imprevistos y Beneficio) -- GG/EPP/Costo Financiero ahí son
-- montos copiados, no hay nada que verificar con producto de factores para esos tres.

create or replace function calcular_factor_k_subitem(p_obra_id uuid, p_subitem_id uuid)
returns table(
  vista text,              -- 'con_materiales' | 'sin_materiales'
  orden int,
  concepto text,
  pct numeric,
  base_texto text,
  base_monto numeric,
  monto numeric,
  costo_costo numeric,
  costo_total_trabajo numeric,
  precio_final numeric,
  insumos_con_precio int,
  insumos_total int,
  cierra_ok boolean
)
language sql security definer set search_path = public stable as $$
  with detalle as (
    select * from calcular_composicion_detalle_subitem(p_obra_id, p_subitem_id)
  ),
  agregado as (
    -- Costo-Costo = suma de rendimiento×precio de TODO lo que tiene precio cargado (mano de obra +
    -- materiales + equipos). Si falta precio en alguna línea, insumos_con_precio < insumos_total
    -- avisa que este número no es confiable todavía -- mismo criterio que ApuPrecioSubitem.completo
    -- en Dart, ahora con la fuente de verdad acá.
    select
      (count(*))::int as insumos_total,
      (count(*) filter (where d.precio_unitario is not null))::int as insumos_con_precio,
      coalesce(sum(d.rendimiento * d.precio_unitario) filter (where d.precio_unitario is not null), 0)
        as costo_costo,
      coalesce(sum(d.rendimiento * d.precio_unitario)
        filter (where d.tipo_componente = 'material' and d.precio_unitario is not null), 0)
        as materiales_subtotal
    from detalle d
  ),
  config as (
    select gg_pct, imprevistos_pct, epp_pct, costo_financiero_pct, beneficio_pct,
           gestion_materiales_terceros_pct
    from obra_presupuesto_config c
    where c.obra_id = p_obra_id
  ),
  -- === Con materiales: cascada secuencial -- lo que se muestra línea por línea =================
  cm_gg as (
    select a.*, co.*,
      a.costo_costo * co.gg_pct / 100 as gg_monto
    from agregado a
    cross join config co
  ),
  cm_imprevistos as (
    select cm_gg.*,
      (costo_costo + gg_monto) * imprevistos_pct / 100 as imprevistos_monto
    from cm_gg
  ),
  cm_epp as (
    select cm_imprevistos.*,
      (costo_costo + gg_monto + imprevistos_monto) * epp_pct / 100 as epp_monto
    from cm_imprevistos
  ),
  cm_cf as (
    select cm_epp.*,
      (costo_costo + gg_monto + imprevistos_monto + epp_monto) * costo_financiero_pct / 100
        as costo_financiero_monto
    from cm_epp
  ),
  cm_beneficio as (
    select cm_cf.*,
      (costo_costo + gg_monto + imprevistos_monto + epp_monto + costo_financiero_monto)
        * beneficio_pct / 100 as beneficio_monto
    from cm_cf
  ),
  cm as (
    -- costo_total_trabajo_cm: fórmula independiente (producto de factores), ver comentario de
    -- cabecera "Chequeo de cierre".
    select cm_beneficio.*,
      costo_costo
        * (1 + gg_pct / 100) * (1 + imprevistos_pct / 100) * (1 + epp_pct / 100)
        * (1 + costo_financiero_pct / 100) * (1 + beneficio_pct / 100)
        as costo_total_trabajo_cm
    from cm_beneficio
  ),
  -- === Sin materiales: GG/EPP/Costo Financiero se COPIAN (mismo monto que arriba, no se
  -- recalculan), Imprevistos y Beneficio se recalculan sobre Costo-Costo sin materiales, Gestión de
  -- materiales de terceros se agrega al final -- ver docs/factor_k_apu_decisiones.md §3 y la hoja
  -- APU_SIN_MATERIALES de la planilla (cita completa en CLAUDE.md, sección "Vista sin materiales").
  sm_base as (
    select cm.*,
      (costo_costo - materiales_subtotal) as costo_costo_sm
    from cm
  ),
  sm_imprevistos as (
    select sm_base.*,
      (costo_costo_sm + gg_monto) * imprevistos_pct / 100 as imprevistos_monto_sm
    from sm_base
  ),
  sm_beneficio as (
    select sm_imprevistos.*,
      (costo_costo_sm + gg_monto + imprevistos_monto_sm + epp_monto + costo_financiero_monto)
        * beneficio_pct / 100 as beneficio_monto_sm
    from sm_imprevistos
  ),
  sm_gestion as (
    select sm_beneficio.*,
      materiales_subtotal * gestion_materiales_terceros_pct / 100 as gestion_materiales_terceros_monto
    from sm_beneficio
  ),
  sm as (
    -- costo_total_trabajo_sm: fórmula independiente, acotada a los dos pasos que son
    -- porcentaje-sobre-base (Imprevistos, Beneficio) -- GG/EPP/Costo Financiero entran como montos
    -- fijos, no como factores, porque acá son copias, no un % de nada.
    select sm_gestion.*,
      ((costo_costo_sm + gg_monto) * (1 + imprevistos_pct / 100) + epp_monto + costo_financiero_monto)
        * (1 + beneficio_pct / 100)
        + gestion_materiales_terceros_monto
        as costo_total_trabajo_sm
    from sm_gestion
  ),
  -- === Impuestos: planos, los 4 sobre la misma base cada uno, no encadenados -- confirmado por la
  -- planilla (las 3 líneas de impuestos apuntan al costo total, no una sobre otra). ===============
  impuestos as (
    select oi.tipo, oi.nombre_otro, oi.porcentaje, oi.orden,
      sm.costo_total_trabajo_cm, sm.costo_total_trabajo_sm
    from obra_impuestos oi
    cross join sm
    where oi.obra_id = p_obra_id
  ),
  impuestos_totales as (
    select
      sum(porcentaje) / 100 as impuestos_pct_total,
      sum(porcentaje * costo_total_trabajo_cm / 100) as impuestos_monto_cm,
      sum(porcentaje * costo_total_trabajo_sm / 100) as impuestos_monto_sm
    from impuestos
  ),
  resumen as (
    -- precio_final: mismo truco, factor sobre el costo total en vez de sumar las 4 líneas.
    select sm.*,
      it.impuestos_monto_cm, it.impuestos_monto_sm,
      sm.costo_total_trabajo_cm * (1 + it.impuestos_pct_total) as precio_final_cm,
      sm.costo_total_trabajo_sm * (1 + it.impuestos_pct_total) as precio_final_sm
    from sm
    cross join impuestos_totales it
  ),
  cierre as (
    select resumen.*,
      (
        costo_costo + gg_monto + imprevistos_monto + epp_monto + costo_financiero_monto + beneficio_monto
          = costo_total_trabajo_cm
        and costo_total_trabajo_cm + impuestos_monto_cm = precio_final_cm
      ) as cierra_ok_cm,
      (
        costo_costo_sm + gg_monto + imprevistos_monto_sm + epp_monto + costo_financiero_monto
          + beneficio_monto_sm + gestion_materiales_terceros_monto = costo_total_trabajo_sm
        and costo_total_trabajo_sm + impuestos_monto_sm = precio_final_sm
      ) as cierra_ok_sm
    from resumen
  )
  -- === Salida: una fila por línea =================================================================
  select 'con_materiales', 1, 'Gastos Generales', gg_pct,
    'Costo-Costo', costo_costo, gg_monto,
    costo_costo, costo_total_trabajo_cm, precio_final_cm, insumos_con_precio, insumos_total, cierra_ok_cm
  from cierre
  union all
  select 'con_materiales', 2, 'Imprevistos', imprevistos_pct,
    'Costo-Costo + GG', costo_costo + gg_monto, imprevistos_monto,
    costo_costo, costo_total_trabajo_cm, precio_final_cm, insumos_con_precio, insumos_total, cierra_ok_cm
  from cierre
  union all
  select 'con_materiales', 3, 'EPP-Seguridad', epp_pct,
    'Costo-Costo + GG + Imprevistos', costo_costo + gg_monto + imprevistos_monto, epp_monto,
    costo_costo, costo_total_trabajo_cm, precio_final_cm, insumos_con_precio, insumos_total, cierra_ok_cm
  from cierre
  union all
  select 'con_materiales', 4, 'Costo Financiero', costo_financiero_pct,
    'Costo-Costo + GG + Imprevistos + EPP',
    costo_costo + gg_monto + imprevistos_monto + epp_monto, costo_financiero_monto,
    costo_costo, costo_total_trabajo_cm, precio_final_cm, insumos_con_precio, insumos_total, cierra_ok_cm
  from cierre
  union all
  select 'con_materiales', 5, 'Beneficio', beneficio_pct,
    'Costo-Costo + GG + Imprevistos + EPP + Costo Financiero',
    costo_costo + gg_monto + imprevistos_monto + epp_monto + costo_financiero_monto, beneficio_monto,
    costo_costo, costo_total_trabajo_cm, precio_final_cm, insumos_con_precio, insumos_total, cierra_ok_cm
  from cierre
  union all
  select 'con_materiales', 5 + oi.orden,
    case oi.tipo
      when 'iva' then 'IVA'
      when 'iibb' then 'Ingresos Brutos'
      when 'tasas_municipales' then 'Tasas Municipales'
      else coalesce(oi.nombre_otro, 'Otro')
    end,
    oi.porcentaje, 'Costo Total del Trabajo', c.costo_total_trabajo_cm,
    oi.porcentaje * c.costo_total_trabajo_cm / 100,
    c.costo_costo, c.costo_total_trabajo_cm, c.precio_final_cm, c.insumos_con_precio, c.insumos_total, c.cierra_ok_cm
  from cierre c
  cross join obra_impuestos oi
  where oi.obra_id = p_obra_id
  union all
  select 'sin_materiales', 1, 'Gastos Generales', gg_pct,
    -- base_monto: el Costo-Costo CON materiales -- es de ahí que sale realmente este monto
    -- (copiado, no recalculado). Mostrar costo_costo_sm acá sería inventar una relación
    -- base×pct=monto que no es la que produjo el número.
    'Costo-Costo', costo_costo, gg_monto,
    costo_costo_sm, costo_total_trabajo_sm, precio_final_sm, insumos_con_precio, insumos_total, cierra_ok_sm
  from cierre
  union all
  select 'sin_materiales', 2, 'Imprevistos', imprevistos_pct,
    -- Esta sí se recalcula de verdad -- base_monto es la base sin materiales real.
    'Costo-Costo + GG', costo_costo_sm + gg_monto, imprevistos_monto_sm,
    costo_costo_sm, costo_total_trabajo_sm, precio_final_sm, insumos_con_precio, insumos_total, cierra_ok_sm
  from cierre
  union all
  select 'sin_materiales', 3, 'EPP-Seguridad', epp_pct,
    'Costo-Costo + GG + Imprevistos', costo_costo + gg_monto + imprevistos_monto, epp_monto,
    costo_costo_sm, costo_total_trabajo_sm, precio_final_sm, insumos_con_precio, insumos_total, cierra_ok_sm
  from cierre
  union all
  select 'sin_materiales', 4, 'Costo Financiero', costo_financiero_pct,
    'Costo-Costo + GG + Imprevistos + EPP', costo_costo + gg_monto + imprevistos_monto + epp_monto,
    costo_financiero_monto,
    costo_costo_sm, costo_total_trabajo_sm, precio_final_sm, insumos_con_precio, insumos_total, cierra_ok_sm
  from cierre
  union all
  select 'sin_materiales', 5, 'Beneficio', beneficio_pct,
    'Costo-Costo + GG + Imprevistos + EPP + Costo Financiero',
    costo_costo_sm + gg_monto + imprevistos_monto_sm + epp_monto + costo_financiero_monto, beneficio_monto_sm,
    costo_costo_sm, costo_total_trabajo_sm, precio_final_sm, insumos_con_precio, insumos_total, cierra_ok_sm
  from cierre
  union all
  select 'sin_materiales', 6, 'Gestión de materiales de terceros', gestion_materiales_terceros_pct,
    'Materiales de la vista con materiales', materiales_subtotal, gestion_materiales_terceros_monto,
    costo_costo_sm, costo_total_trabajo_sm, precio_final_sm, insumos_con_precio, insumos_total, cierra_ok_sm
  from cierre
  union all
  select 'sin_materiales', 6 + oi.orden,
    case oi.tipo
      when 'iva' then 'IVA'
      when 'iibb' then 'Ingresos Brutos'
      when 'tasas_municipales' then 'Tasas Municipales'
      else coalesce(oi.nombre_otro, 'Otro')
    end,
    oi.porcentaje, 'Costo Total del Trabajo', c.costo_total_trabajo_sm,
    oi.porcentaje * c.costo_total_trabajo_sm / 100,
    c.costo_costo_sm, c.costo_total_trabajo_sm, c.precio_final_sm, c.insumos_con_precio, c.insumos_total, c.cierra_ok_sm
  from cierre c
  cross join obra_impuestos oi
  where oi.obra_id = p_obra_id
  order by 1, 2;
$$;

grant execute on function calcular_factor_k_subitem(uuid, uuid) to authenticated;

-- =====================================================================
-- Verificación
-- =====================================================================
--
-- Partida chica (8.1, Mampostería) -- para sumar a mano y confirmar que cierra_ok da true por las
-- razones correctas, no por casualidad.
-- select vista, orden, concepto, pct, base_texto, round(base_monto, 2) as base_monto,
--        round(monto, 2) as monto, round(costo_costo, 2) as costo_costo,
--        round(costo_total_trabajo, 2) as costo_total_trabajo, round(precio_final, 2) as precio_final,
--        insumos_con_precio, insumos_total, cierra_ok
-- from calcular_factor_k_subitem(
--   '<obra_id>'::uuid,
--   (select id from subitems where codigo = '8.1' and creador_usuario_id is null)
-- );

-- Partida de Steel Frame (5.1) -- para ver el contraste real entre las dos vistas (materiales-
-- intensiva, así que Gestión de materiales de terceros y el recorte de base de Imprevistos/
-- Beneficio se tienen que notar).
-- select vista, orden, concepto, pct, base_texto, round(base_monto, 2) as base_monto,
--        round(monto, 2) as monto, round(costo_total_trabajo, 2) as costo_total_trabajo,
--        round(precio_final, 2) as precio_final, cierra_ok
-- from calcular_factor_k_subitem(
--   '<obra_id>'::uuid,
--   (select id from subitems where codigo = '5.1' and creador_usuario_id is null)
-- );

-- Si cierra_ok da false en cualquiera de las dos: es un bug de esta función (una línea usando la
-- base equivocada), no un problema de redondeo -- numeric es aritmética decimal exacta, no float.
