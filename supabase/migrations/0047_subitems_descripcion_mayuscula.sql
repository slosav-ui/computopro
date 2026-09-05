-- PLANILLA_BASE_2_0_v3_CORREGIDA.ods tenía AutoCalculate desactivado (corregido, ver commit
-- e4d4e5a). Con el cálculo reactivado, 72 de los 116 subitems oficiales (rubros 2 a 17) muestran
-- su descripción en MAYÚSCULA — casi seguro un UPPER() sobre la celda fuente que 0016_subitems.sql
-- sembró con el valor cacheado viejo (minúscula/mixta), de antes de que se apagara el
-- AutoCalculate. Diff completo (72 filas) generado programáticamente contra 0016_subitems.sql y el
-- content.xml del .ods, no a mano, y confirmado por el usuario antes de escribir esto.
--
-- 5 valores traían un espacio final en la celda del .ods (codigos 4.2, 7.1, 12.4, 13.6, 14.1) —
-- recortado acá, es ruido de la hoja, no contenido real.
--
-- Rubro 1 no cambia (la fórmula no lo tocaba, seguía sin recalcular). Rubros 3, 4 (salvo 4.2), 18,
-- 19, 20 y las descripciones que ya estaban en mayúscula tampoco cambian — no hay UPDATE para esos
-- codigos, sus filas quedan como están.
--
-- UPDATE contra `codigo`, no contra el texto viejo completo (que podría no matchear exacto por un
-- espacio o tilde) — mismo criterio que el índice único de 0016 (`codigo` es la clave estable).
-- `creador_usuario_id is null` para tocar solo el catálogo oficial, nunca un subítem custom de un
-- usuario que por lo que sea coincida en código con uno oficial (no debería poder pasar por el
-- índice parcial de 0016, pero la guarda no cuesta nada).
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.
--
-- CORRECCIÓN 2026-09-06, antes de aplicar por primera vez: esta migración quedó escrita y sin
-- aplicar durante semanas. Mientras tanto, 0049_limpieza_catalogo_insumos.sql §7 corrigió un typo
-- ("aislacion hidraulica" -> "aislacion hidrofuga") en estos mismos 3 códigos (5.6, 6.6, 15.3) y
-- SÍ se aplicó — cubriendo a propósito tanto la variante minúscula/mixta de 0016 como la mayúscula
-- que traía esta migración, por si esta ya había corrido (no había forma de confirmarlo desde este
-- entorno). Como en los hechos corrió solo 0049, hoy esos 3 subitems ya tienen "hidrofuga" pero en
-- minúscula/mixta. Los 3 valores de abajo para 5.6/6.6/15.3 ya vienen con el typo corregido
-- ("AISLACION HIDROFUGA", no "AISLACION HIDRAULICA" como decía la versión original) para que
-- aplicar esta migración ahora complete la normalización a MAYÚSCULA de esos 3 sin deshacer el fix
-- de 0049.

update subitems s
set descripcion = v.descripcion
from (values
  ('2.1', 'EXCACACION DE ZANJAS ( PROFUNDIDAD MAXIMA 1,5M)'),
  ('2.2', 'EXCACACION DE POZOS (PARA POZOS NEGROS, POZOS ROMANOS, ETC., Y PROFUNDIDADES NO MAYORES A 8M)'),
  ('2.3', 'EXCACACION DE POZOS (PARA BASES DE COLUMNAS, TANQUES ENTERRADOS, Y PROFUNDIDADES NO MAYORES A 4M)'),
  ('4.2', 'LOSAS'),
  ('5.1', 'CERRAMIENTOS EXTERIORES PB (PERFIL CSH PGC 100X40X0,9, AISLACION TERMICA 100MM, PLACA OSB 11,1 AMBAS CARAS, ANCLAJE ESCUADRA HTT14, BROCA MECANICA 10)'),
  ('5.2', 'CERRAMIENTOS EXTERIORES 1° Y 2° PISO (PERFIL CSH PGC 100X40X0,9, AISLACION TERMICA 100MM, PLACA OSB 11,1 AMBAS CARAS, ANCLAJE ESCUADRA HTT14, BROCA MECANICA 10)'),
  ('5.3', 'CERRAMIENTOS INTERIORES PB - 1° Y 2° PISO (PERFIL CSH PGC 100X40X0,9, AISLACION TERMICA 100MM, PLACA OSB 11,1 AMBAS CARAS, ANCLAJE ESCUADRA HTT14, BROCA MECANICA 10)'),
  ('5.4', 'ENTREPISOS (PLACA FENOLICA DE 18MM, PERFIL CSH PGC 150X40X0,9, AISLACION ACUSTICA 100MM)'),
  ('5.5', 'ESCALERAS (PERFIL CSH PGC 100X40X0,9, PLACA OSB DE 11.1MM)'),
  ('5.6', 'CUBIERTAS INCLINADAS (PERFIL CSH PGC 100X40X0,9, PLACA OSB DE 11.1MM, AISLACION HIDROFUGA, REALCES, ALFAJIAS 2”X2”, AISLACION TERMICA, CHAPA SINUSOIDAL)'),
  ('6.1', 'CERRAMIENTOS EXTERIORES PB (ECUADRAS DE MADERA 4”X2”, AISLACION TERMICA 100MM, PLACA OSB 11,1 AMBAS CARAS, ANCLAJES METALICOS, BROCA MECANICA 10)'),
  ('6.2', 'CERRAMIENTOS EXTERIORES 1° Y 2° PISO (ECUADRAS DE MADERA 4”X2”, AISLACION TERMICA 100MM, PLACA OSB 11,1 AMBAS CARAS, ANCLAJES METALICOS, BROCA MECANICA 10)'),
  ('6.3', 'CERRAMIENTOS INTERIORES PB - 1° Y 2° PISO (ECUADRAS DE MADERA 4”X2”, AISLACION TERMICA 100MM, PLACA OSB 11,1 AMBAS CARAS, ANCLAJES METALICOS, BROCA MECANICA 10)'),
  ('6.4', 'ENTREPISOS (PLACA FENOLICA DE 18MM, CABIOS DE MADERA 6”X2”, AISLACION TERMICA 100MM, PLACA OSB 11,1 AMBAS CARAS, ANCLAJES METALICOS, BROCA MECANICA 10), AISLACION ACUSTICA 100MM)'),
  ('6.5', 'ESCALERAS (ESCUADRAS DE MADERA 6”X2”, PLACA FENOLICAS DE 18MM)'),
  ('6.6', 'CUBIERTAS INCLINADAS (CABIOS DE 6”X2”, PLACA OSB DE 11.1MM O MACHIMBRE 4”X1/2”, AISLACION HIDROFUGA, REALCES, ALFAJIAS 2”X2”, AISLACION TERMICA, CHAPA SINUSOIDAL)'),
  ('7.1', 'MONTAJE DE COLUMNAS Y VIGAS EN PERFIL TUBULAR ESTRUCTURAL CUADRADO/RECTANGULAR CONFORMADO EN FRIO.'),
  ('7.2', 'MONTAJE DE COLUMNAS / VIGAS / CORREAS EN PERFIL TUBULAR RECTANGULAR O PERFIL C CONFORMADO EN FRÍO'),
  ('7.3', 'MONTAJE DE CERCHAS / TIJERALES LIVIANOS EN CAÑO ESTRUCTURAL O PERFIL C CONFORMADO EN FRÍO'),
  ('8.1', 'LADRILLOS COMUNES E=15CM'),
  ('8.2', 'LADRILLOS COMUNES A LA VISTA E=15CM'),
  ('8.3', 'LADRILLOS COMUNES E=30CM'),
  ('8.4', 'LADRILLOS COMUNES A LA VISTA E=30CM'),
  ('8.9', 'MUROS BLOQUES DE CEMENTO 19X19X39'),
  ('8.10', 'LADRILLOS MACIZOS HCCA (RETAK) E=10CM'),
  ('8.11', 'LADRILLOS MACIZOS HCCA (RETAK) E=15CM'),
  ('8.12', 'LADRILLOS MACIZOS HCCA (RETAK) E=20CM'),
  ('9.1', 'AISLACION HIDROFUGA HORIZONTAL E=2CM'),
  ('9.2', 'AZOTADO HIDROFUGO VERTICAL E=1CM'),
  ('9.3', 'CARPETA HIDROFUGA E=2CM'),
  ('10.4', 'REVOQUE GRUESO Y FINO A LA CAL EXTERIOR COMPLETO (CON HIDROFUGO)'),
  ('10.5', 'ENLUCIDO A LA CAL (APLICADO SOBRE REVOQUE GRUESO)'),
  ('10.6', 'ENLUCIDO DE YESO (SOBRE REVOQUE GRUESO)'),
  ('11.1', 'CONTRAPISO DE HORMIGON DE CASCOTES E=10CM'),
  ('11.2', 'CONTRAPISO DE HORMIGON ARMADO (CON MALLA ELECTROSOLDADA Y EPS 2CM) ESP TOTAL = 8CM'),
  ('11.3', 'CONTRAPISO DE MATERIAL AISLANTE (ARCILLA EXPANDIDA) E=6CM'),
  ('11.4', 'CONTRAPISO DE MATERIAL AISLANTE (CON PERLAS DE EPS) E=6CM'),
  ('11.5', 'CONTRAPISO EXTERIOR DE HORMIGON ARMADO (CON MALLA ELECTROSOLDADA) ESP TOTAL = 8CM'),
  ('11.6', 'CARPETA CEMENTICIA E=2.5CM'),
  ('12.1', 'PISO PORCELANATO (PIEZAS PEQUEÑAS Y MEDIANAS < 60/60)'),
  ('12.2', 'PISO PORCELANATO (PIEZAS GRANDES > 60/60)'),
  ('12.4', 'PISO FLOTANTE MDF/HDF'),
  ('12.8', 'PISO PIEDRA LAJA (SOBRE CONTRAPISO O CARPETA)'),
  ('12.9', 'BLOQUE DE HORMIGON CALADO 30/30 E=8CM (PARA CESPED)'),
  ('12.10', 'ZOCALO DE MADERA (INCLUYE PINTURA)'),
  ('12.11', 'ZOCALO CERAMICO O PORCELANATO H=8CM'),
  ('13.1', 'REVESTIMIENTO PORCELANATO (PIEZAS PEQUEÑAS Y MEDIANAS < 60/60)'),
  ('13.2', 'REVESTIMIENTO PORCELANATO (PIEZAS GRANDES > 60/60)'),
  ('13.5', 'REVESTIMIENTO MOLON DE PIEDRA E= DE 10 A 15CM'),
  ('13.6', 'REVESTIMIENTO BASE COAT (SOBRE BLOQUE MACIZO HCCA, MALLA DE FIBRA GRAM: 160G/M2 Y BASE-COAT)'),
  ('13.7', 'REVESTIMIENTO PLASTICO (TIPO TARQUINI, REVEAR O SIMILAR)'),
  ('14.1', 'TIPO SISTEMA EIFS (SOBRE REVOQUE GRUESO EXISTENTE U OSB COMPUESTA POR AISLACION HIDROFUGA TIPO TYBEK, REALCES, PLACA DE EPS ALTA DENSIDAD 50MM, MALLA DE FIBRA GRAM: 160G/M2 Y BASE-COAT)'),
  ('14.2', 'REVESTIMIENTO PLACA SIDING CEMENTICIO O SUPERBOARD (BARRERA HIDROFUGA Y VIENTO TIPO TYBEK, OMEGAS REFORZADAS O ALFAJIAS 1”X1.12”, PLACA SIDING O SUPERBOARD'),
  ('14.3', 'REVESTIMIENTO CHAPA PAREDES EXTERIORES FIJADA SOBRE ESTRUCTURA EXISTENTE (AISLACION HIDROFUGA TIPO TYBEK, REALCES, ALFAJIAS DE MADERA CEPILLADA 2" X 2", EPS O LANA DE VIDRIOS 50MM Y CHAPA SINUSOIDAL O TRAPEZOIDAL)'),
  ('14.4', 'REVESTIMIENTO MADERA PAREDES EXTERIORES FIJADA SOBRE ESTRUCTURA EXISTENTE (AISLACION HIDROFUGA TIPO TYBEK, REALCES, ALFAJIAS DE MADERA CEPILLADA 2" X 2", EPS O LANA DE VIDRIOS 50MM Y TABLAS DE MADERA 6”X1”)'),
  ('14.5', 'REVESTIMIENTO CARA INTERIOR CON PLACA DE YESO DE ROCA DE 12,5MM ENCINTADA Y MASILLADA CON TRES MANOS (SOBRE PLACA OSB O ESTRUCTURA EXISTENTE, NO INCLUYE LIJADO)'),
  ('14.6', 'REVESTIMIENTO INTERIOR CON MACHIMBRE DE PINO DE ½" × 4" (COLOCADO HORIZONTALMENTE SOBRE BASTIDOR/LISTONES DE MADERA, SEPARADOS CADA 0,40 M, CON FIJACIÓN MECÁNICA Y TERMINACIÓN BARNIZADA)'),
  ('15.1', 'CUBIERTAS PLANAS (NO ACCESIBLES)'),
  ('15.2', 'CUBIERTAS PLANAS (ACCESIBLES)'),
  ('15.3', 'CUBIERTAS INCLINADAS DE MADERA(CABIOS DE 6”X2”, PLACA OSB DE 11.1MM O MACHIMBRE 4”X1/2”, AISLACION HIDROFUGA, REALCES, ALFAJIAS 2”X2”, AISLACION TERMICA, CHAPA SINUSOIDAL)'),
  ('15.4', 'CUBIERTAS VERDES (EXTENSIVA, SOBRE ESTRUCTURA EXISTRENTE, E=10CM)'),
  ('15.5', 'REVESTIMIENTO CARA INTERIOR CON PLACA DE YESO DE ROCA DE 12,5MM ENCINTADA Y MASILLADA CON TRES MANOS (SOBRE PLACA OSB O ESTRUCTURA EXISTENTE, NO INCLUYE LIJADO)'),
  ('16.1', 'APLICADO DE YESO (SOBRE LOSA DE HORMIGÓN ARMADO)'),
  ('16.2', 'SUSPENDIDO TRADICIONAL DE YESO (CAL/YESO S/ METAL DESPLEGADO)'),
  ('16.3', 'JUNTA TOMADA (PLACA YESO DE ROCA 12.5MM C/ ESTRUCTURA 0.4M (DURLOCK/KNAUF))'),
  ('16.4', 'DESMONTABLE TÉCNICO (PLACAS 60CM X 60CM O 60CM X 120CM)'),
  ('16.5', 'SUSPENDIDO DE MADERA / MACHIMBRADO (VISTA / INTERIOR, INCLUYE E MANSO DE PINTURA AL BARNIZ)'),
  ('17.1', 'LÁTEX INTERIOR (PLANCHADO GENERAL CON ENDUIDO Y 3 MANOS)'),
  ('17.2', 'LÁTEX EXTERIOR / IMPERMEABILIZANTE (FRENTE Y MUROS EXTERIOR)'),
  ('17.3', 'SINTÉTICO / ESMALTE (SOBRE HERRERÍA / ESTRUCTURAS METÁLICAS)'),
  ('17.4', 'BARNIZ / IMPREGNANTE (SOBRE CARPINTERÍAS DE MADERA)'),
  ('17.5', 'PINTURA EPOXI / POLIURETÁNICA (PISOS INDUSTRIALES / GARAJES)')
) as v(codigo, descripcion)
where s.codigo = v.codigo
  and s.creador_usuario_id is null;

-- =====================================================================
-- Verificación — correr después de aplicar
-- =====================================================================

-- 1) De los 72 códigos que esta migración actualiza, cuántos NO quedaron en mayúscula —
--    esperado 0. (No cuenta contra el total de subitems: rubros 1/3/4(salvo 4.2)/18/19/20 y los
--    que ya estaban en mayúscula antes no los toca esta migración, a propósito.)
select count(*) as pendientes_sin_actualizar
from subitems s
join (values
  ('2.1'),('2.2'),('2.3'),('4.2'),('5.1'),('5.2'),('5.3'),('5.4'),('5.5'),('5.6'),
  ('6.1'),('6.2'),('6.3'),('6.4'),('6.5'),('6.6'),('7.1'),('7.2'),('7.3'),
  ('8.1'),('8.2'),('8.3'),('8.4'),('8.9'),('8.10'),('8.11'),('8.12'),
  ('9.1'),('9.2'),('9.3'),('10.4'),('10.5'),('10.6'),
  ('11.1'),('11.2'),('11.3'),('11.4'),('11.5'),('11.6'),
  ('12.1'),('12.2'),('12.4'),('12.8'),('12.9'),('12.10'),('12.11'),
  ('13.1'),('13.2'),('13.5'),('13.6'),('13.7'),
  ('14.1'),('14.2'),('14.3'),('14.4'),('14.5'),('14.6'),
  ('15.1'),('15.2'),('15.3'),('15.4'),('15.5'),
  ('16.1'),('16.2'),('16.3'),('16.4'),('16.5'),
  ('17.1'),('17.2'),('17.3'),('17.4'),('17.5')
) as v(codigo) on v.codigo = s.codigo
where s.creador_usuario_id is null
  and s.descripcion <> upper(s.descripcion);

-- 2) Confirmación puntual del typo de 5.6/6.6/15.3: las 3 deben decir "HIDROFUGA", ninguna
--    "HIDRAULICA" (mismo chequeo que ya corrió 0049 §7, ahora en mayúscula).
select codigo, descripcion from subitems where codigo in ('5.6', '6.6', '15.3');
