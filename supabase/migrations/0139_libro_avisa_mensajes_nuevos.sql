-- 0139 -- El libro avisa: mensajes nuevos desde la última vez que entraste
--
-- Cierra el agujero que abrió el cambio de alcance del 2026-09-14. Textual de Seba, dos veces:
-- *"escribí con slosav y a seba2135 no le apareció nada, ni en el dashboard ni en Gestión de Obra.
-- Sin aviso el libro no sirve"*.
--
-- El acuse de recibo, que se fue con los libros direccionales, era **lo que hacía posible avisar**:
-- daba un estado binario y objetivo -- la entrada tiene hija o no la tiene -- sin necesidad de
-- rastrear quién leyó qué. Con una conversación plana ya no hay tal estado: lo que hay es **un
-- mensaje sin leer**, que es una relación entre cada persona y el libro, no una propiedad de la
-- entrada. De ahí sale la forma de esta migración.
--
-- ================== LAS DOS DECISIONES DE SEBA (2026-09-14) ==================
--
-- **1. Se marca leído al abrir, no con un botón.** *"El libro es para leer. Si hay que tocar algo
-- para que se apague el aviso, aparece un paso que nadie entiende y que se olvida siempre."*
--
-- **2. El cliente también recibe el aviso**, aunque no escriba. *"Leer es todo lo que puede hacer
-- ahí: si no se entera de que hay algo nuevo, para él el libro no existe."* Esto corrige mi
-- recomendación, que era dejarlo afuera del cartel porque "leer no es una acción requerida" -- el
-- argumento de Seba es mejor: para quien solo lee, enterarse **es** la acción. El texto del aviso
-- queda neutro ("Mensajes nuevos en el libro de obra"), así que sirve igual para el que va a
-- contestar y para el que solo se entera.
--
-- ================== POR QUÉ UNA TABLA APARTE, Y NO UNA COLUMNA ==================
--
-- Lo más importante del diseño: **la lectura NO se guarda en `libro_entradas`**. Esa tabla no tiene
-- políticas de UPDATE ni de DELETE (0004) y eso es exactamente lo que la vuelve un registro serio.
-- La última lectura, en cambio, se pisa cada vez que alguien abre la pantalla: es **estado de
-- interfaz**, no registro. Mezclarlos le abriría la primera puerta de escritura a la tabla que no
-- tiene que tenerla, para guardar un dato que a nadie le importa dentro de seis meses.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project -> SQL Editor), después de `0138`. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.


-- =====================================================================
-- Paso 1 -- libro_lecturas
-- =====================================================================
--
-- Una fila por persona y por obra. La clave primaria compuesta es el índice que hace falta y de
-- paso impide dos filas para el mismo par, que sería la forma de que el aviso empiece a mentir.
--
-- Sin `created_at`: no es un historial de visitas, es un solo dato que se pisa. Guardar cada
-- apertura sería vigilancia, no funcionalidad.

create table libro_lecturas (
  obra_id uuid not null references obras(id) on delete cascade,
  usuario_id uuid not null references auth.users(id) on delete cascade,
  ultima_lectura timestamptz not null default now(),
  primary key (obra_id, usuario_id)
);

comment on table libro_lecturas is
  'Hasta cuando ley6 cada persona el libro de cada obra (0139). Estado de interfaz, NO registro: se '
  'pisa en cada apertura. Va aparte de libro_entradas justamente para que esa tabla siga sin '
  'politicas de UPDATE, que es lo que la vuelve un respaldo.';

alter table libro_lecturas enable row level security;

-- Cada uno ve y escribe SOLO su propia fila, y solo en obras donde es miembro. No hay razón para
-- que nadie sepa cuándo entró otro al libro -- ni siquiera el administrador.
create policy libro_lecturas_select on libro_lecturas for select
using (usuario_id = auth.uid() and is_obra_member(obra_id));

create policy libro_lecturas_insert on libro_lecturas for insert with check (
  usuario_id = auth.uid() and is_obra_member(obra_id)
);

create policy libro_lecturas_update on libro_lecturas for update
using (usuario_id = auth.uid() and is_obra_member(obra_id))
with check (usuario_id = auth.uid() and is_obra_member(obra_id));

-- Sin DELETE: borrar la fila equivale a "no leí nada nunca", que no es un estado que alguien
-- necesite pedir. Y si la obra o el usuario se van, el cascade se encarga.


-- =====================================================================
-- Paso 2 -- marcar_libro_leido
-- =====================================================================
--
-- `p_hasta` en vez de `now()` a secas, y no es un detalle de prolijidad: la pantalla primero **trae**
-- las entradas y después marca. Si en ese intervalo entra un mensaje nuevo, marcar con `now()` lo
-- daría por leído sin haberlo mostrado nunca -- un mensaje que desaparece del aviso sin que nadie lo
-- haya visto. Pasando la fecha de la última entrada que efectivamente se cargó, eso no puede pasar.
--
-- Nunca retrocede: si la fila ya tiene una lectura más nueva (otra pantalla, otro dispositivo), se
-- queda con la más nueva. Marcar hacia atrás haría reaparecer avisos ya leídos.
--
-- `security definer` con guard de membresía, mismo patrón que el resto: la RLS de arriba ya lo
-- cubre, pero así el upsert es una sola llamada y no depende de que el cliente arme bien el
-- `on conflict`.

create or replace function marcar_libro_leido(p_obra_id uuid, p_hasta timestamptz default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not is_obra_member(p_obra_id) then
    raise exception 'no sos miembro de esta obra';
  end if;

  insert into libro_lecturas (obra_id, usuario_id, ultima_lectura)
  values (p_obra_id, auth.uid(), coalesce(p_hasta, now()))
  on conflict (obra_id, usuario_id) do update
    set ultima_lectura = greatest(libro_lecturas.ultima_lectura, excluded.ultima_lectura);
end;
$$;

grant execute on function marcar_libro_leido(uuid, timestamptz) to authenticated;
revoke execute on function marcar_libro_leido(uuid, timestamptz) from public, anon;


-- =====================================================================
-- Paso 3 -- mis_pendientes(): la rama del libro
-- =====================================================================
--
-- Cuerpo de la `0138` con **una rama más**, y nada más. La firma no cambia: alcanza con
-- `create or replace`.
--
--   libro_mensajes_nuevos -> a CUALQUIER miembro de la obra, incluido el cliente y el veedor
--                            (decisión 2), cuando hay mensajes de OTRO posteriores a su última
--                            lectura.
--
-- Una fila por obra, no una por mensaje: el cartel diría diez veces lo mismo. `descripcion` trae el
-- texto del más nuevo y `desde` la fecha del más viejo sin leer -- así el ítem se explica solo y se
-- ordena por lo que hace más rato que espera.
--
-- `entidad_id` va null, como `certificacion_periodo`: lo que hay que abrir no es una fila, es el
-- libro de esa obra.
--
-- **Los propios no cuentan** (`autor_usuario_id <> auth.uid()`): nadie necesita que le avisen de lo
-- que acaba de escribir. Y si la obra apagó el libro (`libros_habilitados`), no avisa nada.

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

  -- 0139: mensajes nuevos en el libro de comunicaciones, para cualquier miembro de la obra --
  -- incluido el cliente y el veedor, que solo leen: para ellos enterarse ES la accion.
  select mo.id, mo.nombre, 'libro_mensajes_nuevos'::text, null::uuid,
         nuevos.ultimo_texto, null::int, null::int, nuevos.mas_viejo, null::timestamptz
  from mis_obras mo
  join obras o on o.id = mo.id
  cross join lateral (
    select
      min(e.created_at) as mas_viejo,
      (array_agg(e.contenido order by e.created_at desc))[1] as ultimo_texto
    from libro_entradas e
    left join libro_lecturas l
      on l.obra_id = e.obra_id and l.usuario_id = auth.uid()
    where e.obra_id = mo.id
      and e.libro = 'obra'
      and e.autor_usuario_id <> auth.uid()
      and (l.ultima_lectura is null or e.created_at > l.ultima_lectura)
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
-- 1) Que la función sigue entera y sumó la rama:
--    select
--      prosrc like '%libro_mensajes_nuevos%'     as rama_0139,
--      prosrc like '%certificado_devuelto%'      as rama_0131,
--      prosrc like '%certificado_conforme%'      as rama_0130,
--      prosrc like '%certificacion_periodo%'     as rama_0123,
--      prosrc like '%orden_sin_acuse%'           as no_deberia_estar   -- false
--    from pg_proc where proname = 'mis_pendientes';
--    select count(*) from mis_pendientes();   -- tiene que devolver un número, no un error
--
-- 2) *** EL CASO QUE LO ORIGINÓ, con dos usuarios en una obra con el libro prendido:
--    - slosav escribe en el libro;
--    - a seba2135 le tiene que aparecer `libro_mensajes_nuevos` en el cartel del dashboard;
--    - **a slosav NO**, que fue quien escribió;
--    - seba2135 abre el libro -> el pendiente se apaga solo, sin tocar ningún botón;
--    - slosav escribe otra vez -> vuelve a aparecerle a seba2135, y no a slosav.
--
--    Sin dos dispositivos, con el truco de los claims de la 0130:
--    begin;
--      set local role authenticated;
--      set local request.jwt.claims = '{"sub":"<uuid>","role":"authenticated"}';
--      select tipo, obra_nombre, descripcion, desde from mis_pendientes();
--    rollback;
--
-- 3) *** EL CLIENTE TAMBIÉN (decisión 2): con el cliente de la obra, el mismo aviso tiene que
--    aparecer. Es el cambio respecto de lo que yo había recomendado, así que conviene verlo.
--    Y el veedor igual.
--
-- 4) La marca al abrir, y que no retrocede:
--    select * from libro_lecturas where obra_id = '<obra>';
--    -- una fila por persona que abrió, con su última lectura. Abrir de nuevo la adelanta;
--    -- nunca la atrasa (el `greatest` del paso 2).
--
-- 5) Que nadie ve la lectura de otro:
--    begin;
--      set local role authenticated;
--      set local request.jwt.claims = '{"sub":"<uuid de slosav>","role":"authenticated"}';
--      select count(*) from libro_lecturas;   -- solo SUS filas, aunque haya de otros
--    rollback;
--
-- 6) El interruptor: con `libros_habilitados = false` en la obra, no avisa nada aunque haya
--    mensajes sin leer -- y al volver a prenderlo, el aviso reaparece.
--
-- 7) Una obra sin libro escrito no genera ninguna fila: el `cross join lateral` con
--    `mas_viejo is not null` la deja afuera, no la trae con contador en cero.
