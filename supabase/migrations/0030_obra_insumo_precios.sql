-- Mat y MO — paso 1: tabla `obra_insumo_precios`, el precio de un insumo resuelto para una obra
-- puntual, distinto del precio de referencia global de `precios` (corralones).
-- Ver memoria de diseño "mat_y_mo_fuentes_precio" para el diagnóstico completo (tres fuentes de
-- precio, por qué el precio editado es por obra y no global, precedencia entre fuentes).
--
-- Reordenamiento de plan respecto a la vinculación con APU: esta pieza va ANTES de retomar el
-- motor de precio derivado (migración 0029_calcular_precio_apu_subitem.sql, sigue sin aplicar) —
-- es la fuente de precios que ese motor va a consumir, no al revés.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

-- =====================================================================
-- Diseño: una sola fila activa por (obra, insumo)
-- =====================================================================
--
-- Ausencia de fila para un (obra_id, insumo_id) = sin override, se usa el precio automático
-- (calcular_precio_promedio_insumo(), 0013_rls_proveedores_precios.sql) — igual que
-- precio_unitario_manual usa NULL para "todavía no decidido" en vez de una columna aparte de
-- estado.
--
-- `origen` distingue de dónde salió el valor guardado (para la marca visual permanente que la app
-- tiene que mostrar en cualquier precio que no sea el automático) — no hace falta un historial de
-- filas compitiendo entre sí: con un único slot por par, la fila más reciente ES el precio
-- vigente para esa obra.
--
-- Precedencia entre fuentes (decisión del usuario, 2026-08-31): un presupuesto en firme es un
-- compromiso real de un tercero, no una estimación — pisarlo con una edición manual sin avisar
-- pierde información que no se recupera. Al revés (cargar un presupuesto en firme sobre una
-- edición manual) no necesita aviso: el dato duro reemplaza a la estimación sin pérdida real.
-- **Esta regla NO se fuerza a nivel de base** — la base no tiene forma de saber si el usuario vio
-- y confirmó un diálogo de aviso del lado de la app. Se implementa en la capa de escritura de Dart
-- (paso 3, todavía sin construir): antes de guardar un precio con origen='manual', el repositorio
-- consulta si ya existe una fila con origen='presupuesto_firme' para ese (obra, insumo) y, si la
-- hay, exige confirmación explícita antes de pisarla. Mismo patrón ya usado en el proyecto para
-- "avisar y dejar decidir" en vez de bloquear a nivel de base (ver borrado de subítems propios,
-- rubros_apu_diseno_datos.md).

create table obra_insumo_precios (
  id uuid primary key default gen_random_uuid(),
  obra_id uuid not null references obras(id) on delete cascade,
  insumo_id uuid not null references insumos(id) on delete cascade,
  precio numeric not null check (precio >= 0),
  origen text not null check (origen in ('manual', 'presupuesto_firme')),
  corralon_id uuid references corralones(id),  -- solo cuando origen = 'presupuesto_firme'
  usuario_id uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),  -- sin trigger, mismo criterio que obra_subitems
                                                     -- (0019) / apu_composiciones (0018) — la app
                                                     -- lo pisa a mano en cada update
  unique (obra_id, insumo_id),
  constraint obra_insumo_precios_corralon_solo_en_firme check (
    (origen = 'presupuesto_firme' and corralon_id is not null)
    or (origen = 'manual' and corralon_id is null)
  )
);

-- =====================================================================
-- RLS
-- =====================================================================
--
-- Mismo patrón de rol-gate que obra_subitems (0019) / obra_presupuesto_config (0020): SELECT
-- abierto a cualquier miembro de la obra, escritura restringida a admin_maestro/profesional (los
-- dos roles con edición total de cómputos y precios en la matriz de permisos ya cerrada).
--
-- DELETE permitido (a diferencia de `precios`, que es append-only): borrar la fila de acá es
-- "volver al precio automático para este insumo en esta obra", no perder un registro que otra
-- parte del sistema necesite conservar — mismo criterio ya usado para el borrado de subítems
-- propios (avisar y dejar decidir, no bloquear).

alter table obra_insumo_precios enable row level security;

create policy obra_insumo_precios_select on obra_insumo_precios for select
using (is_obra_member(obra_id));

create policy obra_insumo_precios_insert on obra_insumo_precios for insert with check (
  tiene_rol_en_obra(obra_id, 'admin_maestro')
  or tiene_rol_en_obra(obra_id, 'profesional')
);

create policy obra_insumo_precios_update on obra_insumo_precios for update using (
  tiene_rol_en_obra(obra_id, 'admin_maestro')
  or tiene_rol_en_obra(obra_id, 'profesional')
) with check (
  tiene_rol_en_obra(obra_id, 'admin_maestro')
  or tiene_rol_en_obra(obra_id, 'profesional')
);

create policy obra_insumo_precios_delete on obra_insumo_precios for delete using (
  tiene_rol_en_obra(obra_id, 'admin_maestro')
  or tiene_rol_en_obra(obra_id, 'profesional')
);

-- =====================================================================
-- Qué queda sin resolver a propósito, fuera de alcance de este paso
-- =====================================================================
--
-- Ningún mecanismo de precio para insumos de mano de obra todavía (ver
-- rubros_apu_diseno_datos.md) — esta tabla puede guardar un precio editado manualmente para un
-- insumo de mano_obra igual que para un material (no distingue `insumos.tipo`), así que sirve como
-- la vía real para que el usuario cargue un valor/hora manual de mano de obra por obra. Lo que
-- sigue faltando es el mecanismo del lado "automático" para mano de obra (no hay escala UOCRA
-- cargada ni una tabla equivalente a `precios` para valor/hora) — pieza de diseño aparte, sin
-- empezar.
--
-- Sin UI todavía: este paso es solo schema. El consolidado de solo lectura (paso 2), la edición
-- con aviso y marca visual (paso 3) y el presupuesto en firme (paso 4) quedan para después.
