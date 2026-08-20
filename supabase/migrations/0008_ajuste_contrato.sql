-- Modelos de Certificación, paso 3: modificaciones_obra gana el tipo 'ajuste_contrato', y una
-- función aprobar_ajuste_contrato() que aprueba + aplica el delta a
-- obras.monto_total_contratado + registra audit_log, todo atómico.
-- Ver docs/modelos_certificacion_diseno_datos.md, sección 7.7-bis, para el diseño completo.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.
--
-- Motivación (§7.7 del diseño): un aumento de monto_total_contratado es plata que termina
-- pagando el Cliente, mismo peso que un Adicional — no puede ser una edición libre del
-- Administrador. La carga INICIAL de monto_total_contratado (primera vez, valor null -> un
-- número) sigue siendo edición directa simple, sin cambios acá. Los cambios POSTERIORES a un
-- valor ya cargado pasan por acá.

-- =====================================================================
-- modificaciones_obra: nuevo tipo 'ajuste_contrato'
-- =====================================================================
--
-- Se asume que el check constraint original (0002_modificaciones_obra_audit_log.sql, columna
-- 'tipo' sin nombre explícito) quedó con el nombre por defecto que le da Postgres a un check de
-- una sola columna: modificaciones_obra_tipo_check. Si el DROP de abajo falla porque el nombre
-- real es otro, revisar con \d modificaciones_obra (o Table Editor -> Definition) y ajustar el
-- nombre antes de reintentar — no vuelve a intentar con otro nombre automáticamente.
alter table modificaciones_obra
  drop constraint modificaciones_obra_tipo_check;

alter table modificaciones_obra
  add constraint modificaciones_obra_tipo_check
  check (tipo in ('adicional', 'demasia', 'quita', 'ajuste_contrato'));

-- Para tipo='ajuste_contrato' (§7.7-bis): sin subitem_id/apu_privado_id (no hay cómputo métrico
-- de por medio en Modelo B), y cantidad coincide con monto_total (no hay cantidad física
-- distinta de un precio unitario, es un ajuste puramente monetario al contrato). El signo de
-- monto_total indica el sentido: positivo = aumenta monto_total_contratado, negativo = lo
-- reduce.
alter table modificaciones_obra
  add constraint modificaciones_obra_ajuste_contrato_check
  check (
    tipo <> 'ajuste_contrato'
    or (subitem_id is null and apu_privado_id is null and cantidad = monto_total)
  );

-- =====================================================================
-- aprobar_ajuste_contrato: aprobar + aplicar delta a obras + audit_log, atómico
-- =====================================================================
--
-- SECURITY INVOKER: corre como el usuario que llama, así que las políticas RLS ya existentes de
-- modificaciones_obra (puede_aprobar_monto) y audit_log se aplican tal cual — mismo criterio que
-- cambiar_modelo_certificacion() del paso 1 (0005_modelo_certificacion.sql).
--
-- El WHERE ... and estado = 'pendiente' en el update de modificaciones_obra hace que una segunda
-- llamada sobre la misma fila ya aprobada no vuelva a aplicar el delta dos veces (afecta 0 filas,
-- FOUND queda false, la función corta antes de tocar obras) — no hace falta una columna extra de
-- "ya aplicado" para evitar la doble aplicación.
--
-- Reusa puede_aprobar_monto(obra_id, monto) (de 0004_rls_etapa3.sql) como cadena de autoridad —
-- misma que ya resuelve la aprobación de adicionales/demasías/quitas. Punto marcado como abierto
-- en el diseño (§8): si la aprobación de un ajuste_contrato necesita una cadena distinta a la de
-- un adicional normal, esto hay que revisarlo — no se resolvió acá, se asumió que es la misma.
--
-- Limitación conocida, NO resuelta en esta migración (documentada para que quede explícita, no
-- porque se haya decidido ignorarla): esta función es el camino sancionado, pero no es el único
-- camino técnicamente posible. La política modificaciones_obra_update ya existente (genérica,
-- para los 4 tipos) sigue permitiendo un UPDATE directo de estado a 'aprobado' sobre una fila de
-- tipo ajuste_contrato sin pasar por esta función — en ese caso la modificacion_obra queda
-- aprobada pero el delta nunca se aplica a obras.monto_total_contratado ni se genera el
-- audit_log específico de acá. Es la misma clase de limitación que ya tiene 'adicional' hoy (su
-- graduación a Subitem real tampoco está forzada a nivel de base, es efecto de app) — se
-- mantuvo así a propósito por consistencia (§7.7-bis del diseño: "no vía trigger de base, para
-- mantener consistencia con cómo ya funciona modificaciones_obra"), no por descuido. Cerrar esto
-- del todo requeriría además restringir la política de UPDATE existente o agregar un trigger en
-- obras — ninguna de las dos cosas se hizo acá; avisar si se prefiere esa vía más estricta.
--
-- Tampoco hay ninguna restricción de base que impida editar monto_total_contratado directamente
-- una vez que ya tiene un valor cargado (la regla "solo carga inicial es edición libre" de
-- §7.7-bis queda como convención de la capa de app/UI, no forzada en la base) — mismo criterio
-- de "no trigger" de arriba.
create or replace function aprobar_ajuste_contrato(
  p_modificacion_id uuid,
  p_comentario text default null
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_obra_id uuid;
  v_tipo text;
  v_monto numeric;
begin
  select obra_id, tipo, monto_total
    into v_obra_id, v_tipo, v_monto
  from modificaciones_obra
  where id = p_modificacion_id and estado = 'pendiente';

  if v_obra_id is null then
    raise exception 'modificacion_obra % no encontrada, o ya no está pendiente', p_modificacion_id;
  end if;

  if v_tipo <> 'ajuste_contrato' then
    raise exception 'modificacion_obra % no es de tipo ajuste_contrato — usar el flujo de aprobación genérico', p_modificacion_id;
  end if;

  if not puede_aprobar_monto(v_obra_id, v_monto) then
    raise exception 'sin autoridad de aprobación para este monto en esta obra';
  end if;

  update modificaciones_obra
  set estado = 'aprobado',
      aprobado_por = auth.uid(),
      fecha_resolucion = now(),
      comentario_resolucion = p_comentario
  where id = p_modificacion_id and estado = 'pendiente';

  if not found then
    raise exception 'modificacion_obra % ya no está pendiente (aprobación concurrente)', p_modificacion_id;
  end if;

  update obras
  set monto_total_contratado = coalesce(monto_total_contratado, 0) + v_monto
  where id = v_obra_id;

  if not found then
    raise exception 'sin permiso para actualizar el monto_total_contratado de esta obra';
  end if;

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (
    v_obra_id, auth.uid(), 'aprobar_ajuste_contrato', 'modificacion_obra', p_modificacion_id,
    jsonb_build_object('delta_monto_total_contratado', v_monto)
  );
end;
$$;

grant execute on function aprobar_ajuste_contrato(uuid, text) to authenticated;
