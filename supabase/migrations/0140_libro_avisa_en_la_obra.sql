-- 0140 -- El libro avisa adentro de la obra, no en la pantalla principal
--
-- CORRECCIÓN de la `0139`, después de probarla con los tres usuarios. Funcionaba, y por eso se vio
-- el problema: **cada mensaje del libro generaba un aviso en la pantalla principal, y eso termina
-- siendo ruido**.
--
-- La regla que fija Seba (2026-09-14), y que vale de acá en adelante para toda la app:
--
--   *"La pantalla principal es para lo que requiere acción, no para conversaciones. Un certificado
--   esperando, un adicional para aprobar, una objeción -- eso sí. Un mensaje en el libro, no."*
--
-- Es un criterio de producto, no una preferencia de esta pieza: un cartel de "acciones requeridas"
-- que se llena de cosas que no son acciones deja de mirarse, y el día que aparezca un certificado de
-- verdad va a estar enterrado entre diez mensajes de obra. **Cuando lleguen las notificaciones al
-- teléfono, el mismo criterio**: certificados y adicionales sí, el libro no salvo que lo prendan.
--
-- ================== EL INTERRUPTOR, Y POR QUÉ NO ES UN CAPRICHO ==================
--
-- Va igual un interruptor por persona para volver a verlo en la pantalla principal, apagado por
-- defecto -- *"como en WhatsApp, que se puede silenciar o no una conversación"*.
--
-- Y tiene una razón de fondo que Seba explicó y conviene dejar escrita, porque explica por qué la
-- app **no** intenta resolverlo: hoy este circuito vive en un grupo de WhatsApp con los tres, y
-- siempre termina igual -- se arman grupos separados, el constructor con el profesional por un lado
-- y el profesional con el cliente por otro. Eso va a pasar igual, y no es un problema a resolver: la
-- app da la herramienta y el que la quiere usar la usa. El interruptor es exactamente eso: cada uno
-- decide cuánto quiere que este libro le invada la pantalla principal.
--
-- ================== POR PERSONA Y POR OBRA, EN LA TABLA QUE YA ESTÁ ==================
--
-- `libro_lecturas` ya tiene justo ese grano -- una fila por (obra, usuario) -- así que el
-- interruptor es una columna más ahí y no una tabla nueva. Y el default `false` cae solo: **si no
-- hay fila, no hay aviso**, que es exactamente "apagado por defecto" sin necesidad de crear filas
-- para nadie.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project -> SQL Editor), después de `0139`. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.


-- =====================================================================
-- Paso 1 -- el interruptor
-- =====================================================================

alter table libro_lecturas
  add column avisar_en_dashboard boolean not null default false;

comment on column libro_lecturas.avisar_en_dashboard is
  'Si esta persona quiere ver los mensajes nuevos del libro en el cartel del dashboard (0140). '
  'Default false: la pantalla principal es para lo que requiere accion, no para conversaciones. Es '
  'por persona y por obra, como silenciar una conversacion.';

-- Prender y apagar. Upsert porque la fila puede no existir todavía: alguien puede querer el aviso
-- antes de haber abierto el libro por primera vez.
--
-- `ultima_lectura` en el insert queda en el pasado a propósito (`-infinity` no se puede por el
-- `not null` con default, así que se usa el epoch): crear la fila para prender el aviso **no puede
-- marcar el libro como leído**. Sería apagar lo que se acaba de pedir prender.
create or replace function set_aviso_libro_dashboard(p_obra_id uuid, p_avisar boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not is_obra_member(p_obra_id) then
    raise exception 'no sos miembro de esta obra';
  end if;

  insert into libro_lecturas (obra_id, usuario_id, ultima_lectura, avisar_en_dashboard)
  values (p_obra_id, auth.uid(), 'epoch'::timestamptz, coalesce(p_avisar, false))
  on conflict (obra_id, usuario_id) do update
    set avisar_en_dashboard = coalesce(p_avisar, false);
end;
$$;

grant execute on function set_aviso_libro_dashboard(uuid, boolean) to authenticated;
revoke execute on function set_aviso_libro_dashboard(uuid, boolean) from public, anon;


-- =====================================================================
-- Paso 2 -- libro_novedades: el aviso que va ADENTRO de Gestión de Obra
-- =====================================================================
--
-- Es el reemplazo real del aviso del dashboard, no un premio consuelo: ahí el usuario **ya está
-- mirando esa obra**, así que decirle que hay comunicaciones nuevas es información y no
-- interrupción.
--
-- Devuelve cuántas, de quién y desde cuándo. Los nombres salen de `perfiles` con el mismo criterio
-- que `get_perfiles_de_obra` (0099): entre compañeros de obra el nombre se ve, `es_pro` nunca. Si
-- alguien no cargó nombre, simplemente no aparece en el array -- la pantalla dice "3 mensajes
-- nuevos" sin el "de", que es mejor que inventar un nombre o mostrar un UUID.
--
-- Una sola fila siempre (los agregados sin `group by` la garantizan): `cuantos = 0` cuando no hay
-- nada nuevo, y ahí la pantalla no dibuja nada.

create or replace function libro_novedades(p_obra_id uuid)
returns table(
  cuantos int,
  autores text[],
  mas_viejo timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    count(*)::int,
    coalesce(array_agg(distinct p.nombre) filter (where nullif(btrim(p.nombre), '') is not null),
             array[]::text[]),
    min(e.created_at)
  from libro_entradas e
  left join libro_lecturas l on l.obra_id = e.obra_id and l.usuario_id = auth.uid()
  left join perfiles p on p.usuario_id = e.autor_usuario_id
  where e.obra_id = p_obra_id
    and e.libro = 'obra'
    and e.autor_usuario_id <> auth.uid()
    and (l.ultima_lectura is null or e.created_at > l.ultima_lectura)
    and is_obra_member(p_obra_id);
$$;

grant execute on function libro_novedades(uuid) to authenticated;
revoke execute on function libro_novedades(uuid) from public, anon;


-- =====================================================================
-- Paso 3 -- mis_pendientes(): la rama del libro, solo para quien la pidió
-- =====================================================================
--
-- Cuerpo de la `0139` con **una condición más** en la rama del libro:
-- `l.avisar_en_dashboard` tiene que ser true. Sin fila de lectura no hay aviso, que es el default
-- apagado.
--
-- La rama no se borra: el interruptor existe justamente para que se pueda prender. Lo que cambia es
-- que ahora **hay que pedirlo**.
--
-- El `left join` de la 0139 pasa a `join`: sin fila en `libro_lecturas` no puede haber interruptor
-- prendido, así que la fila es obligatoria para que la rama devuelva algo. Y como esa fila también
-- trae `ultima_lectura`, el filtro de "posteriores a mi última lectura" sigue igual.

create or replace function mis_pendientes()
returns table(
  obra_id uuid,
  obra_nombre text,
  tipo text,                -- adicional | quita | demasia | certificado_emitido | certificado_leido
                            -- | certificado_pagado | anulacion | firma_fisica | certificacion_periodo
                            -- | certificado_propuesto | certificado_sin_reemplazo
                            -- | certificado_objetado | objecion_respondida
                            -- | certificado_conforme | certificado_devuelto
                            -- | libro_mensajes_nuevos
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

  union all

  -- 0139/0140: mensajes nuevos en el libro, **solo para quien prendio el interruptor** de esa obra.
  -- Apagado por defecto: el aviso normal del libro vive adentro de Gestion de Obra (libro_novedades),
  -- que es donde el usuario ya esta mirando esa obra. Aca solo llega si lo pidio.
  select mo.id, mo.nombre, 'libro_mensajes_nuevos'::text, null::uuid,
         nuevos.ultimo_texto, null::int, null::int, nuevos.mas_viejo, null::timestamptz
  from mis_obras mo
  join obras o on o.id = mo.id
  cross join lateral (
    select
      min(e.created_at) as mas_viejo,
      (array_agg(e.contenido order by e.created_at desc))[1] as ultimo_texto
    from libro_entradas e
    -- 0140: `join` y no `left join`. Sin fila de lectura no puede haber interruptor prendido, y sin
    -- interruptor prendido esta rama no tiene nada que hacer -- la pantalla principal es para lo que
    -- requiere accion, no para conversaciones.
    join libro_lecturas l
      on l.obra_id = e.obra_id and l.usuario_id = auth.uid()
    where e.obra_id = mo.id
      and e.libro = 'obra'
      and e.autor_usuario_id <> auth.uid()
      and l.avisar_en_dashboard
      and e.created_at > l.ultima_lectura
  ) nuevos
  where o.libros_habilitados
    and nuevos.mas_viejo is not null

  order by 8;
$$;

grant execute on function mis_pendientes() to authenticated;
revoke execute on function mis_pendientes() from public, anon;


-- =====================================================================
-- Verificación a mano después de aplicar
-- =====================================================================
--
-- 1) *** LO QUE MOTIVÓ LA MIGRACIÓN: con mensajes sin leer y el interruptor apagado (o sin fila),
--    `mis_pendientes()` **no** tiene que devolver `libro_mensajes_nuevos`. Ese es el arreglo.
--
--    begin;
--      set local role authenticated;
--      set local request.jwt.claims = '{"sub":"<uuid>","role":"authenticated"}';
--      select tipo from mis_pendientes() where tipo = 'libro_mensajes_nuevos';   -- 0 filas
--    rollback;
--
-- 2) El aviso que sí va, adentro de la obra:
--    select * from libro_novedades('<obra>');
--    -- cuantos > 0, `autores` con los nombres de quienes escribieron (sin el que pregunta), y
--    -- `mas_viejo` con la fecha del más viejo sin leer.
--    -- Con el libro al día: cuantos = 0 y autores vacío (una fila igual, no cero filas).
--
-- 3) El interruptor, de las dos formas:
--    select set_aviso_libro_dashboard('<obra>', true);
--    -- y ahora sí, el punto 1 tiene que devolver la fila.
--    select set_aviso_libro_dashboard('<obra>', false);
--    -- y vuelve a no devolverla.
--
-- 4) *** QUE PRENDER EL AVISO NO MARQUE EL LIBRO COMO LEÍDO. Con mensajes sin leer y SIN haber
--    abierto nunca el libro:
--    select set_aviso_libro_dashboard('<obra>', true);
--    select cuantos from libro_novedades('<obra>');
--    -- tiene que seguir contando los mensajes. Si diera 0, el insert está pisando `ultima_lectura`
--    -- con `now()` y apagó justo lo que se acaba de pedir prender.
--
-- 5) Que el resto del cartel no se movió: las 15 ramas de certificados, adicionales y quitas siguen
--    devolviendo lo mismo que antes.
--    select count(*) from mis_pendientes();   -- sin error
--
-- 6) Y en la app: en Gestión de Obra tiene que aparecer la línea de comunicaciones nuevas con el
--    nombre de quien escribió; en el dashboard, nada -- hasta prender el interruptor desde el libro.
