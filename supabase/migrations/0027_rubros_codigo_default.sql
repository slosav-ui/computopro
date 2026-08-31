-- Rubros: código vs. número mostrado — Etapa D (alta sin código) de la pieza documentada en
-- docs/rubros_orden_diseno_datos.md. El PRO ya no elige un código al crear un rubro propio — pasa a
-- generarse solo, del lado de la base, con el mismo mecanismo que ya usa rubros.id en esta misma
-- tabla (gen_random_uuid()). rubros.codigo sigue existiendo y sigue NOT NULL, solo deja de depender
-- de que el cliente lo mande en el insert.
--
-- La migración 0025 (rubros_codigo_unique, índice único global) NO se toca — sigue vigente como red
-- de seguridad, aunque con un código generado así la chance real de colisión es la misma,
-- astronómicamente baja, que ya aceptamos hoy para id en cualquier tabla del proyecto.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor) ANTES de desplegar el cambio
-- de Dart que deja de mandar `codigo` en el insert de RubrosRepository.crearPersonalizado — sin
-- este default, ese insert fallaría por violar el NOT NULL de la columna. No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

alter table rubros alter column codigo set default gen_random_uuid()::text;
