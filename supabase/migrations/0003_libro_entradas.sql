-- Etapa 3 — Roles y Permisos, paso 3: libro_entradas.
-- Ver docs/etapa3_roles_permisos_diseno_datos.md, sección 5, para el diseño completo.
--
-- Tabla única para los 3 "libros" de Gestión de Obra (Libro de Obra, Libro de
-- Órdenes de Servicio, Libro de Notas de Pedido), discriminados por 'libro'.
-- entrada_padre_id modela acuse de recibo / respuesta como entrada hija de la
-- original, sin necesitar una tabla de "acuses" aparte.
--
-- Esta tabla solo referencia obras y auth.users (ya existen) y a sí misma —
-- a diferencia de 0002, no depende de ninguna tabla todavía inexistente.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

create table libro_entradas (
  id uuid primary key default gen_random_uuid(),
  obra_id uuid not null references obras(id) on delete cascade,
  libro text not null check (libro in ('obra','orden_servicio','nota_pedido')),
  autor_usuario_id uuid not null references auth.users(id),
  autor_rol text not null,
  contenido text not null,
  adjuntos jsonb,
  entrada_padre_id uuid references libro_entradas(id),
  created_at timestamptz not null default now()
);
