-- =====================================================================
-- 0156 — Reimportar reemplaza, avisando
-- =====================================================================
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.
--
-- §6.2 de `docs/carpetas_importado_y_catalogo_diseno_datos.md`, decisión 3.3.
-- **Leer esa sección antes de tocar esto.**
--
-- =====================================================================
-- QUÉ ARREGLA
-- =====================================================================
--
-- *"Importar dos veces la misma obra es corregir, no acumular."* (Seba)
--
-- Hoy `confirmar_importacion` (0081) hace upsert por partida: actualiza las que ya están y agrega
-- las nuevas, **pero nunca saca las que dejaron de venir en la planilla**. Reimportar una planilla
-- a la que le borraste tres partidas deja esas tres tildadas en la obra, sumando plata que ya no
-- está en el presupuesto. Y las descripciones que cambiaron entran como partidas nuevas, al lado de
-- las viejas.
--
-- =====================================================================
-- LO QUE HACE PELIGROSA ESTA PIEZA, Y CÓMO SE EVITA
-- =====================================================================
--
-- **`obra_subitems.rubro_id` y `subitem_id` tienen `on delete cascade` desde la `0028`.** O sea que
-- borrar un rubro o un subítem de la carpeta **se lleva las cantidades cargadas sin preguntar**. La
-- base no protege el cómputo; lo único que se planta son `certificado_subitems_avance` y
-- `presupuesto_subitems_congelado`, que no cascadean.
--
-- Por eso esta migración **nunca borra y vuelve a crear** una partida que sobrevive. Lo que
-- coincide se actualiza con un `update` que **conserva `obra_subitems.id`**, y eso es lo que hace
-- que el avance certificado y el monto congelado sigan apuntando a algo real. Es la misma razón por
-- la que la `0155` mueve el cómputo con un update en vez de un delete+insert.
--
-- =====================================================================
-- LAS CUATRO REGLAS
-- =====================================================================
--
-- 1. **Se conserva tildado, y con su cantidad, lo que coincide.** *"Si no, corregir tres precios
--    obliga a volver a tildar 24 partidas, y eso es empezar de nuevo en vez de corregir."*
--
-- 2. **Se rechaza si hay certificados emitidos.** Una obra que ya certificó no se reimporta: es
--    plata emitida contra un presupuesto, y rehacerlo por debajo es exactamente lo que no puede
--    pasar. Se corrige a mano, partida por partida.
--
-- 3. **Si está congelada sin emitir, se descongela** -- el snapshot deja de corresponder a las
--    partidas. El aviso lo dice antes.
--
-- 4. **Si no hay nada de eso, se avisa con números**: cuántas partidas se conservan, cuántas entran
--    nuevas, cuántas se descartan y **cuánta cantidad y monto se pierden con ellas**. El aviso dice
--    qué se pierde, no "¿estás seguro?".
--
-- =====================================================================
-- CÓMO SE DECIDE QUE DOS PARTIDAS SON "LA MISMA"
-- =====================================================================
--
-- La decisión es **código Y descripción**. Y acá aparece una limitación real que conviene tener
-- escrita, no descubrir después:
--
-- **El importador todavía no captura el código de la partida** (`importaciones_items` no tiene esa
-- columna, ver §8.1 del doc). Así que hoy el matcheo es **solo por descripción normalizada**.
--
-- **Falla hacia el lado seguro, y por eso se puede liberar así**: sin código, un cambio de
-- redacción hace que la partida se trate como nueva -- se pierde un tilde, que cuesta un toque. Lo
-- que NUNCA puede pasar es lo inverso (que una partida herede la cantidad de otra), y para eso
-- haría falta matchear solo por código, que es justamente lo que no se hace.
--
-- Cuando exista la columna de código, esto pasa a exigir las dos cosas y el matcheo se vuelve más
-- estricto, nunca más laxo. La función ya está escrita con el `coalesce` preparado.
--
-- Normalización: `insumo_nombre_normalizado` (0153). El nombre dice "insumo" por dónde nació, pero
-- es un normalizador de texto genérico -- mayúsculas, acentos y espacios. Reusarlo es mejor que
-- tener dos definiciones de "el mismo texto" que puedan divergir, que es exactamente el error que
-- creó las tres grúas.

-- =====================================================================
-- Sección 1 — la vista previa: los números del aviso, sin tocar nada
-- =====================================================================
--
-- Función aparte de la que ejecuta, y no un `out` de aquella: **el aviso va antes de hacer nada**.
-- La pantalla la llama al abrir el diálogo de confirmación y muestra lo que devuelve.
--
-- `security definer` para poder leer certificados y montos que la RLS del usuario no
-- necesariamente abre; el chequeo de autoridad va a mano y primero, como en el resto del proyecto.

create or replace function previsualizar_reemplazo_importacion(p_importacion_id uuid)
returns table(
  obra_id uuid,
  conservadas int,
  nuevas int,
  descartadas int,
  descartadas_con_cantidad int,
  monto_descartado numeric,
  avances_borrador int,
  bloqueado boolean,
  motivo_bloqueo text,
  descongela boolean
)
language plpgsql
security definer
set search_path = public
stable
as $fn$
#variable_conflict use_column
declare
  v_obra uuid;
  v_hay_emitidos boolean;
  v_congelada boolean;
begin
  select i.obra_id into v_obra from importaciones i where i.id = p_importacion_id;

  if v_obra is null then
    raise exception 'La importación no existe o no tiene obra asociada';
  end if;

  if not (tiene_rol_en_obra(v_obra, 'admin_maestro') or tiene_rol_en_obra(v_obra, 'profesional')) then
    raise exception 'Sin autoridad para revisar esta importación';
  end if;

  select exists (
    select 1 from certificados c where c.obra_id = v_obra and c.estado <> 'borrador'
  ) into v_hay_emitidos;

  select (o.presupuesto_congelado_en is not null) into v_congelada
  from obras o where o.id = v_obra;

  return query
  with filas as (
    -- Lo que trae la planilla, ya normalizado. `descripcion_texto` vacío no puede matchear nada ni
    -- entrar como partida: es una fila que la revisión no resolvió.
    select distinct insumo_nombre_normalizado(ii.descripcion_texto) as clave
    from importaciones_items ii
    where ii.importacion_id = p_importacion_id
      and ii.descripcion_texto is not null
      and trim(ii.descripcion_texto) <> ''
  ),
  actuales as (
    -- Lo que la obra tiene HOY en su carpeta. Solo la carpeta: una partida del catálogo tildada a
    -- mano no la trajo ninguna importación y no le corresponde a esta operación tocarla.
    select os.id as obra_subitem_id,
           os.cantidad,
           insumo_nombre_normalizado(s.descripcion) as clave
    from obra_subitems os
    join subitems s on s.id = os.subitem_id
    where os.obra_id = v_obra and s.obra_id = v_obra
  ),
  a_descartar as (
    select a.* from actuales a
    where not exists (select 1 from filas f where f.clave = a.clave)
  ),
  montos as (
    select m.obra_subitem_id, m.monto_total
    from calcular_monto_obra_subitems(v_obra) m
  )
  select
    v_obra,
    (select count(*)::int from actuales a where exists (select 1 from filas f where f.clave = a.clave)),
    (select count(*)::int from filas f where not exists (select 1 from actuales a where a.clave = f.clave)),
    (select count(*)::int from a_descartar),
    (select count(*)::int from a_descartar d where d.cantidad > 0),
    (select coalesce(sum(m.monto_total), 0) from a_descartar d join montos m on m.obra_subitem_id = d.obra_subitem_id),
    (select count(*)::int
       from certificado_subitems_avance csa
       join certificados c on c.id = csa.certificado_id
       where c.estado = 'borrador'
         and csa.obra_subitem_id in (select d.obra_subitem_id from a_descartar d)),
    v_hay_emitidos,
    case when v_hay_emitidos
      then 'Esta obra ya tiene certificados emitidos. Reimportar reharía el presupuesto por debajo de plata ya certificada.'
      else null end,
    (v_congelada and not v_hay_emitidos);
end;
$fn$;

grant execute on function previsualizar_reemplazo_importacion(uuid) to authenticated;
revoke execute on function previsualizar_reemplazo_importacion(uuid) from public, anon;


-- =====================================================================
-- Sección 2 — el reemplazo
-- =====================================================================
--
-- Reemplaza a `confirmar_importacion` (0081) para las importaciones de una obra que ya tiene
-- carpeta. **La 0081 no se toca y sigue existiendo**: es el camino de la primera importación, donde
-- no hay nada que reemplazar y el upsert simple es exactamente lo correcto.
--
-- El orden de abajo no es negociable y es el mismo que ya aprendimos con el seed: **lo que
-- referencia se borra antes que lo referenciado**, y lo que sobrevive se actualiza, nunca se
-- recrea.

create or replace function reemplazar_desde_importacion(p_importacion_id uuid)
returns table(conservadas int, nuevas int, descartadas int)
language plpgsql
security definer
set search_path = public
as $fn$
#variable_conflict use_column
declare
  v_obra uuid;
  v_estado text;
  v_conservadas int := 0;
  v_nuevas int := 0;
  v_descartadas int := 0;
  v_fila record;
  v_existente uuid;
begin
  select i.obra_id, i.estado into v_obra, v_estado
  from importaciones i where i.id = p_importacion_id;

  if v_obra is null then
    raise exception 'La importación no existe o no tiene obra asociada';
  end if;

  if v_estado <> 'pendiente_revision' then
    raise exception 'La importación no está pendiente de revisión (estado actual: %)', v_estado;
  end if;

  if not (tiene_rol_en_obra(v_obra, 'admin_maestro') or tiene_rol_en_obra(v_obra, 'profesional')) then
    raise exception 'Sin autoridad para confirmar esta importación';
  end if;

  -- ---------------------------------------------------------------- regla 2: el rechazo
  --
  -- Antes que cualquier escritura. Una obra que ya certificó no se reimporta.
  if exists (select 1 from certificados c where c.obra_id = v_obra and c.estado <> 'borrador') then
    raise exception 'Esta obra ya tiene certificados emitidos: no se puede reimportar. Corregí las partidas a mano.';
  end if;

  -- ---------------------------------------------------------------- regla 3: descongelar
  --
  -- El snapshot describe un presupuesto que está por dejar de existir. Se borra entero, no se
  -- intenta parchear: `congelar_presupuesto_obra` lo vuelve a armar de cero cuando corresponda.
  -- Llegar acá con certificados emitidos es imposible -- lo cortó el paso anterior.
  if exists (select 1 from obras o where o.id = v_obra and o.presupuesto_congelado_en is not null) then
    delete from presupuesto_subitems_congelado where obra_id = v_obra;
    delete from presupuesto_config_congelado where obra_id = v_obra;
    update obras
    set presupuesto_congelado_en = null,
        presupuesto_congelado_por = null,
        cotizacion_dolar_al_congelar = null
    where id = v_obra;
  end if;

  -- ---------------------------------------------------------------- las que se van
  --
  -- Tabla temporal y no una subconsulta repetida: las mismas filas se usan tres veces y el conjunto
  -- tiene que quedar fijo antes de empezar a borrar.
  --
  -- `drop ... if exists` primero: `on commit drop` la suelta al cerrar la transacción, pero dos
  -- llamadas dentro de la MISMA transacción chocarían con un "relation already exists". Cuesta una
  -- línea y evita un error que aparecería solo en el caso raro.
  drop table if exists _a_descartar;

  create temp table _a_descartar on commit drop as
  select os.id as obra_subitem_id, os.subitem_id
  from obra_subitems os
  join subitems s on s.id = os.subitem_id
  where os.obra_id = v_obra
    and s.obra_id = v_obra
    and not exists (
      select 1 from importaciones_items ii
      where ii.importacion_id = p_importacion_id
        and ii.descripcion_texto is not null
        and insumo_nombre_normalizado(ii.descripcion_texto) = insumo_nombre_normalizado(s.descripcion)
    );

  select count(*)::int into v_descartadas from _a_descartar;

  -- Los avances de certificados EN BORRADOR: sin cascade en `certificado_subitems_avance`, hay que
  -- sacarlos antes o el delete de abajo choca. Los de certificados emitidos no existen -- lo
  -- garantiza el rechazo de arriba.
  delete from certificado_subitems_avance
  where obra_subitem_id in (select d.obra_subitem_id from _a_descartar d);

  delete from obra_subitems
  where id in (select d.obra_subitem_id from _a_descartar d);

  -- Y las partidas de la carpeta que quedaron sin uso. `on delete cascade` de `subitems.rubro_id`
  -- no aplica acá (se borra el subítem, no el rubro), así que esto es explícito.
  delete from subitems s
  where s.id in (select d.subitem_id from _a_descartar d)
    and not exists (select 1 from obra_subitems os where os.subitem_id = s.id);

  -- ---------------------------------------------------------------- las que vienen
  --
  -- `distinct on` por clave: dos filas de la planilla con la misma descripción son la misma partida
  -- -- se toma la primera y no se crean dos. Sin esto, una planilla con un renglón repetido
  -- duplicaría la partida en la obra.
  for v_fila in
    select distinct on (insumo_nombre_normalizado(ii.descripcion_texto))
           ii.rubro_id, ii.subitem_id, ii.cantidad, ii.precio_unitario,
           insumo_nombre_normalizado(ii.descripcion_texto) as clave
    from importaciones_items ii
    where ii.importacion_id = p_importacion_id
      and ii.rubro_id is not null
      and ii.subitem_id is not null
      and ii.descripcion_texto is not null
      and trim(ii.descripcion_texto) <> ''
    order by insumo_nombre_normalizado(ii.descripcion_texto), ii.orden
  loop
    -- ¿Ya está en la obra, por descripción? Se busca contra la CARPETA, no contra el subitem_id que
    -- resolvió la revisión: si la revisión creó una partida nueva para algo que ya estaba, lo que
    -- manda es lo que la obra ya tiene -- conservar su id es lo que salva el tilde y la cantidad.
    select os.id into v_existente
    from obra_subitems os
    join subitems s on s.id = os.subitem_id
    where os.obra_id = v_obra
      and s.obra_id = v_obra
      and insumo_nombre_normalizado(s.descripcion) = v_fila.clave
    limit 1;

    if v_existente is not null then
      -- **REGLA 1.** Se actualiza el precio y NO la cantidad: reimportar es traer precios nuevos,
      -- y la cantidad es lo que no se quiere volver a cargar. `update` sobre la fila existente, así
      -- que `obra_subitems.id` no cambia y nada de lo que apunta a él se entera.
      update obra_subitems
      set precio_unitario_manual = coalesce(v_fila.precio_unitario, precio_unitario_manual),
          es_aplicable = true,
          ultima_modificacion_usuario_id = auth.uid(),
          updated_at = now()
      where id = v_existente;

      v_conservadas := v_conservadas + 1;

      -- La partida que la revisión creó de más para esta misma fila, si la creó, queda sin uso.
      delete from subitems s
      where s.id = v_fila.subitem_id
        and s.obra_id = v_obra
        and not exists (select 1 from obra_subitems os where os.subitem_id = s.id);
    else
      insert into obra_subitems (
        obra_id, rubro_id, subitem_id, cantidad, precio_unitario_manual,
        es_aplicable, agregado_por_usuario_id
      ) values (
        v_obra, v_fila.rubro_id, v_fila.subitem_id, coalesce(v_fila.cantidad, 0),
        v_fila.precio_unitario, true, auth.uid()
      );

      v_nuevas := v_nuevas + 1;
    end if;
  end loop;

  update importaciones
  set estado = 'confirmado'
  where id = p_importacion_id;

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (
    v_obra, auth.uid(), 'reemplazar_desde_importacion', 'importacion', p_importacion_id,
    jsonb_build_object('conservadas', v_conservadas, 'nuevas', v_nuevas, 'descartadas', v_descartadas)
  );

  return query select v_conservadas, v_nuevas, v_descartadas;
end;
$fn$;

grant execute on function reemplazar_desde_importacion(uuid) to authenticated;
revoke execute on function reemplazar_desde_importacion(uuid) from public, anon;


-- =====================================================================
-- Verificación
-- =====================================================================
--
-- Conviene armarla sobre una obra de prueba importada, NO sobre Galpón Mix con sus certificados.
--
-- ---- 1. la vista previa no toca nada
--
--   select * from previsualizar_reemplazo_importacion('<importacion_id>');
--   select calcular_presupuesto_vivo_obra('<obra_id>');   -- igual que antes de llamarla
--
-- ---- 2. el caso central: se conserva el tilde y la cantidad
--
--   -- (a) importar una planilla, confirmar, y cargar cantidades a mano en 3 partidas
--   -- (b) reimportar la MISMA planilla con un precio distinto en una de ellas
--   -- (c) select * from reemplazar_desde_importacion('<importacion_2>');
--   --     conservadas = todas, nuevas = 0, descartadas = 0
--   -- (d) las cantidades de (a) tienen que seguir ahí, y el precio actualizado:
--
--   select s.descripcion, os.cantidad, os.precio_unitario_manual
--   from obra_subitems os join subitems s on s.id = os.subitem_id
--   where os.obra_id = '<obra_id>' order by s.codigo;
--
-- ---- 3. **la prueba que más importa: los id no cambiaron**
--
--   -- anotar antes:  select id, subitem_id from obra_subitems where obra_id = '<obra_id>';
--   -- después del reemplazo, los id de las conservadas tienen que ser LOS MISMOS.
--   -- Si cambiaron, se borró y se creó, y eso rompe certificados y congelado.
--
-- ---- 4. se descarta lo que ya no viene
--
--   -- reimportar una planilla a la que le sacaste 2 renglones:
--   --   descartadas = 2, y esas 2 partidas ya no están en obra_subitems ni en la carpeta.
--   -- La vista previa tiene que haber anunciado esas 2 y su monto ANTES.
--
-- ---- 5. el rechazo (regla 2)
--
--   -- emitir un certificado en la obra y reintentar:
--   select * from reemplazar_desde_importacion('<importacion_id>');
--   -- "Esta obra ya tiene certificados emitidos: no se puede reimportar."
--   -- y previsualizar_... tiene que devolver bloqueado = true con el mismo motivo.
--
-- ---- 6. descongelar (regla 3)
--
--   -- congelar la obra (sin emitir), reemplazar, y confirmar que quedó descongelada:
--   select presupuesto_congelado_en from obras where id = '<obra_id>';   -- null
--   select count(*) from presupuesto_subitems_congelado where obra_id = '<obra_id>';   -- 0
--   -- y que previsualizar_... lo había anunciado con descongela = true
--
-- ---- 7. una planilla con un renglón repetido
--
--   -- dos filas con la misma descripción tienen que dejar UNA partida, no dos.
--
-- ---- 8. no quedan partidas huérfanas en la carpeta
--
--   select count(*) from subitems s
--   where s.obra_id = '<obra_id>'
--     and not exists (select 1 from obra_subitems os where os.subitem_id = s.id);
--   -- 0: ni las descartadas ni las que la revisión creó de más
