-- Ciclo de vida del Certificado de Obra (5 estados, Modelo A), paso 1: tabla certificados +
-- columnas nuevas en obras + RLS.
-- Ver docs/certificados_ciclo_vida_diseno_datos.md, secciones 3, 4 y 7, para el diseño completo.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.
--
-- Nota de alcance: obra_modelo_es() estaba planeada para el paso 2 (funciones de transición,
-- docs/certificados_ciclo_vida_diseno_datos.md §11), pero la política INSERT de certificados de
-- acá abajo ya la necesita para el guard "solo Modelo A" (§2 del diseño) — se adelanta a este
-- archivo para no dejar la tabla sin ese guard ni un momento, mismo criterio de "RLS desde la
-- creación" que ya se usó para hitos_certificacion.

-- =====================================================================
-- obras: columnas nuevas
-- =====================================================================

alter table obras
  add column dias_plazo_pago_certificados int,
  add column anticipo_pct numeric,
  add column fondo_reparo_pct numeric;

-- =====================================================================
-- obra_modelo_es: helper SECURITY DEFINER, adelantado del paso 2 (ver nota de alcance arriba)
-- =====================================================================
--
-- Mismo motivo que ya tienen is_obra_member/tiene_rol_en_obra (0004_rls_etapa3.sql): si el guard
-- hiciera un select directo contra obras dentro de una política de certificados, esa subconsulta
-- quedaría sujeta a la política SELECT de obras (que no tiene migración propia en este repo) en
-- vez de resolverse de forma directa.

create or replace function obra_modelo_es(p_obra_id uuid, p_modelo text)
returns boolean language sql security definer set search_path = public stable as $$
  select exists (select 1 from obras where id = p_obra_id and modelo_certificacion = p_modelo);
$$;

grant execute on function obra_modelo_es(uuid, text) to authenticated;

-- =====================================================================
-- certificados
-- =====================================================================

create table certificados (
  id uuid primary key default gen_random_uuid(),
  obra_id uuid not null references obras(id) on delete cascade,
  numero int not null,
  periodo text not null,
  monto numeric not null check (monto > 0),
  estado text not null default 'borrador'
    check (estado in ('borrador', 'emitido', 'leido', 'pagado', 'impactado_cerrado')),

  creado_por uuid not null references auth.users(id),
  fecha_creacion timestamptz not null default now(),

  -- Emitido
  fecha_emision timestamptz,
  emitido_por uuid references auth.users(id),
  dias_plazo_pago int,
  requiere_firma_fisica boolean,

  -- Leído por Propietario
  fecha_lectura timestamptz,
  leido_por uuid references auth.users(id),

  -- Pagado
  fecha_pago timestamptz,
  pagado_por uuid references auth.users(id),
  medio_pago text check (medio_pago is null or medio_pago in ('transferencia', 'efectivo', 'cheque', 'otro')),
  comprobante_pago_adjuntos text[] not null default '{}',

  -- Anticipo / Fondo de Reparo — snapshot al emitir
  anticipo_pct_aplicado numeric,
  fondo_reparo_pct_aplicado numeric,
  monto_anticipo_descontado numeric,
  monto_fondo_reparo_retenido numeric,
  monto_neto_a_pagar numeric,

  -- Impactado y Cerrado
  fecha_impacto timestamptz,
  impactado_por uuid references auth.users(id),
  factura_final_adjuntos text[] not null default '{}',

  -- Firma física (independiente del estado del ciclo)
  pdf_firmado_subido boolean not null default false,
  pdf_firmado_fecha timestamptz,
  pdf_firmado_adjuntos text[] not null default '{}',

  unique (obra_id, numero),

  check (estado not in ('emitido', 'leido', 'pagado', 'impactado_cerrado') or fecha_emision is not null),
  check (estado not in ('leido', 'pagado', 'impactado_cerrado') or fecha_lectura is not null),
  check (estado not in ('pagado', 'impactado_cerrado') or fecha_pago is not null),
  check (estado <> 'impactado_cerrado' or fecha_impacto is not null)
);

-- =====================================================================
-- RLS
-- =====================================================================

alter table certificados enable row level security;

-- SELECT: abierto a cualquier miembro de la obra, mismo patrón que el resto de Etapa 3+.
create policy certificados_select on certificados for select
using (is_obra_member(obra_id));

-- INSERT: admin_maestro, profesional o constructor (el Constructor puede cargar/solicitar un
-- borrador, mismo criterio ya documentado en CLAUDE.md para Gestión de Obra), solo pueden
-- autoasignarse como creado_por, y solo si la obra está en Modelo A (certificados no aplica bajo
-- Modelo B, que usa hitos_certificacion — docs/certificados_ciclo_vida_diseno_datos.md §2).
create policy certificados_insert on certificados for insert with check (
  creado_por = auth.uid()
  and (
    tiene_rol_en_obra(obra_id, 'admin_maestro')
    or tiene_rol_en_obra(obra_id, 'profesional')
    or tiene_rol_en_obra(obra_id, 'constructor')
  )
  and obra_modelo_es(obra_id, 'avance_medido')
);

-- UPDATE: dos niveles, según el estado actual de la fila.
--
-- Mientras sigue en 'borrador': edición manual directa (monto/periodo), reservada a los mismos 3
-- roles que pueden crearlo — mismo paralelo que un certificado en Borrador siendo editable.
--
-- Una vez fuera de 'borrador': el conjunto de roles se amplía porque las transiciones siguientes
-- (emitir, leer, pagar, impactar) involucran actores distintos entre sí (Profesional emite,
-- Cliente/Apoderado lee y paga, Constructor impacta) — la corrección fina de cuál de ellos puede
-- hacer cuál transición puntual la resuelven las funciones (emitir_certificado,
-- marcar_certificado_leido, marcar_certificado_pagado, marcar_certificado_impactado,
-- docs/certificados_ciclo_vida_diseno_datos.md §7), no esta política. Limitación conocida, mismo
-- patrón ya aceptado para modificaciones_obra/aprobar_ajuste_contrato (0008): esta política no
-- impide que alguien con alguno de estos roles haga un UPDATE directo fuera de las funciones
-- sancionadas, dejando el certificado en un estado inconsistente (por ejemplo, sin el audit_log
-- correspondiente) si evita llamarlas.
create policy certificados_update on certificados for update using (
  (estado = 'borrador' and (
    tiene_rol_en_obra(obra_id, 'admin_maestro')
    or tiene_rol_en_obra(obra_id, 'profesional')
    or tiene_rol_en_obra(obra_id, 'constructor')
  ))
  or (estado <> 'borrador' and (
    tiene_rol_en_obra(obra_id, 'admin_maestro')
    or tiene_rol_en_obra(obra_id, 'profesional')
    or tiene_rol_en_obra(obra_id, 'constructor')
    or tiene_rol_en_obra(obra_id, 'cliente_principal')
    or tiene_rol_en_obra(obra_id, 'invitado_apoderado')
  ))
) with check (
  tiene_rol_en_obra(obra_id, 'admin_maestro')
  or tiene_rol_en_obra(obra_id, 'profesional')
  or tiene_rol_en_obra(obra_id, 'constructor')
  or tiene_rol_en_obra(obra_id, 'cliente_principal')
  or tiene_rol_en_obra(obra_id, 'invitado_apoderado')
);

-- Sin política DELETE: registro financiero/legal, append-only, mismo criterio que el resto de
-- Etapa 3+.
