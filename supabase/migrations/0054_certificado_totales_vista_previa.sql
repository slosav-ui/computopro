-- Gestión de Obra, pieza 4, tanda 1: vista previa del certificado antes de emitir + el botón de
-- emitir en sí. Sin cambios de schema — solo funciones nuevas y un `emitir_certificado` que las
-- usa en vez de recalcular inline.
--
-- Motivo (pedido explícito del usuario, no repetirlo en Dart): "no dupliques la cuenta en Dart —
-- que sea una función que devuelva lo mismo que va a congelar la emisión." Se sacan de
-- emitir_certificado (0052) las dos cuentas que la vista previa necesita ver de antemano — el
-- desglose de montos (subtotal/anticipo/fondo de reparo/neto) y el chequeo del 100% acumulado —
-- a dos funciones nuevas, y emitir_certificado pasa a llamarlas en vez de tener la cuenta inline.
-- El número que ve la vista previa es matemáticamente el mismo que se congela al emitir, porque
-- es la misma consulta corriendo dos veces, no dos implementaciones del mismo cálculo.
--
-- Alcance deliberado de esta tanda (acordado con el usuario): solo esto. La anulación (columna
-- `version`, estado `anulado`, propuesta/aprobación entre profesional y constructor, el ajuste de
-- calcular_avance_acumulado_subitem y el bug de `numero - 1` sin filtrar versión en
-- emitir_certificado) es la tanda 2, con su propia migración, después de que esta se verifique y
-- se commitee.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

-- =====================================================================
-- calcular_totales_certificado — el desglose completo, una sola vez
-- =====================================================================
--
-- SECURITY INVOKER (sin `security definer`), mismo criterio que calcular_avance_acumulado_subitem
-- (0052): las tablas que toca (certificados, certificado_subitems_avance, obras) ya tienen su
-- propia RLS abierta a is_obra_member — para un no-miembro, esas políticas ya devuelven 0 filas
-- solas, no hace falta bypassearlas acá.
--
-- Devuelve también anticipo_pct/fondo_reparo_pct/dias_plazo_pago (no solo los montos derivados):
-- emitir_certificado los necesita tal cual para snapshotearlos en las columnas
-- *_pct_aplicado/dias_plazo_pago, y así no vuelve a consultar `obras` por su cuenta — una sola
-- fuente para todo lo que hay que congelar.
create or replace function calcular_totales_certificado(p_certificado_id uuid)
returns table(
  monto numeric,
  anticipo_pct numeric,
  fondo_reparo_pct numeric,
  monto_anticipo numeric,
  monto_fondo_reparo numeric,
  monto_neto numeric,
  dias_plazo_pago int
)
language sql stable as $$
  with cert as (
    select c.obra_id from certificados c where c.id = p_certificado_id
  ),
  monto as (
    select coalesce(sum(csa.monto_periodo), 0) as v
    from certificado_subitems_avance csa
    where csa.certificado_id = p_certificado_id
  )
  select
    m.v as monto,
    o.anticipo_pct,
    o.fondo_reparo_pct,
    round(m.v * coalesce(o.anticipo_pct, 0) / 100, 2) as monto_anticipo,
    round(m.v * coalesce(o.fondo_reparo_pct, 0) / 100, 2) as monto_fondo_reparo,
    m.v
      - round(m.v * coalesce(o.anticipo_pct, 0) / 100, 2)
      - round(m.v * coalesce(o.fondo_reparo_pct, 0) / 100, 2) as monto_neto,
    o.dias_plazo_pago_certificados as dias_plazo_pago
  from cert c
  join obras o on o.id = c.obra_id
  cross join monto m;
$$;

grant execute on function calcular_totales_certificado(uuid) to authenticated;

-- =====================================================================
-- calcular_excesos_certificado — qué subitems de este borrador superan el 100% acumulado
-- =====================================================================
--
-- Misma cuenta que hacía el loop de emitir_certificado, ahora reusable desde la vista previa:
-- antes el usuario solo se enteraba de un exceso al intentar emitir; con esto la pantalla de
-- revisión lo puede mostrar de entrada. Devuelve TODAS las filas que exceden (no solo la primera)
-- — mejor para la vista previa, que puede listarlas todas de una vez en vez de una por intento.
create or replace function calcular_excesos_certificado(p_certificado_id uuid)
returns table(
  obra_subitem_id uuid,
  descripcion text,
  acumulado_previo numeric,
  disponible numeric,
  intentado numeric
)
language sql stable as $$
  with base as (
    select
      csa.obra_subitem_id,
      coalesce(s.descripcion, os.descripcion_libre, 'subítem sin descripción') as descripcion,
      csa.porcentaje_periodo as intentado,
      calcular_avance_acumulado_subitem(csa.obra_subitem_id) as acumulado_previo
    from certificado_subitems_avance csa
    join obra_subitems os on os.id = csa.obra_subitem_id
    left join subitems s on s.id = os.subitem_id
    where csa.certificado_id = p_certificado_id
  )
  select
    obra_subitem_id,
    descripcion,
    round(acumulado_previo, 2) as acumulado_previo,
    round(100 - acumulado_previo, 2) as disponible,
    intentado
  from base
  where intentado > round(100 - acumulado_previo, 2);
$$;

grant execute on function calcular_excesos_certificado(uuid) to authenticated;

-- =====================================================================
-- emitir_certificado — create or replace: mismo cuerpo, con la cuenta de 100% y de montos
-- delegada a las dos funciones de arriba en vez de calculada inline
-- =====================================================================
--
-- Sin cambios de comportamiento respecto a la versión de 0052: mismos mensajes de error, misma
-- secuencia de chequeos, mismo resultado final. El bug de `numero = v_numero - 1` sin filtrar
-- versión (encontrado en el diagnóstico de esta pieza) queda intacto a propósito — no existe
-- ninguna columna `version` todavía, se corrige en la tanda 2 junto con el resto de la anulación.
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
  v_prev_requiere_firma boolean;
  v_prev_pdf_subido boolean;
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

  -- Bloqueo de firma física: el certificado anterior de la misma obra, si existe, no puede tener
  -- pendiente su PDF firmado.
  select requiere_firma_fisica, pdf_firmado_subido
    into v_prev_requiere_firma, v_prev_pdf_subido
  from certificados
  where obra_id = v_obra_id and numero = v_numero - 1;

  if v_prev_requiere_firma is true and coalesce(v_prev_pdf_subido, false) = false then
    raise exception 'el certificado anterior (N° %) requiere firma física y todavía no se subió el PDF firmado', v_numero - 1;
  end if;

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

-- 1) Las 2 funciones nuevas existen.
select proname from pg_proc
where proname in ('calcular_totales_certificado', 'calcular_excesos_certificado');

-- 2) Con un Borrador de prueba que tenga avance cargado: calcular_totales_certificado tiene que
--    devolver el mismo monto que la suma manual de certificado_subitems_avance.monto_periodo de
--    ese certificado, y el mismo anticipo/fondo de reparo/neto que ya se veía al emitir antes de
--    esta migración.
-- select * from calcular_totales_certificado(:certificado_id);

-- 3) Con un Borrador donde algún subítem exceda el 100% acumulado: calcular_excesos_certificado
--    tiene que devolver esa fila (antes de intentar emitir), y emitir_certificado tiene que seguir
--    fallando con el mismo mensaje de siempre si se intenta emitir igual.
-- select * from calcular_excesos_certificado(:certificado_id);

-- 4) Caso feliz: emitir un Borrador sin excesos tiene que dejar certificados.monto igual a la
--    suma de monto_periodo, y anticipo/fondo de reparo/neto coherentes con obras.anticipo_pct/
--    fondo_reparo_pct — mismo resultado que daba la versión anterior de la función.
