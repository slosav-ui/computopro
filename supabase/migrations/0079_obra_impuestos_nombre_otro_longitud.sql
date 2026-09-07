-- Última pieza del Factor K: editar los 4 porcentajes de impuestos (IVA/IIBB/Tasas/el cuarto,
-- hoy fijos en 21/3/1.5/0 sin forma de tocarlos desde ningún lado -- PanelEditarFactorK solo edita
-- los 6 conceptos de obra_presupuesto_config, nunca tocó obra_impuestos). Diagnóstico completo en
-- la conversación, no hay doc nuevo en docs/ para esta pieza puntual todavía (se suma cuando se
-- construya PanelEditarImpuestos, junto con el resto de los archivos de esta pieza).
--
-- Esta migración es la única pieza de schema que hace falta -- "uno solo, no se borra" (ver
-- diagnóstico): el cuarto impuesto ("Otro") se resuelve reusando la fila que el trigger de 0020 ya
-- siembra en cada obra (tipo = 'otro', nombre_otro null, porcentaje 0), sin agregar filas nuevas ni
-- políticas de INSERT/DELETE -- "agregar impuesto" es tipear nombre_otro/porcentaje en esa misma
-- fila vía UPDATE, que la RLS ya permite desde 0020. `unique(obra_id, tipo)` sigue sin tocarse:
-- sigue habiendo como máximo una fila `tipo = 'otro'` por obra, a propósito.
--
-- Lo único que faltaba: nombre_otro es `text` sin límite de longitud desde que se creó (0020) --
-- nunca importó porque nunca se escribía desde la app. Ahora que un PRO va a tipear un nombre libre
-- que se muestra en una línea de la pantalla (y potencialmente en un presupuesto exportado más
-- adelante), un nombre sin límite puede romper el layout. El límite real (evitar que se tipee algo
-- larguísimo) queda en el `TextField` de `PanelEditarImpuestos` (`maxLength`) -- este `check` es la
-- red de seguridad del lado de la base, mismo criterio que ya tiene esta columna con
-- `obra_impuestos_nombre_otro_solo_en_otro` (0020): esa constraint protege una regla de esta misma
-- columna a nivel de base, esta agrega la otra.
--
-- 40 caracteres: alcanza para un nombre real ("Tasa de Seguridad e Higiene Municipal" son 38) sin
-- ser tan corto que fuerce abreviaturas raras.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor), después de 0078. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

alter table obra_impuestos
  add constraint obra_impuestos_nombre_otro_longitud
  check (nombre_otro is null or char_length(nombre_otro) <= 40);

-- =====================================================================
-- Verificación
-- =====================================================================
--
-- 1) Un nombre dentro del límite tiene que aceptarse -- reusa la fila 'otro' ya sembrada por el
--    trigger de 0020, no inserta ninguna fila nueva.
-- update obra_impuestos
-- set nombre_otro = 'Tasa de Seguridad e Higiene', porcentaje = 2.5
-- where obra_id = '<obra_id>'::uuid and tipo = 'otro';

-- 2) Un nombre de más de 40 caracteres tiene que rechazarse con la violación de este check, no
--    guardarse truncado ni en silencio.
-- update obra_impuestos
-- set nombre_otro = 'Un nombre de impuesto deliberadamente larguísimo para probar el límite'
-- where obra_id = '<obra_id>'::uuid and tipo = 'otro'; -- tiene que fallar

-- 3) "Quitar" el cuarto impuesto es vaciar el nombre, no un DELETE -- confirmar que sigue siendo
--    la misma fila (mismo id) antes y después.
-- update obra_impuestos
-- set nombre_otro = null, porcentaje = 0
-- where obra_id = '<obra_id>'::uuid and tipo = 'otro';
