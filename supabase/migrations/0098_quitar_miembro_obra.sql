-- Invitaciones/obra_members, Tanda 2: sacar a alguien de la obra, con guarda contra dejarla sin
-- administrador. Ver docs/invitaciones_diseno_datos.md.
--
-- "Sacar a alguien" ya era posible en la base sin esta función -- obra_members_update
-- (0004_rls_etapa3.sql) ya deja que admin_maestro ponga activo=false en cualquier fila. Esta
-- función no cambia esa política ni la reemplaza: agrega la guarda que un UPDATE directo no
-- puede expresar ("no dejes la obra sin ningún admin_maestro activo") y, mismo criterio que
-- aceptar_invitacion/revocar_invitacion, deja su propio rastro en audit_log de forma garantizada.
--
-- Autorización deliberadamente más estricta que la RLS cruda: obra_members_update también deja
-- que cliente_principal actualice filas de invitado_apoderado (gestión de su propia delegación de
-- firma). Esta función no cubre ese caso a propósito -- es el "Panel de Delegación de Firma" que
-- CLAUDE.md ya prevé como pieza aparte, no la gestión general de miembros de la Tanda 2. Acá:
-- admin_maestro, y nada más.
--
-- Sin #variable_conflict use_column: a diferencia de aceptar_invitacion/revocar_invitacion/
-- previsualizar_invitacion (0097), esta función no tiene RETURNS TABLE ni ninguna columna de
-- salida -- no hay variable con la que una columna pueda ambiguar. Agregar el pragma acá sería
-- copiar el remedio sin el problema que lo motiva.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.
create or replace function quitar_miembro_obra(p_obra_member_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_miembro obra_members%rowtype;
  v_otros_admins_activos integer;
begin
  select * into v_miembro from obra_members where id = p_obra_member_id;
  if not found then
    raise exception 'Miembro no encontrado.';
  end if;

  if not tiene_rol_en_obra(v_miembro.obra_id, 'admin_maestro') then
    raise exception 'No tenés permiso para sacar miembros de esta obra.';
  end if;

  if not v_miembro.activo then
    raise exception 'Ese miembro ya no está activo.';
  end if;

  -- La guarda real de esta función: si es el único admin_maestro activo, no se lo puede sacar --
  -- la obra quedaría sin nadie que pueda administrarla (revertir esto a mano en el SQL Editor
  -- sería el único camino, y ni siquiera queda claro quién debería poder pedirlo).
  if v_miembro.rol = 'admin_maestro' then
    select count(*) into v_otros_admins_activos
    from obra_members
    where obra_id = v_miembro.obra_id
      and rol = 'admin_maestro'
      and activo
      and id <> p_obra_member_id;

    if v_otros_admins_activos = 0 then
      raise exception 'No se puede sacar al único administrador de la obra -- asigná otro administrador antes.';
    end if;
  end if;

  update obra_members set activo = false where id = p_obra_member_id;

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (v_miembro.obra_id, auth.uid(), 'quitar_miembro_obra', 'obra_member', v_miembro.id,
          jsonb_build_object('usuario_id', v_miembro.usuario_id, 'rol', v_miembro.rol));
end;
$$;

grant execute on function quitar_miembro_obra(uuid) to authenticated;
