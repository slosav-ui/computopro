-- Bug real encontrado por Seba probando "presupuestar con la app" (2026-09-12): tocar Crear en
-- Adicionales → "+" → "Presupuestar con la app" fallaba con `null value in column "monto_total"`,
-- sin crear nada (la transacción entera vuelve atrás -- ni obra hija ni adicional a medio crear).
--
-- Causa: el insert en `modificaciones_obra` de `crear_adicional_presupuestado` (0113) no manda
-- `monto_total`. La columna es `numeric not null` SIN default desde la 0002, y el único que la
-- llenaba solo era el trigger `calcular_monto_total_adicional` (0112) -- que la 0113 acotó, a
-- propósito, a `obra_hija_id is null` (camino de monto fijo). Para el camino de obra hija nadie la
-- seteaba. El insert de la obra hija en `obras` NO era el problema: ya manda `monto_total = 0`.
--
-- Fix: el insert manda `monto_total = 0` explícito. Es el valor que la pantalla ya espera
-- (`adicionales_screen.dart`: un adicional presupuestado con la app y pendiente muestra "Presu-
-- puestándose con la app" en vez del monto, justamente porque está en 0 hasta que se apruebe y se
-- congele la obra hija, Tanda 2) -- mismo criterio que `crearQuitaDemasia`, que también inserta 0.
-- No se toca la columna (`drop not null` / default): el resto del circuito asume un número.
--
-- El resto de la función queda idéntico a la 0113.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor), después de 0113. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

create or replace function crear_adicional_presupuestado(
  p_obra_id uuid,
  p_descripcion text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_madre obras%rowtype;
  v_obra_hija_id uuid;
  v_modificacion_id uuid;
begin
  if not is_obra_member(p_obra_id) then
    raise exception 'sin autoridad para presupuestar un adicional en esta obra';
  end if;

  if p_descripcion is null or btrim(p_descripcion) = '' then
    raise exception 'el adicional necesita una descripción';
  end if;

  select * into v_madre from obras where id = p_obra_id;
  if not found then
    raise exception 'obra % no encontrada', p_obra_id;
  end if;

  insert into obras (
    nombre, propietario, ubicacion, tipo_obra, perfil_creador, monto_total, superficie_m2,
    estado, moneda, aplica_cac, mes_base_cac, revision, estado_servicio_especial,
    id_admin_creador, obra_madre_id
  ) values (
    'Adicional: ' || p_descripcion, v_madre.propietario, v_madre.ubicacion, v_madre.tipo_obra,
    v_madre.perfil_creador, 0, 0,
    'Cotización', v_madre.moneda, false, date_trunc('month', now())::date, 'Rev. 00', 'Ninguno',
    auth.uid(), p_obra_id
  )
  returning id into v_obra_hija_id;

  -- Pisa el default genérico (0020) con los valores REALES vigentes de la madre -- el trigger de
  -- bootstrap ya insertó una fila para v_obra_hija_id, así que acá es UPDATE, no INSERT.
  update obra_presupuesto_config dest
  set tipo_presupuesto = src.tipo_presupuesto,
      aplica_impuestos = src.aplica_impuestos,
      tipo_suelo = src.tipo_suelo,
      zona_sismorresistente = src.zona_sismorresistente,
      gg_pct = src.gg_pct,
      imprevistos_pct = src.imprevistos_pct,
      epp_pct = src.epp_pct,
      costo_financiero_pct = src.costo_financiero_pct,
      beneficio_pct = src.beneficio_pct,
      gestion_materiales_terceros_pct = src.gestion_materiales_terceros_pct,
      updated_at = now()
  from obra_presupuesto_config src
  where dest.obra_id = v_obra_hija_id and src.obra_id = p_obra_id;

  -- Mismo criterio: pisa los 4 impuestos default (IVA 21/IIBB 3/Tasas 1.5/Otro 0) con los
  -- porcentajes reales de la madre -- las 4 filas ya existen (mismo bootstrap), se actualizan por
  -- `tipo`, nunca se insertan de nuevo.
  update obra_impuestos dest
  set porcentaje = src.porcentaje,
      nombre_otro = src.nombre_otro
  from obra_impuestos src
  where dest.obra_id = v_obra_hija_id and src.obra_id = p_obra_id and dest.tipo = src.tipo;

  -- Equipo de la madre, foto -- `on conflict do nothing` porque el bootstrap ya insertó al
  -- creador como admin_maestro en la obra hija; si esa misma persona tiene además otros roles en
  -- la madre (combinación de roles), esos sí se copian, no chocan con el conflicto.
  insert into obra_members (
    obra_id, usuario_id, rol, invitado_por_usuario_id,
    puede_aprobar_certificados, puede_aprobar_adicionales, tope_monto_aprobacion,
    delegacion_inicio, delegacion_fin, puede_invitar_terceros, puede_ver_apu_ajena
  )
  select
    v_obra_hija_id, usuario_id, rol, invitado_por_usuario_id,
    puede_aprobar_certificados, puede_aprobar_adicionales, tope_monto_aprobacion,
    delegacion_inicio, delegacion_fin, puede_invitar_terceros, puede_ver_apu_ajena
  from obra_members
  where obra_id = p_obra_id and activo
  on conflict (obra_id, usuario_id, rol) do nothing;

  -- monto_total = 0 explícito (fix de esta migración): la columna es `not null` sin default
  -- (0002) y el trigger `calcular_monto_total_adicional` no la toca cuando `obra_hija_id` no es
  -- nulo -- el monto real se congela al aprobar (Tanda 2).
  insert into modificaciones_obra (
    obra_id, tipo, descripcion, cantidad, obra_hija_id, monto_total, solicitado_por, subido_por
  ) values (
    p_obra_id, 'adicional', p_descripcion, 1, v_obra_hija_id, 0, auth.uid(), auth.uid()
  )
  returning id into v_modificacion_id;

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (
    p_obra_id, auth.uid(), 'crear_adicional_presupuestado', 'modificacion_obra', v_modificacion_id,
    jsonb_build_object('obra_hija_id', v_obra_hija_id)
  );

  return v_modificacion_id;
end;
$$;

grant execute on function crear_adicional_presupuestado(uuid, text) to authenticated;
revoke execute on function crear_adicional_presupuestado(uuid, text) from public, anon;

-- =====================================================================
-- Verificación
-- =====================================================================
--
-- 1) En la app: Adicionales → "+" → "Presupuestar con la app" → descripción → Crear. Tiene que
--    navegar a las solapas de la obra hija, sin error.
-- 2) select id, obra_hija_id, costo_costo_base, monto_total, estado from modificaciones_obra
--    where tipo = 'adicional' order by fecha_solicitud desc limit 1;
--    -- obra_hija_id seteado, costo_costo_base null, monto_total = 0, estado 'pendiente'.
-- 3) El resto de la verificación de la 0113 (config/impuestos/equipo copiados de la madre) sigue
--    aplicando tal cual -- es la primera vez que la función llega a correr entera.
