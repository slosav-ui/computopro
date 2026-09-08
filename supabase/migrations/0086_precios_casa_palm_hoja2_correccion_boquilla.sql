-- Segunda hoja del mismo presupuesto de Casa Palm (00001-00168829, 07/09/2026) que 0082 -- pisos,
-- pinturas, madera, tornillería y consumibles. Precio de CONTADO, mismo criterio que 0082/0058.
--
-- =====================================================================
-- Metodología: todo se carga en la unidad del catálogo, nunca la del paquete
-- =====================================================================
--
-- La cotización trae, para cada ítem, precio del paquete/caja/rollo + su equivalencia en unidad de
-- catálogo (ej. "caja x 800", "rollo 50 m²", "pote 4 kg"). El valor que se guarda en `precios` es
-- SIEMPRE precio_paquete / factor -- igual que ya se hizo a mano para HIERRO BARRA ADN 420 en 0082
-- y para el siding/machimbre de esta misma hoja (ver abajo). `unidad_compra`/`factor_conversion` en
-- la tabla `insumos` no se tocan acá (siguen sin usarse salvo casos puntuales ya cargados antes,
-- como CANTONERAS en 0057) -- la conversión se hace una sola vez, a mano, en esta migración, mismo
-- criterio que el resto del proyecto.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado automáticamente
-- por Claude Code: sin acceso a la base de datos desde este entorno.

-- =====================================================================
-- Paso 1 (el que más importa) — corrección del precio de HIZA para la boquilla
-- =====================================================================
--
-- Con el precio de Casa Palm ($2.349,42 = $7.048,26 / 3, blíster) se confirma lo que ya se
-- sospechaba en 0065: el precio de HIZA cargado en 0058 ($8.360) es el blíster de 3 puesto como si
-- fuera precio unitario. $8.360 / 3 = $2.786,67 -- a 0,85% del precio de Felemax ($2.763,17), ya
-- cargado. Con los tres precios reales convertidos (Casa Palm $2.349, Felemax $2.763, HIZA
-- corregido $2.787) el spread queda en 15%, normal -- contra el 3x que había antes. DECISIÓN DE
-- SEBA: corregir con UPDATE, sin borrar la fila (mantiene el historial de que HIZA cotizó esto).
--
-- Nota aparte, no bloqueante: el nombre de este insumo tiene una inconsistencia real de comillas
-- entre migraciones -- 0022 (alta del insumo) usa comilla recta ("), 0058 (el precio que se
-- corrige acá) usa comilla tipográfica ("). No se puede confiar en cuál de las dos quedó
-- efectivamente en `insumos.nombre` sin acceso a la base real, así que el UPDATE de abajo ubica la
-- fila por corralón + valor viejo (8360.0, prácticamente único) en vez de por nombre exacto, y usa
-- `like` con el nombre truncado antes del paréntesis para evitar depender de qué comilla es la
-- real. Mismo criterio se usa en el Paso 3 para el precio nuevo de Casa Palm de este insumo.

update precios
set valor = 2786.67, fecha_actualizacion = '2026-09-08'
where corralon_id = (select id from corralones where nombre = 'HIZA')
  and insumo_id = (
    select id from insumos
    where nombre like 'BOQUILLA / DADO HEXAGONAL MAGNÉTICO%' and creador_usuario_id is null
  )
  and valor = 8360.0;

-- =====================================================================
-- Paso 2 — los 27 ítems limpios de la hoja 2, ya convertidos a precio por unidad de catálogo
-- =====================================================================
--
-- Conversión aplicada (precio de paquete / factor de conversión → precio por unidad de catálogo):
--   PLACAS DE OSB 11.1MM:                     30.882,12 / 2,9768        = 10.374,27 /m²
--   PLACAS FENOLICAS DE 18MM (...):           44.974,25 / 2,9768        = 15.108,26 /m²
--   MACHIMBRE DE PINO/EUCALIPTO 1/2"X4":      42.628,14 / 3,87          = 11.015,02 /m²
--   TORNILLOS T1 CABEZA TANQUE 8X9.5MM:       29.265,68 / 800           =     36,58 /und
--   TORNILLOS T2 PUNTA MECHA 6X1.1/8:         29.871,38 / 700           =     42,67 /und
--   TORNILLOS T2 PUNTA MECHA CON ALAS 8X1.1/4: 6.459,33 / 100           =     64,59 /und
--   TORNILLOS T2 PUNTA AGUJA 6X1:             18.685,62 / 900           =     20,76 /und
--   TORNILLO CABEZA EXAGONAL 10X3/4":         24.562,50 / 350           =     70,18 /und
--   TORNILLO HEXAGONAL PUNTA 17 ZINCADO 14X3": 42.194,61 / 100          =    421,95 /und
--   TACOS DE EXPANSIÓN 8MM C/TORNILLO:         4.659,72 / 100           =     46,60 /und
--   PUNTAS PH2 IMPACTO PARA ATORNILLADOR:      1.142,76 / 10            =    114,28 /und  (*)
--   ADHESIVO DE MONTAJE / COLA VINILICA:      32.623,87 / 4             =  8.155,97 /kg
--   CINTA DE ENMASCARAR AZUL/UV 48MM:          8.463,31 / 50            =    169,27 /ml
--   AGUARRÁS MINERAL P/DILUCIÓN:              17.142,90 / 4             =  4.285,73 /ltrs
--   DILUYENTE:                                132.432,07 / 18          =  7.357,34 /ltrs
--   BANDEJA DESCARTABLE DE PINTURA:           12.167,21 / 10            =  1.216,72 /und (*)
--   TRAPO DE ESTOPA:                           2.122,07 / 0,5           =  4.244,14 /kg
--   MALLA FIBRA DE VIDRIO 160G/M2:            56.515,61 / 50            =  1.130,31 /m²
--   CINTA DE ENMASCARAR 24MM:                  4.295,50 / 40            =    107,39 /ml
--   ANTIOXIDO:                                83.839,90 / 4             = 20.959,98 /ltrs
--   PINTURA LÁTEX INTERIOR LAVABLE (3 MANOS): 200.845,30 / 20           = 10.042,27 /ltrs
--   (resto: factor 1, precio de la cotización directo)
--
-- (*) PUNTAS PH2 y BANDEJA venían con factor 1 en la cotización original, pero comparadas contra el
-- precio ya cargado de Felemax daban 10,7x y 8,5x respectivamente -- mismo patrón que la boquilla.
-- DECISIÓN DE SEBA: vienen por caja/blíster de 10, no por unidad -- factor real 10, no 1.
--
-- SIDING: Casa Palm cotiza 3,60 x 0,20 = 0,72 m² nominal, pero es el mismo producto que Felemax
-- (3,66 x 0,19 = 0,695 m² real) con la medida redondeada. DECISIÓN DE SEBA: usar la medida real de
-- Felemax (0,695), no la nominal de Casa Palm -- 16.286,57 / 0,695 = 23.433,91 /m², va como segundo
-- precio del mismo insumo. MACHIMBRE: confirmado mismo insumo que Felemax/SB Maderas, sin ajuste de
-- medida (a diferencia del siding, acá no se pidió usar la medida de Felemax) -- va con su propia
-- conversión (3,87 m² propios), como tercer precio.
--
-- MALLA FIBRA DE VIDRIO, CINTA DE ENMASCARAR 24MM y ANTIOXIDO ya tenían precio de HIZA -- entran acá
-- como segundo precio del mismo insumo, no como alta nueva (la Lista B original los daba por
-- error como "sin precio" -- verificado contra el catálogo real antes de cargar, corregido).
--
-- PINTURA LÁTEX INTERIOR LAVABLE (3 MANOS) YA EXISTE en el catálogo desde 0022 (fila 300) -- no es
-- alta nueva como se pensó al principio (el catálogo sí tenía este insumo, la búsqueda inicial no
-- lo había encontrado). Este es su primer precio real.
--
-- Observaciones sin bloquear la carga (spread más ancho que el resto, pero sin un patrón tan claro
-- de "paquete cargado como unidad" como para pedir otra verificación):
--   - TORNILLO HEXAGONAL PUNTA 17 ZINCADO 14X3": $421,95 vs Felemax $268,84 y HIZA $198,00 -- ya
--     había 36% de spread entre esos dos antes de sumar Casa Palm.
--   - RODILLO EPOXI PELO CORTO ANTIGOTA: $8.866,87 vs Felemax $6.032,21 (+47%).
--   - DILUYENTE: $7.357,34 vs Felemax $5.661,09 (+30%) -- hay 3 insumos "diluyente" distintos en el
--     catálogo (genérico, /thinner, específico epoxi), puede ser una calidad distinta.
--   - TORNILLOS T2 PUNTA AGUJA 6X1: $20,76 vs Felemax $15,83 (+31%).
--   - HOJA DE LIJA: $1.034,86 vs HIZA $1.778,00 (-42%) -- insumo genérico que ya absorbió varias
--     variantes de grano (0066), spread ancho esperable.
--
-- No se cargan (decisión de Seba, ver conversación): MASILLA TIPO ENDUIDO (balde en litros, precio
-- ya cargado de HIZA en kg -- sin el peso real del balde no se puede convertir; el balde tendría
-- que pesar 58kg para que cerrara contra el precio de HIZA, imposible para 25 litros -- queda
-- pendiente con el peso real) y CANTONERAS METÁLICAS/PLÁSTICAS P/ESQUINAS (zócalo Curves, producto
-- distinto -- Casa Palm ya cargó la cantonera real en la hoja 1, 0082).
--
-- Tampoco se cargan (sin precio de Casa Palm, fuera de alcance de esta ronda): Zen Hueso y Perla
-- Satin (nombres comerciales, el catálogo usa genéricos con referencia -- no mezclar), y los 10
-- ítems sin equivalente claro en el catálogo (sellador acrílico, Kem Satin, sellador Fischer MS,
-- disco de corte de madera 7", copa clásica 67mm, grampas de engrampadora, lija al agua 220,
-- tornillos Drywall madera, tacos metálicos MR, y Pastina Klaukol -- esta última SÍ tiene match
-- genérico ya en el catálogo, "PASTINA", pero sin precio de Casa Palm para cargar).

insert into precios (insumo_id, corralon_id, valor, fecha_actualizacion)
select i.id, c.id, v.valor, '2026-09-07'
from (values
  ('PLACAS DE OSB 11.1MM', 10374.27),
  ('PLACAS FENOLICAS DE 18MM O MACHIMBRE 5” X 3/4”', 15108.26),
  ('MACHIMBRE DE PINO/EUCALIPTO 1/2” X 4”', 11015.02),
  ('PLACAS / TABLAS DE SIDING 19CM X 3.60M', 23433.91),
  ('TORNILLOS T1 CABEZA TANQUE PUNTA MECHA 8X9.5MM', 36.58),
  ('TORNILLOS T2 PUNTA MECHA 6X1.1/8', 42.67),
  ('TORNILLOS T2 PUNTA MECHA CON ALAS 8X1.1/4”', 64.59),
  ('TORNILLOS T2 PUNTA AGUJA 6X1', 20.76),
  ('TORNILLO CABEZA EXAGONAL 10 X 3/4”', 70.18),
  ('TORNILLO HEXAGONAL PUNTA 17 ZINCADO 14 X 3"', 421.95),
  ('CLAVOS ESPIRALADOS / ESTRIADOS PARA CLAVADORA (2.5” A 3”)', 5454.02),
  ('CLAVOS', 6007.98),
  ('CLAVOS CABEZA PERDIDA 12 X 50MM', 9645.26),
  ('TACOS DE EXPANSIÓN 8MM C/TORNILLO', 46.60),
  ('PUNTAS PH2 IMPACTO PARA ATORNILLADOR', 114.28),
  ('DISCOS DE CORTE PARA AMOLADORA (115 X 1MM)', 2800.27),
  ('DISCOS DE CORTE PARA AMOLADORA (180 X 1,6MM)', 4033.44),
  ('MECHA WIDIA PARA CONCRETO 10MM', 5579.62),
  ('HOJAS DE LIJA PARA MAMPOSTERÍA N° 100/120', 1034.86),
  ('HOJA DE LIJA', 1034.86),
  ('ADHESIVO DE MONTAJE / COLA VINILICA', 8155.97),
  ('CINTA DE ENMASCARAR AZUL/UV 48MM', 169.27),
  ('AGUARRÁS MINERAL P/DILUCIÓN', 4285.73),
  ('DILUYENTE', 7357.34),
  ('BANDEJA DESCARTABLE DE PINTURA', 1216.72),
  ('RODILLO EPOXI PELO CORTO ANTIGOTA', 8866.87),
  ('TRAPO DE ESTOPA', 4244.14),
  ('MALLA FIBRA DE VIDRIO 160G/M2', 1130.31),
  ('CINTA DE ENMASCARAR 24MM', 107.39),
  ('ANTIOXIDO', 20959.98),
  ('PINTURA LÁTEX INTERIOR LAVABLE (3 MANOS)', 10042.27)
) as v(insumo_nombre, valor)
join insumos i on i.nombre = v.insumo_nombre and i.creador_usuario_id is null
cross join corralones c
where c.nombre = 'Casa Palm'
  and not exists (select 1 from precios p where p.insumo_id = i.id and p.corralon_id = c.id);

-- =====================================================================
-- Paso 3 — precio de Casa Palm para la boquilla, aparte por la ambigüedad de comillas (ver Paso 1)
-- =====================================================================

insert into precios (insumo_id, corralon_id, valor, fecha_actualizacion)
select i.id, c.id, 2349.42, '2026-09-07'
from insumos i
cross join corralones c
where i.nombre like 'BOQUILLA / DADO HEXAGONAL MAGNÉTICO%' and i.creador_usuario_id is null
  and c.nombre = 'Casa Palm'
  and not exists (select 1 from precios p where p.insumo_id = i.id and p.corralon_id = c.id);

-- =====================================================================
-- Verificación
-- =====================================================================

-- 1) Tienen que haber entrado 31 filas nuevas (27 del bloque principal + boquilla), fecha
--    2026-09-07 -- si da menos, algún nombre no matcheó (ver diagnóstico del punto 2).
select count(*) as filas_casa_palm_hoja2
from precios p
join corralones c on c.id = p.corralon_id
where c.nombre = 'Casa Palm' and p.fecha_actualizacion = '2026-09-07';

-- 2) Diagnóstico: de los 31 nombres de esta hoja (30 del bloque + boquilla), ¿cuáles NO
--    encontraron insumo? Tiene que devolver 0 filas -- cualquier fila acá es un nombre que no
--    matcheó contra el catálogo, no cargado en silencio.
select v.insumo_nombre
from (values
  ('PLACAS DE OSB 11.1MM'), ('PLACAS FENOLICAS DE 18MM O MACHIMBRE 5” X 3/4”'),
  ('MACHIMBRE DE PINO/EUCALIPTO 1/2” X 4”'), ('PLACAS / TABLAS DE SIDING 19CM X 3.60M'),
  ('TORNILLOS T1 CABEZA TANQUE PUNTA MECHA 8X9.5MM'), ('TORNILLOS T2 PUNTA MECHA 6X1.1/8'),
  ('TORNILLOS T2 PUNTA MECHA CON ALAS 8X1.1/4”'), ('TORNILLOS T2 PUNTA AGUJA 6X1'),
  ('TORNILLO CABEZA EXAGONAL 10 X 3/4”'), ('TORNILLO HEXAGONAL PUNTA 17 ZINCADO 14 X 3"'),
  ('CLAVOS ESPIRALADOS / ESTRIADOS PARA CLAVADORA (2.5” A 3”)'), ('CLAVOS'),
  ('CLAVOS CABEZA PERDIDA 12 X 50MM'), ('TACOS DE EXPANSIÓN 8MM C/TORNILLO'),
  ('PUNTAS PH2 IMPACTO PARA ATORNILLADOR'), ('DISCOS DE CORTE PARA AMOLADORA (115 X 1MM)'),
  ('DISCOS DE CORTE PARA AMOLADORA (180 X 1,6MM)'), ('MECHA WIDIA PARA CONCRETO 10MM'),
  ('HOJAS DE LIJA PARA MAMPOSTERÍA N° 100/120'), ('HOJA DE LIJA'),
  ('ADHESIVO DE MONTAJE / COLA VINILICA'), ('CINTA DE ENMASCARAR AZUL/UV 48MM'),
  ('AGUARRÁS MINERAL P/DILUCIÓN'), ('DILUYENTE'), ('BANDEJA DESCARTABLE DE PINTURA'),
  ('RODILLO EPOXI PELO CORTO ANTIGOTA'), ('TRAPO DE ESTOPA'), ('MALLA FIBRA DE VIDRIO 160G/M2'),
  ('CINTA DE ENMASCARAR 24MM'), ('ANTIOXIDO'), ('PINTURA LÁTEX INTERIOR LAVABLE (3 MANOS)')
) as v(insumo_nombre)
where not exists (
  select 1 from insumos i where i.nombre = v.insumo_nombre and i.creador_usuario_id is null
);

-- 3) Ningún insumo con dos precios del mismo corralón (chequeo de siempre).
select insumo_id, corralon_id, count(*) as filas
from precios
group by insumo_id, corralon_id
having count(*) > 1;

-- 4) Boquilla: los 3 precios reales tienen que quedar dentro de un rango razonable (antes de esta
--    migración el spread era 3x -- 8.360 vs 2.763 -- ahora tiene que dar bien por debajo de 1,2).
select c.nombre as corralon, p.valor
from precios p
join corralones c on c.id = p.corralon_id
where p.insumo_id = (
  select id from insumos
  where nombre like 'BOQUILLA / DADO HEXAGONAL MAGNÉTICO%' and creador_usuario_id is null
)
order by p.valor;

select
  max(p.valor) / min(p.valor) as spread_max_sobre_min
from precios p
where p.insumo_id = (
  select id from insumos
  where nombre like 'BOQUILLA / DADO HEXAGONAL MAGNÉTICO%' and creador_usuario_id is null
);
-- esperado: 3 filas (Casa Palm ~2.349,42, Felemax 2.763,17, HIZA 2.786,67) y spread ~1,19 (19%),
-- muy por debajo del 3,03 que daba antes de corregir HIZA.
