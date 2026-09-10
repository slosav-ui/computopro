-- Invitaciones: mismo bug 42702 ya visto en la familia de funciones de edición de APU
-- (0075/0076) -- confirmado por Seba en producción al probar aceptar_invitacion: "column
-- reference obra_id is ambiguous -- It could refer to either a PL/pgSQL variable or a table
-- column." `aceptar_invitacion` declara `returns table(obra_id uuid, obra_nombre text, rol
-- text)`, y PL/pgSQL expone esas columnas de salida como variables del cuerpo de la función --
-- cualquier `obra_id`/`rol` sin calificar en una consulta embebida (acá, el más probable:
-- `on conflict (obra_id, usuario_id, rol)`, línea 183 de 0095) queda ambiguo entre esa variable y
-- la columna de la tabla, y con `plpgsql.variable_conflict = error` (el default) corta con 42702.
--
-- Mismo criterio que 0076, no calificar caso por caso: "Postgres corta el parseo en la primera
-- ambigüedad, así que arreglar una revela la siguiente en la próxima corrida" -- ya pasó con esta
-- misma familia de bug antes. Solución de fondo: `#variable_conflict use_column` como primera
-- línea del cuerpo, en las tres funciones de esta pieza, no solo en la que falló:
--
-- - `aceptar_invitacion`: la que reportó el error. `obra_id` y `rol` son columnas de su
--   `RETURNS TABLE`.
-- - `revocar_invitacion`: pedido explícito de Seba ("la otra tiene el mismo patrón"). Revisada
--   ahora: no declara ningún `obra_id`/`rol` como variable de salida (`returns void`, sin
--   columnas de salida) -- hoy no tiene esta ambigüedad puntual. El pragma se agrega de todos
--   modos porque no cambia nada cuando no hace falta (mismo argumento de seguridad que 0076 usó
--   para las 3 funciones que "hoy no lo tienen pero comparten el mismo patrón"), y dentro de la
--   misma migración es más simple aplicarlo a las tres que justificar por qué a esta no.
-- - `previsualizar_invitacion`: pedido explícito de Seba ("aunque hoy funcione"). Su
--   `RETURNS TABLE(obra_nombre text, rol text)` sí incluye `rol` como columna de salida, y aunque
--   hoy el cuerpo solo la lee calificada (`v_inv.rol`), es exactamente el mismo patrón de riesgo
--   que ya mordió dos veces en este proyecto -- se agrega preventivo, no reactivo.
--
-- Por qué es seguro en las tres: ninguna necesita nunca la otra lectura (la variable) -- las
-- columnas del `RETURNS TABLE` nunca se leen ni se asignan a mano en ningún lado, se completan
-- solas vía `RETURN QUERY`. Todo acceso real a datos usa variables con prefijo `v_`/`p_`, o
-- accede a través de un alias de tabla (`v_inv.obra_id`, `i.codigo`, `o.nombre`), nunca el
-- nombre pelado de una columna de salida.
--
-- `create or replace function` -- ninguna cambia de firma, solo se les agrega la directiva.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor), después de 0096. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

create or replace function aceptar_invitacion(p_codigo text)
returns table(obra_id uuid, obra_nombre text, rol text)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_intentos_recientes integer;
  v_inv invitaciones%rowtype;
  v_obra_nombre text;
begin
  if auth.uid() is null then
    raise exception 'No autenticado.';
  end if;

  select count(*) into v_intentos_recientes
  from audit_log
  where usuario_id = auth.uid()
    and accion = 'canje_invitacion_fallido'
    and created_at > now() - interval '15 minutes';

  if v_intentos_recientes >= 5 then
    raise exception 'Demasiados intentos. Esperá unos minutos y volvé a probar.';
  end if;

  select * into v_inv
  from invitaciones i
  where i.codigo = upper(trim(p_codigo))
    and i.estado = 'pendiente'
    and i.expira_en > now();

  if not found then
    insert into audit_log (usuario_id, accion, entidad, detalle)
    values (auth.uid(), 'canje_invitacion_fallido', 'invitacion', jsonb_build_object());
    raise exception 'Código inválido o vencido.';
  end if;

  insert into obra_members (
    obra_id, usuario_id, rol, invitado_por_usuario_id,
    puede_aprobar_certificados, puede_aprobar_adicionales, tope_monto_aprobacion,
    delegacion_inicio, delegacion_fin, puede_invitar_terceros, puede_ver_apu_ajena
  ) values (
    v_inv.obra_id, auth.uid(), v_inv.rol, v_inv.invitado_por_usuario_id,
    v_inv.puede_aprobar_certificados, v_inv.puede_aprobar_adicionales, v_inv.tope_monto_aprobacion,
    v_inv.delegacion_inicio, v_inv.delegacion_fin, v_inv.puede_invitar_terceros, v_inv.puede_ver_apu_ajena
  )
  -- Re-aceptar un rol que ya se tenía (reactivado tras una revocación, o el mismo permiso
  -- reenviado) reactiva y refresca los permisos en vez de romper contra el unique existente.
  on conflict (obra_id, usuario_id, rol) do update set
    activo = true,
    invitado_por_usuario_id = excluded.invitado_por_usuario_id,
    puede_aprobar_certificados = excluded.puede_aprobar_certificados,
    puede_aprobar_adicionales = excluded.puede_aprobar_adicionales,
    tope_monto_aprobacion = excluded.tope_monto_aprobacion,
    delegacion_inicio = excluded.delegacion_inicio,
    delegacion_fin = excluded.delegacion_fin,
    puede_invitar_terceros = excluded.puede_invitar_terceros,
    puede_ver_apu_ajena = excluded.puede_ver_apu_ajena;

  update invitaciones
  set estado = 'aceptada', aceptada_por_usuario_id = auth.uid(), aceptada_en = now()
  where id = v_inv.id;

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (v_inv.obra_id, auth.uid(), 'aceptar_invitacion', 'invitacion', v_inv.id,
          jsonb_build_object('rol', v_inv.rol));

  select o.nombre into v_obra_nombre from obras o where o.id = v_inv.obra_id;

  return query select v_inv.obra_id, v_obra_nombre, v_inv.rol;
end;
$$;

create or replace function revocar_invitacion(p_invitacion_id uuid)
returns void language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_inv invitaciones%rowtype;
  v_autorizado boolean;
begin
  select * into v_inv from invitaciones where id = p_invitacion_id;
  if not found then
    raise exception 'Invitación no encontrada.';
  end if;

  v_autorizado := v_inv.invitado_por_usuario_id = auth.uid()
    or tiene_rol_en_obra(v_inv.obra_id, 'admin_maestro')
    or exists (
      select 1 from obra_members m
      where m.obra_id = v_inv.obra_id and m.usuario_id = auth.uid()
        and m.activo and m.puede_invitar_terceros
    );

  if not v_autorizado then
    raise exception 'No tenés permiso para revocar esta invitación.';
  end if;

  if v_inv.estado <> 'pendiente' then
    raise exception 'Esta invitación ya no está pendiente.';
  end if;

  update invitaciones set estado = 'revocada' where id = p_invitacion_id;

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (v_inv.obra_id, auth.uid(), 'revocar_invitacion', 'invitacion', v_inv.id,
          jsonb_build_object('rol', v_inv.rol));
end;
$$;

create or replace function previsualizar_invitacion(p_codigo text)
returns table(obra_nombre text, rol text)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_inv invitaciones%rowtype;
begin
  select * into v_inv
  from invitaciones i
  where i.codigo = upper(trim(p_codigo))
    and i.estado = 'pendiente'
    and i.expira_en > now();

  if not found then
    return;
  end if;

  return query
    select o.nombre, v_inv.rol
    from obras o
    where o.id = v_inv.obra_id;
end;
$$;
