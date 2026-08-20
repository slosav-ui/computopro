-- Ciclo de vida del Certificado de Obra, paso 3: guard retroactivo sobre hitos_certificacion —
-- solo permite crear/editar hitos del contrato principal (Modelo B) si la obra realmente está en
-- 'hitos_precio_cerrado'. Los Subcontratos (contratista_nombre cargado) quedan afuera del guard,
-- porque no dependen del modelo de certificación de la obra.
-- Ver docs/certificados_ciclo_vida_diseno_datos.md, sección 9 ("Cierre del gap retroactivo de
-- hitos_certificacion"), para el diseño completo.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.
--
-- Motivación: 0006/0007_hitos_certificacion*.sql (ya aplicadas) nunca chequearon
-- obras.modelo_certificacion — hoy se puede insertar o editar un hito de contrato principal aunque
-- la obra esté en Modelo A. Se corrige con obra_modelo_es() (creada en
-- 0009_certificados.sql, paso 1 de esta misma pieza), vía DROP POLICY + CREATE POLICY sobre las 2
-- políticas de escritura de hitos_certificacion, sin recrear la tabla ni tocar sus datos.
--
-- El guard queda condicionado por contratista_nombre (discriminador ya existente entre contrato
-- principal y Subcontrato, docs/modelos_certificacion_diseno_datos.md §4/§7.3): un Subcontrato
-- puede existir sin importar el modelo de certificación activo de la obra, así que el guard de
-- modelo solo aplica cuando contratista_nombre es null (fila de contrato principal).
--
-- Alcance confirmado por el usuario: el guard va tanto en INSERT como en UPDATE (no solo INSERT
-- como se había pedido originalmente) — extensión que yo había propuesto en el diseño y el usuario
-- confirmó explícitamente.

drop policy hitos_certificacion_insert on hitos_certificacion;

create policy hitos_certificacion_insert on hitos_certificacion for insert with check (
  creado_por = auth.uid()
  and tiene_rol_en_obra(obra_id, 'admin_maestro')
  and (contratista_nombre is not null or obra_modelo_es(obra_id, 'hitos_precio_cerrado'))
);

drop policy hitos_certificacion_update on hitos_certificacion;

create policy hitos_certificacion_update on hitos_certificacion for update using (
  estado = 'activo'
  and tiene_rol_en_obra(obra_id, 'admin_maestro')
  and (contratista_nombre is not null or obra_modelo_es(obra_id, 'hitos_precio_cerrado'))
) with check (
  tiene_rol_en_obra(obra_id, 'admin_maestro')
  and (contratista_nombre is not null or obra_modelo_es(obra_id, 'hitos_precio_cerrado'))
);
