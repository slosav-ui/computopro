-- Costo de mano de obra — columna suelta que faltó en la 0036: vacaciones_jornales_mes en
-- obra_presupuesto_config. Se necesita para reproducir la fila "Vacaciones" de docs/seed/
-- costo_laboral_uocra.xlsx (hoja "Calculo", filas D10/H10) en la función de valor hora del Paso 3.
--
-- Por qué es columna editable por PRO y NO va al bucket "no editable pero aplicada" (FICS/IERIC/
-- FODECO/obra_social_patronal_pct/uocra_empleador_pct de la 0036): esas cinco son alícuotas fijas
-- por normativa, ninguna empresa las puede variar. Ésta no — 1 jornal/mes son 12 jornales/año
-- (~14 días), que es la licencia que corresponde con antigüedad menor a 5 años (Ley 20.744
-- art. 150). Con personal de 5 a 10 años son 21 días y el valor pasa a 1,5; con más antigüedad,
-- más. No depende solo de una política de empresa, depende de la antigüedad promedio de su
-- personal, que varía de una empresa a otra — mismo tipo de parámetro que
-- horas_improductivas_mensuales (0036), que ya quedó editable.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.
--
-- No hace falta tocar handle_new_obra_presupuesto() (0020_obra_presupuesto_config.sql): ese
-- trigger inserta la fila sin listar columnas, hereda el default solo. El trigger
-- set_updated_at_obra_presupuesto_config (0035) ya cubre esta tabla.

alter table obra_presupuesto_config
  add column vacaciones_jornales_mes numeric not null default 1 check (vacaciones_jornales_mes >= 0);
