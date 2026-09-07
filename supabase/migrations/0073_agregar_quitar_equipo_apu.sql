-- Extiende agregar/quitar (0072_edicion_apu_correcciones.sql) a equipos -- esa migración solo
-- cubría materiales; `apu_composicion_items.tipo_componente` admite 'equipo' desde el diseño
-- fundacional (0018) y la planilla trae un bloque de equipos en cada partida, pero la pantalla no
-- tenía forma de agregar/quitar uno ni de mostrar el bloque cuando no había ninguno cargado.
--
-- Funciones nuevas, no una generalización de agregar_material_apu/quitar_material_apu -- esas ya
-- están en producción con esa firma exacta (aplicadas desde 0072), cambiarles el contrato ahí
-- rompería sin necesidad. El precio de un equipo YA iba a obra_insumo_precios en
-- personalizar_item_apu (0072): esa función solo separa mano_obra (obra_valor_hora_override) de
-- "cualquier otra cosa" (obra_insumo_precios) -- equipo entra en la segunda rama sin cambios acá.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor), después de 0072. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

create or replace function agregar_equipo_apu(
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
  if v_tipo <> 'equipo' then
    raise exception 'Solo se pueden agregar equipos a la receta';
  end if;

  v_composicion_personal_id := clonar_receta_personal_apu(p_subitem_id);

  if exists (
    select 1 from apu_composicion_items
    where apu_composicion_id = v_composicion_personal_id and insumo_id = p_insumo_id
  ) then
    raise exception 'Este equipo ya está en la receta';
  end if;

  insert into apu_composicion_items (apu_composicion_id, tipo_componente, insumo_id, rendimiento)
  values (v_composicion_personal_id, 'equipo', p_insumo_id, p_rendimiento);

  return query
    select * from calcular_composicion_detalle_subitem(p_obra_id, p_subitem_id);
end;
$$;

grant execute on function agregar_equipo_apu(uuid, uuid, uuid, numeric) to authenticated;

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
  where apu_composicion_id = v_composicion_personal_id
    and insumo_id = p_insumo_id
    and tipo_componente = 'equipo';

  if not found then
    raise exception 'No se encontró ese equipo en la receta';
  end if;

  return query
    select * from calcular_composicion_detalle_subitem(p_obra_id, p_subitem_id);
end;
$$;

grant execute on function quitar_equipo_apu(uuid, uuid, uuid) to authenticated;

-- =====================================================================
-- Verificación
-- =====================================================================
--
-- IMPORTANTE antes de probar: hoy no hay ningún insumo con tipo = 'equipo' en el catálogo (ver
-- conversación -- confirmado por grep en todas las migraciones, ninguna cargó uno nunca). El
-- buscador de "Agregar equipo" de la pantalla no va a encontrar nada hasta que exista al menos
-- uno. Para probar esto en el SQL Editor, cargar un equipo de prueba primero:
--
-- insert into insumos (nombre, unidad, tipo) values ('HORMIGONERA 1 BOLSA', 'hs', 'equipo')
-- returning id;

-- 1) Agregar el equipo de prueba a la partida 8.1 (clona si hace falta).
-- select * from agregar_equipo_apu(
--   '<obra_id>'::uuid,
--   (select id from subitems where codigo = '8.1' and creador_usuario_id is null),
--   '<id devuelto por el insert de arriba>'::uuid,
--   0.1
-- );

-- 2) Quitarlo de nuevo.
-- select * from quitar_equipo_apu(
--   '<obra_id>'::uuid,
--   (select id from subitems where codigo = '8.1' and creador_usuario_id is null),
--   '<mismo id>'::uuid
-- );
