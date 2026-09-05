-- Corrige un bug de catálogo real, encontrado al cargar el precio de referencia de PIEDRA: 0022
-- sembró PIEDRA en unidad M2 cuando debería ser M3 (canto rodado). Al revisar si el mismo error se
-- repetía, se encontró que TABLAS y TIRANTES también quedaron en M2 debiendo ser ML — un criterio
-- que Seba ya había definido en la ronda de la limpieza de catálogo (0049) pero que nunca se llegó
-- a aplicar en la base: 0049 unificó/renombró filas, pero no tocó estas tres unidades.
--
-- Evidencia de que el criterio correcto es el que se aplica acá, no una suposición nueva:
-- - PIEDRA se usa en 3.1-3.4/4.1-4.7 (Fundaciones/Hormigón Armado) junto con ARENA (mismo
--   rendimiento en cada partida) y CEMENTO PORTLAND X 25KG (320kg) -- es la dosificación clásica
--   de hormigón por m³ (arena + piedra + cemento), así que esos rendimientos ya son m³, no m².
-- - TABLAS/TIRANTES se usan en el mismo bloque de partidas (encofrado de fundaciones/estructura),
--   medidos por metro lineal de tabla/tirante de encofrado -- ya se había cargado su precio en
--   0058 (SB Maderas) asumiendo ML sin corregir la columna, mismo error, sin que nadie lo notara
--   hasta ahora porque ningún consumidor comparaba la unidad declarada contra el rendimiento real.
--
-- Los UPDATE son defensivos (solo tocan la fila si el valor actual es el que se espera corregir) --
-- si alguna de las tres ya estuviera bien por algún motivo no documentado, no hacen nada, no pisan
-- un valor correcto a ciegas.
--
-- ARENA: Seba pidió confirmar la unidad real en la base en vez de asumirla -- no está declarada en
-- ninguna migración (fila previa a 0022, renombrada desde "Arena fina", ver 0022 §Sección 1), así
-- que no se puede verificar por código, solo por consulta en vivo. Mismo patrón defensivo: el
-- UPDATE de abajo solo corrige si encuentra el mismo error (M2), no asume que está mal. Correr la
-- SELECT de verificación #1 antes para ver qué tenía ANTES de este archivo, y la #4 depués para
-- confirmar qué quedó.
--
-- Consecuencia a revisar, no resuelta acá: cambiar la unidad de un insumo no cambia los
-- rendimientos de las composiciones que lo usan -- si esos rendimientos ya estaban expresados en
-- la unidad nueva (m³/ML, ver evidencia arriba), no hace falta tocarlos; si en algún momento se
-- cargaron pensando en m², sí. Ver el listado completo de partidas/rendimientos de PIEDRA en la
-- conversación de esta pieza (14 partidas: 3.1-3.4, 4.1-4.7 con 0.65 cada una -- dosificación de
-- hormigón; 11.2/11.5 con 0.08 -- contrapiso de hormigón armado esp. 8cm; 13.5 con 1.25 --
-- revestimiento molón de piedra esp. 10-15cm) para que Seba confirme si algún rendimiento necesita
-- ajuste. TABLAS/TIRANTES: 3.2-3.4/4.1-4.7, mismo bloque de encofrado, rendimientos entre 0.25 y 3.5.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor), después de 0061. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

-- =====================================================================
-- Verificación PREVIA — correr antes de los UPDATE, para tener el "antes" a mano
-- =====================================================================

select nombre, unidad from insumos where nombre in ('PIEDRA', 'TABLAS', 'TIRANTES', 'ARENA');

-- =====================================================================
-- Correcciones defensivas
-- =====================================================================

update insumos set unidad = 'M3' where nombre = 'PIEDRA' and unidad = 'M2' and creador_usuario_id is null;

update insumos set unidad = 'ML' where nombre = 'TABLAS' and unidad = 'M2' and creador_usuario_id is null;

update insumos set unidad = 'ML' where nombre = 'TIRANTES' and unidad = 'M2' and creador_usuario_id is null;

-- Mismo criterio defensivo: solo corrige si encuentra el mismo error que las otras tres. No se
-- asume que ARENA está mal -- la SELECT previa y la de verificación de abajo muestran qué pasó.
update insumos set unidad = 'M3' where nombre = 'ARENA' and unidad = 'M2' and creador_usuario_id is null;

-- =====================================================================
-- PIEDRA — el precio de referencia ($70.000/m³, sin IVA) SIGUE SIN CARGARSE
-- =====================================================================
--
-- Nueva pregunta encontrada al escribir esto, no estaba antes: `precios.corralon_id` no admite
-- null (mismo motivo por el que 0058 falló la primera vez con `corralones.lat` -- estas dos tablas
-- no tienen columnas opcionales donde uno esperaría). Este precio no es la cotización de ningún
-- corralón real (Sólido/Felemax/SB Maderas/HIZA) -- es un valor de mercado que aportó Seba de
-- memoria, sin vendedor detrás. No hay ninguna fila de `corralones` a la que atribuírselo
-- honestamente.
--
-- Dos caminos, a decidir antes de escribir el INSERT (no se elige acá):
-- 1. Crear un corralón placeholder tipo "Referencia de mercado" para colgar precios sin vendedor
--    real -- mismo mecanismo que ya existen (Sólido/Felemax/SB Maderas/HIZA), pero con esa
--    identidad. Necesitaría su propio criterio: ¿lat/lng de qué poner si esa columna es NOT NULL
--    (ver 0058)? ¿Cómo se distingue en la UI de un corralón real para no confundir al usuario?
-- 2. No cargar en `precios` y guardarlo en otro lado (docs/ o una nota) hasta que exista un
--    mecanismo real para precios sin corralón -- mismo gap ya anotado en docs/confianza_precios_
--    diseno.md para la sierra de 60 dientes, PIEDRA sería el segundo caso sin resolver.
--
-- No se inventa ninguna de las dos opciones acá -- queda para la próxima ronda.

-- =====================================================================
-- Verificación — correr después de las tres correcciones
-- =====================================================================

-- 1) Las cuatro unidades quedan como corresponde: PIEDRA/ARENA en M3, TABLAS/TIRANTES en ML.
select nombre, unidad from insumos where nombre in ('PIEDRA', 'TABLAS', 'TIRANTES', 'ARENA');

-- 2) Ningún apu_composicion_items queda huérfano (el cambio de unidad no toca insumo_id, esto
--    debería dar 0 de todos modos -- mismo chequeo de siempre, gratis de correr).
select count(*) as huerfanos
from apu_composicion_items ci
left join insumos i on i.id = ci.insumo_id
where i.id is null;

-- 3) Los rendimientos de PIEDRA/TABLAS/TIRANTES para que Seba los revise con la unidad ya
--    corregida a la vista (misma consulta que en el diagnóstico, para no tener que volver a pedirla).
select s.codigo, s.descripcion, aci.rendimiento
from apu_composicion_items aci
join apu_composiciones ac on ac.id = aci.apu_composicion_id
join subitems s on s.id = ac.subitem_id
join insumos i on i.id = aci.insumo_id
where i.nombre in ('PIEDRA', 'TABLAS', 'TIRANTES')
  and ac.creador_usuario_id is null
order by i.nombre, s.codigo;
