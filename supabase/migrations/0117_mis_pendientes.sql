-- Avisos de "algo te espera" (docs/avisos_pendientes_diseno.md, ambigüedades A-D cerradas por Seba
-- 2026-09-12): una función que devuelve, para el usuario logueado y en todas sus obras, cada cosa
-- que espera SU acción. La lee el dashboard al abrir la app (cartel + contador por obra). Sin tabla
-- nueva, sin estado de "visto", sin push -- solo lectura de lo que ya está en cada tabla.
--
-- Criterio central: cada rama filtra con LA MISMA autoridad que usa la transición que resuelve esa
-- espera (la función, o el mismo chequeo de roles copiado de ella). Así el aviso nunca muestra algo
-- que el usuario no puede resolver, ni esconde algo que sí. Armarlo en Dart con UserContext obra por
-- obra sería otra copia de la autoridad -- el tipo de copia que ya divergió una vez (delegación sin
-- fechas, docs/adicionales_quitas_demasias_diagnostico.md §13.4).
--
-- Qué entra (§2 y §4 del doc):
-- - adicional pendiente, de monto fijo o presupuestado YA ENVIADO (uno en preparación no espera a
--   nadie más que a quien lo arma, §4-D), para quien puede APROBARLO con su monto -- un apoderado
--   con el tope superado no lo ve, el cliente principal sí (§4-B) -- `puede_aprobar_adicional`, 0116;
-- - quita/demasía pendiente, para profesional/constructor -- `puede_aprobar_quita_demasia`, 0109 --
--   salvo para quien la cargó, a menos que sea el único profesional/constructor activo de la obra
--   (si no, nadie la vería y quedaría colgada, §4-C);
-- - certificado emitido sin leer: cliente_principal o apoderado -- `marcar_certificado_leido`, 0011;
-- - certificado leído sin pagar: `puede_gestionar_certificado(obra, monto)` -- `marcar_certificado_
--   pagado`, 0011 (con el tope del apoderado, igual que la transición);
-- - certificado pagado sin cerrar: admin_maestro o constructor -- `marcar_certificado_impactado`, 0011;
-- - anulación propuesta: profesional o constructor, nunca quien la propuso --
--   `resolver_anulacion_certificado` (0056/0111), que ya lo prohíbe; acá no hay excepción de "único",
--   porque la transición misma no la tiene;
-- - firma física pendiente (sumada por Seba en §4-A: "tiene su cartel pero está adentro de la obra"):
--   admin_maestro o profesional -- `subir_pdf_firmado_certificado`, 0011 -- en un certificado ya
--   emitido y no anulado.
--
-- Solo obras reales (`obra_madre_id is null`): lo de un adicional presupuestado vive en la madre, y
-- una obra hija no certifica ni tiene quitas/demasías (sin solapa Gestión de Obra).
--
-- SECURITY DEFINER porque lee tablas de varias obras de una vez; el acotamiento a "mis obras" (CTE
-- `mis_obras`, membresía activa) y cada chequeo de autoridad dependen de auth.uid() -- con anon, o
-- sin sesión, devuelve 0 filas. Revocada a anon de todos modos (lección de la 0085/0115).
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor), después de 0116. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

create or replace function mis_pendientes()
returns table(
  obra_id uuid,
  obra_nombre text,
  tipo text,                -- adicional | quita | demasia | certificado_emitido | certificado_leido
                            -- | certificado_pagado | anulacion | firma_fisica
  entidad_id uuid,          -- modificaciones_obra.id o certificados.id, según tipo
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

  order by 8;
$$;

grant execute on function mis_pendientes() to authenticated;
revoke execute on function mis_pendientes() from public, anon;

-- =====================================================================
-- Verificación
-- =====================================================================
--
-- La función depende de auth.uid(): en el SQL Editor (sin sesión) tiene que devolver 0 filas -- ese
-- es el primer chequeo. La prueba real es en la app, con dos usuarios.
--
-- 1) SQL Editor: `select * from mis_pendientes();` -- 0 filas, sin error.
-- 2) Adicional: enviado para aprobación -> aparece al cliente principal, no a quien lo cotiza. En
--    preparación (sin enviar) -> no le aparece a nadie. Apoderado con tope menor al monto -> no le
--    aparece; con tope mayor -> sí.
-- 3) Quita/demasía: cargada por el profesional en una obra con constructor -> aparece al
--    constructor, no al profesional. En una obra donde el profesional es el único
--    profesional/constructor -> le aparece a él.
-- 4) Certificados: emitido -> aparece al cliente; marcado leído -> pasa a "sin pagar" para el
--    cliente; pagado -> pasa a admin/constructor; cerrado -> desaparece de todos.
-- 5) Anulación propuesta por el profesional -> aparece al constructor, nunca al profesional.
-- 6) Firma física: certificado emitido con firma física -> aparece a admin/profesional hasta que se
--    sube el PDF.
-- 7) `select has_function_privilege('anon', 'mis_pendientes()', 'EXECUTE');` -> false.
