-- Segunda tanda de precios de HIZA (mayormente tornillería/aislaciones de Steel Frame, varias de
-- ellas los insumos que quedaban sin cotizar de las partidas 5.x/6.x -- ver diagnóstico de la
-- solapa APU) más 3 precios de Felemax. Depende de 0064 (correccion_partidas_duplicadas_como_
-- insumo) ya aplicada -- dos de los insumos de la carga original ya no existen en el catálogo
-- (HORMIGÓN DE PENDIENTE, CARPETA DE NIVELACIÓN), por eso no están en este archivo.
--
-- Contado, con IVA incluido, sin flete (mismo criterio que toda la carga anterior).
-- fecha_actualizacion: 05/09/2026, confirmada por Seba (misma fecha que el resto de la carga de
-- HIZA/Felemax de esta ronda).
--
-- =====================================================================
-- CINCO ITEMS DE LA LISTA ORIGINAL, DELIBERADAMENTE NO INCLUIDOS ACA
-- =====================================================================
--
-- 1. BOQUILLA / DADO HEXAGONAL MAGNÉTICO (1/4” O 5/16”), HIZA -- $4.085 en esta lista, pero HIZA ya
--    tiene un precio cargado para este mismo insumo desde 0058: $8.360. Casi el doble de diferencia
--    para el mismo corralon y el mismo insumo. DECISION DE SEBA: no se toca -- el precio de HIZA
--    para este insumo sigue siendo $8.360, el $4.085 de esta lista no se carga.
--
-- 2. CHAPA SINUSOIDAL – COLOR C25, HIZA -- $73.756 / 3,3 m2 = $22.350/m2. El catálogo tiene DOS
--    insumos de chapa sinusoidal distintos: este (M2, variante de color, usado en Steel Frame
--    5.6/6.6/15.3, sin precio) y 'CHAPA SINUSOIDAL O TRAPEZOIDAL' (ML, generico, ya con precio de
--    Felemax). El nombre y la unidad de este precio matchean limpio contra COLOR C25 -- pero Seba
--    avisó que HIZA ya cotizó "chapa sinusoidal por metro" a $24.586 en su presupuesto formal, con
--    apenas 10% de diferencia contra este. Esos dos números (COLOR C25 a $22.350/m2 y el de
--    $24.586/ml) son de UNIDADES distintas (M2 contra ML) -- no se puede promediar ni elegir uno
--    sin saber si HIZA está cotizando el mismo producto dos veces con dos criterios de medida, o si
--    son dos productos realmente distintos (coloreado vs. genérico) que casualmente cuestan
--    parecido. Falta esa aclaración antes de cargar cualquiera de los dos números de HIZA acá.
--
-- 3. AISLACION TERMICA (LANA DE VIDRIO 50MM), HIZA -- $137.924, "rollo 21,6 m2". El catálogo NO
--    tiene ningún insumo con ese nombre exacto -- el único insumo de 50mm es 'AISLACION TERMICA EPS
--    O LANA DE VIDRIO 50MM', hoy en ML (no M2), lo que ya de por sí no encaja con "rollo 21,6 m2"
--    sin saber el ancho del rollo.
--
-- 4. AISLACION TERMICA EPS O LANA DE VIDRIO 50MM, HIZA -- $14.708, "placa 1 m2" -- mismo precio y
--    mismo formato de envase que la fila de abajo (EPS ALTA DENSIDAD), que sí se carga. ¿Son dos
--    nombres para el mismo producto (HIZA cotizándolo dos veces), o dos productos reales que
--    casualmente cuestan lo mismo? Mientras esto no se aclare, se carga solo EPS ALTA DENSIDAD (sin
--    ambigüedad de nombre ni de unidad) y se deja afuera esta fila y la del punto 3.
--
-- 5. BANDA ACUSTICA BAJO SOLERA 100MM, HIZA -- $3.952,01, "rollo 3 m". El catálogo la tiene en UND,
--    no en ML -- y el rendimiento real que ya usan las partidas 6.3 (1) y 6.4 (30) para este mismo
--    insumo hace sospechar que la unidad está mal (30 "unidades" de banda por m2 de entrepiso no
--    tiene sentido físico; 30 ML sí). Mismo patrón de bug que PIEDRA/TABLAS/TIRANTES (0062) -- no
--    se corrige a ciegas ni se carga el precio hasta confirmar la unidad real.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor), después de 0064. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.
--
-- =====================================================================
-- Hallazgo aparte, no bloqueante para esta migración -- anotado para revisar después
-- =====================================================================
--
-- AISLACION TERMICA (LANA DE VIDRIO 100MM) SÍ se carga acá (limpio, sin ambigüedad). Pero al
-- verificar dónde se usa cada aislación se encontró que el precio de Felemax cargado en 0058 bajo
-- 'AISLACION ACUSTICA (LANA DE VIDRIO 100MM)' (Lana De Vidrio Cubierta Plata) quedó en el insumo
-- equivocado o, al menos, en uno mucho menos usado: ACUSTICA se usa en una sola partida (5.4),
-- mientras que TERMICA (esta que se carga acá) se usa en siete (5.1/5.2/5.3/6.1/6.2/6.3/6.4). No se
-- toca ese precio de Felemax acá -- puede ser un producto genuinamente distinto (acústico para
-- entrepisos vs. térmico para muros) o un error de mapeo de una carga anterior. DECISION DE SEBA:
-- queda anotado sin corregir por ahora -- no se toca el precio de Felemax en ACUSTICA.

insert into precios (insumo_id, corralon_id, valor, fecha_actualizacion)
select i.id, c.id, v.valor, '2026-09-05'
from (values
  ('ALAMBRE NEGRO', 'HIZA', 4362.0),
  ('CLAVOS', 'HIZA', 4908.99),
  ('TORNILLOS T1 CABEZA TANQUE PUNTA MECHA 8X9.5MM', 'HIZA', 50.092),
  ('AISLACION TERMICA (LANA DE VIDRIO 100MM)', 'HIZA', 13294.5819),
  ('PASTINA', 'HIZA', 4473.4),
  ('AISLACION HIDROFUGA TIPO TYVEK', 'HIZA', 1707.267),
  ('TORNILLOS T2 CABEZA TROMPETA PUNTA MECHA 10X1.1/2”', 'HIZA', 84.88),
  ('BANDA HIDROFUGA. MEMBRANA AUTOADESIVA (TIPO BLACK IRON)  100MM', 'HIZA', 6050.0),
  ('BROCA MECANICA DE EXPANCION, ANCLAJE QUIMICO DIAM10MM (3/8”X3.1/2”)', 'HIZA', 1377.0),
  ('ANTIOXIDO', 'HIZA', 16556.25),
  ('ANCLAJE ESCUADRA DE TRACCION HTT14', 'HIZA', 13973.0),
  ('ANCLAJE ESCUADRA METALICO GALVANIZADO', 'HIZA', 13973.0),
  ('CAÑO ESTRUCTURAL CUADRADO/RECTANGULAR O PERFIL C CONFORMADO EN FRÍO', 'HIZA', 3212.7667),
  ('CINTA DE ENMASCARAR 24MM', 'HIZA', 114.75),
  ('CLAVOS ESPIRALADOS / ESTRIADOS PARA CLAVADORA (2.5” A 3”)', 'HIZA', 6514.0),
  ('FLEJE DE ACERO GALVANIZADO, CRUCE DE SAN ANDRES 0.9MM X 100MM', 'HIZA', 1918.401),
  ('LISTONES DE REALCE 1” X 10MM', 'HIZA', 274.44),
  ('MALLA FIBRA DE VIDRIO 160G/M2', 'HIZA', 901.18),
  ('TORNILLOS T2 CABEZA TROMPETA PUNTA MECHA 8X1.1/4”', 'HIZA', 72.475),
  ('EPS ALTA DENSIDAD', 'HIZA', 14708.0),
  ('BARNIZ', 'HIZA', 13366.0),
  ('CINTA DE PAPEL', 'HIZA', 145.3814),
  ('CLIPS DE RETENCIÓN CONTRA VIENTO', 'HIZA', 4.201),
  ('HOJA DE LIJA', 'HIZA', 1778.0),
  ('IMPRIMACIÓN ASFÁLTICA BASE AGUA', 'HIZA', 11388.0),
  ('MASILLA TIPO ENDUIDO', 'HIZA', 1684.6563),
  ('BASE COAT MONOCOMPONENTE', 'Felemax', 1389.056),
  ('MANTA BAJOS PISO, ESPUMA DE POLIETILENO 2MM', 'Felemax', 1961.55),
  ('MASILLA PARA MADERA', 'Felemax', 9780.4)
) as v(insumo_nombre, corralon_nombre, valor)
join insumos i on i.nombre = v.insumo_nombre and i.creador_usuario_id is null
join corralones c on c.nombre = v.corralon_nombre;

-- =====================================================================
-- Verificación
-- =====================================================================

-- 1) 29 filas nuevas (26 HIZA + 3 Felemax). Si da menos, algún nombre no matcheó -- parar y
--    revisar cuál antes de seguir, no asumir.
select count(*) as precios_cargados_esta_tanda
from precios p
join corralones c on c.id = p.corralon_id
join insumos i on i.id = p.insumo_id
where (c.nombre, i.nombre) in (
  ('HIZA', 'ALAMBRE NEGRO'), ('HIZA', 'CLAVOS'),
  ('HIZA', 'TORNILLOS T1 CABEZA TANQUE PUNTA MECHA 8X9.5MM'),
  ('HIZA', 'AISLACION TERMICA (LANA DE VIDRIO 100MM)'), ('HIZA', 'PASTINA'),
  ('HIZA', 'AISLACION HIDROFUGA TIPO TYVEK'),
  ('HIZA', 'TORNILLOS T2 CABEZA TROMPETA PUNTA MECHA 10X1.1/2”'),
  ('HIZA', 'BANDA HIDROFUGA. MEMBRANA AUTOADESIVA (TIPO BLACK IRON)  100MM'),
  ('HIZA', 'BROCA MECANICA DE EXPANCION, ANCLAJE QUIMICO DIAM10MM (3/8”X3.1/2”)'),
  ('HIZA', 'ANTIOXIDO'), ('HIZA', 'ANCLAJE ESCUADRA DE TRACCION HTT14'),
  ('HIZA', 'ANCLAJE ESCUADRA METALICO GALVANIZADO'),
  ('HIZA', 'CAÑO ESTRUCTURAL CUADRADO/RECTANGULAR O PERFIL C CONFORMADO EN FRÍO'),
  ('HIZA', 'CINTA DE ENMASCARAR 24MM'),
  ('HIZA', 'CLAVOS ESPIRALADOS / ESTRIADOS PARA CLAVADORA (2.5” A 3”)'),
  ('HIZA', 'FLEJE DE ACERO GALVANIZADO, CRUCE DE SAN ANDRES 0.9MM X 100MM'),
  ('HIZA', 'LISTONES DE REALCE 1” X 10MM'), ('HIZA', 'MALLA FIBRA DE VIDRIO 160G/M2'),
  ('HIZA', 'TORNILLOS T2 CABEZA TROMPETA PUNTA MECHA 8X1.1/4”'),
  ('HIZA', 'EPS ALTA DENSIDAD'), ('HIZA', 'BARNIZ'), ('HIZA', 'CINTA DE PAPEL'),
  ('HIZA', 'CLIPS DE RETENCIÓN CONTRA VIENTO'), ('HIZA', 'HOJA DE LIJA'),
  ('HIZA', 'IMPRIMACIÓN ASFÁLTICA BASE AGUA'), ('HIZA', 'MASILLA TIPO ENDUIDO'),
  ('Felemax', 'BASE COAT MONOCOMPONENTE'),
  ('Felemax', 'MANTA BAJOS PISO, ESPUMA DE POLIETILENO 2MM'),
  ('Felemax', 'MASILLA PARA MADERA')
);

-- 2) Cuántos insumos de material quedan sin ningún precio real ahora.
select count(*) as insumos_material_sin_precio
from insumos i
where i.tipo = 'material' and i.creador_usuario_id is null
  and not exists (select 1 from precios p where p.insumo_id = i.id);

-- 3) Las partidas de Steel Frame que antes daban muy incompletas por falta de tornillería/
--    aislación real (5.1, 5.4, 6.1) -- para ver cuánto mejoró la cobertura, no hace falta que den
--    completo (la mano de obra depende de 0059, y puede haber otros insumos min-usados sin precio
--    todavía).
-- select * from calcular_precio_apu_subitems(
--   '<obra_id>'::uuid,
--   array[
--     (select id from subitems where codigo = '5.1' and creador_usuario_id is null),
--     (select id from subitems where codigo = '5.4' and creador_usuario_id is null),
--     (select id from subitems where codigo = '6.1' and creador_usuario_id is null)
--   ]
-- );
