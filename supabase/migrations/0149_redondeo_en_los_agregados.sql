-- =====================================================================
-- 0149 — El redondeo baja a la base
-- =====================================================================
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.
--
-- **Es cosmético: no mueve plata.** Redondea a 2 decimales resultados que la pantalla ya venía
-- mostrando redondeados; lo único que cambia es de qué lado del cable pasa el redondeo.
--
-- =====================================================================
-- DE DÓNDE SALE
-- =====================================================================
--
-- Seba lo vio en el teléfono: el precio unitario de una partida mostraba diez decimales. El
-- relevamiento que salió de ahí encontró una causa más grande que el síntoma: **la base casi nunca
-- redondea**. Lo que salvaba a la pantalla eran los formateadores de Dart, uno por pantalla, y
-- donde falta uno salen los decimales crudos.
--
-- Ya había pasado dos veces por el mismo camino, y la segunda dejó la lección que ordena esta
-- migración: la `0078` puso 31 `round()` en `calcular_factor_k_subitem`, la `0110` hizo
-- `drop function` + `create` y **se los llevó puestos a todos**, y la `0115` los devolvió.
--
-- Lo que no redondeaba, y ahora sí:
--
--   * `calcular_monto_obra_subitems.monto_total`            -- `cantidad * precio_final`, crudo
--   * `calcular_presupuesto_vivo_obra`                      -- `sum(monto)` pelado
--   * `calcular_presupuesto_hoy_config_congelada_obra`      -- idem
--   * `congelar_presupuesto_obra`                           -- **escribe** el monto pactado
--   * `calcular_avance_ponderado_rubros.monto_ponderado`    -- el único total por rubro del sistema
--
-- La última merece una nota: en esa misma consulta `avance_pct` **sí** estaba redondeado desde la
-- `0052` y `monto_ponderado` no. La asimetría estaba a la vista, en dos líneas consecutivas.
--
-- =====================================================================
-- LOS TRES CRITERIOS
-- =====================================================================
--
-- **1. Se redondea por línea, no al final.** Cada `monto_total` es una partida certificable: es el
-- número del que `certificado_subitems_avance.monto_periodo` (0052) ya saca su propio
-- `round(..., 2)`. Redondear la suma en vez de cada línea dejaría el total del presupuesto y la
-- suma de los certificados apartados por centavos, sin que nadie pueda decir cuál está bien.
--
-- **2. El dato de entrada no se toca.** `obra_subitems.precio_unitario_manual` se sigue guardando
-- con toda su precisión. En la obra real de Galpón Mix el precio se deriva del total del PDF
-- (`total / cantidad`) justamente porque redondearlo reintroduce la deriva que ese cálculo existe
-- para evitar. **Se redondea el resultado, nunca la entrada.**
--
-- **3. Una función se recrea una sola vez por tanda.** Es la lección de la 0110: si hay que
-- cambiarle dos cosas a una función, se cambian juntas.
--
-- Por ese criterio 3, esta migración nació junto con la regla "un precio manual cargado gana sobre
-- la cascada de APU", que toca cuatro de estas cinco funciones. Se separaron cuando la idea de las
-- dos carpetas movió las prioridades: **el redondeo es independiente y va ya; la otra mueve plata
-- y espera su turno.** Quedó en `0150_precio_manual_gana_sobre_apu.sql`, marcada para no aplicar
-- todavía y escrita sobre los cuerpos de ESTA migración, para que el redondeo no se pierda cuando
-- le toque. Ver el corte en `docs/carpetas_importado_y_catalogo_diseno_datos.md`.
--
-- **Lo que NO se toca**: `calcular_monto_congelado_ajustado` (0106), que multiplica por el factor
-- CAC sin redondear. No hace falta: su salida entra por la rama `congelado` de
-- `calcular_monto_obra_subitems`, que ahora redondea. Recrear ese cuerpo entero (cuatro ramas de
-- `return query`) para redondear algo que el consumidor ya redondea es riesgo sin beneficio.
--
-- =====================================================================


-- =====================================================================
-- 1 -- calcular_monto_obra_subitems  (última versión: 0105)
-- =====================================================================
--
-- La que alimenta la certificación entera: `certificado_subitems_avance.monto_periodo` sale de
-- acá vía el trigger `calcular_monto_periodo_avance` (0052). Redondear acá es lo que hace que el
-- monto de un certificado y el total del presupuesto hablen del mismo número.

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
    -- round acá y no adentro de calcular_monto_congelado_ajustado: el factor CAC es una
    -- multiplicación con cola larga de decimales y este es su único consumidor.
    select mca.obra_subitem_id, round(mca.monto_total, 2) as monto_total, true as tiene_precio_completo
    from calcular_monto_congelado_ajustado(p_obra_id) mca
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
      round(
        case tipo_precio_manual
          when 'global' then coalesce(precio_unitario_manual, 0)
          else cantidad * coalesce(precio_unitario_manual, 0)
        end,
        2
      ) as monto_total,
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
      round(b.cantidad * p.precio_final, 2) as monto_total,
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
revoke execute on function calcular_monto_obra_subitems(uuid) from public, anon;


-- =====================================================================
-- 2 -- calcular_presupuesto_vivo_obra  (última versión: 0091)
-- =====================================================================
--
-- El total de la tarjeta de ObrasListScreen. Usa `calcular_precio_final_apu_subitems` (0090, con
-- la cascada completa), no `calcular_precio_apu_subitems` -- eso no cambia acá.

create or replace function calcular_presupuesto_vivo_obra(p_obra_id uuid)
returns numeric
language sql security definer set search_path = public stable as $$
  with autorizado as (
    select is_obra_member(p_obra_id) as ok
  ),
  base as (
    select os.id as obra_subitem_id, os.cantidad, os.precio_unitario_manual,
           os.subitem_id, r.usa_apu, r.tipo_precio_manual
    from obra_subitems os
    join rubros r on r.id = os.rubro_id
    cross join autorizado a
    where os.obra_id = p_obra_id and os.es_aplicable = true and a.ok
  ),
  manual as (
    select
      round(
        case tipo_precio_manual
          when 'global' then coalesce(precio_unitario_manual, 0)
          else cantidad * coalesce(precio_unitario_manual, 0)
        end,
        2
      ) as monto
    from base
    where usa_apu = false
  ),
  apu_ids as (
    select array_agg(subitem_id) as ids from base where usa_apu = true
  ),
  apu_precios as (
    -- unnest(null) da 0 filas, no error -- caso obra sin ninguna partida de APU tildada todavía.
    select * from calcular_precio_final_apu_subitems(p_obra_id, (select ids from apu_ids))
  ),
  apu as (
    select round(b.cantidad * p.precio_final, 2) as monto
    from base b
    join apu_precios p on p.subitem_id = b.subitem_id
    where b.usa_apu = true
  )
  select coalesce(sum(monto), 0)
  from (select monto from manual union all select monto from apu) t;
$$;

grant execute on function calcular_presupuesto_vivo_obra(uuid) to authenticated;
revoke execute on function calcular_presupuesto_vivo_obra(uuid) from public, anon;


-- =====================================================================
-- 3 -- calcular_presupuesto_hoy_config_congelada_obra  (última versión: 0110)
-- =====================================================================
--
-- Mide el desfasaje de PRECIOS con la config congelada: `calcular_factor_k_subitem(..., true)`.
-- La rama manual no pasa por Factor K, así que para ella "hoy con config congelada" y "hoy" son
-- el mismo número -- correcto: un precio manual no se mueve porque cambien los insumos.

create or replace function calcular_presupuesto_hoy_config_congelada_obra(p_obra_id uuid)
returns numeric
language sql security definer set search_path = public stable as $$
  with autorizado as (
    select is_obra_member(p_obra_id) as ok
  ),
  vista_congelada as (
    select case when tipo_presupuesto = 'mano_obra_sola' then 'sin_materiales' else 'con_materiales' end as vista
    from presupuesto_config_congelado
    where obra_id = p_obra_id
  ),
  base as (
    select psc.cantidad, os.subitem_id, os.precio_unitario_manual, r.usa_apu, r.tipo_precio_manual
    from presupuesto_subitems_congelado psc
    join obra_subitems os on os.id = psc.obra_subitem_id
    join rubros r on r.id = os.rubro_id
    cross join autorizado a
    where psc.obra_id = p_obra_id and a.ok
  ),
  manual as (
    select
      round(
        case tipo_precio_manual
          when 'global' then coalesce(precio_unitario_manual, 0)
          else cantidad * coalesce(precio_unitario_manual, 0)
        end,
        2
      ) as monto
    from base
    where usa_apu = false
  ),
  apu as (
    select round(b.cantidad * f.precio_final, 2) as monto
    from base b
    cross join lateral calcular_factor_k_subitem(p_obra_id, b.subitem_id, true) as f
    cross join vista_congelada v
    where b.usa_apu = true and f.vista = v.vista and f.orden = 1
  )
  select coalesce(sum(monto), 0)
  from (select monto from manual union all select monto from apu) t;
$$;

grant execute on function calcular_presupuesto_hoy_config_congelada_obra(uuid) to authenticated;
revoke execute on function calcular_presupuesto_hoy_config_congelada_obra(uuid) from public, anon;


-- =====================================================================
-- 4 -- congelar_presupuesto_obra  (última versión: 0122)
-- =====================================================================
--
-- La única de las cinco que ESCRIBE. `presupuesto_subitems_congelado.monto_total` es el monto
-- pactado: el número que después no se mueve más. Que quede con cola de decimales es peor que en
-- cualquier otro lado, porque queda escrito.

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
      round(
        case tipo_precio_manual
          when 'global' then coalesce(precio_unitario_manual, 0)
          else cantidad * coalesce(precio_unitario_manual, 0)
        end,
        2
      ) as monto_total,
      null::numeric as precio_final,
      null::numeric as costo_costo,
      null::numeric as materiales_subtotal
    from base
    where usa_apu = false
  ),
  apu_ids as (
    select array_agg(subitem_id) as ids from base where usa_apu = true
  ),
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
      max(costo_costo) filter (where vista = 'con_materiales' and orden = 1) as costo_costo_cm,
      max(costo_costo) filter (where vista = 'sin_materiales' and orden = 1) as costo_costo_sm
    from apu_raw
    group by subitem_id
  ),
  apu as (
    select
      b.obra_subitem_id,
      b.cantidad,
      round(
        b.cantidad * (case when v_tipo_presupuesto = 'mano_obra_sola' then d.precio_final_sm else d.precio_final_cm end),
        2
      ) as monto_total,
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


-- =====================================================================
-- 5 -- calcular_avance_ponderado_rubros  (última versión: 0052)
-- =====================================================================
--
-- **El único total por rubro que existe en todo el sistema.** Solo cambio 1: acá no hay nada de
-- `usa_apu` que decidir, los montos le llegan ya resueltos por `calcular_monto_obra_subitems`.
--
-- La asimetría estaba en dos líneas consecutivas: `avance_pct` con `round(..., 2)` desde la 0052
-- y `monto_ponderado` sin nada. Hoy no se ve porque `panel_avance_obra.dart` lo tapa con un
-- formateador que redondea a entero ("Peso en la obra"); era un decimal de más esperando a que
-- alguien lo mostrara sin formatear.

create or replace function calcular_avance_ponderado_rubros(p_obra_id uuid)
returns table(rubro_id uuid, avance_pct numeric, monto_ponderado numeric)
language sql stable as $$
  with pesos as (
    select os.rubro_id, os.id as obra_subitem_id, m.monto_total
    from obra_subitems os
    join calcular_monto_obra_subitems(p_obra_id) m on m.obra_subitem_id = os.id
    where os.obra_id = p_obra_id and os.es_aplicable = true
  )
  select
    p.rubro_id,
    round(
      sum(calcular_avance_acumulado_subitem(p.obra_subitem_id) * p.monto_total)
      / nullif(sum(p.monto_total), 0),
      2
    ) as avance_pct,
    round(sum(p.monto_total), 2) as monto_ponderado
  from pesos p
  group by p.rubro_id;
$$;

grant execute on function calcular_avance_ponderado_rubros(uuid) to authenticated;


-- =====================================================================
-- Verificación
-- =====================================================================
--
-- Ningún monto con más de 2 decimales. Las tres tienen que dar 0 filas:
--
--   -- por partida
--   select * from calcular_monto_obra_subitems('<obra_id>')
--   where monto_total <> round(monto_total, 2);
--
--   -- por rubro
--   select * from calcular_avance_ponderado_rubros('<obra_id>')
--   where monto_ponderado <> round(monto_ponderado, 2);
--
--   -- el snapshot escrito (después de un congelamiento nuevo)
--   select * from presupuesto_subitems_congelado
--   where obra_id = '<obra_id>' and monto_total <> round(monto_total, 2);
--
-- Y el total de la tarjeta, que ahora tiene que venir con 2 decimales de la base:
--
--   select calcular_presupuesto_vivo_obra('<obra_id>');
--
-- REGRESIÓN -- ningún total tiene que moverse más de un centavo por partida. Anotar estos dos
-- números antes de aplicar y compararlos después, en una obra con partidas de APU reales:
--
--   select calcular_presupuesto_vivo_obra('<obra_id>');
--   select coalesce(sum(monto_total), 0) from presupuesto_subitems_congelado where obra_id = '<obra_id>';
--
-- Si alguno se movió más que centavos, cambió algo además del redondeo.
