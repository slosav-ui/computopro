-- Carga de 4 precios de referencia de mercado (no cotizaciones de corralón), cerrados con Seba
-- antes del documento de "Unificación de duplicados" de 0066: los tres productos de la familia
-- cerámico/porcelanato quedan con precio propio cada uno (no se unifican entre sí -- son productos
-- distintos, la relación de precio entre porcelanato y cerámico mediano ya se verificó en ~2,15),
-- y el impregnante/barniz base solvente (ya unificado en 0066, sobreviviente sin precio hasta
-- ahora) toma como referencia el precio real de BARNIZ (HIZA, 0065) -- mismo material base, el
-- lasur penetra y el barniz forma película pero la app no distingue esa diferencia técnica en el
-- costo del insumo.
--
-- Van bajo 'Cantera privada (referencia)' (creada en 0063 para PIEDRA), no bajo Sólido/Felemax/SB
-- Maderas/HIZA -- ninguno de estos 4 valores es una cotización real, mismo criterio que PIEDRA.
-- Nota de nomenclatura, no bloqueante: ese nombre es específico de áridos/cantera y le queda
-- forzado a cerámicos y barniz -- si en algún momento se agrega una columna que distinga precio
-- cotizado de precio de referencia (gap ya anotado en docs/confianza_precios_diseno.md), tiene
-- sentido revisar si conviene un nombre más genérico para el corralón en vez de uno por rubro.
--
-- fecha_actualizacion: 05/09/2026, misma fecha en que Seba cerró estos 4 valores.
--
-- Depende de 0066 (IMPREGNANTE / BARNIZ BASE SOLVENTE (3 MANOS) tiene que existir como
-- sobreviviente del merge de esa migración antes de este INSERT) y de 0063 (corralón de
-- referencia) ya aplicadas.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor), después de 0066. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

insert into precios (insumo_id, corralon_id, valor, fecha_actualizacion)
select i.id, c.id, v.valor, '2026-09-05'
from (values
  ('CERAMICO MEDIANO', 19575.0),
  ('PORCELANATO', 43200.0),
  ('SOLADO CERÁMICO / PORCELLANATO DE EXTERIOR', 45900.0),
  ('IMPREGNANTE / BARNIZ BASE SOLVENTE (3 MANOS)', 13366.0)
) as v(insumo_nombre, valor)
join insumos i on i.nombre = v.insumo_nombre and i.creador_usuario_id is null
join corralones c on c.nombre = 'Cantera privada (referencia)'
where not exists (
  select 1 from precios p
  where p.insumo_id = i.id and p.corralon_id = c.id
);

-- =====================================================================
-- Verificación
-- =====================================================================

-- 1) Las 4 filas nuevas, con el corralón de referencia y el valor esperado.
select i.nombre as insumo, c.nombre as corralon, p.valor, p.fecha_actualizacion
from precios p
join insumos i on i.id = p.insumo_id
join corralones c on c.id = p.corralon_id
where c.nombre = 'Cantera privada (referencia)'
order by i.nombre;

-- 2) calcular_precio_promedio_insumo ya resuelve para los 4 (cantidad_corralones = 1 en cada uno,
--    salvo que alguno ya tuviera otro precio real cargado antes -- no debería, ver chequeo previo).
select i.nombre, pr.promedio, pr.minimo, pr.maximo, pr.cantidad_corralones
from insumos i
cross join lateral calcular_precio_promedio_insumo(i.id) pr
where i.nombre in ('CERAMICO MEDIANO', 'PORCELANATO', 'SOLADO CERÁMICO / PORCELLANATO DE EXTERIOR', 'IMPREGNANTE / BARNIZ BASE SOLVENTE (3 MANOS)');

-- 3) La relación de precio porcelanato/cerámico mediano sigue en el rango verificado (~2,15).
select 43200.0 / 19575.0 as relacion_porcelanato_ceramico;
