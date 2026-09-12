-- Corrige el chip "Pactado / Hoy / Desfasaje" del dashboard (agregado en la tanda anterior, sin
-- aplicar todavía): comparaba el pactado (congelado con la configuración de Factor K vigente AL
-- MOMENTO DE CONGELAR) contra `calcular_presupuesto_vivo_obra`, que recalcula con la configuración
-- VIGENTE HOY (`obra_presupuesto_config`/`obra_impuestos`, los interruptores de la Solapa APU).
-- Caso real que lo destapó (Seba, 2026-09-12): obra con impuestos aplicados al congelar (IVA 21 +
-- Ingresos Brutos 3 + Tasas 1,5 = 25,5%) y el interruptor de impuestos apagado hoy -- el chip
-- mostraba un desfasaje de 20,3% que no existía: eran dos configuraciones distintas, no dos
-- momentos distintos del mismo costo. El desfasaje real (costo de insumos) quedaba escondido
-- detrás de esa diferencia de configuración.
--
-- Corrección: "Hoy" tiene que calcularse con la MISMA configuración con la que se congeló --
-- Factor K completo (gg/imprevistos/epp/costo_financiero/beneficio/gestión materiales terceros +
-- impuestos) y la misma vista (con/sin materiales) -- variando únicamente el precio de los
-- insumos, que es lo único que un desfasaje de "cuánto se corrió el costo" tiene que medir.
-- `presupuesto_config_congelado` (0104) ya guarda esos 6 % + el total de impuestos, así que el
-- dato existe -- no hace falta ninguna tabla nueva.
--
-- DECISIÓN DE DISEÑO (repitiendo el criterio de 0090, comentario de cabecera): no se duplica la
-- cascada de Factor K en una función nueva. `calcular_factor_k_subitem` (0077/0078/0085) gana un
-- parámetro `p_config_congelada boolean default false` -- con el default, se comporta EXACTO igual
-- que hoy (todos los call sites existentes, `calcular_precio_final_apu_subitems` incluida, no
-- necesitan tocarse); con `true`, lee `presupuesto_config_congelado` en vez de
-- `obra_presupuesto_config`/`obra_impuestos`. `drop` + `create` (no `create or replace`) porque
-- cambia la firma -- mismo patrón que 0090 con `calcular_precio_apu_subitems`.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor), después de 0109. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

drop function calcular_factor_k_subitem(uuid, uuid);

create function calcular_factor_k_subitem(
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
  with detalle as (
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
    where c.obra_id = p_obra_id and not p_config_congelada
    union all
    select gg_pct, imprevistos_pct, epp_pct, costo_financiero_pct, beneficio_pct,
           gestion_materiales_terceros_pct
    from presupuesto_config_congelado c
    where c.obra_id = p_obra_id and p_config_congelada
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
    where oi.obra_id = p_obra_id and not p_config_congelada
    union all
    select 'congelado'::text, null::text, pcc.impuestos_pct_total, 1,
      sm.costo_total_trabajo_cm, sm.costo_total_trabajo_sm
    from presupuesto_config_congelado pcc
    cross join sm
    where pcc.obra_id = p_obra_id and p_config_congelada
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
  where oi.obra_id = p_obra_id and not p_config_congelada
  union all
  select 'con_materiales', 6, 'Impuestos (congelados)', pcc.impuestos_pct_total,
    'Costo Total del Trabajo', c.costo_total_trabajo_cm, pcc.impuestos_pct_total * c.costo_total_trabajo_cm / 100,
    c.costo_costo, c.costo_total_trabajo_cm, c.precio_final_cm, c.insumos_con_precio, c.insumos_total, c.cierra_ok_cm
  from cierre c
  cross join presupuesto_config_congelado pcc
  where pcc.obra_id = p_obra_id and p_config_congelada
  union all
  select 'sin_materiales', 1, 'Gastos Generales', gg_pct,
    'Costo-Costo', costo_costo, gg_monto,
    costo_costo_sm, costo_total_trabajo_sm, precio_final_sm, insumos_con_precio, insumos_total, cierra_ok_sm
  from cierre
  union all
  select 'sin_materiales', 2, 'Imprevistos', imprevistos_pct,
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
  where oi.obra_id = p_obra_id and not p_config_congelada
  union all
  select 'sin_materiales', 7, 'Impuestos (congelados)', pcc.impuestos_pct_total,
    'Costo Total del Trabajo', c.costo_total_trabajo_sm, pcc.impuestos_pct_total * c.costo_total_trabajo_sm / 100,
    c.costo_costo_sm, c.costo_total_trabajo_sm, c.precio_final_sm, c.insumos_con_precio, c.insumos_total, c.cierra_ok_sm
  from cierre c
  cross join presupuesto_config_congelado pcc
  where pcc.obra_id = p_obra_id and p_config_congelada
  order by 1, 2;
$$;

grant execute on function calcular_factor_k_subitem(uuid, uuid, boolean) to authenticated;

-- =====================================================================
-- calcular_presupuesto_hoy_config_congelada_obra -- el número "Hoy" que de verdad compara
-- igual-contra-igual
-- =====================================================================
--
-- Mismas partidas y cantidades que se congelaron (`presupuesto_subitems_congelado`, no
-- `obra_subitems` en vivo) -- el desfasaje mide únicamente el costo de insumos de hoy contra el
-- pactado, nunca un cambio de alcance (metros de más/menos son quitas/demasías,
-- `docs/adicionales_quitas_demasias_diagnostico.md`, un concepto aparte que no corresponde mezclar
-- acá). Rubros de precio manual: no tienen cascada de Factor K que congelar (0104), así que su
-- aporte a "hoy" es el mismo `precio_unitario_manual` de siempre, igual que en
-- `calcular_presupuesto_vivo_obra` -- no hay nada que journal congelado del que leer para esa rama.
create or replace function calcular_presupuesto_hoy_config_congelada_obra(p_obra_id uuid)
returns numeric
language sql security definer set search_path = public stable as $$
  with autorizado as (
    select is_obra_member(p_obra_id) as ok
  ),
  vista_congelada as (
    select case when tipo_presupuesto = 'mano_obra_sola' then 'sin_materiales' else 'con_materiales' end as vista
    from presupuesto_config_congelado
    where obra_id = p_obra_id
  ),
  base as (
    select psc.cantidad, os.subitem_id, os.precio_unitario_manual, r.usa_apu, r.tipo_precio_manual
    from presupuesto_subitems_congelado psc
    join obra_subitems os on os.id = psc.obra_subitem_id
    join rubros r on r.id = os.rubro_id
    cross join autorizado a
    where psc.obra_id = p_obra_id and a.ok
  ),
  manual as (
    select
      case tipo_precio_manual
        when 'global' then coalesce(precio_unitario_manual, 0)
        else cantidad * coalesce(precio_unitario_manual, 0)
      end as monto
    from base
    where usa_apu = false
  ),
  apu as (
    select b.cantidad * f.precio_final as monto
    from base b
    cross join lateral calcular_factor_k_subitem(p_obra_id, b.subitem_id, true) as f
    cross join vista_congelada v
    where b.usa_apu = true and f.vista = v.vista and f.orden = 1
  )
  select coalesce(sum(monto), 0)
  from (select monto from manual union all select monto from apu) t;
$$;

grant execute on function calcular_presupuesto_hoy_config_congelada_obra(uuid) to authenticated;
revoke execute on function calcular_presupuesto_hoy_config_congelada_obra(uuid) from public, anon;

-- =====================================================================
-- Verificación
-- =====================================================================
--
-- 1) Obra congelada CON impuestos/config activa al momento de congelar, e interruptor de
--    impuestos (u otro % de Factor K) cambiado DESPUÉS de congelar: `calcular_factor_k_subitem`
--    con `p_config_congelada = true` sigue dando el precio_final de ANTES del cambio (usa
--    presupuesto_config_congelado, no obra_presupuesto_config/obra_impuestos vigentes).
-- 2) Misma obra, sin cambiar ningún precio de insumo desde que se congeló:
--    `calcular_presupuesto_hoy_config_congelada_obra` tiene que dar EXACTO el mismo número que
--    `getMontoPactadoCongelado` (suma de presupuesto_subitems_congelado.monto_total) -- nada
--    cambió (ni insumos ni config), así que "hoy con la config de entonces" tiene que coincidir con
--    "lo pactado".
-- 3) Misma obra, después de subir el precio de un insumo que participa en alguna partida
--    congelada: el número de (2) ahora es mayor que el pactado, y el desfasaje que muestre el
--    dashboard tiene que atribuirse enteramente a ese cambio de precio -- no a los interruptores de
--    la Solapa APU, que no participan en este cálculo.
-- 4) Todos los call sites existentes de calcular_factor_k_subitem con 2 argumentos (
--    calcular_precio_final_apu_subitems, congelar_presupuesto_obra) siguen dando exactamente los
--    mismos resultados que antes de esta migración -- p_config_congelada default false, sin
--    ningún cambio de comportamiento para el camino en vivo.
-- 5) anon/authenticated sin membresía: 0 en calcular_presupuesto_hoy_config_congelada_obra, mismo
--    criterio que el resto de las funciones de este patrón.
