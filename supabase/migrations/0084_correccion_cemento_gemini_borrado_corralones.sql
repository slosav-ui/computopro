-- Registro de una corrección ya aplicada a mano por Seba (queda acá solo para que el historial de
-- supabase/migrations/ tenga el cambio documentado, no para volver a ejecutarla con efecto real).
--
-- Encontrado al revisar los 2 corralones que sobrevivieron a la limpieza de 0083 (Corralón del
-- Valle, Materiales Neuquén Capital -- no eran duplicados entre sí, así que 0083 no los tocó):
-- ambos tenían CEMENTO PORTLAND X 25KG cargado en la unidad KG a $9.500 y $8.900 respectivamente --
-- el precio de la BOLSA puesto directo en la unidad del kilo, sin dividir por 25. El precio real
-- ronda los $416/kg entre los 4 proveedores reales -- estos dos estaban ~8 veces arriba, e inflaban
-- el promedio de cemento (y por lo tanto toda partida que lo usa) cada vez que se calculaba.
--
-- Origen: carga vieja de la sesión de Gemini, fuera del flujo de migraciones (mismo bloque de 6
-- tablas de proveedores que ya documenta CLAUDE.md) -- ninguna migración tocada por Claude Code
-- cargó nunca precios bajo estos dos nombres.
--
-- Seba borró los precios y los dos corralones enteros a mano en el SQL Editor -- no quedaba nada
-- más que rescatar de ellos (0083 ya había confirmado que no tenían otros precios reales colgando,
-- y no eran parte de los 6 proveedores reales del catálogo).
--
-- Los DELETE de abajo son naturalmente idempotentes -- si ya no existe nada que borrar, afectan 0
-- filas, sin error. No ejecutada automáticamente por Claude Code: sin acceso a la base de datos
-- desde este entorno, y de hecho innecesaria -- el cambio ya está aplicado.

delete from precios
where corralon_id in (
  select id from corralones
  where nombre in ('Corralón del Valle', 'Materiales Neuquén Capital')
);

delete from corralones
where nombre in ('Corralón del Valle', 'Materiales Neuquén Capital');

-- =====================================================================
-- Verificación
-- =====================================================================

-- 1) Tienen que quedar 6 corralones -- los reales (Sólido, HIZA, Felemax, SB Maderas, Casa Palm,
--    Cantera privada [referencia]).
select count(*) as total_corralones from corralones;
select nombre from corralones order by nombre;

-- 2) CEMENTO PORTLAND X 25KG: banda de precio esperada entre los proveedores reales, sin ningún
--    valor fuera de rango (nada cerca de 8.000-9.500).
select c.nombre as corralon, p.valor
from precios p
join insumos i on i.id = p.insumo_id
join corralones c on c.id = p.corralon_id
where i.nombre = 'CEMENTO PORTLAND X 25KG'
order by p.valor;
