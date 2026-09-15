-- =====================================================================
-- 0155 — Bajar un rubro del catálogo a esta obra, para modificarlo (tanda 7)
-- =====================================================================
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor), **después de la 0154** (usa
-- su helper). No ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde
-- este entorno.
--
-- Tanda 7 de `docs/carpetas_importado_y_catalogo_diseno_datos.md` §6.1, dirección B, con las dos
-- decisiones b.1 y b.2 ya cerradas. **Leer esa sección antes de tocar esto.**
--
-- =====================================================================
-- QUÉ HACE
-- =====================================================================
--
-- *"Bajar uno del catálogo a esta obra para modificarlo sin tocar el original."* (Seba)
--
-- Duplica el rubro y sus partidas dentro de la carpeta de la obra. **El original queda en el
-- catálogo, intacto para todas tus otras obras.**
--
-- Pero a diferencia de la dirección A (0154), esta **sí toca `obra_subitems`**, y por dos motivos
-- que se decidieron explícitamente.
--
-- ---------------------------------------------------------------- b.1 — el cómputo pasa a la copia
--
-- Si la obra ya tiene partidas tildadas en ese rubro del catálogo y se lo baja sin más, quedan **dos
-- rubros con el mismo nombre en la misma obra**: el del catálogo con el cómputo, y la copia vacía.
-- Seba: *"Sin eso la función no sirve."*
--
-- Así que las partidas de ESTA obra pasan a apuntar a la copia. **Es un `update`, no un `delete` +
-- `insert`, y esa distinción es todo**: `obra_subitems.id` no cambia, y como
-- `certificado_subitems_avance` y `presupuesto_subitems_congelado` apuntan a ese id, **el avance ya
-- certificado y el monto congelado sobreviven intactos**. Con delete+insert, bajar un rubro podría
-- romper un certificado emitido.
--
-- Lo que sí cambia de dueño es el `rubro_id`/`subitem_id` de esas filas. La cantidad no se toca.
--
-- ---------------------------------------------------------------- b.2 — el precio se congela
--
-- Un rubro del catálogo puede tener `usa_apu = true` y sus subítems, composición cargada. **Los
-- subítems de la copia son filas nuevas sin `apu_composiciones`**, así que una copia con
-- `usa_apu = true` dejaría sus partidas sin precio -- cero, en silencio, que es el mismo modo de
-- falla que ya mordió una vez con el mapeo del PDF.
--
-- Entonces la copia nace `usa_apu = false` / `tipo_precio_manual = 'unitario'`, y **al copiar se
-- escribe en `precio_unitario_manual` el `precio_final` que el APU da en ese momento**. Seba: *"Es
-- lo que estoy pidiendo cuando bajo un rubro a la obra -- sacarlo de la cascada para esta obra
-- puntual."*
--
-- Tres consecuencias que conviene tener a la vista:
--
--   * **el precio deja de seguir a los insumos** para ese rubro en esa obra. Es el punto, no un
--     efecto lateral, pero la pantalla lo avisa antes de confirmar;
--   * **no hace falta la `0150`.** La copia es un rubro de precio manual de verdad, no uno con APU
--     al que se le mete un precio a mano;
--   * **la receta no se duplica.** Descartado a propósito: copiar `apu_composiciones` metería la
--     pieza en la propiedad del APU por persona, que es otra conversación.
--
-- **El precio se calcula ANTES de mover el cómputo**, porque después de mover, los `subitem_id` ya
-- son los de la copia y `calcular_precio_final_apu_subitems` no encontraría ninguna composición.
-- Es el orden que hace que todo lo demás funcione.
--
-- ---------------------------------------------------------------- sobre las obras congeladas
--
-- No se bloquea, y no es un olvido. El monto no se mueve: `obra_subitems.id` se conserva, la
-- cantidad tampoco cambia, y el precio que se congela en la partida es exactamente el que el APU
-- daba. Además, en una obra congelada `calcular_monto_obra_subitems` ni siquiera mira la rama viva
-- -- lee `presupuesto_subitems_congelado`, que apunta a los mismos `obra_subitems.id`.

-- =====================================================================
-- Sección 1 — helpers de código libre dentro de una carpeta
-- =====================================================================
--
-- Los índices de la `0151` son `(obra_id, codigo)`, y para subítems abarcan **toda la carpeta**, no
-- el rubro. Por eso hay dos helpers y no uno: un código de rubro y uno de partida se chequean
-- contra tablas distintas.
--
-- Mismo criterio de sufijo que `siguiente_codigo_rubro_propio` (0154): `-2`, `-3`... Acá el código
-- SÍ se ve (en las partidas), así que el sufijo es también la señal al usuario de que hubo un
-- choque -- mejor un "14.5-2" visible que un número inventado que parezca del catálogo.

create or replace function siguiente_codigo_rubro_en_obra(p_codigo text, p_obra_id uuid)
returns text
language plpgsql
stable
set search_path = public
as $fn$
declare
  v_candidato text := p_codigo;
  v_n int := 1;
begin
  while exists (select 1 from rubros r where r.obra_id = p_obra_id and r.codigo = v_candidato) loop
    v_n := v_n + 1;
    if v_n > 50 then
      raise exception 'No se pudo encontrar un código libre para el rubro "%" en esta obra', p_codigo;
    end if;
    v_candidato := p_codigo || '-' || v_n::text;
  end loop;
  return v_candidato;
end;
$fn$;

create or replace function siguiente_codigo_subitem_en_obra(p_codigo text, p_obra_id uuid)
returns text
language plpgsql
stable
set search_path = public
as $fn$
declare
  v_candidato text := p_codigo;
  v_n int := 1;
begin
  while exists (select 1 from subitems s where s.obra_id = p_obra_id and s.codigo = v_candidato) loop
    v_n := v_n + 1;
    if v_n > 50 then
      raise exception 'No se pudo encontrar un código libre para la partida "%" en esta obra', p_codigo;
    end if;
    v_candidato := p_codigo || '-' || v_n::text;
  end loop;
  return v_candidato;
end;
$fn$;

grant execute on function siguiente_codigo_rubro_en_obra(text, uuid) to authenticated;
grant execute on function siguiente_codigo_subitem_en_obra(text, uuid) to authenticated;


-- =====================================================================
-- Sección 2 — cuántas partidas de la obra se van a mover
-- =====================================================================
--
-- La pantalla necesita este número **antes** de confirmar, para poder decir "Esta obra tiene 6
-- partidas cargadas en este rubro. Pasan a la copia, con sus cantidades y su avance." (b.1). Con 0
-- la frase no aparece: no hay nada que advertir.
--
-- Función aparte y no un `out` de la copia: el aviso va antes de hacer nada.

create or replace function partidas_de_la_obra_en_rubro(p_rubro_id uuid, p_obra_id uuid)
returns int
language sql
stable
security invoker
set search_path = public
as $fn$
  select count(*)::int
  from obra_subitems os
  where os.obra_id = p_obra_id and os.rubro_id = p_rubro_id;
$fn$;

grant execute on function partidas_de_la_obra_en_rubro(uuid, uuid) to authenticated;


-- =====================================================================
-- Sección 3 — copiar_rubro_a_la_obra
-- =====================================================================
--
-- `security definer`, a diferencia de la 0154, y el motivo es concreto:
-- `calcular_precio_final_apu_subitems` necesita leer precios de insumos cuya RLS no está abierta al
-- usuario, y el `update` de `obra_subitems` tiene que poder correr aunque la política de esa tabla
-- sea más angosta que `puede_editar_presupuesto`. **Por eso el chequeo de autoridad se hace a mano
-- y primero**, igual que en el resto de las funciones definer del proyecto.

create or replace function copiar_rubro_a_la_obra(p_rubro_id uuid, p_obra_id uuid)
returns table(rubro_id uuid, codigo text, partidas int, partidas_movidas int)
language plpgsql
security definer
set search_path = public
as $fn$
#variable_conflict use_column
declare
  v_usuario uuid := auth.uid();
  v_origen record;
  v_codigo text;
  v_nuevo uuid;
  v_orden int;
  v_partidas int := 0;
  v_movidas int := 0;
  v_fila record;
  v_nuevo_subitem uuid;
begin
  if v_usuario is null then
    raise exception 'Sin sesión';
  end if;

  if not puede_editar_presupuesto(p_obra_id) then
    raise exception 'Sin autoridad para editar el presupuesto de esta obra';
  end if;

  select r.* into v_origen from rubros r where r.id = p_rubro_id;

  if v_origen.id is null then
    raise exception 'El rubro no existe';
  end if;

  if v_origen.obra_id is not null then
    raise exception 'Ese rubro ya es de una obra, no del catálogo';
  end if;

  -- Un rubro propio de OTRA persona no se puede bajar: la RLS de lectura lo permitiría en algunos
  -- casos (puede_ver_apu_ajena), pero copiar el catálogo de otro a tu obra es otra cosa.
  if v_origen.creador_usuario_id is not null and v_origen.creador_usuario_id <> v_usuario then
    raise exception 'Ese rubro es del catálogo personal de otra persona';
  end if;

  v_codigo := siguiente_codigo_rubro_en_obra(v_origen.codigo, p_obra_id);

  select coalesce(max(r.orden), 0) + 1 into v_orden from rubros r where r.obra_id = p_obra_id;

  -- **usa_apu = false y precio manual** (decisión b.2): la copia sale de la cascada de APU para esta
  -- obra. Sus subítems son filas nuevas sin composición, así que dejarla en `usa_apu = true` la
  -- dejaría sin precio, en silencio.
  insert into rubros (codigo, nombre, orden, usa_apu, tipo_precio_manual, creador_usuario_id, obra_id)
  values (v_codigo, v_origen.nombre, v_orden, false, 'unitario', v_usuario, p_obra_id)
  returning rubros.id into v_nuevo;

  -- ---------------------------------------------------------------- las partidas, una por una
  --
  -- Loop y no un `insert ... select`: hace falta el mapa viejo -> nuevo para mover el cómputo, y el
  -- código de cada partida se calcula contra la carpeta, que va cambiando a medida que se insertan.
  for v_fila in
    select s.id, s.codigo, s.descripcion, s.unidad
    from subitems s
    where s.rubro_id = p_rubro_id
      and (s.creador_usuario_id is null or s.creador_usuario_id = v_usuario)
      and s.obra_id is null
    order by s.codigo
  loop
    insert into subitems (rubro_id, codigo, descripcion, unidad, creador_usuario_id, obra_id)
    values (
      v_nuevo,
      siguiente_codigo_subitem_en_obra(v_fila.codigo, p_obra_id),
      v_fila.descripcion,
      v_fila.unidad,
      v_usuario,
      p_obra_id
    )
    returning subitems.id into v_nuevo_subitem;

    v_partidas := v_partidas + 1;

    -- ------------------------------------------------------------ mover el cómputo de ESTA obra
    --
    -- **El precio se resuelve ANTES del update**, con el `subitem_id` viejo: después de mover, la
    -- partida apunta a la copia, que no tiene composición, y el precio daría null.
    --
    -- `coalesce(precio_unitario_manual, <el del APU>)`: si la obra ya le había puesto un precio a
    -- mano, ese gana -- bajar el rubro no puede pisar una decisión del usuario. Solo se congela el
    -- precio a las que lo derivaban del APU.
    update obra_subitems os
    set rubro_id = v_nuevo,
        subitem_id = v_nuevo_subitem,
        precio_unitario_manual = coalesce(
          os.precio_unitario_manual,
          (select p.precio_final
           from calcular_precio_final_apu_subitems(p_obra_id, array[v_fila.id]) p
           where p.subitem_id = v_fila.id)
        ),
        ultima_modificacion_usuario_id = v_usuario,
        updated_at = now()
    where os.obra_id = p_obra_id and os.subitem_id = v_fila.id;
  end loop;

  -- Las partidas movidas se cuentan al final contra el rubro nuevo, y no acumulando `row_count`
  -- dentro del loop: una misma partida puede estar cargada más de una vez en la obra (sectores
  -- distintos, ver `obra_subitems`, que a propósito no tiene unique(obra_id, subitem_id)), así que
  -- el conteo de filas movidas y el de partidas copiadas no tienen por qué coincidir.
  select count(*)::int into v_movidas
  from obra_subitems os
  where os.obra_id = p_obra_id and os.rubro_id = v_nuevo;

  return query select v_nuevo, v_codigo, v_partidas, v_movidas;
end;
$fn$;

grant execute on function copiar_rubro_a_la_obra(uuid, uuid) to authenticated;
revoke execute on function copiar_rubro_a_la_obra(uuid, uuid) from public, anon;


-- =====================================================================
-- Verificación
-- =====================================================================
--
-- Conviene hacerla sobre una obra de prueba con partidas tildadas en un rubro CON APU (por ejemplo
-- el 14 REVESTIMIENTOS SECOS), que es el caso que ejercita las dos decisiones a la vez.
--
-- ---- 1. anotar el estado ANTES
--
--   select calcular_presupuesto_vivo_obra('<obra_id>') as vivo_antes;
--   select partidas_de_la_obra_en_rubro(
--     (select id from rubros where codigo = '14' and creador_usuario_id is null), '<obra_id>');
--
-- ---- 2. copiar
--
--   select * from copiar_rubro_a_la_obra(
--     (select id from rubros where codigo = '14' and creador_usuario_id is null), '<obra_id>');
--   -- partidas = las del rubro del catálogo; partidas_movidas = las que la obra tenía tildadas
--
-- ---- 3. **la prueba que más importa: el monto no se movió**
--
--   select calcular_presupuesto_vivo_obra('<obra_id>');
--   -- tiene que dar lo mismo que `vivo_antes`, al centavo. Si bajó, el precio no se congeló bien;
--   -- si subió, se contó algo dos veces.
--
-- ---- 4. el cómputo quedó en la copia y no duplicado
--
--   select r.codigo, r.nombre, r.obra_id, count(os.id) as partidas_cargadas
--   from rubros r left join obra_subitems os on os.rubro_id = r.id and os.obra_id = '<obra_id>'
--   where r.codigo like '14%' group by 1,2,3;
--   -- el rubro del catálogo tiene que quedar en 0 para esta obra; la copia, con las que había
--
-- ---- 5. el original está intacto
--
--   select count(*) from subitems where rubro_id =
--     (select id from rubros where codigo = '14' and creador_usuario_id is null);
--   -- las 6 de siempre; y el rubro sigue con usa_apu = true
--
-- ---- 6. **los certificados sobrevivieron** (si la obra tenía alguno emitido sobre ese rubro)
--
--   select count(*) from certificado_subitems_avance csa
--   join obra_subitems os on os.id = csa.obra_subitem_id
--   where os.obra_id = '<obra_id>';
--   -- el mismo número que antes: el update conserva obra_subitems.id, así que nada quedó huérfano
--
--   select * from calcular_totales_certificado('<certificado_id>');
--   -- los mismos montos que antes de copiar
--
-- ---- 7. el precio quedó congelado y ya no sigue al APU
--
--   select s.codigo, os.cantidad, os.precio_unitario_manual
--   from obra_subitems os join subitems s on s.id = os.subitem_id
--   where os.obra_id = '<obra_id>' and os.rubro_id = '<id de la copia>';
--   -- precio_unitario_manual con el valor que daba el APU. Cambiar el precio de un insumo en
--   -- Mat y MO ya no tiene que mover estos números.
--
-- ---- 8. lo que tiene que fallar
--
--   -- un rubro que ya es de una obra: "Ese rubro ya es de una obra, no del catálogo"
--   -- sin puede_editar_presupuesto: "Sin autoridad para editar el presupuesto de esta obra"
--
-- ---- 9. renumeración: bajar el mismo rubro dos veces a la misma obra
--
--   -- la segunda copia tiene que volver con codigo "14-2" y sus partidas con "14.1-2", etc.
--   -- La segunda vez `partidas_movidas` da 0: la obra ya no tiene nada tildado en el del catálogo.
