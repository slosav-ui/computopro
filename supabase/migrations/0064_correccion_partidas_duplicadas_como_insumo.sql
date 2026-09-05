-- Corrige tres insumos del catálogo que en realidad eran partidas ejecutadas en obra (o, en el
-- caso de SUSPENDIDO TRADICIONAL, un nombre mal copiado de la partida al cargar la estructura de
-- soporte real) -- ver el relevamiento de esta pieza para el diagnóstico completo, esta migración
-- solo aplica lo ya decidido con Seba, no repite el razonamiento.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

-- =====================================================================
-- Sección 1 -- SUSPENDIDO TRADICIONAL: se RENOMBRA, no se borra sin reasignar
-- =====================================================================
--
-- No era un duplicado de la partida 16.2 -- era la estructura principal de sostén del cielorraso
-- (alfajías 2"x2", una cada 40cm -> 2,8 ML/m2), con el nombre de la partida copiado por error al
-- cargar en vez del insumo real. Confirmado por Seba contra el resto de la composición (ya tiene
-- las alfajías cruzadas de 1"x2" como capa inferior, 2.2 ML) y contra el propio rendimiento (2,8
-- ML/m2 = una estructura cada 40cm).
--
-- Se reasigna la fila de apu_composicion_items de 16.2 al insumo real (mismo rendimiento, 2.8 --
-- no cambia, ya estaba bien) y recién después se borra el insumo viejo, que queda sin ninguna
-- referencia.

update apu_composicion_items
set insumo_id = (select id from insumos where nombre = 'ALFAJIAS 2”X2” CEPILLADAS' and creador_usuario_id is null)
where insumo_id = (
    select id from insumos
    where nombre = 'SUSPENDIDO TRADICIONAL (CAL/YESO S/ METAL DESPLEGADO)' and creador_usuario_id is null
  )
  and apu_composicion_id = (
    select ac.id from apu_composiciones ac
    join subitems s on s.id = ac.subitem_id
    where s.codigo = '16.2' and s.creador_usuario_id is null and ac.creador_usuario_id is null
  );

-- =====================================================================
-- Sección 2 -- HORMIGÓN DE PENDIENTE y CARPETA DE NIVELACIÓN: se reemplazan por materiales reales
-- =====================================================================
--
-- Salen de 15.1 y 15.2 (Cubiertas Planas) y se reemplazan por las recetas que ya existen para el
-- mismo concepto en 11.4 (CONTRAPISO DE MATERIAL AISLANTE con perlas de EPS -- receta real: cemento
-- 15 + bolsas de perlas de EPS x170L 0.3, por m3) y 9.3 (CARPETA HIDROFUGA -- receta real: cemento
-- 7 + arena 0.15 + hidrofugo 0.5, por m3), escaladas al rendimiento que ya tenían 15.1/15.2 (0.08 y
-- 0.025 m3 respectivamente). Mano de obra NO se agrega -- Seba confirmó que la de 15.1/15.2 ya
-- contempla ejecutar estas dos capas, agregarla de nuevo la duplicaría.
--
-- CEMENTO PORTLAND X 25KG se combina en una sola línea por partida (1.2 de hormigón de pendiente +
-- 0.175 de carpeta = 1.375) en vez de dos líneas separadas del mismo insumo -- dos filas del mismo
-- insumo en la misma composición se verían como el mismo bug que se está corrigiendo acá
-- (ComposicionApuScreen las mostraría como una línea repetida), y calcular_precio_apu_subitems suma
-- por insumo de todos modos, así que el resultado numérico es idéntico.

delete from apu_composicion_items
where apu_composicion_id in (
    select ac.id from apu_composiciones ac
    join subitems s on s.id = ac.subitem_id
    where s.codigo in ('15.1', '15.2') and s.creador_usuario_id is null and ac.creador_usuario_id is null
  )
  and insumo_id in (
    select id from insumos
    where nombre in ('HORMIGÓN DE PENDIENTE (CASCOTE/PERLA EPS)', 'CARPETA DE NIVELACIÓN 1:3 CON HIDRÓFUGO')
      and creador_usuario_id is null
  );

insert into apu_composicion_items (apu_composicion_id, tipo_componente, insumo_id, rendimiento)
select ac.id, 'material', i.id, v.rendimiento
from (values
  ('15.1', 'CEMENTO PORTLAND X 25KG', 1.375),
  ('15.1', 'BOLSAS DE PERLAS DE EPS X 170 LITROS', 0.024),
  ('15.1', 'ARENA', 0.00375),
  ('15.1', 'HIDROFUGO', 0.0125),
  ('15.2', 'CEMENTO PORTLAND X 25KG', 1.375),
  ('15.2', 'BOLSAS DE PERLAS DE EPS X 170 LITROS', 0.024),
  ('15.2', 'ARENA', 0.00375),
  ('15.2', 'HIDROFUGO', 0.0125)
) as v(codigo, insumo_nombre, rendimiento)
join subitems s on s.codigo = v.codigo and s.creador_usuario_id is null
join apu_composiciones ac on ac.subitem_id = s.id and ac.creador_usuario_id is null
join insumos i on i.nombre = v.insumo_nombre and i.creador_usuario_id is null;

-- =====================================================================
-- Sección 3 -- Borrado de los 3 insumos, ya sin ninguna referencia
-- =====================================================================
--
-- Defensivo: cada DELETE solo aplica si, en el momento de correr esto, no queda ninguna fila que lo
-- referencie en apu_composicion_items, precios ni obra_insumo_precios -- mismo criterio que 0049
-- con Hierro del 12mm (verificar las 3 tablas, no asumir). Si algo saliera mal en las secciones de
-- arriba (por ejemplo, si algún WHERE no matcheó y la reasignación no corrió), el DELETE
-- correspondiente simplemente no hace nada -- no hay riesgo de borrar un insumo que siga en uso.

delete from insumos
where nombre in (
    'SUSPENDIDO TRADICIONAL (CAL/YESO S/ METAL DESPLEGADO)',
    'HORMIGÓN DE PENDIENTE (CASCOTE/PERLA EPS)',
    'CARPETA DE NIVELACIÓN 1:3 CON HIDRÓFUGO'
  )
  and creador_usuario_id is null
  and not exists (select 1 from apu_composicion_items where insumo_id = insumos.id)
  and not exists (select 1 from precios where insumo_id = insumos.id)
  and not exists (select 1 from obra_insumo_precios where insumo_id = insumos.id);

-- =====================================================================
-- Verificación
-- =====================================================================

-- 1) Los 3 insumos ya no existen en el catálogo.
select nombre from insumos
where nombre in (
  'SUSPENDIDO TRADICIONAL (CAL/YESO S/ METAL DESPLEGADO)',
  'HORMIGÓN DE PENDIENTE (CASCOTE/PERLA EPS)',
  'CARPETA DE NIVELACIÓN 1:3 CON HIDRÓFUGO'
);
-- esperado: 0 filas. Si aparece alguno, el DELETE no corrió (todavía tiene una referencia en algún
-- lado) -- no reintentar a ciegas, revisar cuál de las 3 tablas la tiene.

-- 2) La composición completa de 16.2 -- confirmar que ALFAJIAS 2"X2" CEPILLADAS aparece con
--    rendimiento 2.8, junto a la de 1"X2" CRUZADAS con 2.2 (las dos, no una reemplazando a la otra).
select i.nombre, aci.rendimiento
from apu_composicion_items aci
join apu_composiciones ac on ac.id = aci.apu_composicion_id
join subitems s on s.id = ac.subitem_id
join insumos i on i.id = aci.insumo_id
where s.codigo = '16.2' and ac.creador_usuario_id is null
order by i.nombre;

-- 3) La composición completa de 15.1 y 15.2 -- confirmar las 4 líneas nuevas de material en cada
--    una, sin ninguna línea de HORMIGÓN DE PENDIENTE ni CARPETA DE NIVELACIÓN.
select s.codigo, i.nombre, aci.rendimiento
from apu_composicion_items aci
join apu_composiciones ac on ac.id = aci.apu_composicion_id
join subitems s on s.id = ac.subitem_id
join insumos i on i.id = aci.insumo_id
where s.codigo in ('15.1', '15.2') and ac.creador_usuario_id is null
order by s.codigo, i.nombre;

-- 4) Ningún apu_composicion_items queda huérfano (mismo chequeo de siempre).
select count(*) as huerfanos
from apu_composicion_items ci
left join insumos i on i.id = ci.insumo_id
where i.id is null;

-- 5) calcular_precio_apu_subitems sigue funcionando para 15.1/15.2/16.2 después del cambio (no
--    tiene que tirar error -- solo confirma que las 3 partidas siguen resolviendo, no que den
--    completo, eso depende de que el resto de sus insumos tengan precio).
-- select * from calcular_precio_apu_subitems(
--   '<obra_id>'::uuid,
--   array[
--     (select id from subitems where codigo = '15.1' and creador_usuario_id is null),
--     (select id from subitems where codigo = '15.2' and creador_usuario_id is null),
--     (select id from subitems where codigo = '16.2' and creador_usuario_id is null)
--   ]
-- );
