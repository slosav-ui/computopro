-- Carga de precios reales de corralones de Bariloche: Solido S.R.L., Felemax/Matcom SAS y SB
-- Maderas y Construccion (cotizaciones del 04/09/2026), mas HIZA como cuarto corralon para varios
-- items de ferreteria/steel frame sin cotizacion de los otros tres.
-- Depende de 0057 (catalogo) ya aplicada -- varios de los insumos de aca no existen hasta que esa
-- migracion corra. Ver supabase/seed_staging/mapeo_precios_corralones_2026-09-04.csv para el
-- detalle completo linea por linea de cada decision de mapeo, unidad de compra y promedio.
--
-- Precios SIN FLETE (se resuelve aparte, con la geolocalizacion de la obra) y CON IVA (las 4
-- fuentes cotizan asi). Felemax cargado a precio de CONTADO, no de lista (Solido y SB Maderas ya
-- cotizaron directo en efectivo) -- ver docs/confianza_precios_diseno.md para el criterio general
-- de esta pieza.
--
-- fecha_actualizacion = 04/09/2026 en las 114 filas (fecha real de las 4 cotizaciones, no la fecha
-- en que se aplica esta migracion -- created_at sí queda con el default now() para eso).
--
-- Aplicar a mano en el SQL Editor de Supabase (Project -> SQL Editor), DESPUES de 0057. No
-- ejecutado automaticamente por Claude Code: sin acceso a la base de datos desde este entorno.
--
-- =====================================================================
-- Seccion 1 -- 4 corralones nuevos
-- =====================================================================
--
-- Los 8 corralones ya existentes (Corralon del Valle x4, Materiales Neuquen Capital x4, duplicados)
-- NO se tocan aca -- esa limpieza sigue pendiente, requiere correr antes las 3 queries de
-- verificacion de referencias en `precios`/`obra_insumo_precios` para elegir sobreviviente sin
-- perder datos, mismo criterio que 0049 con Hierro del 12mm. No bloquea esta carga: los 4
-- corralones de aca son filas nuevas, no tocan las 8 existentes.
--
-- usuario_id null a proposito, mismo criterio que el seed viejo -- quedan sin dueno hasta
-- asignacion real. es_capital = false: Bariloche (Rio Negro) no es capital de provincia.
--
-- CORRECCION tras el primer intento fallido: `corralones.lat` es NOT NULL (no estaba documentado
-- hasta que la migracion original fallo con lat/lng en null -- no aplico nada, transaccion
-- completa). Lat/lng de las 4 direcciones que figuran en cada cotizacion, aproximadas (alcanzan
-- para filtro por zona, se pueden precisar despues si hace falta):
--   Solido S.R.L. -- Neneo 22, Bariloche
--   Felemax / Matcom SAS -- Lonquimay 3885, Bariloche
--   HIZA -- Miramar 53, Bariloche
--   SB Maderas y Construccion -- Bariloche (sin direccion puntual en la cotizacion)
--
-- Antes de reaplicar, correr esto para confirmar que no hay otra columna NOT NULL sin cubrir --
-- no se pudo verificar contra la base real desde este entorno, solo se cubren las columnas ya
-- confirmadas por Seba (nombre/ciudad/lat/lng/es_capital/usuario_id):
--
--   select column_name, is_nullable, column_default
--   from information_schema.columns
--   where table_name = 'corralones'
--   order by ordinal_position;

insert into corralones (nombre, ciudad, lat, lng, es_capital, usuario_id)
select v.nombre, 'Bariloche', v.lat, v.lng, false, null
from (values
  ('Sólido', -41.1456, -71.3082),
  ('Felemax', -41.1372, -71.2544),
  ('HIZA', -41.1389, -71.3011),
  ('SB Maderas', -41.1335, -71.3103)
) as v(nombre, lat, lng)
where not exists (
  select 1 from corralones c where c.nombre = v.nombre
);


-- =====================================================================
-- Seccion 2 -- precios (114 filas)
-- =====================================================================
--
-- HIERRO BARRA ADN 420: las 8 lineas originales por diametro (Ø6/8/10/12 x 2 corralones) NO se
-- cargan una por una -- el catalogo solo tiene un insumo generico en TON (sin distincion de
-- diametro, ver 0023). Se carga un solo valor por corralon: el promedio de los 4 diametros, cada
-- uno ya convertido a $/kg por el peso real de su barra (barras de 12m, confirmado por Seba para
-- los dos corralones) y multiplicado x1000 para TON. Verificado dos veces (con precio de lista y
-- de contado) que da el mismo resultado que promediar barra-por-barra y despues convertir.
--
-- Items 'genericos con precio de referencia' (mismo insumo del catalogo, mas de un producto/marca
-- real cotizado por el mismo corralon): se carga el promedio de los productos reales, no un valor
-- inventado -- ver notas puntuales en el mapeo (CSV) para cada caso: lija antiempaste 100/120,
-- cal Santa Barbara/Risco Bayo, clavos 2"/2.5", adhesivo cementicio Sika/Klaukol, trapo
-- blanco/estopa (estos dos ultimos son productos fisicamente distintos -- tela de algodon vs fibra
-- suelta -- pero la receta de APU no los distingue, anotado por si algun dia importa).

insert into precios (insumo_id, corralon_id, valor, fecha_actualizacion)
select i.id, c.id, v.valor, '2026-09-04'
from (values

  ('CEMENTO PORTLAND X 25KG', 'Sólido', 416.9636),
  ('CAL HIDRÁULICA', 'Sólido', 339.674),
  ('MALLA ELECTROSOLDADA Q188 15/15', 'Sólido', 8785.4278),
  ('ALAMBRE NEGRO COCIDO N° 16', 'Sólido', 3716.16),
  ('HIDROFUGO', 'Sólido', 2226.566),
  ('FILM DE POLIETILENO 200 MICRONES', 'Sólido', 567.6425),
  ('LADRILLOS CERAMICOS HUECOS 18/18/33', 'Sólido', 1539.95),
  ('LADRILLOS CERAMICOS HUECOS 12/18/33', 'Sólido', 1078.25),
  ('LADRILLOS CERAMICOS PORTANTES 18/19/33', 'Sólido', 1792.56),
  ('ADHESIVO CEMENTICIO', 'Sólido', 1292.956),
  ('MEMBRANA ASFÁLTICA 4MM GEOTEXTIL', 'Sólido', 1525.4067),
  ('PERFIL PGC 100 X 40 X 0,9MM', 'Sólido', 5541.83),
  ('PLACA DE YESO STD 12.5MM (1.20 X 2.40M)', 'Sólido', 6208.8125),
  ('MASILLA P/JUNTAS (LISTA PARA USAR O EN POLVO)', 'Sólido', 1525.5075),
  ('CINTA TRAMADA', 'Sólido', 168.0556),
  ('CANTONERAS METÁLICAS / PLÁSTICAS P/ESQUINAS', 'Sólido', 1042.3),
  ('PINTURA LÁTEX INTERIOR LAVABLE (3 MANOS)', 'Sólido', 7499.58),
  ('PERFIL PGC 150 X 40 X 0,9MM', 'Sólido', 7983.7317),
  ('PERFIL PGU 150 X 30 X 0,9MM', 'Sólido', 7289.4933),
  ('CEMENTO PORTLAND X 25KG', 'Felemax', 433.11),
  ('ARENA', 'Felemax', 62477.448),
  ('CANTO RODADO / PIEDRA PARTIDA', 'Felemax', 112313.89),
  ('MALLA ELECTROSOLDADA 15/25', 'Felemax', 4545.6264),
  ('ALAMBRE NEGRO COCIDO N° 16', 'Felemax', 5492.28),
  ('HIDROFUGO', 'Felemax', 1886.244),
  ('FILM DE POLIETILENO 200 MICRONES', 'Felemax', 500.2675),
  ('LADRILLOS CERAMICOS HUECOS 18/18/33', 'Felemax', 1565.41),
  ('LADRILLOS CERAMICOS HUECOS 12/18/33', 'Felemax', 1093.42),
  ('LADRILLOS CERAMICOS PORTANTES 18/19/33', 'Felemax', 2010.23),
  ('LADRILLOS COMUNES', 'Felemax', 397.19),
  ('BLOQUES DE CEMENTO 19/19/39', 'Felemax', 3296.38),
  ('YESO', 'Felemax', 387.2663),
  ('MORTERO ADHESIVO', 'Felemax', 975.6908),
  ('PERFIL PGC 100 X 40 X 0,9MM', 'Felemax', 5582.495),
  ('PERFIL PGU 103 X 30 X 0,9MM', 'Felemax', 4687.7667),
  ('PERFIL PGC 150 X 40 X 0,9MM', 'Felemax', 6997.2383),
  ('PERFIL PGU 150 X 30 X 0,9MM', 'Felemax', 6074.9783),
  ('PLACA DE YESO STD 12.5MM (1.20 X 2.40M)', 'Felemax', 5481.6076),
  ('AISLACION ACUSTICA (LANA DE VIDRIO 100MM)', 'Felemax', 14660.8806),
  ('MEMBRANA ASFÁLTICA 4MM GEOTEXTIL', 'Felemax', 1464.0733),
  ('BANDA ACUSTICA POLIETILENO 100MM', 'Felemax', 1033.356),
  ('MASILLA P/JUNTAS (LISTA PARA USAR O EN POLVO)', 'Felemax', 1429.7219),
  ('CINTA DE PAPEL MICROPERFORADA P/JUNTAS', 'Felemax', 59.6079),
  ('CANTONERAS METÁLICAS / PLÁSTICAS P/ESQUINAS', 'Felemax', 963.2154),
  ('CHAPA SINUSOIDAL O TRAPEZOIDAL', 'Felemax', 22216.02),
  ('PINTURA LÁTEX INTERIOR LAVABLE (3 MANOS)', 'Felemax', 6542.341),
  ('FIJADOR / SELLADOR AL AGUA CONCENTRADO 1:8', 'Felemax', 4923.2655),
  ('ENDUIDO PLÁSTICO INTERIOR (PLANCHADO TOTAL)', 'Felemax', 4174.8285),
  ('ESMALTE SINTÉTICO', 'Felemax', 12668.9),
  ('PLACAS DE OSB 11.1MM', 'Felemax', 9872.3428),
  ('PLACAS FENOLICAS DE 18MM O MACHIMBRE 5” X 3/4”', 'Felemax', 12746.1099),
  ('MACHIMBRE DE PINO/EUCALIPTO 1/2” X 4”', 'Felemax', 9700.3806),
  ('TORNILLOS T1 MECHA 8X9/16', 'Felemax', 32.11),
  ('TORNILLOS T2 PUNTA MECHA 6X1.1/8', 'Felemax', 37.46),
  ('TORNILLOS T2 PUNTA MECHA CON ALAS 10X1.1/2', 'Felemax', 77.86),
  ('TORNILLOS T2 PUNTA MECHA CON ALAS 8X1.1/4”', 'Felemax', 56.12),
  ('TORNILLOS T2 PUNTA AGUJA 6X1', 'Felemax', 15.83),
  ('TORNILLO CABEZA EXAGONAL 10 X 3/4”', 'Felemax', 61.6),
  ('CLAVOS CABEZA PERDIDA 12 X 50MM', 'Felemax', 8901.56),
  ('TORNILLO MADERA 10 X 3 3/4"', 'Felemax', 211.06),
  ('TORNILLO MADERA FIC 8 X 2 (21X50MM)', 'Felemax', 46.73),
  ('TORNILLO HEXAGONAL PUNTA 17 ZINCADO 14 X 3"', 'Felemax', 268.84),
  ('ANCLAJE DE EXPANSION POR GOLPE M10 X 85', 'Felemax', 1155.91),
  ('ANCLAJE DE EXPANSION POR GOLPE M8 X 70', 'Felemax', 829.23),
  ('TACOS DE EXPANSIÓN 8MM C/TORNILLO', 'Felemax', 57.29),
  ('PUNTAS PH2 IMPACTO PARA ATORNILLADOR', 'Felemax', 106.618),
  ('BOQUILLA / DADO HEXAGONAL MAGNÉTICO (1/4” O 5/16”)', 'Felemax', 2763.17),
  ('DISCOS DE CORTE PARA AMOLADORA (180 X 1,6MM)', 'Felemax', 5032.36),
  ('DISCOS DE SIERRA CIRCULAR PARA MADERA (184MM X 24T)', 'Felemax', 15362.41),
  ('MECHA HSS PARA ACERO 4MM A 10MM', 'Felemax', 17852.58),
  ('MECHA WIDIA PARA CONCRETO 10MM', 'Felemax', 5000.33),
  ('MECHA COPA / MECHA DE ESPERA PARA PADERA', 'Felemax', 32907.28),
  ('LIJA PARA MADERA N° 120/180', 'Felemax', 891.15),
  ('HOJAS DE LIJA P/METAL N° 120/180/220', 'Felemax', 1690.56),
  ('SELLADOR POLIURETANICO', 'Felemax', 11360.5),
  ('ADHESIVO DE MONTAJE / COLA VINILICA', 'Felemax', 6750.6533),
  ('CINTA DE ENMASCARAR AZUL/UV 48MM', 'Felemax', 171.6658),
  ('CINTA TRAMADA', 'Felemax', 74.1787),
  ('ELECTRODO REVESTIDO / ALAMBRE MIG', 'Felemax', 14625.314),
  ('AGUARRÁS MINERAL P/DILUCIÓN', 'Felemax', 3643.9175),
  ('DILUYENTE', 'Felemax', 5661.085),
  ('BANDEJA DESCARTABLE DE PINTURA', 'Felemax', 1427.47),
  ('RODILLO EPOXI PELO CORTO ANTIGOTA', 'Felemax', 6032.21),
  ('ESCUADRIAS PINO 2" X 4" (100 X 50 CEPILLADO)', 'SB Maderas', 2405.0492),
  ('TIRANTES', 'SB Maderas', 2312.1311),
  ('CABIOS DE PINO 6” X 2.1/2” (100 X 75 CEPILLADO)', 'SB Maderas', 5411.3443),
  ('ALFAJIAS 2”X2” CEPILLADAS', 'SB Maderas', 1027.6066),
  ('ALFAJÍAS / LISTONES DE PINO 1” X 2” (CRUZADOS)', 'SB Maderas', 513.8033),
  ('TABLAS', 'SB Maderas', 1541.4098),
  ('PLACAS DE OSB 11.1MM', 'SB Maderas', 10595.2701),
  ('PLACAS FENOLICAS DE 18MM O MACHIMBRE 5” X 3/4”', 'SB Maderas', 12871.204),
  ('MACHIMBRE DE PINO/EUCALIPTO 1/2” X 4”', 'SB Maderas', 8600.0),
  ('REALCES 1/2” X 1”', 'SB Maderas', 200.0),
  ('LISTOS ZOCALO DE MADERA 3” X 1/2”', 'SB Maderas', 5165.5738),
  ('TORNILLO HEXAGONAL PUNTA 17 ZINCADO 14 X 3"', 'HIZA', 198.0),
  ('TORNILLO MADERA FIC 8 X 2 (21X50MM)', 'HIZA', 88.53),
  ('TORNILLO MADERA 10 X 3 3/4"', 'HIZA', 156.69),
  ('ANCLAJE DE EXPANSION POR GOLPE M10 X 85', 'HIZA', 1377.0),
  ('ANCLAJE DE EXPANSION POR GOLPE M8 X 70', 'HIZA', 1377.0),
  ('CLAVOS CABEZA PERDIDA 12 X 50MM', 'HIZA', 11500.0),
  ('MECHA COPA / MECHA DE ESPERA PARA PADERA', 'HIZA', 35040.0),
  ('DISCOS DE SIERRA CIRCULAR PARA MADERA (184MM X 24T)', 'HIZA', 36000.0),
  ('MALLA ELECTROSOLDADA Q188 15/15', 'HIZA', 8289.7917),
  ('MALLA ELECTROSOLDADA 15/25', 'HIZA', 4502.7778),
  ('BOQUILLA / DADO HEXAGONAL MAGNÉTICO (1/4” O 5/16”)', 'HIZA', 8360.0),
  ('DISCOS DE CORTE PARA AMOLADORA (115 X 1MM)', 'HIZA', 2605.0),
  ('DISCOS DE CORTE PARA AMOLADORA (180 X 1,6MM)', 'HIZA', 4060.0),
  ('HIERRO BARRA ADN 420', 'Sólido', 2152112.5),
  ('HIERRO BARRA ADN 420', 'Felemax', 2320975.0),
  ('HOJAS DE LIJA PARA MAMPOSTERÍA N° 100/120', 'Felemax', 1369.48),
  ('CAL HIDRÁULICA', 'Felemax', 385.79),
  ('CLAVOS DE 2” Y 2.1/2”', 'Felemax', 5694.37),
  ('ADHESIVO CEMENTICIO', 'Felemax', 787.3948),
  ('TRAPO DE ESTOPA', 'Felemax', 4075.59)

) as v(insumo_nombre, corralon_nombre, valor)
join insumos i on i.nombre = v.insumo_nombre and i.creador_usuario_id is null
join corralones c on c.nombre = v.corralon_nombre;


-- =====================================================================
-- Verificacion -- correr despues de aplicar todo lo de arriba
-- =====================================================================

-- 1) Total de filas insertadas: esperado 114. Si da menos, algun nombre de insumo o de
--    corralon no matcheo (typo, o 0057 no se aplico antes) y esa fila se perdio en silencio --
--    parar y revisar antes de seguir, no asumir cual fue.
select count(*) as total_precios_cargados from precios
where corralon_id in (select id from corralones where nombre in ('Sólido','Felemax','SB Maderas','HIZA'));

-- 2) Los 4 corralones nuevos existen, con lat/lng cargados (ninguno debe dar null).
select nombre, ciudad, lat, lng, es_capital from corralones where nombre in ('Sólido','Felemax','SB Maderas','HIZA');

-- 3) HIERRO BARRA ADN 420: banda de precio esperada -- minimo ~2.152.113 (Solido), maximo
--    ~2.320.975 (Felemax contado), promedio ~2.236.544.
select * from calcular_precio_promedio_insumo(
  (select id from insumos where nombre = 'HIERRO BARRA ADN 420' and creador_usuario_id is null)
);

-- 4) Cuantos insumos de material quedan sin ningun precio real ahora (deberia bajar fuerte desde
--    los ~204 sin precio del diagnostico original).
select count(*) as insumos_material_sin_precio
from insumos i
where i.tipo = 'material' and i.creador_usuario_id is null
  and not exists (select 1 from precios p where p.insumo_id = i.id);
