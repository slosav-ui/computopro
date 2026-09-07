-- Importador de Excel/PDF — Capa 1 + el recorte de Capa 2 §1: tablas `importaciones` /
-- `importaciones_items`, bucket de Storage para el archivo original, y RLS.
-- Ver docs/importador_capa1_diseno_datos.md (schema base, 7 ambigüedades cerradas 2026-08-22) y
-- docs/importador_capa2_diseno_datos.md §1 (los 3 recortes de esta ronda) para el diseño completo
-- — no se repite el razonamiento acá.
--
-- Diferencias respecto al schema de Capa 1, todas por §1 de Capa 2:
--   - obra_id pasa de nullable a NOT NULL — se importa sobre una obra ya elegida/creada, nunca
--     "suelta". La rama de RLS para obra_id null (Capa 1 §2.3, segundo párrafo) queda afuera de
--     esta migración a propósito: el día que la estimación sin obra se diseñe de verdad, esa rama
--     se agrega en su propia migración, no se adivina ahora.
--   - Sin columna ni mecanismo de límite mensual Free (Capa 1 §2.5/§3.C): el importador es
--     exclusivo de PRO (docs/importador_capa2_diseno_datos.md §1), mismo criterio que ya cerró el
--     Factor K (docs/monetizacion.md §9) — el gate es `perfiles.es_pro`, verificado en vivo desde
--     la app antes de subir un archivo, igual que el resto de las funciones PRO del proyecto. No
--     se fuerza en RLS: es la misma decisión ya aceptada para el resto del catálogo Free/PRO
--     (docs/rubros_apu_diseno_datos.md §3.G) — sin tabla de plan/suscripción todavía de la cual
--     colgar un chequeo a nivel de base.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

create table importaciones (
  id uuid primary key default gen_random_uuid(),
  obra_id uuid not null references obras(id) on delete cascade,
  usuario_id uuid not null references auth.users(id),
  archivo_nombre text not null,
  archivo_storage_path text not null,
  tipo_archivo text not null check (tipo_archivo in ('excel','pdf','foto')),
  hojas_seleccionadas text[],
  moneda_default text check (moneda_default is null or moneda_default in ('ARS','USD')),
  estado text not null default 'pendiente_revision'
    check (estado in ('pendiente_revision','confirmado','descartado')),
  pct_avance_manual numeric,
  monto_certificado_manual numeric,
  confianza_general text check (confianza_general is null or confianza_general in ('alta','media','baja')),
  confirmado_por_usuario_id uuid references auth.users(id),
  confirmado_at timestamptz,
  created_at timestamptz not null default now()
);

create table importaciones_items (
  id uuid primary key default gen_random_uuid(),
  importacion_id uuid not null references importaciones(id) on delete cascade,
  orden int not null,
  rubro_texto text,
  descripcion_texto text,
  unidad_texto text,
  cantidad numeric,
  precio_unitario numeric,
  moneda text check (moneda is null or moneda in ('ARS','USD')),
  datos_originales jsonb,
  -- Reservado para la migración siguiente (0081_confirmar_importacion.sql): sin FK activa todavía
  -- acá, se agrega junto con la función de confirmación — mismo orden que ya usó
  -- 0021_modificaciones_obra_fks.sql para cerrar una FK reservada después de que la tabla de
  -- destino existiera.
  rubro_id uuid,
  subitem_id uuid,
  created_at timestamptz not null default now()
);

-- =====================================================================
-- RLS — importaciones / importaciones_items
-- =====================================================================
--
-- Una sola rama (obra_id siempre cargado en esta ronda, ver nota de cabecera). Mismo criterio ya
-- cerrado para obra_subitems (0019): SELECT abierto a cualquier miembro de la obra,
-- INSERT/UPDATE restringido a admin_maestro/profesional (Constructor no edita cómputo/precios).
-- Sin política DELETE: descartar una importación es estado='descartado', no un borrado físico —
-- mismo criterio append-only que el resto del proyecto.

alter table importaciones enable row level security;

create policy importaciones_select on importaciones for select
using (is_obra_member(obra_id));

create policy importaciones_insert on importaciones for insert with check (
  usuario_id = auth.uid()
  and (tiene_rol_en_obra(obra_id, 'admin_maestro') or tiene_rol_en_obra(obra_id, 'profesional'))
);

create policy importaciones_update on importaciones for update using (
  tiene_rol_en_obra(obra_id, 'admin_maestro') or tiene_rol_en_obra(obra_id, 'profesional')
) with check (
  tiene_rol_en_obra(obra_id, 'admin_maestro') or tiene_rol_en_obra(obra_id, 'profesional')
);

alter table importaciones_items enable row level security;

-- importaciones_items no tiene obra_id propio -- se resuelve vía el header, mismo patrón que
-- apu_composicion_items delegando en puede_ver_apu_composicion (0018).
create policy importaciones_items_select on importaciones_items for select
using (
  exists (
    select 1 from importaciones i
    where i.id = importacion_id and is_obra_member(i.obra_id)
  )
);

create policy importaciones_items_insert on importaciones_items for insert with check (
  exists (
    select 1 from importaciones i
    where i.id = importacion_id
      and (tiene_rol_en_obra(i.obra_id, 'admin_maestro') or tiene_rol_en_obra(i.obra_id, 'profesional'))
  )
);

create policy importaciones_items_update on importaciones_items for update using (
  exists (
    select 1 from importaciones i
    where i.id = importacion_id
      and (tiene_rol_en_obra(i.obra_id, 'admin_maestro') or tiene_rol_en_obra(i.obra_id, 'profesional'))
  )
) with check (
  exists (
    select 1 from importaciones i
    where i.id = importacion_id
      and (tiene_rol_en_obra(i.obra_id, 'admin_maestro') or tiene_rol_en_obra(i.obra_id, 'profesional'))
  )
);

-- =====================================================================
-- Storage — bucket privado para el archivo original (decisión §3.F de Capa 1)
-- =====================================================================
--
-- Convención de path obligatoria para que la RLS de abajo funcione: `archivo_storage_path` =
-- '{obra_id}/{uuid}-{archivo_nombre}' -- el primer segmento del path SIEMPRE tiene que ser el
-- obra_id de la importación (texto plano, no el id de la fila). Lo hace cumplir la propia Edge
-- Function al subir el archivo, antes de insertar la fila en `importaciones`.

insert into storage.buckets (id, name, public)
values ('importaciones', 'importaciones', false)
on conflict (id) do nothing;

create policy importaciones_storage_select on storage.objects for select using (
  bucket_id = 'importaciones'
  and is_obra_member((storage.foldername(name))[1]::uuid)
);

create policy importaciones_storage_insert on storage.objects for insert with check (
  bucket_id = 'importaciones'
  and (
    tiene_rol_en_obra((storage.foldername(name))[1]::uuid, 'admin_maestro')
    or tiene_rol_en_obra((storage.foldername(name))[1]::uuid, 'profesional')
  )
);

-- Sin política UPDATE/DELETE sobre el bucket: mismo criterio append-only que las tablas de arriba
-- -- un archivo subido no se reemplaza ni se borra, una importación descartada simplemente deja
-- de usarse.
