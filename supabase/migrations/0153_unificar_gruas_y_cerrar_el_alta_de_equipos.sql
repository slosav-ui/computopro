-- =====================================================================
-- 0153 — Unifica las tres grúas y cierra el agujero por el que entraron
-- =====================================================================
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.
--
-- =====================================================================
-- QUÉ PASÓ
-- =====================================================================
--
-- Seba vio en Mat y MO tres insumos para la misma cosa: GRÚA, GRÚA DE IZAJE y GRÚAS. Los tres
-- equipos, los tres sin precio, ninguno usado en ningún APU.
--
-- **Entraron por el alta de equipos, y no por un bug.** Desde la app solo se pueden crear equipos
-- (`insumos_repository.dart` solo hace `select` sobre `insumos`; el único camino de alta es
-- `buscar_o_crear_equipo_apu`, 0074). Esa función define la identidad de un equipo por el nombre,
-- comparado con `upper(trim(...))` -- exacto. Los tres nombres son distintos, así que hizo
-- exactamente lo que dice hacer y creó tres filas.
--
-- **El agujero real está en el buscador que tenía que evitarlo**, y son dos:
--
--   1. `ilike '%texto%'` NO ignora acentos. Escribir "grua" no encuentra "GRÚA" -- en un teléfono,
--      que es donde se usa, esto es lo normal. El usuario ve un buscador vacío y crea uno nuevo.
--      **Este es el que importa.**
--   2. La subcadena va en un solo sentido: escribir "grúas" tampoco encuentra "GRÚA", porque
--      'GRÚA' no contiene 'GRÚAS'.
--
-- El catálogo de materiales está sano: Seba corrió la verificación y **no hay ningún material sin
-- precio**. Los únicos sin precio son estas tres grúas y las 5 categorías de mano de obra, que no
-- tienen precio acá porque su valor sale del convenio con las cargas sociales
-- (`docs/costo_mano_de_obra_decisiones.md`). Queda descartada la sospecha de que la `0084` -- que
-- borró los precios de dos corralones de la carga vieja de Gemini -- hubiera dejado insumos
-- huérfanos.
--
-- =====================================================================
-- LO QUE NO SE HACE, Y POR QUÉ
-- =====================================================================
--
-- **No se normalizan los plurales en la función de alta.** Sería fácil hacer que "GRÚAS" encuentre
-- "GRÚA", y está descartado a propósito -- decisión de Seba:
--
--     "Fusionar en silencio es peor que mostrar los parecidos y que elija el usuario."
--
-- Un merge automático acierta con grúa/grúas y se equivoca con TABLA/TABLAS o CAÑO/CAÑOS, y el día
-- que se equivoca nadie se entera. La normalización que sí se aplica es **solo de acentos, mayúsculas
-- y espacios de borde** -- tres formas de escribir el mismo texto, no dos cosas parecidas.
--
-- =====================================================================
-- EL ORDEN DE ESTE ARCHIVO NO ES NEGOCIABLE
-- =====================================================================
--
-- La sección 3 crea un índice único sobre el nombre normalizado. **Si corriera antes de la sección
-- 1, fallaría**: hoy hay tres grúas que normalizan a claves distintas, pero cualquier par que
-- difiera solo en acento o mayúscula reventaría la creación del índice. Unificar primero, cerrar
-- después. Es la razón por la que la limpieza y la prevención van en la misma migración y no en
-- dos.

-- =====================================================================
-- Sección 1 — unificar las grúas
-- =====================================================================
--
-- **Sin nombres hardcodeados**, mismo criterio que la `0083` con los corralones duplicados: no hace
-- falta saber si el nombre real lleva tilde, va en mayúsculas o tiene un espacio de más. Se buscan
-- los equipos cuyo nombre normalizado contiene GRUA, y sobrevive el que normaliza exactamente a
-- 'GRUA'.
--
-- Decisión de Seba sobre cuál sobrevive: **"grúa" a secas**. *"De izaje no agrega nada, toda grúa
-- iza. Si mañana hay que distinguir una torre de una hidráulica, se crean con esos nombres."*
--
-- Se reasigna todo antes de borrar, igual que la `0066`. Las tres consultas de reasignación son
-- no-ops con los datos de hoy (ninguna grúa tiene precio ni uso en APU) y se escriben igual: son la
-- diferencia entre una migración que funciona hoy y una que funciona si mañana alguien la corre con
-- otros datos, o si este archivo se reusa de plantilla para el próximo grupo de duplicados.

do $seccion1$
declare
  v_sobreviviente uuid;
  v_absorbidos uuid[];
  v_n int;
begin
  -- El sobreviviente: el que normaliza exactamente a 'GRUA'.
  select id into v_sobreviviente
  from insumos
  where tipo = 'equipo'
    and translate(upper(trim(nombre)), 'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNAEIOUUN') = 'GRUA'
  limit 1;

  if v_sobreviviente is null then
    -- Fail-closed y no "elijo cualquiera": si el nombre genérico no existe, algo cambió desde el
    -- diagnóstico y borrar a ciegas se llevaría puesto el único que quedaba.
    raise exception 'No hay ningún equipo cuyo nombre normalice a GRUA. Revisá el catálogo antes de correr esto.';
  end if;

  select array_agg(id) into v_absorbidos
  from insumos
  where tipo = 'equipo'
    and id <> v_sobreviviente
    and translate(upper(trim(nombre)), 'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNAEIOUUN') like '%GRUA%';

  if v_absorbidos is null then
    raise notice 'Sección 1 -- no hay grúas duplicadas: ya estaba unificado.';
    return;
  end if;

  raise notice 'Sección 1 -- sobreviviente: %. Absorbidos: %.', v_sobreviviente, array_length(v_absorbidos, 1);

  -- 1a) los usos en APU. `update` y no `delete`: si alguna partida usaba "GRÚA DE IZAJE", tiene que
  --     seguir usando una grúa, no quedarse sin el equipo.
  --
  --     El `where not exists` evita el caso en que una misma composición ya tenga las dos: ahí
  --     reasignar dejaría la grúa dos veces en la misma receta, sumando su rendimiento dos veces.
  --     Esas filas se borran en 1b en vez de reasignarse.
  update apu_composicion_items aci
  set insumo_id = v_sobreviviente
  where aci.insumo_id = any(v_absorbidos)
    and not exists (
      select 1 from apu_composicion_items otro
      where otro.apu_composicion_id = aci.apu_composicion_id
        and otro.insumo_id = v_sobreviviente
    );
  get diagnostics v_n = row_count;
  raise notice '  usos en APU reasignados: %', v_n;

  -- 1b) las que quedaron porque su composición ya tenía la grúa sobreviviente.
  delete from apu_composicion_items where insumo_id = any(v_absorbidos);
  get diagnostics v_n = row_count;
  if v_n > 0 then
    raise notice '  usos en APU descartados por duplicación dentro de la misma receta: %', v_n;
  end if;

  -- 1c) precios de corralón. Hoy ninguna grúa tiene, pero el criterio de la 0066 es que el
  --     sobreviviente se queda con TODAS las filas de `precios` de los absorbidos, como proveedores
  --     distintos -- no se pierde ninguna cotización.
  update precios set insumo_id = v_sobreviviente where insumo_id = any(v_absorbidos);
  get diagnostics v_n = row_count;
  if v_n > 0 then
    raise notice '  precios de corralón reasignados: %', v_n;
  end if;

  -- 1d) precios por obra. **Este es el que puede chocar**: `obra_insumo_precios` tiene una fila por
  --     (obra, insumo), así que si una obra le puso precio a la grúa Y a la grúa de izaje, el
  --     update violaría la unicidad. Se reasigna solo donde no hay conflicto y se descarta el resto
  --     -- el precio que sobrevive es el que la obra le puso al insumo que sobrevive.
  update obra_insumo_precios oip
  set insumo_id = v_sobreviviente
  where oip.insumo_id = any(v_absorbidos)
    and not exists (
      select 1 from obra_insumo_precios otro
      where otro.obra_id = oip.obra_id and otro.insumo_id = v_sobreviviente
    );
  get diagnostics v_n = row_count;
  if v_n > 0 then
    raise notice '  precios por obra reasignados: %', v_n;
  end if;

  delete from obra_insumo_precios where insumo_id = any(v_absorbidos);
  get diagnostics v_n = row_count;
  if v_n > 0 then
    raise notice '  precios por obra descartados (la obra ya tenía uno para la grúa): %', v_n;
  end if;

  -- 1e) recién ahora.
  delete from insumos where id = any(v_absorbidos);
  get diagnostics v_n = row_count;
  raise notice '  insumos borrados: %', v_n;
end;
$seccion1$;


-- =====================================================================
-- Sección 2 — una sola definición de "el mismo nombre"
-- =====================================================================
--
-- Hasta ahora la normalización estaba escrita a mano en cada lugar que la necesitaba, y eran dos
-- criterios distintos: `upper(trim(...))` en el alta y `ilike '%...%'` en el buscador. **De esa
-- divergencia salieron las tres grúas.** Acá pasa a haber una sola definición, y las tres piezas
-- de abajo la usan.
--
-- `immutable` es obligatorio: sin eso no se puede indexar por esta expresión (sección 3). Y tiene
-- una consecuencia que conviene tener presente -- **si algún día se cambia el cuerpo de esta
-- función, el índice de la sección 3 queda corrupto en silencio**, porque Postgres no reindexa
-- solo. Cambiarla es siempre `create or replace` + `reindex index insumos_equipo_nombre_unique`.
--
-- Normaliza tres cosas y ninguna más: mayúsculas, acentos y espacios (de borde y repetidos). Son
-- tres formas de tipear el mismo texto. Plurales y sinónimos quedan afuera a propósito (ver la
-- cabecera).

create or replace function insumo_nombre_normalizado(p_nombre text)
returns text
language sql
immutable
strict
set search_path = public
as $fn$
  select regexp_replace(
           translate(upper(trim(p_nombre)), 'ÁÉÍÓÚÜÑÀÈÌÒÙÂÊÎÔÛ', 'AEIOUUNAEIOUAEIOU'),
           '\s+', ' ', 'g'
         );
$fn$;

comment on function insumo_nombre_normalizado(text) is
  'Forma canonica de un nombre de insumo: mayusculas, sin acentos, sin espacios repetidos ni de '
  'borde. Unica definicion de "el mismo nombre" -- la usan el indice unico de equipos, '
  'buscar_o_crear_equipo_apu y buscar_insumos_por_tipo (0153). IMMUTABLE porque se indexa: '
  'cambiarla obliga a reindexar insumos_equipo_nombre_unique.';


-- =====================================================================
-- Sección 3 — la red de seguridad: dos equipos no pueden llamarse igual
-- =====================================================================
--
-- Parcial sobre `tipo = 'equipo'` y no sobre toda la tabla: los materiales vienen sembrados y no se
-- crean desde la app, así que acá no hay nada que prevenir -- y un índice único sobre los 174
-- podría chocar con algún par histórico que hoy convive a propósito.
--
-- Es la red, no la barrera principal. La barrera es que el buscador encuentre (sección 5); esto
-- existe para el día que la UI falle o alguien llame la RPC por otro camino.

create unique index insumos_equipo_nombre_unique
  on insumos (insumo_nombre_normalizado(nombre))
  where tipo = 'equipo';


-- =====================================================================
-- Sección 4 — el alta usa la misma definición
-- =====================================================================
--
-- **Sin esto, la sección 3 rompe el alta en vez de protegerla.** Hoy la función busca por
-- `upper(trim(...))`: un usuario que escribe "GRUA" sin acento no encuentra "GRÚA", intenta crear,
-- y con el índice nuevo recibiría un error de unicidad en la cara. Con la misma normalización en
-- los dos lados, encuentra la que ya existe y la devuelve -- que es lo que la función promete.
--
-- Cambios respecto de la versión de la 0076: solo la normalización. El pragma
-- `#variable_conflict use_column`, el `security invoker`, los chequeos de nombre vacío y de unidad,
-- y el `categoria`/`tipo` = 'equipo' quedan igual.
--
-- **Se guarda `trim(p_nombre)` tal como lo escribió el usuario**, no el normalizado: la
-- normalización es para comparar, no para mostrar. Nadie quiere ver "GRUA" sin tilde en la pantalla
-- porque el sistema decidió que así se compara mejor.

create or replace function buscar_o_crear_equipo_apu(p_nombre text, p_unidad text)
returns table(id uuid, nombre text, unidad text)
language plpgsql security invoker set search_path = public as $fn$
#variable_conflict use_column
declare
  v_id uuid;
  v_nombre_normalizado text := insumo_nombre_normalizado(p_nombre);
begin
  if v_nombre_normalizado is null or v_nombre_normalizado = '' then
    raise exception 'El nombre del equipo no puede estar vacío';
  end if;
  if p_unidad not in ('hs', 'dia') then
    raise exception 'Unidad inválida para un equipo: % (tiene que ser hs o dia)', p_unidad;
  end if;

  select ins.id into v_id
  from insumos ins
  where ins.tipo = 'equipo'
    and insumo_nombre_normalizado(ins.nombre) = v_nombre_normalizado
  limit 1;

  if v_id is null then
    insert into insumos (nombre, unidad, categoria, tipo, creador_usuario_id)
    values (trim(p_nombre), p_unidad, 'equipo', 'equipo', auth.uid())
    returning insumos.id into v_id;
  end if;

  return query select ins.id, ins.nombre, ins.unidad from insumos ins where ins.id = v_id;
end;
$fn$;

grant execute on function buscar_o_crear_equipo_apu(text, text) to authenticated;


-- =====================================================================
-- Sección 5 — el buscador encuentra, que es el arreglo de fondo
-- =====================================================================
--
-- Reemplaza el `ilike '%texto%'` que hacía el Dart a mano contra la tabla. Dos cambios:
--
--   1. **Compara sin acentos.** Es el agujero que creó las tres grúas: hoy escribís "grua" y no
--      encuentra nada, así que creás una nueva.
--
--   2. **La subcadena va en los dos sentidos.** Antes solo encontraba si el nombre del catálogo
--      contenía lo tipeado; ahora también si lo tipeado contiene al nombre del catálogo. Con eso
--      "GRÚAS" encuentra "GRÚA" y el usuario elige la que existe en vez de crear otra.
--
--      **No contradice la decisión de no normalizar plurales.** Son cosas distintas: esto es una
--      búsqueda, donde de más no hace daño -- el usuario ve la lista y elige. Lo que quedó
--      descartado es que el ALTA fusione sola dos nombres distintos, que es donde equivocarse sale
--      caro y nadie se entera.
--
-- `security invoker`: no hay nada que bypassar, `insumos_select` (0013) ya está abierto a cualquier
-- autenticado. Sin sesión devuelve 0 filas por esa misma RLS, sin necesidad de chequearlo acá.

create or replace function buscar_insumos_por_tipo(p_texto text, p_tipo text)
returns table(id uuid, nombre text, unidad text)
language sql
security invoker
stable
set search_path = public
as $fn$
  with q as (select insumo_nombre_normalizado(p_texto) as termino)
  select ins.id, ins.nombre, ins.unidad
  from insumos ins, q
  where ins.tipo = p_tipo
    and q.termino <> ''
    and (
      insumo_nombre_normalizado(ins.nombre) like '%' || q.termino || '%'
      or q.termino like '%' || insumo_nombre_normalizado(ins.nombre) || '%'
    )
  order by
    -- El que coincide exacto primero, después por nombre. Sin esto, buscar "GRÚA" con varias grúas
    -- cargadas puede dejar la exacta en el medio de la lista.
    (insumo_nombre_normalizado(ins.nombre) = q.termino) desc,
    ins.nombre
  limit 50;
$fn$;

grant execute on function buscar_insumos_por_tipo(text, text) to authenticated;
revoke execute on function buscar_insumos_por_tipo(text, text) from public, anon;


-- =====================================================================
-- Verificación
-- =====================================================================
--
-- ---- 1. quedó una sola grúa, y es la genérica
--
--   select id, nombre, unidad, tipo from insumos
--   where insumo_nombre_normalizado(nombre) like '%GRUA%';
--   -- una fila, nombre "Grúa" (o como estuviera escrita la que sobrevivió)
--
-- ---- 2. no se perdió nada en el camino
--
--   select count(*) from apu_composicion_items aci
--   left join insumos i on i.id = aci.insumo_id where i.id is null;   -- 0: ninguna receta quedó rota
--
--   select count(*) from precios p
--   left join insumos i on i.id = p.insumo_id where i.id is null;     -- 0
--
--   select count(*) from obra_insumo_precios o
--   left join insumos i on i.id = o.insumo_id where i.id is null;     -- 0
--
-- ---- 3. el catálogo sigue sano (era el estado confirmado antes de esta migración)
--
--   select i.nombre, i.tipo from insumos i
--   where not exists (select 1 from precios p where p.insumo_id = i.id)
--   order by i.tipo, i.nombre;
--   -- solo la grúa y las 5 categorías de mano de obra. Ningún material.
--
-- ---- 4. el alta ya no crea un duplicado por acento  **la prueba que más importa**
--
--   select * from buscar_o_crear_equipo_apu('GRUA', 'hs');   -- devuelve la que YA existe
--   select count(*) from insumos where tipo = 'equipo'
--     and insumo_nombre_normalizado(nombre) = 'GRUA';        -- sigue en 1
--
--   -- Antes de esta migración, esa llamada creaba una cuarta grúa.
--
-- ---- 5. el índice hace de red
--
--   insert into insumos (nombre, unidad, categoria, tipo, creador_usuario_id)
--   values ('  grúa  ', 'hs', 'equipo', 'equipo', auth.uid());
--   -- tiene que fallar por insumos_equipo_nombre_unique
--
-- ---- 6. el buscador encuentra en los dos sentidos y sin acentos
--
--   select * from buscar_insumos_por_tipo('grua', 'equipo');    -- encuentra la grúa
--   select * from buscar_insumos_por_tipo('gruas', 'equipo');   -- también
--   select * from buscar_insumos_por_tipo('', 'equipo');        -- 0 filas, no el catálogo entero
