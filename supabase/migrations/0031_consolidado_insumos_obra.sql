-- Mat y MO — paso 2: consolidado real de insumos de una obra, solo lectura, para reemplazar el
-- mock de presupuestos_screen.dart._buildTabMaterialesYMo(). Ver memoria de diseño
-- "mat_y_mo_fuentes_precio" para el plan completo de 4 pasos.
--
-- Primera vez que se lee de verdad qué insumos consume una obra según las composiciones de APU
-- tildadas — no existía ningún query así hasta ahora (el paso 3 de la vinculación con APU,
-- 0029_calcular_precio_apu_subitem.sql, calcula un precio por subítem, no un consolidado por
-- insumo agregado en toda la obra).
--
-- Precio: automático únicamente (avg(precios.valor), mismo criterio que
-- calcular_precio_promedio_insumo() de 0013_rls_proveedores_precios.sql, inline acá por el mismo
-- motivo que 0029 documentó — evitar N llamadas a función dentro del join). `obra_insumo_precios`
-- (0030, precio editado/en firme por obra) todavía no se lee acá a propósito — ese es el paso 3,
-- sin construir. Con casi ningún insumo con precio real cargado hoy, la lista va a mostrar
-- "sin precio" para casi todo — por diseño **nunca colapsa a 0**, mismo criterio que el resto de
-- esta pieza (ApuPrecioSubitem, 0029): `tiene_precio` es explícito, `precio_promedio` queda NULL
-- en vez de 0 cuando no hay ninguna fila en `precios` para ese insumo.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

create or replace function consolidado_insumos_obra(p_obra_id uuid)
returns table(
  insumo_id uuid,
  nombre text,
  unidad text,
  tipo text,
  cantidad_total numeric,
  precio_promedio numeric,
  tiene_precio boolean
)
language sql security definer set search_path = public stable as $$
  with autorizado as (
    -- SECURITY DEFINER bypassa la RLS de obra_subitems, así que el chequeo de membresía se repite
    -- acá a mano — mismo motivo que apu_composiciones/tiene_apu_ajena_visible_por_subitem en 0019.
    -- Si el usuario no es miembro de la obra, subitems_obra queda vacía y no filtra ningún error,
    -- solo devuelve una lista vacía (fail-closed silencioso, mismo patrón que el resto).
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
    -- Misma selección "propia si existe, si no oficial" que calcular_precio_apu_subitems (0029) —
    -- un subítem propio (nunca tiene composición) simplemente no aporta filas acá, sin necesitar
    -- un caso aparte.
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
    p.promedio as precio_promedio,
    (p.promedio is not null) as tiene_precio
  from items i
  join insumos ins on ins.id = i.insumo_id
  left join lateral (
    select avg(valor) as promedio from precios pr where pr.insumo_id = i.insumo_id
  ) p on true
  group by ins.id, ins.nombre, ins.unidad, ins.tipo, p.promedio
  order by ins.nombre;
$$;

grant execute on function consolidado_insumos_obra(uuid) to authenticated;
