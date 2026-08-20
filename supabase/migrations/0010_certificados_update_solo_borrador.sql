-- Ciclo de vida del Certificado de Obra, ajuste sobre el paso 1: certificados_update pasa a
-- permitir SOLO la edición manual de un Borrador — bloquea cualquier UPDATE directo sobre un
-- certificado que ya salió de 'borrador', forzando que las transiciones (emitir, leer, pagar,
-- impactar) pasen exclusivamente por las funciones del paso 2.
-- Ver docs/certificados_ciclo_vida_diseno_datos.md, sección 7, para el diseño completo.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.
--
-- Motivación (corrección pedida por el usuario sobre 0009, ya aplicada): a diferencia del límite
-- ya aceptado para modificaciones_obra/aprobar_ajuste_contrato (donde el usuario es el único que
-- toca la base por SQL directo, riesgo bajo), la política original de 0009 permitía que
-- CUALQUIER usuario logueado con alguno de los 5 roles hiciera un UPDATE directo sobre un
-- certificado ya emitido sin pasar por ninguna función — riesgo real desde el uso normal de la
-- app, no solo desde SQL a mano. 0009 queda aplicada tal cual (no se re-corre); este archivo
-- reemplaza únicamente la política certificados_update por encima de lo ya aplicado.
--
-- Consecuencia para el paso 2 (todavía no escrito, hay que tenerlo presente al escribirlo): las 4
-- funciones de transición (emitir_certificado, marcar_certificado_leido,
-- marcar_certificado_pagado, marcar_certificado_impactado) NO pueden ser SECURITY INVOKER como
-- cambiar_modelo_certificacion/aprobar_ajuste_contrato — con esta política, ni siquiera
-- emitir_certificado podría completar su propio UPDATE (pasa el estado de 'borrador' a 'emitido',
-- y el WITH CHECK de abajo exige que el estado del resultado siga siendo 'borrador'). Las 4
-- funciones del paso 2 tienen que ser SECURITY DEFINER, haciendo ellas mismas el chequeo de
-- autoridad (tiene_rol_en_obra/puede_gestionar_certificado) en el cuerpo de la función en vez de
-- apoyarse en esta política para eso — acá RLS pasa a ser puramente el candado del Borrador
-- editable a mano, no la autoridad de las demás transiciones.

drop policy certificados_update on certificados;

create policy certificados_update on certificados for update using (
  estado = 'borrador'
  and (
    tiene_rol_en_obra(obra_id, 'admin_maestro')
    or tiene_rol_en_obra(obra_id, 'profesional')
    or tiene_rol_en_obra(obra_id, 'constructor')
  )
) with check (
  estado = 'borrador'
  and (
    tiene_rol_en_obra(obra_id, 'admin_maestro')
    or tiene_rol_en_obra(obra_id, 'profesional')
    or tiene_rol_en_obra(obra_id, 'constructor')
  )
);
