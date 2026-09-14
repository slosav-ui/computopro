-- 0131 -- El plazo de la objeción: se levanta sola a los 5 días, y consta que fue por vencimiento
--
-- Pedido de Seba (2026-09-14), al verificar la tanda 3 con tres usuarios. Diseño completo y las
-- 8 ambigüedades con sus respuestas: docs/certificacion_acuerdo_partes_diagnostico.md §5.2.
--
-- QUÉ RESUELVE, textual: **"si el técnico responde y el cliente no levanta, el certificado queda
-- trabado para siempre. Y el plazo de pago es de cinco días, así que una objeción abierta quince lo
-- convierte en letra muerta."** A los 2 días de la respuesta se le avisa al cliente que la objeción
-- se va a resolver sola; a los 5, se levanta.
--
-- LA CONDICIÓN QUE ORDENA TODA LA MIGRACIÓN, y es la razón de que haya un cuarto estado en vez de
-- reusar `aclarada`: **tiene que constar que se levantó por vencimiento, no porque el cliente la
-- aceptó**. Textual de Seba: *"hacer constar una conformidad que no existió sería peor que la
-- demora, y en un documento que puede terminar en una discusión formal eso importa"*. Es el mismo
-- principio que ordena la pieza entera -- la conformidad la da alguien, no se deduce -- aplicado al
-- final del recorrido: un certificado cuya objeción venció es un certificado **pagable**, no un
-- certificado **conformado**.
--
-- Y la constancia no necesita ninguna columna nueva: **`aclarada` la escribe un humano y deja
-- `objecion_resuelta_por` cargado; `vencida` lo deja en NULL**. "No la levantó nadie" queda dicho por
-- ausencia de firmante, que es la forma más fuerte de decirlo -- y el check del paso 2 lo vuelve
-- imposible de falsear en el otro sentido.
--
-- POR QUÉ NO ALCANZABA LA SALIDA QUE YA HABÍA. La `0129` contestaba "¿y si no la levanta nunca?" con
-- la anulación: el lado técnico puede anular y emitir corregido sin pedir permiso. Sigue siendo
-- cierto, pero no sirve acá: la anulación es para cuando la objeción **tenía razón**. Si ya fue
-- respondida y nadie sostiene que el certificado esté mal, anularlo es tirar abajo el documento,
-- renumerar la versión y rehacer el circuito completo de las dos partes técnicas para resolver que
-- alguien no abrió la app.
--
-- LAS RESPUESTAS DE SEBA QUE DEFINIERON LA FORMA (§5.2):
--
--   * **Son dos relojes distintos.** El de la objeción corre **por tiempo total desde la respuesta,
--     sin pausas**. El del pago **se congela mientras hay una objeción abierta** -- ver el paso 8:
--     no hace falta escribir nada para eso, ya está todo guardado.
--   * **5 días fijos, NO `dias_plazo_pago_certificados`**: *"el plazo de pago es cuánto tarda en
--     pagarse el certificado; este es cuánto tiempo tenés para sostener una objeción. Si alguien
--     pacta pago a treinta días, no corresponde que una objeción viva treinta."*
--   * **La objeción sin responder NO vence**: *"si el técnico no responde, el certificado frenado lo
--     tiene él"*. El silencio del que debe responder no puede beneficiar al que debe cobrar -- si
--     venciera, al lado técnico le convendría no contestar nunca.
--   * **No se puede volver a objetar por el mismo motivo** (o el plazo queda decorativo), pero sí
--     por algo nuevo -- paso 6, con el límite que la base sí puede sostener escrito ahí.
--   * **`audit_log.usuario_id` pasa a nullable**: un vencimiento no lo hizo nadie, y anotarlo a
--     nombre del que pasaba por ahí sería exactamente la falsedad que esta migración evita.
--
-- CÓMO "PASA SOLO" SIN UN JOB: el proyecto no tiene `pg_cron` ni ningún scheduler, y no se agrega
-- uno. **El vencimiento se calcula al leer y se materializa al tocar**, igual que
-- `proximo_periodo_certificacion` (0123). Todo lo que decide algo pregunta por `objecion_vigente()`
-- (paso 4), así que el efecto es correcto desde el segundo en que vence, mire quien mire; la fila
-- se pasa a `vencida` cuando alguien la toca, y **con la fecha del vencimiento real, no la de la
-- materialización** (paso 5) -- el documento no miente aunque nadie abra la app en dos semanas.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project -> SQL Editor), después de `0130`. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.


-- =====================================================================
-- Paso 1 -- `vencida`, el cuarto valor
-- =====================================================================
--
-- El check de `objecion_estado` nació inline en la `0129` (`add column ... check (...)`), así que
-- Postgres le puso el nombre `certificados_objecion_estado_check`. Se reemplaza entero.

alter table certificados drop constraint certificados_objecion_estado_check;

alter table certificados add constraint certificados_objecion_estado_check
  check (objecion_estado is null
    or objecion_estado in ('abierta', 'aclarada', 'aceptada', 'vencida'));

comment on column certificados.objecion_estado is
  'Eje de la objecion del cliente (0129, 0131): abierta | aclarada | aceptada | vencida. NO es el '
  'estado del certificado (certificados.estado), que sigue emitido/leido mientras se discute. Frena '
  'el pago solo mientras objecion_vigente() da true; leer sigue permitido siempre. vencida = se '
  'levanto sola a los 5 dias de la respuesta, sin que el cliente la levantara: objecion_resuelta_por '
  'queda NULL a proposito, es la constancia de que no la cerro ninguna persona.';


-- =====================================================================
-- Paso 2 -- el check del cierre: quién firma cada final
-- =====================================================================
--
-- Acá vive la garantía de que un vencimiento no se pueda disfrazar de conformidad. Hoy el check
-- exige firmante para todo cierre; pasa a exigir **firmante en `aclarada`/`aceptada`** y **ausencia
-- de firmante en `vencida`**. Las dos direcciones: no se puede vencer una objeción "a nombre de"
-- alguien, y no se puede aclarar una sin que conste quién la aclaró.

alter table certificados drop constraint certificados_objecion_cierre_check;

alter table certificados add constraint certificados_objecion_cierre_check
  check (
    objecion_estado is null
    or objecion_estado = 'abierta'
    or (objecion_estado in ('aclarada', 'aceptada')
        and objecion_resuelta_por is not null
        and objecion_resuelta_fecha is not null)
    or (objecion_estado = 'vencida'
        and objecion_resuelta_por is null
        and objecion_resuelta_fecha is not null)
  );


-- =====================================================================
-- Paso 3 -- el plazo, en un solo lugar
-- =====================================================================
--
-- Los 5 días viven acá y en ningún otro lado: lo usan el predicado del paso 4, la materialización
-- del paso 5, la rama del aviso en `mis_pendientes()` y la pantalla de detalle (por RPC, para no
-- copiar el número en Dart -- el precedente de qué pasa cuando se copia una regla al cliente está
-- en la delegación, `docs/adicionales_quitas_demasias_diagnostico.md` §13.4).
--
-- `stable` y no `immutable`: `timestamptz + interval '5 days'` depende del huso horario de la
-- sesión, así que no califica como inmutable aunque parezca constante.
--
-- Días corridos, no hábiles: es lo que significa "por tiempo total, sin pausas", y días hábiles
-- necesitaría un calendario de feriados de Argentina que el proyecto no tiene. Lo que compensa es
-- que la UI muestra **la fecha exacta** en que se resuelve sola, no un contador de días.

create or replace function objecion_vence_el(p_respondida_fecha timestamptz)
returns timestamptz language sql stable set search_path = public as $$
  select p_respondida_fecha + interval '5 days';
$$;

grant execute on function objecion_vence_el(timestamptz) to authenticated;
revoke execute on function objecion_vence_el(timestamptz) from public, anon;

-- Y el otro número de la misma decisión: a los 2 días se le avisa al cliente que esto se resuelve
-- solo. Vive acá por el mismo motivo que el de arriba -- **los dos plazos se deciden en la base**.
-- El Dart no sabe ni el 2 ni el 5: `mis_pendientes()` le manda `vence` recién cuando el aviso
-- corresponde (paso 9), así que la regla "avisar a los 2 días" no se puede desincronizar entre la
-- función y la pantalla, porque está escrita una sola vez.

create or replace function objecion_avisa_el(p_respondida_fecha timestamptz)
returns timestamptz language sql stable set search_path = public as $$
  select p_respondida_fecha + interval '2 days';
$$;

grant execute on function objecion_avisa_el(timestamptz) to authenticated;
revoke execute on function objecion_avisa_el(timestamptz) from public, anon;


-- =====================================================================
-- Paso 4 -- objecion_vigente: la única definición de "esto todavía frena"
-- =====================================================================
--
-- Toma los dos valores, no el id: así `mis_pendientes()` la puede llamar por fila sin volver a
-- buscar el certificado que ya tiene en la mano.
--
-- **Sin respuesta no hay plazo**, y es la decisión de Seba, no un descuido: si la objeción que el
-- técnico no contestó venciera sola, no contestar sería la mejor estrategia para cobrar.

create or replace function objecion_vigente(p_objecion_estado text, p_respondida_fecha timestamptz)
returns boolean language sql stable set search_path = public as $$
  select p_objecion_estado = 'abierta'
     and (p_respondida_fecha is null or now() < objecion_vence_el(p_respondida_fecha));
$$;

grant execute on function objecion_vigente(text, timestamptz) to authenticated;
revoke execute on function objecion_vigente(text, timestamptz) from public, anon;


-- =====================================================================
-- Paso 5 -- audit_log sin autor, y la materialización
-- =====================================================================
--
-- `usuario_id` pasa a nullable **solo para esto**: NULL = lo hizo el sistema, y de ahora en más hay
-- dónde anotar cualquier hecho automático sin ponerle la firma de una persona. Las dos políticas de
-- la `0004`/`0121` aguantan sin cambios: la de SELECT deja ver la fila por la rama de `obra_id`
-- (nadie pierde visibilidad), y la de INSERT exige `usuario_id = auth.uid()`, que sigue valiendo
-- para todo lo que inserta un usuario -- las filas del sistema entran desde funciones
-- `security definer`, que corren como dueñas de la tabla y no pasan por RLS.
--
-- El audit_log sigue siendo inalterable: no se agrega UPDATE ni DELETE para nadie.

alter table audit_log alter column usuario_id drop not null;

comment on column audit_log.usuario_id is
  'Quien hizo la accion. NULL = el sistema, no una persona (0131): hoy solo lo escribe el '
  'vencimiento automatico de una objecion. Anotar un hecho sin autor a nombre de quien lo disparo '
  'seria falsear el rastro.';

-- Materializa el vencimiento de UNA objeción, si corresponde. No decide nada que no esté ya
-- decidido por `objecion_vigente()`: solo escribe en la fila lo que el predicado ya dice.
--
-- **La fecha que se escribe es la del vencimiento real** (`respuesta + 5 días`), no `now()`. Si
-- nadie abrió la app en dos semanas, el certificado tiene que decir que la objeción se levantó el
-- día que se levantó, no el día en que alguien pasó por ahí.
--
-- Idempotente y sin autoridad propia: la puede llamar cualquier miembro de la obra, porque no es el
-- acto de voluntad de nadie -- es el reloj. Si no hay nada que vencer, no hace nada.

create or replace function vencer_objecion_si_corresponde(p_certificado_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_obra_id uuid;
  v_objecion_estado text;
  v_respondida_fecha timestamptz;
  v_vencio_el timestamptz;
begin
  select obra_id, objecion_estado, objecion_respondida_fecha
    into v_obra_id, v_objecion_estado, v_respondida_fecha
  from certificados
  where id = p_certificado_id;

  if v_obra_id is null or not is_obra_member(v_obra_id) then
    return;
  end if;

  if v_objecion_estado <> 'abierta' or v_respondida_fecha is null then
    return;
  end if;

  if objecion_vigente(v_objecion_estado, v_respondida_fecha) then
    return;
  end if;

  v_vencio_el := objecion_vence_el(v_respondida_fecha);

  update certificados
  set objecion_estado = 'vencida',
      objecion_resuelta_fecha = v_vencio_el,
      objecion_resuelta_por = null
  where id = p_certificado_id
    and objecion_estado = 'abierta';

  if not found then
    return;
  end if;

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (
    v_obra_id, null, 'vencer_objecion_certificado', 'certificado', p_certificado_id,
    jsonb_build_object(
      'respondida_fecha', v_respondida_fecha,
      'vencio_el', v_vencio_el,
      'materializado_el', now(),
      'materializado_por', auth.uid(),
      'motivo', 'el cliente no levanto la objecion dentro del plazo'
    )
  );
end;
$$;

grant execute on function vencer_objecion_si_corresponde(uuid) to authenticated;
revoke execute on function vencer_objecion_si_corresponde(uuid) from public, anon;


-- =====================================================================
-- Paso 6 -- objetar_certificado: no dos veces por lo mismo
-- =====================================================================
--
-- Cuerpo vigente de la `0129` con **un guard nuevo y nada más**. Sin él, el plazo sería decorativo:
-- vencida la objeción, el cliente vuelve a plantear la misma el día 6 y frena el pago otros cinco
-- días, y otra vez, sin techo.
--
-- LO QUE LA BASE PUEDE SOSTENER, dicho sin exagerar: comparar **textos**, no intenciones. El guard
-- rechaza un fundamento que ya se presentó antes en este certificado (normalizado: sin mayúsculas ni
-- diferencias de espaciado), y los fundamentos anteriores salen de `audit_log`, que es donde ya
-- quedaban. Una objeción nueva **de verdad** -- algo que no estaba antes, que es lo que Seba dejó
-- expresamente habilitado -- pasa sin problema.
--
-- LÍMITE CONOCIDO Y ACEPTADO: alguien decidido a estirar el pago puede reescribir el mismo reclamo
-- con otras palabras. No se puede cerrar desde la base, y cerrarlo a lo bruto (una sola objeción por
-- certificado y listo) le sacaría al cliente el derecho a plantear un problema real que aparece
-- después. Lo que sí queda: cada vuelta cuesta una respuesta del técnico (que reinicia el reloj de 5
-- días) y **todas quedan en `audit_log`, una al lado de la otra**, que es exactamente lo que hace
-- falta si la discusión termina siendo formal.

create or replace function objetar_certificado(
  p_certificado_id uuid,
  p_fundamento text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_obra_id uuid;
  v_estado text;
  v_objecion_estado text;
begin
  select obra_id, estado, objecion_estado
    into v_obra_id, v_estado, v_objecion_estado
  from certificados
  where id = p_certificado_id;

  if v_obra_id is null then
    raise exception 'certificado % no encontrado', p_certificado_id;
  end if;

  if not (tiene_rol_en_obra(v_obra_id, 'cliente_principal')
       or tiene_rol_en_obra(v_obra_id, 'invitado_apoderado')) then
    raise exception 'la objeción la plantea quien recibe el certificado: el cliente o su apoderado';
  end if;

  if v_estado not in ('emitido', 'leido') then
    raise exception 'un certificado % no se objeta — si ya se pagó y hay un error, el camino es la anulación', v_estado;
  end if;

  -- Una objeción cuyo plazo ya venció no bloquea la siguiente, pero **tiene que quedar asentada
  -- antes de que la nueva la pise**: el `update` de más abajo limpia las columnas de la anterior,
  -- así que si no se materializa acá, esa objeción se iría sin dejar en `audit_log` que venció. Es
  -- la fila del audit lo que se está salvando, no las columnas -- el historial de cada vuelta vive
  -- ahí desde la 0129.
  perform vencer_objecion_si_corresponde(p_certificado_id);
  select objecion_estado into v_objecion_estado from certificados where id = p_certificado_id;

  if v_objecion_estado = 'abierta' then
    raise exception 'este certificado ya tiene una objeción abierta';
  end if;

  if p_fundamento is null or btrim(p_fundamento) = '' then
    raise exception 'la objeción necesita un fundamento: sin decir qué está mal, no hay nada que responder';
  end if;

  -- 0131: el mismo motivo, no dos veces. Los fundamentos anteriores de ESTE certificado están en
  -- audit_log desde la 0129.
  if exists (
    select 1 from audit_log a
    where a.entidad = 'certificado'
      and a.entidad_id = p_certificado_id
      and a.accion = 'objetar_certificado'
      and lower(regexp_replace(btrim(a.detalle ->> 'fundamento'), '\s+', ' ', 'g'))
        = lower(regexp_replace(btrim(p_fundamento), '\s+', ' ', 'g'))
  ) then
    raise exception 'esta objeción ya se planteó sobre este certificado y su plazo se cumplió — si hay algo nuevo, plantealo; si es lo mismo, el camino es pedir la anulación';
  end if;

  update certificados
  set objecion_estado = 'abierta',
      objecion_fundamento = p_fundamento,
      objecion_por = auth.uid(),
      objecion_fecha = now(),
      objecion_respuesta = null,
      objecion_respondida_por = null,
      objecion_respondida_fecha = null,
      objecion_resuelta_por = null,
      objecion_resuelta_fecha = null
  where id = p_certificado_id;

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (
    v_obra_id, auth.uid(), 'objetar_certificado', 'certificado', p_certificado_id,
    jsonb_build_object('fundamento', p_fundamento)
  );
end;
$$;

grant execute on function objetar_certificado(uuid, text) to authenticated;
revoke execute on function objetar_certificado(uuid, text) from public, anon;


-- =====================================================================
-- Paso 7 -- marcar_certificado_pagado: el freno, ahora con plazo
-- =====================================================================
--
-- Cuerpo vigente de la `0129` con **dos cambios**: materializa el vencimiento antes de decidir, y el
-- guard pregunta por `objecion_vigente()` en vez de comparar con el literal `'abierta'`. Sigue
-- siendo el mismo único punto donde la objeción frena el pago.

create or replace function marcar_certificado_pagado(
  p_certificado_id uuid,
  p_medio_pago text,
  p_comprobante_adjuntos text[] default '{}'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_obra_id uuid;
  v_estado text;
  v_monto numeric;
  v_fecha_lectura timestamptz;
  v_lectura_automatica boolean := false;
  v_objecion_estado text;
  v_objecion_respondida_fecha timestamptz;
begin
  -- 0131: si la objeción ya venció, que la fila lo diga antes de que este pago se registre. Así el
  -- certificado no queda pagado con una objeción figurando como abierta.
  perform vencer_objecion_si_corresponde(p_certificado_id);

  select obra_id, estado, monto, fecha_lectura, objecion_estado, objecion_respondida_fecha
    into v_obra_id, v_estado, v_monto, v_fecha_lectura, v_objecion_estado, v_objecion_respondida_fecha
  from certificados
  where id = p_certificado_id;

  if v_obra_id is null then
    raise exception 'certificado % no encontrado', p_certificado_id;
  end if;

  if v_estado not in ('emitido', 'leido') then
    raise exception 'certificado % no está en condiciones de pagarse (estado actual: %)', p_certificado_id, v_estado;
  end if;

  -- Objeción del cliente (0129), con plazo desde la 0131: "el cliente no debe pagar si tiene dudas",
  -- pero la duda que ya fue respondida y no se sostuvo en 5 días deja de frenar.
  if objecion_vigente(v_objecion_estado, v_objecion_respondida_fecha) then
    raise exception 'este certificado tiene una objeción abierta: se levanta la objeción, o se corrige el certificado, antes de pagarlo';
  end if;

  if not puede_gestionar_certificado(v_obra_id, v_monto) then
    raise exception 'sin autoridad de aprobación para pagar este certificado';
  end if;

  if v_fecha_lectura is null then
    v_lectura_automatica := true;
  end if;

  update certificados
  set estado = 'pagado',
      fecha_pago = now(),
      pagado_por = auth.uid(),
      medio_pago = p_medio_pago,
      comprobante_pago_adjuntos = p_comprobante_adjuntos,
      fecha_lectura = coalesce(fecha_lectura, now()),
      leido_por = coalesce(leido_por, auth.uid())
  where id = p_certificado_id;

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (
    v_obra_id, auth.uid(), 'marcar_certificado_pagado', 'certificado', p_certificado_id,
    jsonb_build_object('medio_pago', p_medio_pago, 'lectura_automatica', v_lectura_automatica)
  );
end;
$$;

grant execute on function marcar_certificado_pagado(uuid, text, text[]) to authenticated;


-- =====================================================================
-- Paso 8 -- el otro reloj: el plazo de pago, congelado. Sin escribir nada.
-- =====================================================================
--
-- Decisión de Seba: **el plazo de pago se congela mientras hay una objeción abierta** -- si no, la
-- objeción se come el plazo y el pago nace vencido el día que se destraba.
--
-- No hay nada que construir, y conviene que quede dicho para que nadie agregue una columna al
-- pedo: hoy `certificados.dias_plazo_pago` **solo se muestra**. No dispara ningún aviso, ningún
-- cálculo y ninguna transición -- no existe todavía el reloj de pago que habría que congelar. Y
-- cuando exista, los días frenados ya están guardados y son una resta: `objecion_fecha` y
-- `objecion_resuelta_fecha` están en la fila, en las cuatro salidas posibles (aclarada, aceptada,
-- vencida, o abierta y todavía corriendo).
--
-- O sea: la decisión está tomada y el dato para aplicarla está completo. Lo único que falta es el
-- aviso de "certificado por vencer", que no es de esta tanda.


-- =====================================================================
-- Paso 9 -- mis_pendientes(): el aviso de los 2 días, y dos ramas más
-- =====================================================================
--
-- Cuerpo vigente de la `0130` con cuatro cambios, y ninguna otra línea:
--
--   1. **Una columna más en la firma: `vence`.** El aviso tiene que decir la fecha exacta en que la
--      objeción se resuelve sola, y esa fecha la calcula la base -- copiar los 5 días al Dart sería
--      repetir la regla en dos lugares. Null en todas las ramas que no tienen plazo. Agregar una
--      columna a un `returns table` obliga a **borrar la función primero**: `create or replace` no
--      puede cambiar el tipo de retorno. Nada depende de ella salvo el RPC del dashboard.
--   2. `certificado_leido` (el pedido de pago) y las dos de objeción pasan a preguntar por
--      `objecion_vigente()`, así el pedido de pago **reaparece solo** en cuanto el plazo se cumple,
--      sin esperar a que nadie materialice nada.
--   3. **`objecion_respondida` no se parte en dos.** El aviso de los 2 días es el mismo ítem con
--      otro texto (`vence` ya viaja en la fila y el Dart decide cómo decirlo): dos ítems distintos
--      por el mismo certificado sería contarle dos veces lo mismo al cliente.
--   4. **`certificado_devuelto`**, la rama que faltaba del mismo origen que la `0130`: el borrador
--      que la contraparte devolvió con un comentario, esperando a quien propuso. No choca con "lo
--      que está en preparación no figura" (§4-D del diseño de avisos): un borrador que te
--      devolvieron **no es trabajo que elegiste tener abierto**, es una respuesta que te esperan.
--      Va solo a `propuesto_por`, que la `0124` no borra al devolver -- justamente para esto.

drop function if exists mis_pendientes();

create function mis_pendientes()
returns table(
  obra_id uuid,
  obra_nombre text,
  tipo text,                -- adicional | quita | demasia | certificado_emitido | certificado_leido
                            -- | certificado_pagado | anulacion | firma_fisica | certificacion_periodo
                            -- | certificado_propuesto | certificado_sin_reemplazo
                            -- | certificado_objetado | objecion_respondida
                            -- | certificado_conforme | certificado_devuelto
  entidad_id uuid,
  descripcion text,
  certificado_numero int,
  certificado_version int,
  desde timestamptz,
  -- 0131: cuando esto se resuelve solo. Hoy lo llena UNA sola rama, `objecion_respondida`, y
  -- **recien pasados los 2 dias del aviso**: null antes de eso y null en todas las demas ramas,
  -- que no tienen plazo. O sea que "hay fecha" y "hay que avisar" son la misma cosa del lado del
  -- Dart, y los dos numeros (2 y 5) viven solo aca.
  vence timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  with mis_obras as (
    select distinct o.id, o.nombre
    from obras o
    join obra_members om on om.obra_id = o.id
    where om.usuario_id = auth.uid() and om.activo and o.obra_madre_id is null
  )
  select mo.id as obra_id, mo.nombre as obra_nombre, 'adicional'::text as tipo, m.id as entidad_id,
         m.descripcion as descripcion, null::int as certificado_numero, null::int as certificado_version,
         coalesce(m.enviado_a_aprobacion_en, m.fecha_solicitud) as desde, null::timestamptz as vence
  from modificaciones_obra m
  join mis_obras mo on mo.id = m.obra_id
  where m.tipo = 'adicional'
    and m.estado = 'pendiente'
    and (m.obra_hija_id is null or m.enviado_a_aprobacion_en is not null)
    and puede_aprobar_adicional(m.obra_id, m.monto_total)

  union all

  select mo.id, mo.nombre, m.tipo, m.id, m.descripcion, null::int, null::int, m.fecha_solicitud, null::timestamptz
  from modificaciones_obra m
  join mis_obras mo on mo.id = m.obra_id
  where m.tipo in ('quita', 'demasia')
    and m.estado = 'pendiente'
    and puede_aprobar_quita_demasia(m.obra_id)
    and (
      m.solicitado_por <> auth.uid()
      or not exists (
        select 1 from obra_members otro
        where otro.obra_id = m.obra_id and otro.activo
          and otro.rol in ('profesional', 'constructor')
          and otro.usuario_id <> auth.uid()
      )
    )

  union all

  select mo.id, mo.nombre, 'certificado_emitido'::text, c.id, c.periodo, c.numero, c.version, c.fecha_emision, null::timestamptz
  from certificados c
  join mis_obras mo on mo.id = c.obra_id
  where c.estado = 'emitido'
    and (tiene_rol_en_obra(c.obra_id, 'cliente_principal') or tiene_rol_en_obra(c.obra_id, 'invitado_apoderado'))

  union all

  select mo.id, mo.nombre, 'certificado_leido'::text, c.id, c.periodo, c.numero, c.version, c.fecha_lectura, null::timestamptz
  from certificados c
  join mis_obras mo on mo.id = c.obra_id
  where c.estado = 'leido'
    and puede_gestionar_certificado(c.obra_id, c.monto)
    -- 0129: con una objeción abierta el pago está frenado, así que pedirlo sería ofrecer algo que la
    -- base rechaza. El pendiente que corresponde ahí es `objecion_respondida`, más abajo.
    -- 0131: "abierta" ya no alcanza -- una objeción respondida que nadie sostuvo en 5 días dejó de
    -- frenar, y el pedido de pago tiene que reaparecer solo, sin esperar a que nadie la materialice.
    and not objecion_vigente(c.objecion_estado, c.objecion_respondida_fecha)

  union all

  select mo.id, mo.nombre, 'certificado_pagado'::text, c.id, c.periodo, c.numero, c.version, c.fecha_pago, null::timestamptz
  from certificados c
  join mis_obras mo on mo.id = c.obra_id
  where c.estado = 'pagado'
    and (tiene_rol_en_obra(c.obra_id, 'admin_maestro') or tiene_rol_en_obra(c.obra_id, 'constructor'))

  union all

  select mo.id, mo.nombre, 'anulacion'::text, c.id, c.periodo, c.numero, c.version, c.anulacion_propuesta_fecha, null::timestamptz
  from certificados c
  join mis_obras mo on mo.id = c.obra_id
  where c.anulacion_estado = 'propuesta'
    and (tiene_rol_en_obra(c.obra_id, 'profesional') or tiene_rol_en_obra(c.obra_id, 'constructor'))
    and c.anulacion_propuesta_por <> auth.uid()

  union all

  select mo.id, mo.nombre, 'firma_fisica'::text, c.id, c.periodo, c.numero, c.version, c.fecha_emision, null::timestamptz
  from certificados c
  join mis_obras mo on mo.id = c.obra_id
  where c.requiere_firma_fisica = true
    and c.pdf_firmado_subido = false
    and c.estado not in ('borrador', 'anulado')
    and (tiene_rol_en_obra(c.obra_id, 'admin_maestro') or tiene_rol_en_obra(c.obra_id, 'profesional'))

  union all

  select mo.id, mo.nombre, 'certificacion_periodo'::text, null::uuid,
         o.periodicidad_certificacion, null::int, null::int, p.vence, null::timestamptz
  from obras o
  join mis_obras mo on mo.id = o.id
  cross join lateral proximo_periodo_certificacion(o.id) as p(vence)
  where o.periodicidad_certificacion is not null
    and o.modelo_certificacion = 'avance_medido'
    and o.presupuesto_congelado_en is not null
    and p.vence is not null
    and p.vence <= now()
    and not exists (
      select 1 from certificados c where c.obra_id = o.id and c.estado = 'borrador'
    )
    and (tiene_rol_en_obra(o.id, 'admin_maestro')
      or tiene_rol_en_obra(o.id, 'profesional')
      or tiene_rol_en_obra(o.id, 'constructor'))

  union all

  select mo.id, mo.nombre, 'certificado_propuesto'::text, c.id, c.periodo, c.numero, c.version,
         c.propuesta_fecha, null::timestamptz
  from certificados c
  join mis_obras mo on mo.id = c.obra_id
  where c.estado = 'borrador'
    and c.acuerdo_estado = 'propuesto'
    and puede_dar_conformidad_certificado(c.id)

  union all

  select mo.id, mo.nombre, 'certificado_sin_reemplazo'::text, c.id, c.periodo, c.numero, c.version,
         c.anulacion_resuelta_fecha, null::timestamptz
  from certificados c
  join mis_obras mo on mo.id = c.obra_id
  where c.estado = 'anulado'
    and falta_reemplazo_certificado(c.id)
    and (tiene_rol_en_obra(c.obra_id, 'admin_maestro')
      or tiene_rol_en_obra(c.obra_id, 'profesional')
      or tiene_rol_en_obra(c.obra_id, 'constructor'))

  union all

  -- Objeción del cliente (0129), ida: al lado técnico, mientras no haya respuesta. Mismo conjunto
  -- que `responder_objecion_certificado`.
  select mo.id, mo.nombre, 'certificado_objetado'::text, c.id, c.periodo, c.numero, c.version,
         c.objecion_fecha, null::timestamptz
  from certificados c
  join mis_obras mo on mo.id = c.obra_id
  where objecion_vigente(c.objecion_estado, c.objecion_respondida_fecha)
    and c.objecion_respuesta is null
    and (tiene_rol_en_obra(c.obra_id, 'profesional')
      or tiene_rol_en_obra(c.obra_id, 'constructor')
      or tiene_rol_en_obra(c.obra_id, 'admin_maestro'))

  union all

  -- Y la vuelta: al cliente, cuando ya le respondieron y la objeción sigue abierta. Le toca a él
  -- leer la aclaración y levantar la objeción, o dejarla planteada.
  select mo.id, mo.nombre, 'objecion_respondida'::text, c.id, c.periodo, c.numero, c.version,
         c.objecion_respondida_fecha,
         -- El aviso de los 2 días: hasta ahí el pendiente dice "revisá la respuesta" y nada más;
         -- desde ahí viaja la fecha, y el cartel agrega que se resuelve sola ese día. Los dos
         -- plazos quedan del lado de la base -- ver el paso 3.
         case when now() >= objecion_avisa_el(c.objecion_respondida_fecha)
              then objecion_vence_el(c.objecion_respondida_fecha) end
  from certificados c
  join mis_obras mo on mo.id = c.obra_id
  where objecion_vigente(c.objecion_estado, c.objecion_respondida_fecha)
    and c.objecion_respuesta is not null
    and (tiene_rol_en_obra(c.obra_id, 'cliente_principal')
      or tiene_rol_en_obra(c.obra_id, 'invitado_apoderado'))

  union all

  -- 0130: el borrador ya conformado que todavía nadie emitió. Va a quien emite en esta obra según la
  -- escalera de la 0125 (profesional -> cliente -> admin_maestro), que es la misma autoridad que
  -- ejecuta `emitir_certificado`. `desde` = conforme_fecha: la espera empieza con el acuerdo, no con
  -- la creación del borrador.
  select mo.id, mo.nombre, 'certificado_conforme'::text, c.id, c.periodo, c.numero, c.version,
         c.conforme_fecha, null::timestamptz
  from certificados c
  join mis_obras mo on mo.id = c.obra_id
  where c.estado = 'borrador'
    and c.acuerdo_estado = 'conforme'
    and puede_emitir_certificado(c.obra_id)

  union all

  -- 0131: el borrador que la contraparte devolvió con un comentario (`devolver_avance_certificado`,
  -- 0124) y todavía nadie volvió a proponer. Va SOLO a quien propuso -- `propuesto_por` sobrevive a
  -- la devolución justamente para esto -- y no a los otros dos roles técnicos que también podrían
  -- editar el borrador: la respuesta se la piden a él.
  --
  -- `desde` = `propuesta_fecha` y no la fecha de la devolución, que **no existe como columna**: la
  -- 0124 guardó el comentario y no el momento. Queda un poco antes de cuando la espera empezó de
  -- verdad, y solo afecta el orden del cartel. Si algún día molesta, es una columna
  -- `devolucion_fecha` y una línea en `devolver_avance_certificado` -- no se agrega ahora porque
  -- esta migración ya toca bastante.
  select mo.id, mo.nombre, 'certificado_devuelto'::text, c.id, c.periodo, c.numero, c.version,
         c.propuesta_fecha, null::timestamptz
  from certificados c
  join mis_obras mo on mo.id = c.obra_id
  where c.estado = 'borrador'
    and c.acuerdo_estado = 'en_carga'
    and c.comentario_devolucion is not null
    and c.propuesto_por = auth.uid()

  order by 8;
$$;

grant execute on function mis_pendientes() to authenticated;
revoke execute on function mis_pendientes() from public, anon;


-- =====================================================================
-- Verificación a mano después de aplicar
-- =====================================================================
--
-- 0) Que no se perdió ninguna rama al reescribir la función entera:
--
--    select
--      prosrc like '%certificado_devuelto%'      as rama_0131,
--      prosrc like '%certificado_conforme%'      as rama_0130,
--      prosrc like '%certificado_objetado%'      as ramas_0129,
--      prosrc like '%certificado_sin_reemplazo%' as rama_0126,
--      prosrc like '%certificado_propuesto%'     as rama_0124,
--      prosrc like '%certificacion_periodo%'     as rama_0123
--    from pg_proc where proname = 'mis_pendientes';
--    -- las seis en true. Y que la firma tenga 9 columnas:
--    select pg_get_function_result(oid) from pg_proc where proname = 'mis_pendientes';
--
-- 1) El plazo, sin esperar cinco días. Los relojes se prueban moviendo el ancla, no esperando --
--    misma lección que dejó la Tanda 1 con `proximo_periodo_certificacion`. Con una objeción
--    respondida y abierta:
--
--    update certificados set objecion_respondida_fecha = now() - interval '3 days' where id = '<cert>';
--    -- a los 3 días: sigue abierta, el pago sigue frenado, y el cliente ya tiene el aviso de que
--    -- se resuelve sola (pasaron los 2 días).
--    update certificados set objecion_respondida_fecha = now() - interval '6 days' where id = '<cert>';
--    -- a los 6: el pago YA no está frenado aunque la fila todavía diga 'abierta' -- eso es lo que
--    -- significa "se calcula al leer". Y `mis_pendientes()` del cliente ya no muestra
--    -- 'objecion_respondida' sino que le vuelve a aparecer el pedido de pago a quien paga.
--
--    select objecion_vigente(objecion_estado, objecion_respondida_fecha),
--           objecion_vence_el(objecion_respondida_fecha)
--    from certificados where id = '<cert>';
--
-- 2) *** LA MATERIALIZACIÓN, que es el punto de toda la migración:
--
--    select vencer_objecion_si_corresponde('<cert>');
--    select objecion_estado, objecion_resuelta_por, objecion_resuelta_fecha
--    from certificados where id = '<cert>';
--    -- objecion_estado = 'vencida'
--    -- objecion_resuelta_por IS NULL          <- LA CONSTANCIA: no la levantó ninguna persona
--    -- objecion_resuelta_fecha = la fecha del vencimiento REAL (respuesta + 5 días), NO now()
--
--    select usuario_id, accion, detalle from audit_log
--    where entidad_id = '<cert>' and accion = 'vencer_objecion_certificado';
--    -- usuario_id IS NULL (el sistema), y en `detalle` quedan las dos fechas separadas: cuándo
--    -- venció y cuándo se materializó.
--
-- 3) Que NO se pueda falsear en ninguna de las dos direcciones (correr para ver el error, no se
--    aplican):
--    update certificados set objecion_estado = 'vencida', objecion_resuelta_por = '<uid>' where id = '<cert>';
--    -- tiene que fallar por certificados_objecion_cierre_check: nadie firma un vencimiento.
--    update certificados set objecion_estado = 'aclarada', objecion_resuelta_por = null,
--      objecion_resuelta_fecha = now() where id = '<cert>';
--    -- tiene que fallar por el mismo check: una objeción aclarada sin quién la aclaró no existe.
--
-- 4) El mismo motivo, no dos veces (paso 6). Con una objeción vencida en el certificado, el cliente
--    objeta de nuevo:
--    - copiando y pegando el fundamento anterior (o con otras mayúsculas o espacios de más) -> el
--      mensaje "esta objeción ya se planteó...";
--    - con un fundamento distinto -> entra, y el reloj arranca de cero recién cuando le respondan.
--
-- 5) *** EL CIRCUITO COMPLETO CON TRES USUARIOS, que es como se encontró todo esto:
--    - el cliente objeta -> al lado técnico le aparece `certificado_objetado`;
--    - el técnico responde -> al cliente le aparece `objecion_respondida` con la fecha en que se
--      resuelve sola, y al técnico se le apaga;
--    - se mueve `objecion_respondida_fecha` 6 días atrás -> el cliente deja de tener el pendiente,
--      y a quien paga le vuelve `certificado_leido`;
--    - paga -> el pago entra, y el certificado queda con la objeción en 'vencida' (la materializó
--      `marcar_certificado_pagado`), no en 'aclarada'.
--
-- 6) La objeción SIN responder no vence nunca (decisión de Seba): con `objecion_respuesta` en null y
--    `objecion_fecha` de hace un mes, `objecion_vigente` sigue dando true y el pago sigue frenado.
--
-- 7) Las dos ramas nuevas de avisos:
--    - `certificado_devuelto`: la contraparte devuelve el borrador con comentario -> le aparece a
--      quien propuso, y a nadie más. Vuelve a proponer -> se apaga (la 0124 limpia
--      `comentario_devolucion` al reproponer);
--    - `certificado_conforme` (0130): sigue funcionando igual que antes de esta migración.
--
-- 8) Que las 12 ramas anteriores devuelvan exactamente lo mismo que antes, ahora con `vence` en null.
