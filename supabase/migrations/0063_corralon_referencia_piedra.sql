-- Resuelve el gap encontrado en 0062: PIEDRA ($70.000/m³) es un precio de referencia de mercado
-- que aportó Seba, no la cotización de ningún corralón real -- y `corralones`/`precios` no tienen
-- ninguna columna opcional para modelar "sin vendedor detrás" (mismo motivo por el que 0058 falló
-- la primera vez con `corralones.lat` NOT NULL).
--
-- Se crea un corralón nuevo, "Cantera privada (referencia)", para colgar precios de este tipo. El
-- "(referencia)" en el nombre es a propósito, no cosmético: mientras `precios` no tenga una columna
-- que distinga un precio cotizado de uno de referencia (mismo gap ya anotado en
-- docs/confianza_precios_diseno.md para la sierra de 60 dientes -- PIEDRA es el segundo caso real),
-- el nombre del corralón es la ÚNICA señal visible en la app de que este número no vino de un
-- vendedor real. Si algún día se agrega esa columna (es_referencia o similar), este corralón sigue
-- siendo válido -- no hay que deshacer nada, solo dejaría de ser la única señal.
--
-- lat/lng: centro de Bariloche (mismos valores que ya se usaron para SB Maderas en 0058, que
-- tampoco tenía dirección puntual en su cotización) -- no es un error de copiado, es el mismo
-- criterio "sin dirección real, centro de la ciudad" aplicado dos veces.
--
-- Depende de 0062 (unidades corregidas) ya aplicada -- PIEDRA tiene que estar en M3 antes de este
-- INSERT, si no el precio quedaría atribuido a un insumo todavía declarado en M2.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor), después de 0062. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

-- =====================================================================
-- Corralón nuevo
-- =====================================================================

insert into corralones (nombre, ciudad, lat, lng, es_capital, usuario_id)
select 'Cantera privada (referencia)', 'Bariloche', -41.1335, -71.3103, false, null
where not exists (
  select 1 from corralones where nombre = 'Cantera privada (referencia)'
);

-- =====================================================================
-- Precio de PIEDRA — SIN IVA, a diferencia de los 126 ya cargados (0057-0061, todos con IVA)
-- =====================================================================
--
-- Decisión explícita de Seba, tomada sabiendo la consecuencia: PIEDRA queda ~21% por debajo del
-- resto del catálogo en términos comparables, no porque sea más barata sino porque está medida en
-- otra base impositiva. No sale de ninguna cotización -- es conocimiento de mercado de Seba, por
-- eso el corralón es "(referencia)" y no un vendedor real.
--
-- No se atribuye a Sólido: su presupuesto complementario cotizó "piedra partida" a $95.000 + IVA,
-- un producto y una base distintos (piedra partida vs. canto rodado, con IVA vs. sin IVA) -- cargar
-- ese número acá sería mezclar dos cosas que no son la misma. Por decisión de Seba de dejar los
-- áridos de ese complementario afuera, ese precio de Sólido queda sin cargar en ningún lado.
--
-- fecha_actualizacion: 05/09/2026 -- fecha en que Seba estableció este valor de referencia (no hay
-- una cotización con fecha propia detrás, a diferencia del resto de la carga).

insert into precios (insumo_id, corralon_id, valor, fecha_actualizacion)
select i.id, c.id, 70000, '2026-09-05'
from insumos i, corralones c
where i.nombre = 'PIEDRA' and i.creador_usuario_id is null
  and c.nombre = 'Cantera privada (referencia)';

-- =====================================================================
-- Verificación
-- =====================================================================

-- 1) El corralón nuevo existe, con coordenadas (ninguna en null -- ver el fallo real que tuvo 0058
--    la primera vez por esto).
select nombre, ciudad, lat, lng, es_capital from corralones where nombre = 'Cantera privada (referencia)';

-- 2) Exactamente 1 fila de precio para PIEDRA, atribuida al corralón de referencia.
select i.nombre as insumo, c.nombre as corralon, p.valor, p.fecha_actualizacion
from precios p
join insumos i on i.id = p.insumo_id
join corralones c on c.id = p.corralon_id
where i.nombre = 'PIEDRA';

-- 3) calcular_precio_promedio_insumo ya funciona para PIEDRA con un solo corralón detrás
--    (cantidad_corralones = 1, promedio = minimo = maximo = 70000).
select * from calcular_precio_promedio_insumo(
  (select id from insumos where nombre = 'PIEDRA' and creador_usuario_id is null)
);
