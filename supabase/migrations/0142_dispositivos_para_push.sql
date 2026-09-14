-- 0142 -- Tanda 1 de las notificaciones: dónde vive el token de cada teléfono
--
-- Diagnóstico completo y las 5 tandas: docs/notificaciones_push_diagnostico.md.
--
-- **Esta migración no manda ninguna notificación, y no depende de Firebase.** Es la mitad de SQL de
-- la Tanda 1: la tabla donde se guarda el token de cada dispositivo y las dos funciones que lo
-- registran y lo borran. La otra mitad (Flutter + `firebase_messaging`) **está bloqueada hasta que
-- exista el proyecto de Firebase** -- ver la nota al final.
--
-- Se puede aplicar sin comprometerse a nada: si al mirar el uso real el aviso adentro de la app
-- alcanza y se decide no seguir (opción C de Seba), esto es un `drop table` y no dejó rastro en
-- ninguna otra pieza.
--
-- ================== LOS EVENTOS, DECIDIDOS (no se usan todavía) ==================
--
-- Cerrado por Seba el 2026-09-14, y queda escrito acá porque es lo que la Tanda 2 va a implementar:
--
--   1. **certificado emitido**   -> al cliente (o su apoderado)
--   2. **adicional aprobado**    -> a quien lo presentó
--   3. **certificado pagado**    -> a quien cobra (admin_maestro / constructor)
--   4. **vencimiento de objeción cerca** -> al cliente, que es quien la tiene que levantar
--
-- Los tres primeros con el mismo criterio, textual: *"todos son de plata, y el que espera plata
-- tiene que enterarse"*. El cuarto lo sumó por el plazo: *"son cinco días, si alguien tarda tres en
-- abrir la app ya se comió más de la mitad"*.
--
-- OJO CON EL CUARTO, y conviene saberlo antes de la Tanda 2: **el aviso de vencimiento de la
-- objeción YA EXISTE adentro de la app desde la `0131`**. La rama `objecion_respondida` de
-- `mis_pendientes()` devuelve `vence` a partir de las 24 h del aviso, y el cartel muestra
-- *"respondida el 12/09 · se resuelve sola el 17/09"*. Lo que falta no es el aviso: es que salga del
-- teléfono sin abrir la app. Por eso no entra en esta tanda, que no manda nada.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project -> SQL Editor), después de `0141`. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.


-- =====================================================================
-- Paso 1 -- la tabla
-- =====================================================================
--
-- Una fila por **dispositivo**, no por usuario: la misma persona tiene el teléfono y la tablet, y un
-- aviso tiene que llegar a los dos. Por eso es tabla y no una columna en `perfiles`.
--
-- **`unique (token)` y no `unique (usuario_id, token)`**, que es la parte que se piensa mal: el
-- token identifica **una instalación de la app en un aparato**, no a una persona. Si en ese teléfono
-- se cierra sesión y entra otro usuario, FCM devuelve el MISMO token -- y si la fila vieja quedara,
-- el aparato seguiría recibiendo las notificaciones del usuario anterior. Con `unique (token)`, el
-- registro del paso 2 se lo transfiere al nuevo dueño en vez de duplicarlo.
--
-- `plataforma` no se usa todavía: el mensaje de FCM se arma distinto para Android y para iOS, y
-- cuando haya iOS la Edge Function va a necesitar saberlo sin tener que adivinarlo del token.

create table dispositivos (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  token text not null unique,
  plataforma text not null check (plataforma in ('android', 'ios', 'web')),
  creado_en timestamptz not null default now(),
  ultima_vez_visto timestamptz not null default now()
);

create index dispositivos_usuario_idx on dispositivos (usuario_id);

comment on table dispositivos is
  'Token de push (FCM) por dispositivo -- Tanda 1 de las notificaciones (0142). Una fila por '
  'aparato, no por persona. unique(token) a proposito: el token identifica la instalacion, asi que '
  'si en ese telefono entra otro usuario, la fila CAMBIA DE DUENO en vez de duplicarse -- si no, el '
  'aparato seguiria recibiendo los avisos del anterior.';

comment on column dispositivos.ultima_vez_visto is
  'Se actualiza en cada arranque de la app. Sirve para limpiar tokens de aparatos que no aparecen '
  'hace meses, ademas de los que FCM marque como muertos (Tanda 4).';

alter table dispositivos enable row level security;

-- Cada uno ve y borra solo sus propios dispositivos. Nadie tiene por qué saber con qué aparatos
-- entra otro, ni siquiera el admin_maestro de una obra: esto no es de la obra, es de la persona.
create policy dispositivos_select on dispositivos for select
using (usuario_id = auth.uid());

create policy dispositivos_delete on dispositivos for delete
using (usuario_id = auth.uid());

-- Sin políticas de INSERT ni UPDATE: se escribe solo por la función del paso 2, que es la única que
-- sabe transferir un token de un usuario a otro.


-- =====================================================================
-- Paso 2 -- registrar y borrar
-- =====================================================================
--
-- **`registrar_dispositivo` se llama en CADA ARRANQUE de la app, no solo al iniciar sesión.** Un
-- token de FCM no es estable: cambia al reinstalar, al borrar los datos de la app, y a veces solo
-- porque FCM lo rota. Registrarlo únicamente en el login deja aparatos con tokens muertos que no
-- reciben nada y nadie se entera -- el fallo más típico de esta clase de pieza, y el más difícil de
-- notar, porque no falla nada visible: simplemente no llega.
--
-- El `on conflict (token)` es el que hace la transferencia de dueño descrita en el paso 1.

create or replace function registrar_dispositivo(p_token text, p_plataforma text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'sin sesión no se registra ningún dispositivo';
  end if;

  if p_token is null or btrim(p_token) = '' then
    raise exception 'el token del dispositivo no puede venir vacío';
  end if;

  if p_plataforma not in ('android', 'ios', 'web') then
    raise exception 'plataforma desconocida: %', p_plataforma;
  end if;

  insert into dispositivos (usuario_id, token, plataforma)
  values (auth.uid(), btrim(p_token), p_plataforma)
  on conflict (token) do update
    set usuario_id = auth.uid(),
        plataforma = excluded.plataforma,
        ultima_vez_visto = now();
end;
$$;

grant execute on function registrar_dispositivo(text, text) to authenticated;
revoke execute on function registrar_dispositivo(text, text) from public, anon;

-- Al cerrar sesión. **Es importante que se llame antes del signOut**, no después: con la sesión ya
-- cerrada `auth.uid()` es null y el borrado no matchea nada, y el aparato se queda recibiendo los
-- avisos de quien se acaba de ir.
create or replace function borrar_dispositivo(p_token text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from dispositivos
  where token = p_token and usuario_id = auth.uid();
end;
$$;

grant execute on function borrar_dispositivo(text) to authenticated;
revoke execute on function borrar_dispositivo(text) from public, anon;


-- =====================================================================
-- Lo que falta para cerrar la Tanda 1 -- y está bloqueado, no pendiente
-- =====================================================================
--
-- La otra mitad es Flutter: `firebase_messaging`, el permiso de Android 13+
-- (`POST_NOTIFICATIONS`) y llamar a `registrar_dispositivo` en cada arranque. **No se puede escribir
-- todavía**, y no por falta de tiempo: sin un proyecto de Firebase creado no hay
-- `google-services.json`, y sin ese archivo el build de Android **falla al compilar** -- no es que
-- ande a medias, no compila.
--
-- Lo que hace falta, en orden (es la Tanda 0 del diagnóstico, unos minutos en la consola):
--
--   1. crear un proyecto en console.firebase.google.com;
--   2. agregarle una app Android con el applicationId del proyecto
--      (`com.example.mi_primera_app`, en android/app/build.gradle.kts -- **conviene cambiarlo antes**:
--      `com.example.*` no se puede publicar en Play, y el applicationId no se cambia después sin
--      perder la app);
--   3. bajar `google-services.json` y ponerlo en `android/app/`.
--
-- Con eso, la mitad de Flutter son unas pocas líneas y la Tanda 1 queda cerrada.


-- =====================================================================
-- Verificación a mano después de aplicar
-- =====================================================================
--
-- Todo esto corre sin Firebase: se prueba la tabla, no el envío.
--
-- 1) Registrar, haciéndose pasar por un usuario (truco de los claims de la 0130):
--    begin;
--      set local role authenticated;
--      set local request.jwt.claims = '{"sub":"<uuid de slosav>","role":"authenticated"}';
--      select registrar_dispositivo('token-de-prueba-1', 'android');
--      select usuario_id, plataforma, token from dispositivos;
--    commit;
--
-- 2) Que llamarla dos veces con el mismo token NO duplique: correr el registrar dos veces y que
--    `select count(*) from dispositivos` siga en 1, con `ultima_vez_visto` actualizado.
--
-- 3) *** LA TRANSFERENCIA DE DUEÑO, que es el punto del `unique (token)`: registrar el MISMO token
--    desde otro usuario (otro `sub` en los claims) y verificar que la fila sigue siendo UNA y que
--    cambió de `usuario_id`. Si aparecieran dos filas, ese teléfono recibiría los avisos de los dos.
--
-- 4) Que nadie vea los dispositivos de otro:
--    begin;
--      set local role authenticated;
--      set local request.jwt.claims = '{"sub":"<uuid de seba2135>","role":"authenticated"}';
--      select count(*) from dispositivos;   -- solo los suyos
--    rollback;
--
-- 5) El borrado: `select borrar_dispositivo('token-de-prueba-1');` con el dueño -> se va. Con otro
--    usuario -> no borra nada (0 filas afectadas, sin error).
--
-- 6) Limpieza de la prueba: `delete from dispositivos where token like 'token-de-prueba-%';`
