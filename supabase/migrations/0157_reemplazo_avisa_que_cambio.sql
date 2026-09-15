-- =====================================================================
-- 0157 — El reemplazo avisa QUÉ cambió, y lo descartado se destilda
-- =====================================================================
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor), después de la `0156`. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.
--
-- §6.2 de `docs/carpetas_importado_y_catalogo_diseno_datos.md`.
--
-- =====================================================================
-- CAMBIO DE CRITERIO SOBRE LA 0156
-- =====================================================================
--
-- La `0156` resolvía por regla quién ganaba cuando la planilla traía un número distinto al cargado
-- (conservaba la cantidad de la obra). Seba la corrigió, y la corrección cambia la forma de la
-- pieza:
--
-- > *"Tenemos que tirar una alerta de que los datos no se corresponden, de que se han modificado, y
-- > que si querés dejarlos modificados, o se corrige la planilla que ya está en la aplicación, o
-- > querés revisarla antes de ejecutarla."*
--
-- Y el miedo concreto detrás: *"para que no pise y digas: uy, mirá, me perdí todo el trabajo"*.
--
-- **Ninguna de las dos fuentes gana por regla. La app muestra qué cambia y el usuario decide.** La
-- regla se muda del código al aviso. Por eso `reemplazar_desde_importacion` deja de conservar la
-- cantidad: aplica la planilla entera, porque para cuando se la llama el usuario ya vio el diff y
-- dijo que sí.
--
-- =====================================================================
-- LA COLUMNA QUE HACE QUE EL AVISO NO SEA RUIDO
-- =====================================================================
--
-- **`editada_a_mano`.** Con cincuenta diferencias, cincuenta iguales no dicen nada. No es lo mismo:
--
--   * *la planilla ahora dice 42 y antes decía 40* -> la planilla se corrigió, aplicar es lo que se
--     quiere;
--   * *la planilla dice 40, antes decía 40, y hoy hay 42 porque lo cambió el usuario* -> **eso es el
--     trabajo que se pierde**, y es lo único que justifica frenar.
--
-- Se puede distinguir porque **las importaciones anteriores no se borran nunca**: quedan en estado
-- `confirmado` con todos sus ítems (0080 no tiene política DELETE a propósito). Así que se compara
-- lo que está cargado hoy contra lo que trajo la última importación confirmada de esta obra.
--
-- Una partida de la carpeta que **ninguna importación previa trajo** se marca `editada_a_mano =
-- true`: si no se puede probar que el número lo puso una planilla, se asume que es del usuario. El
-- fail-safe apunta a avisar de más, nunca de menos.
--
-- =====================================================================
-- LO DESCARTADO SE DESTILDA, NO SE BORRA
-- =====================================================================
--
-- La `0156` borraba las partidas que dejaban de venir en la planilla. Ahora se les pone
-- `es_aplicable = false`, y es **más barato que lo que reemplaza**:
--
--   * no se pierde nada: la cantidad queda cargada;
--   * el total de la obra no las cuenta, así que la obra sí corresponde a la planilla;
--   * si fue un error, se vuelve a tildar y listo -- **el reemplazo pasa a ser reversible dentro de
--     la app**, que es mejor que un archivo que hay que ir a buscar;
--   * si una reimportación posterior las trae de vuelta, el matcheo las encuentra y las re-tilda
--     **con su cantidad intacta** (tipo `reactivada` en el diff);
--   * y desaparece el `delete` sobre `obra_subitems`, con él todo el riesgo del cascade de la
--     `0028` en este camino.
--
-- =====================================================================
-- EL DIFF SE CALCULA EN UN SOLO LUGAR
-- =====================================================================
--
-- `diferencias_reemplazo_importacion` devuelve las filas y
-- `previsualizar_reemplazo_importacion` agrega sobre ellas. **El resumen no puede desviarse del
-- detalle porque sale del detalle** -- si fueran dos consultas distintas, el día que una cambie el
-- criterio la otra seguiría contando lo de antes, y el usuario vería "cambian 3" y después cuatro
-- renglones.
--
-- El matcheo sigue siendo **por descripción normalizada** (`insumo_nombre_normalizado`, 0153),
-- con la limitación ya escrita en la `0156`: el importador todavía no captura el código de partida
-- (§8.1 del doc), y sin código el matcheo falla hacia el lado seguro -- trata como nueva una
-- partida cuya redacción cambió, que cuesta un tilde.

-- =====================================================================
-- Sección 1 — el diff, fila por fila
-- =====================================================================

create or replace function diferencias_reemplazo_importacion(p_importacion_id uuid)
returns table(
  codigo text,
  descripcion text,
  tipo text,              -- 'precio' | 'cantidad' | 'nueva' | 'descartada' | 'reactivada'
  valor_actual numeric,
  valor_planilla numeric,
  editada_a_mano boolean,
  monto_actual numeric
)
language plpgsql
security definer
set search_path = public
stable
as $fn$
#variable_conflict use_column
declare
  v_obra uuid;
  v_previa uuid;
begin
  select i.obra_id into v_obra from importaciones i where i.id = p_importacion_id;

  if v_obra is null then
    raise exception 'La importación no existe o no tiene obra asociada';
  end if;

  if not (tiene_rol_en_obra(v_obra, 'admin_maestro') or tiene_rol_en_obra(v_obra, 'profesional')) then
    raise exception 'Sin autoridad para revisar esta importación';
  end if;

  -- La última importación confirmada de esta obra: la referencia para saber si un número lo puso
  -- una planilla o una persona. `confirmado_at` y no `created_at`: lo que importa es cuál fue la
  -- última que efectivamente impactó en la obra.
  select i.id into v_previa
  from importaciones i
  where i.obra_id = v_obra and i.estado = 'confirmado' and i.id <> p_importacion_id
  order by i.confirmado_at desc nulls last, i.created_at desc
  limit 1;

  return query
  with planilla as (
    -- `distinct on` por clave: dos renglones con la misma descripción son la misma partida. Sin
    -- esto una planilla con un renglón repetido generaría dos diferencias por lo mismo.
    select distinct on (insumo_nombre_normalizado(ii.descripcion_texto))
           insumo_nombre_normalizado(ii.descripcion_texto) as clave,
           ii.descripcion_texto,
           ii.cantidad,
           ii.precio_unitario
    from importaciones_items ii
    where ii.importacion_id = p_importacion_id
      and ii.rubro_id is not null
      and ii.subitem_id is not null
      and ii.descripcion_texto is not null
      and trim(ii.descripcion_texto) <> ''
    order by insumo_nombre_normalizado(ii.descripcion_texto), ii.orden
  ),
  -- Todas las partidas de la carpeta, tildadas o no: una destildada por un reemplazo anterior tiene
  -- que poder volver a entrar si la planilla la trae de nuevo.
  en_la_obra as (
    select os.id as obra_subitem_id, os.subitem_id, os.es_aplicable,
           s.codigo, s.descripcion,
           os.cantidad, os.precio_unitario_manual,
           insumo_nombre_normalizado(s.descripcion) as clave
    from obra_subitems os
    join subitems s on s.id = os.subitem_id
    where os.obra_id = v_obra and s.obra_id = v_obra
  ),
  previa as (
    select ii.subitem_id, ii.cantidad, ii.precio_unitario
    from importaciones_items ii
    where v_previa is not null and ii.importacion_id = v_previa and ii.subitem_id is not null
  ),
  montos as (
    select m.obra_subitem_id, m.monto_total from calcular_monto_obra_subitems(v_obra) m
  ),
  cruce as (
    select o.*, p.cantidad as cant_planilla, p.precio_unitario as precio_planilla,
           pr.cantidad as cant_previa, pr.precio_unitario as precio_previo,
           (pr.subitem_id is not null) as hubo_previa
    from en_la_obra o
    join planilla p on p.clave = o.clave
    left join previa pr on pr.subitem_id = o.subitem_id
  )
  -- Cambia el precio
  select c.codigo, c.descripcion, 'precio'::text,
         round(c.precio_unitario_manual, 2), round(c.precio_planilla, 2),
         -- Sin importación previa que lo respalde, se asume que el número es del usuario.
         coalesce(c.hubo_previa and round(c.precio_unitario_manual, 2)
                    is distinct from round(c.precio_previo, 2), true),
         null::numeric
  from cruce c
  where round(c.precio_unitario_manual, 2) is distinct from round(c.precio_planilla, 2)

  union all
  -- Cambia la cantidad
  select c.codigo, c.descripcion, 'cantidad'::text,
         round(c.cantidad, 2), round(c.cant_planilla, 2),
         coalesce(c.hubo_previa and round(c.cantidad, 2)
                    is distinct from round(c.cant_previa, 2), true),
         null::numeric
  from cruce c
  where round(c.cantidad, 2) is distinct from round(c.cant_planilla, 2)

  union all
  -- Vuelve a entrar una que un reemplazo anterior había destildado
  select c.codigo, c.descripcion, 'reactivada'::text,
         null::numeric, round(c.cant_planilla, 2), false, null::numeric
  from cruce c
  where c.es_aplicable = false

  union all
  -- Viene en la planilla y no está en la obra
  select null::text, p.descripcion_texto, 'nueva'::text,
         null::numeric, round(p.cantidad, 2), false, null::numeric
  from planilla p
  where not exists (select 1 from en_la_obra o where o.clave = p.clave)

  union all
  -- Está tildada en la obra y la planilla ya no la trae
  select o.codigo, o.descripcion, 'descartada'::text,
         round(o.cantidad, 2), null::numeric,
         -- Se marca si la cantidad cargada no la puso la última planilla: es trabajo que se
         -- destilda, y el aviso tiene que poder decirlo.
         coalesce((select round(o.cantidad, 2) is distinct from round(pr.cantidad, 2)
                   from previa pr where pr.subitem_id = o.subitem_id), true),
         (select round(m.monto_total, 2) from montos m where m.obra_subitem_id = o.obra_subitem_id)
  from en_la_obra o
  where o.es_aplicable = true
    and not exists (select 1 from planilla p where p.clave = o.clave);
end;
$fn$;

grant execute on function diferencias_reemplazo_importacion(uuid) to authenticated;
revoke execute on function diferencias_reemplazo_importacion(uuid) from public, anon;


-- =====================================================================
-- Sección 2 — el resumen, agregando sobre el mismo diff
-- =====================================================================
--
-- Cambia la lista de columnas respecto de la `0156`, así que va `drop` + `create`: `create or
-- replace` no admite cambiar el `returns table`.

drop function if exists previsualizar_reemplazo_importacion(uuid);

create function previsualizar_reemplazo_importacion(p_importacion_id uuid)
returns table(
  obra_id uuid,
  cambios_precio int,
  cambios_cantidad int,
  editadas_a_mano int,
  nuevas int,
  descartadas int,
  reactivadas int,
  sin_cambios int,
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

  select exists (select 1 from certificados c where c.obra_id = v_obra and c.estado <> 'borrador')
    into v_hay_emitidos;

  select (o.presupuesto_congelado_en is not null) into v_congelada from obras o where o.id = v_obra;

  return query
  with d as (select * from diferencias_reemplazo_importacion(p_importacion_id)),
  -- Las que están en las dos y no cambiaron nada: se cuentan aparte porque son la mayoría y el
  -- aviso necesita poder decir "las otras 20 quedan igual".
  en_comun as (
    select count(*)::int as n
    from obra_subitems os
    join subitems s on s.id = os.subitem_id
    where os.obra_id = v_obra and s.obra_id = v_obra and os.es_aplicable = true
      and exists (
        select 1 from importaciones_items ii
        where ii.importacion_id = p_importacion_id
          and ii.descripcion_texto is not null
          and insumo_nombre_normalizado(ii.descripcion_texto) = insumo_nombre_normalizado(s.descripcion)
      )
      and not exists (
        select 1 from d
        where d.tipo in ('precio', 'cantidad') and d.descripcion = s.descripcion
      )
  )
  select
    v_obra,
    (select count(*)::int from d where d.tipo = 'precio'),
    (select count(*)::int from d where d.tipo = 'cantidad'),
    -- Una partida con precio Y cantidad editados a mano cuenta una sola vez: el aviso habla de
    -- partidas en riesgo, no de campos.
    (select count(distinct d.descripcion)::int from d
      where d.editada_a_mano and d.tipo in ('precio', 'cantidad', 'descartada')),
    (select count(*)::int from d where d.tipo = 'nueva'),
    (select count(*)::int from d where d.tipo = 'descartada'),
    (select count(*)::int from d where d.tipo = 'reactivada'),
    (select n from en_comun),
    (select coalesce(sum(d.monto_actual), 0) from d where d.tipo = 'descartada'),
    -- Avances en certificados BORRADOR sobre partidas que se van a destildar: se descartan al
    -- aplicar (un avance sobre una partida destildada calcularía 0 y quedaría de adorno).
    (select count(*)::int
       from certificado_subitems_avance csa
       join certificados c on c.id = csa.certificado_id
       join obra_subitems os on os.id = csa.obra_subitem_id
       join subitems s on s.id = os.subitem_id
       where c.estado = 'borrador' and os.obra_id = v_obra and s.obra_id = v_obra
         and os.es_aplicable = true
         and not exists (
           select 1 from importaciones_items ii
           where ii.importacion_id = p_importacion_id
             and ii.descripcion_texto is not null
             and insumo_nombre_normalizado(ii.descripcion_texto) = insumo_nombre_normalizado(s.descripcion)
         )),
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
-- Sección 3 — el reemplazo
-- =====================================================================
--
-- Cambia respecto de la `0156` en dos cosas y **nada más**:
--
--   1. **aplica la planilla entera**, cantidad incluida -- la decisión de qué gana se tomó en el
--      aviso, no acá;
--   2. **destilda en vez de borrar** lo que la planilla ya no trae.
--
-- Lo que protege queda igual: el rechazo con certificados emitidos antes de cualquier escritura, el
-- descongelamiento, y el `update` que conserva `obra_subitems.id` para que nada de lo que apunta a
-- él quede huérfano.

create or replace function reemplazar_desde_importacion(p_importacion_id uuid)
returns table(actualizadas int, nuevas int, destildadas int)
language plpgsql
security definer
set search_path = public
as $fn$
#variable_conflict use_column
declare
  v_obra uuid;
  v_estado text;
  v_actualizadas int := 0;
  v_nuevas int := 0;
  v_destildadas int := 0;
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

  -- Regla 2: el rechazo, antes de escribir una sola fila.
  if exists (select 1 from certificados c where c.obra_id = v_obra and c.estado <> 'borrador') then
    raise exception 'Esta obra ya tiene certificados emitidos: no se puede reimportar. Corregí las partidas a mano.';
  end if;

  -- Regla 3: descongelar. El snapshot describe un presupuesto que está por dejar de existir; se
  -- borra entero y `congelar_presupuesto_obra` lo rearma cuando corresponda. Llegar acá con
  -- certificados emitidos es imposible: lo cortó el paso anterior.
  if exists (select 1 from obras o where o.id = v_obra and o.presupuesto_congelado_en is not null) then
    delete from presupuesto_subitems_congelado where obra_id = v_obra;
    delete from presupuesto_config_congelado where obra_id = v_obra;
    update obras
    set presupuesto_congelado_en = null,
        presupuesto_congelado_por = null,
        cotizacion_dolar_al_congelar = null
    where id = v_obra;
  end if;

  -- ---------------------------------------------------------------- las que la planilla ya no trae
  drop table if exists _a_destildar;
  create temp table _a_destildar on commit drop as
  select os.id as obra_subitem_id
  from obra_subitems os
  join subitems s on s.id = os.subitem_id
  where os.obra_id = v_obra
    and s.obra_id = v_obra
    and os.es_aplicable = true
    and not exists (
      select 1 from importaciones_items ii
      where ii.importacion_id = p_importacion_id
        and ii.descripcion_texto is not null
        and insumo_nombre_normalizado(ii.descripcion_texto) = insumo_nombre_normalizado(s.descripcion)
    );

  -- Los avances en BORRADOR sí se borran: un avance sobre una partida destildada calcularía 0 y
  -- quedaría de adorno adentro del certificado. Los de certificados emitidos no existen -- lo
  -- garantiza el rechazo de arriba.
  delete from certificado_subitems_avance
  where obra_subitem_id in (select d.obra_subitem_id from _a_destildar d);

  -- **Destildar, no borrar.** La cantidad queda cargada: si esto fue un error, se vuelve a tildar.
  update obra_subitems
  set es_aplicable = false,
      ultima_modificacion_usuario_id = auth.uid(),
      updated_at = now()
  where id in (select d.obra_subitem_id from _a_destildar d);

  get diagnostics v_destildadas = row_count;

  -- ---------------------------------------------------------------- las que trae la planilla
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
    -- Se busca contra la CARPETA por descripción, no contra el `subitem_id` que resolvió la
    -- revisión: si la revisión creó una partida nueva para algo que ya estaba -- porque el buscador
    -- no la encontró -- manda lo que la obra ya tiene. Conservar su id es lo que salva el avance
    -- certificado y el congelado.
    select os.id into v_existente
    from obra_subitems os
    join subitems s on s.id = os.subitem_id
    where os.obra_id = v_obra and s.obra_id = v_obra
      and insumo_nombre_normalizado(s.descripcion) = v_fila.clave
    limit 1;

    -- Segundo intento, por `subitem_id`, que es lo que hace `confirmar_importacion` (0081). Cubre
    -- la fila que la revisión mapeó a una partida del CATÁLOGO ya tildada en esta obra: no está en
    -- la carpeta, así que la búsqueda de arriba no la encuentra, y sin esto se insertaría una
    -- segunda fila para la misma partida.
    --
    -- Con esto el reemplazo es un superconjunto de la 0081 y la pantalla puede usar siempre este
    -- camino, también en la primera importación, donde no hay nada que destildar.
    if v_existente is null then
      select os.id into v_existente
      from obra_subitems os
      where os.obra_id = v_obra and os.subitem_id = v_fila.subitem_id
      limit 1;
    end if;

    if v_existente is not null then
      -- La planilla entera, cantidad incluida. `es_aplicable = true` re-tilda una que un reemplazo
      -- anterior había destildado, con la cantidad que traiga ahora.
      update obra_subitems
      set cantidad = coalesce(v_fila.cantidad, cantidad),
          precio_unitario_manual = coalesce(v_fila.precio_unitario, precio_unitario_manual),
          es_aplicable = true,
          ultima_modificacion_usuario_id = auth.uid(),
          updated_at = now()
      where id = v_existente;

      v_actualizadas := v_actualizadas + 1;

      -- La partida que la revisión creó de más para esta misma fila queda sin uso.
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
  set estado = 'confirmado',
      confirmado_por_usuario_id = auth.uid(),
      confirmado_at = now()
  where id = p_importacion_id;

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (
    v_obra, auth.uid(), 'reemplazar_desde_importacion', 'importacion', p_importacion_id,
    jsonb_build_object('actualizadas', v_actualizadas, 'nuevas', v_nuevas, 'destildadas', v_destildadas)
  );

  return query select v_actualizadas, v_nuevas, v_destildadas;
end;
$fn$;

grant execute on function reemplazar_desde_importacion(uuid) to authenticated;
revoke execute on function reemplazar_desde_importacion(uuid) from public, anon;


-- =====================================================================
-- Verificación
-- =====================================================================
--
-- Sobre una obra de prueba importada, NO sobre una con certificados emitidos.
--
-- ---- 1. el resumen sale del detalle y no puede desviarse
--
--   select * from previsualizar_reemplazo_importacion('<importacion_id>');
--   select * from diferencias_reemplazo_importacion('<importacion_id>') order by tipo, codigo;
--   -- cambios_precio tiene que ser exactamente cuántas filas de tipo 'precio' hay, y así con cada
--   -- contador. Si no coinciden, alguien tocó una de las dos consultas sin la otra.
--
-- ---- 2. **la columna que importa**: editada_a_mano
--
--   -- (a) importar y confirmar una planilla
--   -- (b) cambiar A MANO la cantidad de una partida en Cómputo
--   -- (c) reimportar la MISMA planilla sin tocarla
--   -- (d) select * from diferencias_reemplazo_importacion('<importacion_2>');
--   --     una fila tipo 'cantidad', con editada_a_mano = TRUE
--   --     (el valor cargado no lo puso la planilla anterior: lo puso el usuario)
--   -- (e) ahora al revés: cambiar la cantidad EN LA PLANILLA y reimportar
--   --     misma fila tipo 'cantidad', pero editada_a_mano = FALSE
--   --     (lo cargado sí coincide con lo que trajo la planilla anterior)
--
-- ---- 3. destildar y volver
--
--   -- reimportar una planilla sin 2 renglones: destildadas = 2, y esas partidas siguen existiendo
--   select s.descripcion, os.es_aplicable, os.cantidad
--   from obra_subitems os join subitems s on s.id = os.subitem_id
--   where os.obra_id = '<obra_id>' and os.es_aplicable = false;
--   -- es_aplicable false, cantidad intacta. Nada se borró.
--
--   -- y volver a importar la planilla COMPLETA:
--   --   el diff las muestra como 'reactivada' y al aplicar vuelven tildadas con su cantidad.
--
-- ---- 4. el monto de la obra refleja solo lo tildado
--
--   select calcular_presupuesto_vivo_obra('<obra_id>');
--   -- no cuenta las destildadas: `es_aplicable = true` filtra en todos los agregados
--
-- ---- 5. los identificadores no cambiaron (el cascade de la 0028 nunca se dispara)
--
--   -- anotar antes:  select id, subitem_id from obra_subitems where obra_id = '<obra_id>';
--   -- después: los id tienen que ser LOS MISMOS, incluidas las destildadas.
--
-- ---- 6. las reglas que no cambiaron
--
--   -- con un certificado emitido: bloqueado = true, y reemplazar_... corta con el mensaje.
--   -- con la obra congelada sin emitir: descongela = true, y después de aplicar
--   --   presupuesto_congelado_en queda en null y presupuesto_subitems_congelado vacío.
--
-- ---- 7. no quedan partidas huérfanas en la carpeta
--
--   select count(*) from subitems s
--   where s.obra_id = '<obra_id>'
--     and not exists (select 1 from obra_subitems os where os.subitem_id = s.id);
--   -- 0: las que la revisión creó de más se limpian al conservar la existente
