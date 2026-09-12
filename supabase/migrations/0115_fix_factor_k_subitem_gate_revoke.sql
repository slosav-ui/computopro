-- Regresión de seguridad encontrada revisando la Tanda 2 de Adicionales (2026-09-12): la 0110 hizo
-- `drop` + `create` de `calcular_factor_k_subitem` para sumarle `p_config_congelada`, y en el camino
-- se perdieron tres cosas de la versión anterior (0078/0085):
--
-- 1) El gate de membresía (`autorizado`/`is_obra_member`, 0085). Un usuario autenticado que no es
--    miembro de una obra volvía a poder leer sus % de Factor K (GG, Imprevistos, EPP, Costo
--    Financiero, Beneficio, Gestión de materiales de terceros, impuestos) si conoce su id -- el caso
--    exacto de la verificación 1 de la 0085. Con `p_config_congelada = true`, además, los % con los
--    que se firmó la obra (`presupuesto_config_congelado`).
-- 2) El `revoke ... from public, anon` (0085). Una función creada de nuevo nace ejecutable por
--    PUBLIC, y en este proyecto anon además tiene grant directo por default privileges (lección de
--    la 0085/0101) -- anon también podía llamarla, sin sesión.
-- 3) El redondeo de salida a 2 decimales (0078). No es de seguridad, pero se perdió en el mismo
--    drop + create: la 0110 decía en su cabecera que con el default se comportaba "EXACTO igual que
--    hoy", y no era así -- los montos volvieron a salir con decenas de decimales (el bug original
--    de la 0078). Se devuelve igual que estaba: solo en la salida, nunca en las CTEs intermedias, y
--    `cierra_ok` sigue calculándose sobre valores sin redondear.
--
-- Cuerpo: el de la 0110 (misma firma, misma lógica de la rama congelada) con esas tres cosas
-- devueltas -- nada más. `create or replace`: la firma (uuid, uuid, boolean) es la vigente, así que
-- no hace falta otro drop.
--
-- De paso, misma auditoría pedida por Seba sobre TODAS las funciones de supabase/migrations/
-- (script que simula create/replace/drop/grant/revoke/alter en orden, las 69 funciones):
-- - Gate perdido: solo esta. (`calcular_saldo_pendiente_avance_medido`, 0105, aparece sin
--   `is_obra_member` en el cuerpo pero delega en `calcular_monto_congelado_ajustado`, que corta con
--   excepción a un no-miembro -- falso positivo.)
-- - SECURITY DEFINER con EXECUTE abierto a anon: solo esta. `previsualizar_invitacion` también
--   figura, pero es la excepción deliberada documentada en la 0096/0101 -- no se toca.
-- - `search_path` perdido por recrear la función sin `set search_path` (el caso ya visto con
--   `calcular_totales_certificado`): esa misma y `calcular_monto_periodo_avance`, las dos en la 0105
--   (la 0085 se los había fijado con `alter function`), más `calcular_monto_total_adicional`
--   (0112/0113), que nunca lo tuvo. Las tres son SECURITY INVOKER -- gravedad menor, mismo criterio
--   que el paso 3 de la 0085 -- y se cierran con `alter function`, sin tocar el cuerpo. Todas
--   referencian solo objetos de `public`.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor), después de 0114. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

-- =====================================================================
-- Paso 1 — calcular_factor_k_subitem: gate + redondeo de vuelta
-- =====================================================================

create or replace function calcular_factor_k_subitem(
  p_obra_id uuid,
  p_subitem_id uuid,
  p_config_congelada boolean default false
)
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
  with autorizado as (
    -- SECURITY DEFINER bypassa la RLS de obra_presupuesto_config/obra_impuestos/
    -- presupuesto_config_congelado, así que el chequeo de membresía se repite acá a mano (0085,
    -- perdido en la 0110 y devuelto en la 0115).
    select is_obra_member(p_obra_id) as ok
  ),
  detalle as (
    -- Composición y precios de insumos SIEMPRE de hoy, con o sin config congelada -- lo que varía
    -- entre las dos ramas es únicamente qué porcentajes se aplican sobre ese costo, nunca el costo
    -- en sí. Es justamente lo que hace que "hoy con config congelada" mida solo el desfasaje de
    -- precios, no un desfasaje de configuración.
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
  -- Config: vigente (obra_presupuesto_config) o congelada (presupuesto_config_congelado) según el
  -- parámetro -- los predicados son mutuamente excluyentes, así que esta CTE da siempre 1 fila,
  -- igual que antes de este cambio.
  config as (
    select gg_pct, imprevistos_pct, epp_pct, costo_financiero_pct, beneficio_pct,
           gestion_materiales_terceros_pct
    from obra_presupuesto_config c
    cross join autorizado a
    where c.obra_id = p_obra_id and not p_config_congelada and a.ok
    union all
    select gg_pct, imprevistos_pct, epp_pct, costo_financiero_pct, beneficio_pct,
           gestion_materiales_terceros_pct
    from presupuesto_config_congelado c
    cross join autorizado a
    where c.obra_id = p_obra_id and p_config_congelada and a.ok
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
    select cm_beneficio.*,
      costo_costo
        * (1 + gg_pct / 100) * (1 + imprevistos_pct / 100) * (1 + epp_pct / 100)
        * (1 + costo_financiero_pct / 100) * (1 + beneficio_pct / 100)
        as costo_total_trabajo_cm
    from cm_beneficio
  ),
  -- === Sin materiales ============================================================================
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
  -- === Impuestos: planos, los 4 sobre la misma base cada uno =====================================
  --
  -- Rama congelada: una sola fila sintética con `impuestos_pct_total` (ya sumado, 0104) en vez de
  -- las filas reales de `obra_impuestos` -- ambigüedad A del diseño original (0104 §10) dejó el
  -- desglose por tipo afuera del snapshot, así que no hay de dónde reconstruir IVA/IIBB/Tasas por
  -- separado. La fórmula de abajo (`impuestos_totales`) es la MISMA sin importar la rama -- solo
  -- cambian las filas de entrada, nunca la cuenta.
  impuestos as (
    select oi.tipo, oi.nombre_otro, oi.porcentaje, oi.orden,
      sm.costo_total_trabajo_cm, sm.costo_total_trabajo_sm
    from obra_impuestos oi
    cross join sm
    cross join autorizado a
    where oi.obra_id = p_obra_id and not p_config_congelada and a.ok
    union all
    select 'congelado'::text, null::text, pcc.impuestos_pct_total, 1,
      sm.costo_total_trabajo_cm, sm.costo_total_trabajo_sm
    from presupuesto_config_congelado pcc
    cross join sm
    cross join autorizado a
    where pcc.obra_id = p_obra_id and p_config_congelada and a.ok
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
    -- Chequeo de cierre sobre valores SIN redondear -- ver comentario de cabecera de 0078.
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
  -- === Salida: una fila por línea -- montos redondeados a 2 decimales SOLO acá (0078) ======
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
  where oi.obra_id = p_obra_id and not p_config_congelada
  union all
  select 'con_materiales', 6, 'Impuestos (congelados)', pcc.impuestos_pct_total,
    'Costo Total del Trabajo', round(c.costo_total_trabajo_cm, 2),
    round(pcc.impuestos_pct_total * c.costo_total_trabajo_cm / 100, 2),
    round(c.costo_costo, 2), round(c.costo_total_trabajo_cm, 2), round(c.precio_final_cm, 2),
    c.insumos_con_precio, c.insumos_total, c.cierra_ok_cm
  from cierre c
  cross join presupuesto_config_congelado pcc
  where pcc.obra_id = p_obra_id and p_config_congelada
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
  where oi.obra_id = p_obra_id and not p_config_congelada
  union all
  select 'sin_materiales', 7, 'Impuestos (congelados)', pcc.impuestos_pct_total,
    'Costo Total del Trabajo', round(c.costo_total_trabajo_sm, 2),
    round(pcc.impuestos_pct_total * c.costo_total_trabajo_sm / 100, 2),
    round(c.costo_costo_sm, 2), round(c.costo_total_trabajo_sm, 2), round(c.precio_final_sm, 2),
    c.insumos_con_precio, c.insumos_total, c.cierra_ok_sm
  from cierre c
  cross join presupuesto_config_congelado pcc
  where pcc.obra_id = p_obra_id and p_config_congelada
  order by 1, 2;
$$;

grant execute on function calcular_factor_k_subitem(uuid, uuid, boolean) to authenticated;
revoke execute on function calcular_factor_k_subitem(uuid, uuid, boolean) from public, anon;

-- =====================================================================
-- Paso 2 — search_path fijado en las tres SECURITY INVOKER que lo perdieron o nunca lo tuvieron
-- =====================================================================

alter function calcular_totales_certificado(uuid) set search_path = public;
alter function calcular_monto_periodo_avance() set search_path = public;
alter function calcular_monto_total_adicional() set search_path = public;

-- =====================================================================
-- Verificación
-- =====================================================================
--
-- 1) Sin membresía -- el SQL Editor corre sin auth.uid(), así que sirve de "no miembro" (ver 0078):
--    ANTES de aplicar esta migración, esto devuelve las 12-13 filas con los % reales de la obra
--    (y costo 0); DESPUÉS tiene que devolver 0 filas. Probar también con `true` en el tercer
--    argumento sobre una obra congelada -- mismo resultado, 0 filas.
-- select * from calcular_factor_k_subitem(
--   '<obra_id>'::uuid,
--   (select id from subitems where codigo = '8.1' and creador_usuario_id is null)
-- );
--
-- 2) anon ya no puede ejecutarla:
-- select has_function_privilege('anon', 'calcular_factor_k_subitem(uuid,uuid,boolean)', 'EXECUTE');
-- -- tiene que dar false. Y la consulta general de la 0085 (verificación 4) -- todas las SECURITY
-- -- DEFINER con anon_puede = false, salvo previsualizar_invitacion (a propósito):
-- select p.proname, has_function_privilege('anon', p.oid, 'EXECUTE') as anon_puede
-- from pg_proc p join pg_namespace n on n.oid = p.pronamespace
-- where n.nspname = 'public' and p.prosecdef = true
-- order by anon_puede desc, p.proname;
--
-- 3) search_path:
-- select proname, proconfig from pg_proc
-- where proname in ('calcular_factor_k_subitem', 'calcular_totales_certificado',
--                   'calcular_monto_periodo_avance', 'calcular_monto_total_adicional');
-- -- las cuatro con {search_path=public}.
--
-- 4) En la app, logueado como miembro: el bloque Factor K de la Solapa APU muestra los mismos
--    números que antes (ahora redondeados a 2 decimales en la base, no solo en pantalla); el chip
--    Pactado/Hoy del dashboard de una obra congelada sigue dando el mismo desfasaje; crear un
--    adicional de monto fijo y emitir/previsualizar un certificado siguen funcionando igual.
