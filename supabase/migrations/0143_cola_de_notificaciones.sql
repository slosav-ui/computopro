-- 0143 -- Notificaciones, Tanda 2: la cola de envíos
--
-- Diagnóstico completo y las 5 tandas: docs/notificaciones_push_diagnostico.md §4.
--
-- **Esta migración tampoco manda nada.** Deja las filas listas para enviar y se puede verificar
-- entera desde el SQL Editor: emitir un certificado y ver aparecer la fila con el destinatario
-- correcto. Lo que envía es la Tanda 3 (Edge Function + FCM).
--
-- Los cuatro eventos, cerrados por Seba:
--
--   1. **certificado emitido**       -> al cliente (o su apoderado con delegación vigente)
--   2. **certificado pagado**        -> a quien cobra (admin_maestro / constructor)
--   3. **adicional aprobado**        -> a quien lo presentó
--   4. **objeción por vencer**       -> al cliente, **a las 24 h** de que le respondieron
--
-- Los tres primeros: *"todos son de plata, y el que espera plata tiene que enterarse"*. El cuarto
-- llega **antes que el aviso de la app**, que aparece a las 48 h (`objecion_avisa_el`, 0131): el
-- plazo total son 5 días y *"si alguien tarda tres en abrir la app ya se comió más de la mitad"*.
-- Justamente por eso el push va primero — es el que no necesita que abra la app.
--
-- **El libro de obra no empuja nunca** (`criterio_pantalla_principal_solo_acciones`). No hay ninguna
-- rama de libros acá y no se agrega después.
--
-- ================== POR QUÉ TRIGGERS Y NO TOCAR LAS CUATRO FUNCIONES ==================
--
-- El primer instinto es meter el encolado adentro de `emitir_certificado`, `aprobar_adicional`,
-- `marcar_certificado_pagado` y `responder_objecion_certificado`. Serían **cuatro cuerpos de función
-- copiados enteros** (entre 50 y 110 líneas cada uno) para agregarles tres líneas, y este proyecto ya
-- sabe cómo termina eso: la `0138` salió a arreglar una función que quedó rota justamente por
-- reescribir cuerpos grandes.
--
-- Van como **triggers AFTER UPDATE** que miran la transición (`old.estado` vs `new.estado`), no como
-- "cambió una fila". Y eso **no contradice** lo que dice §4 del diagnóstico: lo que ahí se descarta
-- es que un webhook dispare por cualquier cambio y que el destinatario se calcule en TypeScript. Acá
-- el disparo es una transición concreta y **el destinatario se calcula en SQL**, al lado de la misma
-- autoridad que ya usa `mis_pendientes()`.
--
-- Ventaja de yapa: si mañana aparece otro camino que emite un certificado, el aviso sale igual. Con
-- el encolado adentro de la función, habría que acordarse.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project -> SQL Editor), después de `0142`. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.


-- =====================================================================
-- Paso 1 -- a quién le toca: la versión "lista de personas" de la autoridad
-- =====================================================================
--
-- `tiene_rol_en_obra(obra, rol)` contesta "¿el que mira tiene este rol?". Para notificar hace falta
-- lo otro: **quiénes lo tienen**. Es la misma regla mirada al revés, incluida la delegación del
-- apoderado (sin fechas = permanente; con las dos, tiene que caer en el rango).
--
-- **Y acá hay una duplicación que dejo a propósito, con el motivo escrito**: la regla de la
-- delegación queda en dos lugares (esta función y `tiene_rol_en_obra`). Lo correcto sería que
-- `tiene_rol_en_obra` pasara a definirse en términos de esta, para que haya una sola copia -- y este
-- proyecto ya se quemó una vez con esa regla duplicada, así que la tentación es fuerte.
--
-- No lo hago en esta migración por una razón concreta: **`tiene_rol_en_obra` la evalúan las políticas
-- RLS de casi todas las tablas, fila por fila.** Cambiarle el cuerpo en la misma migración que
-- introduce una pieza nueva mezcla un refactor de alto alcance con una feature, y si algo sale mal no
-- se sabe cuál de las dos fue. Si conviene unificarlas, es una migración sola que no hace nada más
-- -- y ahí se puede mirar el plan de una consulta antes y después.
--
-- El `usuario_id is distinct from auth.uid()` es la otra regla que vive acá y en ningún otro lado:
-- **a nadie se le avisa de lo que acaba de hacer él mismo**.

create or replace function destinatarios_notificacion(p_obra_id uuid, p_roles text[])
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select distinct m.usuario_id
  from obra_members m
  where m.obra_id = p_obra_id
    and m.activo
    and m.rol = any (p_roles)
    and (m.rol <> 'invitado_apoderado'
      or (m.delegacion_inicio is null and m.delegacion_fin is null)
      or now() between m.delegacion_inicio and m.delegacion_fin)
    and m.usuario_id is distinct from auth.uid();
$$;

revoke execute on function destinatarios_notificacion(uuid, text[]) from public, anon, authenticated;


-- =====================================================================
-- Paso 2 -- la cola
-- =====================================================================
--
-- Una fila por **persona y hecho**, no una por hecho: si un certificado le tiene que llegar al
-- cliente y a su apoderado, son dos filas. Así el reintento, el error y el "ya se envió" son por
-- destinatario, que es como falla FCM en la vida real -- se cae un token, no un evento.
--
-- `enviar_despues_de` es lo que hace que el evento 4 entre en el mismo mecanismo sin inventar otro:
-- la fila se crea cuando el técnico responde y queda fechada para 24 h más tarde.
--
-- **OJO, y es lo que hay que resolver en la Tanda 3:** una fila fechada en el futuro **no la despierta
-- nadie**. El webhook de Supabase dispara en el INSERT, y en ese momento todavía no corresponde
-- mandarla. Para los eventos 1 a 3 (fecha = ahora) el webhook alcanza; para el 4 hace falta algo que
-- pase cada tanto -- `pg_cron`, que Supabase deja habilitar, con un job que pinchee la Edge Function.
-- Es la misma clase de hallazgo que la `0131`: el proyecto no tiene ningún scheduler, y este evento
-- es el primero que lo pide de verdad.
--
-- `intentos` y `error` existen desde el día uno: un push que no llegó, sin esto, no deja rastro en
-- ningún lado.

create table notificaciones (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  obra_id uuid not null references obras(id) on delete cascade,
  tipo text not null check (tipo in (
    'certificado_emitido', 'certificado_pagado', 'adicional_aprobado', 'objecion_por_vencer'
  )),
  entidad_id uuid,
  titulo text not null,
  cuerpo text not null,
  estado text not null default 'pendiente'
    check (estado in ('pendiente', 'enviada', 'fallida', 'descartada')),
  enviar_despues_de timestamptz not null default now(),
  creada_en timestamptz not null default now(),
  enviada_en timestamptz,
  intentos int not null default 0,
  error text
);

-- El índice que va a usar la Tanda 3 para juntar lo que toca mandar. Parcial: las enviadas son la
-- mayoría con el tiempo y no hace falta indexarlas.
create index notificaciones_por_enviar_idx
  on notificaciones (enviar_despues_de)
  where estado = 'pendiente';

create index notificaciones_usuario_idx on notificaciones (usuario_id, creada_en desc);

comment on table notificaciones is
  'Cola de salida de las notificaciones al telefono (0143). Una fila por persona y hecho. La escribe '
  'la base con triggers sobre las transiciones; la vacia la Edge Function de la Tanda 3. NO se '
  'escribe desde el cliente: no hay politica de INSERT.';

comment on column notificaciones.enviar_despues_de is
  'Cuando corresponde mandarla. now() en casi todo; +24 h en objecion_por_vencer. OJO: una fila '
  'fechada en el futuro no la despierta el webhook (dispara en el INSERT) -- hace falta un scheduler '
  'para esas, ver la Tanda 3.';

alter table notificaciones enable row level security;

-- Cada uno ve las suyas y nada más. Sirve para depurar y, si algún día se quiere, para una pantalla
-- de "avisos" adentro de la app.
create policy notificaciones_select on notificaciones for select
using (usuario_id = auth.uid());

-- Sin INSERT, UPDATE ni DELETE para nadie: escriben los triggers (security definer) y la Edge
-- Function con la service key. Que un cliente pueda encolarse una notificación a sí mismo -- o peor,
-- a otro -- no tiene ningún caso de uso y sí varias formas de terminar mal.


-- =====================================================================
-- Paso 3 -- encolar
-- =====================================================================
--
-- Un solo lugar donde se escribe en la cola, con las dos reglas que valen para todos los eventos:
-- **no avisarle al que lo hizo** y **nunca cortar la transición**. Lo segundo importa: si encolar
-- fallara, `emitir_certificado` no puede fallar con él. Un aviso que no sale es molesto; un
-- certificado que no se emite porque no se pudo encolar un aviso es inaceptable.

create or replace function encolar_notificacion(
  p_usuario_id uuid,
  p_obra_id uuid,
  p_tipo text,
  p_entidad_id uuid,
  p_titulo text,
  p_cuerpo text,
  p_enviar_despues_de timestamptz default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_usuario_id is null or p_usuario_id = auth.uid() then
    return;
  end if;

  insert into notificaciones (
    usuario_id, obra_id, tipo, entidad_id, titulo, cuerpo, enviar_despues_de
  )
  values (
    p_usuario_id, p_obra_id, p_tipo, p_entidad_id, p_titulo, p_cuerpo,
    coalesce(p_enviar_despues_de, now())
  );
exception
  when others then
    -- Ver el comentario de arriba: la transición sigue aunque el encolado falle.
    raise warning 'no se pudo encolar la notificación % para %: %', p_tipo, p_usuario_id, sqlerrm;
end;
$$;

revoke execute on function encolar_notificacion(uuid, uuid, text, uuid, text, text, timestamptz)
  from public, anon, authenticated;

-- Cuándo se le avisa al cliente que la objeción se le vence. **24 h**, y no las 48 h del aviso de la
-- app (`objecion_avisa_el`, 0131): el push llega antes justamente porque es el que no necesita que
-- abra la app. Los dos números viven cada uno en su función, como el resto de los plazos.
create or replace function objecion_aviso_push_el(p_respondida_fecha timestamptz)
returns timestamptz language sql stable set search_path = public as $$
  select p_respondida_fecha + interval '24 hours';
$$;

revoke execute on function objecion_aviso_push_el(timestamptz) from public, anon, authenticated;


-- =====================================================================
-- Paso 4 -- los disparadores
-- =====================================================================
--
-- **Sin montos en el texto, y no es una cuestión de redacción**: una notificación se ve en la
-- pantalla bloqueada, y ahí el monto de un certificado lo lee cualquiera que levante el teléfono. Es
-- la única parte de esta pieza que puede filtrar información a alguien que no es miembro de la obra.
-- Por eso los textos dicen qué pasó y de qué obra, y el número se ve entrando.

create or replace function notificar_transicion_certificado()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_obra text;
  v_num text;
  v_u uuid;
begin
  select nombre into v_obra from obras where id = new.obra_id;
  v_num := 'N° ' || coalesce(new.numero::text, '?')
        || case when coalesce(new.version, 1) > 1 then ' v' || new.version else '' end;

  -- 1) Emitido -> al cliente y a su apoderado. Mismo conjunto que la rama `certificado_emitido` de
  --    mis_pendientes() y que `marcar_certificado_leido`.
  if new.estado = 'emitido' and old.estado is distinct from 'emitido' then
    for v_u in
      select * from destinatarios_notificacion(
        new.obra_id, array['cliente_principal', 'invitado_apoderado'])
    loop
      perform encolar_notificacion(
        v_u, new.obra_id, 'certificado_emitido', new.id,
        'Certificado ' || v_num,
        coalesce(v_obra, 'Una obra') || ': hay un certificado nuevo para revisar.');
    end loop;
  end if;

  -- 2) Pagado -> a quien cobra. Mismo conjunto que la rama `certificado_pagado`.
  if new.estado = 'pagado' and old.estado is distinct from 'pagado' then
    for v_u in
      select * from destinatarios_notificacion(
        new.obra_id, array['admin_maestro', 'constructor'])
    loop
      perform encolar_notificacion(
        v_u, new.obra_id, 'certificado_pagado', new.id,
        'Certificado ' || v_num || ' pagado',
        coalesce(v_obra, 'Una obra') || ': registraron el pago del certificado.');
    end loop;
  end if;

  -- 4) Le respondieron la objeción -> al cliente, pero recién a las 24 h. La fila se crea ahora y
  --    queda fechada; quien la despierte es problema de la Tanda 3.
  if new.objecion_respuesta is not null and old.objecion_respuesta is null then
    for v_u in
      select * from destinatarios_notificacion(
        new.obra_id, array['cliente_principal', 'invitado_apoderado'])
    loop
      perform encolar_notificacion(
        v_u, new.obra_id, 'objecion_por_vencer', new.id,
        'Respondieron tu objeción',
        coalesce(v_obra, 'Una obra') || ': respondieron la objeción del certificado ' || v_num
          || '. Si no la levantás, se resuelve sola.',
        objecion_aviso_push_el(coalesce(new.objecion_respondida_fecha, now())));
    end loop;
  end if;

  return null;
end;
$$;

create trigger certificados_notificar
  after update on certificados
  for each row execute function notificar_transicion_certificado();


-- 3) Adicional aprobado -> a quien lo presentó. Acá el destinatario no es un rol: es una persona
--    concreta (`solicitado_por`), así que no pasa por `destinatarios_notificacion` -- pero la regla
--    de "no avisarle al que lo hizo" igual se aplica, porque vive en `encolar_notificacion`.
create or replace function notificar_adicional_aprobado()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_obra text;
begin
  if new.tipo <> 'adicional' then
    return null;
  end if;

  if new.estado = 'aprobado' and old.estado is distinct from 'aprobado' then
    select nombre into v_obra from obras where id = new.obra_id;
    perform encolar_notificacion(
      new.solicitado_por, new.obra_id, 'adicional_aprobado', new.id,
      'Adicional aprobado',
      coalesce(v_obra, 'Una obra') || ': aprobaron el adicional que presentaste.');
  end if;

  return null;
end;
$$;

create trigger modificaciones_obra_notificar
  after update on modificaciones_obra
  for each row execute function notificar_adicional_aprobado();


-- =====================================================================
-- Verificación a mano después de aplicar
-- =====================================================================
--
-- Todo se prueba sin Firebase: se mira la cola, no el envío.
--
-- 1) Que la cola arranca vacía y que nadie puede escribirla desde el cliente:
--    select count(*) from notificaciones;   -- 0
--    -- Y con los claims de un usuario cualquiera:
--    begin;
--      set local role authenticated;
--      set local request.jwt.claims = '{"sub":"<uuid>","role":"authenticated"}';
--      insert into notificaciones (usuario_id, obra_id, tipo, titulo, cuerpo)
--        values (auth.uid(), '<obra>', 'certificado_emitido', 'x', 'y');
--    rollback;
--    -- tiene que fallar por RLS: no hay política de INSERT.
--
-- 2) *** EL CASO PRINCIPAL, desde la app con dos usuarios: el profesional emite un certificado.
--    select tipo, usuario_id, titulo, cuerpo, enviar_despues_de from notificaciones
--    order by creada_en desc;
--    -- una fila por cliente/apoderado de la obra, con `enviar_despues_de` = ahora.
--    -- *** Y NINGUNA para el que emitió, aunque también sea cliente en esa obra.
--
-- 3) Pagar ese certificado (desde el cliente) -> una fila `certificado_pagado` para el
--    admin_maestro y el constructor, y ninguna para el cliente que pagó.
--
-- 4) Aprobar un adicional -> una fila `adicional_aprobado` para `solicitado_por`. Si el que aprueba
--    es el mismo que lo presentó, NINGUNA fila.
--
-- 5) *** EL EVENTO 4, que es el distinto: el técnico responde una objeción.
--    select tipo, enviar_despues_de, creada_en from notificaciones where tipo = 'objecion_por_vencer';
--    -- `enviar_despues_de` tiene que ser 24 h DESPUÉS de `creada_en`. Si diera igual, el push
--    -- saldría junto con la respuesta y no serviría de recordatorio.
--
-- 6) Que el libro NO empuja: escribir en el libro de obra y verificar que no aparece ninguna fila.
--    select count(*) from notificaciones where tipo like '%libro%';   -- 0, y no existe el tipo
--
-- 7) Que un rechazo no notifica: rechazar un adicional -> sin filas. Y anular un certificado
--    tampoco: el trigger solo mira las transiciones a 'emitido' y 'pagado'.
--
-- 8) Que encolar no puede tumbar una transición: es difícil de forzar a mano, pero conviene saber
--    que `encolar_notificacion` atrapa cualquier error y sigue -- si algún día una notificación no
--    aparece, mirar los `warning` del log de Postgres antes de sospechar del trigger.
--
-- 9) La delegación del apoderado: con una delegación VENCIDA, emitir un certificado no le tiene que
--    generar fila a ese apoderado (sí al cliente_principal).
--
-- 10) Limpieza de la prueba, si hace falta: `delete from notificaciones;` -- todavía no las lee
--     nadie, así que borrarlas no rompe nada.
