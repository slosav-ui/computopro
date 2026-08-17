-- Etapa 3 — Roles y Permisos, paso 1: tabla obra_members.
-- Ver docs/etapa3_roles_permisos_diseno_datos.md, sección 2, para el diseño completo.
--
-- Roles combinables por (obra, usuario): una fila por (obra_id, usuario_id, rol).
-- Combinar roles = insertar varias filas para el mismo usuario en la misma obra.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

create table obra_members (
  id uuid primary key default gen_random_uuid(),
  obra_id uuid not null references obras(id) on delete cascade,
  usuario_id uuid not null references auth.users(id),
  rol text not null check (rol in (
    'admin_maestro','profesional','constructor',
    'cliente_principal','invitado_veedor','invitado_apoderado'
  )),
  invitado_por_usuario_id uuid references auth.users(id),
  activo boolean not null default true,
  puede_aprobar_certificados boolean not null default false,
  puede_aprobar_adicionales boolean not null default false,
  tope_monto_aprobacion numeric,
  delegacion_inicio timestamptz,
  delegacion_fin timestamptz,
  puede_invitar_terceros boolean not null default false,
  puede_ver_apu_ajena boolean not null default false,
  created_at timestamptz not null default now(),
  unique (obra_id, usuario_id, rol)
);
