-- Limpieza de los 8 corralones duplicados que 0058 ya había marcado como pendiente ("Corralon del
-- Valle x4, Materiales Neuquen Capital x4... esa limpieza sigue pendiente, requiere correr antes
-- las 3 queries de verificación de referencias en precios/obra_insumo_precios para elegir
-- sobreviviente sin perder datos, mismo criterio que 0049 con Hierro del 12mm"). Deberían quedar 6
-- corralones en total (Sólido, HIZA, Felemax, SB Maderas, Casa Palm, Cantera privada [referencia]),
-- no 14.
--
-- `corralones`/`precios`/`obra_insumo_precios` no tienen su CREATE TABLE en supabase/migrations/
-- (son 3 de las 6 tablas del bloque "proveedores" creadas fuera del flujo de migraciones, ver
-- CLAUDE.md) -- no se puede confirmar desde el repo si el FK de precios.corralon_id tiene ON
-- DELETE CASCADE o RESTRICT. Por eso esta migración NO confía en eso: reasigna/limpia
-- precios y obra_insumo_precios A MANO antes de borrar los corralones, sin importar qué haga el FK
-- por su cuenta -- mismo criterio "defensivo, cuesta cero" que ya usó 0049.
--
-- Sin nombres hardcodeados a propósito -- no hace falta saber si el nombre real lleva tilde,
-- "Capital", u otra variante exacta: cualquier `nombre` de `corralones` que aparezca más de una vez
-- se trata como duplicado. El sobreviviente por grupo es el de `id` menor (orden de texto del uuid,
-- arbitrario pero determinístico) -- no hace falta que sea "el que tiene más datos", porque el paso
-- 3 le reasigna TODO lo que cuelgue de cualquiera de los otros duplicados igual, gane o pierda el
-- sorteo del id. Corre igual de bien si termina habiendo un tercer nombre duplicado que hoy no se
-- identificó a mano.
--
-- CORRECCIÓN sobre el primer intento: ese usaba una tabla temporal creada en una sentencia y leída
-- en las siguientes -- falló con "relation does not exist" porque el SQL Editor no garantiza que
-- todas las sentencias de un mismo pegado corran en la misma sesión/conexión. Esta versión no
-- depende de nada compartido entre sentencias: cada UPDATE/DELETE resuelve el sobreviviente con su
-- propia subconsulta inline, autocontenida.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

-- =====================================================================
-- Paso 1 -- diagnóstico: cuánto cuelga de cada duplicado, ANTES de tocar nada
-- =====================================================================
--
-- Corré esto primero y mirá el resultado -- si algún duplicado tiene precios/obra_insumo_precios
-- con valores REALES (no ceros en todos lados), tené en cuenta que el paso 3 los va a mover al
-- sobreviviente de su grupo igual, sin perder nada, sin importar cuál gane el sorteo del id.

select
  c.id,
  c.nombre,
  c.lat,
  c.lng,
  (select count(*) from precios p where p.corralon_id = c.id) as precios_colgando,
  (select count(*) from obra_insumo_precios o where o.corralon_id = c.id) as obra_insumo_precios_colgando
from corralones c
where c.nombre in (select nombre from corralones group by nombre having count(*) > 1)
order by c.nombre, precios_colgando desc, obra_insumo_precios_colgando desc;

-- =====================================================================
-- Paso 2 -- reasignar precios de los duplicados al sobreviviente (id menor) de su grupo
-- =====================================================================

update precios p
set corralon_id = can.canonico_id
from (
  select nombre, min(id::text)::uuid as canonico_id
  from corralones
  group by nombre
  having count(*) > 1
) can
join corralones dup on dup.nombre = can.nombre
where p.corralon_id = dup.id
  and dup.id <> can.canonico_id;

-- =====================================================================
-- Paso 3 -- reasignar obra_insumo_precios igual
-- =====================================================================

update obra_insumo_precios o
set corralon_id = can.canonico_id
from (
  select nombre, min(id::text)::uuid as canonico_id
  from corralones
  group by nombre
  having count(*) > 1
) can
join corralones dup on dup.nombre = can.nombre
where o.corralon_id = dup.id
  and dup.id <> can.canonico_id;

-- =====================================================================
-- Paso 4 -- deduplicar precios que hayan quedado con (insumo_id, corralon_id) repetido tras la
-- reasignación -- mismo patrón ya usado en 0068 (promedia y se queda con una sola fila).
-- Actúa sobre TODA la tabla, no solo sobre lo tocado en los pasos 2/3: es un no-op para cualquier
-- (insumo_id, corralon_id) que ya era único, así que no hay riesgo de tocar datos ajenos a esta
-- limpieza.
-- =====================================================================

with clasificado as (
  select
    id, insumo_id, corralon_id,
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
  select
    id, insumo_id, corralon_id,
    row_number() over (partition by insumo_id, corralon_id order by fecha_actualizacion desc, id) as posicion,
    count(*) over (partition by insumo_id, corralon_id) as total_filas
  from precios
)
delete from precios p
using clasificado c
where p.id = c.id and c.posicion > 1 and c.total_filas > 1;

-- =====================================================================
-- Paso 5 -- borrar los corralones duplicados, ya sin precios/obra_insumo_precios colgando
-- =====================================================================

delete from corralones c
using (
  select nombre, min(id::text)::uuid as canonico_id
  from corralones
  group by nombre
  having count(*) > 1
) can
where c.nombre = can.nombre
  and c.id <> can.canonico_id;

-- =====================================================================
-- Verificación
-- =====================================================================

-- 1) Tienen que quedar 6 corralones -- si da otro número, había más nombres duplicados de los que
--    se identificaron a mano, o algún nombre "único" en realidad tenía variantes (con/sin tilde,
--    con/sin "Capital") que este script no agrupó porque el texto no era IDÉNTICO.
select count(*) as total_corralones from corralones;

-- 2) Listado final, para confirmar a simple vista que son los 6 esperados.
select nombre, ciudad, lat, lng from corralones order by nombre;

-- 3) Ningún insumo con dos precios del mismo corralón (chequeo de siempre, tiene que dar 0 filas).
select insumo_id, corralon_id, count(*) as filas
from precios
group by insumo_id, corralon_id
having count(*) > 1;

-- 4) Total de precios -- no debería haber bajado salvo por los que el paso 4 promedió/fusionó
--    (informativo, comparar con el conteo de antes de correr esta migración).
select count(*) as total_precios from precios;
