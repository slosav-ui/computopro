-- Dos correcciones sobre 0066, encontradas al verificar el resultado real en producción.
--
-- =====================================================================
-- Parte 1 — ENDUIDO PLÁSTICO INTERIOR (PLANCHADO TOTAL): por qué no se absorbió
-- =====================================================================
--
-- Causa encontrada: SÍ tenía precio (Felemax, $4.174,8285, cargado en 0058) -- lo mismo que el
-- caso de CHAPA de 0066, pero este no se detectó al escribir esa migración. El motivo concreto:
-- se verificó "¿tiene precio el absorbido?" con un grep de terminal sobre el nombre con acento
-- (ENDUIDO PLÁSTICO), y ese grep no matcheó por un problema de codificación en esta consola --
-- mismo tipo de falso negativo que ya había pasado (y se había corregido a tiempo) con AGUARRÁS y
-- ALFAJÍAS al auditar 0058. Acá no se repitió esa segunda verificación antes de escribir 0066, así
-- que pasó -- MASILLA TIPO ENDUIDO (sobreviviente) reasignó bien las composiciones (por eso el
-- huérfanos dio 0), pero el `not exists (select 1 from precios where insumo_id = ...)` del DELETE
-- de 0066 encontró la fila de Felemax todavía apuntando al insumo viejo y, correctamente, se negó
-- a borrarlo -- el chequeo defensivo funcionó como está pensado, evitó perder ese precio.
--
-- Se reasigna el precio de Felemax a MASILLA TIPO ENDUIDO (que ya tiene el de HIZA, 0065) -- dos
-- corralones distintos, sin colisión, nada que promediar acá -- y recién después se borra el
-- insumo viejo, mismo criterio de siempre.

update precios p
set insumo_id = isup.id
from insumos isup, insumos iabs
where isup.nombre = 'MASILLA TIPO ENDUIDO' and isup.creador_usuario_id is null
  and iabs.nombre = 'ENDUIDO PLÁSTICO INTERIOR (PLANCHADO TOTAL)' and iabs.creador_usuario_id is null
  and p.insumo_id = iabs.id;

delete from insumos
where nombre = 'ENDUIDO PLÁSTICO INTERIOR (PLANCHADO TOTAL)'
  and creador_usuario_id is null
  and not exists (select 1 from apu_composicion_items where insumo_id = insumos.id)
  and not exists (select 1 from precios where insumo_id = insumos.id)
  and not exists (select 1 from obra_insumo_precios where insumo_id = insumos.id);

-- =====================================================================
-- Parte 2 — Precios duplicados: mismo corralón, mismo insumo, dos filas
-- =====================================================================
--
-- No se reconstruyen los 6 casos a mano contra los archivos de origen -- ya hubo un miss (Parte 1
-- de este mismo archivo) confiando en verificación estática en vez de en la base real. La consulta
-- de abajo lista los duplicados reales tal como están en este momento, y el fix que sigue los
-- promedia de forma genérica (agrupando por insumo_id + corralon_id, sin importar cuántas filas
-- caigan en cada grupo) -- mismo criterio ya usado antes: promediar valor, y de fecha_actualizacion
-- se toma la más reciente de las que se promedian, no un valor arbitrario.

-- Verificación PREVIA — correr esto primero para ver los 6 casos reales antes de tocar nada.
select i.nombre as insumo, c.nombre as corralon, count(*) as filas,
       array_agg(p.valor order by p.fecha_actualizacion) as valores,
       array_agg(p.fecha_actualizacion order by p.fecha_actualizacion) as fechas
from precios p
join insumos i on i.id = p.insumo_id
join corralones c on c.id = p.corralon_id
group by i.nombre, c.nombre
having count(*) > 1
order by i.nombre;

-- Fix: conserva una sola fila por (insumo_id, corralon_id) -- la de fecha_actualizacion más
-- reciente (empate resuelto por id, que sí admite ORDER BY aunque no admita MIN() -- corregido
-- tras el error 42883 de la primera versión de este archivo, min(uuid) no existe en Postgres),
-- con su valor reemplazado por el promedio de todas las filas del grupo.
--
-- row_number() en vez de min(id): además de evitar el error, dejalo elegir la fila más reciente
-- por fecha en vez de una fila cualquiera -- mismo criterio que ya se había propuesto, ahora
-- expresado correctamente.
with clasificado as (
  select id, insumo_id, corralon_id,
         row_number() over (partition by insumo_id, corralon_id order by fecha_actualizacion desc, id) as posicion,
         avg(valor) over (partition by insumo_id, corralon_id) as promedio,
         max(fecha_actualizacion) over (partition by insumo_id, corralon_id) as fecha_reciente,
         count(*) over (partition by insumo_id, corralon_id) as total_filas
  from precios
)
update precios p
set valor = c.promedio, fecha_actualizacion = c.fecha_reciente
from clasificado c
where p.id = c.id and c.posicion = 1 and c.total_filas > 1;

with clasificado as (
  select id, insumo_id, corralon_id,
         row_number() over (partition by insumo_id, corralon_id order by fecha_actualizacion desc, id) as posicion,
         count(*) over (partition by insumo_id, corralon_id) as total_filas
  from precios
)
delete from precios p
using clasificado c
where p.id = c.id and c.posicion > 1 and c.total_filas > 1;

-- =====================================================================
-- Verificación
-- =====================================================================

-- 1) ENDUIDO PLÁSTICO INTERIOR (PLANCHADO TOTAL) ya no existe.
select nombre from insumos where nombre = 'ENDUIDO PLÁSTICO INTERIOR (PLANCHADO TOTAL)';
-- esperado: 0 filas.

-- 2) MASILLA TIPO ENDUIDO tiene los dos precios (HIZA y Felemax), sin duplicar.
select c.nombre as corralon, p.valor
from precios p
join insumos i on i.id = p.insumo_id
join corralones c on c.id = p.corralon_id
where i.nombre = 'MASILLA TIPO ENDUIDO' and i.creador_usuario_id is null
order by c.nombre;

-- 3) Cero duplicados de (insumo_id, corralon_id) en toda la tabla.
select insumo_id, corralon_id, count(*) as filas
from precios
group by insumo_id, corralon_id
having count(*) > 1;
-- esperado: 0 filas.

-- 4) Conteo final de insumos -- 168 (el de después de 0066) menos 1 (ENDUIDO) = 167.
select count(*) as total_insumos from insumos;

-- 5) apu_composicion_items no cambió por nada de este archivo (ni la Parte 1 ni la Parte 2 tocan
--    esa tabla) -- tiene que seguir dando 774, el número que Seba ya confirmó como correcto
--    (774 y no 770 porque 0064 sumó líneas al reemplazar hormigón de pendiente/carpeta por sus
--    recetas reales -- no es un problema de esta migración).
select count(*) as total_apu_composicion_items from apu_composicion_items;
