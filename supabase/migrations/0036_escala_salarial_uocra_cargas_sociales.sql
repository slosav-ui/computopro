-- Costo de mano de obra — pasos 1 y 2: tabla de escala salarial UOCRA + columnas de cargas
-- sociales en obra_presupuesto_config. Fuente de valores: docs/seed/costo_laboral_uocra.xlsx
-- (hojas "Parametros" y "Escala UOCRA").
--
-- Qué está verificado y qué no, para no confundir un supuesto con un dato de ley:
-- - Verificada contra normativa: la EXISTENCIA y la BASE de cálculo de cada concepto — Fondo de
--   Cese Laboral (Ley 22.250 art. 15, Decreto reglamentario 1342/81), ART (Ley 24.557), FICS/
--   IERIC/FODECO calculados sobre el Fondo de Cese, no sobre el sueldo (art. 49 CCT 76/75), y el
--   suplemento de hormigón (CCT 76/75, ver nota en adicional_hormigon_pct más abajo).
-- - SIN verificar contra normativa, pendientes de confirmar con contador: las ALÍCUOTAS CONCRETAS
--   (art_pct, fondo_cese_pct, suss_pct, obra_social_patronal_pct, fics_pct, ieric_pct, fodeco_pct,
--   uocra_empleador_pct) y los montos fijos (fijos_operario_mensual). Salen de la planilla de la
--   liquidadora del usuario, no de una póliza real ni de una verificación propia. Viven como
--   columna editable en obra_presupuesto_config justamente para poder corregirlas con un UPDATE
--   cuando se confirmen — no tratarlas como verdad establecida en ningún punto de este archivo.
--
-- Función de cálculo del valor hora (Paso 3), consolidado de Mat y MO (Paso 4) y UI (Paso 5)
-- quedan para después — esta migración es solo schema + seed.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

-- =====================================================================
-- Ayuda de Gremio vs. Sereno — por qué las 5 categorías de insumos y las 5 de la escala NO
-- coinciden 1 a 1, y no es un error
-- =====================================================================
--
-- Sereno es una categoría real del convenio (CCT 76/75) con básico propio, liquidación mensual,
-- distinta de las 4 categorías por hora. Pero no participa de ninguna APU (nadie le pone
-- rendimiento por m² a un sereno) — es costo indirecto de obra, va al Factor K, no a este
-- mecanismo. Por eso la escala la carga (es parte de la normativa) pero hoy ningún insumo la
-- apunta.
--
-- Ayuda de Gremio, al revés, es un concepto de la APU (mano de obra que pone el contratista
-- principal para asistir a un gremio subcontratado) sin básico propio en el convenio — no es una
-- categoría escalafonaria. Se costea al valor del Ayudante (decisión de negocio, no un dato que
-- faltara cargar).
--
-- El vínculo entre insumos y escala es por código (categoria_uocra), nunca por nombre — un texto
-- que hoy coincide (ej. "OFICIAL" = "Oficial") puede divergir con un typo o un cambio de mayúsculas
-- sin que nada lo detecte; un código fijo con check constraint sí.

-- =====================================================================
-- Paso 1: escala_salarial_uocra — catálogo compartido, no dato de obra
-- =====================================================================

create table escala_salarial_uocra (
  id uuid primary key default gen_random_uuid(),
  categoria_uocra text not null check (categoria_uocra in ('AYUD', 'MOFI', 'OFIC', 'OFES', 'SERE')),
  zona text not null,
  jornal_basico numeric not null check (jornal_basico >= 0),
  adicional_zona numeric not null default 0 check (adicional_zona >= 0),
  -- Suplemento de hormigón (CCT 76/75): 15% sobre el básico, uniforme para todas las categorías.
  -- Corresponde SOLO al personal ocupado directamente en la colada y SOLO cuando no se usan medios
  -- mecánicos para elaborar, transportar, distribuir y vibrar el hormigón — con hormigón elaborado
  -- y bombeado no corresponde. Vive acá porque es un dato de la escala/normativa, pero NUNCA se
  -- suma al valor hora base que calcula el Paso 3 — lo aplica la APU de estructura como una
  -- decisión aparte. Que la app lo aplique por defecto en las APU de estructura es un supuesto de
  -- diseño sobre cómo trabaja la mayoría de las obras, no una obligación legal — si algún día se
  -- suma en los dos lados a la vez (valor hora base + APU de estructura), se cuenta dos veces, y
  -- eso sí sería un bug real.
  adicional_hormigon_pct numeric not null default 15 check (adicional_hormigon_pct >= 0),
  porcentaje_asistencia numeric not null check (porcentaje_asistencia >= 0),
  tipo_liquidacion text not null check (tipo_liquidacion in ('por_hora', 'mensual')),
  -- Sin vigencia_hasta a propósito: la escala vigente en una fecha es la de mayor vigencia_desde
  -- que sea <= esa fecha, para la misma categoria_uocra/zona. Agregar vigencia_hasta obligaría a
  -- mantener dos fechas coherentes en cada paritaria sin ganar ninguna capacidad nueva.
  vigencia_desde date not null,
  created_at timestamptz not null default now(),
  unique (categoria_uocra, zona, vigencia_desde)
);

alter table escala_salarial_uocra enable row level security;

-- Mismo patrón que insumos/rubros/subitems (catálogo oficial): lectura abierta a cualquier
-- autenticado, sin política de escritura — se actualiza a mano vía SQL Editor en cada paritaria
-- (3-4 veces al año), no hay pantalla de alta.
create policy escala_salarial_uocra_select on escala_salarial_uocra for select
using (auth.uid() is not null);

-- Seed: escala Zona B, septiembre 2026 (docs/seed/costo_laboral_uocra.xlsx, hoja "Escala UOCRA").
-- Sereno es mensual — jornal_basico/adicional_zona en pesos/mes, no por hora.
insert into escala_salarial_uocra
  (categoria_uocra, zona, jornal_basico, adicional_zona, adicional_hormigon_pct, porcentaje_asistencia, tipo_liquidacion, vigencia_desde)
values
  ('AYUD', 'B', 5399,   621,    15, 20, 'por_hora', '2026-09-01'),
  ('MOFI', 'B', 5866,   636,    15, 20, 'por_hora', '2026-09-01'),
  ('OFIC', 'B', 6348,   702,    15, 20, 'por_hora', '2026-09-01'),
  ('OFES', 'B', 7420,   816,    15, 20, 'por_hora', '2026-09-01'),
  ('SERE', 'B', 980858, 111861, 15, 22, 'mensual',  '2026-09-01');

-- =====================================================================
-- Paso 2a: insumos.categoria_uocra — vínculo por código, no por nombre
-- =====================================================================
--
-- Nullable: solo aplica a los 5 insumos de tipo mano_obra (0017_alter_insumos.sql), materiales y
-- equipos quedan sin tocar. No se toca la RLS de insumos acá (deshabilitada en 6 tablas del bloque
-- proveedores, tema aparte y conocido).

alter table insumos
  add column categoria_uocra text check (categoria_uocra in ('AYUD', 'MOFI', 'OFIC', 'OFES', 'SERE'));

update insumos set categoria_uocra = 'OFES' where nombre = 'OFICIAL ESPECIALIZADO';
update insumos set categoria_uocra = 'OFIC' where nombre = 'OFICIAL';
update insumos set categoria_uocra = 'MOFI' where nombre = 'MEDIO OFICIAL';
update insumos set categoria_uocra = 'AYUD' where nombre = 'AYUDANTE';
update insumos set categoria_uocra = 'AYUD' where nombre = 'AYUDA DE GREMIO';
-- SERE queda sin ningún insumo que lo apunte — correcto y esperado, ver nota de arriba.

-- =====================================================================
-- Paso 2b: columnas nuevas en obra_presupuesto_config — parámetros de cargas sociales
-- =====================================================================
--
-- Porcentajes en números enteros (10.23, no 0.1023), misma convención que gg_pct/imprevistos_pct/
-- epp_pct/beneficio_pct/costo_financiero_pct ya en esta tabla (0020_obra_presupuesto_config.sql).
--
-- ¡OJO PARA EL PASO 3! Cada uno de los *_pct de acá abajo (art_pct, fondo_cese_pct, suss_pct,
-- obra_social_patronal_pct, fics_pct, ieric_pct, fodeco_pct, uocra_empleador_pct) tiene que
-- DIVIDIRSE POR 100 antes de multiplicar contra el remunerativo — son 10.23, no 0.1023. Olvidarlo
-- da un valor hora absurdo (fácil de notar) o, peor, uno solo un poco alto (fácil de no notar).
--
-- No hace falta tocar handle_new_obra_presupuesto() (0020_obra_presupuesto_config.sql): ese
-- trigger inserta la fila sin listar columnas, así que toda obra nueva hereda estos defaults solo.
-- El trigger set_updated_at_obra_presupuesto_config (0035) ya cubre esta tabla — un UPDATE futuro
-- de estos campos actualiza updated_at sin necesitar nada nuevo acá.

alter table obra_presupuesto_config
  -- Editables por PRO — dependen de la empresa/póliza/convenio de cada usuario.
  add column art_pct numeric not null default 10.23,
  add column fondo_cese_pct numeric not null default 12,
  -- 18 (no 20.4) es el default correcto para el público de la app — pymes constructoras y
  -- constructores independientes (Ley 27.541 art. 19 inc. b). 20.4 es la alícuota de empleadores
  -- más grandes (servicios/comercio); por eso el campo queda editable, no fijo en ninguno de los
  -- dos valores.
  add column suss_pct numeric not null default 18,
  -- El ART entra DOS VECES en el costo total, y es correcto — así cotizan las ART en la práctica:
  -- una alícuota (art_pct de arriba) MÁS una suma fija por trabajador, que es uno de los 5
  -- componentes sumados acá (junto con seguro de vida, preocupacional, indumentaria/EPP,
  -- telegramas/gestión). No es una duplicación a "arreglar" — si alguien lo lee y saca el fijo de
  -- ART pensando que ya está cubierto por art_pct, va a subestimar el costo real.
  add column fijos_operario_mensual numeric not null default 57344.78,
  add column horas_mensuales numeric not null default 176,
  add column horas_improductivas_mensuales numeric not null default 14.41,
  -- No editables por el usuario, pero SÍ viven como columna (no como constante en la función) —
  -- el Paso 5 necesita listarlas con su % en un desglose dinámico, y un cambio de normativa se
  -- resuelve con un UPDATE, no con un deploy.
  add column obra_social_patronal_pct numeric not null default 6,
  add column fics_pct numeric not null default 2,
  add column ieric_pct numeric not null default 1,
  add column fodeco_pct numeric not null default 1,
  add column uocra_empleador_pct numeric not null default 2,
  -- Con o sin cargas sociales: de obra entera (no por categoría), afecta el valor hora real que
  -- calcula el Paso 3, no es solo un flag visual. Default true = con cargas (comportamiento actual
  -- implícito, nada cambia para obras existentes al aplicar esta migración).
  add column aplica_cargas_sociales boolean not null default true;

-- =====================================================================
-- Paso 2c: obra_valor_hora_override — el PRO fija a mano el valor hora de una categoría puntual
-- =====================================================================
--
-- Por categoría, no una sola columna: hasta 5 valores distintos por obra. Precedencia con el
-- cálculo automático (a implementar en el Paso 3, no acá): si existe fila para esa categoría, el
-- override gana siempre — tocar un parámetro de cargas sociales en obra_presupuesto_config NO
-- recalcula ni pisa un override existente.
--
-- Mismo patrón de RLS por membresía que obra_insumo_precios (0030): SELECT abierto a cualquier
-- miembro de la obra, escritura restringida a admin_maestro/profesional.

create table obra_valor_hora_override (
  id uuid primary key default gen_random_uuid(),
  obra_id uuid not null references obras(id) on delete cascade,
  categoria_uocra text not null check (categoria_uocra in ('AYUD', 'MOFI', 'OFIC', 'OFES', 'SERE')),
  valor_hora numeric not null check (valor_hora >= 0),
  usuario_id uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (obra_id, categoria_uocra)
);

alter table obra_valor_hora_override enable row level security;

create policy obra_valor_hora_override_select on obra_valor_hora_override for select
using (is_obra_member(obra_id));

create policy obra_valor_hora_override_insert on obra_valor_hora_override for insert with check (
  tiene_rol_en_obra(obra_id, 'admin_maestro')
  or tiene_rol_en_obra(obra_id, 'profesional')
);

create policy obra_valor_hora_override_update on obra_valor_hora_override for update using (
  tiene_rol_en_obra(obra_id, 'admin_maestro')
  or tiene_rol_en_obra(obra_id, 'profesional')
) with check (
  tiene_rol_en_obra(obra_id, 'admin_maestro')
  or tiene_rol_en_obra(obra_id, 'profesional')
);

create policy obra_valor_hora_override_delete on obra_valor_hora_override for delete using (
  tiene_rol_en_obra(obra_id, 'admin_maestro')
  or tiene_rol_en_obra(obra_id, 'profesional')
);

-- "Borrar todas juntas" no necesita una función aparte: un DELETE sin filtro de categoria_uocra
-- (solo obra_id) ya borra todos los overrides de esa obra bajo la misma política.

create trigger set_updated_at_obra_valor_hora_override
  before update on obra_valor_hora_override
  for each row execute function set_updated_at();
