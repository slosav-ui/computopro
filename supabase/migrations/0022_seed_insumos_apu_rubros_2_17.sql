-- Rubros/APU — Catálogo APU rubros 2 a 17, Migración A: carga de insumos.
-- Fuente: docs/seed/catalogo_apu_completo_rubros_2_17.xlsx (97 partidas curadas y verificadas
-- con el usuario una por una). Esta migración SOLO toca `insumos` — la carga de
-- apu_composiciones / apu_composicion_items (773 ítems, 97 partidas) es la Migración B,
-- deliberadamente separada para poder verificar que los insumos entraron bien antes de correr
-- la carga más grande.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.
--
-- Decisiones cerradas con el usuario (no son suposiciones de esta migración):
-- - `categoria` se setea igual a `tipo` ('material') para las 228 filas nuevas, mismo patrón que
--   los 5 insumos de mano de obra sembrados en 0017_alter_insumos.sql (categoria = tipo). Si
--   `categoria` tiene una taxonomía más fina que no conocemos, avisar antes de correr.
-- - `creador_usuario_id` queda NULL (catálogo oficial), mismo patrón que rubros/subitems/
--   apu_composiciones.
-- - `unidad_compra` / `factor_conversion` / `porcentaje_cargas_sociales` quedan NULL a propósito,
--   mismo criterio que 0017: limpieza fila por fila a cargo del usuario, no se adivina acá.
--
-- =====================================================================
-- Sección 1 — Consolidación de duplicados EXISTENTES: ARENA y CEMENTO
-- =====================================================================
--
-- Confirmado con el usuario con los 12 ids reales pegados desde el SQL Editor: "Arena fina" y
-- "Cemento Holcim x 50kg" no eran 1 fila cada uno como se asumió al principio, sino 4 filas
-- IDÉNTICAS duplicadas por nombre (mismo nombre, id distinto) — 12 filas totales de categoría
-- material, no 12 insumos distintos como sugería (mal interpretado) el comentario de
-- 0013/0017. "Hierro del 12mm" tiene el mismo patrón de 4 duplicados pero NO se toca en esta
-- migración — se decidió dejarlo igual; "HIERRO BARRA ADN 420" entra como insumo nuevo y
-- distinto en la Sección 2, sin fusionarse con él (fórmula en toneladas de acero genérico vs.
-- venta de corralón por diámetro específico, sin equivalente 1:1).
--
-- precios: confirmado que las 60 filas de la tabla son 100% datos de prueba — la suma de
-- referencias a los 4 ids de Cemento (8+14+20+18) da exactamente 60, el total de la tabla, o sea
-- ARENA y HIERRO no tienen ninguna fila de precios. Se van a cargar precios reales en una etapa
-- aparte, así que el usuario autorizó borrar las filas de precios de los ids perdedores sin
-- reasignarlas a mano.
--
-- Sobreviviente de cada grupo (criterio: si hay diferencia de referencias, se queda el id con
-- más para conservar el máximo de datos de prueba bajo el nombre consolidado; si no hay ninguna
-- referencia en ningún id del grupo, da igual cuál sobreviva y se toma el primero de la lista):
--   ARENA:   sobrevive 028ac9ed-023c-4b29-bd0b-7f4f43f92c75 (0 de 0 referencias — no importa cuál)
--   CEMENTO: sobrevive 053f2ba0-979c-4b01-9689-7041c4c26bf2 (20 de 60 referencias, es el máximo)
--
-- apu_composicion_items no debería tener ninguna fila que referencie estos ids todavía (la
-- Migración B, que carga las 773 filas de composición, no corrió). El DELETE de esa tabla queda
-- igual como salvaguarda de costo cero — evita romper por FK si hubiera alguna composición
-- custom cargada a mano que no sabemos.
--
-- Orden importa: hijos (apu_composicion_items, precios) antes que el padre (insumos), si no la
-- FK bloquea el DELETE de insumos. Si algún UPDATE final devuelve 0 filas (RETURNING vacío), el
-- id sobreviviente no existe más (probablemente se borró por error en el paso anterior) — parar
-- y avisar, no reintentar con otro id a ciegas.

-- Grupo ARENA — sobrevive 028ac9ed-023c-4b29-bd0b-7f4f43f92c75
delete from apu_composicion_items where insumo_id in (
  'c2f290cf-202c-434d-870d-a764efd89c6a',
  '2325f0f0-b1a7-45ad-a6ce-54b02a62c181',
  '5bf862bc-e467-4641-a9e5-15f08f689864'
);

delete from precios where insumo_id in (
  'c2f290cf-202c-434d-870d-a764efd89c6a',
  '2325f0f0-b1a7-45ad-a6ce-54b02a62c181',
  '5bf862bc-e467-4641-a9e5-15f08f689864'
);

delete from insumos where id in (
  'c2f290cf-202c-434d-870d-a764efd89c6a',
  '2325f0f0-b1a7-45ad-a6ce-54b02a62c181',
  '5bf862bc-e467-4641-a9e5-15f08f689864'
);

update insumos set nombre = 'ARENA'
where id = '028ac9ed-023c-4b29-bd0b-7f4f43f92c75'
returning id, nombre;

-- Grupo CEMENTO — sobrevive 053f2ba0-979c-4b01-9689-7041c4c26bf2 (20/60 referencias en precios)
delete from apu_composicion_items where insumo_id in (
  '7f1708dc-c7a0-4a25-9141-3a4745454c0b',
  '9529704c-f222-453a-9784-603f443b0b69',
  '93d541f8-947a-47be-8e92-d2f99f339a3a'
);

delete from precios where insumo_id in (
  '7f1708dc-c7a0-4a25-9141-3a4745454c0b',
  '9529704c-f222-453a-9784-603f443b0b69',
  '93d541f8-947a-47be-8e92-d2f99f339a3a'
);

delete from insumos where id in (
  '7f1708dc-c7a0-4a25-9141-3a4745454c0b',
  '9529704c-f222-453a-9784-603f443b0b69',
  '93d541f8-947a-47be-8e92-d2f99f339a3a'
);

update insumos set nombre = 'CEMENTO PORTLAND X 25KG'
where id = '053f2ba0-979c-4b01-9689-7041c4c26bf2'
returning id, nombre;

-- =====================================================================
-- Sección 2 — 228 insumos de material NUEVOS
-- =====================================================================
--
-- 238 nombres únicos de material en el Excel, menos:
--  - ARENA y CEMENTO (ya resueltos como rename en la Sección 1, no se insertan de nuevo)
--  - 8 filas fusionadas en 7 grupos de duplicados/variantes de un mismo material, reducidas a su
--    nombre canónico:
--      CAL HIDRAULICA / CAL HIDRÁULICA                              -> CAL HIDRÁULICA
--      PLACAS OSB DE 11.1MM / PLACASOSB DE 11.1MM (+ PLACAS DE OSB) -> PLACAS DE OSB 11.1MM
--      TORNILLO CABEZA EXAGONAL 10 X 3/4" / ...10X3/4"              -> TORNILLO CABEZA EXAGONAL 10 X 3/4"
--      LADRILLOS COMUNES / LLADRILLOS COMUNES                       -> LADRILLOS COMUNES
--      AISLACION HIDROFUGA/HIDROHUGA TIPO TYBEK                     -> AISLACION HIDROFUGA TIPO TYVEK
--      AGUARÁS MINERAL P/DILUCIÓN / ...PURO P/DILUCIÓN              -> AGUARÁS MINERAL P/DILUCIÓN
--      TORNILLOS T2 AGUJA / TORNILLOS T2 PUNTA AGUJA                -> TORNILLOS T2 PUNTA AGUJA
--  - la fila corrupta del Excel "CINTA DE ENMASCARAR PESADA $48\TEXT{ MM}$" (partida 17.5,
--    artefacto de renderizado tipo fórmula colado en la celda) se simplifica a "CINTA DE
--    ENMASCARAR" (sin medida) — decisión del usuario, no se inventa una medida.
--  = 238 - 2 - 8 = 228 filas insertadas (la simplificación de la cinta no resta fila, solo
--    cambia el nombre).
--
-- "HIERRO BARRA" (nombre del Excel) entra acá ya con su nombre final "HIERRO BARRA ADN 420"
-- (ver Sección 1) — sigue siendo insumo nuevo, no rename de uno existente.
--
-- `where not exists` en vez de un INSERT plano: hace la migración segura de re-correr, y como
-- salvaguarda extra por si alguno de estos 228 nombres coincidiera exacto con uno de los otros
-- insumos existentes que todavía no confirmamos con el SELECT completo (ver nota al final del
-- archivo) — en ese caso no se duplica, se deja el existente como está.

insert into insumos (nombre, unidad, categoria, tipo)
select v.nombre, v.unidad, 'material', 'material'
from (values
  ('ACONDICIONADOR ÁCIDO / SOLUCIÓN NEUTRALIZANTE', 'LTRS'),
  ('ADHESIVO / SELLADOR ELASTOMÉRICO POLIURETÁNICO (CARTUCHO)', 'UND'),
  ('ADHESIVO CEMENTICIO', 'KG'),
  ('ADHESIVO DE MONTAJE / COLA VINILICA', 'KG'),
  ('AGUARÁS MINERAL P/DILUCIÓN', 'LTRS'),
  ('AGUARÁS/AGUA P/DILUCIÓN', 'LTRS'),
  ('AISLACION ACUSTICA (LANA DE VIDRIO 100MM)', 'M2'),
  ('AISLACION HIDROFUGA', 'M2'),
  ('AISLACION HIDROFUGA TIPO TYVEK', 'M2'),
  ('AISLACION TERMICA', 'M2'),
  ('AISLACION TERMICA (LANA DE VIDRIO 100MM)', 'M2'),
  ('AISLACION TERMICA EPS O LANA DE VIDRIO 50MM', 'ML'),
  ('ALAMBRE GALVANIZADO N° 14 P/SUSPENSIÓN', 'ML'),
  ('ALAMBRE NEGRO', 'KG'),
  ('ALAMBRE NEGRO COCIDO N° 16', 'KG'),
  ('ALFAJIAS 2”X2” CEPILLADAS', 'ML'),
  ('ALFAJIAS DE MADERA 2”X2”', 'ML'),
  ('ALFAJÍAS / LISTONES DE PINO 1" X 2" (CRUZADOS)', 'ML'),
  ('ANCLAJE ESCUADRA DE TRACCION HTT14', 'UND'),
  ('ANCLAJE ESCUADRA METALICO GALVANIZADO', 'UND'),
  ('ANTIÓXIDO / FONDO ALQUÍDICO ANTICORROSIVO (2 MANOS)', 'LTRS'),
  ('ARCILLA EXPANDITA 3/10 (TIPIO RIPIOLITA, VERMICULITA, ETC.)', 'M3'),
  ('ARENA DE RIO TAMIZADA', 'M3'),
  ('BALDOZAS', 'UND'),
  ('BANDA ACUSTICA BAJO SOLERA 100MM', 'UND'),
  ('BANDA ACUSTICA POLIETILENO 100MM', 'ML'),
  ('BANDA ACÚSTICA DE POLIETILENO 35MM', 'ML'),
  ('BANDA HIDROFUGA. MEMBRANA AUTOADESIVA (TIPO BLACK IRON)  100MM', 'ML'),
  ('BANDEJA DESCARTABLE DE PINTURA', 'UND'),
  ('BARNIZ', 'LTRS'),
  ('BASE COAT MONOCOMPONENTE', 'KG'),
  ('BASE NIVELADORA / IMPRIMACIÓN DEL MISMO TONO', 'LTRS'),
  ('BLOQUE DE HORMIGON CALADO 30/30 E=8CM', 'UND'),
  ('BLOQUES DE CEMENTO 19/19/39', 'UND'),
  ('BOLSAS DE PERLAS DE EPS X 170 LITROS', 'LITROS'),
  ('BOQUILLA / DADO HEXAGONAL MAGNÉTICO (1/4" O 5/16")', 'UND'),
  ('BROCA MECANICA DE EXPANCION, ANCLAJE QUIMICO DIAM10MM (3/8”X3.1/2”)', 'UND'),
  ('BULONES DE ANCLAJE (CALIDAD 8.8 O GALVANIZADOS) + TUERCAS + ARANDELAS', 'KG'),
  ('CABIOS DE PINO 6" X 2.1/2" (100 X 75 CEPILLADO)', 'ML'),
  ('CAL AEREA', 'KG'),
  ('CAL AEREA HIDRATADA', 'KG'),
  ('CAL HIDRAULICA O AEREA', 'KG'),
  ('CAL HIDRÁULICA', 'KG'),
  ('CANTO RODADO / PIEDRA PARTIDA', 'M3'),
  ('CANTO RODADO DE CONTENCIÓN PERIMETRAL (FRANJA TÉCNICA)', 'KG'),
  ('CANTONERAS METÁLICAS / PLÁSTICAS P/ESQUINAS', 'M2'),
  ('CARPETA DE NIVELACIÓN 1:3 CON HIDRÓFUGO', 'M3'),
  ('CARTELAS / PLATINAS DE CONEXIÓN', 'KG'),
  ('CASCOTE DE LADRILLOS', 'M3'),
  ('CAÑO ESTRUCTURAL CUADRADO/RECTANGULAR CONFORMADO EN FRÍO', 'KG'),
  ('CAÑO ESTRUCTURAL CUADRADO/RECTANGULAR O PERFIL C CONFORMADO EN FRÍO', 'KG'),
  ('CERAMICO', 'M2'),
  ('CERAMICO O PORCELANATO', 'M2'),
  ('CESPED', 'KG'),
  ('CHAPA SINUSOIDAL O TRAPEZOIDAL', 'ML'),
  ('CHAPA SINUSOIDAL – COLOR C25', 'M2'),
  ('CHAPAS DE NUDO / CARTELAS', 'KG'),
  ('CINTA DE ENMASCARAR', 'ML'),
  ('CINTA DE ENMASCARAR 24MM', 'ML'),
  ('CINTA DE ENMASCARAR AZUL/UV 48MM', 'ML'),
  ('CINTA DE PAPEL', 'ML'),
  ('CINTA DE PAPEL MICROPERFORADA P/JUNTAS', 'ML'),
  ('CINTA TRAMADA', 'ML'),
  ('CLAVOS', 'KG'),
  ('CLAVOS DE 2” Y 2.1/2”', 'KG'),
  ('CLAVOS ESPIRALADOS / ESTRIADOS PARA CLAVADORA (2.5” A 3”)', 'KG'),
  ('CLAVOS SIN CABEZA / BRADS O TORNILLOS PARA MADERA', 'UND'),
  ('CLAVOS SIN CABEZA / PUNTA PARÍS 2”', 'KG'),
  ('CLAVOS SIN CABEZA O TORNILLOS', 'UND'),
  ('CLIPS DE RETENCIÓN CONTRA VIENTO', 'UND'),
  ('DESOXIDANTE / FOSFATIZANTE INDUSTRIAL', 'LTRS'),
  ('DILUYENTE', 'LTRS'),
  ('DILUYENTE / THINNER', 'LTRS'),
  ('DILUYENTE ESPECÍFICO EPOXI', 'LTRS'),
  ('DISCO DIAMANTADO P/DESBASTE DE PISO', 'UND'),
  ('DISCOS DE CORTE DE VIDIA 9”', 'UND'),
  ('DISCOS DE CORTE PARA AMOLADORA (115 X 1MM O 180 X 1,6 MM)', 'UND'),
  ('DISCOS DE CORTE PARA AMOLADORA (115 X 1MM)', 'UND'),
  ('DISCOS DE SIERRA CIRCULAR PARA MADERA (184MM X 24T)', 'UND'),
  ('ELECTRODO REVESTIDO / ALAMBRE MIG', 'KG'),
  ('ELECTRODO REVESTIDO E6011/E7018 O ALAMBRE MIG (CHAPA DE MENOR ESPESOR)', 'KG'),
  ('ENDUIDO PLÁSTICO INTERIOR (PLANCHADO TOTAL)', 'KG'),
  ('EPS ALTA DENSIDAD', 'M2'),
  ('ESCUADRIAS PINO 2" X 4" (100 X 50 CEPILLADO)', 'ML'),
  ('ESMALTE DE TERMINACIÓN', 'LTRS'),
  ('ESMALTE EPOXI / POLIURETÁNICO DE ALTO ESPESOR (2 COMP.)', 'LTRS'),
  ('ESMALTE SINTÉTICO DE TERMINACIÓN (2 MANOS)', 'LTRS'),
  ('ESMALTE SINTÉTICO SATINADO/BRILLANTE (2 MANOS)', 'LTRS'),
  ('ESPECIES VEGETALES (SEDUM / TEPE O MULTICELULAR)', 'M2'),
  ('FIJADOR / ACONDICIONADOR AL SOLVENTE (PENETRACIÓN)', 'LTRS'),
  ('FIJADOR / SELLADOR AL AGUA CONCENTRADO 1:8', 'LTRS'),
  ('FILM DE POLIETILENO 200 MICRONES', 'M2'),
  ('FLEJE DE ACERO GALVANIZADO, CRUCE DE SAN ANDRES 0.9MM X 100MM', 'ML'),
  ('FONDO ANTIÓXIDO', 'LTRS'),
  ('FONDO ANTIÓXIDO (2 MANOS)', 'LTRS'),
  ('GRAMPAS DE FIJACION P/METAL DESPLEGADO', 'UND'),
  ('GRAPAS ANCLAJE', 'UND'),
  ('HIDROFUGO EN PASTA', 'KG'),
  ('HIERRO BARRA ADN 420', 'TON'),
  ('HOJA DE LIJA', 'UND'),
  ('HOJAS DE LIJA FINA N° 180/220', 'UND'),
  ('HOJAS DE LIJA FINA N° 180/240', 'UND'),
  ('HOJAS DE LIJA P/MADERA N° 150/220/280', 'UND'),
  ('HOJAS DE LIJA P/METAL N° 120/180/220', 'UND'),
  ('HOJAS DE LIJA PARA MAMPOSTERÍA N° 100/120', 'UND'),
  ('HORMIGÓN DE PENDIENTE (CASCOTE/PERLA EPS)', 'M3'),
  ('IMPREGNANTE (LASUR) O BARNIZ MARINO CON FILTRO UV (3 MANOS)', 'LTRS'),
  ('IMPREGNANTE / BARNIZ BASE SOLVENTE (3 MANOS)', 'LTRS'),
  ('IMPRIMACIÓN ASFÁLTICA BASE AGUA', 'LITRS'),
  ('LADRILLOS CERAMICOS HUECOS 12/18/33', 'UND'),
  ('LADRILLOS CERAMICOS HUECOS 18/18/33', 'UND'),
  ('LADRILLOS CERAMICOS HUECOS 8/18/33', 'UND'),
  ('LADRILLOS CERAMICOS PORTANTES 18/19/33', 'UND'),
  ('LADRILLOS COMUNES', 'UND'),
  ('LADRILLOS MACIZOS HCCA 10/25/50', 'UND'),
  ('LADRILLOS MACIZOS HCCA 15/25/50', 'UND'),
  ('LADRILLOS MACIZOS HCCA 20/25/50', 'UND'),
  ('LANA DE ACERO N° 0 / VIRUTA', 'UND'),
  ('LIJA', 'UND'),
  ('LIJA PARA MADERA N° 120/180', 'UND'),
  ('LISTONADO / ALFAJÍAS PINO 2” X 1”', 'ML'),
  ('LISTONES DE REALCE 1” X 10MM', 'ML'),
  ('LISTONES VERTICALES CADA 0,40 M', 'ML'),
  ('LISTOS ZOCALO DE MADERA 3” X 1/2”', 'ML'),
  ('MACHIMBRE DE PINO/EUCALIPTO 1/2” X 4”', 'M2'),
  ('MACHIMBRE PINO', 'M2'),
  ('MALLA ELECTROSOLDADA 15/25', 'M2'),
  ('MALLA FIBRA', 'M2'),
  ('MALLA FIBRA DE VIDRIO 160G/M2', 'M2'),
  ('MANTA BAJOS PISO, ESPUMA DE POLIETILENO 2MM', 'M2'),
  ('MANTA GEOTEXTIL NO TEJIDA 150G/M2 (FILTRANTE)', 'M2'),
  ('MASILLA P/JUNTAS (LISTA PARA USAR O EN POLVO)', 'KG'),
  ('MASILLA P/MADERA DEL TONO DE LA PIEZA', 'KG'),
  ('MASILLA PARA MADERA', 'KG'),
  ('MASILLA TIPO ENDUIDO', 'KG'),
  ('MECHA COPA / MECHA DE ESPERA PARA PADERA', 'UND'),
  ('MECHA HSS PARA ACERO 4MM A 10MM', 'UND'),
  ('MECHA WIDIA PARA CONCRETO 10MM', 'UND'),
  ('MEMBRANA ANTI-RAÍZ EPDM / PVC (1.2MM)', 'M2'),
  ('MEMBRANA ASFÁLTICA 4MM CON GEOTEXTIL (IMPERMEABILIZACIÓN BASE)', 'M2'),
  ('MEMBRANA ASFÁLTICA 4MM GEOTEXTIL', 'M2'),
  ('MEMBRANA BARRERA DE AGUA Y VIENTO (TYVEK)', 'M2'),
  ('METAL DESPLEGADO PESADO (300 G/M2)', 'M2'),
  ('MICROCEMENTO BASE', 'KG'),
  ('MICROCEMENTO CAPA DE ACABADO', 'KG'),
  ('MOLDURA / ZÓCALO DE MADERA PERIMETRAL', 'ML'),
  ('MORTERO ADHESIVO', 'KG'),
  ('MÓDULO DRENANTE/RETENEDOR NODULAR HDPE', 'M2'),
  ('PASTINA', 'KG'),
  ('PASTINA PARA EXTERIORES (IMPERMEABLE)', 'KG'),
  ('PERFIL DIVISORIO DE BORDE DE ALUMINIO CALADO', 'M'),
  ('PERFIL MONTANTE 35MM U OMEGA (ESTRUCTURA/VELAS)', 'ML'),
  ('PERFIL PERIMETRAL L (3.00M)', 'ML'),
  ('PERFIL PGC 100 X 40 X 0,9MM', 'ML'),
  ('PERFIL PGC 150 X 40 X 0,9MM', 'ML'),
  ('PERFIL PGU 103 X 30 X 0,9MM', 'ML'),
  ('PERFIL PGU 150 X 30 X 0,9MM', 'ML'),
  ('PERFIL PRINCIPAL T (3.60M)', 'ML'),
  ('PERFIL SECUNDARIO T (1.20M)', 'ML'),
  ('PERFIL SOLERA 35MM (PERIMETRAL)', 'ML'),
  ('PERFIL TRANSVERSAL T (0.60M)', 'ML'),
  ('PERFIL TUBULAR RECTANGULAR O PERFIL C ESTRUCTURAL CONFORMADO EN FRÍO', 'KG'),
  ('PERFIL Z / BUÑA PERIMETRAL DE PVC O ALUMINIO', 'ML'),
  ('PERFILERÍA OMEGA O ALFAJIAS MADERA', 'ML'),
  ('PERFILES DE TERMINACIÓN (ESQUINEROS / ZÓCALOS)', 'ML'),
  ('PIEDRA', 'M2'),
  ('PIEDRA LAJA', 'UND'),
  ('PINTURA LÁTEX INTERIOR LAVABLE (3 MANOS)', 'LTRS'),
  ('PISO FLOTANTE MDF/HDF', 'M2'),
  ('PISO FLOTANTE VINILICO', 'M2'),
  ('PITONES L / TACOS DE EXPANSIÓN', 'UND'),
  ('PLACA DE YESO STD 12.5MM (1.20 X 2.40M)', 'M2'),
  ('PLACA YESO DE ROCA 12,5MM', 'M2'),
  ('PLACAS / TABLAS DE SIDING 19CM X 3.60M', 'M2'),
  ('PLACAS ACÚSTICAS / FIBRA MINERAL O PVC 60 X 60', 'M2'),
  ('PLACAS BASE Y PLATINAS DE REFUERZO', 'KG'),
  ('PLACAS DE OSB 11.1MM', 'M2'),
  ('PLACAS FENOLICA DE 18MM', 'M2'),
  ('PLACAS FENOLICADE 18MM O MACHIMBRE 5” X 3/4”', 'M2'),
  ('POLIETILENO / BOBINA DE PAPEL PROTECTOR', 'M2'),
  ('POLIETILENO DE PROTECCIÓN PARA ABERTURAS', 'M2'),
  ('PORCELANATO', 'M2'),
  ('PRESERVADOR / FUNGICIDA-INSECTICIDA BASE SOLVENTE', 'LTRS'),
  ('PRESERVADOR/FUNGICIDA BASE SOLVENTE', 'LTRS'),
  ('PRIMER / IMPRIMACIÓN EPOXI 100% SÓLIDOS (2 COMP.)', 'LTRS'),
  ('PUENTE DE ADHERENCIA LÍQUIDO (LÁTEX/PRIMER TÁCICO)', 'LTRS'),
  ('PUNTAS PH2 IMPACTO PARA ATORNILLADOR', 'UND'),
  ('REALCES', 'ML'),
  ('RECUBRIMIENTO ELASTOMÉRICO IMPERMEABILIZANTE (3-4 MANOS)', 'LTRS'),
  ('REVESTIMIENTO PLÁSTICO TEXTURADO (TEXTURA MEDIA)', 'KG'),
  ('RODILLO EPOXI PELO CORTO ANTIGOTA', 'UND'),
  ('SELLADOR ELASTOMÉRICO DE FISURAS (MASTIC PU)', 'KG'),
  ('SELLADOR PARA MADERA', 'LTRS'),
  ('SELLADOR POLIURETANICO', 'UND'),
  ('SOLADO CERÁMICO / PORCELLANATO DE EXTERIOR', 'M2'),
  ('SUSPENDIDO TRADICIONAL (CAL/YESO S/ METAL DESPLEGADO)', 'ML'),
  ('SUSTRATO LIVIANO FORMULADO (INCLUYE % COMPACTACIÓN)', 'M3'),
  ('TABLAS', 'M2'),
  ('TABLAS DE MADERA 6”X1”', 'M2'),
  ('TACOS DE EXPANSIÓN 8MM C/TORNILLO', 'UND'),
  ('TARUGO PLÁSTICO', 'UND'),
  ('THINNER / DESENGRASANTE DE LIMPIEZA PREVIA', 'LTRS'),
  ('TIERRA', 'M3'),
  ('TIRANTES', 'M2'),
  ('TORNILLERÍA / BULONES DE MONTAJE', 'KG'),
  ('TORNILLO CABEZA EXAGONAL 10 X 3/4”', 'UND'),
  ('TORNILLO PARA FIJACIÓN', 'UND'),
  ('TORNILLOS ESTRUCTURALES AUTOPERFORANTES O BULONES COMUNES', 'KG'),
  ('TORNILLOS PARA ALFAJIAS 3.1/2” X 8', 'UND'),
  ('TORNILLOS PARA TABLAS 2” X 8', 'UND'),
  ('TORNILLOS T1 CABEZA TANQUE PUNTA MECHA 8X9.5MM', 'UND'),
  ('TORNILLOS T1 MECHA', 'UND'),
  ('TORNILLOS T2 CABEZA TROMPETA PUNTA MECHA 10X1.1/2”', 'UND'),
  ('TORNILLOS T2 CABEZA TROMPETA PUNTA MECHA 8X1.1/4”', 'UND'),
  ('TORNILLOS T2 MECHA / T4 ALAS', 'UND'),
  ('TORNILLOS T2 PUNTA AGUJA', 'UND'),
  ('TORNILLOS T2 PUNTA MECHA CON ALAS 8X1.1/4”', 'UND'),
  ('TORNILLOS T2 PUNTA MECHA CON ALAS 8X1.1/4” O CLAVOS ESPIRALADOS 2”', 'KG'),
  ('TORNILLOS Y TETONES PARA FIJACIONES', 'UND'),
  ('TORNILLOS ZINCADOS PUNTA AGUJA/MECHA 3” CON ARANDELA DE GOMA', 'UND'),
  ('TRAPO DE ESTOPA', 'KG'),
  ('TRAPO MICROFIBRA P/LIMPIEZA DE POLVO', 'UND'),
  ('VENDA / MALLA DE FIBRA DE VIDRIO P/FISURAS (10CM)', 'ML'),
  ('YESO BLANCO', 'KG'),
  ('YESO BLANCO DE CONSTRUCCIÓN TRADICIONAL', 'KG'),
  ('YESO DE TERMINACIÓN (MONOFINO / ENDUIDO)', 'KG'),
  ('YESO DE TERMINACIÓN / ENLUCIDO', 'KG'),
  ('ZOCALO MDF O VINILICO', 'ML')
) as v(nombre, unidad)
where not exists (
  select 1 from insumos i where i.nombre = v.nombre
);

-- =====================================================================
-- Verificación — correr después de las dos secciones de arriba
-- =====================================================================
--
-- Total esperado de insumos de material oficiales tras esta migración: 12 existentes − 6
-- borrados (3 ids perdedores de ARENA + 3 de CEMENTO) + 228 nuevos = 234. Las 6 filas que
-- sobreviven de lo anterior son: 1 ARENA (renombrada), 1 CEMENTO PORTLAND X 25KG (renombrada) y
-- las 4 de "Hierro del 12mm", intactas. Si el número no da 234, avisar el número real antes de
-- tocar nada más — no asumir cuál fue el desvío.

select count(*) as total_material_oficial
from insumos
where tipo = 'material' and creador_usuario_id is null;
