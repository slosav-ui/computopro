-- 0144 -- Una sola definición de la delegación del apoderado
--
-- **Esta migración no agrega ninguna funcionalidad. No hace nada más que esto.** Es a propósito:
-- toca `tiene_rol_en_obra`, que evalúan las políticas RLS de casi todas las tablas del proyecto,
-- fila por fila. Si algo se rompe después de aplicarla, hay una sola causa posible.
--
-- ================== QUÉ ARREGLA ==================
--
-- La regla de la delegación del apoderado —*sin ninguna de las dos fechas, permanente; con las dos,
-- tiene que caer en el rango; con una sola cargada, no vigente*— estaba escrita **dos veces**: en
-- `tiene_rol_en_obra` (0004) y en `destinatarios_notificacion` (0143).
--
-- No es una duplicación teórica: **este proyecto ya se quemó exactamente con esta regla**. Hasta el
-- 2026-09-13 convivían dos helpers en Dart, y el viejo trataba "sin fechas" como NO vigente — un
-- apoderado con delegación permanente no podía marcar Leído ni Pagado en la app aunque el servidor
-- sí lo autorizaba. Se borró el viejo y quedó uno solo para que no pudiera volver a pasar. Dejarla
-- duplicada del lado de SQL era volver a poner la trampa, en el lugar donde además nadie la ve.
--
-- ================== CÓMO, SIN CAMBIAR NADA DE COMPORTAMIENTO ==================
--
-- Una función canónica, `miembros_con_roles`, y las otras dos pasan a definirse en términos de ella:
--
--   miembros_con_roles(obra, roles[])  ->  quiénes tienen alguno de esos roles, con la delegación
--                                          aplicada. Es la regla, y ahora vive acá y en ningún lado más.
--   tiene_rol_en_obra(obra, rol)       ->  ¿el que mira está en esa lista?
--   destinatarios_notificacion(...)    ->  esa lista, menos el que disparó el hecho.
--
-- **`miembros_con_roles` NO es `security definer`, y eso es deliberado**: la llaman dos funciones que
-- sí lo son, y adentro de una `security definer` el usuario efectivo ya es el dueño, así que la RLS
-- de `obra_members` no muerde igual. Hacerla definer sumaría un cambio de contexto por llamada en
-- algo que se evalúa fila por fila, sin ganar nada. Igual se le revoca el `execute` a `authenticated`:
-- nadie tiene por qué llamarla suelta.
--
-- Lo que **no** cambia: la firma de `tiene_rol_en_obra`, sus permisos, y el conjunto de usuarios que
-- devuelve para cualquier entrada. Por eso no hay que tocar ni una política -- `create or replace`
-- sobre una función que usan las policies no las invalida mientras la firma sea la misma.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project -> SQL Editor), después de `0143`. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.


-- =====================================================================
-- Paso 1 -- la regla, una sola vez
-- =====================================================================
--
-- Copiada textual de `tiene_rol_en_obra` (0004), que es la que estuvo en producción todo este
-- tiempo: la que manda es esa, no la de la 0143.

create or replace function miembros_con_roles(p_obra_id uuid, p_roles text[])
returns setof uuid
language sql
stable
set search_path = public
as $$
  select distinct m.usuario_id
  from obra_members m
  where m.obra_id = p_obra_id
    and m.activo
    and m.rol = any (p_roles)
    and (
      m.rol <> 'invitado_apoderado'
      or (m.delegacion_inicio is null and m.delegacion_fin is null)
      or now() between m.delegacion_inicio and m.delegacion_fin
    );
$$;

comment on function miembros_con_roles(uuid, text[]) is
  'UNICA definicion de "quien tiene tal rol en tal obra", con la regla de la delegacion del '
  'apoderado adentro (0144). tiene_rol_en_obra y destinatarios_notificacion se definen en terminos '
  'de esta: no volver a escribir la regla en ningun otro lado.';

revoke execute on function miembros_con_roles(uuid, text[]) from public, anon, authenticated;


-- =====================================================================
-- Paso 2 -- las dos que la usan
-- =====================================================================
--
-- Misma firma, mismos permisos, mismo resultado. `security definer` y `set search_path` se
-- conservan tal cual estaban: son lo que permite que las políticas RLS la llamen sin caer en su
-- propia RLS en bucle.

create or replace function tiene_rol_en_obra(p_obra_id uuid, p_rol text)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from miembros_con_roles(p_obra_id, array[p_rol]) u where u = auth.uid()
  );
$$;

create or replace function destinatarios_notificacion(p_obra_id uuid, p_roles text[])
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  -- La otra regla de esta función, que no se movió: a nadie se le avisa de lo que acaba de hacer él
  -- mismo.
  select u from miembros_con_roles(p_obra_id, p_roles) u
  where u is distinct from auth.uid();
$$;


-- =====================================================================
-- Verificación a mano después de aplicar
-- =====================================================================
--
-- 1) *** QUE NO CAMBIÓ NADA, comparando la función contra la regla escrita a mano. Esto recorre
--    TODAS las membresías reales y tiene que devolver **cero filas**: cada una donde la función y la
--    regla no coincidan es una divergencia.
--
--    select m.obra_id, m.usuario_id, m.rol,
--           exists (select 1 from miembros_con_roles(m.obra_id, array[m.rol]) u
--                   where u = m.usuario_id) as dice_la_funcion,
--           (m.activo and (
--              m.rol <> 'invitado_apoderado'
--              or (m.delegacion_inicio is null and m.delegacion_fin is null)
--              or now() between m.delegacion_inicio and m.delegacion_fin
--            )) as dice_la_regla
--    from obra_members m
--    where exists (select 1 from miembros_con_roles(m.obra_id, array[m.rol]) u
--                  where u = m.usuario_id)
--       is distinct from
--          (m.activo and (
--             m.rol <> 'invitado_apoderado'
--             or (m.delegacion_inicio is null and m.delegacion_fin is null)
--             or now() between m.delegacion_inicio and m.delegacion_fin
--           ));
--
-- 2) El caso que originó todo, con un apoderado real: **delegación sin ninguna de las dos fechas**
--    tiene que dar vigente.
--    select * from miembros_con_roles('<obra>', array['invitado_apoderado']);
--    -- y con una sola fecha cargada, NO tiene que aparecer.
--
-- 3) Que `tiene_rol_en_obra` sigue contestando lo mismo, desde la app: entrar con cada rol y
--    verificar que ve y puede lo mismo que antes. **Es la prueba que más importa**: esta función la
--    usan las policies de casi todas las tablas, así que un error acá no se ve como un error, se ve
--    como "me desapareció una obra" o "no me deja pagar".
--
-- 4) Y que no quedó una tercera copia dando vueltas:
--    select proname from pg_proc
--    where prosrc like '%delegacion_inicio is null and delegacion_fin is null%'
--       or prosrc like '%delegacion_inicio is null%';
--    -- tiene que devolver SOLO `miembros_con_roles`. Si aparece otra, es la próxima a unificar.
--
-- 5) Si algo anduviera notablemente más lento después de esto (que no debería: es una llamada más,
--    sin cambio de contexto de seguridad), la consulta para mirarlo es un `explain analyze` sobre un
--    `select` de una tabla con RLS -- por ejemplo `certificados` -- antes y después.
