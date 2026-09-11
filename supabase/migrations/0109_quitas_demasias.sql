-- Quitas y Demasías — primer circuito de Adicionales/Quitas/Demasías, con Adicionales pospuesto a
-- propósito (decisión de Seba, ver docs/adicionales_quitas_demasias_diagnostico.md §8: quitas/
-- demasías reusan el 100% de la certificación existente, adicionales necesitan una pieza de
-- diseño todavía sin cerrar del todo -- no mezclar una pieza lista con una que no lo está).
--
-- Las 3 ambigüedades del diagnóstico, cerradas por Seba:
-- A. Aprobación de UNO solo (profesional o constructor), no de los dos.
-- B. (No aplica a esta migración -- es la regla de Adicionales, migración aparte.)
-- C. (Idem -- seguimiento de Adicionales, migración aparte.)
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor), después de `0108`. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

-- =====================================================================
-- Paso 1 -- el FK real: obra_subitem_id, no subitem_id (catálogo)
-- =====================================================================
--
-- `modificaciones_obra.subitem_id` (0002) referenciaría subitems(id) -- el catálogo compartido, no
-- "esta partida, en esta obra puntual". Corrección: columna nueva `obra_subitem_id`, obligatoria
-- para demasia/quita (son un ajuste de una partida que YA existe en el cómputo de esta obra),
-- prohibida para el resto (adicional no tiene partida existente que ajustar; ajuste_contrato ya
-- exige subitem_id/apu_privado_id nulos desde 0008, mismo criterio, columna nueva). `subitem_id`
-- (catálogo) queda sin usar para estos dos tipos, sin tocarlo -- por si algún otro caso lo
-- necesita más adelante.
--
-- OJO antes de correr: si por algún motivo ya hay filas de demasia/quita cargadas en producción
-- (no debería, no hay repositorio Dart que escriba en esta tabla todavía, confirmado), el `check`
-- de abajo fallaría sobre esas filas en vez de aplicarse a medias -- avisame si pasa, con el
-- mensaje exacto.
alter table modificaciones_obra
  add column obra_subitem_id uuid references obra_subitems(id);

alter table modificaciones_obra
  add constraint modificaciones_obra_obra_subitem_id_check check (
    (tipo in ('demasia', 'quita') and obra_subitem_id is not null)
    or (tipo not in ('demasia', 'quita') and obra_subitem_id is null)
  );

-- =====================================================================
-- Paso 2 -- puede_aprobar_quita_demasia: uno solo, profesional o constructor
-- =====================================================================
--
-- Deliberadamente angosta -- NO reusa `puede_aprobar_monto` (0004), que incluye admin_maestro,
-- profesional Y cliente_principal sin tope: verificado que esa función no gobierna hoy ningún
-- circuito real (cero referencias en lib/, sin repositorio de modificaciones_obra, sin pantalla de
-- ajuste_contrato) -- corregirla acá no cambia nada que ya funcione, pero de todos modos se la deja
-- intacta, sigue siendo la autoridad correcta para `ajuste_contrato` el día que se conecte.
--
-- Sin cliente_principal: confirmado, "al propietario se le informa, no se le pide permiso" -- una
-- demasía/quita no es su aprobación, es su información (ver Paso 5, audit_log). Sin
-- invitado_apoderado tampoco: la delegación de firma del Apoderado es para certificados/adicionales
-- (montos que el Cliente paga), no para correcciones de ejecución entre Profesional y Constructor.
create or replace function puede_aprobar_quita_demasia(p_obra_id uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select tiene_rol_en_obra(p_obra_id, 'profesional') or tiene_rol_en_obra(p_obra_id, 'constructor');
$$;

grant execute on function puede_aprobar_quita_demasia(uuid) to authenticated;
revoke execute on function puede_aprobar_quita_demasia(uuid) from public, anon;

-- =====================================================================
-- Paso 3 -- modificaciones_obra_update: ramifica por tipo, no un solo puede_aprobar_monto genérico
-- =====================================================================
--
-- demasia/quita usan la función nueva (Paso 2); todo lo demás (adicional, ajuste_contrato) sigue
-- exactamente igual que hoy, `puede_aprobar_monto` -- sin cambio de comportamiento para lo que no
-- se tocó en esta pieza. La rama `estado = 'devuelto' and subido_por = auth.uid()` (autocorrección)
-- queda igual para todos los tipos.
--
-- Misma deuda técnica ya aceptada explícitamente para `ajuste_contrato` (`0008`, documentada en
-- CLAUDE.md): esta política sigue permitiendo un `UPDATE` directo a `estado = 'aprobado'` sin pasar
-- por `aprobar_quita_demasia()` (Paso 4) -- quien lo haga así se salta la actualización de
-- `obra_subitems.cantidad` y de `presupuesto_subitems_congelado`. No se agrega ningún trigger para
-- impedirlo, mismo criterio ya aceptado: hoy Seba es el único con acceso directo a la base, y el
-- código Dart siempre va a llamar a la función.
drop policy modificaciones_obra_update on modificaciones_obra;

create policy modificaciones_obra_update on modificaciones_obra for update using (
  is_obra_member(obra_id)
  and (
    (tipo in ('demasia', 'quita') and puede_aprobar_quita_demasia(obra_id))
    or (tipo not in ('demasia', 'quita') and puede_aprobar_monto(obra_id, monto_total))
    or (estado = 'devuelto' and subido_por = auth.uid())
  )
) with check (
  (tipo in ('demasia', 'quita') and puede_aprobar_quita_demasia(obra_id))
  or (tipo not in ('demasia', 'quita') and puede_aprobar_monto(obra_id, monto_total))
  or subido_por = auth.uid()
);

-- =====================================================================
-- Paso 4 -- aprobar_quita_demasia: aprueba + ajusta cantidad + corrige el congelamiento si aplica
-- =====================================================================
--
-- El hallazgo central del diagnóstico (§5): si la obra ya está congelada, la certificación no lee
-- `obra_subitems` en vivo -- lee exclusivamente el snapshot de `presupuesto_subitems_congelado`
-- (`calcular_monto_obra_subitems`, rama congelada, `0105`). Tocar solo `obra_subitems.cantidad`
-- dejaría la demasía ejecutada pero imposible de certificar (o la quita, facturándose de más). Por
-- eso esta función corrige las DOS tablas en la misma transacción, nunca solo una.
--
-- La corrección al congelamiento reusa el precio YA CONGELADO de esa partida -- nunca recalcula
-- contra el precio de insumos de hoy (mismo principio que todo el congelamiento). Para partidas con
-- APU, `precio_final` congelado es un precio POR UNIDAD -- `cantidad_nueva × precio_final` es
-- exacto, sin aproximar. `costo_costo`/`materiales_subtotal` congelados son montos de la partida
-- COMPLETA (no por unidad, 0104 §5) -- se re-escalan en la misma proporción que la cantidad, para
-- que el futuro ajuste por CAC (que usa esa proporción, `0105`/`0106`) siga siendo correcto. Para
-- rubros de precio manual (`usa_apu = false`), no hay ningún precio unitario congelado guardado --
-- se deriva el implícito de la propia fila (`monto_total_congelado / cantidad_congelada`, tipo
-- 'unitario') o se deja sin cambios (tipo 'global', no depende de la cantidad). Límite conocido y
-- aceptado, no resuelto acá: una partida manual 'unitario' que quedó congelada en cantidad 0 no
-- tiene de dónde derivar un precio unitario -- esa fila queda con su `monto_total` sin cambios,
-- necesitaría un recongelamiento para corregirse bien.
create or replace function aprobar_quita_demasia(
  p_modificacion_id uuid,
  p_comentario text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_mod modificaciones_obra%rowtype;
  v_cantidad_actual numeric;
  v_cantidad_nueva numeric;
  v_congelado_en timestamptz;
  v_filas_congeladas int;
begin
  select * into v_mod from modificaciones_obra where id = p_modificacion_id;
  if not found then
    raise exception 'modificación % no encontrada', p_modificacion_id;
  end if;

  if v_mod.tipo not in ('demasia', 'quita') then
    raise exception 'modificación % no es de tipo demasia/quita -- usar el flujo correspondiente a "%"',
      p_modificacion_id, v_mod.tipo;
  end if;

  if v_mod.estado <> 'pendiente' then
    raise exception 'modificación % no está pendiente (estado actual: %)', p_modificacion_id, v_mod.estado;
  end if;

  if not puede_aprobar_quita_demasia(v_mod.obra_id) then
    raise exception 'sin autoridad para aprobar esta modificación -- solo profesional o constructor';
  end if;

  select cantidad into v_cantidad_actual from obra_subitems where id = v_mod.obra_subitem_id;
  if v_cantidad_actual is null then
    raise exception 'la partida de esta modificación ya no existe en el cómputo';
  end if;

  v_cantidad_nueva := case v_mod.tipo
    when 'demasia' then v_cantidad_actual + v_mod.cantidad
    when 'quita' then v_cantidad_actual - v_mod.cantidad
  end;

  if v_cantidad_nueva < 0 then
    raise exception 'la quita deja la cantidad en negativo -- actual %, quita %', v_cantidad_actual, v_mod.cantidad;
  end if;

  update obra_subitems
  set cantidad = v_cantidad_nueva, updated_at = now()
  where id = v_mod.obra_subitem_id;

  select presupuesto_congelado_en into v_congelado_en from obras where id = v_mod.obra_id;

  if v_congelado_en is not null then
    update presupuesto_subitems_congelado psc
    set cantidad = v_cantidad_nueva,
        monto_total = case
          when r.usa_apu then v_cantidad_nueva * psc.precio_final
          when r.tipo_precio_manual = 'global' then psc.monto_total
          when v_cantidad_actual <> 0 then psc.monto_total * v_cantidad_nueva / v_cantidad_actual
          else psc.monto_total -- no se puede derivar precio unitario desde cantidad 0, ver cabecera
        end,
        costo_costo = case
          when r.usa_apu and v_cantidad_actual <> 0
            then psc.costo_costo * v_cantidad_nueva / v_cantidad_actual
          else psc.costo_costo
        end,
        materiales_subtotal = case
          when r.usa_apu and v_cantidad_actual <> 0
            then psc.materiales_subtotal * v_cantidad_nueva / v_cantidad_actual
          else psc.materiales_subtotal
        end
    from obra_subitems os
    join rubros r on r.id = os.rubro_id
    where psc.obra_id = v_mod.obra_id and psc.obra_subitem_id = v_mod.obra_subitem_id
      and os.id = v_mod.obra_subitem_id;

    get diagnostics v_filas_congeladas = row_count;
    -- v_filas_congeladas en 0 es normal y esperable: la partida se tildó después del último
    -- congelamiento, todavía no forma parte de lo pactado -- nada que corregir ahí.
  end if;

  update modificaciones_obra
  set estado = 'aprobado',
      aprobado_por = auth.uid(),
      fecha_resolucion = now(),
      comentario_resolucion = p_comentario
  where id = p_modificacion_id;

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (
    v_mod.obra_id, auth.uid(), 'aprobar_quita_demasia', 'modificacion_obra', p_modificacion_id,
    jsonb_build_object(
      'tipo', v_mod.tipo,
      'cantidad_anterior', v_cantidad_actual,
      'cantidad_nueva', v_cantidad_nueva,
      'corrigio_congelamiento', v_congelado_en is not null
    )
  );
end;
$$;

grant execute on function aprobar_quita_demasia(uuid, text) to authenticated;
revoke execute on function aprobar_quita_demasia(uuid, text) from public, anon;

-- =====================================================================
-- Paso 5 -- informar al propietario: audit_log alcanza tal cual está, sin ninguna migración
-- =====================================================================
--
-- Verificado (§6 del diagnóstico): `audit_log_insert` (0004) ya deja que cualquier miembro de la
-- obra, incluido cliente_principal, inserte su propia fila -- y no hay política de UPDATE/DELETE
-- para nadie, append-only por diseño. Una observación del propietario no puede trabar nada porque
-- no hay ningún mecanismo por el que insertar ahí toque el `estado` de la modificación que
-- comenta. Nada que migrar acá -- el repositorio Dart arma el insert directo
-- (`accion='observar_modificacion'`, `entidad='modificacion_obra'`, `entidad_id=<id>`,
-- `detalle={comentario:...}`), ver lista de archivos.

-- =====================================================================
-- Verificación
-- =====================================================================
--
-- 1) `obra_subitem_id` y el nuevo `check`: intentar insertar una demasía sin `obra_subitem_id`
--    tiene que fallar; una con `obra_subitem_id` cargado tiene que aceptarse.
-- 2) Desde una cuenta `cliente_principal` (o `admin_maestro` puro, sin profesional/constructor
--    combinado): `aprobar_quita_demasia` tiene que rechazar con "sin autoridad...".
-- 3) Caso real, obra SIN congelar: aprobar una demasía de +2 sobre una partida con cantidad 10 --
--    `obra_subitems.cantidad` pasa a 12, `presupuesto_subitems_congelado` no se toca (no hay fila).
-- 4) Caso real, obra CONGELADA: misma demasía -- `obra_subitems.cantidad` y la fila de
--    `presupuesto_subitems_congelado` (cantidad, monto_total, costo_costo, materiales_subtotal)
--    quedan consistentes, todas escaladas a la nueva cantidad. `calcular_saldo_pendiente_avance_medido`
--    de esa obra tiene que reflejar el monto nuevo sin volver a congelar nada.
-- 5) Certificar avance sobre esa partida después de la demasía: el monto_periodo del próximo
--    certificado se calcula contra el `monto_total` corregido, sin ningún cambio en
--    `calcular_avance_acumulado_subitem` ni en el candado del 100%.
-- 6) Una quita que dejaría la cantidad en negativo -- rechaza con el mensaje explícito, no permite
--    una cantidad negativa en ningún lado.
