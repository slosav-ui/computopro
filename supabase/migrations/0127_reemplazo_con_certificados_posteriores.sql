-- 0127 -- El reemplazo nace vacío si hay certificados emitidos después del anulado, + descartar un
-- borrador
--
-- Hallazgo de Seba (2026-09-13), probando la red de seguridad de la 0126 sobre el caso real: le
-- ofrecía crear el `2 bis` de un certificado anulado, pero el 3 ya se había emitido, pagado y
-- cerrado DESPUÉS de esa anulación. Si el 2 bis nace con las filas copiadas del 2, ese avance se
-- puede contar dos veces.
--
-- *** EL AGUJERO NO ES DE LA 0126 -- VIENE DE LA 0056. ***
--
-- `proponer_anulacion_certificado` solo exige que el certificado esté `emitido` o `leido`. NO exige
-- que sea el último. O sea que se puede anular el certificado 2 con el 3 ya emitido, y el camino
-- automático crea el reemplazo con las filas copiadas igual que lo haría la red de seguridad, con
-- el mismo riesgo. **El diseño de la anulación asumió en silencio que el reemplazo nace pegado a su
-- anulación, sin nada emitido en el medio.** La 0126 no introdujo nada: hizo visible ese supuesto.
-- Por eso el arreglo va en el helper compartido y vale para los DOS caminos.
--
-- POR QUÉ EL CANDADO DEL 100% NO ALCANZA. `calcular_avance_acumulado_subitem` (0056) excluye
-- borrador y anulado, así que al anular el 2 su avance dejó de contar y el 3 se cargó sobre el
-- acumulado ya sin él. Después, `calcular_excesos_certificado` compara `intentado > 100 -
-- acumulado_previo`, partida por partida. Con una partida cerca del tope (2 tenía 40, 3 lleva 65,
-- 2 bis intenta 40) rechaza; con una a mitad de camino (2 tenía 20, 3 lleva 30, 2 bis intenta 20)
-- pasa y duplica 20 puntos. Es un candado de TOPE, no un detector de doble conteo.
--
-- LO QUE NO SE PUEDE SABER DESDE LOS DATOS. Al cargar el 3 después de anular el 2, el usuario hizo
-- una de dos cosas, y dejan exactamente las mismas filas en la base:
--   (a) recertificó lo que medía el 2 más lo nuevo  -> el 2 bis duplicaría;
--   (b) cargó solo lo nuevo, contando con el 2 bis  -> el 2 bis es legítimo y el hueco es real.
-- Ante eso, adivinar es lo peor que puede hacer el sistema. Decisión de Seba: **el reemplazo nace
-- VACÍO cuando hay certificados posteriores**, con el aviso de cuántos hay, y lo carga la persona
-- que estuvo ahí mirando el disponible que el candado ya muestra partida por partida.
--
-- Y EL PASO 3, QUE NO ES OPCIONAL. Crear un borrador traba la creación de cualquier otro
-- certificado (índice `certificados_un_borrador_por_obra`, 0053) y hasta hoy no se podía borrar
-- desde la app (`certificados` no tiene policy de DELETE). O sea que la red de seguridad podía
-- crear un problema peor que el que resuelve. Textual de Seba: "si la red de seguridad puede crear
-- un borrador que traba toda la certificación y solo se saca por SQL, la red genera un problema
-- peor que el que resuelve. No puede quedar para después."
--
-- No toca RLS (la tabla sigue SIN policy de DELETE -- se borra solo por la función del paso 3, que
-- es SECURITY DEFINER y solo acepta borradores). No agrega columnas.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project -> SQL Editor), después de `0126`. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.


-- =====================================================================
-- Paso 1 -- cuántos certificados se emitieron después de este
-- =====================================================================
--
-- Devuelve el NÚMERO, no un booleano, porque el aviso de la app lo usa: "se emitieron 2
-- certificados después de este, revisá qué falta certificar antes de cargar" es accionable;
-- "tené cuidado" no sirve (criterio de Seba).
--
-- "Posterior" se mide por `fecha_emision`, no por `numero`: un reemplazo lleva el número del
-- anulado (2 bis es numero 2) y puede haberse emitido después del 3, así que comparar números daría
-- mal. Se cuentan solo los que hoy suman al acumulado -- los borradores no cuentan (todavía no
-- certifican nada) y los anulados tampoco (ya no cuentan, misma regla que
-- `calcular_avance_acumulado_subitem`).
--
-- Si el certificado de referencia no tiene `fecha_emision`, devuelve 0: nunca se emitió, así que no
-- hay nada que pueda ser "posterior" a él. En la práctica no pasa (solo se anula lo emitido), está
-- por si acaso.

create or replace function contar_certificados_posteriores(p_certificado_id uuid)
returns int language sql security definer set search_path = public stable as $$
  select count(*)::int
  from certificados p
  join certificados c on c.id = p_certificado_id
  where p.obra_id = c.obra_id
    and p.id <> c.id
    and p.estado not in ('borrador', 'anulado')
    and c.fecha_emision is not null
    and p.fecha_emision is not null
    and p.fecha_emision > c.fecha_emision;
$$;

grant execute on function contar_certificados_posteriores(uuid) to authenticated;
revoke execute on function contar_certificados_posteriores(uuid) from public, anon;


-- =====================================================================
-- Paso 2 -- crear_borrador_reemplazo: copia las filas SOLO si no hay posteriores
-- =====================================================================
--
-- Cuerpo de la 0126 con una condición agregada alrededor del segundo insert. Todo lo demás igual:
-- el mismo insert del certificado, el mismo filtro de partidas certificables (0111), el mismo
-- mensaje si ya hay un borrador en curso, la misma atomicidad.
--
-- Vale para los dos caminos porque los dos pasan por acá: `resolver_anulacion_certificado` (anular
-- un certificado viejo con otros ya emitidos encima) y `crear_reemplazo_certificado_anulado` (la
-- red de seguridad). Ese es justamente el motivo por el que la 0126 extrajo este helper.
--
-- El reemplazo vacío NO es un reemplazo peor: es un reemplazo honesto. Nace con el mismo número,
-- versión y período que el anulado, listo para que se cargue lo que realmente falte.

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
    raise exception 'el certificado % no está anulado, o ya tiene un reemplazo', p_certificado_anulado_id;
  end if;

  v_posteriores := contar_certificados_posteriores(p_certificado_anulado_id);

  begin
    insert into certificados (obra_id, numero, version, periodo, estado, creado_por)
    values (v_obra_id, v_numero, v_version + 1, v_periodo, 'borrador', auth.uid())
    returning id into v_nuevo_id;

    -- Las filas del anulado se copian SOLO si no hay certificados emitidos después de él (0127).
    -- Con posteriores, no se puede saber si esos certificados ya recertificaron este avance, y
    -- copiarlo lo contaría dos veces: nace vacío y lo carga quien sabe qué pasó.
    --
    -- El filtro de partidas es el de la 0111: solo las que siguen siendo certificables hoy
    -- (`calcular_monto_obra_subitems`), para no arrastrar partidas destildadas después de emitir.
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
-- Paso 2-bis -- las dos bocas: dejar dicho en el audit_log si nació vacío
-- =====================================================================
--
-- Mismo cuerpo que la 0126, con un dato más en el detalle. Importa: dentro de seis meses, "este
-- reemplazo nació vacío" explica por qué el certificado no tiene las partidas del anulado, y evita
-- que se lea como que alguien las borró.
--
-- El contador se guarda en una variable antes de crear el reemplazo, aunque llamarlo después daría
-- lo mismo (el reemplazo recién nacido es un borrador, y los borradores no se cuentan): una sola
-- llamada, y el valor que se loguea es exactamente el que decidió si se copiaban las filas.

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
  v_anulacion_estado text;
  v_propuesta_por uuid;
  v_nuevo_certificado_id uuid;
  v_posteriores int;
begin
  select obra_id, numero, version, anulacion_estado, anulacion_propuesta_por
    into v_obra_id, v_numero, v_version, v_anulacion_estado, v_propuesta_por
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

  v_posteriores := contar_certificados_posteriores(p_certificado_id);
  v_nuevo_certificado_id := crear_borrador_reemplazo(p_certificado_id);

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (
    v_obra_id, auth.uid(), 'resolver_anulacion_certificado', 'certificado', p_certificado_id,
    jsonb_build_object(
      'aprobado', true,
      'numero', v_numero,
      'version_nueva', v_version + 1,
      'certificado_nuevo_id', v_nuevo_certificado_id,
      'certificados_posteriores', v_posteriores,
      'reemplazo_nacio_vacio', v_posteriores > 0
    )
  );
end;
$$;

grant execute on function resolver_anulacion_certificado(uuid, boolean, text) to authenticated;
revoke execute on function resolver_anulacion_certificado(uuid, boolean, text) from public, anon;


create or replace function crear_reemplazo_certificado_anulado(p_certificado_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_obra_id uuid;
  v_numero int;
  v_version int;
  v_nuevo_id uuid;
  v_posteriores int;
begin
  select obra_id, numero, version
    into v_obra_id, v_numero, v_version
  from certificados
  where id = p_certificado_id;

  if v_obra_id is null then
    raise exception 'certificado % no encontrado', p_certificado_id;
  end if;

  if not (tiene_rol_en_obra(v_obra_id, 'admin_maestro')
       or tiene_rol_en_obra(v_obra_id, 'profesional')
       or tiene_rol_en_obra(v_obra_id, 'constructor')) then
    raise exception 'sin autoridad para crear el reemplazo de este certificado';
  end if;

  v_posteriores := contar_certificados_posteriores(p_certificado_id);
  v_nuevo_id := crear_borrador_reemplazo(p_certificado_id);

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (
    v_obra_id, auth.uid(), 'crear_reemplazo_certificado_anulado', 'certificado', p_certificado_id,
    jsonb_build_object(
      'numero', v_numero,
      'version_nueva', v_version + 1,
      'certificado_nuevo_id', v_nuevo_id,
      'certificados_posteriores', v_posteriores,
      'reemplazo_nacio_vacio', v_posteriores > 0
    )
  );

  return v_nuevo_id;
end;
$$;

grant execute on function crear_reemplazo_certificado_anulado(uuid) to authenticated;
revoke execute on function crear_reemplazo_certificado_anulado(uuid) from public, anon;


-- =====================================================================
-- Paso 3 -- descartar un borrador
-- =====================================================================
--
-- Hasta acá, un borrador creado por error no se podía sacar desde la app: `certificados` no tiene
-- policy de DELETE (a propósito), y el índice de un borrador por obra hace que ese borrador trabe
-- la creación de cualquier otro certificado. Con la red de seguridad de la 0126 eso dejó de ser
-- teórico: crear un reemplazo que no correspondía dejaba la certificación de la obra trabada hasta
-- que alguien entrara al SQL Editor.
--
-- **La tabla sigue sin policy de DELETE.** El borrado pasa solo por esta función, SECURITY DEFINER,
-- que acepta únicamente `estado = 'borrador'`. Un certificado emitido, leído, pagado, cerrado o
-- anulado no se puede borrar por ningún camino -- eso no cambia y no tiene que cambiar.
--
-- Autoridad: los tres roles técnicos, la misma que ya crea un borrador y que carga avance. Quien
-- puede crearlo y llenarlo puede descartarlo.
--
-- Se borra de verdad, no se archiva: un borrador es trabajo en curso, no un documento. Las filas de
-- `certificado_subitems_avance` se van solas por el `on delete cascade` de la 0052. Lo que queda es
-- el `audit_log`, y por eso el detalle guarda QUÉ se descartó (número, versión, período, cuántas
-- partidas tenía y en qué punto del acuerdo estaba): si alguien descarta un borrador con avance
-- cargado, tiene que poder reconstruirse qué había.
--
-- Se permite descartar aunque el acuerdo esté 'propuesto' o 'conforme' (0124). Bloquearlo crearía
-- justo la trampa que esta función viene a sacar: un borrador conformado que nadie puede mover y
-- que traba toda la certificación. Queda en el audit_log en qué punto estaba.
--
-- Nota de coherencia con la 0126: si el borrador descartado era el reemplazo de un anulado, el
-- hueco vuelve a existir, y `falta_reemplazo_certificado` lo vuelve a detectar -- el aviso reaparece
-- solo. Es la propiedad que se busca, no un efecto colateral.

create or replace function descartar_borrador_certificado(p_certificado_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_obra_id uuid;
  v_estado text;
  v_numero int;
  v_version int;
  v_periodo text;
  v_acuerdo_estado text;
  v_partidas int;
begin
  select obra_id, estado, numero, version, periodo, acuerdo_estado
    into v_obra_id, v_estado, v_numero, v_version, v_periodo, v_acuerdo_estado
  from certificados
  where id = p_certificado_id;

  if v_obra_id is null then
    raise exception 'certificado % no encontrado', p_certificado_id;
  end if;

  if v_estado <> 'borrador' then
    raise exception 'solo se descarta un borrador (estado actual: %)', v_estado;
  end if;

  if not (tiene_rol_en_obra(v_obra_id, 'admin_maestro')
       or tiene_rol_en_obra(v_obra_id, 'profesional')
       or tiene_rol_en_obra(v_obra_id, 'constructor')) then
    raise exception 'sin autoridad para descartar este borrador';
  end if;

  select count(*)::int into v_partidas
  from certificado_subitems_avance
  where certificado_id = p_certificado_id;

  -- El log ANTES del delete: después, la fila ya no está para leerle nada. `audit_log.entidad_id`
  -- no tiene foreign key a `certificados` (0002), así que la referencia sobrevive al borrado.
  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (
    v_obra_id, auth.uid(), 'descartar_borrador_certificado', 'certificado', p_certificado_id,
    jsonb_build_object(
      'numero', v_numero,
      'version', v_version,
      'periodo', v_periodo,
      'partidas_con_avance', v_partidas,
      'acuerdo_estado', v_acuerdo_estado
    )
  );

  delete from certificados where id = p_certificado_id;
end;
$$;

grant execute on function descartar_borrador_certificado(uuid) to authenticated;
revoke execute on function descartar_borrador_certificado(uuid) from public, anon;


-- =====================================================================
-- Verificación a mano después de aplicar (SQL Editor + app)
-- =====================================================================
--
-- El caso real de la obra ya sirve de prueba: el certificado 2 está anulado, y el 3 se emitió
-- DESPUÉS de esa anulación.
--
-- 1) El contador, sin usuario:
--    select numero, version, estado, fecha_emision, contar_certificados_posteriores(id)
--    from certificados where obra_id = '<obra_id>' order by numero, version;
--    -- el 2 (anulado) tiene que dar 1 o más (el 3, y el 4 si ya está emitido);
--    -- el último emitido de la obra tiene que dar 0.
--
-- 2) *** EL CASO QUE MOTIVA LA MIGRACIÓN: crear el reemplazo del 2 desde la app.
--    - nace `2 bis` en borrador, con numero 2 y version 2, período el del anulado;
--    - `select count(*) from certificado_subitems_avance where certificado_id = '<2bis>';` -> **0**.
--      Si copia filas, la migración no está haciendo lo suyo.
--    - el audit_log de esa acción tiene `reemplazo_nacio_vacio: true` y el número de posteriores.
--
-- 3) Que el camino de siempre NO haya cambiado: anular el ÚLTIMO certificado emitido de una obra
--    (sin nada emitido después) -> el reemplazo tiene que nacer CON las partidas copiadas, igual
--    que antes de esta migración, y el audit_log con `reemplazo_nacio_vacio: false`.
--
-- 4) El camino automático con posteriores (es el agujero viejo de la 0056, el que esta migración
--    cierra de paso): con el 3 ya emitido, proponer y aprobar la anulación del 2 -> el reemplazo
--    tiene que nacer VACÍO. Antes de esta migración nacía con las filas copiadas.
--
-- 5) Descartar un borrador:
--    - con los tres roles técnicos -> se borra, y sus filas de avance se van solas (cascade);
--    - el audit_log queda con numero/version/periodo/partidas_con_avance/acuerdo_estado;
--    - después de descartarlo, "Nuevo certificado" vuelve a funcionar (el índice de un borrador por
--      obra queda liberado);
--    - si el borrador descartado era el reemplazo de un anulado, el aviso `certificado_sin_reemplazo`
--      TIENE que volver a aparecer en mis_pendientes();
--    - intentar descartar un certificado emitido/leído/pagado/cerrado/anulado -> 'solo se descarta
--      un borrador';
--    - con un usuario cliente_principal -> 'sin autoridad para descartar este borrador'.
--
-- 6) Que la tabla siga cerrada al borrado directo: desde la app, con un usuario técnico,
--    `delete from certificados where id = '<un borrador>'` tiene que borrar 0 filas (no hay policy
--    de DELETE). El único camino es la función.
