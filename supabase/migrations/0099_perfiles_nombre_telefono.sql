-- Perfiles: nombre y teléfono visibles entre compañeros de obra -- resuelve el gap encontrado al
-- construir la Tanda 2 de invitaciones (docs/invitaciones_diseno_datos.md §10): la pantalla de
-- miembros mostraba un UUID acortado porque no había ningún dato legible para mostrar.
--
-- Teléfono, no solo nombre -- pedido explícito de Seba: en obra se llama por teléfono, no se
-- manda mail. Mismo mecanismo de escritura/lectura acotada que nombre, mismo criterio de
-- privacidad (visible entre compañeros de obra, no a cualquier usuario del sistema).
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

-- =====================================================================
-- Columnas nuevas -- nullable, sin backfill real posible
-- =====================================================================
--
-- Supabase Auth (email/contraseña) nunca capturó un nombre ni un teléfono -- no hay de dónde
-- sacar el dato de los usuarios que ya existen, así que no hay backfill que escribir (a
-- diferencia de `es_pro`, que si tenía un valor de default razonable). Quedan `null` hasta que
-- cada usuario los carga -- desde el registro (nuevos) o desde "Editar mi perfil" (todos,
-- incluidos los que ya existían). La UI qué hace mientras tanto (mostrar el UUID acortado, como
-- ya hacía) es responsabilidad de la app, no de esta migración.
alter table perfiles add column nombre text;
alter table perfiles add column telefono text;

-- =====================================================================
-- Trigger de alta: ahora también lee nombre/teléfono del metadata del signup
-- =====================================================================
--
-- `raw_user_meta_data` es lo que `signUp(..., data: {...})` guarda en `auth.users` -- disponible
-- en el trigger porque corre AFTER INSERT sobre esa misma fila. Si el cliente no mandó el campo
-- (ej. alguien que se registró con una versión vieja de la app, o el campo quedó vacío), el
-- `->>'nombre'` da null y la columna queda null -- mismo resultado que si no existiera esta
-- función, no hace falta un caso especial.
create or replace function public.handle_new_user_perfil()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.perfiles (usuario_id, nombre, telefono)
  values (
    new.id,
    nullif(trim(new.raw_user_meta_data->>'nombre'), ''),
    nullif(trim(new.raw_user_meta_data->>'telefono'), '')
  )
  on conflict (usuario_id) do nothing;
  return new;
end;
$$;

-- =====================================================================
-- actualizar_mi_perfil: la única forma de escribir nombre/teléfono
-- =====================================================================
--
-- Por qué una función y no una política UPDATE directa: `perfiles` hoy no tiene NINGUNA política
-- UPDATE, a propósito (0014_perfiles.sql) -- un "usuario_id = auth.uid()" genérico dejaría que
-- cualquiera se ponga `es_pro = true` llamando la API directo, sin pasar por la app. Esta función
-- es `SECURITY DEFINER` (bypassea esa ausencia de política) pero en su cuerpo SOLO puede tocar
-- `nombre`/`telefono` de la propia fila (`auth.uid()`) -- `es_pro` no aparece en ningún lado del
-- SET, así que no hay forma de que esta función lo toque, sin importar qué mande el cliente (la
-- firma ni siquiera acepta ese parámetro). La tabla sigue sin política UPDATE: esto no la
-- reemplaza, la evita.
create or replace function actualizar_mi_perfil(p_nombre text, p_telefono text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then
    raise exception 'No autenticado.';
  end if;

  update perfiles
  set nombre = nullif(trim(p_nombre), ''), telefono = nullif(trim(p_telefono), '')
  where usuario_id = auth.uid();
end;
$$;

grant execute on function actualizar_mi_perfil(text, text) to authenticated;

-- =====================================================================
-- get_perfiles_de_obra: la única forma de leer nombre/teléfono de otra persona
-- =====================================================================
--
-- No se amplía `perfiles_select` (que sigue siendo estrictamente `usuario_id = auth.uid()`)
-- porque ese es un permiso por FILA -- Postgres RLS no puede dejar pasar `nombre`/`telefono` de
-- otra persona sin dejar pasar `es_pro` con ella (misma fila). Esta función proyecta solo las
-- tres columnas que corresponde mostrar, nunca `es_pro`, y solo para quien comparte una obra
-- activa con el que pregunta -- mismo patrón que `previsualizar_invitacion` (proyección acotada
-- en vez de abrir la tabla entera).
create or replace function get_perfiles_de_obra(p_obra_id uuid)
returns table(usuario_id uuid, nombre text, telefono text)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not is_obra_member(p_obra_id) then
    raise exception 'No sos miembro de esta obra.';
  end if;

  return query
    select distinct p.usuario_id, p.nombre, p.telefono
    from perfiles p
    join obra_members m on m.usuario_id = p.usuario_id
    where m.obra_id = p_obra_id and m.activo;
end;
$$;

grant execute on function get_perfiles_de_obra(uuid) to authenticated;
