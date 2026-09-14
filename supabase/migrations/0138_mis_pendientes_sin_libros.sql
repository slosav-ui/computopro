-- 0138 -- mis_pendientes() vuelve a no saber nada de libros (y deja de estar rota)
--
-- ARREGLO URGENTE. Seba encontró que después de aplicar la `0137` la rama `orden_sin_acuse` seguía
-- en `mis_pendientes()`. Tenía razón, y el diagnóstico de por qué estaba mal de mi lado:
--
-- **Di por sentado que la `0135` nunca se había aplicado.** Nunca lo confirmé, lo asumí porque no
-- estaba commiteada, y sobre ese supuesto la borré y escribí la `0137` sin tocar `mis_pendientes` --
-- "no hace falta sacar una rama que no existe". La rama existía.
--
-- ================== LO GRAVE, QUE NO ES LA RAMA DE MÁS ==================
--
-- Las dos ramas de libros que dejó la `0135` seleccionan **`e.numero`**, la columna de
-- `libro_entradas` que la `0137` acaba de borrar. Postgres no registra dependencias de columnas
-- dentro del cuerpo de una función, así que el `drop column` pasó sin protestar y el problema
-- aparece recién al **ejecutar**:
--
--     ERROR: column e.numero does not exist
--
-- O sea que ahora mismo **`mis_pendientes()` falla entera**, y con ella el cartel de "acciones
-- requeridas" de todo el dashboard -- no solo lo de libros. Por eso esta migración va antes que
-- cualquier otra cosa.
--
-- Y hay un segundo efecto del mismo supuesto equivocado: la `0135` había renombrado
-- `certificado_numero`/`certificado_version` a `entidad_numero`/`entidad_version`, y al borrarla
-- revertí el Dart a los nombres viejos. Con la `0135` aplicada, esos nombres no coincidían: el
-- cartel habría mostrado "Certificado N° 0" en todos los pendientes de certificado. Esta migración
-- vuelve a los nombres viejos del lado de la base, que es lo que el Dart ya espera.
--
-- ================== QUÉ HACE ==================
--
-- Recrea `mis_pendientes()` con **el cuerpo exacto de la `0131`**: las 15 ramas de certificados,
-- adicionales y quitas/demasías, sin ninguna de libros, y con las columnas
-- `certificado_numero`/`certificado_version`. Es el estado que corresponde al alcance nuevo -- un
-- libro de comunicaciones es una conversación y **no genera pendientes todavía**; cuando se decida
-- cómo avisar (ver §F de docs/libro_obra_horizonte.md) va a ser una rama nueva, con otra forma.
--
-- `drop` + `create` y no `create or replace`: cambian los nombres de dos columnas del
-- `returns table`, y Postgres no permite reemplazar en el lugar cuando eso pasa. El `drop` además
-- sirve de red: deja la función en un estado conocido venga de donde venga la base.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project -> SQL Editor), después de `0137`. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.


-- =====================================================================
-- Antes de aplicar -- confirmar el estado, para no volver a suponer
-- =====================================================================
--
-- Correr esto primero. Es lo que había que haber corrido antes de borrar la 0135:
--
--   select
--     prosrc like '%orden_sin_acuse%'  as tiene_ramas_de_libro,   -- true = la 0135 se aplicó
--     prosrc like '%entidad_numero%'   as tiene_nombres_nuevos,   -- idem
--     prosrc like '%e.numero%'         as referencia_columna_muerta
--   from pg_proc where proname = 'mis_pendientes';
--
--   -- Y la prueba de fuego, que hoy tiene que fallar:
--   select count(*) from mis_pendientes();
--
-- Si las tres dan false y el count funciona, la 0135 no se aplicó y esta migración no hace falta
-- (aunque aplicarla igual es inofensivo: deja exactamente el mismo cuerpo que ya hay).


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
-- 1) *** QUE VUELVA A CORRER, que es el punto:
--    select count(*) from mis_pendientes();
--    -- tiene que devolver un número, no un error.
--
-- 2) Que no quedó nada de libros ni de la numeración:
--    select
--      prosrc like '%orden_sin_acuse%'    as rama_orden,        -- false
--      prosrc like '%nota_sin_respuesta%' as rama_nota,         -- false
--      prosrc like '%libro_entradas%'     as toca_libros,       -- false
--      prosrc like '%e.numero%'           as columna_muerta     -- false
--    from pg_proc where proname = 'mis_pendientes';
--
-- 3) Que las 15 ramas que SÍ van siguen estando -- esta migración reescribe la función entera, así
--    que conviene confirmar que no se llevó puesta ninguna:
--    select
--      prosrc like '%certificado_devuelto%'      as rama_0131,
--      prosrc like '%certificado_conforme%'      as rama_0130,
--      prosrc like '%certificado_objetado%'      as ramas_0129,
--      prosrc like '%certificado_sin_reemplazo%' as rama_0126,
--      prosrc like '%certificado_propuesto%'     as rama_0124,
--      prosrc like '%certificacion_periodo%'     as rama_0123,
--      prosrc like '%firma_fisica%'              as rama_0117
--    from pg_proc where proname = 'mis_pendientes';
--    -- las siete en true.
--
-- 4) La firma, con los nombres que el Dart espera:
--    select pg_get_function_result(oid) from pg_proc where proname = 'mis_pendientes';
--    -- certificado_numero / certificado_version, y 9 columnas (la novena es `vence`, de la 0131).
--
-- 5) *** Y EN LA APP, que es donde se ve si esto quedó bien: el cartel de "acciones requeridas" del
--    dashboard tiene que volver a aparecer, con los números de certificado correctos (no "N° 0").
--    Ese era el segundo efecto del supuesto equivocado, y no se nota mirando SQL.
