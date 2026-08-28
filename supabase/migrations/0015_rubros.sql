-- Rubros/APU parte 2 — Migración 2: tabla `rubros`, sembrada con los 20 rubros reales de
-- PLANILLA_BASE_2_0_v3_CORREGIDA.ods.
-- Ver docs/rubros_apu_permisos_selector_diseno_datos.md §2.1 para el diseño completo.
--
-- Reemplaza el catálogo `macrorrubros` (~17 valores) del diseño fundacional
-- (docs/rubros_apu_diseno_datos.md) — descartado, no complementado. `sistemas_constructivos` y
-- `rubro_sistema_constructivo` también quedan fuera de este diseño: los rubros 4-7 (Hormigón
-- Armado/Steel Frame/Balloon Frame/Metálicas Livianas) ya son rubros de primer nivel, no hace
-- falta una relación N:M para modelar qué sistema constructivo usa una obra.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

create table rubros (
  id uuid primary key default gen_random_uuid(),
  codigo text not null,                     -- "1".."20" en el catálogo oficial, libre para custom
  nombre text not null,
  orden int not null default 0,             -- posición fija 1-20 del catálogo oficial; los
                                             -- rubros custom de un PRO se listan después
  usa_apu boolean not null default true,    -- false = precio 100% manual, sin arrastre de APU
  tipo_precio_manual text                    -- distingue el sub-caso cuando usa_apu = false:
    check (tipo_precio_manual in ('unitario', 'global')),
    -- 'unitario' = cantidad × precio unitario tipeado a mano (Rubros 1 y 20)
    -- 'global'   = un único monto para toda la partida, sin desglose por unidad (Rubros 18 y 19)
  creador_usuario_id uuid references auth.users(id),  -- null = catálogo oficial
  created_at timestamptz not null default now(),
  constraint rubros_tipo_precio_manual_coherente check (
    (usa_apu = true and tipo_precio_manual is null)
    or (usa_apu = false and tipo_precio_manual is not null)
  )
);

-- Evita duplicar accidentalmente un código del catálogo oficial (ej. dos filas "18" oficiales).
-- No restringe a los rubros custom de un PRO — cada uno arma su propio código libremente.
create unique index rubros_codigo_oficial_unique on rubros (codigo)
  where creador_usuario_id is null;

-- =====================================================================
-- Seed: los 20 rubros reales (docs/seed/PLANILLA_BASE_2_0_v3_CORREGIDA.ods, hoja RUBROS)
-- =====================================================================

insert into rubros (codigo, nombre, orden, usa_apu, tipo_precio_manual) values
  ('1',  'TAREAS PRELIMINARES',              1,  false, 'unitario'),
  ('2',  'MOVIMIENTOS DE SUELOS',            2,  true,  null),
  ('3',  'FUNDACIONES',                      3,  true,  null),
  ('4',  'ESTRUCTURAS DE HORMIGON ARMADO',   4,  true,  null),
  ('5',  'ESTRUCTURAS DE STEEL FRAME',       5,  true,  null),
  ('6',  'ESTRUCTURAS DE BALLOON FRAME',     6,  true,  null),
  ('7',  'ESTRUCTURAS METALICAS LIVIANAS',   7,  true,  null),
  ('8',  'MAMPOSTERIAS',                     8,  true,  null),
  ('9',  'CAPAS AISLADORAS',                 9,  true,  null),
  ('10', 'REVOQUES Y YESERIA',               10, true,  null),
  ('11', 'CONTRAPISOS Y CARPETAS',           11, true,  null),
  ('12', 'PISOS Y ZOCALOS',                  12, true,  null),
  ('13', 'REVESTIMIENTOS HUMEDOS',           13, true,  null),
  ('14', 'REVESTIMIENTOS SECOS',             14, true,  null),
  ('15', 'CUBIERTAS',                        15, true,  null),
  ('16', 'CIELORRASOS',                      16, true,  null),
  ('17', 'PINTURAS',                         17, true,  null),
  ('18', 'INSTALACIONES',                    18, false, 'global'),
  ('19', 'CARPINTERIAS',                     19, false, 'global'),
  ('20', 'VARIOS',                           20, false, 'unitario');

-- =====================================================================
-- RLS
-- =====================================================================
--
-- Mismo patrón dueño-nullable que ya usa el resto del catálogo personalizable de este proyecto
-- (docs/rubros_apu_diseno_datos.md §2.6): filas oficiales (creador_usuario_id is null) con
-- SELECT abierto a cualquier autenticado, sin política de escritura (alta/edición del catálogo
-- oficial sigue siendo manual vía SQL Editor, mismo criterio que insumos en
-- 0013_rls_proveedores_precios.sql). Filas personalizadas: el dueño ve, crea, edita y borra las
-- suyas. Free/PRO no se distingue acá — sigue siendo deuda técnica de capa de app (decisión G del
-- diseño fundacional), no hay tabla de planes/pagos todavía de la cual colgar ese control.

alter table rubros enable row level security;

create policy rubros_select on rubros for select
using (
  creador_usuario_id is null
  or creador_usuario_id = auth.uid()
);

create policy rubros_insert on rubros for insert with check (
  creador_usuario_id = auth.uid()
);

create policy rubros_update on rubros for update using (
  creador_usuario_id = auth.uid()
) with check (
  creador_usuario_id = auth.uid()
);

create policy rubros_delete on rubros for delete using (
  creador_usuario_id = auth.uid()
);

-- =====================================================================
-- Limitación conocida, aceptada por ahora
-- =====================================================================
--
-- La política de SELECT de arriba todavía no cubre el caso "colaborador con puede_ver_apu_ajena
-- ve el rubro custom del dueño en la obra donde está tildado" (docs/rubros_apu_diseno_datos.md
-- §2.6, la política de RLS más delicada de toda la pieza) — no se puede escribir todavía porque
-- depende de obra_subitems, que no existe hasta una migración más adelante en este mismo orden
-- (docs/rubros_apu_permisos_selector_diseno_datos.md §5). Mientras tanto, un rubro custom de un
-- PRO solo es visible para él mismo, nunca para un colaborador de su obra — más restrictivo de lo
-- que el diseño final prevé, nunca menos, así que no hay riesgo de seguridad en el medio.
-- Extender esta política (agregar el OR con el join a obra_subitems/obra_members) queda anotado
-- como parte de la migración de obra_subitems.
