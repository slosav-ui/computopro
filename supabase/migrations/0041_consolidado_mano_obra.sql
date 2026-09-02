-- Costo de mano de obra — Paso 4: conecta calcular_valor_hora_mano_obra (0039) al consolidado de
-- Mat y MO. Los 5 insumos de mano de obra dejan de mostrar "Falta cargar precio" en cuanto tienen
-- composición real cargada — el valor sale de la escala UOCRA en vez de depender de una carga
-- manual. Ver docs/costo_mano_de_obra_decisiones.md §12 para el diseño completo (precedencia,
-- mapeo exhaustivo de origen, por qué la excepción de zona faltante propaga a todo el consolidado
-- a propósito).
--
-- No hace falta rama propia para mano de obra: para materiales, valor_hora_mo nunca matchea
-- (categoria_uocra es NULL) y el COALESCE cae en el promedio de corralones de siempre; para mano
-- de obra, el promedio de corralones siempre da NULL (ver 0034) y el COALESCE cae en el valor hora
-- calculado. Mismo COALESCE, sin CASE por tipo de insumo.
--
-- Firma de retorno idéntica a 0032 — CREATE OR REPLACE alcanza, no hace falta DROP.
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
    -- Misma selección "propia si existe, si no oficial" que calcular_precio_apu_subitems (0034).
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
    -- default (current_date): el consolidado es una vista viva mientras se arma el presupuesto, no
    -- congelada — mismo criterio que el resto de Mat y MO hoy (ninguna otra fuente de precio
    -- congela nada). Cuando se diseñe el congelamiento al presentar presupuesto, se resuelve para
    -- todos los orígenes a la vez, no solo para mano de obra — ver
    -- docs/costo_mano_de_obra_decisiones.md §12 y la memoria "precio_congelado_vs_recalculado".
    --
    -- Si escala_salarial_uocra no tiene fila para la zona_uocra/fecha de esta obra,
    -- calcular_valor_hora_mano_obra hace RAISE EXCEPTION (0039) — eso frena TODO este consolidado,
    -- incluidas las filas de materiales que no tienen nada que ver con UOCRA. Es a propósito, no un
    -- descuido: lo que la vuelve inalcanzable en uso normal es que el control de zona del Paso 5 va
    -- a restringir a valores que sí existen en la escala, no un catch acá. Ver
    -- docs/costo_mano_de_obra_decisiones.md §12.
    select * from calcular_valor_hora_mano_obra(p_obra_id)
  )
  select
    ins.id as insumo_id,
    ins.nombre,
    ins.unidad,
    ins.tipo,
    sum(i.cantidad_item) as cantidad_total,
    coalesce(oip.precio, vh.valor_hora, p.promedio) as precio,
    (coalesce(oip.precio, vh.valor_hora, p.promedio) is not null) as tiene_precio,
    coalesce(oip.origen, vh.origen, 'automatico') as origen
  from items i
  join insumos ins on ins.id = i.insumo_id
  left join lateral (
    select avg(valor) as promedio from precios pr where pr.insumo_id = i.insumo_id
  ) p on true
  left join obra_insumo_precios oip on oip.obra_id = p_obra_id and oip.insumo_id = ins.id
  left join valor_hora_mo vh on vh.categoria_uocra = ins.categoria_uocra
  group by ins.id, ins.nombre, ins.unidad, ins.tipo, p.promedio, oip.id, oip.precio, oip.origen, vh.valor_hora, vh.origen
  order by ins.nombre;
$$;

grant execute on function consolidado_insumos_obra(uuid) to authenticated;

-- Gap encontrado al escribir este paso: 0039 (calcular_valor_hora_mano_obra) no tenía GRANT EXECUTE
-- explícito — las otras 20 funciones SECURITY DEFINER/públicas del proyecto sí lo tienen, sin
-- excepción. Postgres otorga EXECUTE a PUBLIC por default en funciones nuevas, así que no rompió
-- nada en la práctica (de ahí que la prueba desde el SQL Editor funcionara), pero rompía la
-- convención 100% consistente del resto del historial de migraciones. Se corrige acá, no
-- reeditando 0039 (ya aplicada).
grant execute on function calcular_valor_hora_mano_obra(uuid, date) to authenticated;
