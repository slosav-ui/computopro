-- 190,67 horas mensuales (44 hs semanales del convenio × 52,14 semanas/año ÷ 12) reemplaza el
-- default de 176 ("Horas Mes según convenio 176" de la planilla de la liquidadora), que asume un
-- mes de 4 semanas exactas y subestima el mes real en ~8%. 190,67 se explica en una línea y
-- cualquiera con la jornada del convenio lo verifica; 176 no tiene esa trazabilidad. La dirección
-- del error importa: 176 da un valor hora más alto, así que este cambio corrige hacia el lado que
-- no sobrecotiza sin fundamento. Se evaluó ocultar el campo en vez de cambiar el default —
-- descartado: la jornada varía de verdad entre empresas y esconder un número que no se puede
-- justificar no lo arregla, solo le saca al usuario la forma de corregirlo.
-- Ver docs/costo_mano_de_obra_decisiones.md §15.
--
-- horas_improductivas_mensuales pasa de 14,41 a 15,62 — no es un dato nuevo verificado, es el
-- 14,41 original (origen desconocido, calculado sobre el mes de 176) escalado proporcionalmente al
-- mes más largo: 14.41 * 190.67 / 176 = 15.62. Dejarlo en 14,41 con un mes de 190,67 contaría menos
-- paradas de las reales. La pregunta a la liquidadora sobre el origen de ambos números sigue
-- pendiente (§1, §10) — si 176 ya trae feriados/paradas descontados, 14,41 estaría duplicando el
-- descuento y habría que revisar esto de nuevo.
--
-- IMPORTANTE para la próxima migración que toque un default de esta tabla: el panel de "Ajustar
-- cargas sociales" muestra "por defecto X" para estos 7 campos desde un archivo de constantes Dart
-- (todavía no existe al momento de esta migración — se crea en el paso siguiente de esta misma
-- pieza, ver docs/costo_mano_de_obra_decisiones.md §15/§16; se descartó leer el default en vivo
-- desde el catálogo de Postgres por desproporcionado para lo que resuelve). Ese archivo NO se
-- actualiza solo — cualquier `alter column ... set default` futuro sobre esta tabla tiene que
-- actualizarlo también a mano, o el "por defecto X" queda mostrando un valor viejo.

alter table obra_presupuesto_config
  alter column horas_mensuales set default 190.67,
  alter column horas_improductivas_mensuales set default 15.62;

-- Dos UPDATE independientes, no uno combinado: son parámetros independientes (un PRO puede haber
-- tocado uno sin el otro, ver el panel de "Ajustar cargas sociales"), así que cada columna se
-- actualiza solo en las filas que todavía tienen SU PROPIO default viejo, sin pisar una
-- personalización real del otro campo.
--
-- Guarda explícita en el segundo UPDATE contra el check de 0044
-- (horas_mensuales > horas_improductivas_mensuales) en vez de asumir el margen de las filas
-- existentes, que no se puede verificar desde acá: horas_mensuales > 15.62 tiene que cumplirse en
-- el momento de este UPDATE, sin importar en qué orden corran las dos sentencias ni qué valor
-- tenga horas_mensuales en cada fila.
update obra_presupuesto_config
  set horas_mensuales = 190.67
  where horas_mensuales = 176;

update obra_presupuesto_config
  set horas_improductivas_mensuales = 15.62
  where horas_improductivas_mensuales = 14.41
    and horas_mensuales > 15.62;
