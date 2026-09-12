-- Adicionales, Tanda 2: aprobar y rechazar. Diseño y ambigüedades cerradas en
-- docs/adicionales_quitas_demasias_diagnostico.md §13 (diagnóstico) y §13.6 (respuestas de Seba,
-- 2026-09-12) -- este archivo implementa ese documento, no repite el razonamiento salvo donde hace
-- falta para leer el SQL.
--
-- Lo central (§13.6-A): en un adicional presupuestado con la app, congela QUIEN COTIZA, al enviarlo
-- para aprobación -- no el aprobador al aprobar. Palabras de Seba: "es como funciona en obra -- te
-- mandan un presupuesto cerrado, no una hoja de cálculo abierta". Así se congela con las recetas y
-- los precios del que cotizó (la composición de APU se resuelve por auth.uid(), 0072), y el cliente
-- aprueba un número fijo. Para el monto fijo nada cambia respecto de §11.6-D: el monto se recalcula
-- al aprobar.
--
-- Los agujeros que esta migración cierra (§13.1), no solo el del monto cero:
-- - `modificaciones_obra_update` dejaba aprobar un adicional con un UPDATE directo, con autoridad
--   de admin_maestro/profesional (contra §7-B), tope comparado contra monto_total = 0 en un
--   adicional presupuestado pendiente, y monto_total escribible a mano en el mismo UPDATE. Desde
--   acá: ninguna escritura directa sobre una fila de adicional; todas las transiciones por las tres
--   funciones SECURITY DEFINER de abajo, cada una con su propio chequeo de autoridad (mismo
--   criterio que certificados, 0010/0011).
-- - `modificaciones_obra_insert` dejaba insertar un adicional con `obra_hija_id` apuntando a
--   cualquier obra (una real, congelada y certificando). Desde acá solo `crear_adicional_
--   presupuestado` (DEFINER) la setea, y toda función que toca la obra hija valida primero
--   `obras.obra_madre_id = modificaciones_obra.obra_id`.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor), después de 0115. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

-- =====================================================================
-- Paso 1 — modificaciones_obra.enviado_a_aprobacion_en
-- =====================================================================
--
-- Null = en preparación (quien cotiza sigue cargando el cómputo de la obra hija). Seteada = enviado,
-- con `monto_total` ya igual a la suma congelada de la hija. Vive en la fila de la madre a
-- propósito: la pantalla de Adicionales la lee sin tener que entrar a la obra hija, que un aprobador
-- invitado después de crearla puede no ver (lo resuelve también el refresco de equipo del Paso 3,
-- pero la lista no debería depender de eso). Solo tiene sentido en el camino obra hija.
alter table modificaciones_obra
  add column enviado_a_aprobacion_en timestamptz;

alter table modificaciones_obra
  add constraint modificaciones_obra_enviado_check check (
    enviado_a_aprobacion_en is null or (tipo = 'adicional' and obra_hija_id is not null)
  );

-- =====================================================================
-- Paso 2 — autoridad: puede_aprobar_adicional / puede_rechazar_adicional
-- =====================================================================
--
-- `puede_aprobar_monto` (0004) sin las ramas admin_maestro/profesional -- §7-B: "si el profesional
-- o el administrador pueden aprobar un adicional, deja de ser una aprobación del que paga". Sin
-- excepción para una obra sin cliente_principal (§13.6-C): se lo invita, o alguien se suma el rol.
--
-- Delegación del apoderado sin fechas = permanente, vigente -- la regla de la base desde la 0004
-- (misma expresión que `tiene_rol_en_obra`/`puede_aprobar_monto`/0011). Ojo: el helper de Dart
-- `_delegacionVigente` hoy la trata como NO vigente -- divergencia anotada como pendiente aparte
-- (§13.4); el mirror en Dart de estas dos funciones replica esta regla, no reusa el helper.
--
-- Rechazar no mira tope (decisión menor de §13.2, aceptada): decir que no no compromete plata.
-- Aprobar exige `p_monto` no nulo -- nunca se evalúa un tope contra un monto que no se pudo
-- calcular (el mismo tipo de agujero que el monto cero, por otro camino).
create or replace function puede_rechazar_adicional(p_obra_id uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select
    tiene_rol_en_obra(p_obra_id, 'cliente_principal')
    or exists (
      select 1 from obra_members
      where obra_id = p_obra_id and usuario_id = auth.uid() and activo
        and rol = 'invitado_apoderado' and puede_aprobar_adicionales
        and ((delegacion_inicio is null and delegacion_fin is null)
             or now() between delegacion_inicio and delegacion_fin)
    );
$$;

create or replace function puede_aprobar_adicional(p_obra_id uuid, p_monto numeric)
returns boolean language sql security definer set search_path = public stable as $$
  select p_monto is not null and (
    tiene_rol_en_obra(p_obra_id, 'cliente_principal')
    or exists (
      select 1 from obra_members
      where obra_id = p_obra_id and usuario_id = auth.uid() and activo
        and rol = 'invitado_apoderado' and puede_aprobar_adicionales
        and (tope_monto_aprobacion is null or p_monto <= tope_monto_aprobacion)
        and ((delegacion_inicio is null and delegacion_fin is null)
             or now() between delegacion_inicio and delegacion_fin)
    )
  );
$$;

grant execute on function puede_rechazar_adicional(uuid) to authenticated;
revoke execute on function puede_rechazar_adicional(uuid) from public, anon;
grant execute on function puede_aprobar_adicional(uuid, numeric) to authenticated;
revoke execute on function puede_aprobar_adicional(uuid, numeric) from public, anon;

-- =====================================================================
-- Paso 3 — enviar_adicional_a_aprobacion: quien cotiza congela la obra hija
-- =====================================================================
--
-- Reusa `presentar_presupuesto_obra` (0103) + `congelar_presupuesto_obra` (0104) TAL COMO ESTÁN,
-- sobre la obra hija, con la identidad de quien envía -- cero cambios en funciones ya verificadas.
-- Las dos exigen admin_maestro/profesional de la obra que tocan (la hija): son exactamente quienes
-- pueden editar su cómputo (0019), o sea, quienes cotizan. El que creó el adicional ya es
-- admin_maestro de la hija por el bootstrap de 0033, aunque en la madre tenga otro rol.
--
-- Presentar es solo porque congelar lo exige (candado 1 de 0104) -- validez default de 30 días,
-- que después no frena la aprobación (decisión menor de §13.2). `congelar_presupuesto_obra` ya
-- rechaza una hija sin ninguna partida tildada, con su propio mensaje.
--
-- Reenviar (mientras siga pendiente) es llamar esto de nuevo: presentar y congelar ya soportan el
-- reintento (la hija nunca tiene certificados, así que el candado de recongelamiento no la frena),
-- y `monto_total` se pisa con la suma nueva.
--
-- Equipo (§13.6-B): antes de congelar se vuelve a copiar el equipo activo de la madre -- el mismo
-- insert `on conflict do nothing` de la 0113. Sigue siendo una foto, solo que más reciente: un
-- cliente o apoderado invitado a la madre después de crear la hija la puede abrir y ver qué está
-- aprobando. No saca a nadie. Va antes del chequeo de autoridad a propósito: un profesional sumado a
-- la madre después también es alguien que cotiza. Si la autoridad falla, la excepción revierte la
-- copia con todo lo demás.
--
-- Devuelve el monto enviado (la suma congelada), para que la pantalla lo muestre sin otro viaje.
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

  select coalesce(sum(monto_total), 0) into v_monto
  from presupuesto_subitems_congelado
  where obra_id = v_mod.obra_hija_id;

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

-- =====================================================================
-- Paso 4 — aprobar_adicional: monto real primero, tope después
-- =====================================================================
--
-- Orden de los chequeos, a propósito:
-- 1) autoridad SIN tope (`puede_rechazar_adicional`) -- quien no es cliente ni apoderado habilitado
--    recibe "sin autoridad", no un mensaje sobre montos;
-- 2) el monto REAL que va a quedar aprobado:
--    - monto fijo: `calcular_precio_adicional` recalculado ahora, con la config vigente de la madre
--      (§11.6-D, foto al aprobar);
--    - obra hija: exige que se haya enviado, y vuelve a sumar `presupuesto_subitems_congelado` de la
--      hija -- no confía en `monto_total`: si alguien recongeló la hija por fuera de "enviar"
--      (`congelar_presupuesto_obra` sigue siendo llamable por su admin), la suma de hoy es la verdad;
-- 3) `p_monto_visto`: el que el aprobador tenía en pantalla. Si no coincide (reenvío de la hija o
--    cambio de config de la madre en el medio), rechaza -- nadie aprueba un número que no vio
--    (decisión menor de §13.2);
-- 4) recién con ese monto, `puede_aprobar_adicional(obra_id, monto)` -- el tope del apoderado se
--    compara contra el monto real, nunca contra el cero de un adicional en preparación.
--
-- Todo en una transacción: si cualquier chequeo falla, no cambia nada.
--
-- Después de aprobar, la obra hija sigue existiendo y su snapshot podría recongelarse por fuera
-- (ver arriba) -- sin efecto financiero: lo aprobado es `modificaciones_obra.monto_total`, que desde
-- acá no lo toca nadie (política de update, Paso 6).
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

    select sum(monto_total) into v_monto
    from presupuesto_subitems_congelado
    where obra_id = v_mod.obra_hija_id;
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

grant execute on function aprobar_adicional(uuid, numeric, text) to authenticated;
revoke execute on function aprobar_adicional(uuid, numeric, text) from public, anon;

-- =====================================================================
-- Paso 5 — rechazar_adicional
-- =====================================================================
--
-- Sin tope, y también sobre un adicional presupuestado que todavía no se envió -- el cliente puede
-- decir "no sigas con esto" antes de que se termine de cotizar (decisión menor de §13.2). La obra
-- hija queda (historial; se borra con la madre) y no se reenvía: `enviar` exige `pendiente`.
-- Mismos campos que el rechazo de quitas/demasías (`rechazarModificacion`): aprobado_por guarda a
-- quien resolvió, sea para aprobar o rechazar.
create or replace function rechazar_adicional(
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
    raise exception 'sin autoridad para rechazar adicionales en esta obra -- solo el cliente principal o un apoderado habilitado';
  end if;

  update modificaciones_obra
  set estado = 'rechazado',
      aprobado_por = auth.uid(),
      fecha_resolucion = now(),
      comentario_resolucion = p_comentario
  where id = p_modificacion_id;

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (
    v_mod.obra_id, auth.uid(), 'rechazar_adicional', 'modificacion_obra', p_modificacion_id,
    jsonb_build_object(
      'obra_hija_id', v_mod.obra_hija_id,
      'enviado', v_mod.enviado_a_aprobacion_en is not null,
      'comentario', p_comentario
    )
  );
end;
$$;

grant execute on function rechazar_adicional(uuid, text) to authenticated;
revoke execute on function rechazar_adicional(uuid, text) from public, anon;

-- =====================================================================
-- Paso 6 — RLS: ninguna escritura directa sobre una fila de adicional
-- =====================================================================
--
-- UPDATE: `tipo <> 'adicional'` en el using Y en el with check -- ni se toca un adicional, ni se
-- convierte otra fila en adicional. demasia/quita/ajuste_contrato quedan exactamente como en la 0109
-- (mismas tres ramas). La rama `devuelto` también queda excluida para adicionales: su with check
-- (`or subido_por = auth.uid()`) dejaba pasar la fila a cualquier estado, `aprobado` incluido.
drop policy modificaciones_obra_update on modificaciones_obra;

create policy modificaciones_obra_update on modificaciones_obra for update using (
  is_obra_member(obra_id)
  and tipo <> 'adicional'
  and (
    (tipo in ('demasia', 'quita') and puede_aprobar_quita_demasia(obra_id))
    or (tipo not in ('demasia', 'quita') and puede_aprobar_monto(obra_id, monto_total))
    or (estado = 'devuelto' and subido_por = auth.uid())
  )
) with check (
  tipo <> 'adicional'
  and (
    (tipo in ('demasia', 'quita') and puede_aprobar_quita_demasia(obra_id))
    or (tipo not in ('demasia', 'quita') and puede_aprobar_monto(obra_id, monto_total))
    or subido_por = auth.uid()
  )
);

-- INSERT: la política de la 0004 tal cual, más una condición para adicionales -- directo solo el
-- camino de monto fijo (`crearAdicional`, que ya inserta así), en `pendiente`, sin `obra_hija_id` ni
-- `enviado_a_aprobacion_en`. El camino obra hija entra solo por `crear_adicional_presupuestado`
-- (DEFINER). `estado = 'pendiente'` también para adicionales en autogestión (cliente + profesional +
-- constructor la misma persona, que la 0004 dejaba insertar directo en `aprobado`): un adicional
-- aprobado a mano quedaría con el `monto_total` que se tipee, sin la cascada -- aunque sea la misma
-- persona la que paga, se aprueba por `aprobar_adicional` como cualquier otro (dos toques, no un
-- trámite). demasia/quita/ajuste_contrato sin cambios.
drop policy modificaciones_obra_insert on modificaciones_obra;

create policy modificaciones_obra_insert on modificaciones_obra for insert with check (
  is_obra_member(obra_id) and solicitado_por = auth.uid() and subido_por = auth.uid()
  and (
    estado = 'pendiente'
    or (
      estado = 'aprobado' and aprobado_por = auth.uid()
      and tiene_rol_en_obra(obra_id, 'cliente_principal')
      and tiene_rol_en_obra(obra_id, 'profesional')
      and tiene_rol_en_obra(obra_id, 'constructor')
    )
  )
  and (
    tipo <> 'adicional'
    or (estado = 'pendiente' and obra_hija_id is null and enviado_a_aprobacion_en is null)
  )
);

-- =====================================================================
-- Verificación
-- =====================================================================
--
-- Hace falta una obra con dos usuarios reales: A = admin_maestro o profesional (cotiza), B =
-- cliente_principal (aprueba). Para el tope, un tercero C = invitado_apoderado con
-- puede_aprobar_adicionales y un tope chico. Las funciones dependen de auth.uid(): la prueba real
-- es en la app (el SQL Editor corre sin sesión), salvo los chequeos de schema/RLS marcados.
--
-- 1) Camino obra hija, de punta a punta: A crea un adicional presupuestado, tilda partidas en la
--    obra hija, llama enviar_adicional_a_aprobacion -- devuelve la suma; en modificaciones_obra la
--    fila queda con monto_total = esa suma y enviado_a_aprobacion_en seteado; la obra hija queda
--    con presupuesto_congelado_en seteado y sus filas en presupuesto_subitems_congelado.
-- 2) Refresco de equipo: invitar a B a la madre DESPUÉS de crear el adicional; antes de enviar, B no
--    está en obra_members de la hija; después de enviar, sí.
-- 3) B aprueba con el monto que ve: estado 'aprobado', aprobado_por = B, monto_total igual a la
--    suma congelada; fila en audit_log con rol_aprobador = 'cliente_principal'.
-- 4) Monto visto desactualizado: A reenvía después de cambiar una cantidad; B intenta aprobar con el
--    monto viejo -- rechaza con "el monto del adicional cambió"; con el nuevo, aprueba.
-- 5) Tope real: C (tope menor que el monto enviado) intenta aprobar -- rechaza con "supera tu tope",
--    aunque antes de enviar el adicional tuviera monto_total = 0. Con tope mayor, aprueba.
-- 6) Autoridad: A (admin/profesional) intenta aprobar o rechazar -- "sin autoridad" (§7-B). B
--    intenta enviar -- "solo quien cotiza..." (salvo que B tenga además admin/profesional).
-- 7) Aprobar sin enviar: rechaza con "todavía no fue enviado". Rechazar sin enviar: funciona.
-- 8) Monto fijo: crear uno (Tanda 1), B lo aprueba con el monto que ve -- estado 'aprobado',
--    monto_total = calcular_precio_adicional con la config de la madre de ese momento.
-- 9) RLS, desde la app o con un usuario autenticado: un UPDATE directo sobre una fila de adicional
--    (cualquier columna, cualquier usuario, incluido B) no afecta ninguna fila; un INSERT directo de
--    un adicional con obra_hija_id, o con estado 'aprobado', rechaza. Quitas/demasías siguen
--    aprobándose y rechazándose como antes (misma pantalla, sin cambios).
-- 10) Schema (SQL Editor): el check nuevo rechaza enviado_a_aprobacion_en en un adicional de monto
--     fijo o en una quita; las 5 funciones nuevas con anon_puede = false (consulta de la 0115,
--     verificación 2).
