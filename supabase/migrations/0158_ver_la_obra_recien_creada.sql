-- =====================================================================
-- 0158 — El creador puede ver la obra en el instante en que la crea
-- =====================================================================
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.
--
-- =====================================================================
-- QUÉ ARREGLA
-- =====================================================================
--
-- Desde el 11 de septiembre no se puede crear ninguna obra desde la app. El error real, tapado
-- hasta hoy por un cartel genérico:
--
--     ERROR 42501: new row violates row-level security policy for table "obras"
--
-- La `0108` dejó la política de SELECT de `obras` en `is_obra_member(id)` solamente, sacándole la
-- rama del creador que traía la `0051`. Y escribió que era seguro, con este razonamiento:
--
--     "0033 es un trigger AFTER INSERT ON obras, corre en la misma transacción, ANTES de que el
--      .select() que encadena crearObra() evalúe esta política nueva."
--
-- **Ese razonamiento es falso.** La app no hace un SELECT aparte: PostgREST pide la fila con la
-- misma orden, en un RETURNING, y Postgres evalúa el RETURNING **antes** de correr los triggers
-- AFTER INSERT. En ese momento el creador todavía no es miembro de nada, la lectura se rechaza, y
-- como es una sola orden se cae el alta entera.
--
-- Comprobado por Seba: el mismo insert SIN returning pasa; con returning, 42501.
--
-- =====================================================================
-- LA DECISIÓN DE LA 0108 NO SE REVIERTE
-- =====================================================================
--
-- No se vuelve a "el creador ve la obra para siempre". El profesional que arma la obra tiene que
-- poder traspasar la administración y retirarse, y al irse deja de verla.
--
-- Lo único que se repara es el instante del alta: **el creador ve la obra mientras la obra no
-- tenga ningún miembro activo**. Esa ventana la abre el RETURNING y la cierra el propio trigger de
-- la 0033, dentro de la misma transacción.
--
-- Traspasar la obra NO la reabre: apenas hay un miembro activo, la rama del creador se apaga.
--
-- Y editar y borrar siguen pidiendo `admin_maestro`, sin cambios: si una obra quedara sin miembros,
-- el creador la ve pero no la puede modificar ni borrar.
--
-- **Por qué hace falta una función y no se escribe inline**: la subconsulta tiene que referirse a
-- la obra de la fila, y dentro de una política eso se rompe cuando la tabla se usa con un alias.
-- Mismo motivo por el que ya existen `is_obra_member` y `tiene_rol_en_obra`.

-- =====================================================================
-- 1 — la función auxiliar
-- =====================================================================
--
-- `activo` igual que `is_obra_member`, a propósito: si una obra quedara con miembros pero todos
-- inactivos, nadie la vería. Con este criterio la ve al menos quien la creó, que es reparación y
-- no filtración -- no puede editarla igual.

create or replace function obra_sin_miembros_activos(p_obra_id uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select not exists (
    select 1 from obra_members
    where obra_id = p_obra_id and activo
  );
$$;

revoke execute on function obra_sin_miembros_activos(uuid) from public, anon;
grant execute on function obra_sin_miembros_activos(uuid) to authenticated;


-- =====================================================================
-- 2 — SELECT: lo único que cambia
-- =====================================================================

drop policy if exists "Usuarios ven sus propias obras" on obras;

create policy "Usuarios ven sus propias obras" on obras for select
using (
  is_obra_member(id)
  or (id_admin_creador = auth.uid() and obra_sin_miembros_activos(id))
);


-- =====================================================================
-- 3 — INSERT: sin cambios de lógica, solo queda escrita en el repositorio
-- =====================================================================
--
-- Hasta hoy esta política existía únicamente en la base: es de antes de las migraciones y nunca se
-- versionó. Se recrea EXACTAMENTE con la misma regla que tiene hoy.
--
-- El bloque de abajo borra la que haya, sin depender de su nombre -- que no está registrado en
-- ningún lado -- y deja una sola, con nombre conocido. Correr el archivo entero de una sola vez:
-- entre el borrado y la creación, el alta de obras queda cerrada.

do $bloque$
declare
  v_nombre text;
begin
  for v_nombre in
    select policyname from pg_policies
    where schemaname = 'public' and tablename = 'obras' and cmd = 'INSERT'
  loop
    execute format('drop policy %I on obras', v_nombre);
  end loop;
end;
$bloque$;

create policy "Usuarios crean sus propias obras" on obras for insert
with check (id_admin_creador = auth.uid());


-- =====================================================================
-- 4 — UPDATE y DELETE: idénticas a como están hoy
-- =====================================================================
--
-- Se recrean sin tocar su lógica ni su nombre. Van acá solo para que las cuatro queden juntas y
-- escritas: hoy hay que leer tres migraciones distintas para saber qué permite cada una.

drop policy if exists "Usuarios editan sus propias obras" on obras;

create policy "Usuarios editan sus propias obras" on obras for update
using (tiene_rol_en_obra(id, 'admin_maestro'))
with check (tiene_rol_en_obra(id, 'admin_maestro'));

drop policy if exists "Usuarios eliminan sus propias obras" on obras;

create policy "Usuarios eliminan sus propias obras" on obras for delete
using (tiene_rol_en_obra(id, 'admin_maestro'));


-- =====================================================================
-- Verificación
-- =====================================================================
--
-- 1) Las cuatro políticas, con su regla:
--
--      select policyname, cmd, qual, with_check
--      from pg_policies where schemaname = 'public' and tablename = 'obras' order by cmd;
--
--    Tienen que ser CUATRO filas, una por cmd:
--      DELETE  qual: tiene_rol_en_obra(id, 'admin_maestro')
--      INSERT  with_check: (id_admin_creador = auth.uid())
--      SELECT  qual: is_obra_member(id) OR (id_admin_creador = auth.uid() AND obra_sin_miembros_activos(id))
--      UPDATE  qual y with_check: tiene_rol_en_obra(id, 'admin_maestro')
--
--    Si aparecen DOS filas con cmd = INSERT, el bloque del paso 3 no corrió: borrá a mano la que
--    no se llame "Usuarios crean sus propias obras".
--
-- 2) El alta real, con returning, simulando la sesión de slosav. Tiene que devolver una fila con
--    un id y el nombre PRUEBA DIAGNOSTICO, y el rollback la descarta:
--
--      begin;
--      select set_config('request.jwt.claims',
--        '{"sub":"c96787da-2c8d-44a2-baa9-de8bb2d83af3","role":"authenticated"}', true);
--      set local role authenticated;
--      insert into obras (
--        nombre, propietario, ubicacion, tipo_obra, perfil_creador, monto_total, superficie_m2,
--        estado, moneda, aplica_cac, mes_base_cac, revision, estado_servicio_especial, id_admin_creador
--      ) values (
--        'PRUEBA DIAGNOSTICO', 'Sin Especificar', 'Ubicación Faltante', 'Residencial',
--        'Director de Obra', 0, 100, 'Cotización', 'ARS', true,
--        date_trunc('month', current_date)::date, 'Rev. 00', 'Ninguno',
--        'c96787da-2c8d-44a2-baa9-de8bb2d83af3'
--      ) returning id, nombre;
--      rollback;
--
-- 3) Que traspasar la obra NO deje al creador viéndola -- la prueba de que la decisión de la 0108
--    sigue en pie. Sobre una obra con miembros:
--
--      select nombre, obra_sin_miembros_activos(id) as sin_miembros
--      from obras order by created_at desc;
--
--    `sin_miembros` tiene que dar false en todas las obras que se ven en la app. Si da true en
--    alguna, esa obra quedó sin miembros y hay que mirarla aparte.
