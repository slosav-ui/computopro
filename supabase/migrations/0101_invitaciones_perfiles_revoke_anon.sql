-- Mismo hallazgo que 0085_hardening_seguridad_linter_supabase.sql, esta vez sobre las funciones
-- de invitaciones/perfiles (0095-0100): Postgres otorga EXECUTE a PUBLIC automáticamente al crear
-- una función, y PUBLIC incluye a `anon`. El `grant execute ... to authenticated` que ya tiene
-- cada una es aditivo, nunca reemplaza ese otorgamiento implícito -- por eso el linter de Supabase
-- volvió a marcarlas. Ninguna de las cinco de abajo tiene sentido sin sesión: todas dependen de
-- `auth.uid()` (autenticación) o de pertenencia a una obra concreta, y devolverían un error o un
-- resultado sin sentido para `anon` de cualquier forma -- pero un `permission denied` explícito en
-- el nivel de Postgres es la defensa correcta, no confiar en que la lógica interna alcance.
--
-- `from public, anon` en los dos, no uno solo -- lección ya aprendida en 0085 (corrección de Seba
-- al aplicarla): un `revoke ... from public` no alcanza porque `anon` tenía además un `grant`
-- directo (de la configuración default del proyecto Supabase, no de ninguna migración de este
-- repo) -- un revoke de PUBLIC no toca un grant directo a un rol específico, hacen falta los dos
-- en la misma sentencia.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

revoke execute on function aceptar_invitacion(text) from public, anon;
revoke execute on function revocar_invitacion(uuid) from public, anon;
revoke execute on function quitar_miembro_obra(uuid) from public, anon;
revoke execute on function actualizar_mi_perfil(text, text, text) from public, anon;
revoke execute on function get_perfiles_de_obra(uuid) from public, anon;

-- =====================================================================
-- previsualizar_invitacion: NO se revoca -- abierta a `anon` a propósito
-- =====================================================================
--
-- Es la única excepción deliberada de todo el proyecto (ver
-- `0096_invitaciones_previsualizar.sql`, que ya dejó el `grant ... to authenticated, anon`
-- explícito). Motivo, para que nadie la cierre en una futura pasada del linter sin entender por
-- qué: quien pega un código de invitación puede no tener cuenta todavía -- es exactamente el caso
-- de uso central de esta pieza (`docs/invitaciones_diseno_datos.md` §7). Necesita poder ver "te
-- invitaron a la obra X como Y" ANTES de registrarse, para que `AceptarInvitacionScreen` tenga
-- algo que mostrar en ese momento. Es de solo lectura, sin efecto, y solo devuelve
-- `obra_nombre`/`rol` -- nunca datos sensibles (ver el propio cuerpo de la función: nada de
-- `perfiles`, nada de `es_pro`, nada de montos). El riesgo residual (alguien adivinando códigos a
-- ciegas) está documentado y aceptado en `docs/invitaciones_diseno_datos.md` §5/§7 -- el espacio
-- de 8 caracteres es la defensa real, no el `grant`.
comment on function previsualizar_invitacion(text) is
  'Abierta a anon a propósito -- quien pega un código puede no tener cuenta todavía. Ver '
  '0101_invitaciones_perfiles_revoke_anon.sql antes de revocarle el acceso.';

-- =====================================================================
-- generar_codigo_invitacion: search_path fijo -- el linter también la marcó
-- =====================================================================
--
-- No es SECURITY DEFINER (no toca datos privilegiados, solo arma un string al azar), así que no
-- tiene el riesgo de fondo que motiva el resto de esta migración -- pero el linter de Supabase
-- marca cualquier función sin `search_path` fijo, sea o no SECURITY DEFINER, como hardening
-- estándar contra search_path hijacking. Mismo criterio que el resto del proyecto (`0085` paso 3).
-- Sin cambio de firma (sin parámetros, mismo tipo de retorno) -- CREATE OR REPLACE alcanza.
create or replace function generar_codigo_invitacion()
returns text language plpgsql set search_path = public as $$
declare
  v_alfabeto text := '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
  v_codigo text := '';
begin
  for i in 1..8 loop
    v_codigo := v_codigo || substr(v_alfabeto, 1 + floor(random() * length(v_alfabeto))::int, 1);
  end loop;
  return v_codigo;
end;
$$;

-- =====================================================================
-- Verificación (correr a mano después de aplicar, no parte de la migración)
-- =====================================================================
--
-- 1) Las cinco funciones revocadas no ejecutables por anon:
-- select proname, has_function_privilege('anon', oid, 'EXECUTE') as anon_puede
-- from pg_proc
-- where proname in (
--   'aceptar_invitacion', 'revocar_invitacion', 'quitar_miembro_obra',
--   'actualizar_mi_perfil', 'get_perfiles_de_obra'
-- );
-- -- Las cinco filas tienen que dar anon_puede = false.
--
-- 2) previsualizar_invitacion sigue abierta:
-- select has_function_privilege('anon', 'previsualizar_invitacion(text)'::regprocedure, 'EXECUTE');
-- -- Tiene que dar true -- si da false, algo revocó esta función por error.
--
-- 3) generar_codigo_invitacion con search_path fijo:
-- select proname, proconfig from pg_proc where proname = 'generar_codigo_invitacion';
-- -- proconfig tiene que mostrar {search_path=public}.
