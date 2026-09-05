-- Gestión de Obra, pieza 4, tanda 3: anulación de un certificado emitido. La más delicada de las
-- tres tandas — columna version + cambio de constraint + estado nuevo + columnas de
-- propuesta/aprobación + 2 funciones. Ver docs/certificados_ciclo_vida_diseno_datos.md §12 para el
-- diseño completo (agregado en esta misma migración) y la memoria de sesión
-- gestion_obra_pieza4_cerrar_circuito para el diagnóstico previo.
--
-- Caso real que motiva esto: se emite un certificado, el cliente detecta un error (el cliente
-- observa, no participa del circuito de anulación), se anula sin borrarlo — queda visible en el
-- historial con motivo — y el reemplazo lleva el mismo número, versión siguiente.
--
-- Dos preguntas del diagnóstico, ya resueltas por Seba:
-- - La dupla que propone/aprueba es profesional y constructor (los dos que armaron el borrador),
--   nunca el cliente. Nunca la misma persona en los dos lados, aunque combine roles.
-- - El borrador nuevo arranca con una COPIA de las filas de certificado_subitems_avance del
--   anulado (no vacío) — el trigger de la 0052 recalcula monto_periodo solo, así que no arrastra
--   el monto viejo.
--
-- Nota importante encontrada al escribir esto, no asumida: el hallazgo del diagnóstico sobre
-- "emitir_certificado busca el certificado anterior por numero = v_numero - 1 sin filtrar version"
-- ya NO aplica al código actual. Verificado releyendo 0055_certificados_firma_fisica_no_bloquea.sql
-- (la versión de emitir_certificado realmente aplicada hoy): 0055 sacó por completo el bloqueo de
-- firma física, que era el único lugar que hacía ese lookup por numero - 1 — la función actual no
-- consulta el certificado anterior para nada. El hallazgo describía una versión de la función que
-- quedó reemplazada como efecto colateral de la tanda 2, no un bug que siga vivo. No se toca
-- emitir_certificado en esta migración por este motivo específico.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor), en el orden en que aparece
-- este archivo. No ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde
-- este entorno.

-- =====================================================================
-- Paso 0 — verificación previa: confirmar el nombre real de la unique constraint a reemplazar
-- =====================================================================
--
-- unique (obra_id, numero) se definió sin nombre en 0009_certificados.sql — Postgres le puso el
-- nombre default certificados_obra_id_numero_key, mismo patrón ya confirmado en este proyecto para
-- checks sin nombre (certificados_monto_check, 0052). Correr esto ANTES del paso 1 para confirmar
-- que el nombre de abajo es el real; si difiere, ajustar el DROP CONSTRAINT del paso 1 con el
-- nombre que devuelva esta consulta.

select conname from pg_constraint
where conrelid = 'public.certificados'::regclass and contype = 'u';

-- =====================================================================
-- Paso 1 — columna version + cambio de unique + estado nuevo + columnas de propuesta/aprobación
-- =====================================================================

alter table certificados
  add column version int not null default 1;

alter table certificados drop constraint certificados_obra_id_numero_key;
alter table certificados add constraint certificados_obra_id_numero_version_key
  unique (obra_id, numero, version);

-- Estado nuevo 'anulado', agregado al check existente (mismo nombre default que
-- certificados_monto_check ya confirmó el patrón: <tabla>_<columna>_check).
alter table certificados drop constraint certificados_estado_check;
alter table certificados add constraint certificados_estado_check
  check (estado in ('borrador', 'emitido', 'leido', 'pagado', 'impactado_cerrado', 'anulado'));

-- Columnas de propuesta y resolución. anulacion_estado es el "sub-estado" de la anulación en sí
-- (distinto de certificados.estado, que solo pasa a 'anulado' cuando la propuesta se APRUEBA — un
-- certificado con una anulación 'propuesta' pendiente sigue siendo 'emitido'/'leido' para todo lo
-- demás, incluido calcular_avance_acumulado_subitem, hasta que se resuelve).
alter table certificados
  add column anulacion_estado text
    check (anulacion_estado is null or anulacion_estado in ('propuesta', 'aprobada', 'rechazada')),
  add column anulacion_motivo text,
  add column anulacion_propuesta_por uuid references auth.users(id),
  add column anulacion_propuesta_fecha timestamptz,
  add column anulacion_resuelta_por uuid references auth.users(id),
  add column anulacion_resuelta_fecha timestamptz,
  add column anulacion_motivo_rechazo text;

-- Coherencia, mismo patrón que los 4 check de fechas ya existentes en la tabla (0009 §4): toda
-- propuesta tiene motivo/quién/cuándo, toda resolución (aprobada o rechazada) tiene quién/cuándo, y
-- estado='anulado' implica que la anulación fue realmente aprobada (no alcanzable de otra forma).
alter table certificados add constraint certificados_anulacion_propuesta_check
  check (anulacion_estado is null
    or (anulacion_motivo is not null and anulacion_propuesta_por is not null and anulacion_propuesta_fecha is not null));

alter table certificados add constraint certificados_anulacion_resolucion_check
  check (anulacion_estado not in ('aprobada', 'rechazada')
    or (anulacion_resuelta_por is not null and anulacion_resuelta_fecha is not null));

alter table certificados add constraint certificados_anulado_check
  check (estado <> 'anulado' or (anulacion_estado = 'aprobada' and anulacion_resuelta_fecha is not null));

-- =====================================================================
-- Paso 2 — calcular_avance_acumulado_subitem: excluir también 'anulado', no solo 'borrador'
-- =====================================================================
--
-- Sin esto, un certificado anulado seguiría sumando al acumulado del 100% — un subítem certificado
-- en un certificado luego anulado quedaría con ese % "gastado" para siempre, bloqueando sin motivo
-- el rango real disponible en el certificado de reemplazo (que empieza limpio salvo por su propia
-- copia de filas, pero esas filas están en el certificado NUEVO, en 'borrador' — ya excluido).

create or replace function calcular_avance_acumulado_subitem(p_obra_subitem_id uuid)
returns numeric language sql stable as $$
  select coalesce(sum(csa.porcentaje_periodo), 0)
  from certificado_subitems_avance csa
  join certificados c on c.id = csa.certificado_id
  where csa.obra_subitem_id = p_obra_subitem_id
    and c.estado not in ('borrador', 'anulado');
$$;

grant execute on function calcular_avance_acumulado_subitem(uuid) to authenticated;

-- =====================================================================
-- Paso 3 — proponer_anulacion_certificado
-- =====================================================================
--
-- Autoridad: profesional o constructor (los dos que arman el borrador) — nunca el cliente, que
-- solo observa el error. Certificado en 'emitido' o 'leido' únicamente (no 'pagado'/
-- 'impactado_cerrado' — el ciclo cierra al pagar, una quita vía modificaciones_obra es el mecanismo
-- para errores posteriores al pago; no 'borrador' porque un borrador se corrige o descarta
-- directamente, no se "anula"; no 'anulado' porque ya lo está).
--
-- Reproponer después de un rechazo está permitido a propósito (el guard solo bloquea una propuesta
-- YA pendiente, no una ya resuelta) — sobrescribe los campos de la propuesta anterior, igual que
-- modificaciones_obra/hitos_certificacion dejan que las columnas "actuales" reflejen el último
-- intento; el historial completo de cada intento queda en audit_log, no en estas columnas.

create or replace function proponer_anulacion_certificado(
  p_certificado_id uuid,
  p_motivo text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_obra_id uuid;
  v_estado text;
  v_anulacion_estado text;
begin
  select obra_id, estado, anulacion_estado
    into v_obra_id, v_estado, v_anulacion_estado
  from certificados
  where id = p_certificado_id;

  if v_obra_id is null then
    raise exception 'certificado % no encontrado', p_certificado_id;
  end if;

  if not (tiene_rol_en_obra(v_obra_id, 'profesional') or tiene_rol_en_obra(v_obra_id, 'constructor')) then
    raise exception 'sin autoridad para proponer la anulación de este certificado';
  end if;

  if v_estado not in ('emitido', 'leido') then
    raise exception 'certificado % no se puede anular desde su estado actual (%)', p_certificado_id, v_estado;
  end if;

  if v_anulacion_estado = 'propuesta' then
    raise exception 'ya hay una anulación propuesta pendiente para este certificado';
  end if;

  if p_motivo is null or btrim(p_motivo) = '' then
    raise exception 'la anulación necesita un motivo';
  end if;

  update certificados
  set anulacion_estado = 'propuesta',
      anulacion_motivo = p_motivo,
      anulacion_propuesta_por = auth.uid(),
      anulacion_propuesta_fecha = now(),
      anulacion_resuelta_por = null,
      anulacion_resuelta_fecha = null,
      anulacion_motivo_rechazo = null
  where id = p_certificado_id;

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (
    v_obra_id, auth.uid(), 'proponer_anulacion_certificado', 'certificado', p_certificado_id,
    jsonb_build_object('motivo', p_motivo)
  );
end;
$$;

grant execute on function proponer_anulacion_certificado(uuid, text) to authenticated;

-- =====================================================================
-- Paso 4 — resolver_anulacion_certificado: aprobar o rechazar, del otro lado de la dupla
-- =====================================================================
--
-- Autoridad: mismo par (profesional/constructor), pero nunca quien propuso — ni siquiera si esa
-- persona combina los dos roles, la propia propuesta no se autoaprueba.
--
-- Al aprobar: certificado pasa a 'anulado', y se crea el borrador de reemplazo con el MISMO número,
-- version + 1, copiando las filas de certificado_subitems_avance del anulado (el trigger de la 0052
-- recalcula monto_periodo con el precio vigente, no arrastra el monto viejo). El índice de "un solo
-- borrador por obra" (0053) no se esquiva: si ya hay otro borrador real en curso, el insert choca
-- solo con ese índice y se devuelve un mensaje de negocio claro en vez del error crudo de Postgres
-- — y como el error se relanza, toda la función revierte (el certificado NO queda marcado 'anulado'
-- si no se pudo crear su reemplazo).
--
-- Al rechazar: el certificado no cambia de estado (sigue 'emitido'/'leido'), solo queda registrado
-- que la anulación propuesta fue rechazada, con motivo opcional.

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

    insert into certificado_subitems_avance (certificado_id, obra_subitem_id, porcentaje_periodo, creado_por)
    select v_nuevo_certificado_id, obra_subitem_id, porcentaje_periodo, auth.uid()
    from certificado_subitems_avance
    where certificado_id = p_certificado_id;
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

-- =====================================================================
-- Verificación
-- =====================================================================

-- 1) La columna version, la unique nueva y el check de estado con 'anulado' existen.
select column_name from information_schema.columns
where table_schema = 'public' and table_name = 'certificados' and column_name = 'version';

select conname from pg_constraint
where conrelid = 'public.certificados'::regclass and conname = 'certificados_obra_id_numero_version_key';

select pg_get_constraintdef(oid) from pg_constraint
where conrelid = 'public.certificados'::regclass and conname = 'certificados_estado_check';

-- 2) Las 2 funciones nuevas existen.
select proname from pg_proc
where proname in ('proponer_anulacion_certificado', 'resolver_anulacion_certificado');

-- 3) Caso real, con un certificado 'emitido' de prueba con avance cargado:
--    a) proponer_anulacion_certificado con el usuario profesional -> certificado sigue 'emitido',
--       anulacion_estado = 'propuesta'.
--    b) resolver_anulacion_certificado(..., p_aprobar => true) con el MISMO usuario -> tiene que
--       fallar ("quien propone... no puede aprobarla").
--    c) resolver_anulacion_certificado(..., p_aprobar => true) con el usuario constructor -> el
--       certificado original pasa a 'anulado'; aparece un certificado nuevo en 'borrador', mismo
--       numero, version = 2, con las mismas filas de certificado_subitems_avance (mismo
--       porcentaje_periodo, monto_periodo recalculado por el trigger).
--    d) calcular_avance_acumulado_subitem de esos obra_subitem_id ya NO cuenta el % del certificado
--       anulado (solo lo que tenga el nuevo borrador una vez emitido).
-- 4) Repetir con p_aprobar => false: el certificado original queda igual (estado sin cambios),
--    anulacion_estado = 'rechazada', sin certificado nuevo creado.
-- 5) Con otro borrador real ya en curso en la misma obra: aprobar una anulación tiene que fallar con
--    el mensaje de negocio de arriba, y el certificado original NO debe quedar en 'anulado' (todo
--    revertido).
