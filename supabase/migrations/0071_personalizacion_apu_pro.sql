-- Primera de las 6 piezas de "edición de APU en la Solapa APU" (diagnóstico previo sin código,
-- misma conversación). Habilita que un PRO edite el rendimiento de una línea de una partida, o
-- reemplace qué insumo lleva esa línea (ej. ladrillo común -> ladrillón), sin tocar la receta
-- oficial ni el precio del insumo (eso sigue viniendo de Mat y MO / `obra_insumo_precios`).
--
-- Mecanismo: clonado por persona, no por obra -- ya diseñado en docs/rubros_apu_diseno_datos.md
-- §2.4/§3.E y en el schema desde 0018 (`apu_composiciones.creador_usuario_id`, índice único
-- parcial "una sola receta oficial por subítem" + `unique(subitem_id, creador_usuario_id)` para
-- las propias). Esta migración no crea tablas nuevas ni cambia RLS -- solo agrega 2 funciones y
-- extiende una tercera para que devuelva los IDs que la edición necesita.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor), después de 0070. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

-- =====================================================================
-- Sección 1 — calcular_composicion_detalle_subitem: agrega los IDs que faltaban para editar
-- =====================================================================
--
-- La versión de 0060 devuelve nombre/unidad/rendimiento/precio ya aplanados, pero descarta el id
-- de la fila de `apu_composicion_items`, el id de la composición, el insumo_id y si la receta que
-- se está mostrando es la oficial o la personal del usuario -- los 4 hacen falta para poder editar
-- (ver diagnóstico de esta pieza, punto 2). `create or replace` no admite cambiar las columnas de
-- un `returns table` (mismo motivo por el que 0032 necesitó `drop function` para
-- `consolidado_insumos_obra`), así que esto es un `drop` + `create`, no un simple replace.
--
-- Sigue SECURITY DEFINER, sin cambios de criterio respecto a 0060: necesita bypassar la RLS de
-- `obra_insumo_precios` para resolver el precio manual de esta obra, igual que antes. Nada de esto
-- tiene que ver con la pregunta de invoker/definer de las funciones de escritura de la Sección 2 --
-- son problemas distintos (una lee precios de otra tabla con RLS más cerrada, las otras escriben
-- en una tabla cuya RLS ya alcanza para el dueño).

drop function if exists calcular_composicion_detalle_subitem(uuid, uuid);

create function calcular_composicion_detalle_subitem(p_obra_id uuid, p_subitem_id uuid)
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
language sql security definer set search_path = public stable as $$
  with autorizado as (
    -- SECURITY DEFINER bypassa la RLS de obra_insumo_precios, mismo motivo que 0034/0059/0060.
    select is_obra_member(p_obra_id) as ok
  ),
  composicion as (
    -- Misma resolución "propia si existe, si no oficial" que ya tenía 0060 -- ahora se lleva
    -- también creador_usuario_id para poder devolver es_personal más abajo.
    select id as composicion_id, creador_usuario_id
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
    aci.id as item_id,
    aci.apu_composicion_id,
    (c.creador_usuario_id is not null) as es_personal,
    aci.tipo_componente,
    aci.insumo_id,
    ins.nombre as insumo_nombre,
    ins.unidad as insumo_unidad,
    aci.rendimiento,
    -- Mismo COALESCE exacto que 0060, sin cambios.
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
-- Sección 2 — Escritura: personalizar_item_apu y restaurar_receta_oficial_apu
-- =====================================================================
--
-- SECURITY INVOKER en las dos, no DEFINER -- verificado contra las políticas reales de 0018 antes
-- de escribir esto (pedido explícito de Seba, no se asume):
--   - apu_composiciones: INSERT admite `creador_usuario_id = auth.uid()` (exactamente lo que se
--     inserta al clonar), UPDATE/DELETE admiten `creador_usuario_id = auth.uid()` (dueño).
--   - apu_composicion_items: INSERT/UPDATE admiten `is_apu_composicion_owner(apu_composicion_id)`,
--     que resuelve a verdadero para la composición que se acaba de crear con auth.uid().
--   - SELECT de ambas tablas ya deja ver las filas oficiales (creador_usuario_id is null) a
--     cualquier autenticado, necesario para poder clonar sus líneas.
-- Ningún paso de estas dos funciones necesita saltarse la RLS -- correr como el usuario que llama
-- (invoker) alcanza para las dos, y es menos privilegio que definer sin necesidad real de más.
--
-- Gate de PRO: deliberadamente NO se chequea acá dentro, mismo criterio ya documentado como deuda
-- técnica aceptada en docs/rubros_apu_diseno_datos.md §3.G ("Free/PRO en la escritura de
-- obra_subitems/personalización queda en capa de app por ahora") -- la app verifica esPro en vivo
-- al tocar Guardar, antes de llamar a esta función, mismo patrón que el resto de los paneles de
-- edición. Revisar esto junto con el resto de esa deuda cuando exista un sistema de planes real.

-- ---------------------------------------------------------------------
-- personalizar_item_apu: clona (si hace falta) y edita, en una sola transacción
-- ---------------------------------------------------------------------
--
-- p_item_id: el id que la pantalla ya tiene en mano (de calcular_composicion_detalle_subitem),
-- sea de la receta oficial o de una personal que ya existía -- no importa cuál, esta función solo
-- lo usa para leer insumo_id/tipo_componente, nunca para localizar la fila a editar después de
-- clonar (los ids cambian al clonar, ver más abajo).
--
-- p_insumo_id_nuevo null (default) = solo cambia el rendimiento, mismo insumo. Con valor = cambia
-- también qué insumo lleva esa línea (ej. LADRILLOS COMUNES -> LADRILLOS MACIZOS HCCA 10/25/50).
--
-- Ubicación de la línea a editar DESPUÉS de clonar: por (insumo_id, tipo_componente), no por id --
-- clonar genera ids nuevos para cada línea, así que el id viejo (oficial) ya no existe en la
-- receta personal. Asume que una composición no repite el mismo insumo dos veces con el mismo
-- tipo_componente (no hay ningún caso real así hoy, ver diagnóstico) -- si alguna vez lo hubiera,
-- el UPDATE tocaría más de una fila a la vez, caso no manejado a propósito por ser inexistente.
--
-- Devuelve la receta actualizada completa (misma forma que calcular_composicion_detalle_subitem)
-- para que la pantalla no tenga que pedirla de nuevo con un segundo viaje de red.

create function personalizar_item_apu(
  p_obra_id uuid,
  p_subitem_id uuid,
  p_item_id uuid,
  p_rendimiento_nuevo numeric,
  p_insumo_id_nuevo uuid default null
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
  v_insumo_id_actual uuid;
  v_tipo_componente text;
  v_composicion_personal_id uuid;
begin
  if p_rendimiento_nuevo < 0 then
    raise exception 'El rendimiento no puede ser negativo';
  end if;

  -- 1) Qué insumo/tipo es la línea referenciada -- funciona sin importar si p_item_id es de la
  --    oficial o de una personal ya existente. Si no matchea nada (no existe, o la RLS de SELECT
  --    no la deja ver), v_insumo_id_actual queda null y se corta acá, sin tocar nada más.
  select aci.insumo_id, aci.tipo_componente
    into v_insumo_id_actual, v_tipo_componente
  from apu_composicion_items aci
  where aci.id = p_item_id;

  if v_insumo_id_actual is null then
    raise exception 'No se encontró el ítem % de la partida, o no está visible para este usuario', p_item_id;
  end if;

  -- 2) Buscar la composición personal de este usuario para este subítem; si no existe, crearla y
  --    clonar ahí las líneas de la oficial completa -- nunca se edita con una sola línea suelta.
  select id into v_composicion_personal_id
  from apu_composiciones
  where subitem_id = p_subitem_id and creador_usuario_id = auth.uid();

  if v_composicion_personal_id is null then
    insert into apu_composiciones (subitem_id, creador_usuario_id)
    values (p_subitem_id, auth.uid())
    returning id into v_composicion_personal_id;

    insert into apu_composicion_items (apu_composicion_id, tipo_componente, insumo_id, rendimiento)
    select v_composicion_personal_id, aci.tipo_componente, aci.insumo_id, aci.rendimiento
    from apu_composicion_items aci
    join apu_composiciones ac on ac.id = aci.apu_composicion_id
    where ac.subitem_id = p_subitem_id and ac.creador_usuario_id is null;
  end if;

  -- 3) Aplicar el cambio sobre la línea correspondiente, ya dentro de la composición personal
  --    (recién creada o preexistente, da igual a esta altura).
  update apu_composicion_items
  set insumo_id = coalesce(p_insumo_id_nuevo, v_insumo_id_actual),
      rendimiento = p_rendimiento_nuevo
  where apu_composicion_id = v_composicion_personal_id
    and insumo_id = v_insumo_id_actual
    and tipo_componente = v_tipo_componente;

  if not found then
    raise exception 'No se encontró la línea a editar en la receta personal (insumo %, tipo %)',
      v_insumo_id_actual, v_tipo_componente;
  end if;

  return query
    select * from calcular_composicion_detalle_subitem(p_obra_id, p_subitem_id);
end;
$$;

grant execute on function personalizar_item_apu(uuid, uuid, uuid, numeric, uuid) to authenticated;

-- ---------------------------------------------------------------------
-- restaurar_receta_oficial_apu: borra el fork del usuario para esta partida
-- ---------------------------------------------------------------------
--
-- Un solo `delete` filtrado por dueño -- la RLS de apu_composiciones ya lo permite (dueño borra lo
-- suyo), no hace falta chequeo adicional acá. `apu_composicion_items` se borra en cascada
-- (`on delete cascade` desde 0018), sin necesitar un segundo DELETE.
--
-- Devuelve `true` si había una receta personal para borrar, `false` si no tenía ninguna (para que
-- la pantalla pueda distinguir "restauré algo" de "no había nada que restaurar" sin una consulta
-- aparte). El aviso previo ("vas a perder tu personalización de esta partida") es responsabilidad
-- de la pantalla, no de esta función -- acá no hay confirmación, se asume que ya se mostró antes
-- de llamar.

create function restaurar_receta_oficial_apu(p_subitem_id uuid)
returns boolean
language plpgsql security invoker set search_path = public as $$
begin
  delete from apu_composiciones
  where subitem_id = p_subitem_id and creador_usuario_id = auth.uid();

  return found;
end;
$$;

grant execute on function restaurar_receta_oficial_apu(uuid) to authenticated;

-- =====================================================================
-- Verificación
-- =====================================================================
--
-- Partida sugerida: 8.1 (Mampostería) -- 6 líneas (2 mano_obra, 4 material), incluye
-- LADRILLOS COMUNES, buen caso para probar el swap de material (-> LADRILLOS MACIZOS HCCA
-- 10/25/50) además de un cambio simple de rendimiento.

-- 1) Estado inicial: la receta de 8.1 sin fork todavía -- las 6 filas deberían tener
--    es_personal = false.
-- select * from calcular_composicion_detalle_subitem(
--   '<obra_id>'::uuid,
--   (select id from subitems where codigo = '8.1' and creador_usuario_id is null)
-- );

-- 2) Cambiar solo el rendimiento de una línea (ej. ARENA) -- primer edit, tiene que clonar las 6
--    y devolver las 6 con es_personal = true, solo ARENA con el rendimiento nuevo.
-- select * from personalizar_item_apu(
--   '<obra_id>'::uuid,
--   (select id from subitems where codigo = '8.1' and creador_usuario_id is null),
--   '<item_id de ARENA, tomado del resultado del paso 1>'::uuid,
--   0.06
-- );

-- 3) Confirmar que ahora existe exactamente 1 apu_composiciones personal para 8.1 (no más).
-- select count(*) from apu_composiciones ac
-- join subitems s on s.id = ac.subitem_id
-- where s.codigo = '8.1' and s.creador_usuario_id is null and ac.creador_usuario_id = auth.uid();

-- 4) Segundo edit, ahora cambiando el insumo (swap): LADRILLOS COMUNES -> LADRILLOS MACIZOS HCCA
--    10/25/50, sin volver a clonar (la composición personal ya existe) -- tiene que seguir dando
--    6 filas, no 7.
-- select * from personalizar_item_apu(
--   '<obra_id>'::uuid,
--   (select id from subitems where codigo = '8.1' and creador_usuario_id is null),
--   '<item_id de LADRILLOS COMUNES, de la respuesta del paso 2>'::uuid,
--   62,
--   (select id from insumos where nombre = 'LADRILLOS MACIZOS HCCA 10/25/50' and creador_usuario_id is null)
-- );

-- 5) Volver a la oficial: true la primera vez, false si se llama de nuevo sin fork.
-- select restaurar_receta_oficial_apu(
--   (select id from subitems where codigo = '8.1' and creador_usuario_id is null)
-- );
-- select restaurar_receta_oficial_apu(
--   (select id from subitems where codigo = '8.1' and creador_usuario_id is null)
-- );

-- 6) Después de restaurar, calcular_composicion_detalle_subitem para 8.1 tiene que volver a dar
--    las 6 líneas oficiales originales, es_personal = false en todas.
