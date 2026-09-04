-- Gestión de Obra, pieza 3 (pantalla de carga de avance): un solo Borrador por obra a la vez.
--
-- Regla de negocio ya cerrada ("es un certificado por vez, el borrador es literalmente el
-- borrador del certificado que se está por emitir") que hasta ahora no tenía ningún respaldo en
-- el schema — dos INSERT a `certificados` en estado 'borrador' para la misma obra pasaban la RLS
-- sin problema, solo la convención de la pantalla evitaría que pase. Mismo criterio ya aplicado
-- en esta pieza al candado del 100% y a la inmutabilidad de `id_admin_creador`: la invariante va
-- en la base, no se confía en que la UI la respete siempre.
--
-- Índice único parcial, no un `check` (un `check` no puede mirar otras filas) ni un trigger (acá
-- alcanza con un índice — no hace falta lógica condicional més allá de "una fila en borrador por
-- obra_id", que es exactamente lo que un índice único parcial expresa de forma nativa).
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

create unique index certificados_un_borrador_por_obra
  on certificados (obra_id)
  where estado = 'borrador';

-- Verificación: no debería haber ninguna obra con más de un borrador hoy (si la hubiera, este
-- índice no se puede crear y Postgres avisa solo con el error de qué filas chocan).
select obra_id, count(*)
from certificados
where estado = 'borrador'
group by obra_id
having count(*) > 1;
