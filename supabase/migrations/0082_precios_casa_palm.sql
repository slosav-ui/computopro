-- Cuarto proveedor de materiales: Casa Palm S.A.C.I.I.A., Av. Alte. Brown 404, Bariloche.
-- Presupuesto 00001-00168829 del 2026-09-07, vendedor Lucero, Jorge Alberto.
--
-- Precio de CONTADO, mismo criterio que ya se aplicó con Felemax (0058) -- comparable directo con
-- Sólido y HIZA, que cotizaron contado. La diferencia con la columna de lista es del 25% parejo en
-- todos los ítems, según la propia cotización -- no hace falta cargar la de lista, no aporta nada
-- que la de contado no tenga ya.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

-- =====================================================================
-- Corralón nuevo
-- =====================================================================

insert into corralones (nombre, ciudad, lat, lng, es_capital, usuario_id)
select 'Casa Palm', 'Bariloche', -41.1372, -71.3245, false, null
where not exists (
  select 1 from corralones where nombre = 'Casa Palm'
);

-- =====================================================================
-- HIERRO BARRA ADN 420 -- promedio de los 4 diámetros, mismo método que Sólido/Felemax (0058)
-- =====================================================================
--
-- El catálogo tiene un solo insumo genérico en TON, sin distinción de diámetro (0022/0023) --
-- Casa Palm cotizó por diámetro (Ø6/Ø8/Ø10/Ø12, barra de 12m), así que se convierte cada uno a
-- $/kg por el peso real de su barra y se promedia, igual que ya se hizo para los otros dos
-- corralones que sí cotizaron hierro (HIZA nunca lo cotizó):
--   Ø6:  6744.78 / 2.64  = 2554.840909 $/kg
--   Ø8:  11586.56 / 4.70 = 2465.225532 $/kg
--   Ø10: 18090.45 / 7.44 = 2431.512097 $/kg
--   Ø12: 25895.12 / 10.68 = 2424.636704 $/kg
--   promedio = 2469.053811 $/kg -> x1000 = 2469053.8 $/TON
--
-- Banda de precio que queda tras esta carga: mínimo ~2.152.113 (Sólido), máximo ~2.469.054 (Casa
-- Palm) -- Casa Palm pasa a ser el hierro más caro de los tres que lo cotizan (Felemax queda al
-- medio, ~2.320.975).

-- =====================================================================
-- Los 33 ítems de la cotización, 31 con precio a cargar
-- =====================================================================
--
-- 2 quedan afuera, a propósito:
--   - Cal Estrella x 20kg ($6.658,04): segunda cal del mismo corralón -- cargar las dos daría dos
--     precios de Casa Palm para el mismo insumo. Va la Cacique (25kg, fila "CAL HIDRÁULICA" de
--     abajo), que coincide con el envase de los otros proveedores.
--   - Arena Media Bolsón ($102.890,70): áridos fuera de alcance, decisión ya tomada.
--
-- Los otros 31 se reducen a 28 filas (los 4 diámetros de hierro colapsan en 1, ver arriba).
--
-- Dos verificaciones resueltas antes de cargar:
--   - HIDROFUGO: Sika-1, bidón de 20 litros. Ficha técnica Sika Argentina: densidad 1,02 kg/litro
--     a 20°C -- 20 litros = 20,4 kg, no 20. Factor de conversión real: 20,4 (no se asume 1:1).
--   - BANDA ACUSTICA POLIETILENO 100MM: Casa Palm la cotiza como "Banda Acustica 3mm (10cm x 20
--     Mts)" -- 10cm = 100mm de ancho, mismo producto que ya está cargado (Felemax/HIZA), confirmado
--     por ancho, no solo por nombre.
--   - FILM DE POLIETILENO 200 MICRONES: Casa Palm cotiza $2.290,49 por ml de rollo de 4m de ancho
--     -- mismo ancho (4m) que ya usan Sólido y Felemax para este insumo, así que la conversión a
--     $/m2 es la misma fórmula ya establecida (precio por ml / ancho del rollo): 2290.49 / 4 =
--     572.6225.
--
-- Nombres verificados contra el catálogo real -- 8 de los 31 no coincidían con el nombre tal cual
-- figura en la cotización (paréntesis o medida que son parte del nombre real, o palabra distinta):
-- PLACA DE YESO STD 12.5MM -> "... (1.20 X 2.40M)"; FLEJE DE ACERO GALVANIZADO CRUZ DE SAN ANDRES
-- -> "..., CRUCE DE SAN ANDRES 0.9MM X 100MM" (coma + "CRUCE", no "CRUZ"); MASILLA P/JUNTAS ->
-- "... (LISTA PARA USAR O EN POLVO)". Cargados con el nombre real, no el de la cotización.

insert into precios (insumo_id, corralon_id, valor, fecha_actualizacion)
select i.id, c.id, v.valor, '2026-09-07'
from (values
  ('CEMENTO PORTLAND X 25KG', 397.5944),
  ('CAL HIDRÁULICA', 434.7308),
  ('HIERRO BARRA ADN 420', 2469053.8),
  ('MALLA ELECTROSOLDADA 15/25', 4571.4292),
  ('ALAMBRE NEGRO', 4442.47),
  ('HIDROFUGO', 2409.5539),
  ('FILM DE POLIETILENO 200 MICRONES', 572.6225),
  ('MEMBRANA ASFÁLTICA 4MM GEOTEXTIL', 11199.17),
  ('LADRILLOS CERAMICOS HUECOS 18/18/33', 1682.86),
  ('LADRILLOS CERAMICOS HUECOS 12/18/33', 1129.20),
  ('LADRILLOS CERAMICOS PORTANTES 18/19/33', 2103.47),
  ('LADRILLOS COMUNES', 509.99),
  ('BLOQUES DE CEMENTO 19/19/39', 2797.55),
  ('ADHESIVO CEMENTICIO', 578.8836),
  ('YESO', 580.4669),
  ('PERFIL PGC 100 X 40 X 0,9MM', 5491.315),
  ('PERFIL PGU 103 X 30 X 0,9MM', 4450.9433),
  ('PERFIL PGC 150 X 40 X 0,9MM', 7068.65),
  ('PERFIL PGU 150 X 30 X 0,9MM', 5822.7233),
  ('PLACA DE YESO STD 12.5MM (1.20 X 2.40M)', 6773.4583),
  ('AISLACION TERMICA (LANA DE VIDRIO 50MM)', 5179.6185),
  ('AISLACION HIDROFUGA TIPO TYVEK', 2263.854),
  ('BANDA ACUSTICA POLIETILENO 100MM', 1844.981),
  ('FLEJE DE ACERO GALVANIZADO, CRUCE DE SAN ANDRES 0.9MM X 100MM', 1817.78),
  ('MASILLA P/JUNTAS (LISTA PARA USAR O EN POLVO)', 1744.835),
  ('CINTA DE PAPEL MICROPERFORADA P/JUNTAS', 93.6681),
  ('CANTONERAS METÁLICAS / PLÁSTICAS P/ESQUINAS', 958.4038),
  ('CHAPA SINUSOIDAL – COLOR C25', 22903.63)
) as v(insumo_nombre, valor)
join insumos i on i.nombre = v.insumo_nombre and i.creador_usuario_id is null
cross join corralones c
where c.nombre = 'Casa Palm'
  and not exists (select 1 from precios p where p.insumo_id = i.id and p.corralon_id = c.id);

-- =====================================================================
-- Verificación
-- =====================================================================

-- 1) Tiene que haber insertado 28 filas -- si da menos, algún nombre de la lista de arriba no
--    coincidió con el catálogo (join silencioso, 0 filas para ese insumo puntual).
select count(*) as filas_casa_palm
from precios p
join corralones c on c.id = p.corralon_id
where c.nombre = 'Casa Palm'
  and p.fecha_actualizacion = '2026-09-07';

-- 2) Ningún insumo con dos precios del mismo corralón (chequeo de siempre).
select insumo_id, corralon_id, count(*) as filas
from precios
group by insumo_id, corralon_id
having count(*) > 1;

-- 3) Los 28 insumos de Casa Palm, para revisar valores a simple vista.
select i.nombre as insumo, p.valor
from precios p
join insumos i on i.id = p.insumo_id
join corralones c on c.id = p.corralon_id
where c.nombre = 'Casa Palm'
order by i.nombre;
