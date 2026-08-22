-- RLS para el bloque de proveedores/insumos/precios (6 tablas creadas fuera del flujo de
-- migraciones, ver diagnóstico en conversación — no hay doc en docs/ para este bloque).
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.
--
-- Alcance cerrado con el usuario:
-- - insumos/corralones/precios: las 3 tablas con datos reales (12/8/60 filas), reciben diseño
--   completo de RLS.
-- - proveedores/insumos_proveedor/documentos_proveedor: vacías o casi vacías (1/0/0 filas) y
--   desconectadas del flujo real (sin FK entrante/saliente hacia insumos/corralones/precios) —
--   se activa RLS sin ninguna política (bloqueo total), sin diseño elaborado, porque puede que
--   ni se terminen usando.
--
-- Ninguna de las 6 tablas tenía columna de dueño (usuario_id/auth.users) antes de esta migración.

-- =====================================================================
-- corralones: nueva columna de dueño
-- =====================================================================
--
-- Nullable a propósito: las 8 filas actuales son datos de seed sin usuario real detrás. Quedan
-- congeladas para edición (ningún usuario autenticado va a poder hacerles UPDATE) hasta que se
-- les asigne usuario_id a mano vía SQL Editor — comportamiento esperado, confirmado con el
-- usuario, no un bug a resolver acá.

alter table corralones add column usuario_id uuid references auth.users(id);

-- =====================================================================
-- Funciones helper
-- =====================================================================
--
-- SECURITY DEFINER + search_path fijo: mismo patrón que is_obra_member en
-- 0004_rls_etapa3.sql (hardening estándar en funciones SECURITY DEFINER de este proyecto).

-- No es estrictamente necesaria como SECURITY DEFINER hoy (corralones_select ya es
-- auth.uid() is not null, o sea visible para cualquier autenticado), pero se deja así por
-- consistencia con el resto del proyecto y para no depender de que la política de SELECT de
-- corralones se mantenga abierta si en el futuro se restringe.
create or replace function is_corralon_owner(p_corralon_id uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select exists (
    select 1 from corralones
    where id = p_corralon_id and usuario_id = auth.uid()
  );
$$;

grant execute on function is_corralon_owner(uuid) to authenticated;

-- Lee todas las filas de precios para el insumo (SECURITY DEFINER, ignora la RLS de precios
-- de abajo) pero solo expone agregados: nunca corralon_id ni valor fila por fila. Es la única
-- vía legítima para que alguien fuera del dueño del corralón sepa algo sobre precios.
--
-- Devuelve mínimo/máximo además del promedio (no solo el promedio) para poder mostrar más
-- adelante una "banda de precio" en la UI (roadmap del motor de precios, fuera de alcance hoy),
-- y cantidad_corralones para que quien consuma el dato pueda juzgar qué tan confiable es el
-- promedio (ej. avg de 1 solo corralón no es lo mismo que avg de 6). Sin filtro de radio ni
-- fallback a MercadoLibre: promedio simple de todo lo que haya en precios para ese insumo,
-- tal como se acordó para esta versión.
create or replace function calcular_precio_promedio_insumo(p_insumo_id uuid)
returns table(promedio numeric, minimo numeric, maximo numeric, cantidad_corralones bigint)
language sql security definer set search_path = public stable as $$
  select avg(valor), min(valor), max(valor), count(*)
  from precios
  where insumo_id = p_insumo_id;
$$;

grant execute on function calcular_precio_promedio_insumo(uuid) to authenticated;

-- =====================================================================
-- corralones
-- =====================================================================

alter table corralones enable row level security;

-- SELECT: directorio abierto a cualquier autenticado (nombre/ciudad/ubicación, sin precios) —
-- un profesional necesita ver qué corralones existen para elegir a quién pedir presupuesto.
create policy corralones_select on corralones for select
using (auth.uid() is not null);

-- UPDATE: solo el dueño de la ficha.
create policy corralones_update on corralones for update using (
  usuario_id = auth.uid()
) with check (
  usuario_id = auth.uid()
);

-- Sin política INSERT: no hay pantalla de alta de corralón en la app todavía — el alta sigue
-- siendo manual, vía SQL Editor (service_role, ignora RLS). Agregar la política cuando exista
-- el flujo de autoregistro.
--
-- Sin política DELETE: no definido para esta versión, mismo estado que INSERT.

-- =====================================================================
-- precios
-- =====================================================================
--
-- La tabla sensible real: cuánto cobra cada corralón por cada insumo. Nadie lee/escribe
-- directo salvo el dueño del corralón correspondiente — ni siquiera un arquitecto autenticado
-- puede hacer un SELECT crudo acá. calcular_precio_promedio_insumo() de arriba es la única
-- salida para cualquier otro usuario.

alter table precios enable row level security;

create policy precios_select on precios for select
using (is_corralon_owner(corralon_id));

create policy precios_insert on precios for insert with check (
  is_corralon_owner(corralon_id)
);

create policy precios_update on precios for update using (
  is_corralon_owner(corralon_id)
) with check (
  is_corralon_owner(corralon_id)
);

-- Sin política DELETE: append-only, mismo criterio que libro_entradas/audit_log (0004_rls_etapa3.sql).
-- Si un corralón se equivoca de precio, corrige con UPDATE — nunca borra, para mantener
-- trazabilidad histórica de qué precios existieron.

-- =====================================================================
-- insumos
-- =====================================================================
--
-- Catálogo global (nombre/unidad/categoría, sin precio ni dueño) — no hay concepto de "dueño
-- de un insumo" como sí lo hay en corralones.

alter table insumos enable row level security;

create policy insumos_select on insumos for select
using (auth.uid() is not null);

-- Sin política de escritura: en este proyecto "admin" siempre significa admin_maestro, un rol
-- por obra (obra_members) — no existe un concepto de administrador global de la plataforma, e
-- insumos no pertenece a ninguna obra. Escritura queda exclusivamente a mano vía SQL Editor
-- (service_role) hasta que se diseñe ese concepto, si hace falta.

-- =====================================================================
-- proveedores / insumos_proveedor / documentos_proveedor — bloqueo total
-- =====================================================================
--
-- Vacías (insumos_proveedor, documentos_proveedor) o con una sola fila de prueba
-- (proveedores), y sin ninguna FK hacia/desde insumos, corralones o precios: no forman parte
-- del flujo real de datos hoy. RLS habilitada sin ninguna política = deniega todo a
-- anon/authenticated (solo service_role, que ignora RLS, sigue viendo todo desde el
-- dashboard). Sin diseño elaborado a propósito — quedan para una migración futura si
-- terminan usándose.

alter table proveedores enable row level security;
alter table insumos_proveedor enable row level security;
alter table documentos_proveedor enable row level security;

-- =====================================================================
-- Limitaciones conocidas, aceptadas para esta versión:
--
-- - Igual limitación general que 0004_rls_etapa3.sql: RLS controla filas, no columnas. Si el
--   día de mañana insumos o corralones suman una columna sensible que no todo autenticado deba
--   ver, hace falta una vista o un ajuste de política — no alcanza con lo de acá.
--
-- Descartado como limitación (verificado, no es un hueco real): corralones_update no permite
-- reasignar usuario_id a otro dueño en el mismo UPDATE. using y with_check están ambos
-- anclados a auth.uid() (el mismo valor fijo durante toda la sentencia) — using exige que la
-- fila VIEJA ya sea del que ejecuta el UPDATE, with_check exige que la fila NUEVA también lo
-- sea, así que el nuevo usuario_id queda transitivamente forzado a ser igual al viejo. No hace
-- falta (ni existe, en una policy) una referencia tipo OLD/NEW para lograr esto — ese patrón
-- es de triggers, no de RLS.
-- =====================================================================
