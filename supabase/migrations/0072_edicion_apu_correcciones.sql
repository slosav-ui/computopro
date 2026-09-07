-- Segunda tanda de "edición de APU en la Solapa APU": 4 correcciones sobre
-- 0071_personalizacion_apu_pro.sql, salidas de comparar la pantalla construida contra la
-- estructura real de la partida 8.1 en PLANILLA_BASE_2_0_v3_CORREGIDA.ods, hoja APU.
--
-- 1) Las 5 categorías de mano de obra (OFICIAL ESPECIALIZADO/OFICIAL/MEDIO OFICIAL/AYUDANTE/AYUDA
--    DE GREMIO) siempre visibles, aunque la receta que se está mostrando (oficial o personal) no
--    tenga fila para alguna -- calcular_composicion_detalle_subitem las sintetiza como fila
--    virtual (item_id null, rendimiento 0) en vez de omitirlas. La fila se vuelve real recién
--    cuando el PRO le carga un rendimiento (personalizar_item_apu la crea en el fork en ese
--    momento, no antes) -- así clonar por editar un material no clona de paso las 5 categorías de
--    mano de obra si el usuario no las tocó.
-- 2) El precio pasa a editarse en el mismo diálogo que el rendimiento -- personalizar_item_apu
--    ahora escribe los dos si hace falta, cada uno en su tabla real (rendimiento en
--    apu_composicion_items del fork; precio en obra_valor_hora_override si el insumo es mano de
--    obra -- por categoría UOCRA, no por insumo suelto, mismo criterio que el lapicito de Mat y MO
--    -- o en obra_insumo_precios si es material/equipo), en una sola llamada para que no quede un
--    guardado a mitad de camino. El aviso de alcance distinto (rendimiento para todas las obras
--    futuras del usuario, precio solo para ésta) es responsabilidad de la pantalla, esta migración
--    no lo impone.
-- 3) agregar_material_apu / quitar_material_apu, nuevas -- alta y baja de una línea de material en
--    el fork del usuario, con el mismo mecanismo de clonado que ya usaba personalizar_item_apu,
--    extraído acá a la función interna clonar_receta_personal_apu para no triplicarlo. El catálogo
--    oficial nunca se toca -- las tres funciones de escritura solo insertan/actualizan/borran
--    filas de la composición personal.
-- 4) personalizar_item_apu pierde el parámetro p_insumo_id_nuevo (el swap "cambiar qué insumo
--    lleva esta línea" queda reemplazado por agregar+quitar -- no tiene sentido dejar dos caminos
--    para el mismo resultado) y pasa a ubicar la línea por insumo_id en vez de por item_id, porque
--    una fila virtual de mano de obra no tiene item_id todavía la primera vez que se edita.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor), después de 0071. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

-- =====================================================================
-- Sección 1 — calcular_composicion_detalle_subitem: sintetiza las 5 categorías de mano de obra
-- =====================================================================
--
-- Mismas columnas que 0071 (`create or replace` alcanza, no hace falta `drop`) -- solo cambia el
-- cuerpo: además de las filas reales, agrega una fila virtual (item_id null) por cada insumo
-- oficial de mano de obra que la composición resuelta (oficial o personal, la que corresponda)
-- todavía no tenga. precio_unitario se resuelve igual que para una fila real -- rendimiento 0 no
-- impide mostrar el valor hora, solo hace que el subtotal de esa línea sea 0.

create or replace function calcular_composicion_detalle_subitem(p_obra_id uuid, p_subitem_id uuid)
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
    -- SECURITY DEFINER bypassa la RLS de obra_insumo_precios, mismo motivo que 0034/0059/0060/0071.
    select is_obra_member(p_obra_id) as ok
  ),
  composicion as (
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
  ),
  filas_reales as (
    select
      aci.id as item_id,
      aci.apu_composicion_id,
      (c.creador_usuario_id is not null) as es_personal,
      aci.tipo_componente,
      aci.insumo_id,
      ins.nombre as insumo_nombre,
      ins.unidad as insumo_unidad,
      aci.rendimiento,
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
  ),
  filas_virtuales as (
    -- Las categorías oficiales de mano de obra que esta composición todavía no tiene como fila
    -- real -- ver punto 1 del comentario de arriba.
    select
      null::uuid as item_id,
      c.composicion_id as apu_composicion_id,
      (c.creador_usuario_id is not null) as es_personal,
      'mano_obra' as tipo_componente,
      ins.id as insumo_id,
      ins.nombre as insumo_nombre,
      ins.unidad as insumo_unidad,
      0::numeric as rendimiento,
      coalesce(vh.valor_hora, (select avg(valor) from precios pr where pr.insumo_id = ins.id)) as precio_unitario
    from composicion c
    cross join insumos ins
    left join valor_hora_mo vh on vh.categoria_uocra = ins.categoria_uocra
    where ins.tipo = 'mano_obra'
      and ins.creador_usuario_id is null
      and not exists (
        select 1 from apu_composicion_items aci2
        where aci2.apu_composicion_id = c.composicion_id and aci2.insumo_id = ins.id
      )
  )
  -- El ORDER BY con expresión (el CASE) no puede ir pegado a un UNION ALL directo -- Postgres solo
  -- admite ordenar por nombre/posición de columna del resultado combinado ahí (error real al
  -- aplicar esta migración por primera vez: "invalid UNION/INTERSECT/EXCEPT ORDER BY clause").
  -- Envolver el UNION en una subconsulta y ordenar afuera lo destraba.
  select * from (
    select * from filas_reales
    union all
    select * from filas_virtuales
  ) todo
  order by
    case tipo_componente when 'mano_obra' then 1 when 'material' then 2 else 3 end,
    insumo_nombre;
$$;

grant execute on function calcular_composicion_detalle_subitem(uuid, uuid) to authenticated;

-- =====================================================================
-- Sección 2 — clonado extraído a función propia, reusada por las 3 funciones de escritura
-- =====================================================================
--
-- Idéntico al bloque que tenía inline personalizar_item_apu en 0071 -- ver ahí el fundamento
-- completo (por qué SECURITY INVOKER alcanza, por qué se ubica por subitem_id + auth.uid()).

create or replace function clonar_receta_personal_apu(p_subitem_id uuid)
returns uuid
language plpgsql security invoker set search_path = public as $$
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

grant execute on function clonar_receta_personal_apu(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- personalizar_item_apu: reemplaza la versión de 0071 -- ubica por insumo_id, no por item_id (una
-- fila virtual de mano de obra no tiene item_id hasta que se edita), y ahora también escribe el
-- precio. Ya no acepta p_insumo_id_nuevo -- el swap in-place queda reemplazado por agregar+quitar.
-- ---------------------------------------------------------------------

drop function if exists personalizar_item_apu(uuid, uuid, uuid, numeric, uuid);

create function personalizar_item_apu(
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

  -- Rendimiento visible ahora mismo (real u oficial, el mismo que ya mostraba la pantalla) -- 0 si
  -- todavía es una fila virtual de mano de obra (ver calcular_composicion_detalle_subitem). Decide
  -- si hace falta clonar: tocar solo el precio de una línea sin cambiar su rendimiento no tiene que
  -- crear un fork -- el precio no vive en la receta personal, vive en obra_insumo_precios /
  -- obra_valor_hora_override, que son por obra y no necesitan ninguna personalización de la receta.
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

    -- Asegura que la línea exista en el fork -- puede faltar si es una categoría de mano de obra
    -- que la oficial no tenía (fila virtual hasta ahora).
    insert into apu_composicion_items (apu_composicion_id, tipo_componente, insumo_id, rendimiento)
    select v_composicion_personal_id, v_tipo, p_insumo_id, 0
    where not exists (
      select 1 from apu_composicion_items
      where apu_composicion_id = v_composicion_personal_id and insumo_id = p_insumo_id
    );

    update apu_composicion_items
    set rendimiento = p_rendimiento_nuevo
    where apu_composicion_id = v_composicion_personal_id and insumo_id = p_insumo_id;
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

grant execute on function personalizar_item_apu(uuid, uuid, uuid, numeric, numeric) to authenticated;

-- ---------------------------------------------------------------------
-- agregar_material_apu / quitar_material_apu: alta y baja de una línea de material en el fork.
-- Acotadas a `tipo = 'material'` a propósito -- agregar/quitar mano de obra o equipos no está
-- pedido en esta pieza (mano de obra ya tiene sus 5 categorías siempre presentes vía fila virtual,
-- no hace falta un alta separada; equipos queda fuera de alcance).
-- ---------------------------------------------------------------------

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
    where apu_composicion_id = v_composicion_personal_id and insumo_id = p_insumo_id
  ) then
    raise exception 'Este material ya está en la receta';
  end if;

  insert into apu_composicion_items (apu_composicion_id, tipo_componente, insumo_id, rendimiento)
  values (v_composicion_personal_id, 'material', p_insumo_id, p_rendimiento);

  return query
    select * from calcular_composicion_detalle_subitem(p_obra_id, p_subitem_id);
end;
$$;

grant execute on function agregar_material_apu(uuid, uuid, uuid, numeric) to authenticated;

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
  where apu_composicion_id = v_composicion_personal_id
    and insumo_id = p_insumo_id
    and tipo_componente = 'material';

  if not found then
    raise exception 'No se encontró ese material en la receta';
  end if;

  return query
    select * from calcular_composicion_detalle_subitem(p_obra_id, p_subitem_id);
end;
$$;

grant execute on function quitar_material_apu(uuid, uuid, uuid) to authenticated;

-- =====================================================================
-- Verificación
-- =====================================================================
--
-- Partida sugerida: 8.1 (Mampostería), misma que usó 0071.

-- 1) Estado inicial (sin fork): tienen que aparecer las 5 categorías de mano de obra aunque la
--    oficial solo tenga 2 cargadas -- las 3 faltantes con item_id null y rendimiento 0.
-- select tipo_componente, insumo_nombre, item_id, rendimiento, precio_unitario
-- from calcular_composicion_detalle_subitem(
--   '<obra_id>'::uuid,
--   (select id from subitems where codigo = '8.1' and creador_usuario_id is null)
-- )
-- order by tipo_componente, insumo_nombre;

-- 2) Cargar rendimiento a una categoría que era virtual (ej. MEDIO OFICIAL) -- clona, y esa línea
--    pasa a tener item_id real; las otras categorías de mano de obra que seguían en 0 quedan como
--    filas reales en 0 (clonadas desde la oficial) o siguen virtuales si la oficial tampoco las
--    tenía -- de cualquier forma, la pantalla las sigue mostrando igual.
-- select * from personalizar_item_apu(
--   '<obra_id>'::uuid,
--   (select id from subitems where codigo = '8.1' and creador_usuario_id is null),
--   (select id from insumos where nombre = 'MEDIO OFICIAL' and creador_usuario_id is null),
--   0.5
-- );

-- 3) Editar SOLO el precio de un material que todavía no tiene fork (ej. ARENA) -- no tiene que
--    crear ninguna fila en apu_composiciones para este usuario (confirmar con el count de abajo
--    antes y después), solo un upsert en obra_insumo_precios.
-- select * from personalizar_item_apu(
--   '<obra_id>'::uuid,
--   (select id from subitems where codigo = '8.1' and creador_usuario_id is null),
--   (select insumo_id from calcular_composicion_detalle_subitem('<obra_id>'::uuid,
--     (select id from subitems where codigo = '8.1' and creador_usuario_id is null))
--    where insumo_nombre ilike '%ARENA%' limit 1),
--   -- mismo rendimiento que ya tenía (sin cambio) --
--   (select rendimiento from calcular_composicion_detalle_subitem('<obra_id>'::uuid,
--     (select id from subitems where codigo = '8.1' and creador_usuario_id is null))
--    where insumo_nombre ilike '%ARENA%' limit 1),
--   15000
-- );
-- select count(*) from apu_composiciones ac join subitems s on s.id = ac.subitem_id
-- where s.codigo = '8.1' and s.creador_usuario_id is null and ac.creador_usuario_id = auth.uid();

-- 4) Agregar un material nuevo (ej. LADRILLOS MACIZOS HCCA 10/25/50) y confirmar que aparece.
-- select * from agregar_material_apu(
--   '<obra_id>'::uuid,
--   (select id from subitems where codigo = '8.1' and creador_usuario_id is null),
--   (select id from insumos where nombre = 'LADRILLOS MACIZOS HCCA 10/25/50' and creador_usuario_id is null),
--   62
-- );

-- 5) Quitarlo de nuevo -- tiene que volver a la cantidad de materiales de antes del paso 4.
-- select * from quitar_material_apu(
--   '<obra_id>'::uuid,
--   (select id from subitems where codigo = '8.1' and creador_usuario_id is null),
--   (select id from insumos where nombre = 'LADRILLOS MACIZOS HCCA 10/25/50' and creador_usuario_id is null)
-- );
