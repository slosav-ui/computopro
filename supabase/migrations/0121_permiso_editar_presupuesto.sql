-- Permiso `puede_editar_presupuesto` (docs/etapa3_roles_permisos_diseno_datos.md §8-§10, decisiones
-- de Seba del 2026-09-12). Resumen:
--
-- - El ROL define qué ves; el PERMISO define qué editás del presupuesto y qué actos formales firmás.
--   "El que armó el presupuesto es el que lo edita; los demás lo ven pero no lo tocan." (§10.1)
-- - El permiso solo aplica a profesional y constructor (los roles que ven el presupuesto). A
--   cliente, veedor o apoderado no se les ofrece -- check en la base.
-- - admin_maestro edita siempre, sin el permiso (§10.2): es quien crea la obra, y una obra nueva
--   necesita alguien que la edite.
-- - Una sola llave (§10.3): editar cómputo, precios, Factor K e impuestos, vista del presupuesto,
--   valor hora y cargas sociales, orden de rubros, importar; presentar y congelar; emitir, subir el
--   PDF firmado, cerrar un certificado cobrado; proponer/resolver una anulación y aprobar una
--   quita/demasía (§10.6-1); enviar un adicional presupuestado a aprobación. Sigue por ROL, sin el
--   permiso: ver, cargar avance en el borrador, certificar avance de un adicional, solicitar
--   adicionales y quitas/demasías, los libros.
-- - Caso que lo motivó: el empleado de Seba, invitado como constructor SIN el permiso, ve precios,
--   compra materiales y carga avance, pero no toca el presupuesto ni emite.
--
-- Decisiones de §9.5/§10.6 que esta migración implementa:
-- - (§9.5-B) el constructor NO aprueba ajustes de contrato: `puede_aprobar_monto` no se toca.
-- - (§9.5-C) el profesional también cierra un certificado cobrado -- vía el permiso.
-- - (§9.5-D) los libros (libro_entradas) no se tocan.
-- - (§10.6-2) los profesionales activos que ya existen quedan con el permiso en true (nadie pierde lo
--   que hoy tiene); los constructores, en false (hoy no editan, se otorga a mano).
-- - (§10.6-3) solo admin_maestro lo otorga, al invitar (invitaciones_insert) o insertando/editando
--   miembros (obra_members_insert/update). Cierra la escalada de "alguien con permiso de invitar que
--   no edita invita a otro que sí". La misma escalada con los OTROS permisos (aprobar, APU ajena)
--   queda para su propia pieza, a pedido de Seba.
-- - (§10.6-4) el que crea un adicional presupuestado es admin de la obra hija (bootstrap) y la edita
--   aunque en la madre no pueda -- sin cambios, la barrera es la aprobación del cliente.
--
-- La protección va en la base (pedido explícito de Seba): cada política y función del inventario de
-- §9.1 pasa por el helper `puede_editar_presupuesto(obra)`. Los botones de la app solo lo espejan.
-- Ojo, y por eso hay trabajo en Dart después de esta migración: un UPDATE o DELETE que la RLS no
-- deja pasar no da error, afecta 0 filas -- los repositorios tienen que tratar "0 filas" como error.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor), después de 0120. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

-- =====================================================================
-- Paso 1 — la columna, en obra_members y en invitaciones, y el backfill
-- =====================================================================
--
-- Por fila, igual que el resto de los permisos especiales (una fila = un rol de una persona en una
-- obra). Si alguien tiene dos filas (profesional y constructor), alcanza con que una lo tenga.
alter table obra_members
  add column puede_editar_presupuesto boolean not null default false;

alter table obra_members
  add constraint obra_members_editar_presupuesto_rol_check
    check (not puede_editar_presupuesto or rol in ('profesional', 'constructor'));

alter table invitaciones
  add column puede_editar_presupuesto boolean not null default false;

alter table invitaciones
  add constraint invitaciones_editar_presupuesto_rol_check
    check (not puede_editar_presupuesto or rol in ('profesional', 'constructor'));

-- §10.6-2: hoy edita cualquier profesional por su rol -- que siga pudiendo. Solo los activos: uno
-- revocado que se reactive después vuelve sin el permiso, y el admin se lo otorga si corresponde.
update obra_members
set puede_editar_presupuesto = true
where rol = 'profesional' and activo;

-- =====================================================================
-- Paso 2 — el helper: la regla, en un solo lugar
-- =====================================================================
--
-- El "helper común" de §9-A: todas las políticas y funciones de abajo lo llaman, así profesional y
-- constructor quedan iguales por construcción y cualquier cambio futuro es acá, en una línea.
-- SECURITY DEFINER porque lee obra_members (mismo patrón que is_obra_member/tiene_rol_en_obra, 0004).
create or replace function puede_editar_presupuesto(p_obra_id uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select
    tiene_rol_en_obra(p_obra_id, 'admin_maestro')
    or exists (
      select 1 from obra_members m
      where m.obra_id = p_obra_id and m.usuario_id = auth.uid() and m.activo
        and m.rol in ('profesional', 'constructor')
        and m.puede_editar_presupuesto
    );
$$;

grant execute on function puede_editar_presupuesto(uuid) to authenticated;
revoke execute on function puede_editar_presupuesto(uuid) from public, anon;

-- =====================================================================
-- Paso 3 — las 18 políticas de escritura del presupuesto pasan por el permiso
-- =====================================================================
--
-- Mismo comportamiento para admin_maestro (edita siempre) y para el profesional con el backfill del
-- Paso 1; cambia para el constructor con el permiso (ahora edita) y para cualquier profesional/
-- constructor sin él (no edita). Una política por tabla y operación, idéntica salvo el chequeo.

drop policy obra_subitems_insert on obra_subitems;
create policy obra_subitems_insert on obra_subitems for insert with check (puede_editar_presupuesto(obra_id));

drop policy obra_subitems_update on obra_subitems;
create policy obra_subitems_update on obra_subitems for update using (puede_editar_presupuesto(obra_id)) with check (puede_editar_presupuesto(obra_id));

drop policy obra_subitems_delete on obra_subitems;
create policy obra_subitems_delete on obra_subitems for delete using (puede_editar_presupuesto(obra_id));

drop policy obra_rubros_orden_insert on obra_rubros_orden;
create policy obra_rubros_orden_insert on obra_rubros_orden for insert with check (puede_editar_presupuesto(obra_id));

drop policy obra_rubros_orden_update on obra_rubros_orden;
create policy obra_rubros_orden_update on obra_rubros_orden for update using (puede_editar_presupuesto(obra_id)) with check (puede_editar_presupuesto(obra_id));

drop policy obra_presupuesto_config_update on obra_presupuesto_config;
create policy obra_presupuesto_config_update on obra_presupuesto_config for update using (puede_editar_presupuesto(obra_id)) with check (puede_editar_presupuesto(obra_id));

drop policy obra_impuestos_update on obra_impuestos;
create policy obra_impuestos_update on obra_impuestos for update using (puede_editar_presupuesto(obra_id)) with check (puede_editar_presupuesto(obra_id));

drop policy obra_insumo_precios_insert on obra_insumo_precios;
create policy obra_insumo_precios_insert on obra_insumo_precios for insert with check (puede_editar_presupuesto(obra_id));

drop policy obra_insumo_precios_update on obra_insumo_precios;
create policy obra_insumo_precios_update on obra_insumo_precios for update using (puede_editar_presupuesto(obra_id)) with check (puede_editar_presupuesto(obra_id));

drop policy obra_insumo_precios_delete on obra_insumo_precios;
create policy obra_insumo_precios_delete on obra_insumo_precios for delete using (puede_editar_presupuesto(obra_id));

drop policy obra_valor_hora_override_insert on obra_valor_hora_override;
create policy obra_valor_hora_override_insert on obra_valor_hora_override for insert with check (puede_editar_presupuesto(obra_id));

drop policy obra_valor_hora_override_update on obra_valor_hora_override;
create policy obra_valor_hora_override_update on obra_valor_hora_override for update using (puede_editar_presupuesto(obra_id)) with check (puede_editar_presupuesto(obra_id));

drop policy obra_valor_hora_override_delete on obra_valor_hora_override;
create policy obra_valor_hora_override_delete on obra_valor_hora_override for delete using (puede_editar_presupuesto(obra_id));

drop policy importaciones_insert on importaciones;
create policy importaciones_insert on importaciones for insert with check (
  usuario_id = auth.uid()
  and puede_editar_presupuesto(obra_id)
);

drop policy importaciones_update on importaciones;
create policy importaciones_update on importaciones for update using (puede_editar_presupuesto(obra_id)) with check (puede_editar_presupuesto(obra_id));

drop policy importaciones_items_insert on importaciones_items;
create policy importaciones_items_insert on importaciones_items for insert with check (
  exists (
    select 1 from importaciones i
    where i.id = importacion_id and puede_editar_presupuesto(i.obra_id)
  )
);

drop policy importaciones_items_update on importaciones_items;
create policy importaciones_items_update on importaciones_items for update using (
  exists (
    select 1 from importaciones i
    where i.id = importacion_id and puede_editar_presupuesto(i.obra_id)
  )
) with check (
  exists (
    select 1 from importaciones i
    where i.id = importacion_id and puede_editar_presupuesto(i.obra_id)
  )
);

drop policy importaciones_storage_insert on storage.objects;
create policy importaciones_storage_insert on storage.objects for insert with check (
  bucket_id = 'importaciones'
  and puede_editar_presupuesto((storage.foldername(name))[1]::uuid)
);

-- =====================================================================
-- Paso 4 — funciones: el chequeo de autoridad pasa al permiso
-- =====================================================================
--
-- Cada función es IDÉNTICA a su versión vigente (archivo indicado) salvo el chequeo de autoridad, o
-- la copia de permisos en las que copian filas de obra_members. `create or replace`, misma firma:
-- los grants se conservan; se repiten igual al final de cada una, mismo patrón que el resto.

-- presentar_presupuesto_obra -- vigente en 0103_presupuesto_validez_obra.sql
create or replace function presentar_presupuesto_obra(
  p_obra_id uuid,
  p_validez_dias int default 30
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_congelado_en timestamptz;
  v_hay_certificado_no_borrador boolean;
begin
  if not puede_editar_presupuesto(p_obra_id) then
    raise exception 'sin autoridad para presentar el presupuesto de esta obra';
  end if;

  if p_validez_dias is null or p_validez_dias <= 0 then
    raise exception 'la validez tiene que ser mayor a 0 días';
  end if;

  select presupuesto_congelado_en into v_congelado_en from obras where id = p_obra_id;

  if v_congelado_en is not null then
    select exists (
      select 1 from certificados where obra_id = p_obra_id and estado <> 'borrador'
    ) into v_hay_certificado_no_borrador;

    if v_hay_certificado_no_borrador then
      raise exception 'ya hay certificados emitidos contra el presupuesto congelado -- no se puede volver a presentar';
    end if;
  end if;

  update obras
  set presupuesto_fecha_presentacion = now(),
      presupuesto_validez_dias = p_validez_dias
  where id = p_obra_id;

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (
    p_obra_id, auth.uid(), 'presentar_presupuesto_obra', 'obra', null,
    jsonb_build_object(
      'validez_dias', p_validez_dias,
      'reintento', v_congelado_en is not null
    )
  );
end;
$$;
grant execute on function presentar_presupuesto_obra(uuid, int) to authenticated;
revoke execute on function presentar_presupuesto_obra(uuid, int) from public, anon;

-- congelar_presupuesto_obra -- vigente en 0104_presupuesto_congelamiento_modelo_a.sql
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

-- emitir_certificado -- vigente en 0107_certificado_cotizacion_al_emitir.sql
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

  if not puede_editar_presupuesto(v_obra_id) then
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
revoke execute on function emitir_certificado(uuid, boolean) from public, anon;

-- subir_pdf_firmado_certificado -- vigente en 0011_certificados_funciones_transicion.sql
create or replace function subir_pdf_firmado_certificado(
  p_certificado_id uuid,
  p_adjuntos text[]
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_obra_id uuid;
  v_estado text;
begin
  select obra_id, estado into v_obra_id, v_estado from certificados where id = p_certificado_id;

  if v_obra_id is null then
    raise exception 'certificado % no encontrado', p_certificado_id;
  end if;

  if v_estado = 'borrador' then
    raise exception 'certificado % todavía no fue emitido', p_certificado_id;
  end if;

  if not puede_editar_presupuesto(v_obra_id) then
    raise exception 'sin autoridad para subir el PDF firmado de este certificado';
  end if;

  if p_adjuntos is null or array_length(p_adjuntos, 1) is null then
    raise exception 'hace falta al menos un adjunto';
  end if;

  update certificados
  set pdf_firmado_subido = true,
      pdf_firmado_fecha = now(),
      pdf_firmado_adjuntos = p_adjuntos
  where id = p_certificado_id;

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (v_obra_id, auth.uid(), 'subir_pdf_firmado_certificado', 'certificado', p_certificado_id, null);
end;
$$;
grant execute on function subir_pdf_firmado_certificado(uuid, text[]) to authenticated;
revoke execute on function subir_pdf_firmado_certificado(uuid, text[]) from public, anon;

-- confirmar_importacion -- vigente en 0081_confirmar_importacion.sql
create or replace function confirmar_importacion(p_importacion_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_obra_id uuid;
  v_estado text;
  v_item record;
  v_obra_subitem_id uuid;
begin
  select obra_id, estado into v_obra_id, v_estado
  from importaciones
  where id = p_importacion_id;

  if v_obra_id is null then
    raise exception 'importación % no encontrada', p_importacion_id;
  end if;

  if v_estado <> 'pendiente_revision' then
    raise exception 'importación % no está pendiente de revisión (estado actual: %)', p_importacion_id, v_estado;
  end if;

  if not puede_editar_presupuesto(v_obra_id) then
    raise exception 'sin autoridad para confirmar esta importación';
  end if;

  for v_item in
    select * from importaciones_items
    where importacion_id = p_importacion_id
      and rubro_id is not null
      and subitem_id is not null
  loop
    select id into v_obra_subitem_id
    from obra_subitems
    where obra_id = v_obra_id and subitem_id = v_item.subitem_id;

    if v_obra_subitem_id is not null then
      update obra_subitems
      set cantidad = coalesce(v_item.cantidad, 0),
          precio_unitario_manual = v_item.precio_unitario,
          es_aplicable = true,
          ultima_modificacion_usuario_id = auth.uid(),
          updated_at = now()
      where id = v_obra_subitem_id;
    else
      insert into obra_subitems (
        obra_id, rubro_id, subitem_id, cantidad, precio_unitario_manual,
        es_aplicable, agregado_por_usuario_id
      ) values (
        v_obra_id, v_item.rubro_id, v_item.subitem_id, coalesce(v_item.cantidad, 0),
        v_item.precio_unitario, true, auth.uid()
      );
    end if;
  end loop;

  update importaciones
  set estado = 'confirmado',
      confirmado_por_usuario_id = auth.uid(),
      confirmado_at = now()
  where id = p_importacion_id;
end;
$$;
grant execute on function confirmar_importacion(uuid) to authenticated;
revoke execute on function confirmar_importacion(uuid) from public, anon;

-- marcar_certificado_impactado -- vigente en 0011_certificados_funciones_transicion.sql
create or replace function marcar_certificado_impactado(
  p_certificado_id uuid,
  p_factura_adjuntos text[] default '{}'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_obra_id uuid;
  v_estado text;
begin
  select obra_id, estado
    into v_obra_id, v_estado
  from certificados
  where id = p_certificado_id;

  if v_obra_id is null then
    raise exception 'certificado % no encontrado', p_certificado_id;
  end if;

  if v_estado <> 'pagado' then
    raise exception 'certificado % no está pagado (estado actual: %)', p_certificado_id, v_estado;
  end if;

  if not puede_editar_presupuesto(v_obra_id) then
    raise exception 'sin autoridad para cerrar este certificado';
  end if;

  update certificados
  set estado = 'impactado_cerrado',
      fecha_impacto = now(),
      impactado_por = auth.uid(),
      factura_final_adjuntos = p_factura_adjuntos
  where id = p_certificado_id;

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (v_obra_id, auth.uid(), 'marcar_certificado_impactado', 'certificado', p_certificado_id, null);
end;
$$;
grant execute on function marcar_certificado_impactado(uuid, text[]) to authenticated;
revoke execute on function marcar_certificado_impactado(uuid, text[]) from public, anon;

-- proponer_anulacion_certificado -- vigente en 0056_certificados_anulacion.sql
create or replace function proponer_anulacion_certificado(
  p_certificado_id uuid,
  p_motivo text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_obra_id uuid;
  v_estado text;
  v_anulacion_estado text;
begin
  select obra_id, estado, anulacion_estado
    into v_obra_id, v_estado, v_anulacion_estado
  from certificados
  where id = p_certificado_id;

  if v_obra_id is null then
    raise exception 'certificado % no encontrado', p_certificado_id;
  end if;

  if not (
    (tiene_rol_en_obra(v_obra_id, 'profesional') or tiene_rol_en_obra(v_obra_id, 'constructor'))
    and puede_editar_presupuesto(v_obra_id)
  ) then
    raise exception 'sin autoridad para proponer la anulación de este certificado';
  end if;

  if v_estado not in ('emitido', 'leido') then
    raise exception 'certificado % no se puede anular desde su estado actual (%)', p_certificado_id, v_estado;
  end if;

  if v_anulacion_estado = 'propuesta' then
    raise exception 'ya hay una anulación propuesta pendiente para este certificado';
  end if;

  if p_motivo is null or btrim(p_motivo) = '' then
    raise exception 'la anulación necesita un motivo';
  end if;

  update certificados
  set anulacion_estado = 'propuesta',
      anulacion_motivo = p_motivo,
      anulacion_propuesta_por = auth.uid(),
      anulacion_propuesta_fecha = now(),
      anulacion_resuelta_por = null,
      anulacion_resuelta_fecha = null,
      anulacion_motivo_rechazo = null
  where id = p_certificado_id;

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (
    v_obra_id, auth.uid(), 'proponer_anulacion_certificado', 'certificado', p_certificado_id,
    jsonb_build_object('motivo', p_motivo)
  );
end;
$$;
grant execute on function proponer_anulacion_certificado(uuid, text) to authenticated;
revoke execute on function proponer_anulacion_certificado(uuid, text) from public, anon;

-- resolver_anulacion_certificado -- vigente en 0111_anulacion_no_copia_partidas_quitadas.sql
create or replace function resolver_anulacion_certificado(
  p_certificado_id uuid,
  p_aprobar boolean,
  p_motivo_rechazo text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_obra_id uuid;
  v_numero int;
  v_version int;
  v_periodo text;
  v_anulacion_estado text;
  v_propuesta_por uuid;
  v_nuevo_certificado_id uuid;
begin
  select obra_id, numero, version, periodo, anulacion_estado, anulacion_propuesta_por
    into v_obra_id, v_numero, v_version, v_periodo, v_anulacion_estado, v_propuesta_por
  from certificados
  where id = p_certificado_id;

  if v_obra_id is null then
    raise exception 'certificado % no encontrado', p_certificado_id;
  end if;

  if not (
    (tiene_rol_en_obra(v_obra_id, 'profesional') or tiene_rol_en_obra(v_obra_id, 'constructor'))
    and puede_editar_presupuesto(v_obra_id)
  ) then
    raise exception 'sin autoridad para resolver la anulación de este certificado';
  end if;

  if v_anulacion_estado <> 'propuesta' then
    raise exception 'certificado % no tiene una anulación pendiente de resolución', p_certificado_id;
  end if;

  if auth.uid() = v_propuesta_por then
    raise exception 'quien propone la anulación no puede aprobarla ni rechazarla';
  end if;

  if not p_aprobar then
    update certificados
    set anulacion_estado = 'rechazada',
        anulacion_resuelta_por = auth.uid(),
        anulacion_resuelta_fecha = now(),
        anulacion_motivo_rechazo = p_motivo_rechazo
    where id = p_certificado_id;

    insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
    values (
      v_obra_id, auth.uid(), 'resolver_anulacion_certificado', 'certificado', p_certificado_id,
      jsonb_build_object('aprobado', false, 'motivo_rechazo', p_motivo_rechazo)
    );
    return;
  end if;

  update certificados
  set estado = 'anulado',
      anulacion_estado = 'aprobada',
      anulacion_resuelta_por = auth.uid(),
      anulacion_resuelta_fecha = now()
  where id = p_certificado_id;

  begin
    insert into certificados (obra_id, numero, version, periodo, estado, creado_por)
    values (v_obra_id, v_numero, v_version + 1, v_periodo, 'borrador', auth.uid())
    returning id into v_nuevo_certificado_id;

    -- FIX (0111): solo se copian las filas cuya partida sigue siendo certificable hoy --
    -- `calcular_monto_obra_subitems` es la fuente de verdad de "qué obra_subitem_id existe para
    -- certificar" (vivo o congelado, según corresponda), la misma que ya usa el trigger de abajo
    -- para calcular monto_periodo. Antes se copiaban TODAS las filas del anulado sin este filtro,
    -- dejando partidas huérfanas (destildadas después de emitir) con avance fantasma en el
    -- reemplazo.
    insert into certificado_subitems_avance (certificado_id, obra_subitem_id, porcentaje_periodo, creado_por)
    select v_nuevo_certificado_id, csa.obra_subitem_id, csa.porcentaje_periodo, auth.uid()
    from certificado_subitems_avance csa
    where csa.certificado_id = p_certificado_id
      and csa.obra_subitem_id in (
        select mos.obra_subitem_id from calcular_monto_obra_subitems(v_obra_id) mos
      );
  exception
    when unique_violation then
      raise exception 'ya hay un borrador en curso para esta obra — resolvé o emití ese borrador antes de poder crear el reemplazo del certificado anulado';
  end;

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (
    v_obra_id, auth.uid(), 'resolver_anulacion_certificado', 'certificado', p_certificado_id,
    jsonb_build_object('aprobado', true, 'numero', v_numero, 'version_nueva', v_version + 1, 'certificado_nuevo_id', v_nuevo_certificado_id)
  );
end;
$$;
grant execute on function resolver_anulacion_certificado(uuid, boolean, text) to authenticated;
revoke execute on function resolver_anulacion_certificado(uuid, boolean, text) from public, anon;

-- puede_aprobar_quita_demasia -- vigente en 0109_quitas_demasias.sql
create or replace function puede_aprobar_quita_demasia(p_obra_id uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select (tiene_rol_en_obra(p_obra_id, 'profesional') or tiene_rol_en_obra(p_obra_id, 'constructor'))
    and puede_editar_presupuesto(p_obra_id);
$$;
grant execute on function puede_aprobar_quita_demasia(uuid) to authenticated;
revoke execute on function puede_aprobar_quita_demasia(uuid) from public, anon;

-- enviar_adicional_a_aprobacion -- vigente en 0118_adicionales_redondeo_y_monto_cero.sql
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
    delegacion_inicio, delegacion_fin, puede_invitar_terceros, puede_ver_apu_ajena,
    puede_editar_presupuesto
  )
  select
    v_mod.obra_hija_id, usuario_id, rol, invitado_por_usuario_id,
    puede_aprobar_certificados, puede_aprobar_adicionales, tope_monto_aprobacion,
    delegacion_inicio, delegacion_fin, puede_invitar_terceros, puede_ver_apu_ajena,
    puede_editar_presupuesto
  from obra_members
  where obra_id = v_mod.obra_id and activo
  on conflict (obra_id, usuario_id, rol) do nothing;

  if not puede_editar_presupuesto(v_mod.obra_hija_id) then
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
grant execute on function enviar_adicional_a_aprobacion(uuid) to authenticated;
revoke execute on function enviar_adicional_a_aprobacion(uuid) from public, anon;

-- crear_adicional_presupuestado -- vigente en 0114_fix_adicional_presupuestado_monto_total.sql
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
    delegacion_inicio, delegacion_fin, puede_invitar_terceros, puede_ver_apu_ajena,
    puede_editar_presupuesto
  )
  select
    v_obra_hija_id, usuario_id, rol, invitado_por_usuario_id,
    puede_aprobar_certificados, puede_aprobar_adicionales, tope_monto_aprobacion,
    delegacion_inicio, delegacion_fin, puede_invitar_terceros, puede_ver_apu_ajena,
    puede_editar_presupuesto
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

-- aceptar_invitacion -- vigente en 0097_invitaciones_variable_conflict_use_column.sql
create or replace function aceptar_invitacion(p_codigo text)
returns table(obra_id uuid, obra_nombre text, rol text)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_intentos_recientes integer;
  v_inv invitaciones%rowtype;
  v_obra_nombre text;
begin
  if auth.uid() is null then
    raise exception 'No autenticado.';
  end if;

  select count(*) into v_intentos_recientes
  from audit_log
  where usuario_id = auth.uid()
    and accion = 'canje_invitacion_fallido'
    and created_at > now() - interval '15 minutes';

  if v_intentos_recientes >= 5 then
    raise exception 'Demasiados intentos. Esperá unos minutos y volvé a probar.';
  end if;

  select * into v_inv
  from invitaciones i
  where i.codigo = upper(trim(p_codigo))
    and i.estado = 'pendiente'
    and i.expira_en > now();

  if not found then
    insert into audit_log (usuario_id, accion, entidad, detalle)
    values (auth.uid(), 'canje_invitacion_fallido', 'invitacion', jsonb_build_object());
    raise exception 'Código inválido o vencido.';
  end if;

  insert into obra_members (
    obra_id, usuario_id, rol, invitado_por_usuario_id,
    puede_aprobar_certificados, puede_aprobar_adicionales, tope_monto_aprobacion,
    delegacion_inicio, delegacion_fin, puede_invitar_terceros, puede_ver_apu_ajena,
    puede_editar_presupuesto
  ) values (
    v_inv.obra_id, auth.uid(), v_inv.rol, v_inv.invitado_por_usuario_id,
    v_inv.puede_aprobar_certificados, v_inv.puede_aprobar_adicionales, v_inv.tope_monto_aprobacion,
    v_inv.delegacion_inicio, v_inv.delegacion_fin, v_inv.puede_invitar_terceros, v_inv.puede_ver_apu_ajena,
    v_inv.puede_editar_presupuesto
  )
  -- Re-aceptar un rol que ya se tenía (reactivado tras una revocación, o el mismo permiso
  -- reenviado) reactiva y refresca los permisos en vez de romper contra el unique existente.
  on conflict (obra_id, usuario_id, rol) do update set
    activo = true,
    invitado_por_usuario_id = excluded.invitado_por_usuario_id,
    puede_aprobar_certificados = excluded.puede_aprobar_certificados,
    puede_aprobar_adicionales = excluded.puede_aprobar_adicionales,
    tope_monto_aprobacion = excluded.tope_monto_aprobacion,
    delegacion_inicio = excluded.delegacion_inicio,
    delegacion_fin = excluded.delegacion_fin,
    puede_invitar_terceros = excluded.puede_invitar_terceros,
    puede_ver_apu_ajena = excluded.puede_ver_apu_ajena,
    puede_editar_presupuesto = excluded.puede_editar_presupuesto;

  update invitaciones
  set estado = 'aceptada', aceptada_por_usuario_id = auth.uid(), aceptada_en = now()
  where id = v_inv.id;

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (v_inv.obra_id, auth.uid(), 'aceptar_invitacion', 'invitacion', v_inv.id,
          jsonb_build_object('rol', v_inv.rol));

  select o.nombre into v_obra_nombre from obras o where o.id = v_inv.obra_id;

  return query select v_inv.obra_id, v_obra_nombre, v_inv.rol;
end;
$$;
grant execute on function aceptar_invitacion(text) to authenticated;
revoke execute on function aceptar_invitacion(text) from public, anon;

-- =====================================================================
-- Paso 5 — quién otorga el permiso, y lo que el constructor ve por rol
-- =====================================================================
--
-- §10.6-3: solo admin_maestro otorga el permiso. Las dos puertas por las que alguien con
-- `puede_invitar_terceros` podía crear un miembro con cualquier permiso: la invitación y el insert
-- directo en obra_members. Las dos se cierran solo para ESTE permiso -- los otros (aprobar, APU
-- ajena) quedan como están, para su propia pieza. obra_members_update ya es de admin_maestro (la
-- rama del cliente solo toca filas de apoderado, y el check del Paso 1 no deja el permiso en esas).
-- Los inserts de las funciones SECURITY DEFINER (bootstrap, aceptar_invitacion, copias de equipo de
-- adicionales) no pasan por estas políticas: copian lo que ya fue otorgado.
drop policy invitaciones_insert on invitaciones;
create policy invitaciones_insert on invitaciones for insert with check (
  invitado_por_usuario_id = auth.uid()
  and (
    tiene_rol_en_obra(obra_id, 'admin_maestro')
    or exists (
      select 1 from obra_members m
      where m.obra_id = invitaciones.obra_id and m.usuario_id = auth.uid()
        and m.activo and m.puede_invitar_terceros
    )
  )
  and (not puede_editar_presupuesto or tiene_rol_en_obra(obra_id, 'admin_maestro'))
);

drop policy obra_members_insert on obra_members;
create policy obra_members_insert on obra_members for insert with check (
  (
    (usuario_id = auth.uid()
      and exists (select 1 from obras o where o.id = obra_id and o.id_admin_creador = auth.uid()))
    or tiene_rol_en_obra(obra_id, 'admin_maestro')
    or exists (
      select 1 from obra_members m
      where m.obra_id = obra_members.obra_id and m.usuario_id = auth.uid()
        and m.activo and m.puede_invitar_terceros
    )
  )
  and (not puede_editar_presupuesto or tiene_rol_en_obra(obra_id, 'admin_maestro'))
);

-- audit_log: el constructor ve el historial completo de la obra, igual que el profesional -- es
-- visibilidad, va por ROL (§8: el constructor ve lo mismo que el profesional). Antes veía solo sus
-- propias acciones.
drop policy audit_log_select on audit_log;
create policy audit_log_select on audit_log for select using (
  usuario_id = auth.uid()
  or (obra_id is not null and (
    tiene_rol_en_obra(obra_id, 'admin_maestro')
    or tiene_rol_en_obra(obra_id, 'profesional')
    or tiene_rol_en_obra(obra_id, 'constructor')
    or tiene_rol_en_obra(obra_id, 'cliente_principal')
  ))
);

-- =====================================================================
-- Verificación
-- =====================================================================
--
-- Schema (SQL Editor):
-- 1) Backfill: `select rol, activo, puede_editar_presupuesto, count(*) from obra_members group by 1,2,3
--    order by 1,2,3;` -- profesional + activo, todos en true; constructor, todos en false.
-- 2) El check: `update obra_members set puede_editar_presupuesto = true where rol = 'cliente_principal';`
--    tiene que rechazar (no se aplica, correrlo solo para ver el error).
-- 3) `select has_function_privilege('anon', 'puede_editar_presupuesto(uuid)', 'EXECUTE');` -> false.
--
-- En la app, con tres usuarios en una obra: A admin_maestro, P profesional (con el permiso por el
-- backfill), C constructor (sin el permiso), y después con el permiso otorgado por A.
-- 4) A y P: todo sigue igual que antes (editar cómputo/precios/Factor K, presentar, congelar,
--    emitir, importar).
-- 5) C sin el permiso: ve todo, pero editar un precio, el Factor K o una cantidad lo rechaza la base;
--    no puede presentar, congelar, emitir, subir el PDF firmado, cerrar un certificado cobrado,
--    anular ni aprobar una quita/demasía. SÍ puede cargar avance en el borrador, certificar avance de
--    un adicional aprobado, solicitar un adicional o una quita/demasía, y escribir en los libros.
--    (Mientras la app no espere a la parte Dart, algunos botones pueden seguir visibles: la base los
--    rechaza igual -- que es justamente lo que esta migración protege.)
-- 6) A le otorga el permiso a C: C pasa a poder todo lo del punto 5, incluido emitir.
-- 7) P (profesional con permiso) cierra un certificado cobrado: ahora funciona (antes no).
-- 8) Un miembro con puede_invitar_terceros que NO es admin intenta invitar a alguien con
--    puede_editar_presupuesto = true: rechaza. Sin el permiso, invita igual que antes.
-- 9) C ve el audit_log completo de la obra, no solo lo suyo.
-- 10) Un cliente que creó la obra (admin_maestro, sin rol técnico) edita el presupuesto, pero sigue sin
--     poder aprobar quitas/demasías ni resolver anulaciones (esas piden además profesional/constructor).
