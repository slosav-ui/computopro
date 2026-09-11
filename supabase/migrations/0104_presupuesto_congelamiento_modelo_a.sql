-- Congelamiento del presupuesto (Modelo A), paso 2: el snapshot en sí, congelar_presupuesto_obra,
-- el saldo pendiente equivalente al del Modelo B, y el cierre del cruce encontrado con la 0094
-- (certificación). Diseño completo, con las 5 ambigüedades cerradas, en
-- docs/presupuesto_congelado_validez_modelo_a_diseno.md -- este archivo es la implementación de
-- ese documento, no repite el razonamiento salvo donde hace falta para entender el SQL.
--
-- Depende de 0103 (columnas de validez + presupuesto_congelado_en/por).
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor), después de 0103. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

-- =====================================================================
-- presupuesto_config_congelado -- Factor K + impuestos, UNA fila por obra, no por partida
-- =====================================================================
--
-- Ambigüedad A, cerrada por Seba: guardar los 6 conceptos de Factor K (Opción 2) -- "dentro de un
-- año, cuando alguien pregunte con qué beneficio se firmó esa obra, el número está". Sin el
-- detalle de impuestos por tipo (queda para cuando haya un caso concreto).
--
-- Va en tabla aparte de presupuesto_subitems_congelado, no repetido en cada fila de esa tabla:
-- gg_pct/imprevistos_pct/etc. son configuración de la OBRA (obra_presupuesto_config, 1:1 con
-- obras, 0020), la misma para todas sus partidas -- duplicarlos por partida sería la misma
-- redundancia que el proyecto ya evita en el resto del schema. impuestos_pct_total: la suma plana
-- de obra_impuestos.porcentaje en el momento de congelar (misma cuenta que impuestos_pct_total en
-- calcular_factor_k_subitem, 0077) -- alcanza con el total para que precio_final no dependa de
-- que nadie vuelva a tocar obra_impuestos después; el desglose por tipo de impuesto es justamente
-- lo que la ambigüedad A dejó afuera.
create table presupuesto_config_congelado (
  obra_id uuid primary key references obras(id) on delete cascade,
  tipo_presupuesto text not null,      -- snapshot de obra_presupuesto_config.tipo_presupuesto
  gg_pct numeric not null,
  imprevistos_pct numeric not null,
  epp_pct numeric not null,
  costo_financiero_pct numeric not null,
  beneficio_pct numeric not null,
  gestion_materiales_terceros_pct numeric not null,
  impuestos_pct_total numeric not null,
  congelado_en timestamptz not null default now()
);

alter table presupuesto_config_congelado enable row level security;

create policy presupuesto_config_congelado_select on presupuesto_config_congelado for select
using (is_obra_member(obra_id));

-- Sin política de escritura a propósito -- se escribe únicamente desde congelar_presupuesto_obra
-- (SECURITY DEFINER, más abajo), mismo criterio que indices_cac (0102): la tabla no se edita a
-- mano por ningún usuario, solo la función controla cuándo cambia.

-- =====================================================================
-- presupuesto_subitems_congelado -- una fila por partida tildada, al momento de congelar
-- =====================================================================
--
-- Por qué tabla aparte y no columnas en obra_subitems: esa tabla sigue siendo el cómputo VIVO --
-- se sigue editando después de firmar (modificaciones_obra ya existe para adicionales/demasías/
-- quitas). Si el snapshot fueran columnas ahí mismo, corregir `cantidad` más adelante pisaría el
-- valor firmado sin querer. Con una tabla aparte, obra_subitems sigue siendo "qué hay tildado
-- hoy" y esta tabla pasa a ser "qué se firmó" -- mismo patrón que ya usa el proyecto para
-- certificado_subitems_avance apuntando a obra_subitems en vez de al catálogo.
--
-- monto_total: el número que de verdad importa (lo que vale esa partida, pactado) -- mismo
-- nombre y mismo significado que la columna homónima de calcular_monto_obra_subitems (0052/0094),
-- a propósito, para que el paso de certificación de más abajo pueda leerla sin traducir nada.
--
-- precio_final/costo_costo/materiales_subtotal: nullable -- solo tienen sentido para partidas con
-- APU (usa_apu = true). Para rubros de precio manual (1/18/19/20/custom) el monto ya es el precio
-- final tal cual lo tipeó el usuario, sin cascada de Factor K aplicada -- no hay costo-costo que
-- desglosar, mismo criterio que ya distingue esas dos ramas en calcular_monto_obra_subitems.
--
-- materiales_subtotal: guardado ahora aunque esta pieza no conecta el CAC (alcance explícito del
-- corte) -- lo pidió el propio docs/indices_cac_cotizacion_dolar_diseno.md §8 como dependencia
-- del split materiales/mano de obra que va a necesitar factor_cac_obra(obra, 'materiales')/
-- ('mano_obra'). Sale gratis de la misma llamada a calcular_factor_k_subitem (ver la función de
-- abajo) -- no guardarlo ahora significaría reconstruirlo después contra una composición de APU
-- que para entonces ya pudo haber cambiado.
create table presupuesto_subitems_congelado (
  id uuid primary key default gen_random_uuid(),
  obra_id uuid not null references obras(id) on delete cascade,
  obra_subitem_id uuid not null references obra_subitems(id),
  cantidad numeric not null,
  monto_total numeric not null,
  precio_final numeric,
  costo_costo numeric,
  materiales_subtotal numeric,
  congelado_en timestamptz not null default now(),
  unique (obra_id, obra_subitem_id)
);

alter table presupuesto_subitems_congelado enable row level security;

create policy presupuesto_subitems_congelado_select on presupuesto_subitems_congelado for select
using (is_obra_member(obra_id));

-- Sin política de escritura, mismo motivo que presupuesto_config_congelado -- solo
-- congelar_presupuesto_obra escribe acá.

-- =====================================================================
-- congelar_presupuesto_obra -- el evento de firma (o anticipo)
-- =====================================================================
--
-- Autoridad: admin_maestro/profesional, ambigüedad B (mismo criterio que presentar, 0103).
--
-- Candados, en orden:
-- 1) tiene que estar presentado (presupuesto_fecha_presentacion not null) -- no se firma un
--    presupuesto que nunca se mostró.
-- 2) no puede estar vencido -- docs §4, candado duro acá (a diferencia del aviso al solo mirar):
--    "al momento de firmar, si la validez pasó, no deja avanzar hasta actualizarlo".
-- 3) si ya estaba congelada (recongelamiento -- ambigüedad C), solo se permite mientras NINGÚN
--    certificado de la obra dejó de ser borrador todavía. Cerrado por Seba, en contra de mi
--    recomendación original de no permitir nunca recongelar: "entre firmar y empezar a
--    certificar puede pasar una semana... mientras no se certificó nada, no hay nada que
--    proteger". Recongelar borra el snapshot anterior y lo vuelve a armar entero -- no es un
--    ajuste parcial fila por fila.
--
-- No valida que haya al menos una partida tildada con precio completo (insumos_con_precio =
-- insumos_total) -- mismo criterio que el resto del proyecto (calcular_monto_obra_subitems,
-- consolidado_insumos_obra): no colapsa "sin precio" a 0 en silencio, pero tampoco bloquea; si
-- falta precio en algún insumo, esa partida congela con lo que haya, y queda para quien mire el
-- detalle notarlo. Sí valida que exista AL MENOS una partida tildada -- congelar una obra vacía
-- no es un caso de negocio real, es casi seguro un error.
create or replace function congelar_presupuesto_obra(p_obra_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_fecha_presentacion timestamptz;
  v_validez_dias int;
  v_congelado_previo timestamptz;
  v_hay_certificado_no_borrador boolean;
  v_tipo_presupuesto text;
  v_filas int;
begin
  if not (tiene_rol_en_obra(p_obra_id, 'admin_maestro') or tiene_rol_en_obra(p_obra_id, 'profesional')) then
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

  update obras
  set presupuesto_congelado_en = now(),
      presupuesto_congelado_por = auth.uid()
  where id = p_obra_id;

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (
    p_obra_id, auth.uid(), 'congelar_presupuesto_obra', 'obra', null,
    jsonb_build_object(
      'partidas_congeladas', v_filas,
      'recongelamiento', v_congelado_previo is not null
    )
  );
end;
$$;

grant execute on function congelar_presupuesto_obra(uuid) to authenticated;
revoke execute on function congelar_presupuesto_obra(uuid) from public, anon;

-- =====================================================================
-- calcular_saldo_pendiente_avance_medido -- el equivalente de calcular_saldo_pendiente_hitos
-- (0102) para el Modelo A
-- =====================================================================
--
-- Por partida: monto_total congelado × (100 − lo ya certificado acumulado) / 100 -- nunca sobre
-- el total, siempre sobre el saldo, mismo principio que ya usa el Modelo B (docs
-- indices_cac_cotizacion_dolar_diseno.md §4, confirmado por Seba). lo ya certificado sale de
-- calcular_avance_acumulado_subitem (0052), sin cambios -- esa función ya cuenta únicamente
-- certificados que dejaron de ser borrador, exactamente lo que hace falta acá.
--
-- Sin factor_cac_obra todavía -- a propósito, fuera de alcance de este corte ("sin conectar el
-- CAC al Modelo A todavía", pedido explícito). Cuando se conecte, la pieza siguiente multiplica
-- acá (o separa materiales/mano de obra con las dos series, usando costo_costo/
-- materiales_subtotal ya guardados arriba) -- esta función queda lista para esa extensión sin
-- necesitar cambiar su firma.
create or replace function calcular_saldo_pendiente_avance_medido(p_obra_id uuid)
returns numeric
language sql security definer set search_path = public stable as $$
  with autorizado as (
    select is_obra_member(p_obra_id) as ok
  )
  select coalesce(sum(
    psc.monto_total * (100 - calcular_avance_acumulado_subitem(psc.obra_subitem_id)) / 100
  ), 0)
  from presupuesto_subitems_congelado psc
  cross join autorizado a
  where psc.obra_id = p_obra_id and a.ok;
$$;

grant execute on function calcular_saldo_pendiente_avance_medido(uuid) to authenticated;
revoke execute on function calcular_saldo_pendiente_avance_medido(uuid) from public, anon;

-- =====================================================================
-- Cierre del cruce con la 0094 -- certificar contra lo congelado, no contra el precio en vivo
-- =====================================================================
--
-- Confirmado por Seba: "el presupuesto congelado es el número contra el que hay que certificar.
-- Se certifica avance sobre el precio pactado, no sobre el de hoy -- ese es todo el sentido de
-- congelarlo." La 0094 (2026-09-08/09) ya había corregido el bug más grave -- certificar contra
-- costo puro, sin la cascada de Factor K -- pero apuntando a calcular_precio_final_apu_subitems,
-- que recalcula EN VIVO. Para una obra congelada, eso certificaría contra los precios de insumos
-- del día de la certificación, no contra el precio pactado al firmar -- exactamente lo que este
-- congelamiento existe para evitar.
--
-- Fix: calcular_monto_obra_subitems bifurca por obras.presupuesto_congelado_en. Si la obra está
-- congelada, lee directo de presupuesto_subitems_congelado (monto_total ya resuelto, sin volver a
-- tocar ningún precio de insumo). Si no está congelada, sigue exactamente igual que la 0094 --
-- mismas tres CTEs (base/manual/apu), sin cambios de comportamiento para ninguna obra que no pase
-- por este mecanismo. `create or replace`, misma firma que 0052/0094 -- el trigger
-- (calcular_monto_periodo_avance), la vista previa (calcular_totales_certificado) y la emisión no
-- necesitan saber que cambió nada adentro, mismo criterio ya usado en la 0094 misma.
--
-- tiene_precio_completo = true para las filas congeladas -- si algún insumo no tenía precio al
-- momento de congelar, ese problema ya quedó resuelto (o aceptado) en el número que se congeló;
-- no tiene sentido seguir señalándolo después, a diferencia de la rama en vivo (donde sí importa
-- saber si el número de hoy es parcial).
create or replace function calcular_monto_obra_subitems(p_obra_id uuid)
returns table(obra_subitem_id uuid, monto_total numeric, tiene_precio_completo boolean)
language sql security definer set search_path = public stable as $$
  with autorizado as (
    select is_obra_member(p_obra_id) as ok
  ),
  estado_obra as (
    select coalesce(presupuesto_congelado_en is not null, false) as congelada
    from obras where id = p_obra_id
  ),
  congelado as (
    select psc.obra_subitem_id, psc.monto_total, true as tiene_precio_completo
    from presupuesto_subitems_congelado psc
    cross join autorizado a
    cross join estado_obra e
    where psc.obra_id = p_obra_id and a.ok and e.congelada
  ),
  base as (
    select os.id as obra_subitem_id, os.cantidad, os.precio_unitario_manual,
           os.subitem_id, r.usa_apu, r.tipo_precio_manual
    from obra_subitems os
    join rubros r on r.id = os.rubro_id
    cross join autorizado a
    cross join estado_obra e
    where os.obra_id = p_obra_id and os.es_aplicable = true and a.ok and not e.congelada
  ),
  manual as (
    select
      obra_subitem_id,
      case tipo_precio_manual
        when 'global' then coalesce(precio_unitario_manual, 0)
        else cantidad * coalesce(precio_unitario_manual, 0)
      end as monto_total,
      precio_unitario_manual is not null as tiene_precio_completo
    from base
    where usa_apu = false
  ),
  apu_ids as (
    select array_agg(subitem_id) as ids from base where usa_apu = true
  ),
  apu_precios as (
    select * from calcular_precio_final_apu_subitems(p_obra_id, (select ids from apu_ids))
  ),
  apu as (
    select
      b.obra_subitem_id,
      b.cantidad * p.precio_final as monto_total,
      (p.insumos_total > 0 and p.insumos_con_precio = p.insumos_total) as tiene_precio_completo
    from base b
    join apu_precios p on p.subitem_id = b.subitem_id
    where b.usa_apu = true
  )
  select * from congelado
  union all
  select * from manual
  union all
  select * from apu;
$$;

grant execute on function calcular_monto_obra_subitems(uuid) to authenticated;

-- =====================================================================
-- Recalcular borradores con avance ya cargado -- mismo paso que la 0094 (§Paso 2), y su propia
-- nota "PATRÓN A REPETIR" pedía explícitamente repetirlo acá
-- =====================================================================
--
-- El trigger calcular_monto_periodo_avance (0052) solo recalcula monto_periodo cuando esa fila
-- puntual de certificado_subitems_avance se inserta o actualiza -- cambiar la función de arriba
-- no reprocesa filas ya guardadas. Sin este paso, un certificado en borrador de una obra que se
-- congela recién ahora quedaría con monto_periodo viejo (calculado en vivo) hasta que alguien
-- vuelva a tocar cada fila a mano -- el mismo tipo de bug silencioso que motivó la 0094 original.
--
-- Mismo mecanismo: un UPDATE que no cambia ningún valor dispara igual el trigger BEFORE UPDATE.
update certificado_subitems_avance
set porcentaje_periodo = porcentaje_periodo
where certificado_id in (select id from certificados where estado = 'borrador');

-- =====================================================================
-- Verificación
-- =====================================================================
--
-- 1) Obra de prueba con cómputo cargado: presentar_presupuesto_obra, esperar (o simular) que no
--    esté vencida, congelar_presupuesto_obra -- presupuesto_subitems_congelado tiene una fila por
--    partida tildada, presupuesto_config_congelado tiene una fila con los % vigentes,
--    obras.presupuesto_congelado_en queda seteado.
-- 2) calcular_presupuesto_vivo_obra (0091) sigue dando el número de HOY, sin cambios, aunque la
--    obra ya esté congelada -- es la mitad "recalculado" de la comparación del punto 4 del
--    diagnóstico.
-- 3) calcular_monto_obra_subitems, sobre la misma obra ya congelada: los montos coinciden EXACTO
--    con presupuesto_subitems_congelado.monto_total, no con lo que daría calcular_precio_final_
--    apu_subitems si se llamara ahora (para confirmarlo, cambiar un precio de insumo después de
--    congelar y ver que el monto de certificación NO se mueve).
-- 4) Obra sin congelar (la mayoría, hoy): calcular_monto_obra_subitems sigue dando exactamente lo
--    mismo que daba antes de esta migración -- sin regresión para ninguna obra que no pase por
--    este mecanismo.
-- 5) Intentar congelar vencida: rechaza. Intentar recongelar con un certificado ya emitido:
--    rechaza. Recongelar sin certificados emitidos: reemplaza el snapshot entero, sin dejar
--    filas viejas mezcladas con nuevas.
-- 6) calcular_saldo_pendiente_avance_medido: sobre una obra congelada con algo de avance ya
--    certificado, el número baja respecto de sumar presupuesto_subitems_congelado.monto_total
--    a secas, en la proporción correcta.
