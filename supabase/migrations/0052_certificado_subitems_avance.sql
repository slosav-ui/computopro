-- Gestión de Obra, pieza 2: avance por partida (Modelo A). Corrige la premisa equivocada del
-- diseño original de `certificados` — el monto no se tipea a mano, sale de certificar un % de
-- avance por subítem, ponderado por lo que vale cada uno, sumado hacia arriba. Ver la sesión que
-- cerró este diseño para el razonamiento completo; acá solo queda el SQL ya decidido.
--
-- Alcance: solo Modelo A. `hitos_certificacion` (Modelo B) no se toca — sigue con su propio
-- mecanismo, monto fijado directo por el Administrador, sin ningún concepto de subítem. La
-- política INSERT de `certificados` ya garantiza que esta tabla nueva solo puede colgar de un
-- certificado creado bajo `modelo_certificacion = 'avance_medido'` (0009), así que la separación
-- entre modelos no necesita ningún guard adicional acá.
--
-- Decisión de negocio que condiciona todo el diseño de abajo: es un certificado por vez, no hay
-- dos borradores abiertos a la vez sobre la misma obra — el borrador es, literalmente, el
-- borrador del certificado que se está por emitir. Por eso el acumulado para el bloqueo del 100%
-- cuenta SOLO certificados que ya dejaron de ser borrador (emitido en adelante), nunca el propio
-- borrador en curso — y por eso la validación real contra ese acumulado se hace una sola vez, al
-- emitir, no en cada carga mientras se compone el borrador.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

-- =====================================================================
-- Tabla certificado_subitems_avance
-- =====================================================================
--
-- Apunta a obra_subitems, no a subitems del catálogo — un mismo subítem puede repetirse en
-- distintos sectores de la misma obra (docs/rubros_apu_diseno_datos.md §3.C, obra_subitems sin
-- unique(obra_id, subitem_id) a propósito); apuntar a la fila de obra_subitems en vez del
-- catálogo evita que dos sectores compartan avance sin querer, sin necesitar ningún caso especial.
--
-- porcentaje_periodo: lo cargado en ESTE certificado puntual, no el acumulado (Seba: "en el
-- primer certificado certifiqué 15%, en el segundo 55%... el tercero hago 30" — cada fila guarda
-- el período, el acumulado se calcula, nunca se guarda como tal en esta tabla).
--
-- monto_periodo: snapshot, mismo criterio que anticipo_pct_aplicado/fondo_reparo_pct_aplicado en
-- certificados — si el precio de la partida cambia después, el certificado ya emitido no se
-- mueve. Se calcula server-side en el trigger de más abajo, nunca se recibe del cliente tal cual
-- — así nadie puede mandar un monto inventado.
create table certificado_subitems_avance (
  id uuid primary key default gen_random_uuid(),
  certificado_id uuid not null references certificados(id) on delete cascade,
  obra_subitem_id uuid not null references obra_subitems(id),
  porcentaje_periodo numeric not null check (porcentaje_periodo > 0 and porcentaje_periodo <= 100),
  monto_periodo numeric not null default 0,
  creado_por uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (certificado_id, obra_subitem_id)
);

-- =====================================================================
-- Snapshot server-side de monto_periodo — trigger, no cálculo en Dart
-- =====================================================================
--
-- BEFORE INSERT OR UPDATE, no solo INSERT: mientras el certificado sigue en borrador, el usuario
-- puede corregir un porcentaje ya cargado (revisar el número antes de emitir) — cada corrección
-- tiene que recalcular monto_periodo con el precio vigente en ese momento, no arrastrar el
-- snapshot de la carga anterior.
--
-- Doble candado sin costo, mismo criterio que el resto del proyecto: la RLS de más abajo ya
-- restringe la escritura a mientras el certificado esté en borrador, pero el trigger lo vuelve a
-- chequear acá — si algún día la RLS cambia sin que este trigger se actualice en el mismo golpe,
-- esto sigue protegiendo solo.
create or replace function calcular_monto_periodo_avance()
returns trigger language plpgsql as $$
declare
  v_obra_id uuid;
  v_estado text;
  v_monto_total_subitem numeric;
begin
  select c.obra_id, c.estado into v_obra_id, v_estado
  from certificados c where c.id = new.certificado_id;

  if v_estado is distinct from 'borrador' then
    raise exception 'el certificado % no está en borrador (estado actual: %)', new.certificado_id, v_estado;
  end if;

  select monto_total into v_monto_total_subitem
  from calcular_monto_obra_subitems(v_obra_id)
  where obra_subitem_id = new.obra_subitem_id;

  new.monto_periodo := round(coalesce(v_monto_total_subitem, 0) * new.porcentaje_periodo / 100, 2);
  new.updated_at := now();
  return new;
end;
$$;

create trigger certificado_subitems_avance_calcular_monto
  before insert or update on certificado_subitems_avance
  for each row execute function calcular_monto_periodo_avance();

-- =====================================================================
-- RLS
-- =====================================================================
--
-- SELECT: cualquier miembro de la obra (vía el certificado). INSERT/UPDATE/DELETE: mismos 3 roles
-- que ya pueden crear/cargar un Borrador de certificado (crear_certificado_borrador, 0009 —
-- admin_maestro/profesional/constructor), y solo mientras el certificado padre siga en borrador —
-- mismo criterio que certificados_update (0010, "solo borrador").

alter table certificado_subitems_avance enable row level security;

create policy certificado_subitems_avance_select on certificado_subitems_avance for select
using (
  is_obra_member((select obra_id from certificados where id = certificado_id))
);

create policy certificado_subitems_avance_insert on certificado_subitems_avance for insert with check (
  exists (
    select 1 from certificados c
    where c.id = certificado_id and c.estado = 'borrador'
      and (tiene_rol_en_obra(c.obra_id, 'admin_maestro')
        or tiene_rol_en_obra(c.obra_id, 'profesional')
        or tiene_rol_en_obra(c.obra_id, 'constructor'))
  )
);

create policy certificado_subitems_avance_update on certificado_subitems_avance for update using (
  exists (
    select 1 from certificados c
    where c.id = certificado_id and c.estado = 'borrador'
      and (tiene_rol_en_obra(c.obra_id, 'admin_maestro')
        or tiene_rol_en_obra(c.obra_id, 'profesional')
        or tiene_rol_en_obra(c.obra_id, 'constructor'))
  )
) with check (
  exists (
    select 1 from certificados c
    where c.id = certificado_id and c.estado = 'borrador'
      and (tiene_rol_en_obra(c.obra_id, 'admin_maestro')
        or tiene_rol_en_obra(c.obra_id, 'profesional')
        or tiene_rol_en_obra(c.obra_id, 'constructor'))
  )
);

create policy certificado_subitems_avance_delete on certificado_subitems_avance for delete using (
  exists (
    select 1 from certificados c
    where c.id = certificado_id and c.estado = 'borrador'
      and (tiene_rol_en_obra(c.obra_id, 'admin_maestro')
        or tiene_rol_en_obra(c.obra_id, 'profesional')
        or tiene_rol_en_obra(c.obra_id, 'constructor'))
  )
);

create trigger set_updated_at_certificado_subitems_avance
  before update on certificado_subitems_avance
  for each row execute function set_updated_at();

-- =====================================================================
-- calcular_monto_obra_subitems — el monto real de cada subítem tildado, las 3 ramas de precio
-- =====================================================================
--
-- No existía ninguna función que diera esto — calcular_precio_apu_subitems (0034) da precio
-- UNITARIO de la receta, no el monto de ese subítem en esta obra (falta multiplicar por
-- obra_subitems.cantidad); y para los rubros sin APU (usa_apu = false: 1/18/19/20/custom) el
-- monto no sale de ninguna composición, sale directo de precio_unitario_manual, con una
-- salvedad: en tipo_precio_manual = 'unitario' se multiplica por cantidad, en 'global' ya es el
-- total de la partida (mismo criterio que ya bifurca subitems_screen.dart para mostrarlo).
--
-- tiene_precio_completo se deja aunque hoy no se use en ningún lado (partidas sin precio no son
-- un caso a contemplar, confirmado) — mismo patrón del proyecto de no colapsar "sin precio" a 0
-- en silencio (calcular_precio_apu_subitems, consolidado_insumos_obra), gratis de mantener.
create or replace function calcular_monto_obra_subitems(p_obra_id uuid)
returns table(obra_subitem_id uuid, monto_total numeric, tiene_precio_completo boolean)
language sql security definer set search_path = public stable as $$
  with autorizado as (
    -- SECURITY DEFINER bypassa la RLS de obra_subitems, así que el chequeo de membresía se repite
    -- acá a mano — mismo motivo y mismo patrón que calcular_precio_apu_subitems (0034).
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
    select * from calcular_precio_apu_subitems(p_obra_id, (select ids from apu_ids))
  ),
  apu as (
    select
      b.obra_subitem_id,
      b.cantidad * p.precio_total as monto_total,
      (p.insumos_total > 0 and p.insumos_con_precio = p.insumos_total) as tiene_precio_completo
    from base b
    join apu_precios p on p.subitem_id = b.subitem_id
    where b.usa_apu = true
  )
  select * from manual
  union all
  select * from apu;
$$;

grant execute on function calcular_monto_obra_subitems(uuid) to authenticated;

-- =====================================================================
-- calcular_avance_acumulado_subitem — solo certificados que ya dejaron de ser borrador
-- =====================================================================
--
-- Sin parámetro de exclusión: como es un certificado por vez y el acumulado nunca cuenta
-- borradores, el certificado que se está componiendo (todavía en 'borrador' en el momento en que
-- se lo consulta) ya queda afuera solo, por el propio filtro de estado — no hace falta excluirlo
-- a mano, ni siquiera en el momento de emitir (ver emitir_certificado más abajo: la validación
-- corre ANTES de que ese certificado cambie de estado, así que sigue siendo 'borrador' cuando
-- esta función lo mira, y el filtro lo excluye igual que a cualquier otro borrador).
--
-- SECURITY INVOKER (sin `security definer`), a propósito, mismo patrón que calcular_avance_hitos
-- (Modelo B): las tablas que consulta (certificado_subitems_avance, certificados) ya tienen su
-- propia RLS con is_obra_member — para un no-miembro, esa RLS ya devuelve 0 filas sola (fail-
-- closed correcto, mismo criterio del resto del proyecto), no hace falta bypassearla. Llamada
-- desde dentro de emitir_certificado (SECURITY DEFINER) igual ve todo lo que necesita, porque
-- corre con el contexto de privilegios de la función que la llama.
create or replace function calcular_avance_acumulado_subitem(p_obra_subitem_id uuid)
returns numeric language sql stable as $$
  select coalesce(sum(csa.porcentaje_periodo), 0)
  from certificado_subitems_avance csa
  join certificados c on c.id = csa.certificado_id
  where csa.obra_subitem_id = p_obra_subitem_id
    and c.estado <> 'borrador';
$$;

grant execute on function calcular_avance_acumulado_subitem(uuid) to authenticated;

-- =====================================================================
-- Agregación ponderada hacia arriba — subítem -> rubro -> obra
-- =====================================================================
--
-- Peso = monto_total de calcular_monto_obra_subitems (lo que vale ese subítem), valor = avance
-- acumulado (solo lo ya emitido, misma función de arriba) — no el % de este certificado puntual,
-- el acumulado real de la obra a la fecha. nullif(...,0) como divisor, mismo patrón que
-- calcular_avance_hitos para no reventar contra una obra sin subítems tildados/priceados.
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
    sum(p.monto_total) as monto_ponderado
  from pesos p
  group by p.rubro_id;
$$;

grant execute on function calcular_avance_ponderado_rubros(uuid) to authenticated;

create or replace function calcular_avance_ponderado_obra(p_obra_id uuid)
returns numeric language sql stable as $$
  select round(
    sum(avance_pct * monto_ponderado) / nullif(sum(monto_ponderado), 0),
    2
  )
  from calcular_avance_ponderado_rubros(p_obra_id);
$$;

grant execute on function calcular_avance_ponderado_obra(uuid) to authenticated;

-- =====================================================================
-- certificados.monto — deja de ser un valor tipeado a mano al crear
-- =====================================================================
--
-- Antes: `not null check (monto > 0)`, exigido desde el insert del Borrador. Ya no tiene sentido
-- — al crear un Borrador todavía no se cargó ningún avance, el monto no se puede saber de
-- antemano. Pasa a arrancar en 0 ("nada certificado todavía", coherente con que un Borrador vacío
-- ya se acepta como inofensivo, docs/certificados_ciclo_vida_diseno_datos.md §10.6) y
-- emitir_certificado lo recalcula de verdad antes de congelarlo, ver más abajo.
alter table certificados alter column monto set default 0;
alter table certificados drop constraint if exists certificados_monto_check;
alter table certificados add constraint certificados_monto_check check (monto >= 0);

-- =====================================================================
-- emitir_certificado — recalcula monto, valida el 100% acumulado, congela como siempre
-- =====================================================================
--
-- create or replace sobre la función de 0011: mismo cuerpo, con 3 agregados — (1) el monto ya no
-- se lee de la fila, se recalcula sumando monto_periodo de esta tabla nueva; (2) antes de tocar
-- nada, valida que ningún subítem del borrador supere el 100% acumulado (lo ya emitido + lo de
-- este borrador) — es el único candado real contra pasarse de 100, porque el borrador no valida
-- nada mientras se carga (decisión de negocio: un certificado por vez, sin necesidad de bloquear
-- en cada tipeo); (3) no deja emitir con monto en 0 (nada cargado no es un certificado real). El
-- mensaje de la excepción trae el disponible calculado, para que la UI lo muestre sin
-- recalcularlo aparte.
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
  v_monto numeric;
  v_estado text;
  v_dias_plazo_pago int;
  v_anticipo_pct numeric;
  v_fondo_reparo_pct numeric;
  v_prev_requiere_firma boolean;
  v_prev_pdf_subido boolean;
  v_monto_anticipo numeric;
  v_monto_fondo_reparo numeric;
  v_monto_neto numeric;
  v_avance record;
  v_acumulado_previo numeric;
  v_disponible numeric;
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

  -- Candado del 100% acumulado — el único momento en que se valida, ver nota de cabecera.
  for v_avance in
    select csa.obra_subitem_id, csa.porcentaje_periodo,
           coalesce(s.descripcion, os.descripcion_libre, 'subítem sin descripción') as descripcion
    from certificado_subitems_avance csa
    join obra_subitems os on os.id = csa.obra_subitem_id
    left join subitems s on s.id = os.subitem_id
    where csa.certificado_id = p_certificado_id
  loop
    v_acumulado_previo := calcular_avance_acumulado_subitem(v_avance.obra_subitem_id);
    v_disponible := round(100 - v_acumulado_previo, 2);
    if v_avance.porcentaje_periodo > v_disponible then
      raise exception '"%" ya tiene % certificado — quedan % disponibles, se intentó cargar %',
        v_avance.descripcion, round(v_acumulado_previo, 2), v_disponible, v_avance.porcentaje_periodo;
    end if;
  end loop;

  -- Monto real: suma de los snapshots ya calculados por el trigger de la tabla nueva, no el valor
  -- que traiga la fila (que arrancó en 0 y no se tocó desde entonces).
  select coalesce(sum(monto_periodo), 0) into v_monto
  from certificado_subitems_avance
  where certificado_id = p_certificado_id;

  if v_monto <= 0 then
    raise exception 'no se puede emitir un certificado sin avance cargado';
  end if;

  -- Bloqueo de firma física: el certificado anterior de la misma obra, si existe, no puede tener
  -- pendiente su PDF firmado.
  select requiere_firma_fisica, pdf_firmado_subido
    into v_prev_requiere_firma, v_prev_pdf_subido
  from certificados
  where obra_id = v_obra_id and numero = v_numero - 1;

  if v_prev_requiere_firma is true and coalesce(v_prev_pdf_subido, false) = false then
    raise exception 'el certificado anterior (N° %) requiere firma física y todavía no se subió el PDF firmado', v_numero - 1;
  end if;

  select dias_plazo_pago_certificados, anticipo_pct, fondo_reparo_pct
    into v_dias_plazo_pago, v_anticipo_pct, v_fondo_reparo_pct
  from obras
  where id = v_obra_id;

  v_monto_anticipo := round(v_monto * coalesce(v_anticipo_pct, 0) / 100, 2);
  v_monto_fondo_reparo := round(v_monto * coalesce(v_fondo_reparo_pct, 0) / 100, 2);
  v_monto_neto := v_monto - v_monto_anticipo - v_monto_fondo_reparo;

  update certificados
  set estado = 'emitido',
      monto = v_monto,
      fecha_emision = now(),
      emitido_por = auth.uid(),
      dias_plazo_pago = v_dias_plazo_pago,
      requiere_firma_fisica = p_requiere_firma_fisica,
      anticipo_pct_aplicado = v_anticipo_pct,
      fondo_reparo_pct_aplicado = v_fondo_reparo_pct,
      monto_anticipo_descontado = v_monto_anticipo,
      monto_fondo_reparo_retenido = v_monto_fondo_reparo,
      monto_neto_a_pagar = v_monto_neto
  where id = p_certificado_id;

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (
    v_obra_id, auth.uid(), 'emitir_certificado', 'certificado', p_certificado_id,
    jsonb_build_object(
      'numero', v_numero,
      'monto', v_monto,
      'requiere_firma_fisica', p_requiere_firma_fisica,
      'monto_neto_a_pagar', v_monto_neto
    )
  );
end;
$$;

grant execute on function emitir_certificado(uuid, boolean) to authenticated;

-- =====================================================================
-- Verificación
-- =====================================================================

-- 1) La tabla, el trigger y las 4 políticas existen.
select tgname from pg_trigger where tgrelid = 'public.certificado_subitems_avance'::regclass and not tgisinternal;

select policyname, cmd from pg_policies
where schemaname = 'public' and tablename = 'certificado_subitems_avance'
order by cmd;

-- 2) certificados.monto: default y check nuevos.
select column_default from information_schema.columns
where table_schema = 'public' and table_name = 'certificados' and column_name = 'monto';

-- 3) Caso real, con un Borrador de prueba que tenga filas en certificado_subitems_avance: cargar
--    un porcentaje que sumado al acumulado ya emitido supere 100 tiene que fallar recién al
--    llamar a emitir_certificado (no al insertar/actualizar la fila de avance), con el mensaje
--    trayendo el disponible real. Cargar un porcentaje que no se pase tiene que emitir bien, con
--    certificados.monto quedando igual a la suma de monto_periodo de esa tanda.
