-- Etapa 3 — Roles y Permisos, paso 2: modificaciones_obra + audit_log.
-- Ver docs/etapa3_roles_permisos_diseno_datos.md, sección 4, para el diseño completo.
--
-- modificaciones_obra: Adicionales/Demasías/Quitas dentro de Gestión de Obra.
-- audit_log: historial inmutable de transiciones, genérico y reusable (no una
-- tabla de auditoría por feature) — sirve para modificaciones_obra hoy y para
-- certificados/delegaciones de firma/moderación de contenido más adelante.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.
--
-- subitem_id y apu_privado_id se dejan como uuid sueltos, SIN foreign key: las
-- tablas subitems y de APU todavía no existen en Supabase (son alcance de la
-- Solapa 2, futura, no de esta Etapa 3). Cuando esas tablas existan, agregar las
-- FKs en una migración aparte, por ejemplo:
--   alter table modificaciones_obra
--     add constraint modificaciones_obra_subitem_id_fkey
--     foreign key (subitem_id) references subitems(id);
--   alter table modificaciones_obra
--     add constraint modificaciones_obra_apu_privado_id_fkey
--     foreign key (apu_privado_id) references apu(id); -- nombre de tabla a confirmar

create table modificaciones_obra (
  id uuid primary key default gen_random_uuid(),
  obra_id uuid not null references obras(id) on delete cascade,
  tipo text not null check (tipo in ('adicional','demasia','quita')),
  subitem_id uuid,                         -- FK futura, cuando exista la tabla subitems (Solapa 2, ver nota abajo)
  descripcion text not null,
  cantidad numeric not null,
  precio_unitario_heredado numeric,
  monto_total numeric not null,
  apu_privado_id uuid,                     -- FK futura, cuando exista la tabla de APU
  solicitado_por uuid not null references auth.users(id),
  subido_por uuid not null references auth.users(id),
  estado text not null default 'pendiente' check (estado in ('pendiente','devuelto','aprobado','rechazado')),
  aprobado_por uuid references auth.users(id),
  fecha_solicitud timestamptz not null default now(),
  fecha_resolucion timestamptz,
  comentario_resolucion text
);

create table audit_log (
  id uuid primary key default gen_random_uuid(),
  obra_id uuid references obras(id) on delete cascade,
  usuario_id uuid not null references auth.users(id),
  ip inet,
  accion text not null,              -- ej. 'aprobar_adicional', 'rechazar_adicional', 'devolver_adicional'
  entidad text not null,             -- ej. 'modificacion_obra', 'certificado', 'delegacion_firma'
  entidad_id uuid,
  detalle jsonb,
  created_at timestamptz not null default now()
);
