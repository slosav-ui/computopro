-- Mat y MO — paso 3: consolidado_insumos_obra pasa a leer obra_insumo_precios (0030), con
-- precedencia sobre el promedio automático de corralones. Ver memoria de diseño
-- "mat_y_mo_fuentes_precio" y docs de la conversación de paso 3.
--
-- CREATE OR REPLACE no alcanza acá: agregar una columna al RETURNS TABLE cambia la firma de
-- retorno, y Postgres no permite tocarla con CREATE OR REPLACE FUNCTION. Hace falta DROP + CREATE.
--
-- Rename precio_promedio -> precio: desde este paso el valor devuelto puede venir de una carga
-- manual, no de un promedio — el nombre viejo mentiría sobre el origen del dato apenas exista una
-- fila en obra_insumo_precios para ese (obra, insumo).
--
-- Precedencia: coalesce(oip.precio, promedio_automático). El guard que evita pisar silenciosamente
-- un origen='presupuesto_firme' con una edición manual (documentado en el comentario de 0030)
-- queda pendiente para el paso 4 — ese origen todavía no puede existir en ninguna fila (paso 4 sin
-- construir), así que escribir esa validación ahora sería código sin forma de dispararse ni
-- probarse.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

drop function consolidado_insumos_obra(uuid);

create function consolidado_insumos_obra(p_obra_id uuid)
returns table(
  insumo_id uuid,
  nombre text,
  unidad text,
  tipo text,
  cantidad_total numeric,
  precio numeric,
  tiene_precio boolean,
  origen text
)
language sql security definer set search_path = public stable as $$
  with autorizado as (
    -- SECURITY DEFINER bypassa la RLS de obra_subitems, así que el chequeo de membresía se repite
    -- acá a mano — mismo motivo que apu_composiciones/tiene_apu_ajena_visible_por_subitem en 0019.
    select is_obra_member(p_obra_id) as ok
  ),
  subitems_obra as (
    -- Solo subitems tildados (es_aplicable), en rubros con usa_apu = true — los rubros de precio
    -- manual (1/18/19/20/custom) no tienen composición, no aportan insumos acá.
    select os.subitem_id, os.cantidad
    from obra_subitems os
    join rubros r on r.id = os.rubro_id
    cross join autorizado a
    where os.obra_id = p_obra_id
      and os.es_aplicable = true
      and r.usa_apu = true
      and os.subitem_id is not null
      and a.ok
  ),
  composiciones as (
    -- Misma selección "propia si existe, si no oficial" que calcular_precio_apu_subitems (0029).
    select distinct on (subitem_id) id as composicion_id, subitem_id
    from apu_composiciones
    where subitem_id in (select subitem_id from subitems_obra)
      and (creador_usuario_id = auth.uid() or creador_usuario_id is null)
    order by subitem_id, creador_usuario_id nulls last
  ),
  items as (
    select
      aci.insumo_id,
      so.cantidad * aci.rendimiento as cantidad_item
    from apu_composicion_items aci
    join composiciones c on c.composicion_id = aci.apu_composicion_id
    join subitems_obra so on so.subitem_id = c.subitem_id
  )
  select
    ins.id as insumo_id,
    ins.nombre,
    ins.unidad,
    ins.tipo,
    sum(i.cantidad_item) as cantidad_total,
    coalesce(oip.precio, p.promedio) as precio,
    (coalesce(oip.precio, p.promedio) is not null) as tiene_precio,
    case when oip.id is not null then oip.origen else 'automatico' end as origen
  from items i
  join insumos ins on ins.id = i.insumo_id
  left join lateral (
    select avg(valor) as promedio from precios pr where pr.insumo_id = i.insumo_id
  ) p on true
  left join obra_insumo_precios oip on oip.obra_id = p_obra_id and oip.insumo_id = ins.id
  group by ins.id, ins.nombre, ins.unidad, ins.tipo, p.promedio, oip.id, oip.precio, oip.origen
  order by ins.nombre;
$$;

grant execute on function consolidado_insumos_obra(uuid) to authenticated;
