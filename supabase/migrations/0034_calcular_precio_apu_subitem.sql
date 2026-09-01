-- Reemplaza al diseño original de "paso 3 de la vinculación con APU" (0029_calcular_precio_apu_
-- subitem.sql, nunca aplicada, confirmado con `select proname from pg_proc where proname =
-- 'calcular_precio_apu_subitems'` sin filas) — aquella versión calculaba el precio de un subítem
-- promediando `precios` (corralones) sin mirar nunca `obra_id` ni `obra_insumo_precios` (0030,
-- todavía no existía cuando se escribió). Esta versión agrega `p_obra_id` y lee el precio manual/
-- en firme de esa obra con la misma precedencia que ya usa `consolidado_insumos_obra`
-- (0032_consolidado_lee_precio_manual.sql): precio cargado a mano primero, promedio de corralón
-- si no hay.
--
-- Diagnóstico importante para quien retome esto más adelante, para no salir a buscar un bug que
-- no existe: para insumos de tipo `mano_obra`, `precios` SIEMPRE va a dar cero filas y el
-- promedio de corralón SIEMPRE va a ser null. No es un bug ni un dato que falte cargar — `precios`
-- modela lo que cobra cada corralón (ver 0013_rls_proveedores_precios.sql), y un corralón no
-- cotiza horas de oficial. No hay forma de que ese mecanismo cubra mano de obra, por la naturaleza
-- del dato, no por una limitación de esta función. La vía correcta para el precio de mano de obra
-- es, y sigue siendo, la carga manual en `obra_insumo_precios` (paso 3 de Mat y MO) — esta versión
-- de la función no "arregla" el precio de mano de obra, simplemente se entera de que esa carga
-- manual existe, cosa que la versión de 0029 nunca hacía.
--
-- Diseño deliberado que se mantiene igual que en 0029: la función NUNCA colapsa "sin precio" a 0
-- ni a NULL. Devuelve insumos_con_precio/insumos_total junto con precio_total, así el llamador
-- puede distinguir "completo" de "incompleto" sin ambigüedad.
--
-- Sin `drop function`: la versión vieja nunca se aplicó, no hay conflicto de tipo de retorno como
-- el que sí tuvo 0032 con `consolidado_insumos_obra`.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

create or replace function calcular_precio_apu_subitems(p_obra_id uuid, p_subitem_ids uuid[])
returns table(subitem_id uuid, precio_total numeric, insumos_con_precio int, insumos_total int)
language sql security definer set search_path = public stable as $$
  with autorizado as (
    -- SECURITY DEFINER bypassa la RLS de obra_insumo_precios, así que el chequeo de membresía se
    -- repite acá a mano -- mismo motivo y mismo patrón que consolidado_insumos_obra (0031): sin
    -- esto, cualquiera podría pasar el obra_id de una obra ajena y enterarse de qué precio cargó
    -- otro. Si el usuario no es miembro de p_obra_id, composiciones queda vacía y no tira ningún
    -- error, solo devuelve una lista vacía (fail-closed silencioso, mismo criterio que el resto
    -- del proyecto).
    select is_obra_member(p_obra_id) as ok
  ),
  composiciones as (
    -- Una composición por subítem: la propia del usuario si existe, si no la oficial. Hoy nunca
    -- hay una propia (la curación de composiciones personalizadas no empezó), pero el diseño ya
    -- lo contempla para no tener que revisar esto cuando exista. El filtro de "propia o oficial"
    -- se repite acá a mano, mismo criterio que is_apu_composicion_owner/puede_ver_apu_composicion
    -- (0018_apu_composiciones.sql).
    select distinct on (subitem_id) id as composicion_id, subitem_id
    from apu_composiciones
    cross join autorizado a
    where subitem_id = any(p_subitem_ids)
      and (creador_usuario_id = auth.uid() or creador_usuario_id is null)
      and a.ok
    order by subitem_id, creador_usuario_id nulls last
  ),
  items_con_precio as (
    select
      c.subitem_id,
      aci.rendimiento,
      -- Precedencia igual a consolidado_insumos_obra (0032): precio cargado a mano/en firme para
      -- esta obra primero; si no hay fila en obra_insumo_precios, el promedio de corralón. Para
      -- insumos de mano_obra el promedio de corralón siempre va a ser null (ver diagnóstico del
      -- encabezado) -- coalesce resuelve solo a la carga manual en ese caso, sin necesitar ningún
      -- caso especial acá.
      coalesce(
        (select oip.precio from obra_insumo_precios oip
         where oip.obra_id = p_obra_id and oip.insumo_id = aci.insumo_id),
        (select avg(valor) from precios pr where pr.insumo_id = aci.insumo_id)
      ) as precio_unitario
    from apu_composicion_items aci
    join composiciones c on c.composicion_id = aci.apu_composicion_id
  )
  select
    subitem_id,
    coalesce(sum(rendimiento * precio_unitario) filter (where precio_unitario is not null), 0),
    count(*) filter (where precio_unitario is not null)::int,
    count(*)::int
  from items_con_precio
  group by subitem_id;
$$;

grant execute on function calcular_precio_apu_subitems(uuid, uuid[]) to authenticated;
