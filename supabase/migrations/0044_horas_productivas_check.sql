-- Costo de mano de obra — Paso 5, tanda 2: el panel de 7 parámetros vuelve alcanzable por primera
-- vez que un PRO cargue horas_improductivas_mensuales >= horas_mensuales, dejando
-- horas_productivas en cero o negativo — calcular_valor_hora_mano_obra divide por ese número
-- (v_horas_productivas := horas_mensuales - horas_improductivas_mensuales). El problema existe
-- desde 0036, pero hasta ahora nada escribía estas columnas desde la app — este panel es lo que
-- lo vuelve alcanzable. Ver docs/costo_mano_de_obra_decisiones.md §15.
--
-- Doble capa, mismo criterio que insumos_mano_obra_requiere_categoria (0042): validación en Dart
-- al guardar (mensaje de error inmediato) + este check como red de seguridad en la base.
--
-- Verificado antes de escribir esta migración: ningún archivo de lib/ lee ni escribe
-- horas_mensuales/horas_improductivas_mensuales (grep sin resultados) — las 3 obras existentes
-- siguen en los defaults de 0036 (176 / 14,41), que cumplen el check. Postgres valida contra las
-- filas existentes al agregar el constraint — si alguna no cumpliera, este ALTER TABLE falla solo,
-- con el nombre de la constraint en el error.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

alter table obra_presupuesto_config
  add constraint obra_presupuesto_config_horas_productivas_positivas check (
    horas_mensuales > horas_improductivas_mensuales
  );
