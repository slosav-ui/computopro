-- Adicionales, último paso de la Tanda 2: seguimiento de avance -- un porcentaje y un monto
-- certificado por adicional aprobado, SIN ciclo de vida propio (§4/§7-C de docs/adicionales_
-- quitas_demasias_diagnostico.md: "construir un segundo circuito de certificación reducido sería
-- duplicar lo que ya existe"). Diagnóstico y ambigüedades cerradas en §14 del mismo doc.
--
-- Decisiones de Seba (2026-09-12, §14.5):
-- - A: solo registro. El monto certificado de un adicional no entra a ningún certificado de la
--   obra ni pasa por emitido/leído/pagado; el cobro se gestiona afuera, como hasta ahora.
-- - B: certifican admin_maestro, profesional y constructor -- igual que la carga de avance de la
--   obra (0052). "Certificar avance no es emitir un certificado: es medir qué se hizo, y eso lo
--   hace el que está en la obra." (Corrige mi recomendación de dejarlo en admin/profesional.)
-- - C: cada carga es firme (sin borrador ni anulación, no hay ciclo) y el acumulado nunca baja; la
--   confirmación antes de guardar la pone la pantalla. Y queda registrado quién hizo cada carga:
--   una fila de audit_log por carga, con usuario (auth.uid(), lo inserta esta función -- no se
--   puede falsear desde la app), sus roles en la obra, el % del período y los montos.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor), después de 0119. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

-- =====================================================================
-- Paso 1 — columnas de seguimiento en modificaciones_obra
-- =====================================================================
--
-- En la propia fila del adicional, no en una tabla aparte (§4/§11.2-6): el seguimiento es un número
-- acumulado, no una lista de certificaciones con estado propio. El detalle de cada carga vive en
-- audit_log (Paso 2).
--
-- Solo un adicional APROBADO puede tener avance -- check en la base, no solo en la función. Para
-- todo lo demás (quitas, demasías, adicionales pendientes/rechazados) las dos columnas quedan en 0.
alter table modificaciones_obra
  add column porcentaje_avance numeric not null default 0,
  add column monto_certificado numeric not null default 0;

alter table modificaciones_obra
  add constraint modificaciones_obra_avance_rango_check
    check (porcentaje_avance >= 0 and porcentaje_avance <= 100 and monto_certificado >= 0),
  add constraint modificaciones_obra_avance_solo_aprobado_check
    check (
      (porcentaje_avance = 0 and monto_certificado = 0)
      or (tipo = 'adicional' and estado = 'aprobado')
    );

-- =====================================================================
-- Paso 2 — certificar_avance_adicional
-- =====================================================================
--
-- `p_porcentaje` es el avance DEL PERÍODO (lo que se suma), no el acumulado -- el mismo gesto que
-- la carga de avance de la obra (`porcentaje_periodo`, 0052): la pantalla muestra el acumulado y lo
-- disponible, y si se pasa ofrece certificar lo que queda. El candado real del 100% vive acá.
--
-- Autoridad (B): los mismos tres roles que `certificado_subitems_avance_insert` (0052). SECURITY
-- DEFINER porque la RLS de update no deja tocar filas de adicional desde la 0116 -- mismo patrón que
-- enviar/aprobar/rechazar.
--
-- Monto: se recalcula sobre el ACUMULADO nuevo (`monto_total × acumulado / 100`, redondeado), no
-- sumando los montos redondeados de cada carga -- así no se arrastra el error de redondeo. Al 100%
-- es exactamente `monto_total` (algún aprobado anterior a la 0118 puede tener más de 2 decimales:
-- redondearlo lo dejaría un pelo por encima o por debajo de lo aprobado). Sin ajuste por CAC: el
-- monto quedó fijo al aprobar (§10.1), y la obra hija nace con aplica_cac = false (0113).
--
-- Devuelve el acumulado nuevo.
create or replace function certificar_avance_adicional(
  p_modificacion_id uuid,
  p_porcentaje numeric
)
returns numeric
language plpgsql
security definer
set search_path = public
as $$
declare
  v_mod modificaciones_obra%rowtype;
  v_acumulado numeric;
  v_monto numeric;
begin
  select * into v_mod from modificaciones_obra where id = p_modificacion_id for update;
  if not found then
    raise exception 'adicional % no encontrado', p_modificacion_id;
  end if;

  if v_mod.tipo <> 'adicional' then
    raise exception 'modificación % no es un adicional -- el avance de la obra se carga en su certificado',
      p_modificacion_id;
  end if;

  if v_mod.estado <> 'aprobado' then
    raise exception 'solo se certifica avance de un adicional aprobado (estado actual: %)', v_mod.estado;
  end if;

  if not (tiene_rol_en_obra(v_mod.obra_id, 'admin_maestro')
          or tiene_rol_en_obra(v_mod.obra_id, 'profesional')
          or tiene_rol_en_obra(v_mod.obra_id, 'constructor')) then
    raise exception 'sin autoridad para certificar avance en esta obra -- administrador, profesional o constructor';
  end if;

  if p_porcentaje is null or p_porcentaje <= 0 then
    raise exception 'el avance del período tiene que ser mayor a 0';
  end if;

  v_acumulado := v_mod.porcentaje_avance + p_porcentaje;
  if v_acumulado > 100 then
    raise exception 'el avance supera el 100%% -- quedan % %% disponibles', 100 - v_mod.porcentaje_avance;
  end if;

  v_monto := case
    when v_acumulado = 100 then v_mod.monto_total
    else round(v_mod.monto_total * v_acumulado / 100, 2)
  end;

  -- El trigger calcular_monto_total_adicional no interviene: solo actúa sobre pendientes (0112).
  update modificaciones_obra
  set porcentaje_avance = v_acumulado,
      monto_certificado = v_monto
  where id = p_modificacion_id;

  -- C: quién hizo cada carga. `usuario_id` es la sesión real (auth.uid()); `roles`, con qué rol(es)
  -- estaba en la obra al cargar -- el constructor puede certificar, y audit_log es append-only.
  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (
    v_mod.obra_id, auth.uid(), 'certificar_avance_adicional', 'modificacion_obra', p_modificacion_id,
    jsonb_build_object(
      'porcentaje_periodo', p_porcentaje,
      'acumulado_anterior', v_mod.porcentaje_avance,
      'acumulado_nuevo', v_acumulado,
      'monto_periodo', v_monto - v_mod.monto_certificado,
      'monto_certificado', v_monto,
      'monto_total', v_mod.monto_total,
      'roles', (
        select string_agg(om.rol, '+' order by om.rol)
        from obra_members om
        where om.obra_id = v_mod.obra_id and om.usuario_id = auth.uid() and om.activo
      )
    )
  );

  return v_acumulado;
end;
$$;

grant execute on function certificar_avance_adicional(uuid, numeric) to authenticated;
revoke execute on function certificar_avance_adicional(uuid, numeric) from public, anon;

-- =====================================================================
-- Verificación
-- =====================================================================
--
-- Schema (SQL Editor):
-- 1) Las dos columnas existen, en 0 para todas las filas actuales.
-- 2) El check rechaza avance en algo que no es un adicional aprobado:
--    update modificaciones_obra set porcentaje_avance = 10 where tipo = 'quita' ... -- rechaza.
-- 3) `select has_function_privilege('anon', 'certificar_avance_adicional(uuid,numeric)', 'EXECUTE');`
--    -> false.
--
-- En la app (depende de auth.uid()), con un adicional aprobado:
-- 4) El constructor certifica +40%: porcentaje_avance 40, monto_certificado = 40% del monto
--    aprobado; fila en audit_log con su usuario_id y roles = 'constructor'.
-- 5) El profesional certifica +60%: acumulado 100, monto_certificado igual EXACTO a monto_total.
-- 6) Intentar +1% más: rechaza con "supera el 100% -- quedan 0% disponibles".
-- 7) El cliente intenta certificar: "sin autoridad".
-- 8) Un adicional pendiente o rechazado: "solo se certifica avance de un adicional aprobado".
-- 9) El historial de cargas:
--    select usuario_id, created_at, detalle from audit_log
--    where accion = 'certificar_avance_adicional' and entidad_id = '<id>' order by created_at;
