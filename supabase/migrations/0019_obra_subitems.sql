-- Rubros/APU parte 2 — Migración 6: tabla `obra_subitems` (el cómputo métrico real de una obra),
-- y cierre de la limitación conocida que quedó pendiente en rubros/subitems/apu_composiciones
-- (0015/0016/0018): ahora que existe una tabla real para "qué está tildado en qué obra", se
-- extiende el SELECT de esas 3 para que un colaborador con puede_ver_apu_ajena vea la
-- personalización del dueño, acotada a lo tildado en su obra — tal como preveía el diseño desde
-- el arranque (docs/rubros_apu_diseno_datos.md §2.6).
--
-- Ver docs/rubros_apu_permisos_selector_diseno_datos.md §2.3 para el diseño de obra_subitems.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

create table obra_subitems (
  id uuid primary key default gen_random_uuid(),
  obra_id uuid not null references obras(id) on delete cascade,
  rubro_id uuid not null references rubros(id),      -- agrupación explícita, necesaria para la
                                                       -- fila OTRO (que no tiene subitem_id)
  subitem_id uuid references subitems(id),            -- nullable: null = fila OTRO
  descripcion_libre text,                              -- solo para la fila OTRO
  sector text,                                          -- opcional, distingue repeticiones del
                                                         -- mismo subítem en sectores distintos
  cantidad numeric not null default 0,
  precio_unitario_manual numeric,                       -- null = deriva de APU (rubros con
                                                         -- usa_apu = true); no-null = override
                                                         -- manual, obligatorio para rubros con
                                                         -- usa_apu = false y para la fila OTRO
                                                         -- (no forzado por check — ver nota abajo)
  es_aplicable boolean not null default true,
  agregado_por_usuario_id uuid not null references auth.users(id),
  ultima_modificacion_usuario_id uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),        -- sin trigger, mismo criterio que
                                                          -- apu_composiciones (0018)
  constraint obra_subitems_subitem_xor_libre check (
    (subitem_id is not null and descripcion_libre is null)
    or (subitem_id is null and descripcion_libre is not null)
  )
  -- Sin unique(obra_id, subitem_id): un mismo subítem puede repetirse en sectores distintos de la
  -- misma obra (docs/rubros_apu_diseno_datos.md §3.C).
);

-- "precio_unitario_manual obligatorio cuando rubros.usa_apu = false, o en la fila OTRO" no se
-- fuerza con un check — requeriría mirar la tabla rubros desde un check de obra_subitems, que
-- Postgres no permite sin un trigger. Queda en capa de app por ahora, mismo criterio ya aceptado
-- para el resto de las reglas Free/PRO de esta pieza (decisión G del diseño fundacional).

-- =====================================================================
-- RLS — obra_subitems
-- =====================================================================
--
-- SELECT: is_obra_member (0004_rls_etapa3.sql) — cualquier miembro activo de la obra ve su
-- cómputo. INSERT/UPDATE: admin_maestro/profesional únicamente, vía tiene_rol_en_obra — son los
-- dos roles con "edición total de cómputos" según la matriz de permisos ya cerrada (Constructor
-- es vista operativa sin montos, Cliente es de solo lectura). Esto es independiente de Free/PRO:
-- esa distinción (qué puede tocar un PRO dentro de lo que ya puede editar, ej. composición de APU
-- vs. solo cantidad) sigue siendo capa de app, decisión G del diseño fundacional — no se resuelve
-- acá ni se mezcla con el rol de obra.

alter table obra_subitems enable row level security;

create policy obra_subitems_select on obra_subitems for select
using (is_obra_member(obra_id));

create policy obra_subitems_insert on obra_subitems for insert with check (
  tiene_rol_en_obra(obra_id, 'admin_maestro')
  or tiene_rol_en_obra(obra_id, 'profesional')
);

create policy obra_subitems_update on obra_subitems for update using (
  tiene_rol_en_obra(obra_id, 'admin_maestro')
  or tiene_rol_en_obra(obra_id, 'profesional')
) with check (
  tiene_rol_en_obra(obra_id, 'admin_maestro')
  or tiene_rol_en_obra(obra_id, 'profesional')
);

-- Sin política DELETE: destildar un subítem se modela con es_aplicable = false (no perder la
-- cantidad cargada), no con un borrado real — mismo criterio que otras tablas de este proyecto
-- que prefieren estado sobre borrado (libro_entradas, audit_log, precios).

-- =====================================================================
-- Cierre de la limitación conocida de 0015/0016/0018: visibilidad de colaborador con
-- puede_ver_apu_ajena
-- =====================================================================
--
-- Funciones helper — SECURITY DEFINER + search_path fijo, mismo criterio que
-- is_apu_composicion_owner (0018): no depender de qué tan abierta esté la política de SELECT de
-- obra_subitems/obra_members al evaluarse desde otra tabla.

create or replace function tiene_apu_ajena_visible_por_rubro(p_rubro_id uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select exists (
    select 1 from obra_subitems os
    join obra_members om on om.obra_id = os.obra_id
    where os.rubro_id = p_rubro_id
      and om.usuario_id = auth.uid()
      and om.activo
      and om.puede_ver_apu_ajena
  );
$$;

grant execute on function tiene_apu_ajena_visible_por_rubro(uuid) to authenticated;

create or replace function tiene_apu_ajena_visible_por_subitem(p_subitem_id uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select exists (
    select 1 from obra_subitems os
    join obra_members om on om.obra_id = os.obra_id
    where os.subitem_id = p_subitem_id
      and om.usuario_id = auth.uid()
      and om.activo
      and om.puede_ver_apu_ajena
  );
$$;

grant execute on function tiene_apu_ajena_visible_por_subitem(uuid) to authenticated;

-- rubros (0015_rubros.sql): agrega el caso colaborador a la política ya existente.
alter policy rubros_select on rubros using (
  creador_usuario_id is null
  or creador_usuario_id = auth.uid()
  or tiene_apu_ajena_visible_por_rubro(id)
);

-- subitems (0016_subitems.sql): ídem.
alter policy subitems_select on subitems using (
  creador_usuario_id is null
  or creador_usuario_id = auth.uid()
  or tiene_apu_ajena_visible_por_subitem(id)
);

-- apu_composiciones (0018_apu_composiciones.sql): ídem, matcheando por subitem_id de la propia
-- composición, no por su propio id.
alter policy apu_composiciones_select on apu_composiciones using (
  creador_usuario_id is null
  or creador_usuario_id = auth.uid()
  or tiene_apu_ajena_visible_por_subitem(subitem_id)
);

-- apu_composicion_items (0018): no hace falta tocar su política — ya delega en
-- puede_ver_apu_composicion(), así que alcanza con extender esa función acá.
create or replace function puede_ver_apu_composicion(p_apu_composicion_id uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select exists (
    select 1 from apu_composiciones c
    where c.id = p_apu_composicion_id
      and (
        c.creador_usuario_id is null
        or c.creador_usuario_id = auth.uid()
        or tiene_apu_ajena_visible_por_subitem(c.subitem_id)
      )
  );
$$;

-- =====================================================================
-- Qué queda todavía sin resolver, a propósito
-- =====================================================================
--
-- La FK de modificaciones_obra.subitem_id/apu_privado_id (Etapa 3, ver CLAUDE.md) sigue suelta —
-- es la Migración 7 de este orden, se cierra en un paso aparte. obra_presupuesto_config y
-- obra_impuestos (selector de tipo de presupuesto, impuestos, suelo/zona) tampoco están acá —
-- migración aparte también, no dependen de obra_subitems para nada de su propio diseño.
