-- Corrige la divergencia entre `obras.id_admin_creador` (dueño único, patrón anterior a Etapa 3)
-- y el rol `admin_maestro` de `obra_members` (lo que el resto del proyecto considera la fuente
-- de verdad desde Etapa 3) — encontrada al construir el panel de configuración de certificación
-- (docs/modelos_certificacion_diseno_datos.md §8, ya la documentaba como limitación conocida) y
-- ya marcada también en `cambiar_modelo_certificacion` (0005) y en el fallback "obra sin acceso"
-- de `obra_subitems_repository.dart`.
--
-- Las 4 políticas de `obras` nunca tuvieron migración propia en este repo (igual que
-- `insumos`/`precios`/`corralones`, ver `docs/proveedores_digitales_bariloche.md` y
-- `0013_rls_proveedores_precios.sql` para el mismo tipo de deuda). Nombres y cláusulas exactas
-- confirmadas por el usuario contra `pg_policies` antes de escribir esto — no reconstruidas:
--
--   "Usuarios ven sus propias obras"     — select — using (id_admin_creador = auth.uid())
--   "Usuarios crean sus propias obras"   — insert — with check (id_admin_creador = auth.uid())
--   "Usuarios editan sus propias obras"  — update — using (id_admin_creador = auth.uid())
--                                                    with check (id_admin_creador = auth.uid())
--   "Usuarios eliminan sus propias obras" — delete — using (id_admin_creador = auth.uid())
--
-- Alcance: se tocan SELECT/UPDATE/DELETE. INSERT queda exactamente igual — ver la nota antes de
-- esa sección para el porqué.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

-- =====================================================================
-- Recursión — verificado, no asumido, antes de escribir política alguna
-- =====================================================================
--
-- tiene_rol_en_obra/is_obra_member (0004_rls_etapa3.sql) son SECURITY DEFINER: consultan
-- obra_members con los privilegios del dueño de la función, sin volver a disparar la RLS de
-- obra_members. Una política de `obras` que las llama no cierra ningún ciclo: obras -> (función
-- SECURITY DEFINER) -> obra_members, sin volver a tocar obras en ningún punto de esa cadena.
--
-- El único contacto cruzado real es al revés: obra_members_insert (0004, línea ~95) tiene una
-- subconsulta CRUDA contra obras (`exists (select 1 from obras o where o.id = obra_id and
-- o.id_admin_creador = auth.uid())`), sin pasar por ninguna función. Con el SELECT de obras ya
-- cambiado más abajo, esa subconsulta queda sujeta a la política nueva — tampoco cierra un ciclo:
-- obra_members_insert -> select obras (dispara el SELECT nuevo de obras) -> is_obra_member
-- (SECURITY DEFINER, no re-dispara RLS de obra_members) -> resuelve. Se resuelve, no se cicla.
-- No se toca obra_members_insert en esta migración — sigue funcionando igual, y hoy es casi
-- vestigial de todos modos (0033_obra_members_bootstrap.sql: ningún código en lib/ inserta nunca
-- en obra_members directamente, el trigger SECURITY DEFINER hace todo el trabajo real).

-- =====================================================================
-- id_admin_creador inmutable — trigger, no RLS
-- =====================================================================
--
-- El with_check actual de UPDATE hace doble trabajo: autoriza quién puede editar Y, de paso,
-- impide que ese update cambie id_admin_creador (si alguien intentara escribir un valor distinto,
-- el with_check fallaría porque la fila resultante ya no cumpliría "id_admin_creador = auth.uid()").
-- Si el with_check nuevo pasa a ser "tiene_rol_en_obra(id, 'admin_maestro') or id_admin_creador =
-- auth.uid()", esa segunda función se pierde para quien pasa por la primera rama: un admin_maestro
-- (vía rol, no dueño) podría reescribir id_admin_creador a cualquier valor, porque esa rama del
-- OR no dice nada sobre qué valor tiene que tener la columna en la fila nueva.
--
-- Postgres RLS no da acceso limpio a "el valor antes del update" dentro de una sola cláusula
-- using/with check (no hay OLD/NEW como en un trigger) — intentar compararlo con una subconsulta
-- contra la propia tabla desde dentro de su propia política es ambiguo y frágil. La herramienta
-- correcta para "esta columna es inmutable" es un trigger BEFORE UPDATE, con acceso limpio a
-- OLD/NEW, y como beneficio extra: a diferencia de RLS (que no aplica a superusuario/service_role),
-- un trigger SÍ se ejecuta siempre salvo que se deshabilite explícitamente — protección más fuerte
-- que la que había, no solo equivalente.
create or replace function proteger_id_admin_creador_inmutable()
returns trigger language plpgsql as $$
begin
  if new.id_admin_creador is distinct from old.id_admin_creador then
    raise exception 'id_admin_creador no se puede modificar después de creada la obra';
  end if;
  return new;
end;
$$;

create trigger obras_id_admin_creador_inmutable
  before update on obras
  for each row execute function proteger_id_admin_creador_inmutable();

-- =====================================================================
-- SELECT — abre a cualquier miembro de la obra, no solo al dueño
-- =====================================================================
--
-- Cierra de paso la cicatriz de obra_subitems_repository.dart (getNombresObrasConUso /
-- getNombresObrasConUsoDeSubitem): el fallback "obra sin acceso" existe ahí porque un colaborador
-- que no es id_admin_creador no podía leer el nombre de una obra donde igual es miembro. Con este
-- cambio, cualquier obra_id que esas consultas manejen ya viene de obra_subitems (SELECT
-- is_obra_member) o de la tabla equivalente por rubro — o sea que el usuario YA es is_obra_member
-- de todas ellas por construcción, así que ese fallback queda inalcanzable en la práctica. No se
-- modifica ese archivo Dart en esta migración: el fallback queda como código muerto inofensivo,
-- no como un bug — se puede limpiar en otro momento sin apuro, y su comentario va a quedar
-- desactualizado explicando un límite que ya no existe (anotado para no perderlo, no arreglado acá).
drop policy "Usuarios ven sus propias obras" on obras;

create policy "Usuarios ven sus propias obras" on obras for select
using (id_admin_creador = auth.uid() or is_obra_member(id));

-- =====================================================================
-- INSERT — sin cambios, a propósito
-- =====================================================================
--
-- Al crear una obra no existe todavía ninguna fila de obra_members a la que consultar — no hay
-- rol que verificar en ese momento, la única pregunta posible es "¿te estás nombrando creador a
-- vos mismo, o a otro?". No tiene el problema de divergencia que sí tienen las otras 3 (esas
-- resuelven "quién administra una obra ya existente"). Se deja exactamente como está, sin
-- DROP/CREATE — nombrada acá solo para que quede explícito que no se olvidó, no que se decidió
-- tocar y no se hizo.

-- =====================================================================
-- UPDATE — admin_maestro o dueño original, con id_admin_creador protegido por el trigger de arriba
-- =====================================================================
drop policy "Usuarios editan sus propias obras" on obras;

create policy "Usuarios editan sus propias obras" on obras for update
using (tiene_rol_en_obra(id, 'admin_maestro') or id_admin_creador = auth.uid())
with check (tiene_rol_en_obra(id, 'admin_maestro') or id_admin_creador = auth.uid());

-- =====================================================================
-- DELETE — mismo criterio que UPDATE, por consistencia (sin esto, un admin_maestro reasignado
-- podría editar una obra pero no borrarla, un hueco sin motivo real)
-- =====================================================================
drop policy "Usuarios eliminan sus propias obras" on obras;

create policy "Usuarios eliminan sus propias obras" on obras for delete
using (tiene_rol_en_obra(id, 'admin_maestro') or id_admin_creador = auth.uid());

-- =====================================================================
-- Verificación
-- =====================================================================

-- 1) Las 4 políticas con su texto nuevo — SELECT/UPDATE/DELETE deberían mostrar el OR con
--    tiene_rol_en_obra/is_obra_member; INSERT tiene que seguir mostrando exactamente lo mismo
--    que antes de esta migración.
select policyname, cmd, qual, with_check
from pg_policies
where schemaname = 'public' and tablename = 'obras'
order by cmd;

-- 2) El trigger de inmutabilidad tiene que existir.
select tgname, tgenabled
from pg_trigger
where tgrelid = 'public.obras'::regclass and not tgisinternal;

-- 3) Caso real, con una obra tuya de prueba: reemplazá :obra_id por una obra donde SEAS
--    admin_maestro pero NO seas id_admin_creador (si no tenés ninguna obra en esa situación
--    todavía, este caso es exactamente el que la migración deja de romper — no hay forma de
--    probarlo hasta que exista un segundo admin_maestro real). Antes de esta migración fallaba
--    con "new row violates row-level security policy"; después tiene que dejar pasar el update.
--
-- update obras set nombre = nombre where id = :obra_id;

-- 4) Confirmar que el trigger bloquea el cambio de id_admin_creador incluso para quien SÍ puede
--    editar la obra por cualquiera de las dos ramas — tiene que fallar con el mensaje del
--    trigger, no en silencio y no con un error de RLS distinto.
--
-- update obras set id_admin_creador = gen_random_uuid() where id = :obra_id;
