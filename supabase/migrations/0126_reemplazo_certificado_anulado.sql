-- 0126 -- Red de seguridad: un certificado anulado que quedó sin reemplazo se puede recrear
--
-- Pedido de Seba (2026-09-13), después de encontrar en una obra real un certificado anulado sin su
-- `bis`. El diagnóstico de ese caso puntual cerró en que NO había bug: el borrador de reemplazo se
-- había creado bien y se borró después a mano, limpiando borradores para probar otra cosa.
--
-- Lo que sí quedó a la vista es un agujero de producto: **si un reemplazo se pierde, la app no tiene
-- forma de recrearlo.** El único camino que genera un `bis` es `resolver_anulacion_certificado`, y
-- esa anulación ya está resuelta. La obra queda con un hueco que solo se tapa por SQL, y mientras
-- tanto lo que certificaba el anulado no está certificado por ningún documento vigente.
--
-- Bajo uso normal de la app esta condición NO se puede producir: la creación del reemplazo es
-- atómica (el `raise` dentro del bloque `exception` propaga y revierte el `update` que anuló),
-- `certificados` no tiene policy de DELETE, y un borrador no se puede anular. O sea que esto es una
-- **red de reparación**, no el parche de un bug vivo. Por eso el aviso NO es descartable (decisión
-- de Seba): si aparece, algo falta de verdad.
--
-- No toca RLS. No agrega columnas. No cambia ninguna transición del ciclo. Lo único que se toca de
-- lo que ya anda es `resolver_anulacion_certificado`, y solo para que llame al helper compartido en
-- vez de tener el bloque duplicado.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project -> SQL Editor), después de `0125`. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.


-- =====================================================================
-- Paso 1 -- la detección: ¿a este anulado le falta el reemplazo?
-- =====================================================================
--
-- El modelo de numeración ya define el reemplazo sin ambigüedad (`unique (obra_id, numero, version)`,
-- 0056): el reemplazo es **mismo `numero`, `version + 1`**.
--
-- La condición es "es la versión MÁS ALTA de su número", y no "no existe la version + 1", a
-- propósito: en una cadena `1 v1 anulado -> 1 v2 anulado -> 1 v3`, el hueco siempre está arriba. Con
-- la otra formulación, el `1 v1` daría falso positivo para siempre.
--
-- Un solo helper para las tres bocas que lo necesitan: la función que recrea, el aviso de
-- `mis_pendientes()` y la app (que lo llama por RPC para decidir si muestra el botón).

create or replace function falta_reemplazo_certificado(p_certificado_id uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select exists (
    select 1 from certificados c
    where c.id = p_certificado_id
      and c.estado = 'anulado'
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
-- Paso 2 -- el helper compartido que CREA el reemplazo
-- =====================================================================
--
-- Estas ~15 líneas vivían dentro de `resolver_anulacion_certificado`. Se extraen para que el camino
-- automático (resolver una anulación) y el manual (reparar un hueco) no puedan divergir: si mañana
-- cambia qué se copia, cambia en un solo lugar. Es el mismo criterio que ya se usó con
-- `puede_dar_conformidad_certificado` en la 0124, y el motivo textual de Seba al pedirlo: "si se
-- duplican las quince líneas, el día que cambie una, la otra queda vieja. Ya nos pasó varias veces".
--
-- NO chequea autoridad ni escribe audit_log: eso es de cada boca, que tiene la suya y loguea su
-- propia acción. Lo que sí chequea es lo que no puede depender de quién llame -- que el certificado
-- esté anulado y que efectivamente le falte el reemplazo.
--
-- El filtro de partidas es el de la 0111: se copian solo las filas cuya partida sigue siendo
-- certificable hoy (`calcular_monto_obra_subitems`), para no arrastrar al reemplazo partidas
-- destildadas después de emitir, con avance fantasma.

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

  begin
    insert into certificados (obra_id, numero, version, periodo, estado, creado_por)
    values (v_obra_id, v_numero, v_version + 1, v_periodo, 'borrador', auth.uid())
    returning id into v_nuevo_id;

    insert into certificado_subitems_avance (certificado_id, obra_subitem_id, porcentaje_periodo, creado_por)
    select v_nuevo_id, csa.obra_subitem_id, csa.porcentaje_periodo, auth.uid()
    from certificado_subitems_avance csa
    where csa.certificado_id = p_certificado_anulado_id
      and csa.obra_subitem_id in (
        select mos.obra_subitem_id from calcular_monto_obra_subitems(v_obra_id) mos
      );
  exception
    when unique_violation then
      raise exception 'ya hay un borrador en curso para esta obra — resolvé o emití ese borrador antes de poder crear el reemplazo del certificado anulado';
  end;

  return v_nuevo_id;
end;
$$;

-- No se le da execute a `authenticated`: es una pieza interna de las dos funciones de abajo, que son
-- las que tienen el chequeo de autoridad. Llamarla suelta saltearía ese chequeo.
revoke execute on function crear_borrador_reemplazo(uuid) from public, anon, authenticated;


-- =====================================================================
-- Paso 3 -- resolver_anulacion_certificado, ahora llamando al helper
-- =====================================================================
--
-- Cuerpo vigente de 0121 copiado tal cual. El único cambio es que el bloque de creación se
-- reemplaza por la llamada al helper del paso 2. **Sin cambio de comportamiento**: mismo insert,
-- mismo filtro de partidas, mismo mensaje de error si ya hay un borrador en curso, misma atomicidad
-- (el `raise` del helper propaga y revierte el `update` que dejó el certificado en 'anulado').
--
-- La autoridad NO cambia: sigue siendo la dupla técnica (profesional/constructor) con el permiso, y
-- nunca quien propuso. Confirmado por Seba el 2026-09-13 al mover la matriz de emisión: "anular es
-- reconocer que la medición estuvo mal, y eso es de los dos, no una potestad de cierre".

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

  -- El reemplazo, vía el helper compartido (0126). Si falla, propaga y revierte también el update
  -- de arriba: el certificado NO queda anulado sin su reemplazo.
  v_nuevo_certificado_id := crear_borrador_reemplazo(p_certificado_id);

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (
    v_obra_id, auth.uid(), 'resolver_anulacion_certificado', 'certificado', p_certificado_id,
    jsonb_build_object('aprobado', true, 'numero', v_numero, 'version_nueva', v_version + 1, 'certificado_nuevo_id', v_nuevo_certificado_id)
  );
end;
$$;

grant execute on function resolver_anulacion_certificado(uuid, boolean, text) to authenticated;
revoke execute on function resolver_anulacion_certificado(uuid, boolean, text) from public, anon;


-- =====================================================================
-- Paso 4 -- la reparación: crear el reemplazo que falta
-- =====================================================================
--
-- Autoridad: los tres roles técnicos (admin_maestro / profesional / constructor), que es
-- exactamente lo que ya exige `certificados_insert` (0009) para crear un borrador, y lo que expone
-- `UserContext.puedeCargarAvance`.
--
-- Por qué esa y no `puede_editar_presupuesto` (decisión de Seba, 2026-09-13): **recrear el reemplazo
-- es crear un borrador, no un acto formal.** No compromete plata, no emite, no cambia ningún monto.
-- Los actos formales siguen pidiendo lo suyo después: la conformidad de la 0124 y la autoridad de
-- emisión de la 0125. Pedir el permiso acá sería más estricto que el camino automático que esto
-- repara, donde el reemplazo nace solo sin que nadie lo pida.
--
-- Lo que NO se trae de la anulación es la regla de "nunca la misma persona en los dos lados": esa
-- protege la DECISIÓN de anular, que ya fue tomada y resuelta. Acá no se decide nada nuevo -- se
-- restituye una fila que debería existir.

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

  -- El helper valida que esté anulado y que le falte el reemplazo, y devuelve el mensaje claro si
  -- hay un borrador en curso.
  v_nuevo_id := crear_borrador_reemplazo(p_certificado_id);

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (
    v_obra_id, auth.uid(), 'crear_reemplazo_certificado_anulado', 'certificado', p_certificado_id,
    jsonb_build_object('numero', v_numero, 'version_nueva', v_version + 1, 'certificado_nuevo_id', v_nuevo_id)
  );

  return v_nuevo_id;
end;
$$;

grant execute on function crear_reemplazo_certificado_anulado(uuid) to authenticated;
revoke execute on function crear_reemplazo_certificado_anulado(uuid) from public, anon;


-- =====================================================================
-- Paso 5 -- mis_pendientes(): el aviso
-- =====================================================================
--
-- Cuerpo vigente de 0124 copiado tal cual, con la rama nueva agregada antes del `order by` y el
-- comentario de la firma actualizado. Ninguna otra línea cambia.
--
-- Va también acá y no solo en la tarjeta del certificado porque los anulados viven en la sección
-- `Anulados (N)` de Gestión de Obra, **colapsada por defecto**: ahí solo lo encuentra el que va a
-- buscarlo, y una red de seguridad que hay que ir a buscar no sirve de nada (decisión de Seba).
--
-- La app vigente todavía no conoce el tipo `certificado_sin_reemplazo`: `Pendiente.desdeRow` (0117)
-- devuelve null para un tipo desconocido y saltea la fila, así que esta migración se puede aplicar y
-- verificar por SQL antes de tocar el Dart.

create or replace function mis_pendientes()
returns table(
  obra_id uuid,
  obra_nombre text,
  tipo text,                -- adicional | quita | demasia | certificado_emitido | certificado_leido
                            -- | certificado_pagado | anulacion | firma_fisica | certificacion_periodo
                            -- | certificado_propuesto | certificado_sin_reemplazo
  entidad_id uuid,          -- modificaciones_obra.id o certificados.id, según tipo; null en
                            -- certificacion_periodo (no es una fila, es un período que venció)
  descripcion text,         -- descripción del adicional/quita/demasía, o período del certificado
  certificado_numero int,   -- solo certificados: la app arma "N° 3 bis" con Certificado.formatearNumero
  certificado_version int,
  desde timestamptz         -- desde cuándo espera (para ordenar y mostrar)
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
         coalesce(m.enviado_a_aprobacion_en, m.fecha_solicitud) as desde
  from modificaciones_obra m
  join mis_obras mo on mo.id = m.obra_id
  where m.tipo = 'adicional'
    and m.estado = 'pendiente'
    and (m.obra_hija_id is null or m.enviado_a_aprobacion_en is not null)
    and puede_aprobar_adicional(m.obra_id, m.monto_total)

  union all

  select mo.id, mo.nombre, m.tipo, m.id, m.descripcion, null::int, null::int, m.fecha_solicitud
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

  select mo.id, mo.nombre, 'certificado_emitido'::text, c.id, c.periodo, c.numero, c.version, c.fecha_emision
  from certificados c
  join mis_obras mo on mo.id = c.obra_id
  where c.estado = 'emitido'
    and (tiene_rol_en_obra(c.obra_id, 'cliente_principal') or tiene_rol_en_obra(c.obra_id, 'invitado_apoderado'))

  union all

  select mo.id, mo.nombre, 'certificado_leido'::text, c.id, c.periodo, c.numero, c.version, c.fecha_lectura
  from certificados c
  join mis_obras mo on mo.id = c.obra_id
  where c.estado = 'leido'
    and puede_gestionar_certificado(c.obra_id, c.monto)

  union all

  select mo.id, mo.nombre, 'certificado_pagado'::text, c.id, c.periodo, c.numero, c.version, c.fecha_pago
  from certificados c
  join mis_obras mo on mo.id = c.obra_id
  where c.estado = 'pagado'
    and (tiene_rol_en_obra(c.obra_id, 'admin_maestro') or tiene_rol_en_obra(c.obra_id, 'constructor'))

  union all

  select mo.id, mo.nombre, 'anulacion'::text, c.id, c.periodo, c.numero, c.version, c.anulacion_propuesta_fecha
  from certificados c
  join mis_obras mo on mo.id = c.obra_id
  where c.anulacion_estado = 'propuesta'
    and (tiene_rol_en_obra(c.obra_id, 'profesional') or tiene_rol_en_obra(c.obra_id, 'constructor'))
    and c.anulacion_propuesta_por <> auth.uid()

  union all

  select mo.id, mo.nombre, 'firma_fisica'::text, c.id, c.periodo, c.numero, c.version, c.fecha_emision
  from certificados c
  join mis_obras mo on mo.id = c.obra_id
  where c.requiere_firma_fisica = true
    and c.pdf_firmado_subido = false
    and c.estado not in ('borrador', 'anulado')
    and (tiene_rol_en_obra(c.obra_id, 'admin_maestro') or tiene_rol_en_obra(c.obra_id, 'profesional'))

  union all

  -- Periodicidad pactada (0123): "ya se puede certificar". No sale de ninguna fila de certificados
  -- ni de modificaciones_obra -- es un período que venció, así que `entidad_id` va en null y la app
  -- lleva a Gestión de Obra de la obra, que es donde se crea el borrador.
  --
  -- Condiciones, en orden de lectura: hay periodicidad pactada; la obra certifica por avance medido
  -- (Modelo A -- en Modelo B no hay certificados, ver la policy INSERT de 0009); está congelada (sin
  -- contrato firmado no hay período que correr, y avisar empujaría a certificar contra precios
  -- vivos); el próximo período ya venció; y NO hay un borrador en curso -- si alguien ya está
  -- armando el certificado, el recordatorio es ruido.
  --
  -- Quién lo ve: los tres roles que cargan avance (mismo conjunto que la RLS de
  -- certificado_subitems_avance y que UserContext.puedeCargarAvance). El cliente no inicia la
  -- certificación: la recibe.
  select mo.id, mo.nombre, 'certificacion_periodo'::text, null::uuid,
         o.periodicidad_certificacion, null::int, null::int, p.vence
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

  -- Acuerdo entre partes (0124): "te proponen un avance para revisar". Va a la contraparte y nunca
  -- a quien propuso -- eso ya lo resuelve puede_dar_conformidad_certificado, que es la MISMA función
  -- que usan dar_conformidad_certificado y devolver_avance_certificado: el aviso no puede ofrecer
  -- algo que después la función rechace. Las dos condiciones de estado se repiten acá para que el
  -- planner filtre barato y para que la rama se lea sola.
  --
  -- `desde` = la fecha de la propuesta, que es desde cuándo el otro está esperando. La app lleva a
  -- la pantalla de carga de avance, que es donde se revisa lo propuesto.
  select mo.id, mo.nombre, 'certificado_propuesto'::text, c.id, c.periodo, c.numero, c.version,
         c.propuesta_fecha
  from certificados c
  join mis_obras mo on mo.id = c.obra_id
  where c.estado = 'borrador'
    and c.acuerdo_estado = 'propuesto'
    and puede_dar_conformidad_certificado(c.id)

  union all

  -- Red de seguridad (0126): un certificado anulado que quedó sin reemplazo. La condición sale del
  -- mismo helper que usa la función que lo repara, así el aviso no puede ofrecer algo que después se
  -- rechace.
  --
  -- Aparece aunque haya un borrador en curso (que impediría crearlo ahora): el hueco existe igual, y
  -- el botón de la app explica que primero hay que emitir o resolver ese borrador. Esconder el
  -- hallazgo hasta que el camino esté despejado sería esconder justo lo que hay que reparar.
  --
  -- `desde` = cuándo se resolvió la anulación, que es desde cuándo la obra tiene el hueco.
  select mo.id, mo.nombre, 'certificado_sin_reemplazo'::text, c.id, c.periodo, c.numero, c.version,
         c.anulacion_resuelta_fecha
  from certificados c
  join mis_obras mo on mo.id = c.obra_id
  where c.estado = 'anulado'
    and falta_reemplazo_certificado(c.id)
    and (tiene_rol_en_obra(c.obra_id, 'admin_maestro')
      or tiene_rol_en_obra(c.obra_id, 'profesional')
      or tiene_rol_en_obra(c.obra_id, 'constructor'))

  order by 8;
$$;

grant execute on function mis_pendientes() to authenticated;


-- =====================================================================
-- Verificación a mano después de aplicar (SQL Editor + app)
-- =====================================================================
--
-- La obra que destapó esto ya tiene el caso listo para probar, sin fabricar nada: el certificado 2
-- está anulado y su `2 bis` no existe.
--
-- 1) La detección, sin usuario (el helper no mira quién llama):
--    select numero, version, estado, falta_reemplazo_certificado(id)
--    from certificados where obra_id = '<obra_id>' order by numero, version;
--    -- true SOLO en el 2 (anulado, sin 2 v2). El 1 tiene su 1 bis -> false. Los no anulados ->
--    -- false. Si un anulado tuviera otro anulado encima (1 v1 -> 1 v2 anulado -> nada), el true
--    -- tiene que caer en el de version más alta, nunca en los dos.
--
-- 2) La reparación, desde la app con un usuario admin_maestro/profesional/constructor y SIN borrador
--    en curso: crear el reemplazo del 2 -> nace `2 bis` (numero 2, version 2) en borrador, con las
--    filas de avance del anulado que siguen siendo certificables hoy.
--
-- 3) El bloqueo esperado: con un borrador en curso, la misma acción tiene que devolver "ya hay un
--    borrador en curso para esta obra — resolvé o emití ese borrador...". Y el certificado 2 tiene
--    que seguir anulado, sin cambios: la función no deja nada a medias.
--
-- 4) Que no se pueda repetir: pedir el reemplazo del 2 una segunda vez -> "no está anulado, o ya
--    tiene un reemplazo".
--
-- 5) Que la anulación siga funcionando IGUAL que antes (es lo único que se tocó de lo que ya anda):
--    anular un certificado emitido de punta a punta -> nace el `bis` con las partidas copiadas,
--    exactamente como antes de esta migración. Y con un borrador en curso, la anulación tiene que
--    fallar con el mensaje de siempre y dejar el certificado SIN anular.
--
-- 6) El aviso: `select tipo, descripcion, certificado_numero from mis_pendientes();` tiene que
--    devolver una fila `certificado_sin_reemplazo` para el 2, y dejar de devolverla en cuanto se
--    crea el reemplazo. Y que las otras 9 ramas sigan devolviendo lo mismo que antes.
--
-- 7) Que la función interna esté cerrada: `select crear_borrador_reemplazo('<id>');` desde un
--    usuario `authenticated` tiene que fallar por permisos -- solo se llega por las dos funciones
--    que chequean autoridad.
