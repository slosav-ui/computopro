-- Limpieza del catálogo de insumos APU — 25 duplicados semánticos unificados, 4 filas huérfanas
-- de "Hierro del 12mm" borradas, 7 nombres genéricos corregidos, unidades normalizadas contra una
-- lista cerrada de 8 valores válidos, y un typo en el texto de 3 subítems.
--
-- Origen: al exportar los 233 insumos sin precio del catálogo (234 de material menos el único con
-- precio real, CEMENTO PORTLAND X 25KG) para pedir cotización a corralones, aparecieron tres
-- problemas de datos: el mismo material cargado con nombres distintos, nombres genéricos que
-- ningún corralón puede cotizar sin más especificación, y unidades de medida sin normalizar.
-- Diagnóstico completo (reconstrucción exacta del catálogo parseando 0022/0023/0024, sin acceso a
-- la base desde este entorno) y todas las decisiones de negocio (qué se une con qué, qué nombre
-- final queda, qué NO se une) quedaron en la memoria de proyecto
-- `limpieza_catalogo_insumos_apu.md` — leer ahí el porqué de cada grupo antes de tocar esta
-- migración; acá solo está el SQL ya decidido.
--
-- Tres verificaciones se corrieron a mano contra la base real antes de escribir esto (no
-- reconstruidas, confirmadas por el usuario en Supabase): las 4 filas de "Hierro del 12mm" dan
-- 0/0/0 en apu_composicion_items/precios/obra_insumo_precios; las 4 filas con unidad literal
-- "unidad" (minúscula) son exactamente esas mismas 4 de Hierro del 12mm, así que desaparecen solas
-- al borrarlas, sin UPDATE aparte; CEMENTO PORTLAND X 25KG tenía `unidad_compra`/`factor_conversion`
-- en NULL — primer insumo del catálogo con esas dos columnas cargadas, caso testigo de para qué
-- existen (ver 0017_alter_insumos.sql).
--
-- CORRECCIÓN sobre una primera versión de esta migración: esa versión asumía que `unidad` de
-- CEMENTO PORTLAND X 25KG ya estaba corregida a mano fuera de esta migración — no era cierto, el
-- UPDATE nunca se aplicó. La base seguía con 'bolsa' (la unidad de *compra*, metida por error en
-- el campo de unidad de *uso*) y el `check` de la Sección 6 la rechazó, sin aplicar nada más (todo
-- el bloque corre como una transacción, confirmado: no quedó nada a medio aplicar). Esta versión
-- corrige `unidad` a 'KG' en la propia Sección 4 — 320 kg/m³ es dosificación de cemento de manual,
-- la unidad de uso real es KG, no 'bolsa'.
--
-- Todo resuelto por `nombre` (con `tipo = 'material'` como guarda extra), no por id pegado a mano:
-- no hay ids reales disponibles desde este entorno, y resolver por nombre es autodocumentado —
-- mismo criterio que 0023/0024 (`join insumos on nombre = ...`), distinto del patrón de ids
-- explícitos que usó 0022 (ahí sí había un SELECT previo del usuario con los ids reales pegados).
--
-- Orden de las secciones, no arbitrario — pedido explícito del usuario, y además necesario:
-- reasignar antes de borrar (si no, el DELETE de insumos falla por la FK restrict de
-- apu_composicion_items), normalizar unidades antes del `check` (si no, el `check` se rechaza solo
-- contra un valor que todavía no se limpió).
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

-- ===== SECCION 1: reasignaciones de apu_composicion_items (17 grupos) =====
update apu_composicion_items
set insumo_id = (select id from insumos where tipo = 'material' and nombre = 'CAL HIDRÁULICA')
where insumo_id in (
  select id from insumos where tipo = 'material' and nombre in ('CAL AEREA', 'CAL AEREA HIDRATADA', 'CAL HIDRAULICA O AEREA')
);

update apu_composicion_items
set insumo_id = (select id from insumos where tipo = 'material' and nombre = 'CINTA DE ENMASCARAR 24MM')
where insumo_id in (
  select id from insumos where tipo = 'material' and nombre in ('CINTA DE ENMASCARAR', 'CINTA DE ENMASCARAR AZUL/UV 48MM')
);

update apu_composicion_items
set insumo_id = (select id from insumos where tipo = 'material' and nombre = 'AGUARÁS MINERAL P/DILUCIÓN')
where insumo_id in (
  select id from insumos where tipo = 'material' and nombre in ('AGUARÁS/AGUA P/DILUCIÓN')
);

update apu_composicion_items
set insumo_id = (select id from insumos where tipo = 'material' and nombre = 'MASILLA PARA MADERA')
where insumo_id in (
  select id from insumos where tipo = 'material' and nombre in ('MASILLA P/MADERA DEL TONO DE LA PIEZA')
);

update apu_composicion_items
set insumo_id = (select id from insumos where tipo = 'material' and nombre = 'MACHIMBRE DE PINO/EUCALIPTO 1/2” X 4”')
where insumo_id in (
  select id from insumos where tipo = 'material' and nombre in ('MACHIMBRE PINO')
);

update apu_composicion_items
set insumo_id = (select id from insumos where tipo = 'material' and nombre = 'ALFAJIAS 2”X2” CEPILLADAS')
where insumo_id in (
  select id from insumos where tipo = 'material' and nombre in ('ALFAJIAS DE MADERA 2”X2”')
);

update apu_composicion_items
set insumo_id = (select id from insumos where tipo = 'material' and nombre = 'MEMBRANA ASFÁLTICA 4MM GEOTEXTIL')
where insumo_id in (
  select id from insumos where tipo = 'material' and nombre in ('MEMBRANA ASFÁLTICA 4MM CON GEOTEXTIL (IMPERMEABILIZACIÓN BASE)')
);

update apu_composicion_items
set insumo_id = (select id from insumos where tipo = 'material' and nombre = 'PLACA DE YESO STD 12.5MM (1.20 X 2.40M)')
where insumo_id in (
  select id from insumos where tipo = 'material' and nombre in ('PLACA YESO DE ROCA 12,5MM')
);

update apu_composicion_items
set insumo_id = (select id from insumos where tipo = 'material' and nombre = 'FONDO ANTIÓXIDO')
where insumo_id in (
  select id from insumos where tipo = 'material' and nombre in ('FONDO ANTIÓXIDO (2 MANOS)', 'ANTIÓXIDO / FONDO ALQUÍDICO ANTICORROSIVO (2 MANOS)')
);

update apu_composicion_items
set insumo_id = (select id from insumos where tipo = 'material' and nombre = 'CAÑO ESTRUCTURAL CUADRADO/RECTANGULAR O PERFIL C CONFORMADO EN FRÍO')
where insumo_id in (
  select id from insumos where tipo = 'material' and nombre in ('CAÑO ESTRUCTURAL CUADRADO/RECTANGULAR CONFORMADO EN FRÍO', 'PERFIL TUBULAR RECTANGULAR O PERFIL C ESTRUCTURAL CONFORMADO EN FRÍO')
);

update apu_composicion_items
set insumo_id = (select id from insumos where tipo = 'material' and nombre = 'PLACAS FENOLICA DE 18MM')
where insumo_id in (
  select id from insumos where tipo = 'material' and nombre in ('PLACAS FENOLICADE 18MM O MACHIMBRE 5” X 3/4”')
);

update apu_composicion_items
set insumo_id = (select id from insumos where tipo = 'material' and nombre = 'ESMALTE DE TERMINACIÓN')
where insumo_id in (
  select id from insumos where tipo = 'material' and nombre in ('ESMALTE SINTÉTICO DE TERMINACIÓN (2 MANOS)')
);

update apu_composicion_items
set insumo_id = (select id from insumos where tipo = 'material' and nombre = 'YESO BLANCO')
where insumo_id in (
  select id from insumos where tipo = 'material' and nombre in ('YESO BLANCO DE CONSTRUCCIÓN TRADICIONAL', 'YESO DE TERMINACIÓN (MONOFINO / ENDUIDO)', 'YESO DE TERMINACIÓN / ENLUCIDO')
);

update apu_composicion_items
set insumo_id = (select id from insumos where tipo = 'material' and nombre = 'DILUYENTE')
where insumo_id in (
  select id from insumos where tipo = 'material' and nombre in ('DILUYENTE / THINNER', 'THINNER / DESENGRASANTE DE LIMPIEZA PREVIA')
);

update apu_composicion_items
set insumo_id = (select id from insumos where tipo = 'material' and nombre = 'MALLA FIBRA DE VIDRIO 160G/M2')
where insumo_id in (
  select id from insumos where tipo = 'material' and nombre in ('MALLA FIBRA')
);

update apu_composicion_items
set insumo_id = (select id from insumos where tipo = 'material' and nombre = 'HOJA DE LIJA')
where insumo_id in (
  select id from insumos where tipo = 'material' and nombre in ('LIJA')
);

update apu_composicion_items
set insumo_id = (select id from insumos where tipo = 'material' and nombre = 'AISLACION HIDROFUGA TIPO TYVEK')
where insumo_id in (
  select id from insumos where tipo = 'material' and nombre in ('AISLACION HIDROFUGA')
);

-- ===== SECCION 2: borrados (25 absorbidas + 4 de Hierro del 12mm = 29 filas) =====
-- defensivo, igual criterio que 0022: no deberia borrar nada (ya reasignado arriba /
-- Hierro del 12mm nunca tuvo referencias), pero cuesta cero y protege si algo cambio
-- entre el diagnostico y la aplicacion real.
delete from apu_composicion_items where insumo_id in (
  select id from insumos where tipo = 'material' and nombre in (
  'CAL AEREA',
  'CAL AEREA HIDRATADA',
  'CAL HIDRAULICA O AEREA',
  'CINTA DE ENMASCARAR',
  'CINTA DE ENMASCARAR AZUL/UV 48MM',
  'AGUARÁS/AGUA P/DILUCIÓN',
  'MASILLA P/MADERA DEL TONO DE LA PIEZA',
  'MACHIMBRE PINO',
  'ALFAJIAS DE MADERA 2”X2”',
  'MEMBRANA ASFÁLTICA 4MM CON GEOTEXTIL (IMPERMEABILIZACIÓN BASE)',
  'PLACA YESO DE ROCA 12,5MM',
  'FONDO ANTIÓXIDO (2 MANOS)',
  'ANTIÓXIDO / FONDO ALQUÍDICO ANTICORROSIVO (2 MANOS)',
  'CAÑO ESTRUCTURAL CUADRADO/RECTANGULAR CONFORMADO EN FRÍO',
  'PERFIL TUBULAR RECTANGULAR O PERFIL C ESTRUCTURAL CONFORMADO EN FRÍO',
  'PLACAS FENOLICADE 18MM O MACHIMBRE 5” X 3/4”',
  'ESMALTE SINTÉTICO DE TERMINACIÓN (2 MANOS)',
  'YESO BLANCO DE CONSTRUCCIÓN TRADICIONAL',
  'YESO DE TERMINACIÓN (MONOFINO / ENDUIDO)',
  'YESO DE TERMINACIÓN / ENLUCIDO',
  'DILUYENTE / THINNER',
  'THINNER / DESENGRASANTE DE LIMPIEZA PREVIA',
  'MALLA FIBRA',
  'LIJA',
  'AISLACION HIDROFUGA',
  'Hierro del 12mm'
  )
);

delete from precios where insumo_id in (
  select id from insumos where tipo = 'material' and nombre in (
  'CAL AEREA',
  'CAL AEREA HIDRATADA',
  'CAL HIDRAULICA O AEREA',
  'CINTA DE ENMASCARAR',
  'CINTA DE ENMASCARAR AZUL/UV 48MM',
  'AGUARÁS/AGUA P/DILUCIÓN',
  'MASILLA P/MADERA DEL TONO DE LA PIEZA',
  'MACHIMBRE PINO',
  'ALFAJIAS DE MADERA 2”X2”',
  'MEMBRANA ASFÁLTICA 4MM CON GEOTEXTIL (IMPERMEABILIZACIÓN BASE)',
  'PLACA YESO DE ROCA 12,5MM',
  'FONDO ANTIÓXIDO (2 MANOS)',
  'ANTIÓXIDO / FONDO ALQUÍDICO ANTICORROSIVO (2 MANOS)',
  'CAÑO ESTRUCTURAL CUADRADO/RECTANGULAR CONFORMADO EN FRÍO',
  'PERFIL TUBULAR RECTANGULAR O PERFIL C ESTRUCTURAL CONFORMADO EN FRÍO',
  'PLACAS FENOLICADE 18MM O MACHIMBRE 5” X 3/4”',
  'ESMALTE SINTÉTICO DE TERMINACIÓN (2 MANOS)',
  'YESO BLANCO DE CONSTRUCCIÓN TRADICIONAL',
  'YESO DE TERMINACIÓN (MONOFINO / ENDUIDO)',
  'YESO DE TERMINACIÓN / ENLUCIDO',
  'DILUYENTE / THINNER',
  'THINNER / DESENGRASANTE DE LIMPIEZA PREVIA',
  'MALLA FIBRA',
  'LIJA',
  'AISLACION HIDROFUGA',
  'Hierro del 12mm'
  )
);

delete from obra_insumo_precios where insumo_id in (
  select id from insumos where tipo = 'material' and nombre in (
  'CAL AEREA',
  'CAL AEREA HIDRATADA',
  'CAL HIDRAULICA O AEREA',
  'CINTA DE ENMASCARAR',
  'CINTA DE ENMASCARAR AZUL/UV 48MM',
  'AGUARÁS/AGUA P/DILUCIÓN',
  'MASILLA P/MADERA DEL TONO DE LA PIEZA',
  'MACHIMBRE PINO',
  'ALFAJIAS DE MADERA 2”X2”',
  'MEMBRANA ASFÁLTICA 4MM CON GEOTEXTIL (IMPERMEABILIZACIÓN BASE)',
  'PLACA YESO DE ROCA 12,5MM',
  'FONDO ANTIÓXIDO (2 MANOS)',
  'ANTIÓXIDO / FONDO ALQUÍDICO ANTICORROSIVO (2 MANOS)',
  'CAÑO ESTRUCTURAL CUADRADO/RECTANGULAR CONFORMADO EN FRÍO',
  'PERFIL TUBULAR RECTANGULAR O PERFIL C ESTRUCTURAL CONFORMADO EN FRÍO',
  'PLACAS FENOLICADE 18MM O MACHIMBRE 5” X 3/4”',
  'ESMALTE SINTÉTICO DE TERMINACIÓN (2 MANOS)',
  'YESO BLANCO DE CONSTRUCCIÓN TRADICIONAL',
  'YESO DE TERMINACIÓN (MONOFINO / ENDUIDO)',
  'YESO DE TERMINACIÓN / ENLUCIDO',
  'DILUYENTE / THINNER',
  'THINNER / DESENGRASANTE DE LIMPIEZA PREVIA',
  'MALLA FIBRA',
  'LIJA',
  'AISLACION HIDROFUGA',
  'Hierro del 12mm'
  )
);

delete from insumos where tipo = 'material' and nombre in (
  'CAL AEREA',
  'CAL AEREA HIDRATADA',
  'CAL HIDRAULICA O AEREA',
  'CINTA DE ENMASCARAR',
  'CINTA DE ENMASCARAR AZUL/UV 48MM',
  'AGUARÁS/AGUA P/DILUCIÓN',
  'MASILLA P/MADERA DEL TONO DE LA PIEZA',
  'MACHIMBRE PINO',
  'ALFAJIAS DE MADERA 2”X2”',
  'MEMBRANA ASFÁLTICA 4MM CON GEOTEXTIL (IMPERMEABILIZACIÓN BASE)',
  'PLACA YESO DE ROCA 12,5MM',
  'FONDO ANTIÓXIDO (2 MANOS)',
  'ANTIÓXIDO / FONDO ALQUÍDICO ANTICORROSIVO (2 MANOS)',
  'CAÑO ESTRUCTURAL CUADRADO/RECTANGULAR CONFORMADO EN FRÍO',
  'PERFIL TUBULAR RECTANGULAR O PERFIL C ESTRUCTURAL CONFORMADO EN FRÍO',
  'PLACAS FENOLICADE 18MM O MACHIMBRE 5” X 3/4”',
  'ESMALTE SINTÉTICO DE TERMINACIÓN (2 MANOS)',
  'YESO BLANCO DE CONSTRUCCIÓN TRADICIONAL',
  'YESO DE TERMINACIÓN (MONOFINO / ENDUIDO)',
  'YESO DE TERMINACIÓN / ENLUCIDO',
  'DILUYENTE / THINNER',
  'THINNER / DESENGRASANTE DE LIMPIEZA PREVIA',
  'MALLA FIBRA',
  'LIJA',
  'AISLACION HIDROFUGA',
  'Hierro del 12mm'
);

-- ===== SECCION 3: renombres (5 sobrevivientes de grupo + 7 puros = 12) =====
update insumos set nombre = 'AGUARRÁS MINERAL P/DILUCIÓN'
where tipo = 'material' and nombre = 'AGUARÁS MINERAL P/DILUCIÓN';

update insumos set nombre = 'ANTIOXIDO'
where tipo = 'material' and nombre = 'FONDO ANTIÓXIDO';

update insumos set nombre = 'PLACAS FENOLICAS DE 18MM O MACHIMBRE 5” X 3/4”'
where tipo = 'material' and nombre = 'PLACAS FENOLICA DE 18MM';

update insumos set nombre = 'ESMALTE SINTÉTICO'
where tipo = 'material' and nombre = 'ESMALTE DE TERMINACIÓN';

update insumos set nombre = 'YESO'
where tipo = 'material' and nombre = 'YESO BLANCO';

update insumos set nombre = 'REALCES 1/2” X 1”'
where tipo = 'material' and nombre = 'REALCES';

update insumos set nombre = 'LISTONES 2” X 2” VERTICALES CADA 0,40 M'
where tipo = 'material' and nombre = 'LISTONES VERTICALES CADA 0,40 M';

update insumos set nombre = 'PERFIL MONTANTE 35MM U OMEGA REFORZADA'
where tipo = 'material' and nombre = 'PERFIL MONTANTE 35MM U OMEGA (ESTRUCTURA/VELAS)';

update insumos set nombre = 'CERAMICO MEDIANO'
where tipo = 'material' and nombre = 'CERAMICO';

update insumos set nombre = 'CERAMICO MEDIANO O PORCELANATO MEDIANO'
where tipo = 'material' and nombre = 'CERAMICO O PORCELANATO';

update insumos set nombre = 'TIERRA FERTIL'
where tipo = 'material' and nombre = 'TIERRA';

update insumos set nombre = 'AISLACION TERMICA (LANA DE VIDRIO 50MM)'
where tipo = 'material' and nombre = 'AISLACION TERMICA';

-- ===== SECCION 4: normalización de unidades (antes del check, si no se rechaza solo) =====
-- 'unidad' (minúscula) no aparece acá: son las 4 filas de Hierro del 12mm, ya borradas en la
-- Sección 2 — desaparece sola, no hace falta UPDATE.
update insumos set unidad = 'LTRS' where unidad in ('LITROS', 'LITRS') and unidad <> 'LTRS';

update insumos set unidad = 'M3' where unidad = 'm3';

update insumos set unidad = 'ML' where unidad = 'M';

-- 'bolsa' es CEMENTO PORTLAND X 25KG, el único insumo del catálogo con precio real — la unidad de
-- *compra* (se compra por bolsa de 25kg) metida por error en el campo de unidad de *uso*. La
-- composición lo usa con rendimiento 320 (kg de cemento por m³ de hormigón, dosificación de
-- manual) — la unidad de uso real es KG, no 'bolsa'. Agregado acá porque una primera versión de
-- esta migración asumía que esto ya estaba corregido a mano y no era cierto (ver comentario de
-- cabecera) — el `check` de la Sección 6 lo rechazó sin aplicar nada más.
update insumos set unidad = 'KG' where tipo = 'material' and nombre = 'CEMENTO PORTLAND X 25KG';

-- ===== SECCION 5: CEMENTO PORTLAND X 25KG — unidad_compra / factor_conversion =====
-- Caso testigo de la distinción unidad de compra vs. unidad de uso (docs/monetizacion.md, punto 5:
-- "schema unidad de compra vs. unidad de uso con factor de conversión" — pieza central del motor
-- de precios). `unidad` ya quedó en 'KG' por el UPDATE de la Sección 4, justo arriba.
update insumos
set unidad_compra = 'bolsa 25kg', factor_conversion = 25
where tipo = 'material' and nombre = 'CEMENTO PORTLAND X 25KG';

-- ===== SECCION 6: check de unidades válidas (recién acá, después de normalizar) =====
-- 8 valores: los 7 de material que sobreviven a la Sección 4 + 'hs' de mano de obra (confirmado
-- correcto por el usuario, no se toca). Sin CHECK previo sobre esta columna — primera vez que se
-- restringe, ver 0038_zona_uocra.sql para el mismo criterio aplicado a otra columna del proyecto
-- ("sin check a propósito... hasta que la integridad la dé una tabla catálogo o, como acá, una
-- limpieza + lista cerrada").
alter table insumos
  add constraint insumos_unidad_valida
  check (unidad in ('KG', 'LTRS', 'M2', 'M3', 'ML', 'TON', 'UND', 'hs'));

-- ===== SECCION 7: typo "aislacion hidraulica" -> "aislacion hidrofuga" en subitems 5.6/6.6/15.3 =====
-- Encontrado al diagnosticar por qué AISLACION TERMICA/AISLACION HIDROFUGA (genéricas) se usaban
-- justo en estas 3 partidas: el texto de la propia descripción decía "hidraulica" cuando el insumo
-- real que la partida usa es "hidrofuga" — typo visible al usuario, no solo interno.
--
-- OJO — interacción con 0047_subitems_descripcion_mayuscula.sql (sin confirmar si ya se aplicó):
-- esa migración reescribe estos mismos 3 textos en MAYÚSCULA, typo incluido ("AISLACION
-- HIDRAULICA"). El `replace()` de abajo cubre las dos variantes (minúscula/mixta de 0016 y
-- mayúscula de 0047) para que el fix ande sin importar si 0047 ya corrió o no — si ninguna de las
-- dos coincide, no hace nada, no rompe.
update subitems
set descripcion = replace(
  replace(descripcion, 'aislacion hidraulica', 'aislacion hidrofuga'),
  'AISLACION HIDRAULICA', 'AISLACION HIDROFUGA'
)
where codigo in ('5.6', '6.6', '15.3')
  and creador_usuario_id is null;

-- =====================================================================
-- Verificación — correr las 4 después de aplicar todo lo de arriba
-- =====================================================================

-- 1) Total de insumos: esperado 210 (239 antes de esta migración − 25 absorbidas − 4 huérfanas de
--    Hierro del 12mm). NO son 206 — un conteo anterior en el diagnóstico de esta pieza había dado
--    29 absorbidas por error (contaba de más en 4 de los 17 grupos); el número correcto, generado
--    programáticamente contra los nombres reales de esta misma migración, es 25.
select count(*) as total_insumos from insumos;

-- 2) Ningún apu_composicion_items debe quedar apuntando a un insumo que ya no existe — esperado 0.
select count(*) as composicion_items_huerfanos
from apu_composicion_items ci
left join insumos i on i.id = ci.insumo_id
where i.id is null;

-- 3) La más importante: el total de apu_composicion_items de las 97 partidas de rubros 2-17 tiene
--    que seguir dando 770. Si baja, se perdió una receta en alguna reasignación de la Sección 1.
select count(*) as total_apu_composicion_items
from apu_composicion_items aci
join apu_composiciones ac on ac.id = aci.apu_composicion_id
join subitems s on s.id = ac.subitem_id
where ac.creador_usuario_id is null
  and s.codigo in (
    '2.1','2.2','2.3','3.1','3.2','3.3','3.4','4.1','4.2','4.3','4.4','4.5','4.6','4.7',
    '5.1','5.2','5.3','5.4','5.5','5.6','6.1','6.2','6.3','6.4','6.5','6.6','7.1','7.2','7.3',
    '8.1','8.2','8.3','8.4','8.5','8.6','8.7','8.8','8.9','8.10','8.11','8.12',
    '9.1','9.2','9.3','10.1','10.2','10.3','10.4','10.5','10.6','10.7',
    '11.1','11.2','11.3','11.4','11.5','11.6',
    '12.1','12.2','12.3','12.4','12.5','12.6','12.7','12.8','12.9','12.10','12.11','12.12',
    '13.1','13.2','13.3','13.4','13.5','13.6','13.7',
    '14.1','14.2','14.3','14.4','14.5','14.6',
    '15.1','15.2','15.3','15.4','15.5',
    '16.1','16.2','16.3','16.4','16.5',
    '17.1','17.2','17.3','17.4','17.5'
  ) and s.creador_usuario_id is null;

-- 4) Solo deberían quedar los 8 valores válidos de unidad (más lo que tenga la tabla `equipo`/
--    filas fuera de este catálogo, hoy 0, si alguna vez se cargan tendrán que respetar el mismo
--    check).
select unidad, count(*) from insumos group by unidad order by count(*) desc;

-- 5) Confirmación visual del fix del typo — las tres deberían decir "hidrofuga", ninguna
--    "hidraulica".
select codigo, descripcion from subitems where codigo in ('5.6', '6.6', '15.3');
