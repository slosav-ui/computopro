-- 0141 -- El libro nunca va a la pantalla principal: globito adentro de la obra, y nada más
--
-- Segunda corrección del aviso, después de probar la `0140` con los tres usuarios. Textual de Seba
-- (2026-09-14):
--
--   *"Con la campana prendida, el aviso del libro sigue apareciendo en el dashboard. Eso es lo que
--   justamente no quiero: los mensajes del libro nunca van a la pantalla principal, ni prendida ni
--   apagada."*
--
-- La `0140` había leído la regla a medias. Yo entendí "que no moleste por defecto" y dejé el
-- interruptor para volver a ponerlo ahí; la regla es más simple y más fuerte: **la pantalla
-- principal es para lo que requiere acción, y una conversación no lo es nunca** -- no es cuestión de
-- preferencia de cada uno. Lo que reemplaza al aviso es **un globito con el número al lado del ícono
-- del libro**, adentro de Gestión de Obra, como el de WhatsApp: se entra a la obra y se ve que hay
-- tres sin leer.
--
-- ================== QUÉ PASA CON LA CAMPANA ==================
--
-- Cambia de significado: deja de ser "mostrar en el dashboard" y pasa a ser **"avisarme al
-- teléfono"**, para cuando existan las notificaciones push. Seba dejó a mi criterio si quedaba
-- apagada y sin efecto, o si se sacaba hasta entonces.
--
-- **La saco**, y el motivo es un precedente de este mismo proyecto: ya hay un control que promete
-- algo y no lo hace -- el botón Free/PRO del dashboard, que no escribe `perfiles.es_pro` -- y está
-- anotado como un problema, no como una gracia. Un interruptor que no hace nada le enseña al usuario
-- que los controles de esta app pueden ser decorativos, y eso se paga en todos los demás.
--
-- La decisión **no se pierde**: queda escrita en docs/libro_obra_horizonte.md §H, donde dice que
-- cuando exista el push la preferencia es **por persona y por obra, apagada por defecto**. Volver a
-- crear la columna ese día es una línea; tenerla dos meses sin que nadie la lea es dato muerto que
-- confunde al que abra el esquema -- el mismo criterio con el que se sacó `libro_entradas.numero` en
-- la `0137`.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project -> SQL Editor), después de `0140`. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.


-- =====================================================================
-- Paso 1 -- fuera el interruptor
-- =====================================================================
--
-- Primero la función (que nombra la columna) y después la columna, por el mismo motivo que la
-- `0137`: Postgres no registra dependencias de columnas dentro del cuerpo de una función, así que
-- dejarla al revés no falla al aplicar -- falla al ejecutar, que es mucho peor. Esa lección ya salió
-- cara una vez en esta misma pieza (ver `0138`).

drop function if exists set_aviso_libro_dashboard(uuid, boolean);

alter table libro_lecturas drop column if exists avisar_en_dashboard;


-- =====================================================================
-- Paso 2 -- `libro_novedades` se queda, y ahora es la única fuente del aviso
-- =====================================================================
--
-- No se toca: devuelve cuántos, de quién y desde cuándo, y la pantalla usa el **cuántos** para el
-- globito. `autores` y `mas_viejo` quedan disponibles y hoy no se muestran -- a diferencia de una
-- columna muerta, acá no hay dato guardado de más: se calculan en el momento, y el día que la
-- pantalla quiera decir "3 mensajes de Juan" ya están.


-- =====================================================================
-- Paso 3 -- mis_pendientes(): el libro sale del cartel, y no vuelve
-- =====================================================================
--
-- La rama `libro_mensajes_nuevos` se va entera. La función vuelve a ser **exactamente el cuerpo de
-- la `0138`**: las 15 ramas de certificados, adicionales y quitas, ninguna de libros.
--
-- La firma no cambia, así que alcanza con `create or replace`.
--
-- Y que quede dicho para el que venga: **esta rama no se vuelve a agregar**. Si algún día el libro
-- tiene que avisar fuera de la obra, el lugar es una notificación al teléfono, no el cartel de
-- acciones requeridas.

create or replace function mis_pendientes()
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
-- 1) *** LO QUE MOTIVÓ LA MIGRACIÓN: con mensajes sin leer, y sin importar nada más,
--    `mis_pendientes()` NO tiene que devolver nada del libro. Ni prendido ni apagado, porque ya no
--    hay dónde prenderlo.
--
--    select prosrc like '%libro%' as toca_libros   -- false
--    from pg_proc where proname = 'mis_pendientes';
--    select count(*) from mis_pendientes();        -- un número, no un error
--
-- 2) Que el interruptor no dejó restos:
--    select column_name from information_schema.columns where table_name = 'libro_lecturas';
--    -- obra_id, usuario_id, ultima_lectura. Sin `avisar_en_dashboard`.
--    select proname from pg_proc where proname = 'set_aviso_libro_dashboard';   -- 0 filas
--
-- 3) Que la marca de leído sigue funcionando, que es lo que el globito necesita:
--    select * from libro_novedades('<obra>');   -- cuantos > 0 con mensajes sin leer
--    -- abrir el libro en la app y volver a correrlo -> cuantos = 0.
--
-- 4) Que las 15 ramas del cartel siguen enteras:
--    select
--      prosrc like '%certificado_devuelto%'      as rama_0131,
--      prosrc like '%certificado_conforme%'      as rama_0130,
--      prosrc like '%certificado_objetado%'      as ramas_0129,
--      prosrc like '%certificacion_periodo%'     as rama_0123,
--      prosrc like '%firma_fisica%'              as rama_0117
--    from pg_proc where proname = 'mis_pendientes';
--
-- 5) En la app: el globito rojo con el número sobre el ícono del libro en Gestión de Obra, que
--    desaparece al entrar y volver. Y el dashboard, sin una sola mención del libro.
