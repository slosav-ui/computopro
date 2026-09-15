-- =====================================================================
-- 0150 — Un precio manual cargado gana sobre la cascada de APU
-- =====================================================================
--
-- =====================================================================
-- NO APLICAR TODAVÍA. Es la tanda 6 del corte de
-- `docs/carpetas_importado_y_catalogo_diseno_datos.md`.
-- =====================================================================
--
-- Nació junto con el redondeo, en una sola migración, porque los dos cambios caen sobre las mismas
-- funciones. Se separó cuando la idea de las dos carpetas movió las prioridades: **el redondeo es
-- independiente y se aplica ya (0149); esto mueve plata y espera su turno.**
--
-- ---------------------------------------------------------------- qué hace
--
-- Hoy las cuatro funciones de abajo deciden de dónde sale el precio de una partida mirando **solo el
-- rubro**: `usa_apu = false` -> `precio_unitario_manual`; `usa_apu = true` -> la cascada de Factor K.
-- Un precio manual cargado en una partida de un rubro con APU (rubros 2 a 17, casi todo lo
-- estructural y las terminaciones) queda guardado pero **no suma**: la base lo ignora en silencio.
--
-- No es una decisión nueva. Está cerrada en `docs/importador_capa2_diseno_datos.md`:
--
--     "Un precio importado es un número ya cerrado por el profesional -- no tiene que competir con
--      (ni depender de) si el subítem matcheado tiene una composición de APU real."
--
-- Y **la mitad de Dart ya está construida**: `SubitemsScreen._buildContenido` chequea
-- `precioUnitarioManual != null` antes de mirar la composición y muestra el campo editable. O sea
-- que hoy la pantalla deja cargar un precio ahí, lo muestra, y la base no lo suma. Falta esta mitad.
--
-- **Regla, en una línea**: si `obra_subitems.precio_unitario_manual` tiene valor, ese precio manda,
-- sin importar el `usa_apu` del rubro. Si es null, nada cambia: sigue la cascada.
--
-- ---------------------------------------------------------------- por qué ya no es urgente
--
-- Era el bloqueo para mapear las partidas del PDF de Galpón Mix a rubros reales del catálogo (14 de
-- 24 caían en rubros con APU y habrían quedado en cero). Con las dos carpetas eso desaparece: la
-- carpeta importada entra tal cual, con rubros de precio manual, y no necesita esta regla.
--
-- Lo que queda es la coherencia: la pantalla ya deja hacer algo que la base no acompaña.
--
-- ---------------------------------------------------------------- qué puede moverse al aplicar
--
-- El doc de la Capa 2 dice que es un no-op para los datos existentes porque "ningún camino existente
-- escribe `precio_unitario_manual` en un subítem oficial con `usa_apu = true`". **Es cierto para los
-- oficiales y NO para los propios**: un subítem propio en un rubro con APU sí puede tenerlo cargado,
-- y hoy no suma. Al aplicar esto empieza a sumar.
--
-- Correr ANTES de aplicar. Son las partidas cuyo monto va a cambiar:
--
--   select o.nombre as obra, r.codigo as rubro, s.codigo, s.descripcion,
--          os.cantidad, os.precio_unitario_manual,
--          round(os.cantidad * os.precio_unitario_manual, 2) as monto_que_pasa_a_sumar
--   from obra_subitems os
--   join obras o    on o.id = os.obra_id
--   join rubros r   on r.id = os.rubro_id
--   join subitems s on s.id = os.subitem_id
--   where r.usa_apu = true
--     and os.precio_unitario_manual is not null
--     and os.es_aplicable = true
--   order by o.nombre, r.codigo, s.codigo;
--
-- Si da 0 filas, es un no-op.
--
-- **Obras ya congeladas no se mueven**: su monto sale de `presupuesto_subitems_congelado`, que es un
-- snapshot. La regla las alcanza recién si se recongela.
--
-- ---------------------------------------------------------------- OJO AL APLICARLA
--
-- Estas cuatro funciones ya fueron recreadas por la `0149` para meterles el redondeo. **Los cuerpos
-- de abajo incluyen esos `round(..., 2)`** -- están escritos sobre la versión de la 0149, no sobre
-- la anterior. Si entre medio alguna de las cuatro se vuelve a tocar, hay que rebasar este archivo
-- sobre la versión vigente antes de correrlo, o el redondeo se pierde de nuevo.
--
-- Es literalmente lo que pasó con `calcular_factor_k_subitem`: la `0078` puso 31 `round()`, la
-- `0110` hizo drop+create y se los llevó puestos, la `0115` los devolvió. Chequeo rápido antes y
-- después de aplicar esto:
--
--   select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--   where n.nspname = 'public'
--     and p.proname in ('calcular_monto_obra_subitems', 'calcular_presupuesto_vivo_obra',
--                       'calcular_presupuesto_hoy_config_congelada_obra', 'congelar_presupuesto_obra')
--     and pg_get_functiondef(p.oid) like '%round(%';   -- tiene que dar 4 en los dos momentos
--
-- Aplicar a mano en el SQL Editor de Supabase. No ejecutado automáticamente por Claude Code.
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
    -- CAMBIO 2: `or precio_unitario_manual is not null`. Antes era solo `usa_apu = false`.
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
    where usa_apu = false or precio_unitario_manual is not null
  ),
  apu_ids as (
    -- Las partidas con precio manual cargado salen de acá: ya las resolvió la rama de arriba, y
    -- dejarlas entraría la misma partida dos veces en el union all.
    select array_agg(subitem_id) as ids from base
    where usa_apu = true and precio_unitario_manual is null
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
    where b.usa_apu = true and b.precio_unitario_manual is null
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
    where usa_apu = false or precio_unitario_manual is not null
  ),
  apu_ids as (
    select array_agg(subitem_id) as ids from base
    where usa_apu = true and precio_unitario_manual is null
  ),
  apu_precios as (
    -- unnest(null) da 0 filas, no error -- caso obra sin ninguna partida de APU tildada todavía.
    select * from calcular_precio_final_apu_subitems(p_obra_id, (select ids from apu_ids))
  ),
  apu as (
    select round(b.cantidad * p.precio_final, 2) as monto
    from base b
    join apu_precios p on p.subitem_id = b.subitem_id
    where b.usa_apu = true and b.precio_unitario_manual is null
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
    where usa_apu = false or precio_unitario_manual is not null
  ),
  apu as (
    select round(b.cantidad * f.precio_final, 2) as monto
    from base b
    cross join lateral calcular_factor_k_subitem(p_obra_id, b.subitem_id, true) as f
    cross join vista_congelada v
    where b.usa_apu = true and b.precio_unitario_manual is null
      and f.vista = v.vista and f.orden = 1
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
--
-- Del cambio 2 acá sale una consecuencia que conviene tener presente: una partida de rubro con APU
-- y precio manual se congela por la rama manual, o sea con `precio_final`, `costo_costo` y
-- `materiales_subtotal` en null. Eso hace que, si la obra tiene CAC activado,
-- `calcular_monto_congelado_ajustado` (0106) la ajuste por la serie **general** en vez de repartir
-- entre materiales y mano de obra -- que es el comportamiento correcto y el que ya tenían los
-- rubros de precio manual: un precio cerrado a mano no tiene composición que repartir.

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
    where usa_apu = false or precio_unitario_manual is not null
  ),
  apu_ids as (
    select array_agg(subitem_id) as ids from base
    where usa_apu = true and precio_unitario_manual is null
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
    where b.usa_apu = true and b.precio_unitario_manual is null
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
-- Verificación
-- =====================================================================
--
-- Una partida de rubro con APU y precio manual cargado ahora suma:
--
--   select s.codigo, s.descripcion, r.usa_apu, os.cantidad, os.precio_unitario_manual,
--          m.monto_total, m.tiene_precio_completo
--   from obra_subitems os
--   join rubros r   on r.id = os.rubro_id
--   join subitems s on s.id = os.subitem_id
--   join calcular_monto_obra_subitems(os.obra_id) m on m.obra_subitem_id = os.id
--   where os.obra_id = '<obra_id>' and r.usa_apu = true and os.precio_unitario_manual is not null;
--
--   -- monto_total = cantidad * precio_unitario_manual (redondeado), tiene_precio_completo true.
--
-- REGRESIÓN, la que importa -- una partida de rubro con APU y SIN precio manual tiene que dar
-- exactamente lo mismo que antes. Anotar el número antes de aplicar y comparar después:
--
--   select calcular_presupuesto_vivo_obra('<obra_id_con_apu_real>');
--
-- Y que ninguna partida entre dos veces (el union all es disjunto por construcción):
--
--   select obra_subitem_id, count(*) from calcular_monto_obra_subitems('<obra_id>')
--   group by obra_subitem_id having count(*) > 1;   -- 0 filas
