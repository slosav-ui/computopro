-- Perfiles: matrícula profesional, opcional -- mismo mecanismo y mismo criterio de privacidad
-- que nombre/teléfono (0099_perfiles_nombre_telefono.sql). Pedido de Seba: un profesional la
-- necesita porque forma parte de su identificación en los documentos que emite -- presupuestos y
-- certificados llevan matrícula. Ver docs/perfiles_nombre_telefono_diseno.md §6 para el diseño
-- completo, incluida la nota para cuando exista el generador de PDF (todavía no existe -- `pdf`/
-- `printing` en pubspec.yaml siguen sin usarse en ningún archivo de `lib/`).
--
-- No se llama "0099b" ni se edita 0099 -- 0099 puede ya estar aplicada en producción (no hay
-- forma de confirmarlo desde acá, sin acceso a la base), así que se trata como inmutable, mismo
-- criterio que el resto del proyecto usa con toda migración ya commiteada (docs/
-- diagnostico_general_producto.md §2.5, deriva entre repositorio y base).
--
-- `actualizar_mi_perfil`/`get_perfiles_de_obra` cambian de firma (un parámetro más, una columna
-- más en el `RETURNS TABLE`) -- `CREATE OR REPLACE FUNCTION` no alcanza para eso (Postgres no
-- deja cambiar el tipo de retorno ni agregar parámetros con `CREATE OR REPLACE`, terminaría
-- creando un overload nuevo en vez de reemplazar el viejo). Por eso el `DROP FUNCTION IF EXISTS`
-- antes de cada una, y el `GRANT EXECUTE` de nuevo después -- un DROP borra los grants del
-- objeto anterior junto con el objeto.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor), después de 0099. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

alter table perfiles add column matricula text;

-- =====================================================================
-- Trigger de alta: sin cambio de firma (returns trigger, sin parámetros) -- CREATE OR REPLACE
-- alcanza, solo cambia el cuerpo.
-- =====================================================================
create or replace function public.handle_new_user_perfil()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.perfiles (usuario_id, nombre, telefono, matricula)
  values (
    new.id,
    nullif(trim(new.raw_user_meta_data->>'nombre'), ''),
    nullif(trim(new.raw_user_meta_data->>'telefono'), ''),
    nullif(trim(new.raw_user_meta_data->>'matricula'), '')
  )
  on conflict (usuario_id) do nothing;
  return new;
end;
$$;

-- =====================================================================
-- actualizar_mi_perfil: un parámetro más
-- =====================================================================
drop function if exists actualizar_mi_perfil(text, text);

create function actualizar_mi_perfil(p_nombre text, p_telefono text default null, p_matricula text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then
    raise exception 'No autenticado.';
  end if;

  update perfiles
  set nombre = nullif(trim(p_nombre), ''),
      telefono = nullif(trim(p_telefono), ''),
      matricula = nullif(trim(p_matricula), '')
  where usuario_id = auth.uid();
end;
$$;

grant execute on function actualizar_mi_perfil(text, text, text) to authenticated;

-- =====================================================================
-- get_perfiles_de_obra: una columna más en el RETURNS TABLE
-- =====================================================================
drop function if exists get_perfiles_de_obra(uuid);

create function get_perfiles_de_obra(p_obra_id uuid)
returns table(usuario_id uuid, nombre text, telefono text, matricula text)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not is_obra_member(p_obra_id) then
    raise exception 'No sos miembro de esta obra.';
  end if;

  return query
    select distinct p.usuario_id, p.nombre, p.telefono, p.matricula
    from perfiles p
    join obra_members m on m.usuario_id = p.usuario_id
    where m.obra_id = p_obra_id and m.activo;
end;
$$;

grant execute on function get_perfiles_de_obra(uuid) to authenticated;
