-- Bug real encontrado por Seba probando la línea "Total con adicionales" (2026-09-12): no aparecía
-- porque el único adicional aprobado tenía monto_total = 0; otro, pendiente, tenía un monto con
-- decenas de decimales.
--
-- Revisado contra el código, no supuesto: `aprobar_adicional` (0116) SÍ rechaza un adicional
-- presupuestado sin enviar ("todavía no fue enviado para aprobación"), y la pantalla no ofrece
-- Aprobar en ese caso. Por la función no se puede aprobar uno sin enviar. Quedan dos caminos que
-- explican un aprobado en 0 -- la consulta de diagnóstico de abajo dice cuál fue:
-- 1) enviado en $ 0: `enviar_adicional_a_aprobacion` aceptaba una suma congelada de 0 (partidas
--    tildadas con cantidad 0, el default, o sin precio). Agujero real -- ESTA migración lo cierra,
--    en enviar y en aprobar;
-- 2) aprobado por un UPDATE directo, sin pasar por la función: antes de la 0116 (la política vieja lo
--    permitía) o desde el SQL Editor, que corre como `postgres` y saltea la RLS. Desde la 0116 no se
--    alcanza desde la app; el SQL Editor es la misma deuda ya aceptada para ajuste_contrato (0008):
--    hoy Seba es el único con acceso directo a la base.
--
-- Y el redondeo (mismo caso que la 0078): `calcular_precio_adicional` y la suma congelada salían con
-- toda la escala acumulada de `numeric`. Se redondea a 2 decimales en la salida de las tres
-- funciones. Montos ya aprobados o rechazados: no se tocan (son números resueltos, mismo principio
-- de "no retroactivo" de todo el proyecto). Pendientes: se redondean al final de esta migración.
--
-- Diagnóstico del adicional aprobado en 0 (correr en el SQL Editor, solo lectura):
--   select m.id, m.descripcion, m.obra_hija_id, m.costo_costo_base, m.enviado_a_aprobacion_en,
--          m.monto_total, m.estado, m.aprobado_por, m.fecha_resolucion,
--          (select string_agg(a.accion || ' ' || to_char(a.created_at, 'DD/MM HH24:MI'), ', '
--                             order by a.created_at)
--             from audit_log a where a.entidad_id = m.id) as historial
--   from modificaciones_obra m
--   where m.tipo = 'adicional'
--   order by m.fecha_solicitud;
--   - costo_costo_base = 0 -> monto fijo tipeado en 0: no es un agujero, ese es el precio;
--   - obra_hija_id y enviado_a_aprobacion_en seteados, historial con enviar + aprobar -> camino 1;
--   - estado 'aprobado' sin 'aprobar_adicional' en el historial -> camino 2 (UPDATE directo).
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor), después de 0117. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

-- =====================================================================
-- Paso 1 — calcular_precio_adicional: redondeo de salida
-- =====================================================================

create or replace function calcular_precio_adicional(
  p_obra_id uuid,
  p_costo_costo_base numeric,
  p_incluye_impuestos boolean
)
returns numeric
language sql security definer set search_path = public stable as $$
  with autorizado as (
    select is_obra_member(p_obra_id) as ok
  ),
  config as (
    select gg_pct, imprevistos_pct, epp_pct, costo_financiero_pct, beneficio_pct
    from obra_presupuesto_config c
    cross join autorizado a
    where c.obra_id = p_obra_id and a.ok
  ),
  impuestos as (
    select coalesce(sum(oi.porcentaje), 0) / 100 as impuestos_pct_total
    from obra_impuestos oi
    cross join autorizado a
    where oi.obra_id = p_obra_id and a.ok
  ),
  costo_total_trabajo as (
    -- Mismo producto de factores que la cascada real (0077), acotado a los 5 conceptos que
    -- aplican acá -- ver la simplificación explicada en la cabecera de este archivo.
    select
      coalesce(p_costo_costo_base, 0)
        * (1 + co.gg_pct / 100) * (1 + co.imprevistos_pct / 100) * (1 + co.epp_pct / 100)
        * (1 + co.costo_financiero_pct / 100) * (1 + co.beneficio_pct / 100) as v
    from config co
  )
  -- Redondeo a 2 decimales SOLO en la salida (0118, mismo criterio que 0078): la cadena de
  -- multiplicaciones de `numeric` va sumando escala en cada paso y el monto salía con decenas de
  -- decimales. Como el trigger, la vista previa y aprobar_adicional pasan todos por acá, los tres
  -- ven el mismo número.
  select round(ctt.v * (1 + case when p_incluye_impuestos then imp.impuestos_pct_total else 0 end), 2)
  from costo_total_trabajo ctt
  cross join impuestos imp;
$$;

-- =====================================================================
-- Paso 2 — enviar_adicional_a_aprobacion: suma redondeada, y nunca en $ 0
-- =====================================================================
--
-- Idéntica a la 0116 salvo el bloque marcado "0118".

create or replace function enviar_adicional_a_aprobacion(p_modificacion_id uuid)
returns numeric
language plpgsql
security definer
set search_path = public
as $$
declare
  v_mod modificaciones_obra%rowtype;
  v_obra_madre_id uuid;
  v_monto numeric;
begin
  select * into v_mod from modificaciones_obra where id = p_modificacion_id for update;
  if not found then
    raise exception 'adicional % no encontrado', p_modificacion_id;
  end if;

  if not is_obra_member(v_mod.obra_id) then
    raise exception 'sin autoridad sobre esta obra';
  end if;

  if v_mod.tipo <> 'adicional' or v_mod.obra_hija_id is null then
    raise exception 'solo un adicional presupuestado con la app se envía para aprobación';
  end if;

  if v_mod.estado <> 'pendiente' then
    raise exception 'el adicional ya no está pendiente (estado actual: %)', v_mod.estado;
  end if;

  select obra_madre_id into v_obra_madre_id from obras where id = v_mod.obra_hija_id;
  if v_obra_madre_id is distinct from v_mod.obra_id then
    raise exception 'la obra del adicional no pertenece a esta obra';
  end if;

  insert into obra_members (
    obra_id, usuario_id, rol, invitado_por_usuario_id,
    puede_aprobar_certificados, puede_aprobar_adicionales, tope_monto_aprobacion,
    delegacion_inicio, delegacion_fin, puede_invitar_terceros, puede_ver_apu_ajena
  )
  select
    v_mod.obra_hija_id, usuario_id, rol, invitado_por_usuario_id,
    puede_aprobar_certificados, puede_aprobar_adicionales, tope_monto_aprobacion,
    delegacion_inicio, delegacion_fin, puede_invitar_terceros, puede_ver_apu_ajena
  from obra_members
  where obra_id = v_mod.obra_id and activo
  on conflict (obra_id, usuario_id, rol) do nothing;

  if not (tiene_rol_en_obra(v_mod.obra_hija_id, 'admin_maestro')
          or tiene_rol_en_obra(v_mod.obra_hija_id, 'profesional')) then
    raise exception 'solo quien cotiza el adicional (administrador o profesional) puede enviarlo para aprobación';
  end if;

  perform presentar_presupuesto_obra(v_mod.obra_hija_id);
  perform congelar_presupuesto_obra(v_mod.obra_hija_id);

  select round(coalesce(sum(monto_total), 0), 2) into v_monto
  from presupuesto_subitems_congelado
  where obra_id = v_mod.obra_hija_id;

  -- 0118: no se envía un presupuesto en $ 0 -- el caso real son partidas tildadas con cantidad 0
  -- (el default de obra_subitems.cantidad) o sin precio. Un adicional enviado en 0 pasaría
  -- cualquier tope de aprobación, el mismo agujero que la 0116 cerró para uno sin enviar. La
  -- excepción revierte también el presentar/congelar de arriba.
  if v_monto <= 0 then
    raise exception 'el presupuesto del adicional da $ 0 -- revisá que las partidas tildadas tengan cantidad y precio antes de enviarlo';
  end if;

  -- El trigger `calcular_monto_total_adicional` no toca esta fila (obra_hija_id no nulo, 0113), así
  -- que el monto que se escribe acá es el que queda.
  update modificaciones_obra
  set monto_total = v_monto,
      enviado_a_aprobacion_en = now()
  where id = p_modificacion_id;

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (
    v_mod.obra_id, auth.uid(), 'enviar_adicional_a_aprobacion', 'modificacion_obra', p_modificacion_id,
    jsonb_build_object(
      'obra_hija_id', v_mod.obra_hija_id,
      'monto', v_monto,
      'reenvio', v_mod.enviado_a_aprobacion_en is not null
    )
  );

  return v_monto;
end;
$$;

-- =====================================================================
-- Paso 3 — aprobar_adicional: suma redondeada, y nunca un presupuestado en $ 0
-- =====================================================================
--
-- Idéntica a la 0116 salvo el bloque marcado "0118". Los pendientes que ya tenían el monto sin
-- redondear se siguen pudiendo aprobar: `p_monto_visto` (sin redondear) y el monto de acá
-- (redondeado) difieren en menos de medio centavo, dentro de la tolerancia de 0,01.

create or replace function aprobar_adicional(
  p_modificacion_id uuid,
  p_monto_visto numeric,
  p_comentario text default null
)
returns numeric
language plpgsql
security definer
set search_path = public
as $$
declare
  v_mod modificaciones_obra%rowtype;
  v_obra_madre_id uuid;
  v_monto numeric;
begin
  select * into v_mod from modificaciones_obra where id = p_modificacion_id for update;
  if not found then
    raise exception 'adicional % no encontrado', p_modificacion_id;
  end if;

  if v_mod.tipo <> 'adicional' then
    raise exception 'modificación % no es un adicional -- usar el flujo correspondiente a "%"',
      p_modificacion_id, v_mod.tipo;
  end if;

  if v_mod.estado <> 'pendiente' then
    raise exception 'el adicional ya no está pendiente (estado actual: %)', v_mod.estado;
  end if;

  if not puede_rechazar_adicional(v_mod.obra_id) then
    raise exception 'sin autoridad para aprobar adicionales en esta obra -- solo el cliente principal o un apoderado habilitado';
  end if;

  if v_mod.obra_hija_id is null then
    v_monto := calcular_precio_adicional(v_mod.obra_id, v_mod.costo_costo_base, v_mod.incluye_impuestos);
  else
    select obra_madre_id into v_obra_madre_id from obras where id = v_mod.obra_hija_id;
    if v_obra_madre_id is distinct from v_mod.obra_id then
      raise exception 'la obra del adicional no pertenece a esta obra';
    end if;

    if v_mod.enviado_a_aprobacion_en is null then
      raise exception 'el adicional todavía no fue enviado para aprobación -- quien lo cotiza tiene que enviarlo primero';
    end if;

    select round(sum(monto_total), 2) into v_monto
    from presupuesto_subitems_congelado
    where obra_id = v_mod.obra_hija_id;

    -- 0118: mismo candado que en enviar, para lo que ya se haya enviado en $ 0 antes de esta
    -- migración -- se corrige el cómputo y se reenvía, no se aprueba un cero. (Un adicional de
    -- monto fijo tipeado en 0 sí se puede aprobar: ese cero es el precio que puso quien lo cotiza,
    -- no un monto que faltó congelar.)
    if v_monto <= 0 then
      raise exception 'el adicional se envió en $ 0 -- quien lo cotiza tiene que corregir el cómputo y reenviarlo';
    end if;
  end if;

  if v_monto is null then
    raise exception 'no se pudo calcular el monto del adicional';
  end if;

  if p_monto_visto is null or abs(v_monto - p_monto_visto) > 0.01 then
    raise exception 'el monto del adicional cambió desde que lo abriste (ahora: %) -- volvé a abrirlo antes de aprobar',
      round(v_monto, 2);
  end if;

  if not puede_aprobar_adicional(v_mod.obra_id, v_monto) then
    raise exception 'el monto del adicional supera tu tope de aprobación';
  end if;

  update modificaciones_obra
  set estado = 'aprobado',
      monto_total = v_monto,
      aprobado_por = auth.uid(),
      fecha_resolucion = now(),
      comentario_resolucion = p_comentario
  where id = p_modificacion_id;

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (
    v_mod.obra_id, auth.uid(), 'aprobar_adicional', 'modificacion_obra', p_modificacion_id,
    jsonb_build_object(
      'monto', v_monto,
      'camino', case when v_mod.obra_hija_id is null then 'monto_fijo' else 'obra_hija' end,
      'obra_hija_id', v_mod.obra_hija_id,
      'rol_aprobador', case
        when tiene_rol_en_obra(v_mod.obra_id, 'cliente_principal') then 'cliente_principal'
        else 'invitado_apoderado'
      end,
      'comentario', p_comentario
    )
  );

  return v_monto;
end;
$$;

-- `create or replace` conserva los grants; se repiten igual, mismo patrón que el resto.
grant execute on function calcular_precio_adicional(uuid, numeric, boolean) to authenticated;
revoke execute on function calcular_precio_adicional(uuid, numeric, boolean) from public, anon;
grant execute on function enviar_adicional_a_aprobacion(uuid) to authenticated;
revoke execute on function enviar_adicional_a_aprobacion(uuid) from public, anon;
grant execute on function aprobar_adicional(uuid, numeric, text) to authenticated;
revoke execute on function aprobar_adicional(uuid, numeric, text) from public, anon;

-- =====================================================================
-- Paso 4 — redondear los pendientes que ya existen
-- =====================================================================
--
-- Con el trigger apagado SOLO durante este update: en el SQL Editor no hay auth.uid(), así que
-- `calcular_precio_adicional` (que exige membresía) devolvería null y el trigger dejaría monto_total
-- en null -- rechazado por el `not null`. Acá no hace falta recalcular nada, solo redondear el número
-- que ya está. Aprobados/rechazados, sin tocar (ver cabecera).
alter table modificaciones_obra disable trigger modificaciones_obra_calcular_monto_adicional;

update modificaciones_obra
set monto_total = round(monto_total, 2)
where tipo = 'adicional' and estado = 'pendiente' and monto_total <> round(monto_total, 2);

alter table modificaciones_obra enable trigger modificaciones_obra_calcular_monto_adicional;

-- =====================================================================
-- Verificación
-- =====================================================================
--
-- 1) La consulta de diagnóstico de la cabecera: el pendiente que tenía decenas de decimales ahora
--    tiene 2; el aprobado en 0 sigue igual (no se toca) -- el historial dice cómo llegó ahí.
-- 2) `select tgenabled from pg_trigger where tgname = 'modificaciones_obra_calcular_monto_adicional';`
--    -> 'O' (el trigger quedó prendido de nuevo).
-- 3) En la app: crear un adicional de monto fijo -- la vista previa y el monto guardado, con 2
--    decimales como máximo.
-- 4) En la app: adicional presupuestado con una partida tildada y cantidad 0 -> "Enviar para
--    aprobación" rechaza con "el presupuesto del adicional da $ 0"; con cantidad cargada, envía, y
--    el monto enviado tiene 2 decimales.
-- 5) Aprobar el que se envió en el punto 4: funciona igual que antes, monto aprobado con 2 decimales.
