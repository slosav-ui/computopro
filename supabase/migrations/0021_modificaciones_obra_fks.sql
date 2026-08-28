-- Rubros/APU parte 2 — Migración 8 (última del plan): cierra las FKs sueltas que
-- modificaciones_obra dejó pendientes desde Etapa 3 (0002_modificaciones_obra_audit_log.sql),
-- ahora que subitems (0016) y apu_composiciones (0018) ya existen.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.
--
-- OJO antes de correr: si alguna fila de modificaciones_obra ya tiene subitem_id o
-- apu_privado_id cargado con un uuid que no matchee ninguna fila real de subitems/
-- apu_composiciones, el ALTER TABLE de abajo va a fallar (violación de FK) en vez de aplicarse a
-- medias — no debería pasar, porque subitems/apu_composiciones no existían todavía cuando se
-- pudo haber cargado algo ahí, pero no tengo forma de confirmarlo sin acceso a la base. Si falla,
-- pasame el mensaje de error (va a nombrar la fila/valor que no matchea) y lo resolvemos antes de
-- reintentar.

alter table modificaciones_obra
  add constraint modificaciones_obra_subitem_id_fkey
  foreign key (subitem_id) references subitems(id);

alter table modificaciones_obra
  add constraint modificaciones_obra_apu_privado_id_fkey
  foreign key (apu_privado_id) references apu_composiciones(id);
