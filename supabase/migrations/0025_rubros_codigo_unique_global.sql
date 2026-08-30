-- Validación de código duplicado en rubros — cierra el hallazgo de la sesión anterior: el único
-- índice único que tenía la tabla (rubros_codigo_oficial_unique, 0015_rubros.sql) es parcial,
-- `where creador_usuario_id is null`, así que nunca cubrió los rubros custom de un PRO. Dos rubros
-- custom con el mismo código, o un custom con el mismo código que un oficial, convivían sin error.
--
-- Decisión de negocio del usuario: la unicidad de `codigo` es GLOBAL, no solo dentro del catálogo
-- oficial — el motivo es el presupuesto impreso, donde dos ítems con el mismo número confunden al
-- cliente. Se reemplaza el índice parcial por uno global que lo cubre por completo: todo lo que
-- bloqueaba el parcial, lo sigue bloqueando el global, no se pierde ninguna protección existente.
--
-- Esto es la mitad "constraint en la base" de la validación; la mitad "mensaje claro al usuario
-- antes de llegar acá" vive en RubrosTab._mostrarDialogoAltaRubro (Dart), que ya chequea el
-- catálogo combinado (oficiales + propios) antes de intentar el insert. Este índice es la red de
-- seguridad final, no la única barrera — cubre el caso de que un código duplicado entre por otro
-- camino (otro cliente de la API, o un bug futuro que salte la validación de Dart).
--
-- Precondición para poder aplicar esta migración: no debe existir ya ningún código repetido en la
-- tabla, o el `create unique index` de abajo falla. Al momento de escribir esto no debería haberlo
-- (el único rubro custom creado hasta ahora, "21 - PARQUIZADO", no repite ningún código oficial) —
-- si de todas formas falla al aplicar, correr primero:
--   select codigo, count(*) from rubros group by codigo having count(*) > 1;
-- para encontrar el duplicado real y resolverlo a mano antes de reintentar.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

drop index rubros_codigo_oficial_unique;

create unique index rubros_codigo_unique on rubros (codigo);
