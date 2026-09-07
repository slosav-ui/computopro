-- Bug real, reportado por Seba con el error exacto de Postgres (buscando en consola con el
-- `debugPrint` agregado a PanelCrearEquipoApu): code=42702 "column reference apu_composicion_id is
-- ambiguous". Las 5 funciones de escritura de esta pieza (0072/0073/0074) declaran
-- `returns table(..., apu_composicion_id uuid, ..., insumo_id uuid, tipo_componente text, ...)` --
-- en PL/pgSQL, las columnas de un `RETURNS TABLE` quedan disponibles como variables de la función
-- (parámetros OUT), con el mismo nombre que las columnas reales de `apu_composicion_items`. Un
-- `where apu_composicion_id = ...` sin calificar, adentro de una consulta que tiene
-- `apu_composicion_items` en el FROM, es ambiguo: Postgres no sabe si es la variable de salida o la
-- columna de la tabla, y con `plpgsql.variable_conflict = error` (el default) corta con 42702.
--
-- Encontrado en 5 funciones, las 5 con el mismo patrón (`if exists (select 1 from
-- apu_composicion_items where apu_composicion_id = ... and insumo_id = ...)` o el `delete`/`update`
-- equivalente) -- revisadas una por una, no solo la que reportó el error:
--   - personalizar_item_apu (0072): 2 lugares (el `not exists` del insert, el `where` del update).
--   - agregar_material_apu (0072): 1 lugar -- nunca se había notado porque coincidencia: nadie
--     probó agregar un material que todavía no estuviera en la receta personal con este código
--     exacto en un caso que lo ejercite limpio, o el error quedó silenciado detrás del mensaje
--     genérico igual que con equipo. De cualquier forma, el código tenía el mismo defecto.
--   - quitar_material_apu (0072): 1 lugar, y ahí son 3 columnas ambiguas a la vez
--     (apu_composicion_id, insumo_id, tipo_componente -- las 3 son columnas de salida Y columnas
--     reales de la tabla).
--   - agregar_equipo_apu (0074, la versión vigente): 1 lugar -- la que reportó el error real.
--   - quitar_equipo_apu (0073, sigue vigente, 0074 no la tocó): 1 lugar, mismas 3 columnas que
--     quitar_material_apu.
--
-- `insumo_id` y `tipo_componente` no salieron en el mensaje de error porque Postgres corta el
-- parseo de la sentencia en la primera columna ambigua que encuentra (`apu_composicion_id`, por ser
-- la primera en el `where`) -- sin este arreglo, corregir solo esa hubiera hecho aparecer el mismo
-- error en la siguiente columna ambigua de la misma línea.
--
-- Arreglo: calificar cada columna ambigua con el nombre de la tabla
-- (`apu_composicion_items.columna`) en vez de renombrar la variable de salida -- renombrarla
-- cambiaría el nombre de columna que devuelve la función, y `ApuComposicionesRepository` en Dart
-- mapea las filas por ese nombre (`row['apu_composicion_id']`). Los `insert`/`update` con lista de
-- columnas destino (`insert into t (col, ...)`, `update t set col = ...`) NO tienen este problema --
-- esa lista se resuelve contra las columnas de la tabla siempre, nunca contra variables de
-- PL/pgSQL, así que quedan sin tocar.
--
-- `create or replace function` alcanza en las 5 -- ninguna cambia de firma acá, solo el cuerpo.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor), después de 0074. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

create or replace function personalizar_item_apu(
  p_obra_id uuid,
  p_subitem_id uuid,
  p_insumo_id uuid,
  p_rendimiento_nuevo numeric,
  p_precio_nuevo numeric default null
)
returns table(
  item_id uuid,
  apu_composicion_id uuid,
  es_personal boolean,
  tipo_componente text,
  insumo_id uuid,
  insumo_nombre text,
  insumo_unidad text,
  rendimiento numeric,
  precio_unitario numeric
)
language plpgsql security invoker set search_path = public as $$
declare
  v_tipo text;
  v_categoria_uocra text;
  v_composicion_personal_id uuid;
  v_rendimiento_actual numeric;
begin
  if p_rendimiento_nuevo < 0 then
    raise exception 'El rendimiento no puede ser negativo';
  end if;
  if p_precio_nuevo is not null and p_precio_nuevo < 0 then
    raise exception 'El precio no puede ser negativo';
  end if;

  select tipo, categoria_uocra into v_tipo, v_categoria_uocra from insumos where id = p_insumo_id;
  if v_tipo is null then
    raise exception 'No se encontró el insumo %, o no está visible para este usuario', p_insumo_id;
  end if;

  select aci.rendimiento into v_rendimiento_actual
  from apu_composicion_items aci
  join apu_composiciones ac on ac.id = aci.apu_composicion_id
  where ac.subitem_id = p_subitem_id
    and (ac.creador_usuario_id = auth.uid() or ac.creador_usuario_id is null)
    and aci.insumo_id = p_insumo_id
  order by ac.creador_usuario_id nulls last
  limit 1;
  v_rendimiento_actual := coalesce(v_rendimiento_actual, 0);

  if p_rendimiento_nuevo <> v_rendimiento_actual then
    v_composicion_personal_id := clonar_receta_personal_apu(p_subitem_id);

    insert into apu_composicion_items (apu_composicion_id, tipo_componente, insumo_id, rendimiento)
    select v_composicion_personal_id, v_tipo, p_insumo_id, 0
    where not exists (
      select 1 from apu_composicion_items
      where apu_composicion_items.apu_composicion_id = v_composicion_personal_id
        and apu_composicion_items.insumo_id = p_insumo_id
    );

    update apu_composicion_items
    set rendimiento = p_rendimiento_nuevo
    where apu_composicion_items.apu_composicion_id = v_composicion_personal_id
      and apu_composicion_items.insumo_id = p_insumo_id;
  end if;

  if p_precio_nuevo is not null then
    if v_tipo = 'mano_obra' then
      if v_categoria_uocra is null then
        raise exception 'Este insumo de mano de obra no tiene categoría UOCRA asignada -- no se puede editar el precio';
      end if;
      insert into obra_valor_hora_override (obra_id, categoria_uocra, valor_hora, usuario_id)
      values (p_obra_id, v_categoria_uocra, p_precio_nuevo, auth.uid())
      on conflict (obra_id, categoria_uocra)
      do update set valor_hora = excluded.valor_hora, usuario_id = excluded.usuario_id;
    else
      insert into obra_insumo_precios (obra_id, insumo_id, precio, origen, usuario_id)
      values (p_obra_id, p_insumo_id, p_precio_nuevo, 'manual', auth.uid())
      on conflict (obra_id, insumo_id)
      do update set precio = excluded.precio, origen = 'manual', corralon_id = null, usuario_id = excluded.usuario_id;
    end if;
  end if;

  return query
    select * from calcular_composicion_detalle_subitem(p_obra_id, p_subitem_id);
end;
$$;

create or replace function agregar_material_apu(
  p_obra_id uuid,
  p_subitem_id uuid,
  p_insumo_id uuid,
  p_rendimiento numeric
)
returns table(
  item_id uuid,
  apu_composicion_id uuid,
  es_personal boolean,
  tipo_componente text,
  insumo_id uuid,
  insumo_nombre text,
  insumo_unidad text,
  rendimiento numeric,
  precio_unitario numeric
)
language plpgsql security invoker set search_path = public as $$
declare
  v_tipo text;
  v_composicion_personal_id uuid;
begin
  if p_rendimiento < 0 then
    raise exception 'El rendimiento no puede ser negativo';
  end if;

  select tipo into v_tipo from insumos where id = p_insumo_id;
  if v_tipo is null then
    raise exception 'No se encontró el insumo %, o no está visible para este usuario', p_insumo_id;
  end if;
  if v_tipo <> 'material' then
    raise exception 'Solo se pueden agregar materiales a la receta';
  end if;

  v_composicion_personal_id := clonar_receta_personal_apu(p_subitem_id);

  if exists (
    select 1 from apu_composicion_items
    where apu_composicion_items.apu_composicion_id = v_composicion_personal_id
      and apu_composicion_items.insumo_id = p_insumo_id
  ) then
    raise exception 'Este material ya está en la receta';
  end if;

  insert into apu_composicion_items (apu_composicion_id, tipo_componente, insumo_id, rendimiento)
  values (v_composicion_personal_id, 'material', p_insumo_id, p_rendimiento);

  return query
    select * from calcular_composicion_detalle_subitem(p_obra_id, p_subitem_id);
end;
$$;

create or replace function quitar_material_apu(
  p_obra_id uuid,
  p_subitem_id uuid,
  p_insumo_id uuid
)
returns table(
  item_id uuid,
  apu_composicion_id uuid,
  es_personal boolean,
  tipo_componente text,
  insumo_id uuid,
  insumo_nombre text,
  insumo_unidad text,
  rendimiento numeric,
  precio_unitario numeric
)
language plpgsql security invoker set search_path = public as $$
declare
  v_composicion_personal_id uuid;
begin
  v_composicion_personal_id := clonar_receta_personal_apu(p_subitem_id);

  delete from apu_composicion_items
  where apu_composicion_items.apu_composicion_id = v_composicion_personal_id
    and apu_composicion_items.insumo_id = p_insumo_id
    and apu_composicion_items.tipo_componente = 'material';

  if not found then
    raise exception 'No se encontró ese material en la receta';
  end if;

  return query
    select * from calcular_composicion_detalle_subitem(p_obra_id, p_subitem_id);
end;
$$;

create or replace function agregar_equipo_apu(
  p_obra_id uuid,
  p_subitem_id uuid,
  p_insumo_id uuid,
  p_rendimiento numeric,
  p_precio_inicial numeric default null
)
returns table(
  item_id uuid,
  apu_composicion_id uuid,
  es_personal boolean,
  tipo_componente text,
  insumo_id uuid,
  insumo_nombre text,
  insumo_unidad text,
  rendimiento numeric,
  precio_unitario numeric
)
language plpgsql security invoker set search_path = public as $$
declare
  v_tipo text;
  v_composicion_personal_id uuid;
begin
  if p_rendimiento < 0 then
    raise exception 'El rendimiento no puede ser negativo';
  end if;
  if p_precio_inicial is not null and p_precio_inicial < 0 then
    raise exception 'El precio no puede ser negativo';
  end if;

  select tipo into v_tipo from insumos where id = p_insumo_id;
  if v_tipo is null then
    raise exception 'No se encontró el insumo %, o no está visible para este usuario', p_insumo_id;
  end if;
  if v_tipo <> 'equipo' then
    raise exception 'Solo se pueden agregar equipos a la receta';
  end if;

  v_composicion_personal_id := clonar_receta_personal_apu(p_subitem_id);

  if exists (
    select 1 from apu_composicion_items
    where apu_composicion_items.apu_composicion_id = v_composicion_personal_id
      and apu_composicion_items.insumo_id = p_insumo_id
  ) then
    raise exception 'Este equipo ya está en la receta';
  end if;

  insert into apu_composicion_items (apu_composicion_id, tipo_componente, insumo_id, rendimiento)
  values (v_composicion_personal_id, 'equipo', p_insumo_id, p_rendimiento);

  if p_precio_inicial is not null then
    insert into obra_insumo_precios (obra_id, insumo_id, precio, origen, usuario_id)
    values (p_obra_id, p_insumo_id, p_precio_inicial, 'manual', auth.uid())
    on conflict (obra_id, insumo_id)
    do update set precio = excluded.precio, origen = 'manual', corralon_id = null, usuario_id = excluded.usuario_id;
  end if;

  return query
    select * from calcular_composicion_detalle_subitem(p_obra_id, p_subitem_id);
end;
$$;

create or replace function quitar_equipo_apu(
  p_obra_id uuid,
  p_subitem_id uuid,
  p_insumo_id uuid
)
returns table(
  item_id uuid,
  apu_composicion_id uuid,
  es_personal boolean,
  tipo_componente text,
  insumo_id uuid,
  insumo_nombre text,
  insumo_unidad text,
  rendimiento numeric,
  precio_unitario numeric
)
language plpgsql security invoker set search_path = public as $$
declare
  v_composicion_personal_id uuid;
begin
  v_composicion_personal_id := clonar_receta_personal_apu(p_subitem_id);

  delete from apu_composicion_items
  where apu_composicion_items.apu_composicion_id = v_composicion_personal_id
    and apu_composicion_items.insumo_id = p_insumo_id
    and apu_composicion_items.tipo_componente = 'equipo';

  if not found then
    raise exception 'No se encontró ese equipo en la receta';
  end if;

  return query
    select * from calcular_composicion_detalle_subitem(p_obra_id, p_subitem_id);
end;
$$;

-- Sin `grant execute` -- ninguna de las 5 cambia de firma, los grants que ya corrieron en
-- 0072/0073/0074 siguen valiendo (un grant no se pierde al reemplazar el cuerpo con `create or
-- replace function` sobre la misma firma).

-- =====================================================================
-- Verificación
-- =====================================================================
--
-- El caso que reportó el error real: crear un equipo nuevo (catálogo en 0, así que cualquier
-- nombre dispara el alta) y agregarlo a una partida.
-- select * from buscar_o_crear_equipo_apu('Hormigonera de prueba', 'hs');
-- select * from agregar_equipo_apu(
--   '<obra_id>'::uuid,
--   (select id from subitems where codigo = '8.1' and creador_usuario_id is null),
--   (select id from buscar_o_crear_equipo_apu('Hormigonera de prueba', 'hs')),
--   0.1,
--   3500
-- ); -- antes: 42702. Ahora tiene que devolver la composición completa sin error.

-- Los otros 4 casos, mismo patrón (agregar dos veces el mismo insumo tiene que fallar con el
-- mensaje de negocio -- "ya está en la receta" -- no con 42702):
-- select * from agregar_material_apu('<obra_id>'::uuid, '<subitem_id>'::uuid, '<insumo_id>'::uuid, 0.1);
-- select * from quitar_material_apu('<obra_id>'::uuid, '<subitem_id>'::uuid, '<insumo_id>'::uuid);
-- select * from quitar_equipo_apu('<obra_id>'::uuid, '<subitem_id>'::uuid, '<insumo_id>'::uuid);
-- select * from personalizar_item_apu('<obra_id>'::uuid, '<subitem_id>'::uuid, '<insumo_id>'::uuid, 1.5, 1000);
