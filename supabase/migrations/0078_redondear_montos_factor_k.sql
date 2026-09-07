-- Bug real, reportado por Seba al correr 0077 en el SQL Editor: los montos salían con más de cien
-- dígitos decimales. Causa: `numeric` en Postgres es aritmética decimal EXACTA, no float -- una
-- división (`pct / 100`) ya agrega dígitos de escala, y encadenar varias multiplicaciones de esos
-- resultados (costo_costo * (1+gg_pct/100) * (1+imprevistos_pct/100) * ...) va sumando la escala de
-- cada paso sobre la anterior. Con 5-6 multiplicaciones encadenadas, la escala final explota.
--
-- Costo-Costo daba 0 en la misma corrida -- eso NO es un bug de esta función: el SQL Editor corre
-- sin usuario logueado, y calcular_composicion_detalle_subitem (que esta función llama por dentro)
-- filtra por is_obra_member/auth.uid() -- mismo caso de siempre, ya documentado en el comentario de
-- verificación de varias migraciones anteriores. La prueba real es en la app, logueado.
--
-- Arreglo: redondear a 2 decimales SOLO en la salida (las 5 columnas monetarias de cada rama del
-- UNION ALL: base_monto, monto, costo_costo, costo_total_trabajo, precio_final) -- nunca en las CTEs
-- intermedias. El chequeo de cierre (cierra_ok, en la CTE `cierre`) se sigue calculando sobre los
-- valores SIN redondear -- si redondeara cada línea individualmente antes de sumar, un centavo de
-- diferencia por redondeo podría hacer que cierra_ok diera `false` sin que hubiera ningún error real
-- de cálculo. `pct` no se redondea -- son valores de configuración ya limpios (15, 4, 1.5, etc.),
-- nunca pasan por la cadena de multiplicaciones que causa el problema.
--
-- `create or replace` alcanza -- misma firma, mismo `returns table`, solo cambia qué expresión
-- calcula cada columna de la salida final.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor), después de 0077. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

create or replace function calcular_factor_k_subitem(p_obra_id uuid, p_subitem_id uuid)
returns table(
  vista text,
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
    select cm_beneficio.*,
      costo_costo
        * (1 + gg_pct / 100) * (1 + imprevistos_pct / 100) * (1 + epp_pct / 100)
        * (1 + costo_financiero_pct / 100) * (1 + beneficio_pct / 100)
        as costo_total_trabajo_cm
    from cm_beneficio
  ),
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
    select sm_gestion.*,
      ((costo_costo_sm + gg_monto) * (1 + imprevistos_pct / 100) + epp_monto + costo_financiero_monto)
        * (1 + beneficio_pct / 100)
        + gestion_materiales_terceros_monto
        as costo_total_trabajo_sm
    from sm_gestion
  ),
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
    select sm.*,
      it.impuestos_monto_cm, it.impuestos_monto_sm,
      sm.costo_total_trabajo_cm * (1 + it.impuestos_pct_total) as precio_final_cm,
      sm.costo_total_trabajo_sm * (1 + it.impuestos_pct_total) as precio_final_sm
    from sm
    cross join impuestos_totales it
  ),
  cierre as (
    -- Chequeo de cierre sobre valores SIN redondear -- ver comentario de cabecera.
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
  -- === Salida: una fila por línea -- base_monto/monto/costo_costo/costo_total_trabajo/precio_final
  -- redondeados acá, es el único lugar de todo el cuerpo donde se redondea. =======================
  select 'con_materiales', 1, 'Gastos Generales', gg_pct,
    'Costo-Costo', round(costo_costo, 2), round(gg_monto, 2),
    round(costo_costo, 2), round(costo_total_trabajo_cm, 2), round(precio_final_cm, 2),
    insumos_con_precio, insumos_total, cierra_ok_cm
  from cierre
  union all
  select 'con_materiales', 2, 'Imprevistos', imprevistos_pct,
    'Costo-Costo + GG', round(costo_costo + gg_monto, 2), round(imprevistos_monto, 2),
    round(costo_costo, 2), round(costo_total_trabajo_cm, 2), round(precio_final_cm, 2),
    insumos_con_precio, insumos_total, cierra_ok_cm
  from cierre
  union all
  select 'con_materiales', 3, 'EPP-Seguridad', epp_pct,
    'Costo-Costo + GG + Imprevistos', round(costo_costo + gg_monto + imprevistos_monto, 2), round(epp_monto, 2),
    round(costo_costo, 2), round(costo_total_trabajo_cm, 2), round(precio_final_cm, 2),
    insumos_con_precio, insumos_total, cierra_ok_cm
  from cierre
  union all
  select 'con_materiales', 4, 'Costo Financiero', costo_financiero_pct,
    'Costo-Costo + GG + Imprevistos + EPP',
    round(costo_costo + gg_monto + imprevistos_monto + epp_monto, 2), round(costo_financiero_monto, 2),
    round(costo_costo, 2), round(costo_total_trabajo_cm, 2), round(precio_final_cm, 2),
    insumos_con_precio, insumos_total, cierra_ok_cm
  from cierre
  union all
  select 'con_materiales', 5, 'Beneficio', beneficio_pct,
    'Costo-Costo + GG + Imprevistos + EPP + Costo Financiero',
    round(costo_costo + gg_monto + imprevistos_monto + epp_monto + costo_financiero_monto, 2),
    round(beneficio_monto, 2),
    round(costo_costo, 2), round(costo_total_trabajo_cm, 2), round(precio_final_cm, 2),
    insumos_con_precio, insumos_total, cierra_ok_cm
  from cierre
  union all
  select 'con_materiales', 5 + oi.orden,
    case oi.tipo
      when 'iva' then 'IVA'
      when 'iibb' then 'Ingresos Brutos'
      when 'tasas_municipales' then 'Tasas Municipales'
      else coalesce(oi.nombre_otro, 'Otro')
    end,
    oi.porcentaje, 'Costo Total del Trabajo', round(c.costo_total_trabajo_cm, 2),
    round(oi.porcentaje * c.costo_total_trabajo_cm / 100, 2),
    round(c.costo_costo, 2), round(c.costo_total_trabajo_cm, 2), round(c.precio_final_cm, 2),
    c.insumos_con_precio, c.insumos_total, c.cierra_ok_cm
  from cierre c
  cross join obra_impuestos oi
  where oi.obra_id = p_obra_id
  union all
  select 'sin_materiales', 1, 'Gastos Generales', gg_pct,
    'Costo-Costo', round(costo_costo, 2), round(gg_monto, 2),
    round(costo_costo_sm, 2), round(costo_total_trabajo_sm, 2), round(precio_final_sm, 2),
    insumos_con_precio, insumos_total, cierra_ok_sm
  from cierre
  union all
  select 'sin_materiales', 2, 'Imprevistos', imprevistos_pct,
    'Costo-Costo + GG', round(costo_costo_sm + gg_monto, 2), round(imprevistos_monto_sm, 2),
    round(costo_costo_sm, 2), round(costo_total_trabajo_sm, 2), round(precio_final_sm, 2),
    insumos_con_precio, insumos_total, cierra_ok_sm
  from cierre
  union all
  select 'sin_materiales', 3, 'EPP-Seguridad', epp_pct,
    'Costo-Costo + GG + Imprevistos', round(costo_costo + gg_monto + imprevistos_monto, 2), round(epp_monto, 2),
    round(costo_costo_sm, 2), round(costo_total_trabajo_sm, 2), round(precio_final_sm, 2),
    insumos_con_precio, insumos_total, cierra_ok_sm
  from cierre
  union all
  select 'sin_materiales', 4, 'Costo Financiero', costo_financiero_pct,
    'Costo-Costo + GG + Imprevistos + EPP',
    round(costo_costo + gg_monto + imprevistos_monto + epp_monto, 2), round(costo_financiero_monto, 2),
    round(costo_costo_sm, 2), round(costo_total_trabajo_sm, 2), round(precio_final_sm, 2),
    insumos_con_precio, insumos_total, cierra_ok_sm
  from cierre
  union all
  select 'sin_materiales', 5, 'Beneficio', beneficio_pct,
    'Costo-Costo + GG + Imprevistos + EPP + Costo Financiero',
    round(costo_costo_sm + gg_monto + imprevistos_monto_sm + epp_monto + costo_financiero_monto, 2),
    round(beneficio_monto_sm, 2),
    round(costo_costo_sm, 2), round(costo_total_trabajo_sm, 2), round(precio_final_sm, 2),
    insumos_con_precio, insumos_total, cierra_ok_sm
  from cierre
  union all
  select 'sin_materiales', 6, 'Gestión de materiales de terceros', gestion_materiales_terceros_pct,
    'Materiales de la vista con materiales', round(materiales_subtotal, 2), round(gestion_materiales_terceros_monto, 2),
    round(costo_costo_sm, 2), round(costo_total_trabajo_sm, 2), round(precio_final_sm, 2),
    insumos_con_precio, insumos_total, cierra_ok_sm
  from cierre
  union all
  select 'sin_materiales', 6 + oi.orden,
    case oi.tipo
      when 'iva' then 'IVA'
      when 'iibb' then 'Ingresos Brutos'
      when 'tasas_municipales' then 'Tasas Municipales'
      else coalesce(oi.nombre_otro, 'Otro')
    end,
    oi.porcentaje, 'Costo Total del Trabajo', round(c.costo_total_trabajo_sm, 2),
    round(oi.porcentaje * c.costo_total_trabajo_sm / 100, 2),
    round(c.costo_costo_sm, 2), round(c.costo_total_trabajo_sm, 2), round(c.precio_final_sm, 2),
    c.insumos_con_precio, c.insumos_total, c.cierra_ok_sm
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
-- Mismas consultas que 0077, ahora sin necesitar el round() manual -- la función ya devuelve 2
-- decimales. Logueado en la app (no desde el SQL Editor, ver comentario de cabecera), Costo-Costo
-- de 8.1 tiene que dar ~95.822,14 (el mismo número que ya muestra "Precio unitario de la partida"
-- en ComposicionApuScreen) y cierra_ok true en las dos vistas.
-- select vista, orden, concepto, pct, base_texto, base_monto, monto, costo_costo,
--        costo_total_trabajo, precio_final, insumos_con_precio, insumos_total, cierra_ok
-- from calcular_factor_k_subitem(
--   '<obra_id>'::uuid,
--   (select id from subitems where codigo = '8.1' and creador_usuario_id is null)
-- );
