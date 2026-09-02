-- Costo de mano de obra — columna zona_uocra en obra_presupuesto_config. Falta antes de escribir
-- la función de valor hora (Paso 3): escala_salarial_uocra.zona admite varias zonas (hoy solo hay
-- una fila cargada, 'B'), y sin esta columna la función tendría que hardcodear 'B' para toda obra.
--
-- Por qué se agrega ahora en vez de esperar a que exista una segunda zona: hardcodear la zona
-- fallaría en silencio el día que se cargue otra — la función devolvería valores de Zona B para
-- una obra de otra región sin ningún error ni warning, números plausibles y equivocados. Mismo
-- modo de falla que ya se evitó dos veces en esta pieza: por eso el vínculo insumos↔escala es por
-- código y no por nombre (0036), y por eso FICS/IERIC/FODECO/UOCRA empleador viven como columna y
-- no como constante (0036). El criterio no cambia porque hoy haya una sola zona cargada.
--
-- Va al lado de zona_sismorresistente: son dos zonificaciones distintas que no se mezclan (una es
-- para diseño estructural, ésta es para escala salarial), pero conceptualmente las dos son
-- "parámetros de la obra" y viven en la misma fila para que la función siga leyendo un solo
-- registro.
--
-- Sin `check` sobre valores a propósito: las zonas UOCRA son varias y no están relevadas todavía.
-- La integridad la da la propia tabla escala_salarial_uocra — si zona_uocra no matchea ninguna
-- fila, la función de valor hora (próximo paso, no éste) tiene que fallar con un mensaje claro
-- (raise exception), nunca devolver NULL o cero en silencio.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.
--
-- No hace falta tocar handle_new_obra_presupuesto() (0020): hereda el default solo. El trigger
-- set_updated_at_obra_presupuesto_config (0035) ya cubre esta tabla.

alter table obra_presupuesto_config
  add column zona_uocra text not null default 'B';
