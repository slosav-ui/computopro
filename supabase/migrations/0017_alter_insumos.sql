-- Rubros/APU parte 2 — Migración 4: extiende `insumos` para servir de catálogo de APU
-- (materiales + mano de obra + equipos), y siembra los 5 insumos oficiales de mano de obra.
-- Ver docs/rubros_apu_diseno_datos.md §2.5 (decisión A) y §3.A para el diseño completo.
--
-- `insumos` no fue creada por una migración versionada de este proyecto (viene de una sesión de
-- Gemini anterior) — columnas confirmadas en vivo por el usuario en Table Editor el 2026-08-22:
-- id/created_at/nombre/unidad/categoria. `categoria` hoy solo tiene valores de MATERIAL
-- (áridos/cementos/hierros), confirmado por el usuario, no un supuesto.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

-- =====================================================================
-- Columnas nuevas
-- =====================================================================

alter table insumos
  add column tipo text,
  add column unidad_compra text,
  add column factor_conversion numeric,
  add column porcentaje_cargas_sociales numeric,
  add column creador_usuario_id uuid references auth.users(id);

-- unidad_compra / factor_conversion quedan NULL para las 12 filas existentes a propósito — no se
-- parsea el nombre (ej. "Cemento Holcim x 50kg") para adivinar el factor de conversión, es
-- limpieza de datos que el usuario revisa fila por fila con su propio criterio, no algo que esta
-- migración resuelva sola.

-- Backfill: las 12 filas existentes son todas de categoria material (áridos/cementos/hierros),
-- confirmado por el usuario en vivo en Table Editor — no es un supuesto de esta migración.
update insumos set tipo = 'material' where tipo is null;

alter table insumos
  alter column tipo set not null,
  add constraint insumos_tipo_check check (tipo in ('material', 'mano_obra', 'equipo'));

-- =====================================================================
-- Seed: 5 insumos oficiales de mano de obra (categorías UOCRA usadas en toda partida de APU)
-- =====================================================================
--
-- porcentaje_cargas_sociales queda NULL a propósito — no se inventa el % de la escala UOCRA, se
-- completa a mano cuando el usuario tenga la escala actualizada. "AYUDA DE GREMIO" normalizado
-- sin el sufijo "ayudante" que trae la celda original de la planilla (redundante con el nombre de
-- la categoría, no parte del nombre oficial).
--
-- OJO antes de correr: si `categoria` tiene una restricción (NOT NULL sin default, o un check
-- que no admita 'mano_obra' como valor) este insert puede fallar — avisame el error exacto si
-- pasa y ajusto la columna `categoria` de estas 5 filas.

insert into insumos (nombre, unidad, categoria, tipo) values
  ('OFICIAL ESPECIALIZADO', 'hs', 'mano_obra', 'mano_obra'),
  ('OFICIAL', 'hs', 'mano_obra', 'mano_obra'),
  ('MEDIO OFICIAL', 'hs', 'mano_obra', 'mano_obra'),
  ('AYUDANTE', 'hs', 'mano_obra', 'mano_obra'),
  ('AYUDA DE GREMIO', 'hs', 'mano_obra', 'mano_obra');

-- =====================================================================
-- RLS — extiende lo ya cerrado en 0013_rls_proveedores_precios.sql
-- =====================================================================
--
-- SELECT sigue sin cambios (auth.uid() is not null, abierto a cualquier autenticado — insumos no
-- es información sensible, a diferencia de precios). Se agregan INSERT/UPDATE/DELETE para que un
-- PRO pueda cargar su propio insumo custom (creador_usuario_id = auth.uid()), mismo patrón que
-- rubros/subitems (0015/0016). Las filas oficiales (creador_usuario_id is null, incluidas las 5
-- de mano de obra recién sembradas) siguen sin política de escritura — alta/edición manual vía
-- SQL Editor, mismo criterio que el resto del catálogo oficial de este proyecto.

create policy insumos_insert on insumos for insert with check (
  creador_usuario_id = auth.uid()
);

create policy insumos_update on insumos for update using (
  creador_usuario_id = auth.uid()
) with check (
  creador_usuario_id = auth.uid()
);

create policy insumos_delete on insumos for delete using (
  creador_usuario_id = auth.uid()
);
