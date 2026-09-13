-- 0128 -- Primero se resuelve la corrección, después sigue la numeración
--
-- Regla que faltaba, dicha por Seba (2026-09-13): **cuando se anula un certificado, hasta que su
-- reemplazo no se emite no se puede crear ninguno con número nuevo.**
--
-- Hoy eso se cumplía **de casualidad**, por el índice de un solo borrador por obra (0053): mientras
-- el reemplazo estaba en borrador, no se podía crear otro. Pero si alguien descarta ese borrador
-- (`descartar_borrador_certificado`, 0127) el candado desaparece y el número siguiente se puede
-- crear dejando el hueco atrás. Es exactamente lo que pasó en la obra de Seba: el 2 quedó anulado
-- sin reemplazo y se emitieron el 3 y el 4 encima.
--
-- Se hace explícito con un trigger, y no con una policy ni con un chequeo en Dart, por tres motivos:
-- la creación del borrador es un `insert` directo desde la app (no hay función que interceptar), un
-- chequeo en Dart no protege de nada, y el trigger cubre también el SQL a mano -- que es justo el
-- camino por el que se coló el problema original.
--
-- *** Y LA CONSECUENCIA QUE OBLIGA AL PASO 3 ***
--
-- La obra de Seba YA está en ese estado, con el 3 y el 4 emitidos después del hueco. Con la regla
-- nueva a secas, para crear el 5 habría que emitir el 2 bis... pero `emitir_certificado` rechaza un
-- certificado sin avance cargado ("no se puede emitir un certificado sin avance cargado"), y el 2
-- bis nace vacío (0127) justamente porque los certificados posteriores pueden haber cubierto todo
-- lo que el 2 medía. **Si efectivamente lo cubrieron, no hay nada que cargar, el 2 bis no se puede
-- emitir, y la obra queda trabada para siempre.**
--
-- Por eso la regla viene con su salida, y la salida no es una excepción escondida: es un acto
-- explícito, con motivo obligatorio, autor y fecha -- `marcar_reemplazo_no_requerido`. Dice, con
-- todas las letras, "este anulado no necesita reemplazo porque lo que medía ya está certificado en
-- los que vinieron después". Que es la verdad de esa obra, y merece quedar escrita en el libro, no
-- resolverse borrando el problema.
--
-- Alternativa descartada: permitir emitir un reemplazo de monto 0. Dejaría un certificado de $0 en
-- el historial, pasaría por todo el circuito de conformidad para nada, y le avisaría al cliente que
-- tiene un certificado nuevo para leer. Un renglón que dice "no hizo falta corregir nada" es más
-- honesto que un documento de cobro por cero pesos.
--
-- No toca RLS. No cambia ninguna transición del ciclo.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project -> SQL Editor), después de `0127`. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.


-- =====================================================================
-- Paso 1 -- "este anulado no necesita reemplazo", con motivo
-- =====================================================================
--
-- Mismo patrón que el resto de los ejes de este proyecto (anulación, acuerdo): quién, cuándo y por
-- qué, con un check que impide dejarlo a medias. El motivo es obligatorio a nivel base: sin el
-- motivo, dentro de un año nadie va a poder decir si el hueco se cerró porque estaba cubierto o
-- porque alguien quería sacarse el aviso de encima.

alter table certificados
  add column reemplazo_no_requerido_por uuid references auth.users(id),
  add column reemplazo_no_requerido_fecha timestamptz,
  add column reemplazo_no_requerido_motivo text;

alter table certificados add constraint certificados_reemplazo_no_requerido_check
  check (
    (reemplazo_no_requerido_por is null
     and reemplazo_no_requerido_fecha is null
     and reemplazo_no_requerido_motivo is null)
    or (reemplazo_no_requerido_por is not null
     and reemplazo_no_requerido_fecha is not null
     and reemplazo_no_requerido_motivo is not null
     and estado = 'anulado')
  );

comment on column certificados.reemplazo_no_requerido_motivo is
  'Por que este certificado anulado no necesita reemplazo (0128) -- tipicamente, porque los '
  'certificados emitidos despues ya cubrieron lo que medía. Cierra el hueco de numeracion sin '
  'inventar un certificado de monto cero.';


-- =====================================================================
-- Paso 2 -- falta_reemplazo_certificado: un marcado ya no cuenta como hueco
-- =====================================================================
--
-- Una línea más sobre la versión de la 0126. Como esta función es la fuente única —la usan el aviso
-- de `mis_pendientes()`, el botón de la app y `crear_borrador_reemplazo`—, marcar un anulado lo saca
-- de los tres lugares de una sola vez.

create or replace function falta_reemplazo_certificado(p_certificado_id uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select exists (
    select 1 from certificados c
    where c.id = p_certificado_id
      and c.estado = 'anulado'
      and c.reemplazo_no_requerido_fecha is null
      and not exists (
        select 1 from certificados r
        where r.obra_id = c.obra_id
          and r.numero = c.numero
          and r.version > c.version
      )
  );
$$;

grant execute on function falta_reemplazo_certificado(uuid) to authenticated;
revoke execute on function falta_reemplazo_certificado(uuid) from public, anon;


-- =====================================================================
-- Paso 3 -- marcar_reemplazo_no_requerido: la salida, explícita
-- =====================================================================
--
-- Autoridad: `puede_editar_presupuesto`. A propósito MÁS estricta que crear el reemplazo (que es de
-- los tres roles técnicos, 0126): crear un borrador es reversible -- se descarta y no queda nada.
-- Esto cierra un hueco del libro de certificados de forma definitiva y destraba la numeración. Es un
-- acto de cierre, no una tarea de carga.
--
-- Solo sobre un anulado que hoy no tenga reemplazo. Si ya tiene uno (aunque esté en borrador), lo
-- que corresponde es emitirlo o descartarlo, no declarar que no hace falta.

create or replace function marcar_reemplazo_no_requerido(
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
  v_numero int;
  v_version int;
begin
  select obra_id, numero, version
    into v_obra_id, v_numero, v_version
  from certificados
  where id = p_certificado_id;

  if v_obra_id is null then
    raise exception 'certificado % no encontrado', p_certificado_id;
  end if;

  if not puede_editar_presupuesto(v_obra_id) then
    raise exception 'sin autoridad para declarar que este certificado no necesita reemplazo';
  end if;

  if p_motivo is null or btrim(p_motivo) = '' then
    raise exception 'hace falta decir por qué este certificado no necesita reemplazo';
  end if;

  if not falta_reemplazo_certificado(p_certificado_id) then
    raise exception 'el certificado % no está anulado, ya tiene un reemplazo, o ya está marcado como que no lo necesita', p_certificado_id;
  end if;

  update certificados
  set reemplazo_no_requerido_por = auth.uid(),
      reemplazo_no_requerido_fecha = now(),
      reemplazo_no_requerido_motivo = p_motivo
  where id = p_certificado_id;

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (
    v_obra_id, auth.uid(), 'marcar_reemplazo_no_requerido', 'certificado', p_certificado_id,
    jsonb_build_object('numero', v_numero, 'version', v_version, 'motivo', p_motivo)
  );
end;
$$;

grant execute on function marcar_reemplazo_no_requerido(uuid, text) to authenticated;
revoke execute on function marcar_reemplazo_no_requerido(uuid, text) from public, anon;


-- =====================================================================
-- Paso 4 -- ¿hay algún anulado sin resolver en la obra?
-- =====================================================================
--
-- OJO, no es lo mismo que `falta_reemplazo_certificado`, y la diferencia importa:
--
--   falta_reemplazo_certificado(cert)  -> no existe NINGUNA versión mayor. Habilita CREAR el
--                                         reemplazo.
--   certificado_anulado_sin_resolver   -> no existe una versión mayor EMITIDA. Bloquea el número
--                                         nuevo.
--
-- Un reemplazo en borrador hace la primera falsa (no se puede crear otro) y la segunda verdadera
-- (todavía no se emitió, así que la corrección no está resuelta). Eso es exactamente la regla:
-- primero se resuelve la corrección, después sigue la numeración.
--
-- Devuelve el id del que hay que resolver, no un booleano, para que el mensaje pueda nombrarlo. En
-- una cadena de anulados (1 v1 -> 1 v2 -> nada) devuelve la punta: el 1 v2, que es sobre el que hay
-- que actuar. Ordena por número para que, con varios huecos, siempre señale el más viejo primero.

create or replace function certificado_anulado_sin_resolver(p_obra_id uuid)
returns uuid language sql security definer set search_path = public stable as $$
  select c.id
  from certificados c
  where c.obra_id = p_obra_id
    and c.estado = 'anulado'
    and c.reemplazo_no_requerido_fecha is null
    and not exists (
      select 1 from certificados r
      where r.obra_id = c.obra_id
        and r.numero = c.numero
        and r.version > c.version
        and r.estado not in ('borrador', 'anulado')
    )
  order by c.numero, c.version desc
  limit 1;
$$;

grant execute on function certificado_anulado_sin_resolver(uuid) to authenticated;
revoke execute on function certificado_anulado_sin_resolver(uuid) from public, anon;


-- =====================================================================
-- Paso 5 -- el trigger: no se crea un número nuevo con una corrección abierta
-- =====================================================================
--
-- `version = 1` es la marca de "número nuevo": un reemplazo siempre nace con `version + 1` >= 2
-- (`crear_borrador_reemplazo`), así que esta regla no lo toca -- y no puede tocarlo, porque el
-- reemplazo es justamente la forma de resolver el bloqueo.
--
-- BEFORE INSERT y no una policy: la creación del borrador es un `insert` directo desde la app
-- (`crearCertificadoBorrador`), y un trigger cubre además el SQL a mano, que es el camino por el que
-- se coló el problema original. Para una reparación puntual desde el SQL Editor se puede
-- `alter table certificados disable trigger certificados_numero_nuevo_bloqueado;` y volver a
-- habilitarlo -- a conciencia, no de pasada.
--
-- El mensaje nombra el certificado que falta resolver y dice las dos salidas, porque un "no se
-- puede" sin decir qué hacer es lo mismo que nada.

create or replace function bloquear_numero_nuevo_con_anulado_sin_resolver()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pendiente_id uuid;
  v_numero int;
  v_version int;
begin
  if new.version <> 1 then
    return new; -- es un reemplazo, no un número nuevo
  end if;

  v_pendiente_id := certificado_anulado_sin_resolver(new.obra_id);
  if v_pendiente_id is null then
    return new;
  end if;

  select numero, version into v_numero, v_version
  from certificados where id = v_pendiente_id;

  raise exception 'el certificado N° % está anulado y su reemplazo todavía no se emitió: emití el reemplazo, o dejá dicho por qué no hace falta, antes de crear un certificado nuevo',
    case when v_version > 1 then v_numero || ' (versión ' || v_version || ')' else v_numero::text end;
end;
$$;

create trigger certificados_numero_nuevo_bloqueado
  before insert on certificados
  for each row execute function bloquear_numero_nuevo_con_anulado_sin_resolver();


-- =====================================================================
-- Paso 6 -- crear_borrador_reemplazo: el mensaje, al día
-- =====================================================================
--
-- Cuerpo de la 0127 sin un solo cambio de lógica. Lo único que cambia es el texto del rechazo, que
-- desde el paso 2 tiene un caso más: un anulado marcado como que no necesita reemplazo. Decir "no
-- está anulado, o ya tiene un reemplazo" en ese caso manda a buscar el problema donde no está --
-- ya nos pasó hoy con "no está pagado" sobre un certificado que estaba cerrado.

create or replace function crear_borrador_reemplazo(p_certificado_anulado_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_obra_id uuid;
  v_numero int;
  v_version int;
  v_periodo text;
  v_nuevo_id uuid;
  v_posteriores int;
begin
  select obra_id, numero, version, periodo
    into v_obra_id, v_numero, v_version, v_periodo
  from certificados
  where id = p_certificado_anulado_id;

  if v_obra_id is null then
    raise exception 'certificado % no encontrado', p_certificado_anulado_id;
  end if;

  if not falta_reemplazo_certificado(p_certificado_anulado_id) then
    raise exception 'el certificado % no está anulado, ya tiene un reemplazo, o está marcado como que no lo necesita', p_certificado_anulado_id;
  end if;

  v_posteriores := contar_certificados_posteriores(p_certificado_anulado_id);

  begin
    insert into certificados (obra_id, numero, version, periodo, estado, creado_por)
    values (v_obra_id, v_numero, v_version + 1, v_periodo, 'borrador', auth.uid())
    returning id into v_nuevo_id;

    -- Las filas del anulado se copian SOLO si no hay certificados emitidos después de él (0127).
    if v_posteriores = 0 then
      insert into certificado_subitems_avance (certificado_id, obra_subitem_id, porcentaje_periodo, creado_por)
      select v_nuevo_id, csa.obra_subitem_id, csa.porcentaje_periodo, auth.uid()
      from certificado_subitems_avance csa
      where csa.certificado_id = p_certificado_anulado_id
        and csa.obra_subitem_id in (
          select mos.obra_subitem_id from calcular_monto_obra_subitems(v_obra_id) mos
        );
    end if;
  exception
    when unique_violation then
      raise exception 'ya hay un borrador en curso para esta obra — resolvé o emití ese borrador antes de poder crear el reemplazo del certificado anulado';
  end;

  return v_nuevo_id;
end;
$$;

revoke execute on function crear_borrador_reemplazo(uuid) from public, anon, authenticated;


-- =====================================================================
-- Verificación a mano después de aplicar (SQL Editor + app)
-- =====================================================================
--
-- La obra que destapó todo esto ya está en el estado que interesa: el 2 anulado sin reemplazo, con
-- el 3 y el 4 emitidos después.
--
-- 1) El estado de la obra, sin usuario:
--    select numero, version, estado, falta_reemplazo_certificado(id) from certificados
--    where obra_id = '<obra_id>' order by numero, version;
--    select certificado_anulado_sin_resolver('<obra_id>');
--    -- tiene que devolver el id del 2.
--
-- 2) *** EL BLOQUEO, que es el motivo de la migración: desde la app, "Nuevo certificado" en esa
--    obra tiene que fallar con "el certificado N° 2 está anulado y su reemplazo todavía no se
--    emitió...". Antes de la 0128 creaba el 5 sin decir nada.
--
-- 3) *** LA SALIDA, que es lo que evita que la obra quede trabada: marcar el 2 como que no necesita
--    reemplazo, con motivo, desde un usuario con puede_editar_presupuesto. Después:
--    - `certificado_anulado_sin_resolver('<obra_id>')` -> null;
--    - "Nuevo certificado" vuelve a funcionar y crea el 5;
--    - el aviso `certificado_sin_reemplazo` desaparece de `mis_pendientes()`;
--    - el botón "Crear el reemplazo" del detalle del 2 desaparece.
--    Con un usuario sin ese permiso -> 'sin autoridad'. Sin motivo -> 'hace falta decir por qué'.
--
-- 4) La otra salida, la normal: en una obra con un anulado sin reemplazo y SIN certificados
--    posteriores, crear el reemplazo (nace con las partidas copiadas), cargarlo y emitirlo ->
--    `certificado_anulado_sin_resolver` pasa a null y el número nuevo se habilita solo.
--
-- 5) Que el reemplazo NO quede bloqueado por su propio anulado: con el 2 anulado sin resolver,
--    crear el reemplazo (version 2) tiene que funcionar. Si esto falla, el trigger está mirando mal
--    la versión y la obra no tiene salida.
--
-- 6) Que una obra sana no cambie en nada: sin ningún anulado, o con todos resueltos, "Nuevo
--    certificado" funciona exactamente como antes.
--
-- 7) El camino de siempre sigue cerrado en orden: anular un certificado deja su reemplazo en
--    borrador, y mientras ese borrador exista no se puede crear un número nuevo -- antes lo impedía
--    el índice de un borrador por obra, ahora además lo dice el trigger con un mensaje que explica
--    qué resolver.
