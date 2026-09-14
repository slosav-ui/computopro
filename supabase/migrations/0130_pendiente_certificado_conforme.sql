-- 0130 -- El certificado conformado que nadie emite: la rama que le faltaba a mis_pendientes()
--
-- BUG REAL, reportado por Seba el 2026-09-14 al verificar la tanda 3 con tres usuarios: "a slosav no
-- le aparece la acción requerida en el dashboard, aunque al entrar a la obra ve todo". Diagnóstico
-- completo: docs/avisos_pendientes_diseno.md §6.
--
-- QUÉ PASA: un certificado en `borrador` con la conformidad ya dada (`acuerdo_estado = 'conforme'`)
-- está esperando que alguien lo emita, y **no le aparece a nadie**. No es un aviso que llega tarde:
-- no llega nunca. El certificado puede quedar ahí indefinidamente mientras las dos partes técnicas
-- creen que ya está, porque las dos hicieron lo suyo.
--
-- POR QUÉ NACIÓ, que es lo que importa para no repetirlo: la tabla de esperas de la `0117` se
-- escribió cuando `borrador -> emitido` era **un solo acto** -- el que miraba el borrador lo emitía,
-- así que no había nada que avisarle. La `0124` partió ese acto en tres (`propuesto -> conforme ->
-- emitido`) y la `0125` le dio el tercero a **otra persona**: el profesional, que puede no haber
-- participado ni de la propuesta ni de la conformidad y que, por lo tanto, puede no tener ni idea de
-- que le toca. Cada vez que un circuito gana un paso con dueño propio, gana también una espera; si
-- no se le agrega la rama, el hueco no avisa de su existencia -- se descubre probando, un mes
-- después, como pasó acá.
--
-- LA AUTORIDAD NO SE INVENTA: `puede_emitir_certificado(obra_id)` existe desde la `0125`, es la misma
-- que ejecuta `emitir_certificado` y la misma que la app ya llama por RPC para decidir si muestra el
-- botón "Emitir". Tres bocas, una definición.
--
-- POR QUÉ LA CONDICIÓN ES `acuerdo_estado = 'conforme'` Y NO "hay un borrador sin emitir": en una
-- obra sin contraparte (`hay_contraparte_certificacion` = false, el caso del usuario solo), la
-- conformidad no se pide y el borrador se emite directo desde `en_carga`. Ahí el borrador es trabajo
-- en curso de la única persona que puede tocarlo, y avisarle a alguien de algo que está haciendo él
-- mismo es ruido -- es el criterio de §4-D del diseño de avisos ("lo que está en preparación no
-- figura"), que sigue valiendo. Lo que cambia con la conformidad es justamente que **ya no está en
-- preparación**: hubo un acuerdo entre dos, y lo que falta es el acto de un tercero.
--
-- ALCANCE, a propósito chico: **una rama más y nada más**. No toca ninguna transición, ninguna
-- columna, ninguna RLS y ningún cálculo. La otra rama huérfana del mismo origen -- el borrador
-- devuelto con comentario (`devolver_avance_certificado`), que tampoco avisa a quien propuso --
-- queda fuera hasta que Seba la confirme: ver §6.2 del diagnóstico.
--
-- Se puede aplicar ANTES de tocar el Dart: `Pendiente.desdeRow` (0117) devuelve null para un `tipo`
-- que la app no conoce y saltea esa fila, así que la app vigente no se rompe ni se entera.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project -> SQL Editor), después de `0129`. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.


-- =====================================================================
-- Paso único -- mis_pendientes(): una rama más
-- =====================================================================
--
-- Cuerpo vigente de la `0129` copiado tal cual, con la rama nueva agregada antes del `order by` y el
-- comentario de la firma actualizado. Ninguna otra línea cambia.
--
--   certificado_conforme -> a quien emite en esa obra, mientras el borrador conformado siga sin
--                           emitirse. `desde` = `conforme_fecha`, que es el momento en que la espera
--                           empezó de verdad.

create or replace function mis_pendientes()
returns table(
  obra_id uuid,
  obra_nombre text,
  tipo text,                -- adicional | quita | demasia | certificado_emitido | certificado_leido
                            -- | certificado_pagado | anulacion | firma_fisica | certificacion_periodo
                            -- | certificado_propuesto | certificado_sin_reemplazo
                            -- | certificado_objetado | objecion_respondida
                            -- | certificado_conforme
  entidad_id uuid,
  descripcion text,
  certificado_numero int,
  certificado_version int,
  desde timestamptz
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
    -- 0129: con una objeción abierta el pago está frenado, así que pedirlo sería ofrecer algo que la
    -- base rechaza. El pendiente que corresponde ahí es `objecion_respondida`, más abajo.
    and coalesce(c.objecion_estado, '') <> 'abierta'

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

  select mo.id, mo.nombre, 'certificado_propuesto'::text, c.id, c.periodo, c.numero, c.version,
         c.propuesta_fecha
  from certificados c
  join mis_obras mo on mo.id = c.obra_id
  where c.estado = 'borrador'
    and c.acuerdo_estado = 'propuesto'
    and puede_dar_conformidad_certificado(c.id)

  union all

  select mo.id, mo.nombre, 'certificado_sin_reemplazo'::text, c.id, c.periodo, c.numero, c.version,
         c.anulacion_resuelta_fecha
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
         c.objecion_fecha
  from certificados c
  join mis_obras mo on mo.id = c.obra_id
  where c.objecion_estado = 'abierta'
    and c.objecion_respuesta is null
    and (tiene_rol_en_obra(c.obra_id, 'profesional')
      or tiene_rol_en_obra(c.obra_id, 'constructor')
      or tiene_rol_en_obra(c.obra_id, 'admin_maestro'))

  union all

  -- Y la vuelta: al cliente, cuando ya le respondieron y la objeción sigue abierta. Le toca a él
  -- leer la aclaración y levantar la objeción, o dejarla planteada.
  select mo.id, mo.nombre, 'objecion_respondida'::text, c.id, c.periodo, c.numero, c.version,
         c.objecion_respondida_fecha
  from certificados c
  join mis_obras mo on mo.id = c.obra_id
  where c.objecion_estado = 'abierta'
    and c.objecion_respuesta is not null
    and (tiene_rol_en_obra(c.obra_id, 'cliente_principal')
      or tiene_rol_en_obra(c.obra_id, 'invitado_apoderado'))

  union all

  -- 0130: el borrador ya conformado que todavía nadie emitió. Va a quien emite en esta obra según la
  -- escalera de la 0125 (profesional -> cliente -> admin_maestro), que es la misma autoridad que
  -- ejecuta `emitir_certificado`. `desde` = conforme_fecha: la espera empieza con el acuerdo, no con
  -- la creación del borrador.
  select mo.id, mo.nombre, 'certificado_conforme'::text, c.id, c.periodo, c.numero, c.version,
         c.conforme_fecha
  from certificados c
  join mis_obras mo on mo.id = c.obra_id
  where c.estado = 'borrador'
    and c.acuerdo_estado = 'conforme'
    and puede_emitir_certificado(c.obra_id)

  order by 8;
$$;

grant execute on function mis_pendientes() to authenticated;
revoke execute on function mis_pendientes() from public, anon;


-- =====================================================================
-- Verificación a mano después de aplicar
-- =====================================================================
--
-- 0) Que la función quedó completa -- la `0130` reescribe el cuerpo entero, así que conviene
--    confirmar que no se perdió ninguna rama de las anteriores por aplicar de a pedazos:
--
--    select
--      prosrc like '%certificado_conforme%'      as rama_0130,
--      prosrc like '%certificado_objetado%'      as ramas_0129,
--      prosrc like '%certificado_sin_reemplazo%' as rama_0126,
--      prosrc like '%certificado_propuesto%'     as rama_0124,
--      prosrc like '%certificacion_periodo%'     as rama_0123
--    from pg_proc where proname = 'mis_pendientes';
--    -- las cinco tienen que dar true.
--
-- 1) *** SIN TRES DISPOSITIVOS: se puede correr `mis_pendientes()` como cualquier usuario desde el
--    SQL Editor. Esto contradice lo que vienen diciendo todas las migraciones anteriores ("el SQL
--    Editor corre sin usuario logueado y tiene_rol_en_obra da false para todo"), y es cierto solo
--    mientras no se pongan los claims a mano: `auth.uid()` lee el claim `sub` del JWT.
--
--    begin;
--      set local role authenticated;
--      set local request.jwt.claims = '{"sub":"<uuid del usuario>","role":"authenticated"}';
--      select tipo, obra_nombre, certificado_numero, desde from mis_pendientes();
--    rollback;
--
--    Sirve para todas las ramas, no solo para esta. `rollback` no hace falta (no escribe nada) pero
--    deja el `set local` acotado a la transacción, que es el punto.
--
-- 2) EL CASO DEL BUG, en la obra donde se probó la tanda 3:
--    - un borrador con `acuerdo_estado = 'conforme'` sin emitir -> `certificado_conforme` tiene que
--      aparecerle a quien emite en esa obra (con profesional activo: al profesional; sin
--      profesional: al cliente o su apoderado; sin ninguno de los dos: al admin_maestro), y a nadie
--      más;
--    - se emite -> la rama se apaga sola y aparece `certificado_emitido` para el cliente.
--
-- 3) Que NO aparezca donde no corresponde:
--    - borrador en `en_carga` (con o sin propuesta) -> nada de `certificado_conforme`;
--    - borrador `propuesto` -> sigue apareciendo `certificado_propuesto` a quien conforma, y nada
--      más;
--    - obra de un solo usuario (sin contraparte, `acuerdo_estado` se queda en `en_carga`) -> nada,
--      que es lo buscado: no se avisa a alguien de su propio trabajo en curso;
--    - se toca el avance de un borrador ya conformado -> el trigger de la `0124` tira la conformidad
--      abajo y lo devuelve a `en_carga`, así que la rama se apaga y vuelve a esperar la propuesta.
--      Vale la pena probarlo: es la única forma en que este pendiente desaparece sin que nadie emita.
--
-- 4) Que las 13 ramas anteriores sigan devolviendo exactamente lo mismo que antes de aplicar.
