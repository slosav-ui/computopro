-- Bug real reportado por Seba: los subítems propios creados por el importador no se pueden
-- borrar desde SubitemsScreen -- el ícono de basura existe y está bien conectado (verificado
-- código por código: RLS subitems_delete ya exige creador_usuario_id = auth.uid(), y
-- SubitemsRepository.eliminar()/RevisarImportacionScreen ya pasan el usuario correcto), pero el
-- DELETE falla igual.
--
-- CAUSA RAÍZ: `importaciones_items.subitem_id` tiene una foreign key hacia `subitems(id)` SIN
-- ninguna acción de borrado (0081_confirmar_importacion.sql:15) -- Postgres la trata como `ON
-- DELETE NO ACTION` por default, que bloquea el DELETE con un error 23503 si existe al menos una
-- fila que referencia esa fila. Un subítem creado vía "crear como propia" del importador SIEMPRE
-- tiene al menos una fila de `importaciones_items` apuntándolo -- es la fila que registra que esa
-- línea del Excel se resolvió creando justamente ese subítem. Por eso el bug es específico de
-- subítems del importador: uno creado a mano desde SubitemsScreen (sin pasar por el importador)
-- no tiene ninguna fila de `importaciones_items` que lo referencie, y por eso ese borra sin
-- problema -- lo que hizo más difícil notar el patrón.
--
-- El error real nunca llegaba a mostrarse: SubitemsScreen._onEliminarSubitem atrapa cualquier
-- excepción del DELETE y muestra un SnackBar genérico ("No se pudo eliminar el subítem. Probá de
-- nuevo") -- el comentario que dejaba ese catch decía explícitamente que ya no hacía falta
-- distinguir 23503 como caso especial (era cierto cuando se escribió, antes de que existiera esta
-- FK de 0081) -- quedó desactualizado, no es un bug de la UI en sí.
--
-- Mismo gap, todavía sin disparar: `modificaciones_obra.subitem_id` (0021_modificaciones_obra_
-- fks.sql) tiene la misma FK sin acción de borrado. No es lo que está bloqueando a Seba hoy (un
-- subítem recién creado por el importador no tiene ningún adicional/demasía cargado todavía), pero
-- es el mismo patrón exacto y va a producir el mismo bug el día que alguien intente borrar un
-- subítem propio que sí tenga un adicional asociado. Se corrige acá también, de una vez.
--
-- POR QUÉ "SET NULL" Y NO "CASCADE": a diferencia de obra_subitems (0028_obra_subitems_cascade_
-- propio.sql, donde SÍ corresponde cascade -- la fila de obra_subitems no tiene sentido sin su
-- subítem, es el cómputo de esa partida), acá las dos tablas guardan algo que vale la pena
-- conservar más allá del subítem: importaciones_items es un registro histórico de qué decía cada
-- fila del Excel original (columnas descripcion_texto/rubro_texto/datos_originales ya sobreviven
-- aparte del subitem_id resuelto, ver 0080_importaciones.sql), y modificaciones_obra es un
-- adicional/demasía/quita aprobado, con
-- su propio monto y descripción -- borrar el registro completo porque el subítem que lo originó
-- ya no existe sería perder historia real sin necesidad. SET NULL dispara ambas columnas (ya son
-- nullable en las dos tablas, sin necesidad de ALTER adicional) y deja el resto de la fila intacto.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado automáticamente
-- por Claude Code: sin acceso a la base de datos desde este entorno.

alter table importaciones_items
  drop constraint importaciones_items_subitem_id_fkey;

alter table importaciones_items
  add constraint importaciones_items_subitem_id_fkey
  foreign key (subitem_id) references subitems(id) on delete set null;

alter table modificaciones_obra
  drop constraint modificaciones_obra_subitem_id_fkey;

alter table modificaciones_obra
  add constraint modificaciones_obra_subitem_id_fkey
  foreign key (subitem_id) references subitems(id) on delete set null;

-- =====================================================================
-- Verificación
-- =====================================================================

-- 1) Las dos FKs muestran ON DELETE SET NULL (confdeltype 'n') en vez de NO ACTION ('a').
select conrelid::regclass as tabla, conname, confdeltype
from pg_constraint
where conname in ('importaciones_items_subitem_id_fkey', 'modificaciones_obra_subitem_id_fkey');

-- 2) Caso real: crear un subítem propio nuevo importando un Excel de prueba (o reusar uno ya
--    creado por el importador que no se haya usado en ninguna obra todavía), y borrarlo desde
--    SubitemsScreen -- tiene que desaparecer sin error. Confirmar después que la fila de
--    importaciones_items que lo originó SIGUE existiendo, con subitem_id ahora en null:
-- select id, nombre_original, subitem_id from importaciones_items where importacion_id = '<id>';
