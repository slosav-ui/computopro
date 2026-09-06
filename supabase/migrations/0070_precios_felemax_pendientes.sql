-- Resuelve las 3 líneas de la cotización de Felemax que quedaron sin precio al auditar el
-- catálogo completo en la ronda de 0069 (la cuarta, el siding, ya se cargó ahí). Dos necesitaban
-- un dato que faltaba (ancho de rollo, metraje de blíster); la tercera no necesitaba ningún dato,
-- solo estaba pendiente de cargar.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor), después de 0069. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

-- =====================================================================
-- 1) MEMBRANA ASFÁLTICA 4MM GEOTEXTIL, Felemax — se promedia, no se agrega una fila nueva
-- =====================================================================
--
-- Felemax cotizó dos membranas distintas ("Membrana Hidrófuga Patagónico" y "Membrana Asfáltica
-- c/Geotextil N500") que el mapeo original (0058) ya hizo caer sobre el mismo insumo tentativo del
-- catálogo -- no hay dos filas en `insumos` para distinguirlas. Mismo criterio que ya usó esa
-- misma carga para cal Santa Bárbara/Risco Bayo y los dos adhesivos cementicios: se promedia el
-- valor, no se elige uno ni se agrega una segunda fila para el mismo (insumo, corralón) -- eso
-- crearía exactamente el tipo de duplicado que 0068 tuvo que limpiar a mano.
--
-- Dato de Seba: el rollo es de 1m de ancho, así que el precio por ML ya es el precio por M2, sin
-- conversión -- $15.204,44 (precio del rollo "X10 Mts") / 10 = $1.520,44/m2.
--
-- Promedio con el valor ya cargado (Patagónico, $1.464,0733): ($1.464,0733 + $1.520,44) / 2 =
-- $1.492,26.

update precios p
set valor = 1492.26, fecha_actualizacion = '2026-09-06'
from insumos i, corralones c
where p.insumo_id = i.id and p.corralon_id = c.id
  and i.nombre = 'MEMBRANA ASFÁLTICA 4MM GEOTEXTIL' and i.creador_usuario_id is null
  and c.nombre = 'Felemax';

-- =====================================================================
-- 2) CINTA DE ENMASCARAR 24MM, Felemax — fila nueva
-- =====================================================================
--
-- Dato de Seba: el blíster trae 50 metros -- $4.311,72 / 50 = $86,23/ml. Felemax no tenía ningún
-- precio cargado para este insumo (solo HIZA, $114,75 desde 0065) -- entra como segundo proveedor.

insert into precios (insumo_id, corralon_id, valor, fecha_actualizacion)
select i.id, c.id, 86.23, '2026-09-06'
from insumos i, corralones c
where i.nombre = 'CINTA DE ENMASCARAR 24MM' and i.creador_usuario_id is null
  and c.nombre = 'Felemax'
  and not exists (select 1 from precios p where p.insumo_id = i.id and p.corralon_id = c.id);

-- =====================================================================
-- 3) DISCOS DE CORTE PARA AMOLADORA (115 X 1MM), Felemax — fila nueva
-- =====================================================================
--
-- No necesita ningún dato de conversión -- "ya en unidad de uso" (UND). Tal cual figura en la
-- cotización: $479,15. HIZA ya tiene precio para este mismo insumo ($2.605, desde 0058) -- Felemax
-- entra como segundo proveedor, no reemplaza nada.

insert into precios (insumo_id, corralon_id, valor, fecha_actualizacion)
select i.id, c.id, 479.15, '2026-09-06'
from insumos i, corralones c
where i.nombre = 'DISCOS DE CORTE PARA AMOLADORA (115 X 1MM)' and i.creador_usuario_id is null
  and c.nombre = 'Felemax'
  and not exists (select 1 from precios p where p.insumo_id = i.id and p.corralon_id = c.id);

-- =====================================================================
-- Verificación
-- =====================================================================

-- 1) Las 3 filas afectadas, para confirmar valor -- y que MEMBRANA tiene una sola fila de Felemax,
--    no dos.
select i.nombre as insumo, c.nombre as corralon, p.valor, p.fecha_actualizacion
from precios p
join insumos i on i.id = p.insumo_id
join corralones c on c.id = p.corralon_id
where c.nombre = 'Felemax'
  and i.nombre in (
    'MEMBRANA ASFÁLTICA 4MM GEOTEXTIL',
    'CINTA DE ENMASCARAR 24MM',
    'DISCOS DE CORTE PARA AMOLADORA (115 X 1MM)'
  )
order by i.nombre;

-- 2) Ningún insumo quedó con dos precios del mismo corralón (chequeo de siempre).
select insumo_id, corralon_id, count(*) as filas
from precios
group by insumo_id, corralon_id
having count(*) > 1;

-- 3) Total de precios -- tiene que ser 221 (219 después de 0069 + 2 filas nuevas; MEMBRANA no
--    suma fila, solo se actualiza).
select count(*) as total_precios from precios;
