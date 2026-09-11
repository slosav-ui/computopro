-- Certificados en obras USD -- las pantallas seguían mostrando el monto en pesos sin convertir
-- (Seba, probando el ciclo completo del certificado recién cerrado). El monto de un certificado
-- siempre se guarda en ARS (`certificados.monto`, igual que todo el sistema de precios) -- la
-- conversión a la moneda de la obra es puramente de visualización, nunca se hizo para
-- certificados (sí para el presupuesto vivo del dashboard, `ObrasListScreen._convertirMonto`).
--
-- Pregunta aparte que Seba hizo bien: un certificado YA EMITIDO, ¿se convierte a la cotización de
-- HOY o a la del momento en que se emitió? Su lectura es la correcta y es la que se implementa acá
-- -- la de emisión: el monto en pesos ya está congelado (`emitir_certificado` lo snapshotea desde
-- siempre), así que el número en dólares que se le mostró al cliente en su momento tampoco puede
-- moverse solo porque el dólar subió después -- mismo espíritu de "no retroactivo" que ya rige
-- todo lo demás de este ciclo (Factor K/impuestos, CAC, anticipo/fondo de reparo, todos
-- snapshoteados al emitir).
--
-- `cotizacion_dolar_bna` (0102) es una fila única, sin serie histórica -- no hay forma de mirar
-- "la cotización de tal fecha" después del hecho. Por eso hace falta un snapshot nuevo en
-- `certificados`, mismo patrón que `anticipo_pct_aplicado`/`fondo_reparo_pct_aplicado`/etc.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor), después de `0106`. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

alter table certificados
  add column cotizacion_dolar_promedio_al_emitir numeric;
-- null para certificados emitidos ANTES de esta migración -- no hay cómo reconstruir qué
-- cotización regía ese día (mismo criterio de "no retroactivo" del resto del proyecto). Del lado
-- de Dart, null se resuelve mostrando esos certificados viejos a la cotización de hoy -- la mejor
-- aproximación disponible, marcada como tal, no una reconstrucción real.

-- create or replace function emitir_certificado: mismo cuerpo que 0105, un solo agregado -- lee
-- cotizacion_dolar_bna (fila única) y snapshotea el promedio compra/venta, mismo criterio que ya
-- usa ObrasListScreen para el valor "Promedio Oficial BNA" (sin la proyección personalizada PRO,
-- que es puramente local a esa pantalla y nunca se persiste -- no hay nada que snapshotear de
-- eso). Si la fila de cotización no existe (no debería, viene sembrada desde 0102), el snapshot
-- queda null -- mismo fallback que un certificado viejo, no rompe la emisión por esto.
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
  v_cotizacion_promedio numeric;
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

  select * into v_exceso from calcular_excesos_certificado(p_certificado_id) limit 1;
  if v_exceso.obra_subitem_id is not null then
    raise exception '"%" ya tiene % certificado — quedan % disponibles, se intentó cargar %',
      v_exceso.descripcion, v_exceso.acumulado_previo, v_exceso.disponible, v_exceso.intentado;
  end if;

  select * into v_totales from calcular_totales_certificado(p_certificado_id);

  if v_totales.monto <= 0 then
    raise exception 'no se puede emitir un certificado sin avance cargado';
  end if;

  select (compra + venta) / 2 into v_cotizacion_promedio from cotizacion_dolar_bna limit 1;

  update certificados
  set estado = 'emitido',
      monto = v_totales.monto,
      monto_pactado = v_totales.monto_pactado,
      fecha_emision = now(),
      emitido_por = auth.uid(),
      dias_plazo_pago = v_totales.dias_plazo_pago,
      requiere_firma_fisica = p_requiere_firma_fisica,
      anticipo_pct_aplicado = v_totales.anticipo_pct,
      fondo_reparo_pct_aplicado = v_totales.fondo_reparo_pct,
      monto_anticipo_descontado = v_totales.monto_anticipo,
      monto_fondo_reparo_retenido = v_totales.monto_fondo_reparo,
      monto_neto_a_pagar = v_totales.monto_neto,
      cotizacion_dolar_promedio_al_emitir = v_cotizacion_promedio
  where id = p_certificado_id;

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (
    v_obra_id, auth.uid(), 'emitir_certificado', 'certificado', p_certificado_id,
    jsonb_build_object(
      'numero', v_numero,
      'monto', v_totales.monto,
      'monto_pactado', v_totales.monto_pactado,
      'monto_ajuste_cac', v_totales.monto_ajuste_cac,
      'requiere_firma_fisica', p_requiere_firma_fisica,
      'monto_neto_a_pagar', v_totales.monto_neto,
      'cotizacion_dolar_promedio_al_emitir', v_cotizacion_promedio
    )
  );
end;
$$;

grant execute on function emitir_certificado(uuid, boolean) to authenticated;

-- =====================================================================
-- Verificación
-- =====================================================================
--
-- 1) Emitir un certificado con avance cargado: cotizacion_dolar_promedio_al_emitir queda con el
--    promedio compra/venta vigente de cotizacion_dolar_bna en ese momento.
-- 2) Certificados YA emitidos antes de esta migración: cotizacion_dolar_promedio_al_emitir queda
--    null -- confirmar que Dart no rompe con ese caso (ver commit de Dart que acompaña esto).
-- 3) Cambiar cotizacion_dolar_bna (UPDATE manual) y volver a mirar un certificado ya emitido antes
--    del cambio: su cotizacion_dolar_promedio_al_emitir no se mueve -- congelada para siempre,
--    igual que el resto de los snapshots de este certificado.
