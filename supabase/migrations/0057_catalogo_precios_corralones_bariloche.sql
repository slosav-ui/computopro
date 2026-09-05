-- Catalogo de insumos para la carga de precios reales de corralones de Bariloche (Solido,
-- Felemax, SB Maderas) + HIZA como referencia adicional para algunos items de ferreteria.
-- Ver supabase/seed_staging/mapeo_precios_corralones_2026-09-04.csv para el detalle linea por
-- linea de cada decision (que corralon dio que precio, por que se eligio cada insumo, que quedo
-- excluido). Este archivo SOLO toca `insumos`/`apu_composicion_items` -- la carga de `precios` y
-- los 4 corralones nuevos es la migracion siguiente (0058), deliberadamente separada para poder
-- verificar que el catalogo entro bien antes de correr la carga mas grande -- mismo criterio que
-- 0022/0023.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project -> SQL Editor). No ejecutado
-- automaticamente por Claude Code: sin acceso a la base de datos desde este entorno.
--
-- =====================================================================
-- Seccion 1 -- Altas: 9 insumos nuevos de ferreteria/steel frame
-- =====================================================================
--
-- Ninguno de estos productos tenia equivalente en el catalogo (verificado contra los 205 insumos
-- de material existentes antes de crear cada uno, no se adivino ninguno). Precio de HIZA cuando
-- corresponde, o de Felemax si HIZA no lo cotizo -- ver 0058 para el detalle de precios.

insert into insumos (nombre, unidad, categoria, tipo, unidad_compra, factor_conversion)
select v.nombre, v.unidad, 'material', 'material', v.unidad_compra, v.factor_conversion
from (values
  ('TORNILLO HEXAGONAL PUNTA 17 ZINCADO 14 X 3"', 'UND', 'caja x100 (HIZA)', 100),
  ('TORNILLO MADERA FIC 8 X 2 (21X50MM)', 'UND', 'bolsa x150 (HIZA)', 150),
  ('TORNILLO MADERA 10 X 3 3/4"', 'UND', 'bolsa x100 (HIZA)', 100),
  ('ANCLAJE DE EXPANSION POR GOLPE M10 X 85', 'UND', null, null),
  ('ANCLAJE DE EXPANSION POR GOLPE M8 X 70', 'UND', null, null),
  ('CLAVOS CABEZA PERDIDA 12 X 50MM', 'KG', null, null),
  ('TORNILLOS T2 PUNTA MECHA 6X1.1/8', 'UND', null, null),
  ('TORNILLOS T2 PUNTA MECHA CON ALAS 10X1.1/2', 'UND', null, null),
  ('MALLA ELECTROSOLDADA Q188 15/15', 'M2', 'paño 6m x 2,40m (14,4 m²)', 14.4)
) as v(nombre, unidad, unidad_compra, factor_conversion)
where not exists (
  select 1 from insumos i where i.nombre = v.nombre
);


-- =====================================================================
-- Seccion 2 -- Renombres de filas existentes (4)
-- =====================================================================
--
-- Ninguno de estos renombres cambia insumo_id ni unidad -- las composiciones de APU que ya
-- referencian estos insumos (verificado contra 0023/0024 antes de escribir esto) siguen intactas,
-- solo cambia como se llaman.

-- 1) HIDROFUGO EN PASTA -> HIDROFUGO: Sika/Mapei liquido, caja de 20kg. La mayoria de los
--    hidrofugos en uso hoy son liquidos y la presentacion no cambia el uso en la receta -- se
--    renombra sin especificar presentacion para que entre cualquiera de las dos sin tocar
--    composiciones. Usado en 9.1/9.2/9.3/10.4 (Capas Aisladoras/Revoques).
update insumos set nombre = 'HIDROFUGO', unidad_compra = 'caja/sachet 20kg', factor_conversion = 20
where nombre = 'HIDROFUGO EN PASTA' and creador_usuario_id is null;

-- 2) TORNILLOS T1 MECHA -> toma la medida cotizada (8X9/16). Sin variante previa (usado en 16.3,
--    unico lugar), no genera ambiguedad.
update insumos set nombre = 'TORNILLOS T1 MECHA 8X9/16'
where nombre = 'TORNILLOS T1 MECHA' and creador_usuario_id is null;

-- 3) TORNILLOS T2 PUNTA AGUJA -> toma la medida cotizada (6X1). Sin variante previa (usado en
--    14.5/15.5), no genera ambiguedad.
update insumos set nombre = 'TORNILLOS T2 PUNTA AGUJA 6X1'
where nombre = 'TORNILLOS T2 PUNTA AGUJA' and creador_usuario_id is null;

-- 4) El insumo bundleado de discos se separa: HIZA cotizo las dos medidas (115x1mm y 180x1,6mm)
--    por separado, con precios reales distintos -- ya no hace falta que compartan una sola fila.
--    OJO: '(115 X 1MM)' YA EXISTIA como fila propia y separada desde 0022 (usada en 5.6/6.6/15.3)
--    -- no se crea de nuevo, solo se renombra la mitad bundleada para que quede sola con '180 X
--    1,6MM' (usada en 5.1/5.2/5.3/5.4/5.5/6.5).
update insumos set nombre = 'DISCOS DE CORTE PARA AMOLADORA (180 X 1,6MM)'
where nombre = 'DISCOS DE CORTE PARA AMOLADORA (115 X 1MM O 180 X 1,6 MM)' and creador_usuario_id is null;


-- =====================================================================
-- Seccion 3 -- Recreacion: revierte parte de 0049 (CINTA DE ENMASCARAR)
-- =====================================================================
--
-- 0049_limpieza_catalogo_insumos.sql unifico 'CINTA DE ENMASCARAR 24MM' y 'CINTA DE ENMASCARAR
-- AZUL/UV 48MM' en un solo insumo, sin precio real que lo justificara en ese momento. Con precio
-- real de cada ancho ($8.120 la de 24mm, $12.789/$6.867 contado la de 48mm -- casi el doble), la
-- unificacion deja de tener sentido: vuelven a ser dos insumos. DECISION EXPLICITA DE SEBA, anotada
-- porque revierte una limpieza reciente.

insert into insumos (nombre, unidad, categoria, tipo, unidad_compra, factor_conversion)
select 'CINTA DE ENMASCARAR AZUL/UV 48MM', 'ML', 'material', 'material', 'rollo 40m', 40
where not exists (
  select 1 from insumos where nombre = 'CINTA DE ENMASCARAR AZUL/UV 48MM'
);

-- La reasignacion de composiciones que importa: 0049 habia movido la referencia de la partida 17.2
-- (LATEX EXTERIOR/IMPERMEABILIZANTE sobre mamposteria, la que originalmente usaba la cinta de
-- 48mm) al insumo de 24mm. Si no se revierte esta fila puntual, la separacion de arriba no cambia
-- nada: 17.2 seguiria calculando con el precio de la cinta equivocada. Las otras partidas que usan
-- 'CINTA DE ENMASCARAR 24MM' (16.1, 17.1) y la que usa la generica sin medida absorbida en 24mm
-- (17.5, decision previa e independiente de esta) NO se tocan -- nunca usaron la de 48mm.
update apu_composicion_items
set insumo_id = (select id from insumos where nombre = 'CINTA DE ENMASCARAR AZUL/UV 48MM' and creador_usuario_id is null)
where insumo_id = (select id from insumos where nombre = 'CINTA DE ENMASCARAR 24MM' and creador_usuario_id is null)
  and apu_composicion_id = (
    select ac.id from apu_composiciones ac
    join subitems s on s.id = ac.subitem_id
    where s.codigo = '17.2' and s.creador_usuario_id is null and ac.creador_usuario_id is null
  );


-- =====================================================================
-- Seccion 4 -- Cantoneras: unidad de insumo (ML) distinta de unidad de subitem (M2)
-- =====================================================================
--
-- No era un error de carga: el subitem que usa cantoneras se mide en M2, pero la cantonera como
-- insumo se compra y se usa en ML -- mismo patron que HIERRO BARRA ADN 420 (TON) dentro de un
-- subitem en M3. Se corrige la unidad del insumo.

update insumos set unidad = 'ML', unidad_compra = 'tira 2,60m', factor_conversion = 2.60
where nombre = 'CANTONERAS METÁLICAS / PLÁSTICAS P/ESQUINAS' and creador_usuario_id is null;

-- PENDIENTE, A PROPOSITO NO INCLUIDO ACA: el rendimiento de apu_composicion_items para la partida
-- 16.1 (unico uso actual de este insumo, rendimiento = 0.35) fue calculado cuando el insumo estaba
-- en M2 -- ahora que es ML, ese numero puede seguir siendo valido (si ya representaba ml/m2 en la
-- planilla original) o puede necesitar recalculo. No se toca sin el numero real de Seba -- cargar
-- el precio de la cantonera en 0058 no depende de esto, pero el costo calculado de la partida 16.1
-- va a estar mal hasta que se resuelva. Verificar contra la planilla fuente antes de tocar:
--
--   select aci.rendimiento from apu_composicion_items aci
--   join apu_composiciones ac on ac.id = aci.apu_composicion_id
--   join subitems s on s.id = ac.subitem_id
--   where s.codigo = '16.1' and aci.insumo_id = (
--     select id from insumos where nombre = 'CANTONERAS METÁLICAS / PLÁSTICAS P/ESQUINAS'
--   );


-- =====================================================================
-- Verificacion -- correr despues de aplicar todo lo de arriba
-- =====================================================================

-- 1) Altas: esperado 10 (9 de ferreteria + la cinta de 48mm recreada).
select count(*) as altas_nuevas from insumos
where nombre in (
  'TORNILLO HEXAGONAL PUNTA 17 ZINCADO 14 X 3"',
  'TORNILLO MADERA FIC 8 X 2 (21X50MM)',
  'TORNILLO MADERA 10 X 3 3/4"',
  'ANCLAJE DE EXPANSION POR GOLPE M10 X 85',
  'ANCLAJE DE EXPANSION POR GOLPE M8 X 70',
  'CLAVOS CABEZA PERDIDA 12 X 50MM',
  'TORNILLOS T2 PUNTA MECHA 6X1.1/8',
  'TORNILLOS T2 PUNTA MECHA CON ALAS 10X1.1/2',
  'MALLA ELECTROSOLDADA Q188 15/15',
  'CINTA DE ENMASCARAR AZUL/UV 48MM'
) and creador_usuario_id is null;

-- 2) Renombres: esperado 0 filas con los nombres viejos (deberian haber desaparecido).
select nombre from insumos
where nombre in ('HIDROFUGO EN PASTA', 'TORNILLOS T1 MECHA', 'TORNILLOS T2 PUNTA AGUJA',
                  'DISCOS DE CORTE PARA AMOLADORA (115 X 1MM O 180 X 1,6 MM)')
  and creador_usuario_id is null;

-- 3) La partida 17.2 tiene que apuntar a la cinta de 48mm, ninguna otra partida de cinta debe
--    haber cambiado.
select s.codigo, i.nombre
from apu_composicion_items aci
join apu_composiciones ac on ac.id = aci.apu_composicion_id
join subitems s on s.id = ac.subitem_id
join insumos i on i.id = aci.insumo_id
where i.nombre in ('CINTA DE ENMASCARAR 24MM', 'CINTA DE ENMASCARAR AZUL/UV 48MM', 'CINTA DE ENMASCARAR')
  and ac.creador_usuario_id is null
order by s.codigo;
-- esperado: 16.1 y 17.1 -> 24MM, 17.2 -> AZUL/UV 48MM, 17.5 -> CINTA DE ENMASCARAR (generica, sin
-- relacion con esta pieza).

-- 4) Ningun apu_composicion_items debe quedar huerfano (mismo chequeo que 0049).
select count(*) as huerfanos
from apu_composicion_items ci
left join insumos i on i.id = ci.insumo_id
where i.id is null;

-- 5) Cantonera: confirmar unidad ML y ver el rendimiento pendiente de revisar (ver Seccion 4).
select nombre, unidad, unidad_compra, factor_conversion from insumos
where nombre = 'CANTONERAS METÁLICAS / PLÁSTICAS P/ESQUINAS';
