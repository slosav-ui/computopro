-- Expone línea por línea lo que calcular_precio_apu_subitems (0034/0059) ya calcula y descarta al
-- sumar -- no es cálculo nuevo, es el mismo COALESCE por ítem, sin el group by/sum final. Hace
-- falta para la pantalla de composición de una partida (ver diagnóstico de esta pieza): mostrar
-- mano de obra / materiales / equipos con su rendimiento, precio unitario y subtotal, no solo el
-- total agregado que ya muestra SubitemsScreen.
--
-- Un solo subitem_id (no array, a diferencia de 0059) -- esta pantalla siempre muestra una partida
-- por vez, no tiene sentido pedir el detalle de varias juntas.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

create or replace function calcular_composicion_detalle_subitem(p_obra_id uuid, p_subitem_id uuid)
returns table(
  tipo_componente text,
  insumo_nombre text,
  insumo_unidad text,
  rendimiento numeric,
  precio_unitario numeric
)
language sql security definer set search_path = public stable as $$
  with autorizado as (
    -- SECURITY DEFINER bypassa la RLS de obra_insumo_precios, mismo motivo que 0034/0059.
    select is_obra_member(p_obra_id) as ok
  ),
  composicion as (
    -- Misma composición "propia si existe, si no oficial" que 0034/0059 -- un solo subitem_id, sin
    -- necesitar distinct on (un solo id de por sí).
    select id as composicion_id
    from apu_composiciones
    cross join autorizado a
    where subitem_id = p_subitem_id
      and (creador_usuario_id = auth.uid() or creador_usuario_id is null)
      and a.ok
    order by creador_usuario_id nulls last
    limit 1
  ),
  valor_hora_mo as (
    select * from calcular_valor_hora_mano_obra(p_obra_id)
  )
  select
    aci.tipo_componente,
    ins.nombre as insumo_nombre,
    ins.unidad as insumo_unidad,
    aci.rendimiento,
    -- Mismo COALESCE exacto que 0059, línea por línea en vez de sumado.
    coalesce(
      (select oip.precio from obra_insumo_precios oip
       where oip.obra_id = p_obra_id and oip.insumo_id = aci.insumo_id and ins.tipo != 'mano_obra'),
      vh.valor_hora,
      (select avg(valor) from precios pr where pr.insumo_id = aci.insumo_id)
    ) as precio_unitario
  from apu_composicion_items aci
  join composicion c on c.composicion_id = aci.apu_composicion_id
  join insumos ins on ins.id = aci.insumo_id
  left join valor_hora_mo vh on vh.categoria_uocra = ins.categoria_uocra
  order by
    case aci.tipo_componente when 'mano_obra' then 1 when 'material' then 2 else 3 end,
    ins.nombre;
$$;

grant execute on function calcular_composicion_detalle_subitem(uuid, uuid) to authenticated;

-- =====================================================================
-- Verificación
-- =====================================================================

-- 1) Partida 8.1: 6 filas (2 mano_obra, 4 material), las 6 con precio_unitario no nulo tras 0059.
--    Sumar rendimiento*precio_unitario tiene que dar lo mismo que precio_total de
--    calcular_precio_apu_subitems para el mismo subítem/obra.
-- select * from calcular_composicion_detalle_subitem(
--   '<obra_id>'::uuid,
--   (select id from subitems where codigo = '8.1' and creador_usuario_id is null)
-- );

-- 2) Una partida de Steel Frame (ej. 5.1) tiene que traer varias filas con precio_unitario null
--    (los tornillos que no matchean ninguna cotización real, ver diagnóstico) -- confirma que la
--    función no colapsa "sin precio" a 0.
