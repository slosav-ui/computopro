-- Rubros/APU — Fix puntual: 3 filas de apu_composicion_items que se perdieron en silencio al
-- correr 0023_seed_apu_composiciones_rubros_2_17.sql.
--
-- Causa raíz: 0023 usó el nombre "TORNILLO CABEZA EXAGONAL 10X3/4"" (sin espacio, tal como
-- aparece literal en la hoja de composición del Excel para las partidas 6.5, 6.6 y 15.3), pero
-- 0022_seed_insumos_apu_rubros_2_17.sql solo insertó la variante canónica con espacio
-- ("TORNILLO CABEZA EXAGONAL 10 X 3/4""), fusionando ambas grafías en una sola fila de insumos.
-- El script que generó 0023 reescribió el mapeo canónico a mano en vez de leerlo del archivo de
-- memoria del proyecto, y se salteó justo esta entrada — el `insert ... join` de 0023 no tira
-- error cuando un nombre no matchea, simplemente descarta la fila, así que las 3 quedaron afuera
-- sin ningún aviso. Verificado por diff exacto entre los nombres realmente insertados en 0022 y
-- los usados en 0023: es la única discrepancia, y explica el 770 → 767 completo (no hay más
-- filas afectadas).
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.
--
-- `where not exists` por las dudas, aunque `apu_composicion_items` no tiene ningún constraint
-- unique más allá de la primary key en `id` (0018_apu_composiciones.sql) — así esta migración es
-- segura de re-correr sin duplicar filas si ya se aplicó.

insert into apu_composicion_items (apu_composicion_id, tipo_componente, insumo_id, rendimiento)
select ac.id, 'material', i.id, v.rendimiento
from (values
  ('6.5', 24),
  ('6.6', 14),
  ('15.3', 14)
) as v(codigo, rendimiento)
join subitems s on s.codigo = v.codigo and s.creador_usuario_id is null
join apu_composiciones ac on ac.subitem_id = s.id and ac.creador_usuario_id is null
join insumos i on i.nombre = 'TORNILLO CABEZA EXAGONAL 10 X 3/4”' and i.tipo = 'material'
where not exists (
  select 1 from apu_composicion_items aci
  where aci.apu_composicion_id = ac.id and aci.insumo_id = i.id
);

-- =====================================================================
-- Verificación
-- =====================================================================
--
-- Esperado: 3 filas nuevas (si ya existieran por alguna corrida parcial anterior, el `where not
-- exists` las salta y este SELECT te va a mostrar menos de 3 — no es necesariamente un error).

select ac.id, i.nombre, aci.rendimiento
from apu_composicion_items aci
join apu_composiciones ac on ac.id = aci.apu_composicion_id
join insumos i on i.id = aci.insumo_id
where i.nombre = 'TORNILLO CABEZA EXAGONAL 10 X 3/4”';

-- Y el total general de apu_composicion_items para las 97 partidas de rubros 2-17 debería dar
-- ahora 770 (767 de 0023 + 3 de este fix):

select count(*) as total_apu_composicion_items
from apu_composicion_items aci
join apu_composiciones ac on ac.id = aci.apu_composicion_id
join subitems s on s.id = ac.subitem_id
where ac.creador_usuario_id is null
  and s.codigo in (
    '2.1','2.2','2.3','3.1','3.2','3.3','3.4','4.1','4.2','4.3','4.4','4.5','4.6','4.7',
    '5.1','5.2','5.3','5.4','5.5','5.6','6.1','6.2','6.3','6.4','6.5','6.6','7.1','7.2','7.3',
    '8.1','8.2','8.3','8.4','8.5','8.6','8.7','8.8','8.9','8.10','8.11','8.12',
    '9.1','9.2','9.3','10.1','10.2','10.3','10.4','10.5','10.6','10.7',
    '11.1','11.2','11.3','11.4','11.5','11.6',
    '12.1','12.2','12.3','12.4','12.5','12.6','12.7','12.8','12.9','12.10','12.11','12.12',
    '13.1','13.2','13.3','13.4','13.5','13.6','13.7',
    '14.1','14.2','14.3','14.4','14.5','14.6',
    '15.1','15.2','15.3','15.4','15.5',
    '16.1','16.2','16.3','16.4','16.5',
    '17.1','17.2','17.3','17.4','17.5'
  ) and s.creador_usuario_id is null;
