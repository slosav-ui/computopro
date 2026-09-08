-- Corrige tres obras con monto_total contaminado por un bug real del alta de obra, y el propio
-- bug en el código (fix separado, en Dart: lib/presentation/dashboard/obras_list_screen.dart).
--
-- CAUSA RAÍZ (confirmada leyendo el código, no asumida): el diálogo de alta de obra tenía una
-- fórmula "estimación de arranque" -- monto_total = superficie × 1.000.000 ARS/m² (o × 750 USD/m²)
-- -- que se ejecutaba SIEMPRE al crear una obra, sin que el usuario la pidiera ni la viera. No era
-- el campo de superficie escribiendo por error en el campo de monto -- era una fórmula deliberada
-- que convertía la superficie en un monto inventado. Sacada de raíz en el mismo commit que esta
-- migración (obras_list_screen.dart): el alta ahora manda monto_total = 0 siempre, sin excepción.
--
-- LAS TRES OBRAS, reconstruidas con aritmética exacta contra la fórmula de arriba -- ninguna
-- vino de un cómputo real:
--
-- 1. Galpón Mix (2026-09-08, 200.000.000 ARS): 200 × 1.000.000 = 200.000.000. Coincide exacto con
--    la superficie que Seba reportó haber tipeado (200 m²). Caso directo, moneda ARS.
--
-- 2. OBRE PRUEBA 2 (2026-09-01, 69.000): 92 × 750 = 69.000 exacto. Caso directo, moneda USD --
--    mismo bug, sin ningún paso intermedio.
--
-- 3. OBRA PRUEBA 3 (2026-09-01, 38.095,238095238090): esta pasó por DOS bugs encadenados, no uno
--    solo. 52 × 1.000.000 = 52.000.000 ARS (mismo bug de alta). Después, alguien cambió la moneda
--    de esa obra a USD desde el diálogo "Ajuste Económico" (obras_list_screen.dart, función
--    _convertirMonto), que divide por la cotización activa -- 1.365 (promedio BNA hardcodeado,
--    ($1.340+$1.390)/2, obras_list_screen.dart:19-22) en su valor default:
--      52.000.000 / 1.365 = 38.095,238095238095238... -- coincide al dígito con el valor real.
--    _convertirMonto en sí no tiene ningún bug -- convierte bien lo que recibe. El problema es que
--    lo que recibió ya estaba mal desde el alta; convertir un número inventado da otro número
--    inventado, con más decimales.
--
-- Las tres se corrigen a 0 -- ninguna tiene un cómputo real detrás que permita recalcular un monto
-- verdadero (son obras de prueba, "PRUEBA" en el nombre de dos de las tres, y Galpón Mix es de
-- ayer). Si alguna sí tiene subitems cargados con cantidad y precio reales, correr la consulta de
-- abajo ANTES del UPDATE para confirmarlo -- si aparece algo, avisar antes de pisarlo con 0.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado automáticamente
-- por Claude Code: sin acceso a la base de datos desde este entorno.

-- =====================================================================
-- Paso 0 — verificación previa: ¿alguna de las tres tiene cómputo real cargado?
-- =====================================================================
--
-- Si esto devuelve alguna fila con cantidad > 0, PARAR -- esa obra puede tener un monto real
-- recalculable desde calcular_monto_obra_subitems, no simplemente ponerla en 0.

select o.nombre, os.id as obra_subitem_id, os.cantidad, os.es_aplicable
from obras o
join obra_subitems os on os.obra_id = o.id
where o.nombre in ('Galpón Mix', 'Galpon Mix', 'OBRA PRUEBA 3', 'OBRE PRUEBA 2')
  and os.cantidad > 0;

-- =====================================================================
-- Paso 1 — corrección (solo si el paso 0 no devolvió filas)
-- =====================================================================
--
-- Match por nombre Y monto_total actual (no solo nombre) -- mismo criterio de seguridad que ya se
-- usó en 0086 para la boquilla: si el monto ya no coincide con el valor reportado (alguien lo tocó
-- entre medio), el UPDATE no afecta esa fila en vez de pisar un valor que ya cambió.

update obras set monto_total = 0
where nombre in ('Galpón Mix', 'Galpon Mix') and monto_total = 200000000;

update obras set monto_total = 0
where nombre = 'OBRE PRUEBA 2' and monto_total = 69000;

update obras set monto_total = 0
where nombre = 'OBRA PRUEBA 3' and round(monto_total, 6) = 38095.238095;

-- =====================================================================
-- Verificación
-- =====================================================================

-- 1) Las tres tienen que dar monto_total = 0 ahora.
select nombre, monto_total, moneda, created_at
from obras
where nombre in ('Galpón Mix', 'Galpon Mix', 'OBRA PRUEBA 3', 'OBRE PRUEBA 2')
order by created_at desc;

-- 2) Ninguna otra obra debería tener un monto "redondo sospechoso" del mismo patrón (múltiplo
--    exacto de 1.000.000 o de 750) -- si aparece algo acá, es la misma fuga en una obra que no
--    estaba en la lista reportada.
select nombre, monto_total, moneda, superficie_m2, created_at
from obras
where (moneda = 'ARS' and monto_total > 0 and mod(monto_total, 1000000) = 0)
   or (moneda = 'USD' and monto_total > 0 and mod(monto_total, 750) = 0)
order by created_at desc;
