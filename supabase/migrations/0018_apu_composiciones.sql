-- Rubros/APU parte 2 — Migración 5: tablas `apu_composiciones` + `apu_composicion_items`,
-- SOLO SCHEMA — sin sembrar ninguna composición real todavía (queda para un paso aparte, una vez
-- que el usuario expanda el catálogo de `insumos` y limpie a mano los nombres con caracteres
-- corruptos del archivo original — no se completan ni se adivinan acá).
-- Ver docs/rubros_apu_diseno_datos.md §2.4 y §2.6 para el diseño completo — la política de RLS
-- de esta pieza es, según ese diseño, la más delicada de toda la parte 2.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

create table apu_composiciones (
  id uuid primary key default gen_random_uuid(),
  subitem_id uuid not null references subitems(id) on delete cascade,
  creador_usuario_id uuid references auth.users(id),  -- null = receta oficial
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),      -- sin trigger que lo mantenga: ningún otro
                                                        -- lado del proyecto usa ese patrón hoy, se
                                                        -- deja a cargo de la app por ahora
  unique (subitem_id, creador_usuario_id)
);

-- OJO — detalle que corrige una imprecisión del diseño original ("único, null tratado como valor
-- propio"): en Postgres, un `unique(subitem_id, creador_usuario_id)` NO alcanza para garantizar
-- "una sola receta oficial por subítem", porque dos NULL nunca se consideran iguales entre sí en
-- una restricción unique — permitiría insertar dos filas oficiales para el mismo subítem sin
-- violar nada. El unique de arriba sí protege bien el caso de un mismo usuario (creador_usuario_id
-- no nulo) con dos recetas propias para el mismo subítem. Falta el índice único parcial de abajo
-- para cerrar el caso oficial — mismo patrón ya usado en rubros/subitems (0015/0016).
create unique index apu_composiciones_oficial_unique on apu_composiciones (subitem_id)
  where creador_usuario_id is null;

create table apu_composicion_items (
  id uuid primary key default gen_random_uuid(),
  apu_composicion_id uuid not null references apu_composiciones(id) on delete cascade,
  tipo_componente text not null check (tipo_componente in ('material', 'mano_obra', 'equipo')),
  insumo_id uuid not null references insumos(id),
  rendimiento numeric not null check (rendimiento >= 0),
  created_at timestamptz not null default now()
);

-- =====================================================================
-- Funciones helper para la RLS de apu_composicion_items
-- =====================================================================
--
-- apu_composicion_items no tiene su propio creador_usuario_id — la dueñez se hereda de
-- apu_composiciones vía apu_composicion_id, así que la política necesita un join, no una
-- comparación directa de columna. SECURITY DEFINER + search_path fijo por el mismo motivo que
-- is_corralon_owner (0013_rls_proveedores_precios.sql): no depender de que la política de SELECT
-- de apu_composiciones se mantenga como está si se ajusta más adelante.

create or replace function is_apu_composicion_owner(p_apu_composicion_id uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select exists (
    select 1 from apu_composiciones c
    where c.id = p_apu_composicion_id and c.creador_usuario_id = auth.uid()
  );
$$;

grant execute on function is_apu_composicion_owner(uuid) to authenticated;

create or replace function puede_ver_apu_composicion(p_apu_composicion_id uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select exists (
    select 1 from apu_composiciones c
    where c.id = p_apu_composicion_id
      and (c.creador_usuario_id is null or c.creador_usuario_id = auth.uid())
  );
$$;

grant execute on function puede_ver_apu_composicion(uuid) to authenticated;

-- =====================================================================
-- RLS — apu_composiciones
-- =====================================================================
--
-- Mismo patrón dueño-nullable que rubros/subitems/insumos: filas oficiales (creador_usuario_id is
-- null) con SELECT abierto a cualquier autenticado, sin política de escritura. Filas
-- personalizadas: el dueño ve, crea, edita y borra las suyas.

alter table apu_composiciones enable row level security;

create policy apu_composiciones_select on apu_composiciones for select
using (
  creador_usuario_id is null
  or creador_usuario_id = auth.uid()
);

create policy apu_composiciones_insert on apu_composiciones for insert with check (
  creador_usuario_id = auth.uid()
);

create policy apu_composiciones_update on apu_composiciones for update using (
  creador_usuario_id = auth.uid()
) with check (
  creador_usuario_id = auth.uid()
);

create policy apu_composiciones_delete on apu_composiciones for delete using (
  creador_usuario_id = auth.uid()
);

-- =====================================================================
-- RLS — apu_composicion_items
-- =====================================================================

alter table apu_composicion_items enable row level security;

create policy apu_composicion_items_select on apu_composicion_items for select
using (puede_ver_apu_composicion(apu_composicion_id));

create policy apu_composicion_items_insert on apu_composicion_items for insert with check (
  is_apu_composicion_owner(apu_composicion_id)
);

create policy apu_composicion_items_update on apu_composicion_items for update using (
  is_apu_composicion_owner(apu_composicion_id)
) with check (
  is_apu_composicion_owner(apu_composicion_id)
);

create policy apu_composicion_items_delete on apu_composicion_items for delete using (
  is_apu_composicion_owner(apu_composicion_id)
);

-- =====================================================================
-- Limitación conocida, aceptada por ahora — igual que rubros/subitems (0015/0016)
-- =====================================================================
--
-- Ni apu_composiciones_select ni puede_ver_apu_composicion() cubren todavía el caso "colaborador
-- con puede_ver_apu_ajena ve la receta personalizada del dueño en la obra donde está tildado" —
-- depende de obra_subitems, que es la próxima migración de este orden. Mientras tanto una receta
-- personalizada solo es visible para su dueño, nunca para un colaborador de su obra: más
-- restrictivo de lo que el diseño final prevé (docs/rubros_apu_diseno_datos.md §2.6), nunca menos,
-- sin riesgo de seguridad en el medio. Extender esto (agregar el OR con el join a
-- obra_subitems/obra_members dentro de puede_ver_apu_composicion) queda anotado como parte de la
-- migración de obra_subitems.
