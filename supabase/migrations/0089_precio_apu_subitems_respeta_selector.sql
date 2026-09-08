-- Bug urgente reportado por Seba: el selector "Comp. Mat y MO" / "Comp. Solo MO"
-- (obra_presupuesto_config.tipo_presupuesto, ver SelectorTipoPresupuesto en la Solapa APU) no
-- afectaba el precio que se ve en la lista de subítems de la solapa Cómputo -- siempre mostraba
-- la vista completa (con materiales), sin importar el selector.
--
-- CAUSA RAÍZ: el precio de la lista de Cómputo sale de `calcular_precio_apu_subitems`
-- (0059_calcular_precio_apu_subitems_mano_obra.sql), que nunca tuvo el concepto de vista
-- con/sin materiales -- suma rendimiento × precio_unitario de TODOS los componentes de la
-- composición (mano de obra + material + equipo) en un solo número, siempre. El Bloque de Factor
-- K de una partida (calcular_factor_k_subitem, vía calcular_composicion_detalle_subitem) sí separa
-- las dos vistas -- son funciones distintas, y solo una de las dos se actualizó cuando se construyó
-- el selector.
--
-- FIX: se agregan 3 columnas a la salida de `calcular_precio_apu_subitems` con la vista "sin
-- materiales" (mano de obra + equipo, excluyendo tipo_componente = 'material') -- mismo criterio
-- de exclusión que ya usa calcular_factor_k_subitem para materiales_subtotal/costo_costo_sm. Una
-- sola función, una sola llamada por pantalla (igual que antes) -- el cliente (SubitemsScreen) elige
-- qué columnas leer según el tipo_presupuesto de la obra, sin pedir nada dos veces.
--
-- RETURNS TABLE cambia (se agregan columnas) -- hace falta DROP + CREATE, no alcanza con REPLACE.
-- Al recrearla se pierden el GRANT y el REVOKE que tenía (0059 y 0085 respectivamente) -- se
-- reaplican los dos acá, mismos roles que antes.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado automáticamente
-- por Claude Code: sin acceso a la base de datos desde este entorno.

drop function calcular_precio_apu_subitems(uuid, uuid[]);

create function calcular_precio_apu_subitems(p_obra_id uuid, p_subitem_ids uuid[])
returns table(
  subitem_id uuid,
  precio_total numeric,
  insumos_con_precio int,
  insumos_total int,
  precio_total_sin_materiales numeric,
  insumos_con_precio_sin_materiales int,
  insumos_total_sin_materiales int
)
language sql security definer set search_path = public stable as $$
  with autorizado as (
    -- SECURITY DEFINER bypassa la RLS de obra_insumo_precios, así que el chequeo de membresía se
    -- repite acá a mano -- mismo motivo y mismo patrón que consolidado_insumos_obra (0031).
    select is_obra_member(p_obra_id) as ok
  ),
  composiciones as (
    -- Una composición por subítem: la propia del usuario si existe, si no la oficial.
    select distinct on (subitem_id) id as composicion_id, subitem_id
    from apu_composiciones
    cross join autorizado a
    where subitem_id = any(p_subitem_ids)
      and (creador_usuario_id = auth.uid() or creador_usuario_id is null)
      and a.ok
    order by subitem_id, creador_usuario_id nulls last
  ),
  valor_hora_mo as (
    -- Una sola llamada -- 5 filas, una por categoría UOCRA -- no una vez por insumo de mano de
    -- obra. p_fecha en su default (current_date), mismo criterio que 0041/0042: vista viva
    -- mientras se arma el presupuesto, no congelada.
    select * from calcular_valor_hora_mano_obra(p_obra_id)
  ),
  items_con_precio as (
    select
      c.subitem_id,
      -- tipo_componente de la línea (no ins.tipo del insumo) -- mismo campo que usa
      -- calcular_factor_k_subitem para separar materiales_subtotal del resto.
      aci.tipo_componente,
      aci.rendimiento,
      -- Precedencia: manual de esta obra (nunca para mano de obra, ver filtro) -> valor hora UOCRA
      -- (con el override del PRO ya resuelto adentro de calcular_valor_hora_mano_obra) -> promedio
      -- de corralones (siempre NULL para mano de obra, coalesce cae solo si algún día precios
      -- tuviera datos de un insumo que hoy no es mano_obra pero tampoco tiene manual ni escala).
      coalesce(
        (select oip.precio from obra_insumo_precios oip
         where oip.obra_id = p_obra_id and oip.insumo_id = aci.insumo_id and ins.tipo != 'mano_obra'),
        vh.valor_hora,
        (select avg(valor) from precios pr where pr.insumo_id = aci.insumo_id)
      ) as precio_unitario
    from apu_composicion_items aci
    join composiciones c on c.composicion_id = aci.apu_composicion_id
    join insumos ins on ins.id = aci.insumo_id
    left join valor_hora_mo vh on vh.categoria_uocra = ins.categoria_uocra
  )
  select
    subitem_id,
    coalesce(sum(rendimiento * precio_unitario) filter (where precio_unitario is not null), 0),
    count(*) filter (where precio_unitario is not null)::int,
    count(*)::int,
    coalesce(
      sum(rendimiento * precio_unitario)
        filter (where precio_unitario is not null and tipo_componente != 'material'),
      0
    ),
    count(*) filter (where precio_unitario is not null and tipo_componente != 'material')::int,
    count(*) filter (where tipo_componente != 'material')::int
  from items_con_precio
  group by subitem_id;
$$;

grant execute on function calcular_precio_apu_subitems(uuid, uuid[]) to authenticated;
revoke execute on function calcular_precio_apu_subitems(uuid, uuid[]) from public, anon;

-- =====================================================================
-- Verificación
-- =====================================================================

-- 1) Partida 8.1 (tiene materiales reales con precio, ver verificación de 0059): comparar las dos
--    vistas -- precio_total_sin_materiales tiene que ser MENOR a precio_total (se restan los
--    materiales), y la diferencia tiene que coincidir con la suma de rendimiento×precio de las
--    líneas 'material' de esa composición.
-- select * from calcular_precio_apu_subitems(
--   '<obra_id>'::uuid,
--   array[(select id from subitems where codigo = '8.1' and creador_usuario_id is null)]
-- );

-- 2) Con la obra en tipo_presupuesto = 'mano_obra_sola', la lista de Cómputo de esa obra (después
--    del fix de Dart en el mismo commit) tiene que mostrar precio_total_sin_materiales para cada
--    partida con composición, no precio_total.

-- 3) anon/authenticated sin membresía en la obra: 0 filas, igual que la función anterior (el
--    comportamiento de autorización no cambió, solo se agregaron columnas).
