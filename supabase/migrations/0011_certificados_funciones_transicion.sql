-- Ciclo de vida del Certificado de Obra, paso 2: helper puede_gestionar_certificado() + las 4
-- funciones de transición de estado + una 5ª función necesaria que no estaba contada entre las
-- "4 funciones" originales (ver nota abajo).
-- Ver docs/certificados_ciclo_vida_diseno_datos.md, sección 7, para el diseño completo.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.
--
-- Todas SECURITY DEFINER (no INVOKER como cambiar_modelo_certificacion/aprobar_ajuste_contrato):
-- consecuencia directa de 0010_certificados_update_solo_borrador.sql, que dejó certificados_update
-- sin permitir ningún cambio de estado por fuera de una función. Cada función hace ella misma el
-- chequeo de autoridad (tiene_rol_en_obra/puede_gestionar_certificado) en el cuerpo, sin apoyarse
-- en la política UPDATE de la tabla para eso.
--
-- Nota sobre la 5ª función (subir_pdf_firmado_certificado, no estaba en las "4 funciones de
-- transición" del diseño original): "subir el PDF firmado" no es una transición de estado del
-- ciclo de 5 pasos — puede pasar en cualquier momento después de emitido, independiente de si el
-- certificado sigue 'emitido', pasó a 'leido', 'pagado' o 'impactado_cerrado'. Con
-- certificados_update ya restringido a solo 'borrador' (0010), no quedaba ningún camino para
-- marcar pdf_firmado_subido=true una vez emitido — sin esta función, el bloqueo de firma física
-- de emitir_certificado (más abajo) sería imposible de destrabar nunca. Se agrega acá porque es
-- una dependencia dura de que el resto del ciclo funcione, no una ampliación de alcance porque sí.

-- =====================================================================
-- puede_gestionar_certificado
-- =====================================================================

create or replace function puede_gestionar_certificado(p_obra_id uuid, p_monto numeric)
returns boolean language sql security definer set search_path = public stable as $$
  select
    tiene_rol_en_obra(p_obra_id, 'cliente_principal')
    or exists (
      select 1 from obra_members
      where obra_id = p_obra_id and usuario_id = auth.uid() and activo
        and rol = 'invitado_apoderado' and puede_aprobar_certificados
        and (tope_monto_aprobacion is null or p_monto <= tope_monto_aprobacion)
        and ((delegacion_inicio is null and delegacion_fin is null)
             or now() between delegacion_inicio and delegacion_fin)
    );
$$;

grant execute on function puede_gestionar_certificado(uuid, numeric) to authenticated;

-- =====================================================================
-- emitir_certificado: Borrador -> Emitido
-- =====================================================================

create or replace function emitir_certificado(
  p_certificado_id uuid,
  p_requiere_firma_fisica boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_obra_id uuid;
  v_numero int;
  v_monto numeric;
  v_estado text;
  v_dias_plazo_pago int;
  v_anticipo_pct numeric;
  v_fondo_reparo_pct numeric;
  v_prev_requiere_firma boolean;
  v_prev_pdf_subido boolean;
  v_monto_anticipo numeric;
  v_monto_fondo_reparo numeric;
  v_monto_neto numeric;
begin
  select obra_id, numero, monto, estado
    into v_obra_id, v_numero, v_monto, v_estado
  from certificados
  where id = p_certificado_id;

  if v_obra_id is null then
    raise exception 'certificado % no encontrado', p_certificado_id;
  end if;

  if v_estado <> 'borrador' then
    raise exception 'certificado % no está en borrador (estado actual: %)', p_certificado_id, v_estado;
  end if;

  if not (tiene_rol_en_obra(v_obra_id, 'admin_maestro') or tiene_rol_en_obra(v_obra_id, 'profesional')) then
    raise exception 'sin autoridad para emitir este certificado';
  end if;

  -- Bloqueo de firma física: el certificado anterior de la misma obra, si existe, no puede tener
  -- pendiente su PDF firmado.
  select requiere_firma_fisica, pdf_firmado_subido
    into v_prev_requiere_firma, v_prev_pdf_subido
  from certificados
  where obra_id = v_obra_id and numero = v_numero - 1;

  if v_prev_requiere_firma is true and coalesce(v_prev_pdf_subido, false) = false then
    raise exception 'el certificado anterior (N° %) requiere firma física y todavía no se subió el PDF firmado', v_numero - 1;
  end if;

  select dias_plazo_pago_certificados, anticipo_pct, fondo_reparo_pct
    into v_dias_plazo_pago, v_anticipo_pct, v_fondo_reparo_pct
  from obras
  where id = v_obra_id;

  v_monto_anticipo := round(v_monto * coalesce(v_anticipo_pct, 0) / 100, 2);
  v_monto_fondo_reparo := round(v_monto * coalesce(v_fondo_reparo_pct, 0) / 100, 2);
  v_monto_neto := v_monto - v_monto_anticipo - v_monto_fondo_reparo;

  update certificados
  set estado = 'emitido',
      fecha_emision = now(),
      emitido_por = auth.uid(),
      dias_plazo_pago = v_dias_plazo_pago,
      requiere_firma_fisica = p_requiere_firma_fisica,
      anticipo_pct_aplicado = v_anticipo_pct,
      fondo_reparo_pct_aplicado = v_fondo_reparo_pct,
      monto_anticipo_descontado = v_monto_anticipo,
      monto_fondo_reparo_retenido = v_monto_fondo_reparo,
      monto_neto_a_pagar = v_monto_neto
  where id = p_certificado_id;

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (
    v_obra_id, auth.uid(), 'emitir_certificado', 'certificado', p_certificado_id,
    jsonb_build_object(
      'numero', v_numero,
      'monto', v_monto,
      'requiere_firma_fisica', p_requiere_firma_fisica,
      'monto_neto_a_pagar', v_monto_neto
    )
  );
end;
$$;

grant execute on function emitir_certificado(uuid, boolean) to authenticated;

-- =====================================================================
-- marcar_certificado_leido: Emitido -> Leído
-- =====================================================================

create or replace function marcar_certificado_leido(p_certificado_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_obra_id uuid;
  v_estado text;
  v_fecha_lectura timestamptz;
begin
  select obra_id, estado, fecha_lectura
    into v_obra_id, v_estado, v_fecha_lectura
  from certificados
  where id = p_certificado_id;

  if v_obra_id is null then
    raise exception 'certificado % no encontrado', p_certificado_id;
  end if;

  if not (tiene_rol_en_obra(v_obra_id, 'cliente_principal') or tiene_rol_en_obra(v_obra_id, 'invitado_apoderado')) then
    raise exception 'sin autoridad para marcar este certificado como leído';
  end if;

  if v_estado = 'borrador' then
    raise exception 'certificado % todavía no fue emitido', p_certificado_id;
  end if;

  if v_fecha_lectura is not null then
    return;  -- idempotente: la app puede llamarla en cada apertura de pantalla sin cuidado especial
  end if;

  update certificados
  set estado = 'leido',
      fecha_lectura = now(),
      leido_por = auth.uid()
  where id = p_certificado_id;

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (v_obra_id, auth.uid(), 'marcar_certificado_leido', 'certificado', p_certificado_id, null);
end;
$$;

grant execute on function marcar_certificado_leido(uuid) to authenticated;

-- =====================================================================
-- marcar_certificado_pagado: Emitido o Leído -> Pagado
-- =====================================================================

create or replace function marcar_certificado_pagado(
  p_certificado_id uuid,
  p_medio_pago text,
  p_comprobante_adjuntos text[] default '{}'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_obra_id uuid;
  v_estado text;
  v_monto numeric;
  v_fecha_lectura timestamptz;
  v_lectura_automatica boolean := false;
begin
  select obra_id, estado, monto, fecha_lectura
    into v_obra_id, v_estado, v_monto, v_fecha_lectura
  from certificados
  where id = p_certificado_id;

  if v_obra_id is null then
    raise exception 'certificado % no encontrado', p_certificado_id;
  end if;

  if v_estado not in ('emitido', 'leido') then
    raise exception 'certificado % no está en condiciones de pagarse (estado actual: %)', p_certificado_id, v_estado;
  end if;

  if not puede_gestionar_certificado(v_obra_id, v_monto) then
    raise exception 'sin autoridad de aprobación para pagar este certificado';
  end if;

  if v_fecha_lectura is null then
    v_lectura_automatica := true;
  end if;

  update certificados
  set estado = 'pagado',
      fecha_pago = now(),
      pagado_por = auth.uid(),
      medio_pago = p_medio_pago,
      comprobante_pago_adjuntos = p_comprobante_adjuntos,
      fecha_lectura = coalesce(fecha_lectura, now()),
      leido_por = coalesce(leido_por, auth.uid())
  where id = p_certificado_id;

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (
    v_obra_id, auth.uid(), 'marcar_certificado_pagado', 'certificado', p_certificado_id,
    jsonb_build_object('medio_pago', p_medio_pago, 'lectura_automatica', v_lectura_automatica)
  );
end;
$$;

grant execute on function marcar_certificado_pagado(uuid, text, text[]) to authenticated;

-- =====================================================================
-- marcar_certificado_impactado: Pagado -> Impactado y Cerrado
-- =====================================================================

create or replace function marcar_certificado_impactado(
  p_certificado_id uuid,
  p_factura_adjuntos text[] default '{}'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_obra_id uuid;
  v_estado text;
begin
  select obra_id, estado
    into v_obra_id, v_estado
  from certificados
  where id = p_certificado_id;

  if v_obra_id is null then
    raise exception 'certificado % no encontrado', p_certificado_id;
  end if;

  if v_estado <> 'pagado' then
    raise exception 'certificado % no está pagado (estado actual: %)', p_certificado_id, v_estado;
  end if;

  if not (tiene_rol_en_obra(v_obra_id, 'admin_maestro') or tiene_rol_en_obra(v_obra_id, 'constructor')) then
    raise exception 'sin autoridad para cerrar este certificado';
  end if;

  update certificados
  set estado = 'impactado_cerrado',
      fecha_impacto = now(),
      impactado_por = auth.uid(),
      factura_final_adjuntos = p_factura_adjuntos
  where id = p_certificado_id;

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (v_obra_id, auth.uid(), 'marcar_certificado_impactado', 'certificado', p_certificado_id, null);
end;
$$;

grant execute on function marcar_certificado_impactado(uuid, text[]) to authenticated;

-- =====================================================================
-- subir_pdf_firmado_certificado: independiente del estado del ciclo (ver nota al principio)
-- =====================================================================

create or replace function subir_pdf_firmado_certificado(
  p_certificado_id uuid,
  p_adjuntos text[]
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_obra_id uuid;
  v_estado text;
begin
  select obra_id, estado into v_obra_id, v_estado from certificados where id = p_certificado_id;

  if v_obra_id is null then
    raise exception 'certificado % no encontrado', p_certificado_id;
  end if;

  if v_estado = 'borrador' then
    raise exception 'certificado % todavía no fue emitido', p_certificado_id;
  end if;

  if not (tiene_rol_en_obra(v_obra_id, 'admin_maestro') or tiene_rol_en_obra(v_obra_id, 'profesional')) then
    raise exception 'sin autoridad para subir el PDF firmado de este certificado';
  end if;

  if p_adjuntos is null or array_length(p_adjuntos, 1) is null then
    raise exception 'hace falta al menos un adjunto';
  end if;

  update certificados
  set pdf_firmado_subido = true,
      pdf_firmado_fecha = now(),
      pdf_firmado_adjuntos = p_adjuntos
  where id = p_certificado_id;

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (v_obra_id, auth.uid(), 'subir_pdf_firmado_certificado', 'certificado', p_certificado_id, null);
end;
$$;

grant execute on function subir_pdf_firmado_certificado(uuid, text[]) to authenticated;
