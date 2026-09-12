-- Corrección de un dato de prueba, pedida por Seba (2026-09-12): el adicional presupuestado que se
-- envió y aprobó en $ 0 (camino 1 del diagnóstico de la 0118 -- confirmado con el historial de
-- audit_log: crear, enviar y aprobar, las tres por las funciones; partidas tildadas sin cantidad).
-- Vuelve a pendiente para poder rehacerlo bien. Mismo criterio que la 0087: una corrección de
-- datos puntual va como migración, para que quede rastro en el repo de qué se tocó y por qué.
--
-- Qué se revierte, y por qué más que el estado:
-- 1) la fila de modificaciones_obra: pendiente, sin aprobador/fecha/comentario de resolución, monto
--    en 0 y SIN `enviado_a_aprobacion_en` -- queda "en preparación", como recién creada;
-- 2) su obra hija, a "nunca enviada": se borra el snapshot congelado (presupuesto_subitems_congelado/
--    presupuesto_config_congelado, que tienen los montos en 0) y se limpian presupuesto_congelado_en/
--    _por y presupuesto_fecha_presentacion. Si la hija quedara congelada, sus solapas seguirían
--    leyendo el snapshot en 0 (calcular_monto_obra_subitems bifurca por congelado, 0104) aunque se
--    carguen cantidades, hasta volver a enviarla. Al reenviar, enviar_adicional_a_aprobacion la
--    presenta y la congela de nuevo, igual que la primera vez.
--
-- audit_log NO se borra (append-only, "inalterable" por diseño): queda el aprobar original y se
-- agrega una fila que dice que se revirtió, a mano y por qué. En el SQL Editor no hay auth.uid() --
-- se registra con el id_admin_creador de la obra madre (el dueño del proyecto), y el detalle lo
-- aclara para que nadie lo lea como una acción hecha desde la app.
--
-- Seguro ante un dato distinto del esperado: identifica la fila por sus condiciones (presupuestado,
-- aprobado, monto 0, enviado) y corta sin tocar nada si no hay EXACTAMENTE una. Después de la 0118
-- no se puede volver a llegar a este estado desde la app.
--
-- El otro adicional de prueba (pendiente, monto con decenas de decimales) no se toca acá: la 0118
-- (Paso 4) ya lo redondea -- queda como verificación de ese fix.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor), después de 0118. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

do $$
declare
  v_cantidad int;
  v_mod modificaciones_obra%rowtype;
  v_actor uuid;
begin
  select count(*) into v_cantidad
  from modificaciones_obra
  where tipo = 'adicional' and estado = 'aprobado' and monto_total = 0
    and obra_hija_id is not null and enviado_a_aprobacion_en is not null;

  if v_cantidad <> 1 then
    raise exception 'se esperaba exactamente 1 adicional presupuestado aprobado en $ 0, hay % -- no se toca nada', v_cantidad;
  end if;

  select * into v_mod
  from modificaciones_obra
  where tipo = 'adicional' and estado = 'aprobado' and monto_total = 0
    and obra_hija_id is not null and enviado_a_aprobacion_en is not null;

  -- El trigger calcular_monto_total_adicional no interviene: la fila tiene obra_hija_id (0113).
  update modificaciones_obra
  set estado = 'pendiente',
      aprobado_por = null,
      fecha_resolucion = null,
      comentario_resolucion = null,
      monto_total = 0,
      enviado_a_aprobacion_en = null
  where id = v_mod.id;

  delete from presupuesto_subitems_congelado where obra_id = v_mod.obra_hija_id;
  delete from presupuesto_config_congelado where obra_id = v_mod.obra_hija_id;

  update obras
  set presupuesto_congelado_en = null,
      presupuesto_congelado_por = null,
      presupuesto_fecha_presentacion = null
  where id = v_mod.obra_hija_id;

  select id_admin_creador into v_actor from obras where id = v_mod.obra_id;

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (
    v_mod.obra_id, v_actor, 'revertir_aprobacion_adicional', 'modificacion_obra', v_mod.id,
    jsonb_build_object(
      'motivo', 'dato de prueba: enviado y aprobado en $ 0 (partidas sin cantidad) antes de la 0118',
      'origen', 'corrección manual desde el SQL Editor, migración 0119 -- no es una acción de la app',
      'obra_hija_id', v_mod.obra_hija_id,
      'aprobado_por_original', v_mod.aprobado_por
    )
  );

  raise notice 'adicional % (%) vuelto a pendiente, obra hija % descongelada', v_mod.id, v_mod.descripcion, v_mod.obra_hija_id;
end;
$$;

-- =====================================================================
-- Verificación
-- =====================================================================
--
-- 1) La consulta de diagnóstico de la 0118: el adicional queda 'pendiente', monto_total 0,
--    enviado_a_aprobacion_en null, y el historial suma 'revertir_aprobacion_adicional' al final.
-- 2) La obra hija:
--    select presupuesto_fecha_presentacion, presupuesto_congelado_en,
--           (select count(*) from presupuesto_subitems_congelado p where p.obra_id = o.id) as filas
--    from obras o where o.id = '<obra_hija_id>';
--    -> null, null, 0.
-- 3) En la app: el adicional aparece como "Presupuestándose con la app" con el botón "Enviar para
--    aprobación"; enviar sin cargar cantidades -> rechaza (0118: el total da $ 0); cargar cantidades
--    en la obra hija, enviar, aprobar. El total con adicionales del dashboard lo muestra. Ojo: la
--    0118 mira el TOTAL, no cada partida -- una partida tildada en 0 entre otras con cantidad no
--    frena el envío (entra al cómputo en 0, como en cualquier obra).
-- 4) Correr esta migración una segunda vez: corta con "hay 0 -- no se toca nada".
