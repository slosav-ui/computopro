-- Alta de equipos: hoy el catálogo tiene 0 filas con tipo = 'equipo' (ver 0073), así que el
-- buscador de "Agregar equipo" nunca encuentra nada. En vez de dejar al usuario frente a un
-- buscador vacío, la pantalla pasa a un formulario de alta directa mientras el catálogo esté
-- vacío, y a buscador-con-opción-de-crear apenas exista al menos un equipo -- mismo patrón que
-- confianza_precios_diseno.md (docs/) ya define para el catálogo colaborativo de materiales, con
-- una diferencia real: lo que identifica a un equipo como "el mismo" es el NOMBRE, no el precio.
-- El alquiler de una hormigonera en Bariloche y en Córdoba no tiene por qué coincidir -- pedir que
-- además coincidan en precio dejaría a los equipos afuera del catálogo compartido para siempre (3
-- usuarios de 3 zonas jamás van a cargar el mismo número). El precio sigue viviendo por obra en
-- `obra_insumo_precios`, igual que cualquier otro insumo -- el promedio colaborativo por zona que
-- describe confianza_precios_diseno.md sigue sin implementarse en ningún lado (ver ese doc), esta
-- migración no lo adelanta, solo deja el criterio de identidad (nombre) listo para cuando se
-- construya.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor), después de 0073. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

-- =====================================================================
-- Sección 1 — 'dia' como unidad válida
-- =====================================================================
--
-- insumos_unidad_valida (0049) solo admitía 'hs' para tiempo -- un equipo puede cobrarse por hora
-- o por día (el formulario de alta se lo pregunta al usuario), hace falta el segundo valor.

alter table insumos drop constraint insumos_unidad_valida;

alter table insumos
  add constraint insumos_unidad_valida
  check (unidad in ('KG', 'LTRS', 'M2', 'M3', 'ML', 'TON', 'UND', 'hs', 'dia'));

-- =====================================================================
-- Sección 2 — buscar_o_crear_equipo_apu: identidad por nombre, no crea duplicados
-- =====================================================================
--
-- SECURITY INVOKER -- la creación queda con creador_usuario_id = auth.uid() bajo la política
-- insumos_insert que ya existe desde 0017 (creador_usuario_id = auth.uid()), sin necesidad de
-- ningún permiso nuevo. `insumos` ya tiene SELECT abierto a cualquier autenticado (0013) sin
-- distinguir por creador_usuario_id -- un equipo que crea un usuario ya es visible/buscable para
-- cualquier otro sin ningún paso de "promoción" aparte, a diferencia del mecanismo de precios.
-- Comparación de nombre case-insensitive y sin espacios de borde (upper(trim(...))) -- "Hormigonera
-- 130 litros" y "HORMIGONERA 130 LITROS " son el mismo equipo.

create or replace function buscar_o_crear_equipo_apu(p_nombre text, p_unidad text)
returns table(id uuid, nombre text, unidad text)
language plpgsql security invoker set search_path = public as $$
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

grant execute on function buscar_o_crear_equipo_apu(text, text) to authenticated;

-- =====================================================================
-- Sección 3 — agregar_equipo_apu gana un precio inicial opcional
-- =====================================================================
--
-- El formulario de alta directa pide nombre + unidad + PRECIO + rendimiento en un solo paso (ver
-- conversación) -- mismo criterio que personalizar_item_apu (0072): rendimiento y precio en una
-- sola llamada, para no dejar un guardado a mitad de camino. `drop` porque cambia la cantidad de
-- parámetros (`create or replace` no alcanza cuando cambia la firma, mismo motivo que 0071/0072).

drop function if exists agregar_equipo_apu(uuid, uuid, uuid, numeric);

create function agregar_equipo_apu(
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
    where apu_composicion_id = v_composicion_personal_id and insumo_id = p_insumo_id
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

grant execute on function agregar_equipo_apu(uuid, uuid, uuid, numeric, numeric) to authenticated;

-- =====================================================================
-- Verificación
-- =====================================================================

-- 1) Crear (o encontrar) un equipo por nombre -- correr dos veces con el mismo nombre en distinta
--    capitalización/espacios tiene que devolver el mismo id la segunda vez.
-- select * from buscar_o_crear_equipo_apu('Hormigonera 130 litros', 'hs');
-- select * from buscar_o_crear_equipo_apu('  HORMIGONERA 130 LITROS  ', 'hs');

-- 2) Agregarlo a la partida 8.1 con precio inicial.
-- select * from agregar_equipo_apu(
--   '<obra_id>'::uuid,
--   (select id from subitems where codigo = '8.1' and creador_usuario_id is null),
--   (select id from buscar_o_crear_equipo_apu('Hormigonera 130 litros', 'hs')),
--   0.1,
--   3500
-- );

-- 3) Confirmar que el precio quedó en obra_insumo_precios, no como una fila nueva de precios.
-- select * from obra_insumo_precios
-- where obra_id = '<obra_id>'::uuid
--   and insumo_id = (select id from insumos where nombre = 'Hormigonera 130 litros');
