-- Rubros: orden por obra — Etapa A (base de datos) de la pieza "código vs. número impreso,
-- reordenamiento por obra". Ver docs/rubros_orden_diseno_datos.md para el diseño completo.
--
-- Separa la identidad fija de un rubro (rubros.codigo, sin tocar) del número que se muestra en
-- pantalla e imprime, que pasa a ser puramente posicional y calculado por obra. Esta tabla guarda
-- SOLO los overrides explícitos (un rubro que alguien arrastró a mano en esa obra puntual) — una
-- obra sin ninguna fila acá sigue funcionando con el orden default de siempre (oficiales por
-- rubros.orden, propios después), sin necesitar backfill ni configuración.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

create table obra_rubros_orden (
  id uuid primary key default gen_random_uuid(),
  obra_id uuid not null references obras(id) on delete cascade,
  rubro_id uuid not null references rubros(id) on delete cascade,  -- on delete cascade a propósito,
                                                                     -- a diferencia de
                                                                     -- obra_subitems.rubro_id (sin
                                                                     -- cascade, protege cantidades
                                                                     -- cargadas): esto es una
                                                                     -- preferencia de orden, no un
                                                                     -- dato del usuario.
  posicion numeric not null,
  -- Indexación fraccionaria (mismo patrón que Trello/Linear/Figma): al reordenar, se calcula el
  -- punto medio entre los dos vecinos nuevos y se hace un solo upsert sobre esta fila — nunca hay
  -- que reescribir el resto de la lista. numeric (no double) para no perder precisión reordenando
  -- muchas veces en el mismo hueco. Los rubros sin fila acá usan un default calculado en la app,
  -- nunca persistido (rubros.orden * 1000 para oficiales; created_at para propios sin override, ver
  -- doc §2.2/§3).
  updated_at timestamptz not null default now(),
  updated_by_usuario_id uuid references auth.users(id),
  unique (obra_id, rubro_id)
);

-- =====================================================================
-- RLS
-- =====================================================================
--
-- Mismo patrón que obra_subitems (0019_obra_subitems.sql): reordenar el cómputo de una obra es una
-- acción de edición, misma autoridad que tildar/cargar cantidades — admin_maestro/profesional.
-- Constructor (vista operativa) no reordena, igual que no edita cómputo. Sin política DELETE para
-- el usuario: el on delete cascade de las FKs de arriba limpia solo cuando se borra la obra o el
-- rubro.

alter table obra_rubros_orden enable row level security;

create policy obra_rubros_orden_select on obra_rubros_orden for select
using (is_obra_member(obra_id));

create policy obra_rubros_orden_insert on obra_rubros_orden for insert with check (
  tiene_rol_en_obra(obra_id, 'admin_maestro')
  or tiene_rol_en_obra(obra_id, 'profesional')
);

create policy obra_rubros_orden_update on obra_rubros_orden for update using (
  tiene_rol_en_obra(obra_id, 'admin_maestro')
  or tiene_rol_en_obra(obra_id, 'profesional')
) with check (
  tiene_rol_en_obra(obra_id, 'admin_maestro')
  or tiene_rol_en_obra(obra_id, 'profesional')
);

-- =====================================================================
-- Qué queda fuera de esta migración, a propósito
-- =====================================================================
--
-- Ningún cambio a rubros.codigo, a la migración 0025 (unicidad global de código, sigue vigente sin
-- tocar) ni a ningún archivo de lib/ — esta es solo la Etapa A (base de datos) de 5. Las Etapas B/C
-- (lectura del orden mezclado + drag-and-drop real en RubrosTab) y D (sacar el campo Código del
-- alta, generarlo server-side) son pasos aparte, ver docs/rubros_orden_diseno_datos.md §4.
