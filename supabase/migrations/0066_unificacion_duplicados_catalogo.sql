-- Unificación de 42 insumos duplicados del catálogo (rubros 2-17), según el relevamiento completo
-- de Seba ("Unificación de duplicados"). Cuatro grupos según si tenían precio cargado:
--   Grupo A -- uno de los dos tenía precio (o ninguno tenía, en la mayoría de los pares)
--   Grupo B -- los DOS tenían precio de corralones distintos -- el sobreviviente se queda con
--              ambas filas de `precios` como proveedores distintos, no se pierde ninguna
--   Grupo C -- ninguno tenía precio
--   Grupo D -- el ya resuelto en la ronda anterior (tornillo T2 sin uso, ver 0065)
--
-- Regla aplicada en todos los casos: primero se reasignan las referencias de
-- `apu_composicion_items` y `precios` al insumo sobreviviente, recién después se borra el
-- absorbido -- mismo orden que 0064. Ningún par tuvo dos precios del MISMO corralón cayendo sobre
-- el mismo insumo (verificado uno por uno contra 0057-0065 antes de escribir esto) -- así que no
-- hizo falta promediar en ningún caso, aunque la regla estaba prevista.
--
-- Cinco pares necesitaban conversión de unidad real (no solo de nombre) porque el sobreviviente
-- queda en una unidad distinta a la del absorbido, y el absorbido tenía uso real en alguna
-- composición -- resueltos con Seba antes de escribir este archivo, con el criterio de cada
-- conversión documentado en la Sección 4 más abajo: TABLAS (M2->ML, ancho de tabla),
-- CANTO RODADO DE CONTENCIÓN PERIMETRAL (KG->M3, densidad de grava rodada 1.600 kg/m³),
-- CHAPA SINUSOIDAL O TRAPEZOIDAL (ML->M2, ancho de chapa 1,1m), BANDA ACUSTICA BAJO SOLERA
-- (UND->ML, con un error de carga real encontrado de paso en la 6.4 -- ver Sección 4), y
-- TRAPO MICROFIBRA (UND->KG, peso de paño estándar).
--
-- CORRECCIÓN sobre una sospecha propia, descartada: se llegó a pensar que la fila de precio
-- ('ESMALTE SINTÉTICO', 'Felemax', 12668.9) de 0058 nunca había impactado -- resultó falso. 0049
-- (Sección 3) ya había renombrado 'ESMALTE DE TERMINACIÓN' a 'ESMALTE SINTÉTICO' antes de que 0058
-- corriera, así que ese insumo sí existe y el precio sí se cargó -- es un tercer insumo de esmalte,
-- distinto de los dos '(2 MANOS)' de esta unificación. El sobreviviente de este archivo (Sección 1)
-- es 'ESMALTE SINTÉTICO', que ya trae ese precio de Felemax puesto -- no 'ESMALTE SINTÉTICO DE
-- TERMINACIÓN (2 MANOS)' (nombre de 0022, borrado por 0049 tras reasignar sus composiciones a
-- 'ESMALTE DE TERMINACIÓN', luego renombrado). Auditoría completa pedida por Seba sobre las 114
-- filas de 0058: se verificaron los 114 nombres de insumo contra el catálogo real vigente al
-- momento en que 0058 corrió (0022 + los 12 renombres/25 bajas de 0049 + las 9 altas/4 renombres/1
-- recreación de 0057) -- las 114 impactaron. Ningún otro caso como el de esmalte.
--
-- Encontrados y corregidos al hacer esa auditoría, dos nombres más de este mismo archivo que
-- quedaron con la forma vieja (pre-0049) en el primer borrador de esta migración -- mismo tipo de
-- error que el esmalte, atrapado antes de aplicar:
--   'PERFIL MONTANTE 35MM U OMEGA (ESTRUCTURA/VELAS)' -> ya no existe, 0049 lo renombró a
--   'PERFIL MONTANTE 35MM U OMEGA REFORZADA' (el nombre que Seba había escrito originalmente).
--   'LISTONES VERTICALES CADA 0,40 M' -> ya no existe, 0049 lo renombró a
--   'LISTONES 2” X 2” VERTICALES CADA 0,40 M' (también el nombre que Seba había escrito).
-- En los dos casos el nombre correcto era el que Seba tecleó de memoria, no el que salía de mirar
-- solo 0022 -- la lección: para cualquier nombre de este catálogo hay que revisar 0049/0057 además
-- del seed original, no alcanza con el seed.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor), después de 0065. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

-- =====================================================================
-- Sección 1 — Reasignación de apu_composicion_items (todos los pares, los 42)
-- =====================================================================
--
-- Defensivo por construcción: si algún nombre no matchea (ya renombrado, ya borrado, o sin uso en
-- ninguna composición), esa fila del driving table simplemente no reasigna nada -- no hay riesgo
-- de tocar de más.

update apu_composicion_items aci
set insumo_id = pares.sobrevive_id
from (
  select isup.id as sobrevive_id, iabs.id as absorbido_id
  from (values
    -- Grupo A
    ('AISLACION HIDROFUGA TIPO TYVEK', 'MEMBRANA BARRERA DE AGUA Y VIENTO (TYVEK)'),
    ('SELLADOR POLIURETANICO', 'ADHESIVO / SELLADOR ELASTOMÉRICO POLIURETÁNICO (CARTUCHO)'),
    ('ELECTRODO REVESTIDO / ALAMBRE MIG', 'ELECTRODO REVESTIDO E6011/E7018 O ALAMBRE MIG (CHAPA DE MENOR ESPESOR)'),
    ('ESMALTE SINTÉTICO', 'ESMALTE SINTÉTICO SATINADO/BRILLANTE (2 MANOS)'),
    ('ALFAJIAS 2”X2” CEPILLADAS', 'LISTONES 2” X 2” VERTICALES CADA 0,40 M'),
    ('HOJA DE LIJA', 'HOJAS DE LIJA FINA N° 180/220'),
    ('HOJA DE LIJA', 'HOJAS DE LIJA FINA N° 180/240'),
    ('LIJA PARA MADERA N° 120/180', 'HOJAS DE LIJA P/MADERA N° 150/220/280'),
    ('CLAVOS CABEZA PERDIDA 12 X 50MM', 'CLAVOS SIN CABEZA / PUNTA PARÍS 2”'),
    ('TACOS DE EXPANSIÓN 8MM C/TORNILLO', 'TARUGO PLÁSTICO'),
    ('TACOS DE EXPANSIÓN 8MM C/TORNILLO', 'PITONES L / TACOS DE EXPANSIÓN'),
    ('ARENA', 'ARENA DE RIO TAMIZADA'),
    ('PASTINA', 'PASTINA PARA EXTERIORES (IMPERMEABLE)'),
    ('FILM DE POLIETILENO 200 MICRONES', 'POLIETILENO / BOBINA DE PAPEL PROTECTOR'),
    ('FILM DE POLIETILENO 200 MICRONES', 'POLIETILENO DE PROTECCIÓN PARA ABERTURAS'),
    ('MASILLA TIPO ENDUIDO', 'ENDUIDO PLÁSTICO INTERIOR (PLANCHADO TOTAL)'),
    ('CLIPS DE RETENCIÓN CONTRA VIENTO', 'GRAMPAS DE FIJACION P/METAL DESPLEGADO'),
    ('CLIPS DE RETENCIÓN CONTRA VIENTO', 'GRAPAS ANCLAJE'),
    ('LISTOS ZOCALO DE MADERA 3” X 1/2”', 'MOLDURA / ZÓCALO DE MADERA PERIMETRAL'),
    ('TABLAS', 'TABLAS DE MADERA 6”X1”'),
    ('CANTO RODADO / PIEDRA PARTIDA', 'CANTO RODADO DE CONTENCIÓN PERIMETRAL (FRANJA TÉCNICA)'),
    ('BANDA ACUSTICA POLIETILENO 100MM', 'BANDA ACUSTICA BAJO SOLERA 100MM'),
    ('TRAPO DE ESTOPA', 'TRAPO MICROFIBRA P/LIMPIEZA DE POLVO'),
    ('CHAPA SINUSOIDAL – COLOR C25', 'CHAPA SINUSOIDAL O TRAPEZOIDAL'),
    -- Grupo B
    ('ALAMBRE NEGRO', 'ALAMBRE NEGRO COCIDO N° 16'),
    ('AISLACION TERMICA (LANA DE VIDRIO 100MM)', 'AISLACION ACUSTICA (LANA DE VIDRIO 100MM)'),
    ('CLAVOS', 'CLAVOS DE 2” Y 2.1/2”'),
    ('TORNILLOS T1 CABEZA TANQUE PUNTA MECHA 8X9.5MM', 'TORNILLOS T1 MECHA 8X9/16'),
    -- Grupo C
    ('PRESERVADOR/FUNGICIDA BASE SOLVENTE', 'PRESERVADOR / FUNGICIDA-INSECTICIDA BASE SOLVENTE'),
    ('CLAVOS SIN CABEZA O TORNILLOS', 'CLAVOS SIN CABEZA / BRADS O TORNILLOS PARA MADERA'),
    ('CARTELAS / PLATINAS DE CONEXIÓN', 'CHAPAS DE NUDO / CARTELAS'),
    ('CARTELAS / PLATINAS DE CONEXIÓN', 'PLACAS BASE Y PLATINAS DE REFUERZO'),
    ('CERAMICO MEDIANO', 'CERAMICO MEDIANO O PORCELANATO MEDIANO'),
    ('PERFIL MONTANTE 35MM U OMEGA REFORZADA', 'PERFILERÍA OMEGA O ALFAJIAS MADERA'),
    ('ALFAJÍAS / LISTONES DE PINO 1" X 2" (CRUZADOS)', 'LISTONADO / ALFAJÍAS PINO 2” X 1”'),
    ('TORNILLERÍA / BULONES DE MONTAJE', 'BULONES DE ANCLAJE (CALIDAD 8.8 O GALVANIZADOS) + TUERCAS + ARANDELAS'),
    ('TORNILLERÍA / BULONES DE MONTAJE', 'TORNILLOS ESTRUCTURALES AUTOPERFORANTES O BULONES COMUNES'),
    ('TORNILLO PARA FIJACIÓN', 'TORNILLOS Y TETONES PARA FIJACIONES'),
    ('PERFIL PRINCIPAL T (3.60M)', 'PERFIL SECUNDARIO T (1.20M)'),
    ('PERFIL PRINCIPAL T (3.60M)', 'PERFIL TRANSVERSAL T (0.60M)'),
    ('IMPREGNANTE / BARNIZ BASE SOLVENTE (3 MANOS)', 'IMPREGNANTE (LASUR) O BARNIZ MARINO CON FILTRO UV (3 MANOS)'),
    -- Grupo D
    ('TORNILLOS T2 PUNTA MECHA CON ALAS 8X1.1/4”', 'TORNILLOS T2 PUNTA MECHA CON ALAS 8X1.1/4” O CLAVOS ESPIRALADOS 2”')
  ) as m(sobrevive, absorbido)
  join insumos isup on isup.nombre = m.sobrevive and isup.creador_usuario_id is null
  join insumos iabs on iabs.nombre = m.absorbido and iabs.creador_usuario_id is null
) as pares
where aci.insumo_id = pares.absorbido_id;

-- =====================================================================
-- Sección 2 — Reasignación de precios existentes (solo los pares donde el absorbido tenía precio)
-- =====================================================================
--
-- De los 42 pares, solo estos 5 tenían al menos una fila en `precios` del lado absorbido -- el
-- resto (Grupo A salvo chapa, todo Grupo C) no tiene nada que mover acá. Mismo mecanismo que la
-- Sección 1: reasigna insumo_id, sin tocar corralon_id/valor -- la conversión de valor de chapa va
-- en la Sección 3, aparte, porque no es una reasignación simple.

update precios p
set insumo_id = pares.sobrevive_id
from (
  select isup.id as sobrevive_id, iabs.id as absorbido_id
  from (values
    ('ALAMBRE NEGRO', 'ALAMBRE NEGRO COCIDO N° 16'),
    ('AISLACION TERMICA (LANA DE VIDRIO 100MM)', 'AISLACION ACUSTICA (LANA DE VIDRIO 100MM)'),
    ('CLAVOS', 'CLAVOS DE 2” Y 2.1/2”'),
    ('TORNILLOS T1 CABEZA TANQUE PUNTA MECHA 8X9.5MM', 'TORNILLOS T1 MECHA 8X9/16'),
    ('CHAPA SINUSOIDAL – COLOR C25', 'CHAPA SINUSOIDAL O TRAPEZOIDAL')
  ) as m(sobrevive, absorbido)
  join insumos isup on isup.nombre = m.sobrevive and isup.creador_usuario_id is null
  join insumos iabs on iabs.nombre = m.absorbido and iabs.creador_usuario_id is null
) as pares
where p.insumo_id = pares.absorbido_id;

-- =====================================================================
-- Sección 3 — Conversión de precio: chapa (ML -> M2)
-- =====================================================================
--
-- $22.216,02/ML (Felemax, ya reasignado a CHAPA SINUSOIDAL – COLOR C25 en la Sección 2) ÷ 1,1m de
-- ancho = $20.196,38/M2. Mismo ancho que ya se usó para la cotización de HIZA de esta chapa
-- ("3m x 1,1m = 3,3m2").

update precios p
set valor = 20196.38
from insumos i
where p.insumo_id = i.id
  and i.nombre = 'CHAPA SINUSOIDAL – COLOR C25'
  and i.creador_usuario_id is null
  and p.corralon_id = (select id from corralones where nombre = 'Felemax');

-- =====================================================================
-- Sección 4 — Precio nuevo: banda acústica bajo solera (convertido, sin fila previa que mover)
-- =====================================================================
--
-- El precio de HIZA para BANDA ACUSTICA BAJO SOLERA 100MM (0065) había quedado sin cargar por la
-- ambigüedad de unidad -- no hay ninguna fila en `precios` para reasignar, es una carga nueva.
-- $3.952,01 / rollo de 3m = $1.317,34/ML, bajo el insumo sobreviviente (que ya tiene precio de
-- Felemax en ML desde 0058) -- queda como segundo proveedor, no reemplaza al primero.

insert into precios (insumo_id, corralon_id, valor, fecha_actualizacion)
select i.id, c.id, 1317.34, '2026-09-05'
from insumos i, corralones c
where i.nombre = 'BANDA ACUSTICA POLIETILENO 100MM' and i.creador_usuario_id is null
  and c.nombre = 'HIZA';

-- =====================================================================
-- Sección 5 — Correcciones puntuales de rendimiento (conversión de unidad real)
-- =====================================================================
--
-- Los insumo_id de estas filas ya fueron reasignados al sobreviviente en la Sección 1 -- acá solo
-- se corrige el número, ahora que la unidad de referencia cambió. Cada UPDATE apunta a la partida
-- exacta para no tocar ninguna otra fila que use el mismo insumo.

-- 14.3 — CHAPA: 1,1 ML x 1,1m de ancho = 1,21 M2.
update apu_composicion_items aci
set rendimiento = 1.21
from apu_composiciones ac, subitems s, insumos i
where aci.apu_composicion_id = ac.id
  and ac.subitem_id = s.id
  and aci.insumo_id = i.id
  and s.codigo = '14.3' and s.creador_usuario_id is null and ac.creador_usuario_id is null
  and i.nombre = 'CHAPA SINUSOIDAL – COLOR C25' and i.creador_usuario_id is null;

-- 14.4 — TABLAS: 1,05 M2 ÷ 0,1524m de ancho (tabla 6”) = 6,89 ML.
update apu_composicion_items aci
set rendimiento = 6.89
from apu_composiciones ac, subitems s, insumos i
where aci.apu_composicion_id = ac.id
  and ac.subitem_id = s.id
  and aci.insumo_id = i.id
  and s.codigo = '14.4' and s.creador_usuario_id is null and ac.creador_usuario_id is null
  and i.nombre = 'TABLAS' and i.creador_usuario_id is null;

-- 15.4 — CANTO RODADO: 8 KG ÷ 1.600 kg/m³ (densidad de grava rodada, confirmada por Seba) = 0,005 M3.
update apu_composicion_items aci
set rendimiento = 0.005
from apu_composiciones ac, subitems s, insumos i
where aci.apu_composicion_id = ac.id
  and ac.subitem_id = s.id
  and aci.insumo_id = i.id
  and s.codigo = '15.4' and s.creador_usuario_id is null and ac.creador_usuario_id is null
  and i.nombre = 'CANTO RODADO / PIEDRA PARTIDA' and i.creador_usuario_id is null;

-- 6.4 — BANDA ACUSTICA: el 30 original era un error de carga (total de la partida, no rendimiento
-- por m²) -- corregido a 0,6 ML según el cálculo real de Seba (28 ml de perímetro / 50 m² de
-- entrepiso). La 6.3 NO se toca: su rendimiento (1) ya es correcto, solo cambia de interpretación
-- (1 UND == 1 ML), sin que el número deba cambiar.
update apu_composicion_items aci
set rendimiento = 0.6
from apu_composiciones ac, subitems s, insumos i
where aci.apu_composicion_id = ac.id
  and ac.subitem_id = s.id
  and aci.insumo_id = i.id
  and s.codigo = '6.4' and s.creador_usuario_id is null and ac.creador_usuario_id is null
  and i.nombre = 'BANDA ACUSTICA POLIETILENO 100MM' and i.creador_usuario_id is null;

-- 17.4 — TRAPO: 0,03 UND x 0,05 kg/paño (paño estándar 40x40) = 0,0015 KG.
update apu_composicion_items aci
set rendimiento = 0.0015
from apu_composiciones ac, subitems s, insumos i
where aci.apu_composicion_id = ac.id
  and ac.subitem_id = s.id
  and aci.insumo_id = i.id
  and s.codigo = '17.4' and s.creador_usuario_id is null and ac.creador_usuario_id is null
  and i.nombre = 'TRAPO DE ESTOPA' and i.creador_usuario_id is null;

-- =====================================================================
-- Sección 6 — Borrado de los 42 insumos absorbidos, ya sin ninguna referencia
-- =====================================================================
--
-- Mismo criterio defensivo que 0064: cada nombre solo se borra si, en el momento de correr esto,
-- no queda ninguna fila que lo referencie en apu_composicion_items, precios ni
-- obra_insumo_precios. Si alguna reasignación de arriba no matcheó por algún motivo, el DELETE
-- correspondiente no hace nada -- no hay riesgo de borrar un insumo todavía en uso.

delete from insumos
where creador_usuario_id is null
  and nombre in (
    'MEMBRANA BARRERA DE AGUA Y VIENTO (TYVEK)',
    'ADHESIVO / SELLADOR ELASTOMÉRICO POLIURETÁNICO (CARTUCHO)',
    'ELECTRODO REVESTIDO E6011/E7018 O ALAMBRE MIG (CHAPA DE MENOR ESPESOR)',
    'ESMALTE SINTÉTICO SATINADO/BRILLANTE (2 MANOS)',
    'LISTONES 2” X 2” VERTICALES CADA 0,40 M',
    'HOJAS DE LIJA FINA N° 180/220',
    'HOJAS DE LIJA FINA N° 180/240',
    'HOJAS DE LIJA P/MADERA N° 150/220/280',
    'CLAVOS SIN CABEZA / PUNTA PARÍS 2”',
    'TARUGO PLÁSTICO',
    'PITONES L / TACOS DE EXPANSIÓN',
    'ARENA DE RIO TAMIZADA',
    'PASTINA PARA EXTERIORES (IMPERMEABLE)',
    'POLIETILENO / BOBINA DE PAPEL PROTECTOR',
    'POLIETILENO DE PROTECCIÓN PARA ABERTURAS',
    'ENDUIDO PLÁSTICO INTERIOR (PLANCHADO TOTAL)',
    'GRAMPAS DE FIJACION P/METAL DESPLEGADO',
    'GRAPAS ANCLAJE',
    'MOLDURA / ZÓCALO DE MADERA PERIMETRAL',
    'TABLAS DE MADERA 6”X1”',
    'CANTO RODADO DE CONTENCIÓN PERIMETRAL (FRANJA TÉCNICA)',
    'BANDA ACUSTICA BAJO SOLERA 100MM',
    'TRAPO MICROFIBRA P/LIMPIEZA DE POLVO',
    'CHAPA SINUSOIDAL O TRAPEZOIDAL',
    'ALAMBRE NEGRO COCIDO N° 16',
    'AISLACION ACUSTICA (LANA DE VIDRIO 100MM)',
    'CLAVOS DE 2” Y 2.1/2”',
    'TORNILLOS T1 MECHA 8X9/16',
    'PRESERVADOR / FUNGICIDA-INSECTICIDA BASE SOLVENTE',
    'CLAVOS SIN CABEZA / BRADS O TORNILLOS PARA MADERA',
    'CHAPAS DE NUDO / CARTELAS',
    'PLACAS BASE Y PLATINAS DE REFUERZO',
    'CERAMICO MEDIANO O PORCELANATO MEDIANO',
    'PERFILERÍA OMEGA O ALFAJIAS MADERA',
    'LISTONADO / ALFAJÍAS PINO 2” X 1”',
    'BULONES DE ANCLAJE (CALIDAD 8.8 O GALVANIZADOS) + TUERCAS + ARANDELAS',
    'TORNILLOS ESTRUCTURALES AUTOPERFORANTES O BULONES COMUNES',
    'TORNILLOS Y TETONES PARA FIJACIONES',
    'PERFIL SECUNDARIO T (1.20M)',
    'PERFIL TRANSVERSAL T (0.60M)',
    'IMPREGNANTE (LASUR) O BARNIZ MARINO CON FILTRO UV (3 MANOS)',
    'TORNILLOS T2 PUNTA MECHA CON ALAS 8X1.1/4” O CLAVOS ESPIRALADOS 2”'
  )
  and not exists (select 1 from apu_composicion_items where insumo_id = insumos.id)
  and not exists (select 1 from precios where insumo_id = insumos.id)
  and not exists (select 1 from obra_insumo_precios where insumo_id = insumos.id);

-- =====================================================================
-- Verificación
-- =====================================================================

-- 1) Cuántos de los 42 nombres absorbidos siguen existiendo -- esperado 0. Si aparece alguno, el
--    DELETE no corrió para ese (todavía tiene una referencia en algún lado) -- no reintentar a
--    ciegas, revisar cuál de las 3 tablas la tiene.
select nombre from insumos
where creador_usuario_id is null
  and nombre in (
    'MEMBRANA BARRERA DE AGUA Y VIENTO (TYVEK)', 'ADHESIVO / SELLADOR ELASTOMÉRICO POLIURETÁNICO (CARTUCHO)',
    'ELECTRODO REVESTIDO E6011/E7018 O ALAMBRE MIG (CHAPA DE MENOR ESPESOR)', 'ESMALTE SINTÉTICO SATINADO/BRILLANTE (2 MANOS)',
    'LISTONES 2” X 2” VERTICALES CADA 0,40 M', 'HOJAS DE LIJA FINA N° 180/220', 'HOJAS DE LIJA FINA N° 180/240',
    'HOJAS DE LIJA P/MADERA N° 150/220/280', 'CLAVOS SIN CABEZA / PUNTA PARÍS 2”', 'TARUGO PLÁSTICO',
    'PITONES L / TACOS DE EXPANSIÓN', 'ARENA DE RIO TAMIZADA', 'PASTINA PARA EXTERIORES (IMPERMEABLE)',
    'POLIETILENO / BOBINA DE PAPEL PROTECTOR', 'POLIETILENO DE PROTECCIÓN PARA ABERTURAS',
    'ENDUIDO PLÁSTICO INTERIOR (PLANCHADO TOTAL)', 'GRAMPAS DE FIJACION P/METAL DESPLEGADO', 'GRAPAS ANCLAJE',
    'MOLDURA / ZÓCALO DE MADERA PERIMETRAL', 'TABLAS DE MADERA 6”X1”', 'CANTO RODADO DE CONTENCIÓN PERIMETRAL (FRANJA TÉCNICA)',
    'BANDA ACUSTICA BAJO SOLERA 100MM', 'TRAPO MICROFIBRA P/LIMPIEZA DE POLVO', 'CHAPA SINUSOIDAL O TRAPEZOIDAL',
    'ALAMBRE NEGRO COCIDO N° 16', 'AISLACION ACUSTICA (LANA DE VIDRIO 100MM)', 'CLAVOS DE 2” Y 2.1/2”',
    'TORNILLOS T1 MECHA 8X9/16', 'PRESERVADOR / FUNGICIDA-INSECTICIDA BASE SOLVENTE',
    'CLAVOS SIN CABEZA / BRADS O TORNILLOS PARA MADERA', 'CHAPAS DE NUDO / CARTELAS', 'PLACAS BASE Y PLATINAS DE REFUERZO',
    'CERAMICO MEDIANO O PORCELANATO MEDIANO', 'PERFILERÍA OMEGA O ALFAJIAS MADERA', 'LISTONADO / ALFAJÍAS PINO 2” X 1”',
    'BULONES DE ANCLAJE (CALIDAD 8.8 O GALVANIZADOS) + TUERCAS + ARANDELAS', 'TORNILLOS ESTRUCTURALES AUTOPERFORANTES O BULONES COMUNES',
    'TORNILLOS Y TETONES PARA FIJACIONES', 'PERFIL SECUNDARIO T (1.20M)', 'PERFIL TRANSVERSAL T (0.60M)',
    'IMPREGNANTE (LASUR) O BARNIZ MARINO CON FILTRO UV (3 MANOS)', 'TORNILLOS T2 PUNTA MECHA CON ALAS 8X1.1/4” O CLAVOS ESPIRALADOS 2”'
  );

-- 2) Conteo total de insumos -- 210 (antes de esta migración) menos 42 bajas = 168.
select count(*) as total_insumos from insumos;

-- 3) apu_composicion_items no perdió ni ganó filas -- tiene que dar el mismo total de antes de
--    correr esto (770 según el último conteo de Seba). Si baja, se perdió una receta al reasignar.
select count(*) as total_apu_composicion_items from apu_composicion_items;

-- 4) Ningún apu_composicion_items queda huérfano.
select count(*) as huerfanos
from apu_composicion_items ci
left join insumos i on i.id = ci.insumo_id
where i.id is null;

-- 5) Ninguna fila de precios quedó huérfana tampoco (mismo chequeo, para precios).
select count(*) as precios_huerfanos
from precios p
left join insumos i on i.id = p.insumo_id
where i.id is null;

-- 6) Ningún insumo quedó con dos precios del mismo corralón (si aparece alguna fila acá, hay que
--    promediarla a mano -- no se encontró ningún caso así al verificar antes de escribir esto).
select insumo_id, corralon_id, count(*) as filas
from precios
group by insumo_id, corralon_id
having count(*) > 1;

-- 7) Los 5 rendimientos corregidos, para que Seba los revise con el nombre del insumo ya
--    unificado a la vista.
select s.codigo, i.nombre, aci.rendimiento
from apu_composicion_items aci
join apu_composiciones ac on ac.id = aci.apu_composicion_id
join subitems s on s.id = ac.subitem_id
join insumos i on i.id = aci.insumo_id
where s.codigo in ('14.3', '14.4', '15.4', '6.3', '6.4', '17.4') and ac.creador_usuario_id is null
order by s.codigo;

-- 8) Los precios de banda acústica y chapa, para confirmar que quedaron los dos proveedores y el
--    valor convertido.
select i.nombre as insumo, c.nombre as corralon, p.valor
from precios p
join insumos i on i.id = p.insumo_id
join corralones c on c.id = p.corralon_id
where i.nombre in ('BANDA ACUSTICA POLIETILENO 100MM', 'CHAPA SINUSOIDAL – COLOR C25')
order by i.nombre, c.nombre;
