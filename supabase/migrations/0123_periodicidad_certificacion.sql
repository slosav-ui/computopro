-- 0123 -- Periodicidad de certificación pactada + aviso de "ya se puede certificar"
--
-- Tanda 1 de "certificar es un acuerdo entre partes" (pedido de Seba, 2026-09-13). Diseño completo,
-- decisiones y el resto de las tandas: docs/certificacion_acuerdo_partes_diagnostico.md §3.1.
--
-- Qué resuelve: la obra pacta de antemano cada cuánto se certifica (semanal, quincenal, mensual) y
-- cuando llega el momento la app avisa. Hasta acá no existía NINGUNA noción de periodicidad -- lo
-- que había y se confunde es `obras.dias_plazo_pago_certificados`, que es cada cuánto se PAGA un
-- certificado ya emitido, no cada cuánto se certifica (y `certificados.periodo` es texto libre,
-- tipeado a mano).
--
-- Por qué es la primera tanda: no toca ninguna transición del ciclo (emitir, leer, pagar, cerrar,
-- anular) ni ningún cálculo de avance. Agrega una columna, un helper de lectura y una rama más en
-- `mis_pendientes()`. El resto de la pieza (el acuerdo entre partes, la objeción del cliente, el
-- avance global) va en tandas siguientes, y la única que cambia RLS es la del acuerdo.
--
-- Se puede aplicar ANTES de tocar el Dart: `Pendiente.desdeRow` (0117) devuelve null para un `tipo`
-- que la app no conoce y saltea esa fila, así que la app vigente no se entera de la rama nueva.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project -> SQL Editor), después de `0122`. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

-- =====================================================================
-- Paso 1 -- la columna, al lado de las otras de certificación de `obras`
-- =====================================================================
--
-- En `obras` y no en una tabla nueva: es config de la obra, y ahí ya viven
-- `dias_plazo_pago_certificados`, `anticipo_pct`, `fondo_reparo_pct`, `modelo_certificacion` y
-- `monto_total_contratado`, que es exactamente el grupo que administra el mismo panel
-- (`ObraConfigCertificacionRepository` -- que a pesar del nombre NO es una tabla, lee estas
-- columnas). Nullable a propósito: null = no se pactó periodicidad, y entonces no hay aviso.

alter table obras
  add column periodicidad_certificacion text
    check (periodicidad_certificacion is null
           or periodicidad_certificacion in ('semanal', 'quincenal', 'mensual'));

comment on column obras.periodicidad_certificacion is
  'Cada cuanto se certifica, pactado de antemano (0123): semanal | quincenal | mensual. null = sin '
  'pactar, sin aviso. NO confundir con dias_plazo_pago_certificados, que es cada cuanto se paga un '
  'certificado ya emitido.';

-- =====================================================================
-- Paso 2 -- proximo_periodo_certificacion: cuándo vence el próximo período
-- =====================================================================
--
-- El ancla se calcula, no se configura -- el dato ya está en la base:
--   1) el último certificado emitido de la obra (excluyendo los anulados, que no certificaron
--      nada), más el intervalo de la periodicidad;
--   2) si no hay ninguno, el congelamiento del presupuesto, más el intervalo;
--   3) si la obra no está congelada, null -- sin contrato firmado no hay período que correr.
--
-- Por intervalo desde el ancla, no por corte de calendario (fin de mes): decisión de alcance
-- anotada en §3.1 del diseño. Si el uso real pide "siempre los días 30", es una columna más y un
-- `case` acá.
--
-- SECURITY DEFINER con guard de membresía, mismo criterio que `calcular_monto_obra_subitems`
-- (0105): necesita leer `obras`/`certificados` sin quedar sujeta a sus políticas cuando la llama
-- `mis_pendientes()`, y devuelve null a quien no es miembro de la obra para no filtrar nada a quien
-- pruebe llamarla directo.

create or replace function proximo_periodo_certificacion(p_obra_id uuid)
returns timestamptz
language sql
security definer
set search_path = public
stable
as $$
  select case o.periodicidad_certificacion
           when 'semanal' then v_ancla.ancla + interval '7 days'
           when 'quincenal' then v_ancla.ancla + interval '15 days'
           when 'mensual' then v_ancla.ancla + interval '1 month'
         end
  from obras o
  cross join lateral (
    select coalesce(
      (select max(c.fecha_emision)
         from certificados c
        where c.obra_id = o.id and c.estado <> 'anulado' and c.fecha_emision is not null),
      o.presupuesto_congelado_en
    ) as ancla
  ) as v_ancla
  where o.id = p_obra_id
    and is_obra_member(p_obra_id)
    and o.periodicidad_certificacion is not null
    and v_ancla.ancla is not null;
$$;

grant execute on function proximo_periodo_certificacion(uuid) to authenticated;
revoke execute on function proximo_periodo_certificacion(uuid) from public, anon;

-- =====================================================================
-- Paso 3 -- mis_pendientes(): una rama más
-- =====================================================================
--
-- Cuerpo vigente de 0117 copiado tal cual, con la rama nueva agregada antes del `order by` y el
-- comentario de la firma actualizado. Ninguna otra línea cambia.

create or replace function mis_pendientes()
returns table(
  obra_id uuid,
  obra_nombre text,
  tipo text,                -- adicional | quita | demasia | certificado_emitido | certificado_leido
                            -- | certificado_pagado | anulacion | firma_fisica | certificacion_periodo
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

  order by 8;
$$;

grant execute on function mis_pendientes() to authenticated;

-- =====================================================================
-- Verificación a mano después de aplicar (SQL Editor)
-- =====================================================================
--
-- 1) La columna y su check:
--    select column_name, data_type, is_nullable from information_schema.columns
--    where table_name = 'obras' and column_name = 'periodicidad_certificacion';
--    update obras set periodicidad_certificacion = 'trimestral' where id = '<obra_id>';
--    -- tiene que fallar por el check; 'mensual' tiene que pasar.
--
-- 2) El helper, en una obra congelada sin certificados emitidos:
--    update obras set periodicidad_certificacion = 'mensual' where id = '<obra_id>';
--    select presupuesto_congelado_en, proximo_periodo_certificacion(id) from obras where id = '<obra_id>';
--    -- el segundo = el primero + 1 mes. Ojo: desde el SQL Editor corre como service_role sin
--    -- usuario logueado, así que `is_obra_member` da false y devuelve null -- esto se verifica
--    -- desde la app, o con `set local role authenticated` y un `request.jwt.claims` armado. Lo que
--    -- SÍ se puede verificar acá es el punto 3 con un usuario real desde la app.
--
-- 3) El aviso, desde la app con un usuario que sea admin_maestro/profesional/constructor de una obra
--    congelada, con periodicidad pactada y SIN borrador en curso:
--    select tipo, obra_nombre, descripcion, desde from mis_pendientes();
--    -- tiene que aparecer una fila 'certificacion_periodo' con descripcion = la periodicidad, en
--    -- cuanto el período esté vencido.
--
-- 4) Que el aviso se calle cuando corresponde (las 4 condiciones, una por una):
--    - crear un borrador en esa obra -> la fila desaparece;
--    - borrar el borrador -> vuelve;
--    - periodicidad_certificacion = null -> desaparece;
--    - emitir un certificado -> desaparece hasta que venza el período siguiente.
--
-- 5) Que no rompió nada de lo que ya avisaba: con un adicional pendiente, un certificado emitido sin
--    leer y uno pagado sin cerrar, `mis_pendientes()` tiene que seguir devolviendo esas filas igual
--    que antes, ordenadas por `desde`.
