-- Corrige un gap real de 0034_calcular_precio_apu_subitem.sql: para insumos tipo mano_obra, el
-- COALESCE original solo miraba obra_insumo_precios (manual) y avg(precios) (promedio de
-- corralones) -- este segundo término da NULL siempre para mano de obra, un corralón no cotiza
-- horas de oficial (ya documentado en el comentario original de 0034). Faltaba la vía correcta:
-- calcular_valor_hora_mano_obra (Paso 5, escala UOCRA), que consolidado_insumos_obra ya usa desde
-- 0041/0042. Sin esto, toda partida con mano de obra (todas) queda "incompleta" para siempre en
-- calcular_precio_apu_subitems, sin importar cuántos materiales tengan precio real.
--
-- Mismo patrón que 0042 le aplicó a consolidado_insumos_obra, ninguna decisión nueva:
-- - join a insumos (antes items_con_precio no tocaba esa tabla) para tener tipo/categoria_uocra.
-- - CTE valor_hora_mo: una sola llamada a calcular_valor_hora_mano_obra por invocación, no una vez
--   por insumo.
-- - obra_insumo_precios se filtra con `ins.tipo != 'mano_obra'` en el propio JOIN/subquery -- cierra
--   el mismo loophole que 0042 cerró: nada a nivel de base impide una fila vieja de
--   obra_insumo_precios para un insumo de mano de obra, y sin este filtro esa fila ganaría sobre
--   la escala UOCRA sin que nadie lo decidiera.
-- - calcular_valor_hora_mano_obra ya resuelve obra_valor_hora_override puertas adentro (0039,
--   líneas de "Override del PRO") -- no hace falta (ni corresponde) mirar esa tabla acá de nuevo.
--   Mat y MO y APU van a mostrar siempre el mismo valor_hora para la misma obra/categoría, porque
--   los dos terminan llamando a la misma función.
--
-- CREATE OR REPLACE, misma firma de retorno que 0034 -- no hace falta DROP.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

create or replace function calcular_precio_apu_subitems(p_obra_id uuid, p_subitem_ids uuid[])
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
    -- obra. p_fecha en su default (current_date), mismo criterio que 0041/0042: vista viva mientras
    -- se arma el presupuesto, no congelada.
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

-- =====================================================================
-- Verificación
-- =====================================================================

-- 1) Partida 8.1 (Ladrillos comunes E=15CM, Rubro 8): las 4 líneas de material ya tenían precio
--    real (0057/0058) -- con esta corrección, las 2 líneas de mano de obra (OFICIAL, AYUDANTE)
--    también deberían resolver, dando insumos_con_precio = insumos_total = 6. Reemplazar los ids
--    reales de obra/subítem antes de correr.
-- select * from calcular_precio_apu_subitems(
--   '<obra_id>'::uuid,
--   array[(select id from subitems where codigo = '8.1' and creador_usuario_id is null)]
-- );

-- 2) El valor_hora de OFICIAL/AYUDANTE para esa obra tiene que coincidir con lo que ya muestra Mat
--    y MO para los mismos insumos -- misma función, mismo resultado.
-- select * from calcular_valor_hora_mano_obra('<obra_id>'::uuid);
