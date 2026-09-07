-- 0075 calificó `apu_composicion_id`/`insumo_id`/`tipo_componente` a mano en cada `where` que
-- encontré -- y aun así quedó una `insumo_id` sin calificar en alguna parte de la cadena de
-- llamadas de crear equipo (mismo error 42702, ahora en esa columna, confirmado por Seba en
-- producción). Calificar caso por caso demostró no ser confiable: es fácil que se escape una en un
-- cuerpo largo, y el error recién avisa de a una por vez (Postgres corta el parseo en la primera
-- ambigüedad, así que arreglar una revela la siguiente en la próxima corrida).
--
-- Solución de fondo, pedida por Seba: `#variable_conflict use_column` como primera línea del
-- cuerpo de cada función PL/pgSQL de esta familia. Le dice al compilador de PL/pgSQL que, ante
-- cualquier identificador ambiguo entre una variable de la función (acá, las columnas del
-- `RETURNS TABLE`, que PL/pgSQL expone como variables) y una columna de una tabla en el FROM de esa
-- consulta puntual, prefiera la columna -- sin excepción, sin importar cuántas apariciones haya ni
-- si alguna quedó sin calificar a mano.
--
-- Por qué es seguro acá (no es un ajuste que se aplique a ciegas): ninguna de estas funciones
-- necesita nunca la otra lectura (la variable) en el cuerpo -- las columnas del `RETURNS TABLE`
-- nunca se leen ni se asignan a mano en ningún lado, se completan solas vía `RETURN QUERY`. Todo
-- acceso real a datos de la función usa variables con prefijo `v_`/`p_`, nunca el nombre pelado de
-- una columna de salida. No hay ningún caso en las 8 funciones donde "ambiguo -> columna" sea la
-- lectura equivocada.
--
-- Las calificaciones manuales de 0075 quedan en el cuerpo (no está de más, y documentan la
-- intención) -- el pragma es la red de seguridad real, no reemplaza haber entendido el bug.
--
-- Alcance: las 8 funciones PL/pgSQL de la familia "edición de APU en la Solapa APU"
-- (0071-0074) -- no solo las 5 que tenían el bug confirmado, también `clonar_receta_personal_apu`,
-- `restaurar_receta_oficial_apu` y `buscar_o_crear_equipo_apu`, que hoy no lo tienen pero
-- comparten el mismo patrón de `RETURNS TABLE`/columnas de `apu_composicion_items` o `insumos` y
-- podrían clonarlo si se les toca el cuerpo en el futuro sin acordarse de este problema.
-- `calcular_composicion_detalle_subitem` queda afuera a propósito: es `language sql`, no
-- `plpgsql` -- no tiene variables declaradas ni `#variable_conflict`, la ambigüedad de esta
-- migración no existe en absoluto para ese lenguaje.
--
-- Todas por `create or replace function` -- ninguna cambia de firma, solo se les agrega la
-- directiva como primera línea del cuerpo.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor), después de 0075. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

create or replace function clonar_receta_personal_apu(p_subitem_id uuid)
returns uuid
language plpgsql security invoker set search_path = public as $$
#variable_conflict use_column
declare
  v_id uuid;
begin
  select id into v_id from apu_composiciones
  where subitem_id = p_subitem_id and creador_usuario_id = auth.uid();

  if v_id is null then
    insert into apu_composiciones (subitem_id, creador_usuario_id)
    values (p_subitem_id, auth.uid())
    returning id into v_id;

    insert into apu_composicion_items (apu_composicion_id, tipo_componente, insumo_id, rendimiento)
    select v_id, aci.tipo_componente, aci.insumo_id, aci.rendimiento
    from apu_composicion_items aci
    join apu_composiciones ac on ac.id = aci.apu_composicion_id
    where ac.subitem_id = p_subitem_id and ac.creador_usuario_id is null;
  end if;

  return v_id;
end;
$$;

create or replace function restaurar_receta_oficial_apu(p_subitem_id uuid)
returns boolean
language plpgsql security invoker set search_path = public as $$
#variable_conflict use_column
begin
  delete from apu_composiciones
  where subitem_id = p_subitem_id and creador_usuario_id = auth.uid();

  return found;
end;
$$;

create or replace function buscar_o_crear_equipo_apu(p_nombre text, p_unidad text)
returns table(id uuid, nombre text, unidad text)
language plpgsql security invoker set search_path = public as $$
#variable_conflict use_column
declare
  v_id uuid;
  v_nombre_normalizado text := upper(trim(p_nombre));
begin
  if v_nombre_normalizado = '' then
    raise exception 'El nombre del equipo no puede estar vacío';
  end if;
  if p_unidad not in ('hs', 'dia') then
    raise exception 'Unidad inválida para un equipo: % (tiene que ser hs o dia)', p_unidad;
  end if;

  select ins.id into v_id
  from insumos ins
  where ins.tipo = 'equipo' and upper(trim(ins.nombre)) = v_nombre_normalizado
  limit 1;

  if v_id is null then
    insert into insumos (nombre, unidad, categoria, tipo, creador_usuario_id)
    values (trim(p_nombre), p_unidad, 'equipo', 'equipo', auth.uid())
    returning insumos.id into v_id;
  end if;

  return query select ins.id, ins.nombre, ins.unidad from insumos ins where ins.id = v_id;
end;
$$;

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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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

-- Sin `grant execute` en ninguna -- ninguna cambia de firma, los grants que ya corrieron en
-- 0071/0072/0073/0074 siguen valiendo.

-- =====================================================================
-- Verificación
-- =====================================================================
--
-- Mismo caso que reportó el error real, de punta a punta:
-- select * from buscar_o_crear_equipo_apu('Hormigonera de prueba 2', 'hs');
-- select * from agregar_equipo_apu(
--   '<obra_id>'::uuid,
--   (select id from subitems where codigo = '8.1' and creador_usuario_id is null),
--   (select id from buscar_o_crear_equipo_apu('Hormigonera de prueba 2', 'hs')),
--   0.1,
--   3500
-- ); -- tiene que devolver la composición completa, sin 42702 en ninguna columna.
