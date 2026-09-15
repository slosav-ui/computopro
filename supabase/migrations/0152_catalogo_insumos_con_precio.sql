-- =====================================================================
-- 0152 — El catálogo de insumos con su precio de referencia, legible por cualquier usuario
-- =====================================================================
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.
--
-- =====================================================================
-- PARA QUÉ
-- =====================================================================
--
-- La solapa Mat y MO, cuando la obra todavía no tiene insumos, muestra el catálogo en gris: los
-- materiales con su precio de referencia y la mano de obra con su valor hora. Criterio de Seba
-- (2026-09-15):
--
--     "Eso es lo que muestra el potencial de esa solapa: el que la abre tiene que ver que la app
--      trae precios reales de la zona."
--
-- Ver docs/carpetas_importado_y_catalogo_diseno_datos.md §9.
--
-- =====================================================================
-- POR QUÉ HACE FALTA UNA FUNCIÓN Y NO ALCANZA CON CONSULTAR LA TABLA
-- =====================================================================
--
-- `precios_select` (0013) es `using (is_corralon_owner(corralon_id))`: **cada corralón ve sus
-- propios precios y nada más.** Un PRO consultando `precios` desde la app recibe cero filas, no un
-- error -- que es el modo de falla peor, porque parece que no hay precios cargados.
--
-- Esa RLS está bien y no se toca. Lo que se agrega es la única lectura agregada que la app
-- necesita, por una función `security definer`, igual que ya lo resuelve
-- `consolidado_insumos_obra` (0032) para los insumos de una obra.
--
-- =====================================================================
-- QUÉ EXPONE, Y QUÉ NO
-- =====================================================================
--
-- **Promedio y cantidad de precios. Nunca el precio de un corralón puntual, ni mínimo, ni máximo.**
--
-- No es una exposición nueva: `consolidado_insumos_obra` (0032) ya devuelve `avg(valor)` a
-- cualquier miembro de una obra. Lo que cambia es el alcance -- de "los insumos de tu obra" a "el
-- catálogo entero" -- y en la práctica la diferencia es chica, porque cualquiera puede crear una
-- obra, tildar partidas y llegar al mismo promedio por el camino largo.
--
-- **Lo que sí conviene tener presente** (está anotado en `docs/proveedores_canje_diseno.md`): con
-- pocos proveedores cargados, un promedio y la cantidad de precios permiten despejar el precio
-- ajeno si uno conoce el propio. Por eso se devuelve `cantidad_precios` y NO min/max: el conteo
-- sirve para decir "promedio de 3 corralones" -- que es información útil y honesta sobre la
-- confianza del dato -- sin agregar una segunda ecuación que haga el despeje más fácil.
--
-- Si algún día hay corralones reales cargando precios y esto pasa a molestar, la salida es un piso
-- de N proveedores para mostrar el promedio, no sacar la función.

create or replace function catalogo_insumos_con_precio()
returns table(
  insumo_id uuid,
  nombre text,
  unidad text,
  tipo text,
  precio_promedio numeric,
  cantidad_precios int
)
language sql
security definer
set search_path = public
stable as $$
  select
    ins.id,
    ins.nombre,
    ins.unidad,
    ins.tipo,
    -- round a 2 acá y no en Dart: es el criterio de la 0149 (el redondeo va en la base, la pantalla
    -- no tiene que acordarse). Sin precios cargados da null, que es distinto de 0 y la app lo
    -- muestra como "sin precio" en vez de como gratis.
    round(avg(pr.valor), 2) as precio_promedio,
    count(pr.valor)::int as cantidad_precios
  from insumos ins
  -- left join: un insumo sin ningún precio cargado tiene que aparecer igual. Es parte de lo que la
  -- pantalla muestra -- el catálogo completo -- y esconderlo daría una idea equivocada del tamaño.
  left join precios pr on pr.insumo_id = ins.id
  -- Fail-closed, mismo criterio que el resto: sin sesión no devuelve nada. `security definer`
  -- bypassa la RLS de `precios`, así que este chequeo es la única puerta que queda.
  where auth.uid() is not null
  group by ins.id, ins.nombre, ins.unidad, ins.tipo
  order by ins.tipo, ins.nombre;
$$;

grant execute on function catalogo_insumos_con_precio() to authenticated;
revoke execute on function catalogo_insumos_con_precio() from public, anon;


-- =====================================================================
-- Verificación
-- =====================================================================
--
-- 1) Como usuario autenticado (no dueño de ningún corralón), tiene que devolver el catálogo entero
--    CON precios -- que es justamente lo que una consulta directa a `precios` no puede:
--
--      select count(*) as insumos,
--             count(*) filter (where precio_promedio is not null) as con_precio
--      from catalogo_insumos_con_precio();
--
--    Al momento de escribir esto el catálogo tiene 174 insumos y 221 precios cargados
--    (ver memoria "carga_precios_catalogo_completo"), con 0 insumos sin precio.
--
-- 2) El promedio tiene que coincidir con el que ya calcula el consolidado de una obra para el mismo
--    insumo, si esa obra no tiene precio manual cargado para él (`obra_insumo_precios`):
--
--      select c.nombre, c.precio_promedio, o.precio, o.origen
--      from catalogo_insumos_con_precio() c
--      join consolidado_insumos_obra('<obra_id>') o on o.insumo_id = c.insumo_id
--      where o.origen = 'automatico';
--      -- precio_promedio y precio tienen que dar lo mismo
--
-- 3) `anon` no puede ejecutarla:
--
--      set role anon;  select * from catalogo_insumos_con_precio();  -- permiso denegado
--      reset role;
--
-- 4) Ningún precio con más de 2 decimales:
--
--      select * from catalogo_insumos_con_precio()
--      where precio_promedio <> round(precio_promedio, 2);   -- 0 filas
