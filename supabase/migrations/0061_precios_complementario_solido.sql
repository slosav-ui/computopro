-- Complemento de Sólido S.R.L. con dos precios que faltaban del catálogo (ver
-- supabase/seed_staging/mapeo_precios_corralones_2026-09-04.csv para el mapeo original de la carga
-- base -- este complemento no está ahí, es posterior).
--
-- Nombres tal cual figuran en la cotización, resueltos contra el catálogo real (verificado contra
-- 0022_seed_insumos_apu_rubros_2_17.sql, no de memoria):
--   "LADRILLO DE 1RA 5 X 11 X 23 XUNI 2230"       -> LADRILLOS COMUNES (linea 246 de 0022)
--   "BLOQUE LISO PORTANTE 19 X 19 X 39 PCRB20"    -> BLOQUES DE CEMENTO 19/19/39 (linea 166)
-- Los dos ya tenían precio de Felemax (0058) -- NO de HIZA, a diferencia de lo que se asumió al
-- pedir esta carga (revisadas las 13 filas de HIZA en 0058 una por una: ninguna es ladrillo ni
-- bloque). En estos dos insumos Felemax es más barato que Sólido (ladrillo $397,19 contra $450,12,
-- bloque $3.296,38 contra $3.985,74) -- al revés que el resto de Mampostería, donde Sólido gana.
--
-- Contado, con IVA incluido, sin flete -- mismas condiciones que las otras dos cotizaciones de
-- Sólido ya cargadas en 0058.
--
-- fecha_actualizacion: 05/09/2026, confirmada por Seba (un día después de las 3 cotizaciones
-- originales de 0058, que fueron del 04/09).
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor), después de 0060. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

insert into precios (insumo_id, corralon_id, valor, fecha_actualizacion)
select i.id, c.id, v.valor, '2026-09-05'
from (values
  ('LADRILLOS COMUNES', 'Sólido', 450.12),
  ('BLOQUES DE CEMENTO 19/19/39', 'Sólido', 3985.74)
) as v(insumo_nombre, corralon_nombre, valor)
join insumos i on i.nombre = v.insumo_nombre and i.creador_usuario_id is null
join corralones c on c.nombre = v.corralon_nombre;

-- =====================================================================
-- PIEDRA — deliberadamente NO incluida en este archivo
-- =====================================================================
--
-- Unidad confirmada por Seba: M3 (canto rodado). El fix de insumos.unidad (PIEDRA, y de paso
-- TABLAS/TIRANTES, mismo bug encontrado en la misma revisión) va en 0062_correccion_unidades_
-- piedra_tablas_tirantes.sql, no acá -- toca catálogo, fuera del alcance declarado para este
-- archivo ("solo INSERT en precios, sin tocar catálogo").
--
-- La carga del precio de PIEDRA en sí queda pendiente de una pregunta nueva, encontrada al
-- escribir esto -- ver el comentario de cabecera de 0062 para el detalle: no hay ningún corralón
-- real al que atribuirle este precio (es una referencia de mercado, no una cotización de Sólido,
-- Felemax, SB Maderas ni HIZA), y `precios.corralon_id` no admite null.
--
-- Recordatorio para cuando se resuelva: ese precio es SIN IVA (a diferencia de los 124+2 ya
-- cargados, todos con IVA) -- decisión explícita de Seba, sabiendo que deja a PIEDRA ~21% por
-- debajo del resto del catálogo en términos comparables, no porque sea más barata sino porque está
-- en otra base. Y no sale de ninguna cotización -- es un valor de mercado que Seba aportó de
-- memoria, mismo problema sin resolver que la sierra de 60 dientes (`precios` no distingue un
-- precio cotizado de uno de referencia, ver docs/confianza_precios_diseno.md, sección de
-- pendientes -- este es el segundo ejemplo real del mismo gap).

-- =====================================================================
-- Lo que se decidió dejar afuera del todo (no es un TODO, es una decisión cerrada)
-- =====================================================================
--
-- Segundo complemento de Sólido: arena mediana a granel ($72.000/m³) y piedra partida ($95.000/m³)
-- -- Seba decidió no cargar áridos de esta cotización. Motivo adicional registrado: ese presupuesto
-- cotiza SIN IVA con IIBB e IVA sumados aparte (primer proveedor en esta base impositiva distinta
-- -- confirma que la distinción de condición de pago/base impositiva, ya anotada como pendiente en
-- docs/confianza_precios_diseno.md §7, va a hacer falta pronto) y flete aparte ($154.300/viaje,
-- coherente con la política de precios sin flete). Ninguno de estos tres números se carga en
-- ningún lado.

-- =====================================================================
-- Verificación — correr después de aplicar
-- =====================================================================

-- 1) 2 filas nuevas (no 3 -- piedra queda afuera a propósito, ver arriba).
select count(*) as precios_complementario_solido
from precios p
join corralones c on c.id = p.corralon_id and c.nombre = 'Sólido'
join insumos i on i.id = p.insumo_id
where i.nombre in ('LADRILLOS COMUNES', 'BLOQUES DE CEMENTO 19/19/39');

-- 2) Confirmar el promedio ya refleja Sólido+Felemax en los dos insumos.
select i.nombre, pr.promedio, pr.minimo, pr.maximo, pr.cantidad_corralones
from insumos i
cross join lateral calcular_precio_promedio_insumo(i.id) pr
where i.nombre in ('LADRILLOS COMUNES', 'BLOQUES DE CEMENTO 19/19/39');
