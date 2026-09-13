-- 0122 -- Cotización congelada de los montos cerrados (Nivel 1 del diagnóstico de monedas)
--
-- El problema, en palabras de Seba (2026-09-13): *"si el número en dólares que le mostré al cliente
-- se mueve solo cuando sube el dólar, ese monto no está cerrado"*. Y con la cotización proyectada
-- editable del dashboard, se mueven todos a la vez.
--
-- Estado que corrige: todo el sistema de precios guarda pesos y `obras.moneda` es de visualización.
-- Una obra en dólares mostraba el **presupuesto pactado** y cada **adicional aprobado** dividiendo
-- el monto fijo en pesos por la cotización *del día en que se los mira* -- así que el número en USD
-- que el cliente vio al firmar cambiaba solo. Los certificados ya no tienen este problema: la 0107
-- les agregó `cotizacion_dolar_promedio_al_emitir` con este razonamiento textual: *"el número en
-- dólares que se le mostró al cliente en su momento tampoco puede moverse solo porque el dólar
-- subió después"*. Esta migración extiende ese mismo patrón a los otros dos momentos en que un
-- monto queda firmado: **congelar el presupuesto** y **aprobar un adicional**.
--
-- Qué NO hace, a propósito: no permite pactar en una moneda distinta a la de la obra (eso es el
-- Nivel 2 del relevamiento -- arrastra CAC, cascada de Factor K, certificación y facturación, y
-- queda para cuando haya una obra real así). Acá la moneda de pacto sigue siendo una sola; lo que
-- se arregla es que la **lente** en dólares deje de moverse sobre montos ya cerrados.
--
-- Diseño completo, decisiones y el caso de las filas viejas:
-- docs/cotizacion_congelada_montos_cerrados_diseno.md
--
-- Las dos funciones se recrean completas (`create or replace`) copiando el cuerpo vigente -- de la
-- 0121 para `congelar_presupuesto_obra` y de la 0118 para `aprobar_adicional` -- con el agregado del
-- snapshot y nada más. Ninguna otra línea cambia.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project -> SQL Editor), después de `0121`. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

alter table obras
  add column cotizacion_dolar_al_congelar numeric;

comment on column obras.cotizacion_dolar_al_congelar is
  'Promedio compra/venta de cotizacion_dolar_bna al congelar el presupuesto (0122). El pactado en '
  'dolares se muestra con ESTA cotizacion, no con la de hoy. null = obra congelada antes de la '
  '0122: se muestra a la cotizacion de hoy, marcado como aproximacion (no hay serie historica de '
  'cotizaciones para reconstruirla). Se reescribe en cada recongelamiento, junto con el resto del '
  'snapshot.';

alter table modificaciones_obra
  add column cotizacion_dolar_al_aprobar numeric;

comment on column modificaciones_obra.cotizacion_dolar_al_aprobar is
  'Promedio compra/venta de cotizacion_dolar_bna al aprobar el adicional (0122) -- el momento en que '
  'pasa a ser un monto firmado. Mientras esta pendiente no hay nada congelado y el monto en dolares '
  'se muestra vivo, a proposito. null = aprobado antes de la 0122, o tipo distinto de adicional '
  '(quita/demasia/ajuste_contrato, que no usan esta columna).';

-- congelar_presupuesto_obra -- cuerpo vigente de 0121 + el snapshot de cotización.

create or replace function congelar_presupuesto_obra(p_obra_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cotizacion_promedio numeric;
  v_fecha_presentacion timestamptz;
  v_validez_dias int;
  v_congelado_previo timestamptz;
  v_hay_certificado_no_borrador boolean;
  v_tipo_presupuesto text;
  v_filas int;
begin
  if not puede_editar_presupuesto(p_obra_id) then
    raise exception 'sin autoridad para congelar el presupuesto de esta obra';
  end if;

  select presupuesto_fecha_presentacion, presupuesto_validez_dias, presupuesto_congelado_en
    into v_fecha_presentacion, v_validez_dias, v_congelado_previo
  from obras
  where id = p_obra_id;

  if v_fecha_presentacion is null then
    raise exception 'el presupuesto todavía no fue presentado -- presentalo antes de congelarlo';
  end if;

  if now() > v_fecha_presentacion + (v_validez_dias || ' days')::interval then
    raise exception 'el presupuesto está vencido -- actualizalo (presentar_presupuesto_obra) antes de congelarlo';
  end if;

  if v_congelado_previo is not null then
    select exists (
      select 1 from certificados where obra_id = p_obra_id and estado <> 'borrador'
    ) into v_hay_certificado_no_borrador;

    if v_hay_certificado_no_borrador then
      raise exception 'ya hay certificados emitidos contra el presupuesto congelado -- no se puede volver a congelar';
    end if;
  end if;

  select tipo_presupuesto into v_tipo_presupuesto
  from obra_presupuesto_config
  where obra_id = p_obra_id;

  -- Recongelamiento: se borra el snapshot anterior entero, se vuelve a armar de cero. Nunca deja
  -- un estado a medio camino porque las dos tablas se completan en la misma transacción de
  -- función (todo o nada -- si algo de abajo lanza excepción, Postgres revierte el delete
  -- también).
  delete from presupuesto_subitems_congelado where obra_id = p_obra_id;
  delete from presupuesto_config_congelado where obra_id = p_obra_id;

  insert into presupuesto_config_congelado (
    obra_id, tipo_presupuesto, gg_pct, imprevistos_pct, epp_pct, costo_financiero_pct,
    beneficio_pct, gestion_materiales_terceros_pct, impuestos_pct_total
  )
  select
    c.obra_id, c.tipo_presupuesto, c.gg_pct, c.imprevistos_pct, c.epp_pct, c.costo_financiero_pct,
    c.beneficio_pct, c.gestion_materiales_terceros_pct,
    coalesce((select sum(oi.porcentaje) from obra_impuestos oi where oi.obra_id = p_obra_id), 0)
  from obra_presupuesto_config c
  where c.obra_id = p_obra_id;

  with base as (
    select os.id as obra_subitem_id, os.cantidad, os.precio_unitario_manual,
           os.subitem_id, r.usa_apu, r.tipo_precio_manual
    from obra_subitems os
    join rubros r on r.id = os.rubro_id
    where os.obra_id = p_obra_id and os.es_aplicable = true
  ),
  manual as (
    select
      obra_subitem_id, cantidad,
      case tipo_precio_manual
        when 'global' then coalesce(precio_unitario_manual, 0)
        else cantidad * coalesce(precio_unitario_manual, 0)
      end as monto_total,
      null::numeric as precio_final,
      null::numeric as costo_costo,
      null::numeric as materiales_subtotal
    from base
    where usa_apu = false
  ),
  apu_ids as (
    select array_agg(subitem_id) as ids from base where usa_apu = true
  ),
  -- Una sola llamada a calcular_factor_k_subitem por partida (unnest + lateral, mismo patrón que
  -- 0090) -- devuelve las dos vistas en la misma consulta, se pivotea con FILTER en vez de llamar
  -- dos veces (una por vista) y recalcular la composición dos veces por nada.
  apu_raw as (
    select i.subitem_id, f.vista, f.orden, f.costo_costo, f.precio_final
    from unnest((select ids from apu_ids)) as i(subitem_id)
    cross join lateral calcular_factor_k_subitem(p_obra_id, i.subitem_id) as f
  ),
  apu_detalle as (
    select
      subitem_id,
      max(precio_final) filter (where vista = 'con_materiales') as precio_final_cm,
      max(precio_final) filter (where vista = 'sin_materiales') as precio_final_sm,
      -- costo_costo en la rama con_materiales incluye materiales; en sin_materiales es
      -- costo_costo_sm (sin materiales, ver 0077 §sm_base) -- la resta de las dos da
      -- materiales_subtotal sin necesidad de tocar calcular_factor_k_subitem para exponer esa
      -- columna aparte (cambiar su returns table exigiría DROP+CREATE, con el riesgo real de
      -- romper 0090/0092 que dependen de la firma actual -- fuera de alcance de esta pieza).
      max(costo_costo) filter (where vista = 'con_materiales' and orden = 1) as costo_costo_cm,
      max(costo_costo) filter (where vista = 'sin_materiales' and orden = 1) as costo_costo_sm
    from apu_raw
    group by subitem_id
  ),
  apu as (
    select
      b.obra_subitem_id,
      b.cantidad,
      b.cantidad * (case when v_tipo_presupuesto = 'mano_obra_sola' then d.precio_final_sm else d.precio_final_cm end)
        as monto_total,
      (case when v_tipo_presupuesto = 'mano_obra_sola' then d.precio_final_sm else d.precio_final_cm end)
        as precio_final,
      (case when v_tipo_presupuesto = 'mano_obra_sola' then d.costo_costo_sm else d.costo_costo_cm end)
        as costo_costo,
      (d.costo_costo_cm - d.costo_costo_sm) as materiales_subtotal
    from base b
    join apu_detalle d on d.subitem_id = b.subitem_id
    where b.usa_apu = true
  )
  insert into presupuesto_subitems_congelado
    (obra_id, obra_subitem_id, cantidad, monto_total, precio_final, costo_costo, materiales_subtotal)
  select p_obra_id, obra_subitem_id, cantidad, monto_total, precio_final, costo_costo, materiales_subtotal
  from manual
  union all
  select p_obra_id, obra_subitem_id, cantidad, monto_total, precio_final, costo_costo, materiales_subtotal
  from apu;

  get diagnostics v_filas = row_count;

  if v_filas = 0 then
    raise exception 'no hay ninguna partida tildada para congelar en esta obra';
  end if;

  -- 0122: la cotización del día del congelamiento, para que el pactado en dólares tampoco se
  -- mueva después. Misma lectura que `emitir_certificado` (0107): promedio compra/venta de la fila
  -- única de `cotizacion_dolar_bna`, sin la proyección personalizada PRO (es local al dashboard y
  -- no se persiste). Si la fila no existiera, queda null y el Dart cae a la cotización de hoy
  -- marcándolo como aproximación -- mismo fallback que un certificado viejo, no aborta el
  -- congelamiento por un dato de visualización.
  select (compra + venta) / 2 into v_cotizacion_promedio from cotizacion_dolar_bna limit 1;

  update obras
  set presupuesto_congelado_en = now(),
      presupuesto_congelado_por = auth.uid(),
      cotizacion_dolar_al_congelar = v_cotizacion_promedio
  where id = p_obra_id;

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (
    p_obra_id, auth.uid(), 'congelar_presupuesto_obra', 'obra', null,
    jsonb_build_object(
      'partidas_congeladas', v_filas,
      'recongelamiento', v_congelado_previo is not null,
      'cotizacion_dolar_al_congelar', v_cotizacion_promedio
    )
  );
end;
$$;
grant execute on function congelar_presupuesto_obra(uuid) to authenticated;
revoke execute on function congelar_presupuesto_obra(uuid) from public, anon;

-- aprobar_adicional -- cuerpo vigente de 0118 + el snapshot de cotización.
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
  v_cotizacion_promedio numeric;
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

  -- 0122: la aprobación es el momento en que el adicional pasa a ser un monto firmado, así que es
  -- acá donde se congela la cotización -- no en el envío. Para el camino de monto fijo es además el
  -- único momento posible: el trigger `calcular_monto_total_adicional` (0112) lo recalcula mientras
  -- sigue pendiente. Para el de obra hija el monto ya estaba fijo desde el envío, pero el número en
  -- dólares que se le muestra al cliente mientras está pendiente SÍ tiene que seguir vivo: todavía
  -- no hay nada firmado. Mismo criterio y misma lectura que 0107 en `emitir_certificado`.
  select (compra + venta) / 2 into v_cotizacion_promedio from cotizacion_dolar_bna limit 1;

  update modificaciones_obra
  set estado = 'aprobado',
      monto_total = v_monto,
      aprobado_por = auth.uid(),
      fecha_resolucion = now(),
      comentario_resolucion = p_comentario,
      cotizacion_dolar_al_aprobar = v_cotizacion_promedio
  where id = p_modificacion_id;

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (
    v_mod.obra_id, auth.uid(), 'aprobar_adicional', 'modificacion_obra', p_modificacion_id,
    jsonb_build_object(
      'monto', v_monto,
      'cotizacion_dolar_al_aprobar', v_cotizacion_promedio,
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

-- `create or replace` conserva los grants; se repiten igual, mismo patrón que el resto. Solo los de
-- esta función: `calcular_precio_adicional` y `enviar_adicional_a_aprobacion` no se tocan acá.
grant execute on function aprobar_adicional(uuid, numeric, text) to authenticated;
revoke execute on function aprobar_adicional(uuid, numeric, text) from public, anon;

-- Verificación a mano después de aplicar (SQL Editor):
--
-- 1) Columnas creadas:
--    select column_name, data_type from information_schema.columns
--    where (table_name, column_name) in
--      (('obras','cotizacion_dolar_al_congelar'), ('modificaciones_obra','cotizacion_dolar_al_aprobar'));
--    -- 2 filas, numeric.
--
-- 2) Filas viejas (lo esperado: todas en null, no hay cómo reconstruirlas):
--    select count(*) filter (where cotizacion_dolar_al_congelar is null) as sin_snapshot,
--           count(*) as congeladas
--    from obras where presupuesto_congelado_en is not null;
--    select count(*) filter (where cotizacion_dolar_al_aprobar is null) as sin_snapshot,
--           count(*) as aprobados
--    from modificaciones_obra where tipo = 'adicional' and estado = 'aprobado';
--
-- 3) Congelar una obra de prueba y ver que el snapshot quedó igual al promedio BNA del día:
--    select (compra + venta) / 2 as promedio_hoy from cotizacion_dolar_bna;
--    select congelar_presupuesto_obra('<obra_id>');
--    select presupuesto_congelado_en, cotizacion_dolar_al_congelar from obras where id = '<obra_id>';
--    -- cotizacion_dolar_al_congelar = promedio_hoy.
--
-- 4) Aprobar un adicional de prueba (monto fijo, importe chico) y lo mismo:
--    select aprobar_adicional('<modificacion_id>', <monto_visto>, 'prueba 0122');
--    select estado, monto_total, cotizacion_dolar_al_aprobar
--    from modificaciones_obra where id = '<modificacion_id>';
--
-- 5) Que el audit_log lo deje anotado:
--    select accion, detalle->>'cotizacion_dolar_al_congelar', detalle->>'cotizacion_dolar_al_aprobar'
--    from audit_log
--    where accion in ('congelar_presupuesto_obra','aprobar_adicional')
--    order by created_at desc limit 5;
--
-- 6) Que nada más se rompió: recongelar una obra sin certificados emitidos sigue funcionando, y
--    aprobar con un monto_visto desactualizado sigue cortando con el mensaje de siempre.
