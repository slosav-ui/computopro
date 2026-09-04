-- Gestión de Obra, pieza 4: la firma física deja de bloquear la emisión del siguiente certificado.
-- Decisión de Seba al ver la tanda 1 funcionando — motivo: el papel firmado depende de terceros y
-- puede tardar días, frenar toda la certificación de una obra por eso es peor que el problema que
-- evita. Pasa a ser un aviso persistente en la UI (ver CartelFirmaPendiente en Dart), no un candado
-- en la base.
--
-- Verificado antes de escribir esto (no asumido): ninguna otra función ni política RLS depende de
-- este bloqueo. `subir_pdf_firmado_certificado` (0011) no lo referencia en absoluto — solo pisa
-- pdf_firmado_subido/pdf_firmado_fecha/pdf_firmado_adjuntos, sin mirar el estado del bloqueo en
-- ningún momento. `marcar_certificado_leido/pagado/impactado` tampoco tocan estas columnas. Ninguna
-- política de `certificados_select/insert/update` las menciona. Sacar el bloqueo de acá no deja
-- ningún otro camino abierto que no correspondía — es la única puerta que existía.
--
-- Se saca SOLO el `if` que rechazaba la emisión — no las columnas, no el registro de que un
-- certificado requirió firma física, no el flag de si ya se subió el PDF. `requiere_firma_fisica`
-- se sigue preguntando y guardando al emitir (sigue siendo dato real, la base del aviso nuevo);
-- `pdf_firmado_subido`/`subir_pdf_firmado_certificado` siguen funcionando exactamente igual.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

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
  v_estado text;
  v_totales record;
  v_exceso record;
begin
  select obra_id, numero, estado
    into v_obra_id, v_numero, v_estado
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

  -- Candado del 100% acumulado — misma cuenta que ve la vista previa, llamada, no repetida.
  select * into v_exceso from calcular_excesos_certificado(p_certificado_id) limit 1;
  if v_exceso.obra_subitem_id is not null then
    raise exception '"%" ya tiene % certificado — quedan % disponibles, se intentó cargar %',
      v_exceso.descripcion, v_exceso.acumulado_previo, v_exceso.disponible, v_exceso.intentado;
  end if;

  -- Monto y desglose — misma cuenta que ve la vista previa, llamada, no repetida. Esto es lo que
  -- se congela en la fila de abajo.
  select * into v_totales from calcular_totales_certificado(p_certificado_id);

  if v_totales.monto <= 0 then
    raise exception 'no se puede emitir un certificado sin avance cargado';
  end if;

  -- Ya NO se valida acá si el certificado anterior requiere firma física y no la tiene todavía —
  -- eso pasó a ser un aviso en la UI (CartelFirmaPendiente), no un bloqueo. requiere_firma_fisica
  -- se sigue preguntando y guardando abajo, sin cambios.

  update certificados
  set estado = 'emitido',
      monto = v_totales.monto,
      fecha_emision = now(),
      emitido_por = auth.uid(),
      dias_plazo_pago = v_totales.dias_plazo_pago,
      requiere_firma_fisica = p_requiere_firma_fisica,
      anticipo_pct_aplicado = v_totales.anticipo_pct,
      fondo_reparo_pct_aplicado = v_totales.fondo_reparo_pct,
      monto_anticipo_descontado = v_totales.monto_anticipo,
      monto_fondo_reparo_retenido = v_totales.monto_fondo_reparo,
      monto_neto_a_pagar = v_totales.monto_neto
  where id = p_certificado_id;

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (
    v_obra_id, auth.uid(), 'emitir_certificado', 'certificado', p_certificado_id,
    jsonb_build_object(
      'numero', v_numero,
      'monto', v_totales.monto,
      'requiere_firma_fisica', p_requiere_firma_fisica,
      'monto_neto_a_pagar', v_totales.monto_neto
    )
  );
end;
$$;

grant execute on function emitir_certificado(uuid, boolean) to authenticated;

-- =====================================================================
-- Verificación
-- =====================================================================

-- 1) Emitir un certificado cuando el anterior de la misma obra tiene requiere_firma_fisica = true
--    y pdf_firmado_subido = false tiene que funcionar ahora (antes fallaba con el mensaje "el
--    certificado anterior... requiere firma física").
--
-- 2) requiere_firma_fisica sigue guardándose con el valor que se pasa al emitir — confirmar en la
--    fila resultante.
--
-- 3) subir_pdf_firmado_certificado sigue funcionando exactamente igual que antes (sin cambios en
--    esta migración) — confirmar que sigue marcando pdf_firmado_subido = true sin error.
select proname from pg_proc where proname = 'emitir_certificado';
