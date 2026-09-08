-- Reemplaza el intento de 0089 (nunca aplicado en producción -- este archivo hace DROP + CREATE
-- del mismo nombre/firma de función, así que el resultado final es correcto sin importar si 0089
-- llegó a correrse o no).
--
-- 0089 restaba las líneas 'material' de la suma (costo-costo sin materiales) y eso NO es lo mismo
-- que el precio final de la vista "sin materiales": esa vista tiene su propia cascada -- Gastos
-- Generales/EPP/Costo Financiero se arrastran de la vista completa, Imprevistos/Beneficio se
-- recalculan sobre la base reducida, y se agrega Gestión de materiales de terceros al 4% -- ya
-- construida y verificada en `calcular_factor_k_subitem` (0078, corregida en 0085) y documentada en
-- docs/factor_k_apu_decisiones.md. DECISIÓN DE SEBA: no duplicar esa cascada en una segunda función
-- -- ya tuvo un bug real de redondeo (0078) que hubo que corregir después de aplicada, y con la
-- lógica en dos lugares la próxima corrección de ese tipo puede olvidarse de uno de los dos,
-- dejando Factor K y Cómputo con precios distintos para la misma partida sin que nadie lo note.
--
-- FIX: función nueva, batch, que llama a `calcular_factor_k_subitem` por dentro vía LATERAL -- una
-- vez por subítem del array, pero en una sola consulta (un solo viaje de red desde Dart), sin
-- reescribir la cascada en ningún lado. Lee `obra_presupuesto_config.tipo_presupuesto` ella misma
-- -- es un dato de la obra, no del cliente, mismo criterio que ya usa `calcular_valor_hora_mano_obra`
-- para zona/cargas sociales sin que Dart le pase nada.
--
-- `calcular_precio_apu_subitems` (0059) vuelve a su forma original de 4 columnas -- las 3 que
-- agregó 0089 calculaban lo que este comentario ya explicó que está mal, quedaban sin uso. Sigue
-- haciendo falta tal cual para `calcular_monto_obra_subitems` (certificación/avance de obra), que
-- no tiene relación con este selector y no se toca acá.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado automáticamente
-- por Claude Code: sin acceso a la base de datos desde este entorno.

-- =====================================================================
-- Paso 1 — calcular_precio_apu_subitems vuelve a su forma de 0059 (4 columnas)
-- =====================================================================

drop function calcular_precio_apu_subitems(uuid, uuid[]);

create function calcular_precio_apu_subitems(p_obra_id uuid, p_subitem_ids uuid[])
returns table(subitem_id uuid, precio_total numeric, insumos_con_precio int, insumos_total int)
language sql security definer set search_path = public stable as $$
  with autorizado as (
    -- SECURITY DEFINER bypassa la RLS de obra_insumo_precios, así que el chequeo de membresía se
    -- repite acá a mano -- mismo motivo y mismo patrón que consolidado_insumos_obra (0031).
    select is_obra_member(p_obra_id) as ok
  ),
  composiciones as (
    -- Una composición por subítem: la propia del usuario si existe, si no la oficial.
    select distinct on (subitem_id) id as composicion_id, subitem_id
    from apu_composiciones
    cross join autorizado a
    where subitem_id = any(p_subitem_ids)
      and (creador_usuario_id = auth.uid() or creador_usuario_id is null)
      and a.ok
    order by subitem_id, creador_usuario_id nulls last
  ),
  valor_hora_mo as (
    -- Una sola llamada -- 5 filas, una por categoría UOCRA -- no una vez por insumo de mano de
    -- obra. p_fecha en su default (current_date), mismo criterio que 0041/0042: vista viva
    -- mientras se arma el presupuesto, no congelada.
    select * from calcular_valor_hora_mano_obra(p_obra_id)
  ),
  items_con_precio as (
    select
      c.subitem_id,
      aci.rendimiento,
      -- Precedencia: manual de esta obra (nunca para mano de obra, ver filtro) -> valor hora UOCRA
      -- (con el override del PRO ya resuelto adentro de calcular_valor_hora_mano_obra) -> promedio
      -- de corralones (siempre NULL para mano de obra, coalesce cae solo si algún día precios
      -- tuviera datos de un insumo que hoy no es mano_obra pero tampoco tiene manual ni escala).
      coalesce(
        (select oip.precio from obra_insumo_precios oip
         where oip.obra_id = p_obra_id and oip.insumo_id = aci.insumo_id and ins.tipo != 'mano_obra'),
        vh.valor_hora,
        (select avg(valor) from precios pr where pr.insumo_id = aci.insumo_id)
      ) as precio_unitario
    from apu_composicion_items aci
    join composiciones c on c.composicion_id = aci.apu_composicion_id
    join insumos ins on ins.id = aci.insumo_id
    left join valor_hora_mo vh on vh.categoria_uocra = ins.categoria_uocra
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
revoke execute on function calcular_precio_apu_subitems(uuid, uuid[]) from public, anon;

-- =====================================================================
-- Paso 2 — calcular_precio_final_apu_subitems: la que usan las listas (Cómputo y Solapa APU)
-- =====================================================================
--
-- `orden = 1` alcanza para quedarse con una sola fila por subítem dentro de la vista elegida:
-- calcular_factor_k_subitem devuelve 6-7 filas por vista (una por concepto de la cascada + líneas
-- de impuestos), todas con el mismo precio_final/insumos_con_precio/insumos_total/cierra_ok
-- repetido -- no hace falta ninguna de las otras. `orden = 1` ("Gastos Generales") es la primera de
-- las dos vistas siempre (ver 0078), así que no depende de cuántas líneas de impuesto tenga cada
-- obra.
--
-- El chequeo de membresía se hace ANTES de invocar calcular_factor_k_subitem (que también lo hace
-- por su cuenta, redundante a propósito) para no calcular la cascada completa de N subítems para
-- alguien sin acceso -- mismo motivo que el resto de las funciones de este archivo repiten el
-- chequeo en vez de confiar en que la función interna ya lo hace.

create function calcular_precio_final_apu_subitems(p_obra_id uuid, p_subitem_ids uuid[])
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
    -- Dato de la obra, no del cliente -- se lee acá adentro, Dart no manda ningún flag.
    select case when c.tipo_presupuesto = 'mano_obra_sola' then 'sin_materiales' else 'con_materiales' end as vista
    from obra_presupuesto_config c
    where c.obra_id = p_obra_id
  )
  select i.subitem_id, f.precio_final, f.insumos_con_precio, f.insumos_total, f.cierra_ok
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

-- 1) Partida 8.1, obra en 'materiales_mano_obra': el precio_final de acá tiene que coincidir EXACTO
--    con el precio_final que ya muestra el bloque de Factor K de esa misma partida, vista
--    "con_materiales" (misma cascada, misma fuente).
-- select * from calcular_precio_final_apu_subitems(
--   '<obra_id>'::uuid,
--   array[(select id from subitems where codigo = '8.1' and creador_usuario_id is null)]
-- );

-- 2) Cambiar la obra a 'mano_obra_sola' (SelectorTipoPresupuesto) y repetir la misma consulta --
--    tiene que coincidir con el precio_final del Factor K en vista "sin_materiales" de esa partida,
--    y tiene que ser un número distinto (más bajo, sin los materiales) del paso 1.

-- 3) calcular_precio_apu_subitems (Paso 1) sigue funcionando igual que antes de 0089/0090 para
--    calcular_monto_obra_subitems -- ver que las partidas certificadas/avance de una obra real no
--    cambiaron de monto con esta migración.

-- 4) anon/authenticated sin membresía: 0 filas en calcular_precio_final_apu_subitems, igual que el
--    resto de las funciones de este patrón.
