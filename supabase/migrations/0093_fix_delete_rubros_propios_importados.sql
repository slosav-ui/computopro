-- Bug real reportado por Seba: un rubro propio creado por el importador no se puede borrar desde
-- el ícono de basura en RubrosTab. Los subítems propios de ese mismo rubro SÍ se borran bien --
-- confirmado por Seba -- así que no es "el rubro todavía tiene subítems adentro": ese candidato
-- queda descartado, subitems.rubro_id ya tiene `on delete cascade` (0016) y funciona.
--
-- CAUSA RAÍZ: exactamente el mismo bug que 0088_fix_delete_subitems_propios.sql, en la columna
-- hermana de la MISMA tabla que esa migración ya tocó -- `importaciones_items.rubro_id`
-- (0081_confirmar_importacion.sql:14) quedó con la FK en `ON DELETE NO ACTION` (default de
-- Postgres) mientras `subitem_id`, dos líneas más abajo en el mismo archivo, se corrigió a `SET
-- NULL`. Un rubro creado vía "crear como propio" del importador SIEMPRE tiene al menos una fila de
-- `importaciones_items` apuntándolo con ese `rubro_id` -- es la fila que registra que esa línea del
-- Excel se resolvió creando justamente ese rubro. Por eso el borrado falla con 23503 antes incluso
-- de llegar a la cascada de `subitems` -- Postgres evalúa esta FK primero.
--
-- Repasadas las demás tablas que referencian `rubros(id)` (`subitems`, `obra_subitems`,
-- `obra_rubros_orden`) -- las tres ya tienen `on delete cascade` (0016/0028/0026). Esta es la única
-- que quedó pendiente.
--
-- POR QUÉ "SET NULL" Y NO "CASCADE": mismo motivo que 0088 para `subitem_id` de esta misma tabla --
-- `importaciones_items` es un registro histórico de qué decía cada línea del Excel original
-- (`rubro_texto`/`descripcion_texto`/`datos_originales` sobreviven aparte del `rubro_id` resuelto,
-- 0080_importaciones.sql), no tiene sentido perder esa fila completa solo porque el rubro que
-- generó ya no existe. `rubro_id` ya es nullable (0080), sin necesidad de ALTER adicional.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado automáticamente
-- por Claude Code: sin acceso a la base de datos desde este entorno.

alter table importaciones_items
  drop constraint importaciones_items_rubro_id_fkey;

alter table importaciones_items
  add constraint importaciones_items_rubro_id_fkey
  foreign key (rubro_id) references rubros(id) on delete set null;

-- =====================================================================
-- Verificación
-- =====================================================================

-- 1) La FK muestra ON DELETE SET NULL (confdeltype 'n') en vez de NO ACTION ('a').
-- select conrelid::regclass as tabla, conname, confdeltype
-- from pg_constraint
-- where conname = 'importaciones_items_rubro_id_fkey';

-- 2) Caso real: borrar desde RubrosTab un rubro propio creado por el importador (uno que ya haya
--    tenido sus subítems borrados, o uno recién creado) -- tiene que desaparecer sin error, con el
--    mensaje de error real (si lo hubiera) visible en la consola de Flutter, no un genérico.
--    Confirmar después que la fila de importaciones_items que lo originó SIGUE existiendo, con
--    rubro_id ahora en null:
-- select id, rubro_texto, rubro_id from importaciones_items where importacion_id = '<id>';
