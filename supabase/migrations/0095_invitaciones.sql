-- Invitaciones a una obra, Tanda 1: tabla `invitaciones`, código corto canjeable, y las dos
-- funciones (aceptar/revocar). Ver docs/invitaciones_diseno_datos.md para el diseño completo —
-- acá solo queda el SQL ya decidido, con un ajuste sobre el documento: el código no es el `token`
-- uuid que proponía el diseño original, es un código corto para pegar a mano por WhatsApp (ver
-- razón en el comentario de generar_codigo_invitacion, más abajo).
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.
--
-- Orden de aplicación de este archivo (de punta a punta, sin cortar a la mitad): función
-- generadora de código -> tabla -> RLS -> función aceptar -> función revocar -> grants. El orden
-- importa porque el DEFAULT de `invitaciones.codigo` llama a la función generadora, así que tiene
-- que existir antes de crear la tabla.

-- =====================================================================
-- generar_codigo_invitacion(): código corto, alfabeto sin ambigüedad visual
-- =====================================================================
--
-- Decisión de Seba (2026-09-10): no un token uuid — nadie copia bien un uuid de 36 caracteres
-- pegado a mano desde un WhatsApp, y si se equivoca al tipear, abandona. 8 caracteres de un
-- alfabeto de 31 símbolos (sin 0/O, sin 1/I/L — son los pares que más se confunden a mano):
-- dígitos 2-9 (8) + letras mayúsculas A-Z sin I/L/O (23) = 31^8 ≈ 852.891 millones de combinaciones
-- posibles. Suficiente para que adivinar un código válido a ciegas sea impracticable incluso sin
-- el freno de intentos de aceptar_invitacion (más abajo) — ese freno es la segunda barrera, no la
-- única.
create or replace function generar_codigo_invitacion()
returns text language plpgsql as $$
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
-- Tabla invitaciones
-- =====================================================================
--
-- Mismas columnas que PermisosEspeciales de obra_members (0001_obra_members.sql) para que
-- aceptar_invitacion copie directo, sin traducir nada. Sin email_destino a propósito (decisión
-- cerrada, ver el diseño §2): el código no está atado a una persona, es un link/código tipo
-- Slack/Notion — quien lo tenga y lo use antes de que venza o se revoque, entra.
--
-- `codigo unique`: la probabilidad de colisión del DEFAULT es despreciable a cualquier volumen
-- real de invitaciones (con 10.000 códigos emitidos, ~1 en 17.000 de que dos coincidan), pero la
-- constraint es la red de seguridad correcta igual — si algún día colisiona, el INSERT del lado
-- de la app falla y reintenta (nuevo DEFAULT), en vez de guardar un duplicado silencioso.
create table invitaciones (
  id uuid primary key default gen_random_uuid(),
  obra_id uuid not null references obras(id) on delete cascade,
  -- Sin 'admin_maestro' a propósito (decisión cerrada, ver el diseño §3): es un flag ligado a
  -- quien crea la obra, no un rol económico invitable.
  rol text not null check (rol in (
    'profesional','constructor','cliente_principal','invitado_veedor','invitado_apoderado'
  )),
  puede_aprobar_certificados boolean not null default false,
  puede_aprobar_adicionales boolean not null default false,
  tope_monto_aprobacion numeric,
  delegacion_inicio timestamptz,
  delegacion_fin timestamptz,
  puede_invitar_terceros boolean not null default false,
  -- Default false, igual que en obra_members -- es el único permiso con gate de plan (ver el
  -- diseño §4): el aviso de "requiere PRO" en la pantalla de invitar es genérico (no se sabe el
  -- plan de alguien que puede ni tener cuenta todavía), la verificación real es esPro(auth.uid())
  -- en vivo, en el momento de uso -- no vive acá, no es responsabilidad de esta migración.
  puede_ver_apu_ajena boolean not null default false,
  codigo text not null unique default generar_codigo_invitacion(),
  invitado_por_usuario_id uuid not null references auth.users(id),
  estado text not null default 'pendiente' check (estado in ('pendiente','aceptada','revocada')),
  creado_at timestamptz not null default now(),
  expira_en timestamptz not null default (now() + interval '30 days'),
  aceptada_por_usuario_id uuid references auth.users(id),
  aceptada_en timestamptz
);

-- =====================================================================
-- RLS
-- =====================================================================
--
-- Sin política UPDATE: a propósito. Los dos únicos cambios de estado posibles (aceptar, revocar)
-- pasan exclusivamente por las funciones SECURITY DEFINER de abajo, nunca por un UPDATE directo
-- del cliente -- ahí es donde vive el freno de fuerza bruta y la autorización de revocar, y no
-- tendría sentido duplicar esa lógica en una policy aparte cuando ya la exige la función.
--
-- Sin política DELETE: mismo criterio que el resto del proyecto (obra_members, certificados) --
-- "revocar sin borrar" es el mecanismo, nunca un delete físico.
alter table invitaciones enable row level security;

-- SELECT: quien la creó, o quien administra la obra (admin_maestro / puede_invitar_terceros) --
-- para poder listarlas en el panel de miembros de la Tanda 2.
create policy invitaciones_select on invitaciones for select using (
  invitado_por_usuario_id = auth.uid()
  or tiene_rol_en_obra(obra_id, 'admin_maestro')
  or exists (
    select 1 from obra_members m
    where m.obra_id = invitaciones.obra_id and m.usuario_id = auth.uid()
      and m.activo and m.puede_invitar_terceros
  )
);

-- INSERT: mismo criterio que obra_members_insert (0004_rls_etapa3.sql) para admin_maestro /
-- puede_invitar_terceros -- self-attribution obligatoria (invitado_por_usuario_id = quien crea).
create policy invitaciones_insert on invitaciones for insert with check (
  invitado_por_usuario_id = auth.uid()
  and (
    tiene_rol_en_obra(obra_id, 'admin_maestro')
    or exists (
      select 1 from obra_members m
      where m.obra_id = invitaciones.obra_id and m.usuario_id = auth.uid()
        and m.activo and m.puede_invitar_terceros
    )
  )
);

-- =====================================================================
-- aceptar_invitacion(p_codigo): SECURITY DEFINER -- necesita insertar en obra_members una fila
-- para alguien que todavía no es miembro de la obra, algo que la RLS normal de obra_members no
-- permite (ni debería, para cualquier otro camino que no sea este).
-- =====================================================================
--
-- Freno de fuerza bruta, en dos capas:
--  1. Antes de mirar la tabla invitaciones siquiera, cuenta los intentos fallidos de ESTE usuario
--     autenticado en los últimos 15 minutos (audit_log, acción 'canje_invitacion_fallido') y corta
--     si ya hubo 5 o más -- barato, reusa audit_log en vez de una tabla nueva solo para esto.
--  2. Un código que no existe, uno vencido, y uno ya usado devuelven exactamente el mismo mensaje
--     genérico ("Código inválido o vencido") -- nunca se distingue el motivo, así quien prueba
--     códigos al azar no tiene forma de saber si estuvo cerca de uno real.
--
-- Límite conocido, no resuelto acá: el freno es por usuario autenticado, no por IP ni dispositivo
-- -- alguien dispuesto a crear muchas cuentas de Supabase podría resetear el contador por cada
-- cuenta nueva. Eso ya tiene su propia fricción (email real + confirmación, ver AuthService) y
-- excede el alcance de esta pieza; si en algún momento hace falta un freno más duro, es un cambio
-- en Supabase Auth (rate limiting de signups), no en esta función.
create or replace function aceptar_invitacion(p_codigo text)
returns table(obra_id uuid, obra_nombre text, rol text)
language plpgsql security definer set search_path = public as $$
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

grant execute on function aceptar_invitacion(text) to authenticated;

-- =====================================================================
-- revocar_invitacion(p_invitacion_id): SECURITY DEFINER por consistencia con aceptar_invitacion
-- (misma razón: deja su propio rastro en audit_log de forma garantizada) -- la autorización la
-- hace la propia función, no una policy UPDATE (que a propósito no existe, ver arriba).
-- =====================================================================
create or replace function revocar_invitacion(p_invitacion_id uuid)
returns void language plpgsql security definer set search_path = public as $$
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

grant execute on function revocar_invitacion(uuid) to authenticated;
