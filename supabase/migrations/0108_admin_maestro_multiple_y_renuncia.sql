-- Decisión de Seba (2026-09-11), a partir de encontrar que el gate de Editar/Ajuste Económico/
-- Eliminar Obra (ObrasListScreen, construido con `id_admin_creador`) no reflejaba la realidad:
-- "hoy el creador es dueño para siempre y si deja el proyecto la obra queda sin nadie que la
-- administre". Dos cosas juntas:
--
-- 1) Puede haber varios `admin_maestro` -- la tabla ya lo soporta (roles combinables,
--    `unique(obra_id, usuario_id, rol)`, no un dueño único), lo que faltaba era la función para
--    otorgar el rol a otro miembro ya existente.
-- 2) Un `admin_maestro` puede renunciar a su rol -- esto YA funciona del lado de datos, sin
--    cambios acá: `quitar_miembro_obra` (`0098`) ya tiene exactamente la guarda pedida ("no puede
--    irse el último administrador... primero tiene que nombrar a otro", `0098` línea ~53) y su
--    chequeo de autoridad (`tiene_rol_en_obra(obra_id,'admin_maestro')`) ya lo satisface el propio
--    renunciante sobre SU PROPIA fila. Lo que falta para que "esa obra desaparezca de su perfil"
--    sea cierto es el punto 2 de abajo.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor), después de `0107`. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

-- =====================================================================
-- Paso 1 -- otorgar_admin_maestro: el otro lado de "puede haber varios administradores"
-- =====================================================================
--
-- La política INSERT de `obra_members` (`0004_rls_etapa3.sql`) ya deja que un `admin_maestro`
-- inserte cualquier fila nueva (`tiene_rol_en_obra(obra_id,'admin_maestro')` en el `with check`)
-- -- un `insert` directo ya pasaría la RLS. Esta función no existe por un hueco de permisos, sino
-- por el mismo motivo que `quitar_miembro_obra` existe siendo un caso ya cubierto por
-- `obra_members_update`: registrar la acción en `audit_log` de forma garantizada, y acá además
-- resolver limpio el caso "la persona ya tuvo admin_maestro antes y se le revocó" (reactivar en
-- vez de chocar contra el `unique(obra_id, usuario_id, rol)`).
create or replace function otorgar_admin_maestro(p_obra_id uuid, p_usuario_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not tiene_rol_en_obra(p_obra_id, 'admin_maestro') then
    raise exception 'No tenés permiso para nombrar administradores en esta obra.';
  end if;

  insert into obra_members (obra_id, usuario_id, rol, invitado_por_usuario_id, activo)
  values (p_obra_id, p_usuario_id, 'admin_maestro', auth.uid(), true)
  on conflict (obra_id, usuario_id, rol) do update set activo = true;

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (
    p_obra_id, auth.uid(), 'otorgar_admin_maestro', 'obra_member', null,
    jsonb_build_object('usuario_id', p_usuario_id)
  );
end;
$$;

grant execute on function otorgar_admin_maestro(uuid, uuid) to authenticated;

-- =====================================================================
-- Paso 2 -- obras: SELECT/UPDATE/DELETE dejan de aceptar id_admin_creador como acceso permanente
-- =====================================================================
--
-- Esto es lo que de verdad hacía que "el creador sea dueño para siempre": aunque alguien
-- renunciara a `admin_maestro` (paso ya posible hoy, ver cabecera), `id_admin_creador` seguía
-- siendo suyo para siempre (columna inmutable, trigger `0051`) y las 3 políticas seguían dejándolo
-- pasar por esa rama del OR -- la obra nunca desaparecía de su perfil, y podía seguir editándola/
-- borrándola, sin importar que ya no tuviera ningún rol activo. `id_admin_creador` sigue existiendo
-- (registro histórico de quién creó la obra, sigue protegido por su propio trigger de
-- inmutabilidad) -- deja de ser una vía de acceso, nada más. INSERT no se toca -- mismo motivo que
-- ya documentó `0051`: al crear la obra todavía no existe ninguna fila de `obra_members` contra la
-- que verificar rol.
--
-- Seguro contra el caso "obra recién creada": `0033_obra_members_bootstrap.sql` es un trigger
-- `AFTER INSERT ON obras` -- corre en la misma transacción, antes de que el `.select()` que
-- `ObrasRepository.crearObra()` encadena evalúe esta política nueva. El creador ya es
-- `admin_maestro` (vía `obra_members`) para el momento en que `is_obra_member` se evalúa acá.
drop policy "Usuarios ven sus propias obras" on obras;
create policy "Usuarios ven sus propias obras" on obras for select
using (is_obra_member(id));

drop policy "Usuarios editan sus propias obras" on obras;
create policy "Usuarios editan sus propias obras" on obras for update
using (tiene_rol_en_obra(id, 'admin_maestro'))
with check (tiene_rol_en_obra(id, 'admin_maestro'));

drop policy "Usuarios eliminan sus propias obras" on obras;
create policy "Usuarios eliminan sus propias obras" on obras for delete
using (tiene_rol_en_obra(id, 'admin_maestro'));

-- =====================================================================
-- Verificación
-- =====================================================================
--
-- 1) Las 3 políticas ya no mencionan id_admin_creador; INSERT sigue exactamente igual.
select policyname, cmd, qual, with_check
from pg_policies
where schemaname = 'public' and tablename = 'obras'
order by cmd;
--
-- 2) Crear una obra de prueba -- el `.select()` que sigue al insert tiene que devolver la fila
--    sin error (confirma que el trigger de bootstrap corrió a tiempo).
--
-- 3) Caso real: en una obra con 2 admin_maestro activos, uno de los dos ejecuta
--    quitar_miembro_obra sobre SU PROPIA fila -- tiene que funcionar (ya funcionaba antes de esta
--    migración), y la obra tiene que dejar de aparecer en su `select * from obras` inmediatamente
--    después (antes de esta migración, seguía apareciendo por id_admin_creador).
--
-- 4) Mismo caso pero con un solo admin_maestro: quitar_miembro_obra sobre esa única fila tiene que
--    rechazar con el mensaje ya existente ("No se puede sacar al único administrador...") -- sin
--    cambios de comportamiento acá, es la guarda de la 0098.
--
-- 5) otorgar_admin_maestro(obra_id, usuario_id) desde una cuenta que NO es admin_maestro de esa
--    obra -- tiene que rechazar con "No tenés permiso para nombrar administradores en esta obra."
