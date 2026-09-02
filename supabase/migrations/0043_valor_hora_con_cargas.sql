-- Costo de mano de obra — Paso 5, tanda 1: el cartel necesita un multiplicador y un valor hora
-- "con cargas" que NO dependan del toggle aplica_cargas_sociales. calcular_valor_hora_mano_obra ya
-- calculaba v_costo_con_cargas siempre, antes de la rama del toggle (0039), pero nunca lo exponía
-- hacia afuera — agrega dos columnas simétricas a valor_hora_sin_cargas (que ya era independiente
-- del modo), sin tocar ninguna lógica de cálculo existente. Ver
-- docs/costo_mano_de_obra_decisiones.md §14.
--
-- Cambia el RETURNS TABLE, hace falta DROP + CREATE. consolidado_insumos_obra (0042) usa `select *`
-- sobre esta función en su CTE — agregar columnas no la rompe, no hace falta tocarla.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

drop function calcular_valor_hora_mano_obra(uuid, date);

create function calcular_valor_hora_mano_obra(p_obra_id uuid, p_fecha date default current_date)
returns table (
  categoria_uocra text,
  valor_hora numeric,
  valor_hora_sin_cargas numeric,
  valor_hora_con_cargas numeric,
  costo_mensual numeric,
  remuneracion_mensual numeric,
  multiplicador numeric,
  multiplicador_con_cargas numeric,
  origen text
)
language plpgsql stable as $$
#variable_conflict error
-- Explícito a propósito (es el default de Postgres, no cambia nada hoy): cualquier ambigüedad
-- futura entre una columna de salida (RETURNS TABLE de arriba) y una columna real de tabla tiene
-- que frenar la función, nunca resolverse en silencio a favor de una u otra.
declare
  v_config record;
  v_cat text;
  v_escala record;
  v_override numeric;
  v_subtotal_base numeric;
  v_asistencia numeric;
  v_total_jornal numeric;
  v_remuneracion_mensual numeric;
  v_sac numeric;
  v_vacaciones numeric;
  v_remunerativo numeric;
  v_fondo_cese_monto numeric;
  v_contribuciones numeric;
  v_costo_con_cargas numeric;
  v_costo_efectivo numeric;
  v_horas_productivas numeric;
  v_valor_hora numeric;
  v_valor_hora_sin_cargas numeric;
  v_multiplicador numeric;
begin
  -- Config de la obra. Ausencia de fila = usuario sin membresía o algo verdaderamente anómalo —
  -- sin fila no hay nada que calcular: se devuelve vacío, fail-closed silencioso (distinto de la
  -- falta de escala, que sí es un error de datos y frena con RAISE EXCEPTION más abajo).
  select * into v_config from obra_presupuesto_config c where c.obra_id = p_obra_id;
  if not found then
    return;
  end if;

  for v_cat in select unnest(array['AYUD', 'MOFI', 'OFIC', 'OFES', 'SERE']) loop
    select * into v_escala
    from escala_salarial_uocra e
    where e.categoria_uocra = v_cat
      and e.zona = v_config.zona_uocra
      and e.vigencia_desde <= p_fecha
    order by e.vigencia_desde desc
    limit 1;

    if not found then
      raise exception 'No hay escala salarial UOCRA para categoría % zona % vigente al %',
        v_cat, v_config.zona_uocra, p_fecha;
    end if;

    v_subtotal_base := v_escala.jornal_basico + v_escala.adicional_zona;
    v_asistencia := v_subtotal_base * v_escala.porcentaje_asistencia / 100;
    v_total_jornal := v_subtotal_base + v_asistencia;

    if v_escala.tipo_liquidacion = 'mensual' then
      v_remuneracion_mensual := v_total_jornal;
      v_vacaciones := (v_remuneracion_mensual / 25) * v_config.vacaciones_jornales_mes;
    else
      v_remuneracion_mensual := v_total_jornal * v_config.horas_mensuales;
      v_vacaciones := (v_total_jornal * 8) * v_config.vacaciones_jornales_mes;
    end if;

    v_sac := v_remuneracion_mensual / 12;
    v_remunerativo := v_remuneracion_mensual + v_sac + v_vacaciones;

    v_fondo_cese_monto := v_remunerativo * v_config.fondo_cese_pct / 100;
    v_contribuciones :=
      v_remunerativo * (
        v_config.suss_pct + v_config.obra_social_patronal_pct + v_config.art_pct
        + v_config.fondo_cese_pct + v_config.uocra_empleador_pct
      ) / 100
      + v_fondo_cese_monto * (v_config.fics_pct + v_config.ieric_pct + v_config.fodeco_pct) / 100;

    -- adicional_hormigon_pct de la escala NUNCA entra acá — corresponde a la APU de estructura.

    v_costo_con_cargas := v_remunerativo + v_contribuciones + v_config.fijos_operario_mensual;
    v_costo_efectivo := case when v_config.aplica_cargas_sociales then v_costo_con_cargas else v_remunerativo end;

    v_horas_productivas := v_config.horas_mensuales - v_config.horas_improductivas_mensuales;

    v_valor_hora := v_costo_efectivo / v_horas_productivas;
    v_valor_hora_sin_cargas := v_remunerativo / v_horas_productivas;
    v_multiplicador := v_costo_efectivo / v_remuneracion_mensual;

    select o.valor_hora into v_override
    from obra_valor_hora_override o
    where o.obra_id = p_obra_id and o.categoria_uocra = v_cat;

    categoria_uocra := v_cat;
    valor_hora := round(coalesce(v_override, v_valor_hora), 2);
    valor_hora_sin_cargas := round(v_valor_hora_sin_cargas, 2);
    -- Nuevo (0043): independiente del toggle, mismo criterio que valor_hora_sin_cargas — el
    -- cartel del Paso 5 los necesita fijos en los dos modos.
    valor_hora_con_cargas := round(v_costo_con_cargas / v_horas_productivas, 2);
    costo_mensual := round(v_costo_efectivo, 2);
    remuneracion_mensual := round(v_remuneracion_mensual, 2);
    multiplicador := round(v_multiplicador, 2);
    -- Nuevo (0043): independiente del toggle — el "1,72×" que el cartel muestra en los dos modos.
    multiplicador_con_cargas := round(v_costo_con_cargas / v_remuneracion_mensual, 2);
    origen := case when v_override is not null then 'override' else 'calculado' end;

    return next;
  end loop;

  return;
end;
$$;

grant execute on function calcular_valor_hora_mano_obra(uuid, date) to authenticated;
