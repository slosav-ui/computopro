-- Bug real encontrado por Seba probando el circuito de anulación completo (2026-09-12): el
-- borrador de reemplazo de un certificado anulado aparecía con una partida en 3% de avance y
-- monto $0 -- una partida que ya no estaba en el cómputo de la obra (se había destildado
-- después de emitir el certificado original, `es_aplicable = false`, ver
-- `ObraSubitemsRepository.actualizarEsAplicable`). Al salir de la vista previa esa partida no
-- aparecía como rubro -- quedaba huérfana, visible solo en el borrador.
--
-- Causa: `resolver_anulacion_certificado` (0056) copia CIEGAMENTE todas las filas de
-- `certificado_subitems_avance` del certificado anulado, sin filtrar si la partida sigue vigente.
-- El trigger `calcular_monto_periodo_avance` (0052) sí calcula bien el monto de esa fila copiada
-- (0, porque `calcular_monto_obra_subitems` ya no la incluye si `es_aplicable = false`) -- el
-- número no rompe ninguna cuenta (0 no distorsiona el total), pero la fila igual queda ahí,
-- mostrando un % de avance sobre algo que ya no existe.
--
-- Fix: el `insert` de las filas copiadas se acota a los `obra_subitem_id` que
-- `calcular_monto_obra_subitems(v_obra_id)` todavía devuelve -- la MISMA función que ya decide
-- qué partidas son certificables hoy (bifurca sola por obra congelada/no congelada, 0104), así
-- que este fix no necesita reimplementar ese criterio, solo filtrar por él. Una partida
-- destildada después de emitir, o (si la obra está congelada) una partida que salió de
-- `presupuesto_subitems_congelado`, no se copia al reemplazo -- si de verdad hace falta seguir
-- corrigiendo su avance, se vuelve a tildar/reincorporar antes, como cualquier otra partida nueva
-- del borrador.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor), después de 0110. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

create or replace function resolver_anulacion_certificado(
  p_certificado_id uuid,
  p_aprobar boolean,
  p_motivo_rechazo text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_obra_id uuid;
  v_numero int;
  v_version int;
  v_periodo text;
  v_anulacion_estado text;
  v_propuesta_por uuid;
  v_nuevo_certificado_id uuid;
begin
  select obra_id, numero, version, periodo, anulacion_estado, anulacion_propuesta_por
    into v_obra_id, v_numero, v_version, v_periodo, v_anulacion_estado, v_propuesta_por
  from certificados
  where id = p_certificado_id;

  if v_obra_id is null then
    raise exception 'certificado % no encontrado', p_certificado_id;
  end if;

  if not (tiene_rol_en_obra(v_obra_id, 'profesional') or tiene_rol_en_obra(v_obra_id, 'constructor')) then
    raise exception 'sin autoridad para resolver la anulación de este certificado';
  end if;

  if v_anulacion_estado <> 'propuesta' then
    raise exception 'certificado % no tiene una anulación pendiente de resolución', p_certificado_id;
  end if;

  if auth.uid() = v_propuesta_por then
    raise exception 'quien propone la anulación no puede aprobarla ni rechazarla';
  end if;

  if not p_aprobar then
    update certificados
    set anulacion_estado = 'rechazada',
        anulacion_resuelta_por = auth.uid(),
        anulacion_resuelta_fecha = now(),
        anulacion_motivo_rechazo = p_motivo_rechazo
    where id = p_certificado_id;

    insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
    values (
      v_obra_id, auth.uid(), 'resolver_anulacion_certificado', 'certificado', p_certificado_id,
      jsonb_build_object('aprobado', false, 'motivo_rechazo', p_motivo_rechazo)
    );
    return;
  end if;

  update certificados
  set estado = 'anulado',
      anulacion_estado = 'aprobada',
      anulacion_resuelta_por = auth.uid(),
      anulacion_resuelta_fecha = now()
  where id = p_certificado_id;

  begin
    insert into certificados (obra_id, numero, version, periodo, estado, creado_por)
    values (v_obra_id, v_numero, v_version + 1, v_periodo, 'borrador', auth.uid())
    returning id into v_nuevo_certificado_id;

    -- FIX (0111): solo se copian las filas cuya partida sigue siendo certificable hoy --
    -- `calcular_monto_obra_subitems` es la fuente de verdad de "qué obra_subitem_id existe para
    -- certificar" (vivo o congelado, según corresponda), la misma que ya usa el trigger de abajo
    -- para calcular monto_periodo. Antes se copiaban TODAS las filas del anulado sin este filtro,
    -- dejando partidas huérfanas (destildadas después de emitir) con avance fantasma en el
    -- reemplazo.
    insert into certificado_subitems_avance (certificado_id, obra_subitem_id, porcentaje_periodo, creado_por)
    select v_nuevo_certificado_id, csa.obra_subitem_id, csa.porcentaje_periodo, auth.uid()
    from certificado_subitems_avance csa
    where csa.certificado_id = p_certificado_id
      and csa.obra_subitem_id in (
        select mos.obra_subitem_id from calcular_monto_obra_subitems(v_obra_id) mos
      );
  exception
    when unique_violation then
      raise exception 'ya hay un borrador en curso para esta obra — resolvé o emití ese borrador antes de poder crear el reemplazo del certificado anulado';
  end;

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (
    v_obra_id, auth.uid(), 'resolver_anulacion_certificado', 'certificado', p_certificado_id,
    jsonb_build_object('aprobado', true, 'numero', v_numero, 'version_nueva', v_version + 1, 'certificado_nuevo_id', v_nuevo_certificado_id)
  );
end;
$$;

grant execute on function resolver_anulacion_certificado(uuid, boolean, text) to authenticated;
revoke execute on function resolver_anulacion_certificado(uuid, boolean, text) from public, anon;

-- =====================================================================
-- Limpieza de filas huérfanas ya creadas por el bug (opcional, correr solo si hace falta)
-- =====================================================================
--
-- Este fix solo previene filas huérfanas NUEVAS -- no toca las que ya existan en un borrador de
-- reemplazo creado antes de aplicar esta migración (como el que encontró Seba). Para identificarlas
-- y borrarlas a mano en ESE borrador puntual (nunca en un certificado que no sea 'borrador' -- la
-- RLS de certificado_subitems_avance ya lo impide, pero conviene no intentarlo):
--
-- select csa.id, csa.obra_subitem_id, csa.porcentaje_periodo, csa.monto_periodo
-- from certificado_subitems_avance csa
-- where csa.certificado_id = '<id del borrador de reemplazo>'
--   and csa.obra_subitem_id not in (
--     select obra_subitem_id from calcular_monto_obra_subitems('<obra_id>')
--   );
--
-- Revisada la lista (debería ser exactamente la partida que Seba vio en 3%/$0), borrarlas con:
-- delete from certificado_subitems_avance where id in (...);

-- =====================================================================
-- Verificación
-- =====================================================================
--
-- 1) Obra de prueba: tildar una partida, cargar avance en un certificado, emitirlo, destildar esa
--    partida (es_aplicable = false), proponer y aprobar la anulación de ese certificado. El
--    borrador de reemplazo NO debe traer ninguna fila para esa partida -- antes de este fix,
--    aparecía con monto $0 y el % copiado.
-- 2) Mismo caso, pero con una partida que sigue tildada: se sigue copiando normal, sin cambios --
--    este fix no afecta el caso feliz (la inmensa mayoría de las anulaciones).
-- 3) Obra congelada: destildar (es_aplicable = false) una partida que sigue en
--    presupuesto_subitems_congelado sin pasar por aprobar_quita_demasia -- calcular_monto_obra_
--    subitems para una obra congelada lee del snapshot, no de es_aplicable, así que esa partida
--    SIGUE copiándose (correcto: el criterio real para una obra congelada es el pactado, no el
--    tilde en vivo).
-- 4) Todo lo demás de la función (candado de autoridad, quien propone no puede aprobar, el choque
--    con "un solo borrador por obra") sigue igual -- sin cambios de comportamiento fuera del
--    filtro nuevo.
