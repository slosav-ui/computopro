-- =====================================================================
-- 0154 — Copiar un rubro de la carpeta de una obra a mi catálogo (tanda 6)
-- =====================================================================
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.
--
-- Tanda 6 de `docs/carpetas_importado_y_catalogo_diseno_datos.md` §6.1, dirección A.
-- **Leer esa sección antes de tocar esto**: acá está el cómo, allá el por qué.
--
-- =====================================================================
-- QUÉ HACE
-- =====================================================================
--
-- *"Si el usuario ve que le sirve siempre, tiene que poder quedárselo: importás, trabajás, y lo
-- bueno se queda."* (Seba)
--
-- **Es una copia, no una mudanza.** El original queda en la carpeta de la obra, intacto. Se
-- duplican el rubro y sus partidas con `obra_id = null` y `creador_usuario_id = auth.uid()`, o sea
-- en el catálogo personal de quien copia.
--
-- **`obra_subitems` no se toca.** El cómputo de la obra sigue apuntando a los ids originales, así
-- que **el monto de la obra no se mueve por copiar**. Es la propiedad que hace que esto sea seguro
-- de ofrecer: copiar nunca puede cambiar un número.
--
-- =====================================================================
-- POR QUÉ ESTA DIRECCIÓN ES LA SIMPLE
-- =====================================================================
--
-- Los rubros de una carpeta son siempre de precio manual -- los crea el importador o el alta a
-- mano, y las dos ramas nacen `usa_apu = false`. Así que acá no hay APU que arrastrar ni cómputo
-- que reacomodar: es un `insert` de rubro + N subítems y nada más.
--
-- La otra dirección (catálogo -> obra) es otra migración, la `0155`, y tiene dos nudos que esta no
-- tiene.

-- =====================================================================
-- Sección 1 — el helper de código libre
-- =====================================================================
--
-- Los índices de la `0151` son por carpeta, así que "libre" significa cosas distintas según a dónde
-- va la fila. Este helper resuelve un solo caso: **el catálogo personal de un usuario**
-- (`rubros_codigo_propio_unique (creador_usuario_id, codigo) where obra_id is null`).
--
-- **No choca contra los códigos oficiales**, y eso es a propósito: el índice del catálogo oficial es
-- otro (`where creador_usuario_id is null`). Un rubro propio "1" convive con TAREAS PRELIMINARES
-- sin problema -- en Cómputo el número que se ve es posicional, no el código.
--
-- Sufijo `-2`, `-3`... en vez de buscar el siguiente número: el código de un rubro propio es
-- interno (desde la `0027` nace siendo un uuid) y lo único que importa es que no choque. Inventar
-- un número nuevo daría la impresión de que significa algo.
--
-- Tope de 50 intentos: si alguien tiene 50 rubros con el mismo código, el problema no es este.

create or replace function siguiente_codigo_rubro_propio(p_codigo text, p_usuario_id uuid)
returns text
language plpgsql
stable
set search_path = public
as $fn$
declare
  v_candidato text := p_codigo;
  v_n int := 1;
begin
  while exists (
    select 1 from rubros r
    where r.obra_id is null
      and r.creador_usuario_id = p_usuario_id
      and r.codigo = v_candidato
  ) loop
    v_n := v_n + 1;
    if v_n > 50 then
      raise exception 'No se pudo encontrar un código libre para "%" en tu catálogo', p_codigo;
    end if;
    v_candidato := p_codigo || '-' || v_n::text;
  end loop;

  return v_candidato;
end;
$fn$;

grant execute on function siguiente_codigo_rubro_propio(text, uuid) to authenticated;


-- =====================================================================
-- Sección 2 — copiar_rubro_al_catalogo
-- =====================================================================
--
-- `security invoker`: no hace falta bypassar nada. Leer el rubro de la carpeta ya lo permite
-- `rubros_select` (0151) vía `is_obra_member`, y escribir en el catálogo personal lo permite
-- `rubros_insert` con `creador_usuario_id = auth.uid()`. **Que las políticas alcancen es la
-- verificación de que la operación es legítima** -- si hubiera que forzarla con `definer`, sería
-- señal de que alguien está copiando algo que no debería ver.
--
-- Devuelve el id del rubro nuevo y el código que le tocó, **para que la pantalla lo muestre**: si
-- hubo que renumerar, el usuario tiene que enterarse antes de buscar el rubro por un número que ya
-- no es. Nunca renumerar en silencio -- el número es lo que el usuario reconoce.

create or replace function copiar_rubro_al_catalogo(p_rubro_id uuid)
returns table(rubro_id uuid, codigo text, partidas int)
language plpgsql
security invoker
set search_path = public
as $fn$
#variable_conflict use_column
declare
  v_usuario uuid := auth.uid();
  v_origen record;
  v_codigo text;
  v_nuevo uuid;
  v_orden int;
  v_partidas int;
begin
  if v_usuario is null then
    raise exception 'Sin sesión';
  end if;

  select r.* into v_origen from rubros r where r.id = p_rubro_id;

  -- Si la RLS no lo deja ver, `v_origen` viene null: el mensaje es el mismo para "no existe" y para
  -- "no tenés acceso", a propósito -- distinguirlos le confirmaría a un extraño que el rubro existe.
  if v_origen.id is null then
    raise exception 'El rubro no existe o no tenés acceso';
  end if;

  if v_origen.obra_id is null then
    raise exception 'Ese rubro ya está en un catálogo, no en la carpeta de una obra';
  end if;

  v_codigo := siguiente_codigo_rubro_propio(v_origen.codigo, v_usuario);

  -- Al final del catálogo personal, no en medio de los oficiales: `orden` es el default que usa
  -- RubrosTab cuando la obra no tiene overrides, y un rubro adoptado no tiene por qué meterse
  -- entre los 20 del catálogo.
  select coalesce(max(r.orden), 100) + 1 into v_orden
  from rubros r
  where r.obra_id is null and r.creador_usuario_id = v_usuario;

  insert into rubros (codigo, nombre, orden, usa_apu, tipo_precio_manual, creador_usuario_id, obra_id)
  values (v_codigo, v_origen.nombre, v_orden, v_origen.usa_apu, v_origen.tipo_precio_manual, v_usuario, null)
  returning rubros.id into v_nuevo;

  -- Las partidas van con él: un rubro sin partidas no sirve de nada, y dejarlas atrás rompería la
  -- regla de coherencia de la 0151 (§4.2 del doc).
  --
  -- Sin renumerar: los subítems propios no tienen índice de unicidad (el de la 0016 es parcial
  -- sobre los oficiales), así que el código del origen entra tal cual. Que la partida conserve su
  -- número es justamente lo que hace reconocible al rubro copiado.
  insert into subitems (rubro_id, codigo, descripcion, unidad, creador_usuario_id, obra_id)
  select v_nuevo, s.codigo, s.descripcion, s.unidad, v_usuario, null
  from subitems s
  where s.rubro_id = p_rubro_id;

  get diagnostics v_partidas = row_count;

  return query select v_nuevo, v_codigo, v_partidas;
end;
$fn$;

grant execute on function copiar_rubro_al_catalogo(uuid) to authenticated;
revoke execute on function copiar_rubro_al_catalogo(uuid) from public, anon;


-- =====================================================================
-- Verificación
-- =====================================================================
--
-- ---- 1. el camino feliz, sobre un rubro de la carpeta de Galpón Mix
--
--   select * from copiar_rubro_al_catalogo(
--     (select id from rubros where obra_id = '<obra_id>' and codigo = '6'));
--   -- devuelve el id nuevo, el código que le tocó y cuántas partidas copió (3 para el rubro 6)
--
-- ---- 2. **la propiedad que importa: el monto de la obra NO se movió**
--
--   select calcular_presupuesto_vivo_obra('<obra_id>');
--   -- el mismo número que antes de copiar. Si cambió, algo tocó obra_subitems y no debía.
--
-- ---- 3. el original sigue en la carpeta, intacto
--
--   select count(*) from rubros where obra_id = '<obra_id>';   -- sigue en 9
--
-- ---- 4. la copia quedó en el catálogo personal, con sus partidas
--
--   select r.codigo, r.nombre, r.obra_id, r.creador_usuario_id,
--          (select count(*) from subitems s where s.rubro_id = r.id) as partidas
--   from rubros r where r.id = '<id devuelto>';
--   -- obra_id null, creador_usuario_id = tu usuario, partidas = 3
--
-- ---- 5. renumeración: copiar el MISMO rubro dos veces
--
--   select * from copiar_rubro_al_catalogo((select id from rubros where obra_id = '<obra_id>' and codigo = '6'));
--   -- la segunda vez el código tiene que volver como "6-2", no fallar ni pisar la primera copia
--
-- ---- 6. lo que tiene que fallar
--
--   -- un rubro que ya está en el catálogo:
--   select * from copiar_rubro_al_catalogo(
--     (select id from rubros where codigo = '18' and creador_usuario_id is null));
--   -- "Ese rubro ya está en un catálogo, no en la carpeta de una obra"
--
--   -- un rubro de una obra ajena (con otro usuario): "El rubro no existe o no tenés acceso"
