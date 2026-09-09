-- Bug reportado por Seba: el interruptor de aplica_impuestos (obra_presupuesto_config, 0020) no
-- afecta ningún monto de precio_final -- ni el precio de la partida en Cómputo, ni el listado de
-- la Solapa APU, ni el total del dashboard (calcular_presupuesto_vivo_obra, 0091, que llama a esta
-- misma función).
--
-- El bloque de Factor K de una partida (bloque_factor_k_partida.dart) SÍ respeta el flag -- pero lo
-- hace del lado del cliente, cortando la UI en "Costo Total del Trabajo" cuando aplica_impuestos es
-- false y no mostrando la línea "Precio Final". `calcular_precio_final_apu_subitems` (0090) no tenía
-- ese mismo corte: devolvía siempre `f.precio_final` de `calcular_factor_k_subitem`, que calcula la
-- cascada de impuestos sin mirar el flag en ningún lado.
--
-- FIX: la CTE `vista_activa` ya lee `tipo_presupuesto` de la config de la obra (0090) -- agrega
-- `aplica_impuestos` a la misma lectura, mismo criterio (dato de la obra, no del cliente). Si está
-- apagado, el precio devuelto es `f.costo_total_trabajo` (la misma columna que usa el bloque de
-- Factor K para el corte) en vez de `f.precio_final` -- ya viene resuelta para la vista correcta
-- (con/sin materiales) adentro de calcular_factor_k_subitem, no hace falta tocar nada más.
--
-- `calcular_presupuesto_vivo_obra` (0091) y todo lo que dependa de esta función se arregla solo --
-- no se toca ningún otro archivo.
--
-- `create or replace`, no DROP+CREATE: misma firma (argumentos y tipo de retorno) que 0090, así que
-- conserva el GRANT/REVOKE existente.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado automáticamente
-- por Claude Code: sin acceso a la base de datos desde este entorno.

create or replace function calcular_precio_final_apu_subitems(p_obra_id uuid, p_subitem_ids uuid[])
returns table(
  subitem_id uuid,
  precio_final numeric,
  insumos_con_precio int,
  insumos_total int,
  cierra_ok boolean
)
language sql security definer set search_path = public stable as $$
  with autorizado as (
    select is_obra_member(p_obra_id) as ok
  ),
  ids as (
    select s.subitem_id
    from unnest(p_subitem_ids) as s(subitem_id)
    cross join autorizado a
    where a.ok
  ),
  vista_activa as (
    -- Datos de la obra, no del cliente -- se leen acá adentro, Dart no manda ningún flag.
    select
      case when c.tipo_presupuesto = 'mano_obra_sola' then 'sin_materiales' else 'con_materiales' end as vista,
      c.aplica_impuestos
    from obra_presupuesto_config c
    where c.obra_id = p_obra_id
  )
  select
    i.subitem_id,
    case when v.aplica_impuestos then f.precio_final else f.costo_total_trabajo end,
    f.insumos_con_precio, f.insumos_total, f.cierra_ok
  from ids i
  cross join lateral calcular_factor_k_subitem(p_obra_id, i.subitem_id) as f
  cross join vista_activa v
  where f.vista = v.vista
    and f.orden = 1;
$$;

grant execute on function calcular_precio_final_apu_subitems(uuid, uuid[]) to authenticated;
revoke execute on function calcular_precio_final_apu_subitems(uuid, uuid[]) from public, anon;

-- =====================================================================
-- Verificación
-- =====================================================================

-- 1) Partida 8.1, obra con aplica_impuestos = true (default): el precio_final de acá tiene que
--    coincidir EXACTO con "Precio Final" del bloque de Factor K de esa misma partida.
-- select * from calcular_precio_final_apu_subitems(
--   '<obra_id>'::uuid,
--   array[(select id from subitems where codigo = '8.1' and creador_usuario_id is null)]
-- );

-- 2) Apagar el interruptor de esa obra (obra_presupuesto_config.aplica_impuestos = false) y repetir
--    la misma consulta -- tiene que coincidir con "Costo Total del Trabajo" del bloque de Factor K
--    (el número que queda justo antes del corte), y tiene que ser más bajo que el paso 1.

-- 3) Precio en Cómputo y listado de Solapa APU de esa partida: tienen que bajar al mismo número del
--    paso 2 apenas se apaga el interruptor, sin recargar la app.

-- 4) Total del dashboard (ObrasListScreen) de esa obra: tiene que bajar en la misma proporción --
--    confirma que calcular_presupuesto_vivo_obra (0091) se arregló solo, sin tocarla.

-- 5) Prender el interruptor de nuevo: todo vuelve a los números del paso 1.
