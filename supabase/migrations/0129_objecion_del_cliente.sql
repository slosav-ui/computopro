-- 0129 -- La objeción del cliente: frena el pago, no el ciclo
--
-- Tanda 3 de "certificar es un acuerdo entre partes" (pedido de Seba, 2026-09-13). Diseño completo:
-- docs/certificacion_acuerdo_partes_diagnostico.md §5.
--
-- Qué resuelve, textual de Seba: **"el cliente no debe pagar si tiene dudas"**. Hasta acá, un
-- certificado emitido solo podía avanzar: leer, pagar, cerrar. El que recibe el documento no tenía
-- forma de decir "esto no está bien" sin salirse de la app.
--
-- LO QUE NO HACE FALTA, y es la mejor noticia de la pieza: **no hace falta un estado nuevo en
-- `certificados.estado`**. La objeción va como eje aparte, calcada de la anulación (0056), igual que
-- el acuerdo de la 0124. Consecuencia: no se tocan las 4 check constraints de fechas, ni el candado
-- del 100%, ni `calcular_avance_acumulado_subitem`, ni el índice de un borrador por obra, ni la
-- numeración. El certificado objetado sigue `emitido` o `leido` mientras se discute.
--
-- EL FRENO AL PAGO ES UNA LÍNEA en `marcar_certificado_pagado`, que hoy tiene un único guard de
-- estado. **Leer sigue permitido**: leer no es pagar, y esconderle el certificado a quien lo está
-- objetando sería al revés de lo que hace falta.
--
-- ================== LAS DOS PREGUNTAS DE SEBA, RESPONDIDAS ACÁ ==================
--
-- **¿QUIÉN RESUELVE LA OBJECIÓN?** El lado técnico *responde*, pero **la objeción solo la levanta
-- quien la puso**. Si el objetado pudiera cerrarla solo, la objeción no valdría nada: alcanzaría con
-- escribir cualquier cosa en la respuesta para destrabar el cobro, y el freno sería decorativo. Es
-- el mismo principio que ya rige el resto de la pieza -- quien propone no da la conformidad, quien
-- propone la anulación no la aprueba.
--
-- **¿CÓMO SE CIERRA SI EL CLIENTE SE EQUIVOCÓ?** El lado técnico responde con la aclaración
-- (`responder_objecion_certificado`), el cliente la lee y **levanta la objeción**
-- (`levantar_objecion_certificado`), y el pago se destraba. Queda todo escrito: el fundamento, la
-- respuesta, quién levantó y cuándo. Nadie "gana" la discusión por default.
--
-- **¿Y SI EL CLIENTE NO LA LEVANTA NUNCA?** No hay bloqueo permanente, y esto importa: el lado
-- técnico siempre puede **anular el certificado y emitir uno corregido**, sin pedirle permiso al
-- cliente (`proponer_anulacion_certificado` + `resolver_anulacion_certificado`, que son de las dos
-- partes técnicas). Un certificado objetado sigue `emitido`/`leido`, así que el circuito de anulación
-- está disponible. Cuando esa anulación se aprueba, la objeción queda marcada como `aceptada`
-- automáticamente (paso 6) -- "tenías razón", sin un paso más que alguien se pueda olvidar.
--
-- Eso es exactamente lo que dice el diagnóstico: **el cliente objeta, las dos partes técnicas
-- corrigen**, y la corrección no se reinventa -- es la anulación que ya existe.
--
-- No toca RLS. No agrega estados. No cambia ninguna transición fuera del guard de pago.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project -> SQL Editor), después de `0128`. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.


-- =====================================================================
-- Paso 1 -- el eje de la objeción, en `certificados`
-- =====================================================================
--
-- Tres tramos, y por eso son varias columnas: la objeción (quién, cuándo, con qué fundamento), la
-- respuesta del lado técnico (quién, cuándo, qué contestó) y el cierre (quién la levantó o la
-- aceptó, y cuándo). Sin el tramo del medio, una objeción resuelta no dice qué se contestó, que es
-- justo lo que hay que poder releer seis meses después.
--
-- `objecion_estado` nullable, como `anulacion_estado`: null = este certificado nunca fue objetado,
-- que es el caso de casi todos. Los tres valores: `abierta` (frena el pago), `aclarada` (el cliente
-- la levantó) y `aceptada` (el lado técnico le dio la razón y anuló).
--
-- El fundamento es obligatorio a nivel base, no solo en la UI: **una objeción sin motivo no sirve**
-- -- no se puede responder algo que no se sabe qué es.

alter table certificados
  add column objecion_estado text
    check (objecion_estado is null or objecion_estado in ('abierta', 'aclarada', 'aceptada')),
  add column objecion_fundamento text,
  add column objecion_por uuid references auth.users(id),
  add column objecion_fecha timestamptz,
  add column objecion_respuesta text,
  add column objecion_respondida_por uuid references auth.users(id),
  add column objecion_respondida_fecha timestamptz,
  add column objecion_resuelta_por uuid references auth.users(id),
  add column objecion_resuelta_fecha timestamptz;

alter table certificados add constraint certificados_objecion_planteo_check
  check (objecion_estado is null
    or (objecion_fundamento is not null and objecion_por is not null and objecion_fecha is not null));

alter table certificados add constraint certificados_objecion_cierre_check
  check (objecion_estado not in ('aclarada', 'aceptada')
    or (objecion_resuelta_por is not null and objecion_resuelta_fecha is not null));

alter table certificados add constraint certificados_objecion_respuesta_check
  check (
    (objecion_respuesta is null and objecion_respondida_por is null and objecion_respondida_fecha is null)
    or (objecion_respuesta is not null and objecion_respondida_por is not null and objecion_respondida_fecha is not null)
  );

comment on column certificados.objecion_estado is
  'Eje de la objecion del cliente (0129): abierta | aclarada | aceptada. NO es el estado del '
  'certificado (certificados.estado), que sigue emitido/leido mientras se discute. abierta frena el '
  'pago; leer sigue permitido.';


-- =====================================================================
-- Paso 2 -- objetar_certificado: el cliente plantea la duda
-- =====================================================================
--
-- Autoridad: `cliente_principal` o `invitado_apoderado` con delegación vigente -- el mismo conjunto
-- que marca Leído, y a propósito SIN `puede_aprobar_certificados` ni tope de monto. Objetar no es un
-- acto económico: no compromete ni libera plata, plantea una duda. Pedirle un tope a alguien para
-- que pueda decir "esto no está bien" sería al revés.
--
-- Solo sobre un certificado `emitido` o `leido`. Uno ya pagado no se objeta: la plata salió, y lo
-- que corresponde ahí es la anulación, que ya existe y contempla ese caso. El mensaje lo dice.
--
-- Se puede volver a objetar un certificado cuya objeción anterior se aclaró: es una duda nueva, y
-- los campos se reinician (el historial completo de cada vuelta queda en `audit_log`, igual que la
-- anulación con sus intentos).

create or replace function objetar_certificado(
  p_certificado_id uuid,
  p_fundamento text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_obra_id uuid;
  v_estado text;
  v_objecion_estado text;
begin
  select obra_id, estado, objecion_estado
    into v_obra_id, v_estado, v_objecion_estado
  from certificados
  where id = p_certificado_id;

  if v_obra_id is null then
    raise exception 'certificado % no encontrado', p_certificado_id;
  end if;

  if not (tiene_rol_en_obra(v_obra_id, 'cliente_principal')
       or tiene_rol_en_obra(v_obra_id, 'invitado_apoderado')) then
    raise exception 'la objeción la plantea quien recibe el certificado: el cliente o su apoderado';
  end if;

  if v_estado not in ('emitido', 'leido') then
    raise exception 'un certificado % no se objeta — si ya se pagó y hay un error, el camino es la anulación', v_estado;
  end if;

  if v_objecion_estado = 'abierta' then
    raise exception 'este certificado ya tiene una objeción abierta';
  end if;

  if p_fundamento is null or btrim(p_fundamento) = '' then
    raise exception 'la objeción necesita un fundamento: sin decir qué está mal, no hay nada que responder';
  end if;

  update certificados
  set objecion_estado = 'abierta',
      objecion_fundamento = p_fundamento,
      objecion_por = auth.uid(),
      objecion_fecha = now(),
      objecion_respuesta = null,
      objecion_respondida_por = null,
      objecion_respondida_fecha = null,
      objecion_resuelta_por = null,
      objecion_resuelta_fecha = null
  where id = p_certificado_id;

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (
    v_obra_id, auth.uid(), 'objetar_certificado', 'certificado', p_certificado_id,
    jsonb_build_object('fundamento', p_fundamento)
  );
end;
$$;

grant execute on function objetar_certificado(uuid, text) to authenticated;
revoke execute on function objetar_certificado(uuid, text) from public, anon;


-- =====================================================================
-- Paso 3 -- responder_objecion_certificado: el lado técnico aclara
-- =====================================================================
--
-- **Responder NO cierra la objeción ni destraba el pago.** Es la mitad de la conversación, no el
-- final: el final lo pone quien objetó (paso 4) o la anulación (paso 6).
--
-- Autoridad: `profesional`, `constructor` o `admin_maestro`. Los dos primeros son las partes
-- técnicas, que son las que saben qué se midió. El tercero entra para que no exista una obra donde
-- alguien objeta y nadie puede contestar (una obra con admin_maestro y cliente, sin profesional ni
-- constructor, es posible).
--
-- Se puede responder varias veces: la última respuesta pisa a la anterior, y todas quedan en
-- `audit_log`. Una discusión real tiene más de una vuelta.

create or replace function responder_objecion_certificado(
  p_certificado_id uuid,
  p_respuesta text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_obra_id uuid;
  v_objecion_estado text;
begin
  select obra_id, objecion_estado
    into v_obra_id, v_objecion_estado
  from certificados
  where id = p_certificado_id;

  if v_obra_id is null then
    raise exception 'certificado % no encontrado', p_certificado_id;
  end if;

  if v_objecion_estado <> 'abierta' then
    raise exception 'este certificado no tiene una objeción abierta para responder';
  end if;

  if not (tiene_rol_en_obra(v_obra_id, 'profesional')
       or tiene_rol_en_obra(v_obra_id, 'constructor')
       or tiene_rol_en_obra(v_obra_id, 'admin_maestro')) then
    raise exception 'sin autoridad para responder la objeción de este certificado';
  end if;

  if p_respuesta is null or btrim(p_respuesta) = '' then
    raise exception 'la respuesta no puede estar vacía';
  end if;

  update certificados
  set objecion_respuesta = p_respuesta,
      objecion_respondida_por = auth.uid(),
      objecion_respondida_fecha = now()
  where id = p_certificado_id;

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (
    v_obra_id, auth.uid(), 'responder_objecion_certificado', 'certificado', p_certificado_id,
    jsonb_build_object('respuesta', p_respuesta)
  );
end;
$$;

grant execute on function responder_objecion_certificado(uuid, text) to authenticated;
revoke execute on function responder_objecion_certificado(uuid, text) from public, anon;


-- =====================================================================
-- Paso 4 -- levantar_objecion_certificado: la levanta quien la puso
-- =====================================================================
--
-- **Este es el paso que hace que la objeción valga algo.** La levanta el mismo lado que la planteó
-- -- el cliente o su apoderado -- y nadie más. Si el lado técnico pudiera cerrarla, alcanzaría con
-- escribir cualquier cosa en la respuesta para destrabar el cobro.
--
-- "El mismo LADO", no "la misma persona": un apoderado existe justamente para actuar por el cliente,
-- así que puede levantar una objeción que planteó el cliente y al revés. Lo que no puede es
-- levantarla el que la tiene que responder.
--
-- No exige que haya respuesta: el cliente también puede levantarla porque se dio cuenta solo de que
-- se había equivocado. Forzarlo a esperar una respuesta que ya no necesita sería trámite.

create or replace function levantar_objecion_certificado(p_certificado_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_obra_id uuid;
  v_objecion_estado text;
begin
  select obra_id, objecion_estado
    into v_obra_id, v_objecion_estado
  from certificados
  where id = p_certificado_id;

  if v_obra_id is null then
    raise exception 'certificado % no encontrado', p_certificado_id;
  end if;

  if v_objecion_estado <> 'abierta' then
    raise exception 'este certificado no tiene una objeción abierta';
  end if;

  if not (tiene_rol_en_obra(v_obra_id, 'cliente_principal')
       or tiene_rol_en_obra(v_obra_id, 'invitado_apoderado')) then
    raise exception 'la objeción la levanta quien la planteó: el cliente o su apoderado';
  end if;

  update certificados
  set objecion_estado = 'aclarada',
      objecion_resuelta_por = auth.uid(),
      objecion_resuelta_fecha = now()
  where id = p_certificado_id;

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (
    v_obra_id, auth.uid(), 'levantar_objecion_certificado', 'certificado', p_certificado_id,
    jsonb_build_object('hubo_respuesta', (select objecion_respuesta is not null from certificados where id = p_certificado_id))
  );
end;
$$;

grant execute on function levantar_objecion_certificado(uuid) to authenticated;
revoke execute on function levantar_objecion_certificado(uuid) from public, anon;


-- =====================================================================
-- Paso 5 -- marcar_certificado_pagado: el freno
-- =====================================================================
--
-- Cuerpo vigente de 0011 copiado tal cual, con UN bloque agregado. Ninguna otra línea cambia: la
-- autoridad sigue siendo `puede_gestionar_certificado` (con tope y delegación), la lectura
-- automática al pagar sigue igual, el audit_log igual.
--
-- El guard va después del chequeo de estado y ANTES del de autoridad, a propósito: el que paga es
-- casi siempre el mismo que objetó, así que "tiene una objeción abierta" le dice qué pasa, mientras
-- que "sin autoridad de aprobación" lo mandaría a buscar el problema donde no está.

create or replace function marcar_certificado_pagado(
  p_certificado_id uuid,
  p_medio_pago text,
  p_comprobante_adjuntos text[] default '{}'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_obra_id uuid;
  v_estado text;
  v_monto numeric;
  v_fecha_lectura timestamptz;
  v_lectura_automatica boolean := false;
  v_objecion_estado text;
begin
  select obra_id, estado, monto, fecha_lectura, objecion_estado
    into v_obra_id, v_estado, v_monto, v_fecha_lectura, v_objecion_estado
  from certificados
  where id = p_certificado_id;

  if v_obra_id is null then
    raise exception 'certificado % no encontrado', p_certificado_id;
  end if;

  if v_estado not in ('emitido', 'leido') then
    raise exception 'certificado % no está en condiciones de pagarse (estado actual: %)', p_certificado_id, v_estado;
  end if;

  -- Objeción del cliente (0129): "el cliente no debe pagar si tiene dudas".
  if v_objecion_estado = 'abierta' then
    raise exception 'este certificado tiene una objeción abierta: se levanta la objeción, o se corrige el certificado, antes de pagarlo';
  end if;

  if not puede_gestionar_certificado(v_obra_id, v_monto) then
    raise exception 'sin autoridad de aprobación para pagar este certificado';
  end if;

  if v_fecha_lectura is null then
    v_lectura_automatica := true;
  end if;

  update certificados
  set estado = 'pagado',
      fecha_pago = now(),
      pagado_por = auth.uid(),
      medio_pago = p_medio_pago,
      comprobante_pago_adjuntos = p_comprobante_adjuntos,
      fecha_lectura = coalesce(fecha_lectura, now()),
      leido_por = coalesce(leido_por, auth.uid())
  where id = p_certificado_id;

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (
    v_obra_id, auth.uid(), 'marcar_certificado_pagado', 'certificado', p_certificado_id,
    jsonb_build_object('medio_pago', p_medio_pago, 'lectura_automatica', v_lectura_automatica)
  );
end;
$$;

grant execute on function marcar_certificado_pagado(uuid, text, text[]) to authenticated;
revoke execute on function marcar_certificado_pagado(uuid, text, text[]) from public, anon;


-- =====================================================================
-- Paso 6 -- anular con una objeción abierta la deja 'aceptada'
-- =====================================================================
--
-- Cuerpo vigente de 0127 con dos líneas más en el `update` que anula. Si el lado técnico le da la
-- razón al cliente y anula el certificado, la objeción queda `aceptada` sola: es la misma decisión,
-- y pedir un paso aparte solo garantizaría que alguien se lo olvide y queden objeciones "abiertas"
-- sobre certificados que ya no existen.
--
-- Si la anulación se RECHAZA, la objeción queda como estaba (abierta): rechazar una anulación no
-- resuelve la duda del cliente.

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
  v_anulacion_estado text;
  v_propuesta_por uuid;
  v_nuevo_certificado_id uuid;
  v_posteriores int;
  v_objecion_estado text;
begin
  select obra_id, numero, version, anulacion_estado, anulacion_propuesta_por, objecion_estado
    into v_obra_id, v_numero, v_version, v_anulacion_estado, v_propuesta_por, v_objecion_estado
  from certificados
  where id = p_certificado_id;

  if v_obra_id is null then
    raise exception 'certificado % no encontrado', p_certificado_id;
  end if;

  if not (
    (tiene_rol_en_obra(v_obra_id, 'profesional') or tiene_rol_en_obra(v_obra_id, 'constructor'))
    and puede_editar_presupuesto(v_obra_id)
  ) then
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
      anulacion_resuelta_fecha = now(),
      -- 0129: anular con una objeción abierta es darle la razón al cliente.
      objecion_estado = case when objecion_estado = 'abierta' then 'aceptada' else objecion_estado end,
      objecion_resuelta_por = case when objecion_estado = 'abierta' then auth.uid() else objecion_resuelta_por end,
      objecion_resuelta_fecha = case when objecion_estado = 'abierta' then now() else objecion_resuelta_fecha end
  where id = p_certificado_id;

  v_posteriores := contar_certificados_posteriores(p_certificado_id);
  v_nuevo_certificado_id := crear_borrador_reemplazo(p_certificado_id);

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (
    v_obra_id, auth.uid(), 'resolver_anulacion_certificado', 'certificado', p_certificado_id,
    jsonb_build_object(
      'aprobado', true,
      'numero', v_numero,
      'version_nueva', v_version + 1,
      'certificado_nuevo_id', v_nuevo_certificado_id,
      'certificados_posteriores', v_posteriores,
      'reemplazo_nacio_vacio', v_posteriores > 0,
      'objecion_aceptada', v_objecion_estado = 'abierta'
    )
  );
end;
$$;

grant execute on function resolver_anulacion_certificado(uuid, boolean, text) to authenticated;
revoke execute on function resolver_anulacion_certificado(uuid, boolean, text) from public, anon;


-- =====================================================================
-- Paso 7 -- mis_pendientes(): las dos mitades de la conversación
-- =====================================================================
--
-- Cuerpo vigente de 0126 copiado tal cual, con DOS ramas nuevas antes del `order by`. Van las dos y
-- no una sola: una objeción es una conversación, y si el aviso solo va de ida, el que responde nunca
-- se entera de que le contestaron. Es el mismo criterio que ya se aplicó al acuerdo de la 0124.
--
--   certificado_objetado   -> al lado técnico, mientras la objeción no tenga respuesta.
--   objecion_respondida    -> al cliente, cuando ya la tiene y sigue abierta (le toca a él).
--
-- Las dos se apagan solas cuando la objeción se levanta o el certificado se anula.

create or replace function mis_pendientes()
returns table(
  obra_id uuid,
  obra_nombre text,
  tipo text,                -- adicional | quita | demasia | certificado_emitido | certificado_leido
                            -- | certificado_pagado | anulacion | firma_fisica | certificacion_periodo
                            -- | certificado_propuesto | certificado_sin_reemplazo
                            -- | certificado_objetado | objecion_respondida
  entidad_id uuid,
  descripcion text,
  certificado_numero int,
  certificado_version int,
  desde timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  with mis_obras as (
    select distinct o.id, o.nombre
    from obras o
    join obra_members om on om.obra_id = o.id
    where om.usuario_id = auth.uid() and om.activo and o.obra_madre_id is null
  )
  select mo.id as obra_id, mo.nombre as obra_nombre, 'adicional'::text as tipo, m.id as entidad_id,
         m.descripcion as descripcion, null::int as certificado_numero, null::int as certificado_version,
         coalesce(m.enviado_a_aprobacion_en, m.fecha_solicitud) as desde
  from modificaciones_obra m
  join mis_obras mo on mo.id = m.obra_id
  where m.tipo = 'adicional'
    and m.estado = 'pendiente'
    and (m.obra_hija_id is null or m.enviado_a_aprobacion_en is not null)
    and puede_aprobar_adicional(m.obra_id, m.monto_total)

  union all

  select mo.id, mo.nombre, m.tipo, m.id, m.descripcion, null::int, null::int, m.fecha_solicitud
  from modificaciones_obra m
  join mis_obras mo on mo.id = m.obra_id
  where m.tipo in ('quita', 'demasia')
    and m.estado = 'pendiente'
    and puede_aprobar_quita_demasia(m.obra_id)
    and (
      m.solicitado_por <> auth.uid()
      or not exists (
        select 1 from obra_members otro
        where otro.obra_id = m.obra_id and otro.activo
          and otro.rol in ('profesional', 'constructor')
          and otro.usuario_id <> auth.uid()
      )
    )

  union all

  select mo.id, mo.nombre, 'certificado_emitido'::text, c.id, c.periodo, c.numero, c.version, c.fecha_emision
  from certificados c
  join mis_obras mo on mo.id = c.obra_id
  where c.estado = 'emitido'
    and (tiene_rol_en_obra(c.obra_id, 'cliente_principal') or tiene_rol_en_obra(c.obra_id, 'invitado_apoderado'))

  union all

  select mo.id, mo.nombre, 'certificado_leido'::text, c.id, c.periodo, c.numero, c.version, c.fecha_lectura
  from certificados c
  join mis_obras mo on mo.id = c.obra_id
  where c.estado = 'leido'
    and puede_gestionar_certificado(c.obra_id, c.monto)
    -- 0129: con una objeción abierta el pago está frenado, así que pedirlo sería ofrecer algo que la
    -- base rechaza. El pendiente que corresponde ahí es `objecion_respondida`, más abajo.
    and coalesce(c.objecion_estado, '') <> 'abierta'

  union all

  select mo.id, mo.nombre, 'certificado_pagado'::text, c.id, c.periodo, c.numero, c.version, c.fecha_pago
  from certificados c
  join mis_obras mo on mo.id = c.obra_id
  where c.estado = 'pagado'
    and (tiene_rol_en_obra(c.obra_id, 'admin_maestro') or tiene_rol_en_obra(c.obra_id, 'constructor'))

  union all

  select mo.id, mo.nombre, 'anulacion'::text, c.id, c.periodo, c.numero, c.version, c.anulacion_propuesta_fecha
  from certificados c
  join mis_obras mo on mo.id = c.obra_id
  where c.anulacion_estado = 'propuesta'
    and (tiene_rol_en_obra(c.obra_id, 'profesional') or tiene_rol_en_obra(c.obra_id, 'constructor'))
    and c.anulacion_propuesta_por <> auth.uid()

  union all

  select mo.id, mo.nombre, 'firma_fisica'::text, c.id, c.periodo, c.numero, c.version, c.fecha_emision
  from certificados c
  join mis_obras mo on mo.id = c.obra_id
  where c.requiere_firma_fisica = true
    and c.pdf_firmado_subido = false
    and c.estado not in ('borrador', 'anulado')
    and (tiene_rol_en_obra(c.obra_id, 'admin_maestro') or tiene_rol_en_obra(c.obra_id, 'profesional'))

  union all

  select mo.id, mo.nombre, 'certificacion_periodo'::text, null::uuid,
         o.periodicidad_certificacion, null::int, null::int, p.vence
  from obras o
  join mis_obras mo on mo.id = o.id
  cross join lateral proximo_periodo_certificacion(o.id) as p(vence)
  where o.periodicidad_certificacion is not null
    and o.modelo_certificacion = 'avance_medido'
    and o.presupuesto_congelado_en is not null
    and p.vence is not null
    and p.vence <= now()
    and not exists (
      select 1 from certificados c where c.obra_id = o.id and c.estado = 'borrador'
    )
    and (tiene_rol_en_obra(o.id, 'admin_maestro')
      or tiene_rol_en_obra(o.id, 'profesional')
      or tiene_rol_en_obra(o.id, 'constructor'))

  union all

  select mo.id, mo.nombre, 'certificado_propuesto'::text, c.id, c.periodo, c.numero, c.version,
         c.propuesta_fecha
  from certificados c
  join mis_obras mo on mo.id = c.obra_id
  where c.estado = 'borrador'
    and c.acuerdo_estado = 'propuesto'
    and puede_dar_conformidad_certificado(c.id)

  union all

  select mo.id, mo.nombre, 'certificado_sin_reemplazo'::text, c.id, c.periodo, c.numero, c.version,
         c.anulacion_resuelta_fecha
  from certificados c
  join mis_obras mo on mo.id = c.obra_id
  where c.estado = 'anulado'
    and falta_reemplazo_certificado(c.id)
    and (tiene_rol_en_obra(c.obra_id, 'admin_maestro')
      or tiene_rol_en_obra(c.obra_id, 'profesional')
      or tiene_rol_en_obra(c.obra_id, 'constructor'))

  union all

  -- Objeción del cliente (0129), ida: al lado técnico, mientras no haya respuesta. Mismo conjunto
  -- que `responder_objecion_certificado`.
  select mo.id, mo.nombre, 'certificado_objetado'::text, c.id, c.periodo, c.numero, c.version,
         c.objecion_fecha
  from certificados c
  join mis_obras mo on mo.id = c.obra_id
  where c.objecion_estado = 'abierta'
    and c.objecion_respuesta is null
    and (tiene_rol_en_obra(c.obra_id, 'profesional')
      or tiene_rol_en_obra(c.obra_id, 'constructor')
      or tiene_rol_en_obra(c.obra_id, 'admin_maestro'))

  union all

  -- Y la vuelta: al cliente, cuando ya le respondieron y la objeción sigue abierta. Le toca a él
  -- leer la aclaración y levantar la objeción, o dejarla planteada.
  select mo.id, mo.nombre, 'objecion_respondida'::text, c.id, c.periodo, c.numero, c.version,
         c.objecion_respondida_fecha
  from certificados c
  join mis_obras mo on mo.id = c.obra_id
  where c.objecion_estado = 'abierta'
    and c.objecion_respuesta is not null
    and (tiene_rol_en_obra(c.obra_id, 'cliente_principal')
      or tiene_rol_en_obra(c.obra_id, 'invitado_apoderado'))

  order by 8;
$$;

grant execute on function mis_pendientes() to authenticated;


-- =====================================================================
-- Verificación a mano después de aplicar (SQL Editor + app)
-- =====================================================================
--
-- Casi todo va desde la app con usuarios reales: el SQL Editor corre sin usuario logueado y
-- `tiene_rol_en_obra` da false para todo.
--
-- 1) Las columnas y los tres checks:
--    select column_name from information_schema.columns
--    where table_name = 'certificados' and column_name like 'objecion%';
--    -- y que el check del fundamento muerda:
--    update certificados set objecion_estado = 'abierta' where id = '<cert_emitido>';
--    -- tiene que fallar por certificados_objecion_planteo_check.
--
-- 2) *** EL CIRCUITO COMPLETO, con dos usuarios (un cliente y un técnico):
--    - el cliente objeta sin fundamento -> "la objeción necesita un fundamento...";
--    - objeta con fundamento -> objecion_estado = 'abierta';
--    - *** el cliente (o su apoderado) intenta PAGAR -> "este certificado tiene una objeción
--      abierta..."  <- este es el punto de toda la tanda;
--    - el cliente marca LEÍDO -> tiene que seguir funcionando (leer no es pagar);
--    - el técnico intenta levantar la objeción -> "la objeción la levanta quien la planteó";
--    - el técnico responde -> la objeción sigue 'abierta' (responder no destraba nada);
--    - el cliente levanta la objeción -> 'aclarada', y AHORA el pago funciona.
--
-- 3) El otro final: con una objeción abierta, el lado técnico propone y aprueba la anulación ->
--    el certificado queda 'anulado', la objeción queda 'aceptada' con quién y cuándo, y nace el
--    reemplazo (vacío o con partidas, según la 0127). Si la anulación se RECHAZA, la objeción tiene
--    que seguir 'abierta'.
--
-- 4) Que un certificado sin objeción no cambie en nada: emitir, leer, pagar y cerrar tiene que
--    funcionar exactamente como antes de esta migración. `objecion_estado` en null no frena nada.
--
-- 5) Objetar fuera de tiempo: sobre un certificado ya pagado o cerrado -> "un certificado pagado no
--    se objeta — si ya se pagó y hay un error, el camino es la anulación".
--
-- 6) Los avisos: con la objeción abierta y sin respuesta, `mis_pendientes()` devuelve
--    'certificado_objetado' al técnico y NO al cliente. Después de responder, devuelve
--    'objecion_respondida' al cliente y ya no 'certificado_objetado' al técnico. Y el
--    'certificado_leido' (pedido de pago) NO tiene que aparecer mientras la objeción esté abierta.
