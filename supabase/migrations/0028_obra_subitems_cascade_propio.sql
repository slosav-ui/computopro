-- obra_subitems: cascada de borrado para elementos PROPIOS del catálogo (rubros/subitems).
--
-- Antes de esta migración, borrar un rubro o subítem propio con datos cargados en alguna obra
-- fallaba por violación de FK (23503): obra_subitems.rubro_id/subitem_id referencian
-- rubros(id)/subitems(id) sin `on delete cascade`. La app usaba eso para BLOQUEAR el borrado
-- (RubrosTab._onEliminarRubro / SubitemsScreen._onEliminarSubitem consultaban en qué obras estaba
-- en uso y no dejaban seguir, ver getNombresObrasConUso/getNombresObrasConUsoDeSubitem).
--
-- Se decidió invertir ese criterio, pero SOLO para el catálogo PROPIO de cada usuario — el
-- catálogo oficial nunca puede llegar a este cascade de entrada, porque rubros_delete/
-- subitems_delete (0015/0016) ya restringen su DELETE a creador_usuario_id = auth.uid(), y las
-- filas oficiales tienen creador_usuario_id null. El catálogo oficial es fijo para todos, no hace
-- falta protegerlo de nadie; lo que el usuario PRO crea es suyo, y ahí la protección correcta no
-- es "no se puede", es "avisá qué se pierde y dejá decidir" — esa advertencia vive en la UI
-- (RubrosTab/SubitemsScreen), antes de llegar a este DELETE.
--
-- *** EXCEPCIÓN puntual, no un cambio de criterio general — leer esto antes de asumir lo contrario ***
-- obra_subitems documenta explícitamente en 0019_obra_subitems.sql (~línea 77) el principio
-- "prefiere estado sobre borrado": destildar un subítem sigue siendo es_aplicable = false, NUNCA
-- un DELETE, y ese flujo normal de tildar/destildar sigue sin necesitar ni usar ninguna política
-- DELETE. Lo que esta migración habilita es un caso acotado y distinto: cuando el usuario DUEÑO
-- borra su propio rubro/subítem del catálogo, sus filas de cómputo asociadas en cualquier obra
-- dejan de tener sentido (apuntan a algo que ya no existe) y se van con él, con el usuario ya
-- avisado de qué va a perder. No es "ahora obra_subitems se puede borrar en general" — es "se
-- puede borrar como consecuencia directa de borrar el elemento de catálogo propio del que
-- depende". Si dentro de un tiempo este archivo se lee preguntando por qué esta tabla tiene
-- DELETE cuando el resto del proyecto evita borrar (audit_log, libro_entradas, precios), esta es
-- la respuesta: sigue sin haber un DELETE de uso normal sobre obra_subitems, solo el disparado
-- por esta cascada puntual.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

-- =====================================================================
-- 1. FKs a cascada
-- =====================================================================
-- Nombres de constraint por default de Postgres (<tabla>_<columna>_fkey) — mismo patrón ya usado
-- en este proyecto para dropear constraints sin nombre explícito (ver
-- 0008_ajuste_contrato.sql:25, 0021_modificaciones_obra_fks.sql).

alter table obra_subitems
  drop constraint obra_subitems_rubro_id_fkey,
  add constraint obra_subitems_rubro_id_fkey
    foreign key (rubro_id) references rubros(id) on delete cascade;

alter table obra_subitems
  drop constraint obra_subitems_subitem_id_fkey,
  add constraint obra_subitems_subitem_id_fkey
    foreign key (subitem_id) references subitems(id) on delete cascade;

-- =====================================================================
-- 2. Política DELETE nueva — sin esto, la cascada de arriba no alcanza
-- =====================================================================
-- Postgres evalúa la RLS de la tabla hija (obra_subitems) para el DELETE que dispara la cascada,
-- con la misma sesión del usuario autenticado que ejecutó el DELETE en rubros/subitems — sin
-- ninguna política DELETE, RLS lo deniega por default, cascada o no. La tabla no tenía ninguna
-- (a propósito, ver el principio de arriba), así que hace falta agregar una.
--
-- Mismo rol que ya exige INSERT/UPDATE en esta misma tabla (obra_subitems_insert/
-- obra_subitems_update, 0019_obra_subitems.sql: admin_maestro o profesional de esa obra) — no una
-- versión más angosta atada a creador_usuario_id del rubro/subítem. El disparador real siempre va
-- a ser una cascada desde rubros/subitems, que ya restringen su propio DELETE al dueño por su
-- cuenta; agregar esa subconsulta acá sería proteger de nuevo un caso que la tabla padre ya
-- protege, complejidad sin beneficio real.

create policy obra_subitems_delete on obra_subitems for delete using (
  tiene_rol_en_obra(obra_id, 'admin_maestro')
  or tiene_rol_en_obra(obra_id, 'profesional')
);
