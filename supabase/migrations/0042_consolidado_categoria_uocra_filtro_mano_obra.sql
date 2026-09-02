-- Costo de mano de obra — Paso 4.1: el lapicito de mano de obra escribe en
-- obra_valor_hora_override (por categoría), no en obra_insumo_precios (por insumo suelto). Ver
-- docs/costo_mano_de_obra_decisiones.md §13 para el motivo completo: el override es la tabla
-- construida específicamente para esto (0036) y quedaba tapada por el mecanismo genérico, que
-- además podía dejar AYUDANTE y AYUDA DE GREMIO — misma categoría, mismo valor hora por diseño —
-- con dos números distintos.
--
-- Tres cambios:
--
-- 1. consolidado_insumos_obra agrega categoria_uocra al RETURNS TABLE — Dart lo necesita para
--    saber en qué categoría escribir el override al tocar el lápiz de un insumo de mano de obra.
--    Cambia la firma de retorno, así que hace falta DROP + CREATE (igual que 0032).
-- 2. obra_insumo_precios deja de aplicar a insumos de tipo mano_obra, con un filtro en el propio
--    JOIN — no alcanza con que la UI deje de escribir ahí: nada a nivel de base impedía (ni
--    impide) una fila de obra_insumo_precios para un insumo de mano de obra por otra vía (SQL
--    directo, una fila vieja sin limpiar). El filtro cierra el loophole donde se lee, no solo
--    donde se escribe — a partir de acá, para mano de obra el COALESCE es efectivamente solo
--    vh.valor_hora (p.promedio de corralones ya daba NULL siempre, ver 0034).
-- 3. Constraint nueva en insumos: un insumo de tipo mano_obra siempre tiene categoria_uocra. Sin
--    esto, un insumo de mano de obra sin categoría (estado hoy imposible en la práctica — nada en
--    Dart escribe la tabla insumos todavía, grep sin resultados — pero no bloqueado a nivel de
--    base) haría que el diálogo de edición no tuviera dónde escribir el override, y sin un guard
--    explícito en Dart caería silenciosamente en obra_insumo_precios, que este mismo commit deja
--    de leer para mano de obra: el usuario guardaría, no vería error, y el número no cambiaría
--    nunca. No identifiqué ningún caso legítimo de un insumo mano_obra sin categoría — conceptualmente
--    todo insumo de mano de obra representa una categoría UOCRA real, es la razón de ser de la
--    columna. Si en algún momento hace falta un insumo de mano de obra fuera de las 5 categorías
--    del convenio, esta constraint tiene que revisarse primero, no ignorarse.
--    Postgres valida esta constraint contra las filas existentes al agregarla — si algún insumo de
--    mano de obra no tuviera categoría hoy, este ALTER TABLE falla solo, con el nombre de la
--    constraint en el error. No hace falta una consulta de verificación aparte.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

alter table insumos
  add constraint insumos_mano_obra_requiere_categoria check (
    tipo != 'mano_obra' or categoria_uocra is not null
  );

drop function consolidado_insumos_obra(uuid);

create function consolidado_insumos_obra(p_obra_id uuid)
returns table(
  insumo_id uuid,
  nombre text,
  unidad text,
  tipo text,
  categoria_uocra text,
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
  ),
  valor_hora_mo as (
    -- Una sola llamada — 5 filas, una por categoría UOCRA — no una vez por insumo. p_fecha en su
    -- default (current_date), ver 0041.
    select * from calcular_valor_hora_mano_obra(p_obra_id)
  )
  select
    ins.id as insumo_id,
    ins.nombre,
    ins.unidad,
    ins.tipo,
    ins.categoria_uocra,
    sum(i.cantidad_item) as cantidad_total,
    coalesce(oip.precio, vh.valor_hora, p.promedio) as precio,
    (coalesce(oip.precio, vh.valor_hora, p.promedio) is not null) as tiene_precio,
    coalesce(oip.origen, vh.origen, 'automatico') as origen
  from items i
  join insumos ins on ins.id = i.insumo_id
  left join lateral (
    select avg(valor) as promedio from precios pr where pr.insumo_id = i.insumo_id
  ) p on true
  left join obra_insumo_precios oip
    on oip.obra_id = p_obra_id and oip.insumo_id = ins.id and ins.tipo != 'mano_obra'
  left join valor_hora_mo vh on vh.categoria_uocra = ins.categoria_uocra
  group by ins.id, ins.nombre, ins.unidad, ins.tipo, ins.categoria_uocra, p.promedio, oip.id, oip.precio, oip.origen, vh.valor_hora, vh.origen
  order by ins.nombre;
$$;

grant execute on function consolidado_insumos_obra(uuid) to authenticated;
