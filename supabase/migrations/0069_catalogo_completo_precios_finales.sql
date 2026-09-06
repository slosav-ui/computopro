-- Carga final del catálogo: ningún insumo queda sin precio. Tres piezas, en este orden porque la
-- fusión y la corrección de Felemax tienen que estar antes de la carga masiva de precios (la
-- fusión libera el nombre/insumo que se va a usar en la Sección 3; la corrección de Felemax es un
-- precio real que se nos había pasado, no tiene que confundirse con la carga de referencia).
--
-- Motivo de negocio (para que quede escrito, no solo en la conversación): el catálogo tiene que
-- estar completo antes de repartir el APK. Un catálogo a medias hace que el primer usuario que lo
-- abra piense que la app está incompleta. Un precio estimado y marcado como tal es mejor que un
-- hueco.
--
-- Los 49 precios "estimados" de la Sección 3 son precios de referencia de mercado, NO
-- cotizaciones -- verificados contra precios reales y la lista salió mezclada (algunos a nivel
-- Bariloche, otros a nivel Buenos Aires), así que no se les aplica ningún factor de corrección
-- único, van tal cual. El corralón 'Cantera privada (referencia)' (creado en 0063) es HOY la
-- ÚNICA señal en la app de que un precio no es una cotización real -- mismo gap ya anotado en
-- docs/confianza_precios_diseno.md, sin resolver todavía (no hay columna en `precios` que
-- distinga precio cotizado de precio de referencia).
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor), después de 0068. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

-- =====================================================================
-- Sección 1 — Fusión: AISLACION TERMICA EPS O LANA DE VIDRIO 50MM se absorbe en
-- AISLACION TERMICA (LANA DE VIDRIO 50MM)
-- =====================================================================
--
-- El nombre del absorbido nombraba dos productos a la vez (EPS o lana de vidrio). Decisión de
-- Seba: en las dos partidas que lo usan (14.3, 14.4) va lana de vidrio de 50mm. EPS ALTA DENSIDAD
-- (insumo distinto, con precio propio de HIZA desde 0065) no se toca.
--
-- Conversión de rendimiento: el absorbido estaba en ML, el sobreviviente está en M2. El rollo de
-- lana de vidrio de 50mm es de 1,20m de ancho (cotización HIZA, "Rollo 100mm x 1.2 x 6m") -- cada
-- rendimiento en ML se multiplica por 1,20 para expresarlo en M2 (mismo criterio ya usado en 0062/
-- 0066 para convertir ML<->M2 por ancho real de material). Afecta a 14.3 y 14.4 (rendimiento
-- 1.05 -> 1.26 cada una), las únicas dos composiciones que usan el absorbido (ver 0023).
--
-- Sin precio que reasignar: el absorbido nunca llegó a tener una fila en `precios` -- quedó sin
-- cargar en 0065 por esta misma ambigüedad de ancho de rollo (ver esa migración, punto 3). Los dos
-- UPDATE de precios/obra_insumo_precios de abajo son defensivos, no se espera que toquen ninguna
-- fila -- mismo criterio "no confiar en la verificación estática" que ya costó un miss real en 0068
-- (Parte 1, ENDUIDO PLÁSTICO).

update apu_composicion_items aci
set insumo_id = isup.id, rendimiento = aci.rendimiento * 1.2
from insumos isup, insumos iabs
where isup.nombre = 'AISLACION TERMICA (LANA DE VIDRIO 50MM)' and isup.creador_usuario_id is null
  and iabs.nombre = 'AISLACION TERMICA EPS O LANA DE VIDRIO 50MM' and iabs.creador_usuario_id is null
  and aci.insumo_id = iabs.id;

update precios p
set insumo_id = isup.id
from insumos isup, insumos iabs
where isup.nombre = 'AISLACION TERMICA (LANA DE VIDRIO 50MM)' and isup.creador_usuario_id is null
  and iabs.nombre = 'AISLACION TERMICA EPS O LANA DE VIDRIO 50MM' and iabs.creador_usuario_id is null
  and p.insumo_id = iabs.id;

update obra_insumo_precios oip
set insumo_id = isup.id
from insumos isup, insumos iabs
where isup.nombre = 'AISLACION TERMICA (LANA DE VIDRIO 50MM)' and isup.creador_usuario_id is null
  and iabs.nombre = 'AISLACION TERMICA EPS O LANA DE VIDRIO 50MM' and iabs.creador_usuario_id is null
  and oip.insumo_id = iabs.id;

delete from insumos
where nombre = 'AISLACION TERMICA EPS O LANA DE VIDRIO 50MM'
  and creador_usuario_id is null
  and not exists (select 1 from apu_composicion_items where insumo_id = insumos.id)
  and not exists (select 1 from precios where insumo_id = insumos.id)
  and not exists (select 1 from obra_insumo_precios where insumo_id = insumos.id);

-- =====================================================================
-- Sección 2 — Precio de Felemax que nunca se cargó: Siding Volcan 8mm
-- =====================================================================
--
-- Felemax cotizó siding en su presupuesto original (mismo lote de 04/09/2026 que 0058 cargó) y esa
-- línea no se mapeó en su momento -- se detectó al verificar el catálogo completo contra las 88
-- líneas del presupuesto de Felemax. "Siding Volcan 8mm Nativa Natural 190mmx3660mm", $18.677,27
-- la placa en efectivo. Placa de 0,19 x 3,66 = 0,695 m² -> $26.874,49/m². Es una cotización real
-- de Felemax, no una referencia -- va con su corralón, no con 'Cantera privada (referencia)'.
--
-- fecha_actualizacion: 04/09/2026, la fecha real de esa cotización (misma fecha que el resto del
-- lote de Felemax en 0058), no la fecha en que se aplica esta migración.

insert into precios (insumo_id, corralon_id, valor, fecha_actualizacion)
select i.id, c.id, 26874.49, '2026-09-04'
from insumos i, corralones c
where i.nombre = 'PLACAS / TABLAS DE SIDING 19CM X 3.60M' and i.creador_usuario_id is null
  and c.nombre = 'Felemax'
  and not exists (
    select 1 from precios p where p.insumo_id = i.id and p.corralon_id = c.id
  );

-- =====================================================================
-- Sección 3 — Los 63 precios: catálogo completo
-- =====================================================================
--
-- Cuatro con precio real de cotización (van con HIZA, no con la referencia). De estos cuatro,
-- BOQUILLA / DADO HEXAGONAL MAGNÉTICO ya tiene exactamente este mismo precio ($8.360) cargado
-- desde 0058 (ver 0065, punto 1 -- decisión de Seba de no tocarlo). El `where not exists` de abajo
-- lo deja afuera solo -- no se fuerza a 0 ni a 1, que la verificación de la Sección "Verificación"
-- diga cuántas de las 4 entraron nuevas (esperado: 3, la de BOQUILLA no debería sumar fila).
--
-- fecha_actualizacion: 06/09/2026, fecha en que Seba cerró esta ronda de valores (no hay una
-- cotización con fecha propia detrás para estos tres -- mismo criterio que 0063/0067 con
-- 'Cantera privada (referencia)').

insert into precios (insumo_id, corralon_id, valor, fecha_actualizacion)
select i.id, c.id, v.valor, '2026-09-06'
from (values
  ('AISLACION TERMICA (LANA DE VIDRIO 50MM)', 6385.00),
  ('BANDA ACÚSTICA DE POLIETILENO 35MM', 705.00),
  ('BOQUILLA / DADO HEXAGONAL MAGNÉTICO (1/4" O 5/16")', 8360.00),
  ('TORNILLOS ZINCADOS PUNTA AGUJA/MECHA 3” CON ARANDELA DE GOMA', 198.00)
) as v(insumo_nombre, valor)
join insumos i on i.nombre = v.insumo_nombre and i.creador_usuario_id is null
join corralones c on c.nombre = 'HIZA'
where not exists (
  select 1 from precios p where p.insumo_id = i.id and p.corralon_id = c.id
);

-- Diez corregidos por Seba con precio de mercado real (ya convertidos a la unidad de uso del
-- catálogo) + cuarenta y nueve estimados sin factor -- los 59 van bajo 'Cantera privada
-- (referencia)'. Mismo criterio de `not exists` que el resto de esta migración: si alguno ya
-- tuviera una fila cargada para ese (insumo, corralón), no se duplica.

insert into precios (insumo_id, corralon_id, valor, fecha_actualizacion)
select i.id, c.id, v.valor, '2026-09-06'
from (values
  -- 10 corregidos
  ('BOLSAS DE PERLAS DE EPS X 170 LITROS', 269.99),
  ('CASCOTE DE LADRILLOS', 35210.00),
  ('ESPECIES VEGETALES (SEDUM / TEPE O MULTICELULAR)', 32310.00),
  ('MICROCEMENTO BASE', 8519.68),
  ('MÓDULO DRENANTE/RETENEDOR NODULAR HDPE', 13250.00),
  ('PERFIL PRINCIPAL T (3.60M)', 3688.16),
  ('PISO FLOTANTE MDF/HDF', 33974.10),
  ('PISO FLOTANTE VINILICO', 45772.00),
  ('TIERRA FERTIL', 95120.00),
  ('PLACAS / TABLAS DE SIDING 19CM X 3.60M', 35206.43),
  -- 49 estimados
  ('ACONDICIONADOR ÁCIDO / SOLUCIÓN NEUTRALIZANTE', 3600.00),
  ('ALAMBRE GALVANIZADO N° 14 P/SUSPENSIÓN', 320.00),
  ('ALFAJÍAS / LISTONES DE PINO 1" X 2" (CRUZADOS)', 480.00),
  ('ARCILLA EXPANDITA 3/10 (TIPIO RIPIOLITA, VERMICULITA, ETC.)', 162000.00),
  ('BALDOZAS', 2500.00),
  ('BASE NIVELADORA / IMPRIMACIÓN DEL MISMO TONO', 5100.00),
  ('BLOQUE DE HORMIGON CALADO 30/30 E=8CM', 4500.00),
  ('CABIOS DE PINO 6" X 2.1/2" (100 X 75 CEPILLADO)', 4200.00),
  ('CARTELAS / PLATINAS DE CONEXIÓN', 5200.00),
  ('CESPED', 14500.00),
  ('CLAVOS SIN CABEZA O TORNILLOS', 32.00),
  ('DESOXIDANTE / FOSFATIZANTE INDUSTRIAL', 4500.00),
  ('DILUYENTE ESPECÍFICO EPOXI', 7300.00),
  ('DISCO DIAMANTADO P/DESBASTE DE PISO', 32500.00),
  ('DISCOS DE CORTE DE VIDIA 9”', 38750.00),
  ('ESMALTE EPOXI / POLIURETÁNICO DE ALTO ESPESOR (2 COMP.)', 23600.00),
  ('FIJADOR / ACONDICIONADOR AL SOLVENTE (PENETRACIÓN)', 6900.00),
  ('LADRILLOS CERAMICOS HUECOS 8/18/33', 1250.00),
  ('LADRILLOS MACIZOS HCCA 10/25/50', 6800.00),
  ('LADRILLOS MACIZOS HCCA 15/25/50', 10200.00),
  ('LADRILLOS MACIZOS HCCA 20/25/50', 13600.00),
  ('LANA DE ACERO N° 0 / VIRUTA', 1850.00),
  ('MANTA GEOTEXTIL NO TEJIDA 150G/M2 (FILTRANTE)', 2500.00),
  ('MEMBRANA ANTI-RAÍZ EPDM / PVC (1.2MM)', 27500.00),
  ('METAL DESPLEGADO PESADO (300 G/M2)', 6100.00),
  ('MICROCEMENTO CAPA DE ACABADO', 5150.00),
  ('PERFIL DIVISORIO DE BORDE DE ALUMINIO CALADO', 5700.00),
  ('PERFIL MONTANTE 35MM U OMEGA REFORZADA', 2350.00),
  ('PERFIL PERIMETRAL L (3.00M)', 1900.00),
  ('PERFIL SOLERA 35MM (PERIMETRAL)', 2100.00),
  ('PERFIL Z / BUÑA PERIMETRAL DE PVC O ALUMINIO', 2950.00),
  ('PERFILES DE TERMINACIÓN (ESQUINEROS / ZÓCALOS)', 3900.00),
  ('PIEDRA LAJA', 1250.00),
  ('PLACAS ACÚSTICAS / FIBRA MINERAL O PVC 60 X 60', 23500.00),
  ('PRESERVADOR/FUNGICIDA BASE SOLVENTE', 8600.00),
  ('PRIMER / IMPRIMACIÓN EPOXI 100% SÓLIDOS (2 COMP.)', 26300.00),
  ('PUENTE DE ADHERENCIA LÍQUIDO (LÁTEX/PRIMER TÁCICO)', 7950.00),
  ('RECUBRIMIENTO ELASTOMÉRICO IMPERMEABILIZANTE (3-4 MANOS)', 9050.00),
  ('REVESTIMIENTO PLÁSTICO TEXTURADO (TEXTURA MEDIA)', 3600.00),
  ('SELLADOR ELASTOMÉRICO DE FISURAS (MASTIC PU)', 19400.00),
  ('SELLADOR PARA MADERA', 7550.00),
  ('SUSTRATO LIVIANO FORMULADO (INCLUYE % COMPACTACIÓN)', 102500.00),
  ('TORNILLERÍA / BULONES DE MONTAJE', 14600.00),
  ('TORNILLO PARA FIJACIÓN', 44.00),
  ('TORNILLOS PARA ALFAJIAS 3.1/2” X 8', 65.00),
  ('TORNILLOS PARA TABLAS 2” X 8', 50.00),
  ('TORNILLOS T2 MECHA / T4 ALAS', 48.00),
  ('VENDA / MALLA DE FIBRA DE VIDRIO P/FISURAS (10CM)', 900.00),
  ('ZOCALO MDF O VINILICO', 4200.00)
) as v(insumo_nombre, valor)
join insumos i on i.nombre = v.insumo_nombre and i.creador_usuario_id is null
join corralones c on c.nombre = 'Cantera privada (referencia)'
where not exists (
  select 1 from precios p where p.insumo_id = i.id and p.corralon_id = c.id
);

-- Nota sobre ARCILLA EXPANDITA (Sección 4 de la conversación, sin acción de SQL propia): queda con
-- este precio de $162.000/m³ y NO se reemplaza por perlas de EPS -- son dos formas distintas de
-- hacer el contrapiso aislante y las dos tienen que estar disponibles para que el usuario elija.

-- =====================================================================
-- Verificación
-- =====================================================================

-- 1) El absorbido ya no existe.
select nombre from insumos where nombre = 'AISLACION TERMICA EPS O LANA DE VIDRIO 50MM';
-- esperado: 0 filas.

-- 2) Los rendimientos de 14.3/14.4 quedaron convertidos (1.05 -> 1.26) bajo el insumo sobreviviente.
select s.codigo, i.nombre, aci.rendimiento
from apu_composicion_items aci
join apu_composiciones ac on ac.id = aci.apu_composicion_id
join subitems s on s.id = ac.subitem_id
join insumos i on i.id = aci.insumo_id
where s.codigo in ('14.3', '14.4') and ac.creador_usuario_id is null
  and i.nombre = 'AISLACION TERMICA (LANA DE VIDRIO 50MM)'
order by s.codigo;

-- 3) Cuántas filas nuevas entraron en cada tramo -- si alguno da menos de lo esperado, algún
--    nombre no matcheó (typo o rename no capturado), parar y revisar cuál antes de seguir.
--    Esperado: Felemax siding = 1, HIZA reales = 3 (BOQUILLA no debería sumar), referencia = 59.
select
  (select count(*) from precios p join corralones c on c.id = p.corralon_id
     join insumos i on i.id = p.insumo_id
     where c.nombre = 'Felemax' and i.nombre = 'PLACAS / TABLAS DE SIDING 19CM X 3.60M') as felemax_siding,
  (select count(*) from precios p join corralones c on c.id = p.corralon_id
     where c.nombre = 'HIZA' and p.fecha_actualizacion = '2026-09-06') as hiza_reales_nuevos,
  (select count(*) from precios p join corralones c on c.id = p.corralon_id
     where c.nombre = 'Cantera privada (referencia)' and p.fecha_actualizacion = '2026-09-06') as referencia_nuevos;

-- 4) Ningún apu_composicion_items ni precios quedó huérfano.
select count(*) as huerfanos_apu
from apu_composicion_items ci left join insumos i on i.id = ci.insumo_id where i.id is null;

select count(*) as huerfanos_precios
from precios p left join insumos i on i.id = p.insumo_id where i.id is null;

-- 5) Ningún insumo quedó con dos precios del mismo corralón.
select insumo_id, corralon_id, count(*) as filas
from precios group by insumo_id, corralon_id having count(*) > 1;

-- 6) Conteo de insumos -- tiene que bajar en 1 por la fusión (Seba lo espera en 174).
select count(*) as total_insumos from insumos;

-- 7) La verificación central: sin_precio tiene que dar 0.
select
  (select count(*) from insumos) as insumos,
  (select count(*) from precios) as precios,
  (select count(*) from insumos i where i.tipo != 'mano_obra'
     and exists (select 1 from apu_composicion_items ci where ci.insumo_id = i.id)
     and not exists (select 1 from precios p where p.insumo_id = i.id)) as sin_precio;
