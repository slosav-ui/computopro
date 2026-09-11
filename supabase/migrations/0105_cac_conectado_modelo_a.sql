-- CAC conectado al Modelo A -- cierra la línea que arrancó con `0102` (índices) y siguió con
-- `0103`/`0104` (congelamiento). Diseño completo, con las 3 ambigüedades cerradas, en
-- docs/cac_conectado_modelo_a_diseno.md -- este archivo es la implementación de ese documento.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor), después de `0104`. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

-- =====================================================================
-- Paso 1 -- obras.cac_serie: general vs. separado, ambigüedad A
-- =====================================================================
--
-- Nace en 'materiales_mano_obra' (separado) -- ambigüedad A, cerrada por Seba: "es lo más preciso
-- y es lo que corresponde... como esto aplica a obras que todavía no están en producción, no hay a
-- quién sorprender". Leída ÚNICAMENTE por las funciones nuevas de este archivo --
-- `calcular_saldo_pendiente_hitos` (Modelo B, `0102`) no la toca, sigue ignorándola por completo.

alter table obras
  add column cac_serie text not null default 'materiales_mano_obra'
    check (cac_serie in ('general', 'materiales_mano_obra'));

-- =====================================================================
-- Paso 2 -- factor_cac_obra gana un parámetro opcional: mes base explícito
-- =====================================================================
--
-- Hallazgo del diagnóstico, confirmado por Seba: `obras.mes_base_cac` se carga UNA SOLA VEZ, al
-- crear la obra (`obras_list_screen.dart`, `_primerDiaDelMesActual()`) -- correcto para el Modelo
-- B, donde el monto se pacta cerca de la creación, pero equivocado para el Modelo A: acá el mes
-- base tiene que ser el del CONGELAMIENTO (`presupuesto_congelado_en`), que puede quedar semanas o
-- meses después de crear la obra (cómputo, negociación, firma).
--
-- Parámetro nuevo al final, con default `null` -- SIN romper ninguna llamada existente en cuanto a
-- COMPORTAMIENTO. `p_mes_base is null` (el default, lo que sigue usando `calcular_saldo_pendiente_hitos`
-- sin cambios) preserva el comportamiento exacto de hoy: lee `obras.mes_base_cac`. Con un valor
-- explícito (lo que va a usar la función nueva de más abajo), lo usa en su lugar. Cero cambio de
-- comportamiento para el Modelo B -- confirmado, `calcular_saldo_pendiente_hitos` no se toca en
-- este archivo.
--
-- OJO -- `create or replace` NO alcanza acá, a diferencia del resto de las funciones de este
-- archivo: Postgres identifica una función por su lista de TIPOS de parámetros, no por el nombre
-- solo. `factor_cac_obra(uuid, text)` (la firma de hoy) y `factor_cac_obra(uuid, text, date)` (la
-- nueva) son dos firmas DISTINTAS -- un `create or replace` con el parámetro de más crearía una
-- SEGUNDA función sobrecargada en vez de reemplazar la primera, y con las dos firmas coexistiendo
-- cualquier llamada de 2 argumentos (como la que ya hace `calcular_saldo_pendiente_hitos`) queda
-- ambigua para Postgres ("function factor_cac_obra(uuid, text) is not unique") -- rompería el
-- Modelo B, exactamente lo que esta pieza tiene que evitar. `drop` primero, para que solo quede
-- una firma.

drop function factor_cac_obra(uuid, text);

create function factor_cac_obra(
  p_obra_id uuid,
  p_serie text default 'general',
  p_mes_base date default null
)
returns numeric
language plpgsql security definer set search_path = public stable as $$
declare
  v_mes_base date;
  v_indice_base numeric;
  v_indice_actual numeric;
  v_mes_actual date := date_trunc('month', current_date)::date;
begin
  if not is_obra_member(p_obra_id) then
    raise exception 'No sos miembro de esta obra.';
  end if;

  if p_serie not in ('general', 'materiales', 'mano_obra') then
    raise exception 'Serie de índice CAC inválida: %', p_serie;
  end if;

  if p_mes_base is not null then
    v_mes_base := p_mes_base;
  else
    select mes_base_cac into v_mes_base from obras where id = p_obra_id;
  end if;

  if v_mes_base is null then
    raise exception 'Esta obra no tiene mes base de CAC configurado.';
  end if;

  select case p_serie
           when 'general' then general
           when 'materiales' then materiales
           when 'mano_obra' then mano_obra
         end
    into v_indice_base
  from indices_cac where mes = v_mes_base;

  if v_indice_base is null then
    raise exception 'No hay índice CAC (%) cargado para el mes base de esta obra (%).', p_serie, v_mes_base;
  end if;

  select case p_serie
           when 'general' then general
           when 'materiales' then materiales
           when 'mano_obra' then mano_obra
         end
    into v_indice_actual
  from indices_cac where mes = v_mes_actual;

  if v_indice_actual is null then
    raise exception 'Todavía no se cargó el índice CAC (%) de este mes (%).', p_serie, v_mes_actual;
  end if;

  return v_indice_actual / v_indice_base;
end;
$$;

grant execute on function factor_cac_obra(uuid, text, date) to authenticated;
revoke execute on function factor_cac_obra(uuid, text, date) from public, anon;

-- =====================================================================
-- Paso 3 -- calcular_monto_congelado_ajustado: la función compartida
-- =====================================================================
--
-- Meter el mismo cálculo en dos lugares (saldo pendiente y certificación) es exactamente el
-- patrón que ya mordió a este proyecto tres veces (`0091`→`0094`, `0094`→`0104`, y el motivo
-- explícito por el que existe `calcular_precio_final_apu_subitems`, `0090`, en primer lugar) --
-- confirmado por Seba como criterio para esta pieza. Una sola función, dos consumidores (pasos 4 y
-- 5), nunca la cuenta reescrita en el segundo lugar.
--
-- Devuelve, por partida congelada: el monto ya ajustado, la serie que se usó, y si esa partida
-- cayó al fallback de "general" aunque la obra eligió separar series (ambigüedad C -- ver más
-- abajo por qué hace falta esta columna).
--
-- La demostración de por qué la proporción materiales_subtotal/costo_costo es EXACTA (no una
-- estimación) para partidas con APU en vista "con materiales" está en
-- docs/cac_conectado_modelo_a_diseno.md §1 -- la cascada de Factor K multiplica costo_costo entero
-- por un único factor K, así que esa proporción se conserva intacta después de aplicar GG/
-- Imprevistos/EPP/CF/Beneficio/Impuestos.
--
-- Tres casos caen al fallback "general" -- cerrado con Seba que SÍ hay que marcarlos (ambigüedad
-- C, `fallback_general`):
--   1) Rubros de precio manual (usa_apu = false): costo_costo/materiales_subtotal quedan null en
--      `presupuesto_subitems_congelado` (`0104` §5) -- sin cascada, no hay proporción que sacar.
--      Frecuente, no marginal -- Seba: "hay 17 rubros en el catálogo y varios se cotizan de forma
--      global".
--   2) Partida con APU pero costo_costo congelado en 0 (todos sus insumos sin precio al momento de
--      congelar) -- división por cero, mismo fallback.
--   3) Vista "sin materiales" (`tipo_presupuesto = 'mano_obra_sola'`) -- caso DISTINTO, no
--      fallback: acá el 100% va a la serie mano de obra a propósito (el contratista no cobra
--      materiales en esa modalidad, `costo_costo` congelado en esta vista ya los excluye) --
--      `fallback_general` queda `false` para estas filas, es el comportamiento correcto de la
--      obra, no una excepción que haya que señalar.
create or replace function calcular_monto_congelado_ajustado(p_obra_id uuid)
returns table(
  obra_subitem_id uuid,
  monto_total numeric,
  serie_aplicada text,
  fallback_general boolean
)
language plpgsql security definer set search_path = public stable as $$
declare
  v_congelado_en timestamptz;
  v_aplica_cac boolean;
  v_cac_serie text;
  v_tipo_presupuesto text;
  v_mes_base date;
  v_factor_general numeric;
  v_factor_materiales numeric;
  v_factor_mano_obra numeric;
begin
  if not is_obra_member(p_obra_id) then
    return; -- fail-closed, 0 filas -- mismo criterio que el resto del proyecto
  end if;

  select o.presupuesto_congelado_en, o.aplica_cac, o.cac_serie
    into v_congelado_en, v_aplica_cac, v_cac_serie
  from obras o
  where o.id = p_obra_id;

  -- Obra sin congelar: nada que ajustar -- presupuesto_subitems_congelado está vacío para esta
  -- obra de cualquier forma, así que 0 filas es el resultado correcto (el llamador usa la rama en
  -- vivo, no esta función, mientras la obra no esté congelada).
  if v_congelado_en is null then
    return;
  end if;

  -- Sin CAC activado: el monto congelado tal cual, sin tocar -- serie_aplicada null (no hay
  -- ninguna), fallback_general false (no aplica el concepto sin CAC).
  if coalesce(v_aplica_cac, false) is not true then
    return query
      select psc.obra_subitem_id, psc.monto_total, null::text, false
      from presupuesto_subitems_congelado psc
      where psc.obra_id = p_obra_id;
    return;
  end if;

  select c.tipo_presupuesto into v_tipo_presupuesto
  from presupuesto_config_congelado c
  where c.obra_id = p_obra_id;

  v_mes_base := date_trunc('month', v_congelado_en)::date;

  if v_cac_serie = 'general' then
    -- La obra eligió el índice general para todo -- ninguna fila es "fallback", es el criterio
    -- elegido para la obra entera.
    v_factor_general := factor_cac_obra(p_obra_id, 'general', v_mes_base);
    return query
      select psc.obra_subitem_id, psc.monto_total * v_factor_general, 'general'::text, false
      from presupuesto_subitems_congelado psc
      where psc.obra_id = p_obra_id;
    return;
  end if;

  -- cac_serie = 'materiales_mano_obra' -- los 3 factores de una sola vez, no uno por partida.
  v_factor_materiales := factor_cac_obra(p_obra_id, 'materiales', v_mes_base);
  v_factor_mano_obra := factor_cac_obra(p_obra_id, 'mano_obra', v_mes_base);
  v_factor_general := factor_cac_obra(p_obra_id, 'general', v_mes_base); -- solo para el fallback

  return query
    select
      psc.obra_subitem_id,
      case
        when psc.costo_costo is null or psc.costo_costo = 0
          then psc.monto_total * v_factor_general
        when v_tipo_presupuesto = 'mano_obra_sola'
          then psc.monto_total * v_factor_mano_obra
        else
          psc.monto_total * (coalesce(psc.materiales_subtotal, 0) / psc.costo_costo) * v_factor_materiales
          + psc.monto_total * (1 - coalesce(psc.materiales_subtotal, 0) / psc.costo_costo) * v_factor_mano_obra
      end,
      case
        when psc.costo_costo is null or psc.costo_costo = 0 then 'general'
        when v_tipo_presupuesto = 'mano_obra_sola' then 'mano_obra'
        else 'materiales_mano_obra'
      end,
      (psc.costo_costo is null or psc.costo_costo = 0) -- único caso real de fallback, ver cabecera
    from presupuesto_subitems_congelado psc
    where psc.obra_id = p_obra_id;
end;
$$;

grant execute on function calcular_monto_congelado_ajustado(uuid) to authenticated;
revoke execute on function calcular_monto_congelado_ajustado(uuid) from public, anon;

-- =====================================================================
-- Paso 4 -- calcular_saldo_pendiente_avance_medido: consume la función compartida
-- =====================================================================
--
-- `create or replace`, misma firma que `0104`. Único cambio: ya no lee `presupuesto_subitems_
-- congelado.monto_total` directo -- lee el monto ya ajustado de `calcular_monto_congelado_
-- ajustado`, que internamente devuelve el mismo número sin ajustar cuando `aplica_cac` es falso o
-- la obra no está congelada, así que el comportamiento para esos dos casos no cambia.
create or replace function calcular_saldo_pendiente_avance_medido(p_obra_id uuid)
returns numeric
language sql security definer set search_path = public stable as $$
  select coalesce(sum(
    mca.monto_total * (100 - calcular_avance_acumulado_subitem(mca.obra_subitem_id)) / 100
  ), 0)
  from calcular_monto_congelado_ajustado(p_obra_id) mca;
$$;

grant execute on function calcular_saldo_pendiente_avance_medido(uuid) to authenticated;
revoke execute on function calcular_saldo_pendiente_avance_medido(uuid) from public, anon;

-- =====================================================================
-- Paso 5 -- calcular_monto_obra_subitems: la rama congelada también ajusta por CAC
-- =====================================================================
--
-- Confirmado por Seba (punto 2 del diagnóstico): "si se certifica contra el presupuesto congelado,
-- y ese presupuesto se ajusta por CAC, el certificado tiene que usar el valor ajustado al mes de
-- la certificación". Como un certificado se calcula y se congela en el momento de emitirlo
-- (`now()`), leer acá el monto de `calcular_monto_congelado_ajustado` (que usa el mes actual como
-- destino) YA da "el valor ajustado al mes de la certificación", sin que `emitir_certificado` ni el
-- trigger de `0052` necesiten saber que existe CAC -- mismo desacople que ya logró `0104` al
-- separar esta función de la fuente del precio.
--
-- `create or replace`, misma firma que `0052`/`0094`/`0104` -- solo cambia de dónde lee la rama
-- `congelado`. Las ramas `manual`/`apu` (obra sin congelar) quedan idénticas.
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
    select mca.obra_subitem_id, mca.monto_total, true as tiene_precio_completo
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
-- Paso 6 -- desglose pactado/ajuste en la certificación (ambigüedad B)
-- =====================================================================
--
-- Cerrado por Seba, en contra de mi propuesta de alcance mínimo: "cuando un cliente pregunte por
-- qué el certificado 5 salió más caro que el 3 por la misma partida y el mismo avance, tiene que
-- haber una respuesta... una vez emitido, si no se guardó, esa información se perdió para siempre.
-- Es barato ahora y caro después." Mismo criterio que ya usa el proyecto para anticipo_pct_aplicado/
-- fondo_reparo_pct_aplicado (`0009`): snapshot al emitir, congelado para siempre junto con el resto
-- del certificado.
--
-- Una sola columna nueva por nivel (no una tercera para "el ajuste" -- se deriva restando, no tiene
-- ningún significado de negocio propio más allá de esa resta, a diferencia de anticipo/fondo de
-- reparo que sí son porcentajes independientes entre sí).

alter table certificado_subitems_avance
  add column monto_periodo_pactado numeric not null default 0;

alter table certificados
  add column monto_pactado numeric
    check (monto_pactado is null or monto_pactado >= 0);
-- null en certificados emitidos ANTES de esta migración -- no se puede reconstruir el desglose
-- retroactivo (la certificación de esos ya usaba precios en vivo, sin ningún concepto de "pactado"
-- separado del total), mismo criterio de "no retroactivo" que ya rige el resto del proyecto. Un
-- certificado nuevo, emitido después de aplicar esto, siempre lo trae.

-- calcular_monto_periodo_avance (trigger de certificado_subitems_avance, 0052): agrega
-- monto_periodo_pactado en la misma pasada, sin abrir una segunda consulta a
-- calcular_monto_obra_subitems -- lee presupuesto_subitems_congelado directo (el monto SIN
-- ajustar) y, si la obra no está congelada, usa el mismo monto vivo que ya calculó para
-- monto_periodo (no hay "pactado" distinto de lo vivo cuando no hay congelamiento).
create or replace function calcular_monto_periodo_avance()
returns trigger language plpgsql as $$
declare
  v_obra_id uuid;
  v_estado text;
  v_monto_total_subitem numeric;
  v_monto_pactado_subitem numeric;
begin
  select c.obra_id, c.estado into v_obra_id, v_estado
  from certificados c where c.id = new.certificado_id;

  if v_estado is distinct from 'borrador' then
    raise exception 'el certificado % no está en borrador (estado actual: %)', new.certificado_id, v_estado;
  end if;

  select monto_total into v_monto_total_subitem
  from calcular_monto_obra_subitems(v_obra_id)
  where obra_subitem_id = new.obra_subitem_id;

  select monto_total into v_monto_pactado_subitem
  from presupuesto_subitems_congelado
  where obra_subitem_id = new.obra_subitem_id;

  if v_monto_pactado_subitem is null then
    v_monto_pactado_subitem := v_monto_total_subitem;
  end if;

  new.monto_periodo := round(coalesce(v_monto_total_subitem, 0) * new.porcentaje_periodo / 100, 2);
  new.monto_periodo_pactado := round(coalesce(v_monto_pactado_subitem, 0) * new.porcentaje_periodo / 100, 2);
  new.updated_at := now();
  return new;
end;
$$;

-- calcular_totales_certificado (0054): DROP + CREATE, no `create or replace` -- cambia el
-- `returns table` (2 columnas nuevas al final), Postgres no permite reemplazar en el lugar cuando
-- cambia la lista de columnas de salida. Sin dependencias duras que romper: ninguna otra función ni
-- vista la referencia a nivel de esquema (ver nota de verificación al final), así que el DROP es
-- seguro dentro de esta misma migración.
drop function calcular_totales_certificado(uuid);

create function calcular_totales_certificado(p_certificado_id uuid)
returns table(
  monto numeric,
  anticipo_pct numeric,
  fondo_reparo_pct numeric,
  monto_anticipo numeric,
  monto_fondo_reparo numeric,
  monto_neto numeric,
  dias_plazo_pago int,
  monto_pactado numeric,
  monto_ajuste_cac numeric
)
language sql stable as $$
  with cert as (
    select c.obra_id from certificados c where c.id = p_certificado_id
  ),
  monto as (
    select
      coalesce(sum(csa.monto_periodo), 0) as v,
      coalesce(sum(csa.monto_periodo_pactado), 0) as v_pactado
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
    o.dias_plazo_pago_certificados as dias_plazo_pago,
    m.v_pactado as monto_pactado,
    m.v - m.v_pactado as monto_ajuste_cac
  from cert c
  join obras o on o.id = c.obra_id
  cross join monto m;
$$;

grant execute on function calcular_totales_certificado(uuid) to authenticated;
revoke execute on function calcular_totales_certificado(uuid) from public, anon;
-- Corregido (Seba, 2026-09-11): cerrada a mano en producción tras encontrarla abierta a anon.
-- Precisión sobre el origen (revisado contra el archivo, no de memoria): la `0085` NO le agregó
-- revoke a esta función -- la clasificó en su "Paso 3" (funciones SECURITY INVOKER, búsqueda de
-- `search_path` nada más) junto con otras 9, con el argumento de que una INVOKER no necesita
-- revoke por seguridad: corre con los privilegios de quien la llama, así que si `anon` la ejecuta
-- sigue chocando contra la RLS de `certificados`/`obras` igual que si llamara a esas tablas
-- directo -- sin filtración real. Esa clasificación seguía siendo correcta acá (sigue siendo
-- `language sql stable`, sin `security definer`, sin cambios en ese aspecto por el DROP de abajo).
-- Lo que sí es válida es la lección general que motivó este chequeo: un `DROP FUNCTION` +
-- `CREATE FUNCTION` resetea el `EXECUTE` de vuelta al default de Postgres (abierto a PUBLIC/anon)
-- sin importar si la función es DEFINER o INVOKER -- por eso apareció abierta después de esta
-- migración aunque nunca lo hubiera estado por un exploit real. Se revoca igual por prolijidad y
-- para no depender de que el argumento de "INVOKER = inofensiva" siga siendo válido si el cuerpo
-- de la función cambia en el futuro.

-- emitir_certificado (0055, vigente hoy): YA lee `v_totales` de `calcular_totales_certificado` --
-- agregar `monto_pactado` a la fila que se congela es una línea nueva en el UPDATE, sin tocar nada
-- más de la función (mismo motivo por el que 0055 ya la había centralizado ahí: una sola fuente
-- para todo lo que hay que congelar).
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

  select * into v_exceso from calcular_excesos_certificado(p_certificado_id) limit 1;
  if v_exceso.obra_subitem_id is not null then
    raise exception '"%" ya tiene % certificado — quedan % disponibles, se intentó cargar %',
      v_exceso.descripcion, v_exceso.acumulado_previo, v_exceso.disponible, v_exceso.intentado;
  end if;

  select * into v_totales from calcular_totales_certificado(p_certificado_id);

  if v_totales.monto <= 0 then
    raise exception 'no se puede emitir un certificado sin avance cargado';
  end if;

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
      monto_neto_a_pagar = v_totales.monto_neto
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
      'monto_neto_a_pagar', v_totales.monto_neto
    )
  );
end;
$$;

grant execute on function emitir_certificado(uuid, boolean) to authenticated;

-- =====================================================================
-- Paso 7 -- recalcular borradores con avance ya cargado (mismo paso que 0094/0104 -- la nota
-- "PATRÓN A REPETIR" de la 0094 pedía explícitamente repetirlo en cualquier migración que cambiara
-- qué alimenta monto_periodo, y el trigger de arriba vuelve a cambiar)
-- =====================================================================
update certificado_subitems_avance
set porcentaje_periodo = porcentaje_periodo
where certificado_id in (select id from certificados where estado = 'borrador');

-- =====================================================================
-- Verificación
-- =====================================================================
--
-- 0) Antes de aplicar: confirmar que nada más depende de la firma vieja de
--    calcular_totales_certificado(uuid) -- returns table(monto, anticipo_pct, fondo_reparo_pct,
--    monto_anticipo, monto_fondo_reparo, monto_neto, dias_plazo_pago), 7 columnas:
--    select pg_get_functiondef(oid) from pg_proc where proname = 'calcular_totales_certificado';
--    (esperado: solo esta función y `emitir_certificado` la mencionan, ninguna vista/trigger).
--
-- 1) Obra en Modelo A, congelada, aplica_cac = true, cac_serie por defecto
--    ('materiales_mano_obra'): calcular_saldo_pendiente_avance_medido baja o sube respecto de sumar
--    presupuesto_subitems_congelado.monto_total a secas, según el mes actual vs. el mes de
--    congelamiento -- y el número no coincide con multiplicar por un solo factor general (prueba
--    de que sí está separando materiales/mano de obra).
-- 2) Misma obra, cac_serie = 'general': el saldo SÍ coincide con multiplicar el total pactado
--    pendiente por un único factor_cac_obra(obra, 'general', mes_congelamiento).
-- 3) Partida de un rubro sin APU (usa_apu = false) en una obra con cac_serie separado:
--    calcular_monto_congelado_ajustado devuelve fallback_general = true para esa fila, serie_aplicada
--    = 'general' -- y el número usa el factor general, no una mezcla.
-- 4) Cargar avance y emitir un certificado sobre una obra congelada con aplica_cac = true: el
--    monto del certificado (calcular_totales_certificado.monto, lo que congela emitir_certificado)
--    es mayor a monto_pactado en la proporción esperada -- monto_ajuste_cac > 0. Emitir un segundo
--    certificado el mes siguiente (o simulando el paso de mes con otro índices_cac cargado) sobre
--    la misma partida y mismo % tiene que dar un monto_periodo más alto que el primero.
-- 5) Obra SIN congelar (la mayoría, hoy): calcular_monto_obra_subitems, calcular_saldo_pendiente_
--    avance_medido (0 filas congeladas, sigue dando 0 como antes) y emitir_certificado siguen
--    exactamente igual que antes de esta migración.
-- 6) calcular_saldo_pendiente_hitos (Modelo B) sin cambios -- confirmar que sigue funcionando
--    idéntico, sin leer obras.cac_serie ni el nuevo parámetro de factor_cac_obra.
-- 7) Falta el índice CAC del mes actual (o del mes de congelamiento): factor_cac_obra sigue
--    cortando con excepción explícita, nunca un valor aproximado -- mismo comportamiento ya
--    verificado en 0102, sin cambios de fondo acá.
