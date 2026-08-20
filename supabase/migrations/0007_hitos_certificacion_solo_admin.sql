-- Modelos de Certificación, ajuste sobre el paso 2: hitos_certificacion, escritura solo
-- admin_maestro (no admin_maestro + profesional como quedó en 0006_hitos_certificacion.sql).
-- Ver docs/modelos_certificacion_diseno_datos.md, sección 4/§8, para el diseño completo.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.
--
-- 0006 ya está aplicada en producción (tabla + columna + RLS con admin_maestro/profesional) y no
-- se vuelve a correr — este archivo solo reemplaza las 2 políticas de escritura por encima de lo
-- ya aplicado. Decisión cerrada con el usuario: igual que obras.modelo_certificacion
-- ("únicamente el Administrador", §8 del diseño), hitos_certificacion también queda
-- exclusivamente en manos de admin_maestro, sin incluir a profesional.
--
-- SELECT no cambia (sigue abierto a is_obra_member), y no hace falta re-crearla acá.

drop policy hitos_certificacion_insert on hitos_certificacion;

create policy hitos_certificacion_insert on hitos_certificacion for insert with check (
  creado_por = auth.uid()
  and tiene_rol_en_obra(obra_id, 'admin_maestro')
);

drop policy hitos_certificacion_update on hitos_certificacion;

create policy hitos_certificacion_update on hitos_certificacion for update using (
  estado = 'activo'
  and tiene_rol_en_obra(obra_id, 'admin_maestro')
) with check (
  tiene_rol_en_obra(obra_id, 'admin_maestro')
);
