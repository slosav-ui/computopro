-- Costo de mano de obra — Paso 3: función que calcula el valor hora de las 5 categorías UOCRA
-- para una obra puntual, aplicando (o no) cargas sociales, y respetando un override manual del
-- PRO si existe. Verificada a mano contra docs/seed/costo_laboral_uocra.xlsx (hoja "Calculo"),
-- categoría Ayudante, zona B, defaults de 0036/0037/0038: reproduce al centavo
-- costo_mensual = 2.191.583,1128, valor_hora = 13.562,6159589083, multiplicador = 1,72372325266787
-- (redondeado en la salida de esta función a 13.562,62 y 1,72 respectivamente).
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.
--
-- Requiere zona_uocra (0038) ya aplicada.

-- =====================================================================
-- Dos ratios distintos, a propósito — no confundir uno con el otro
-- =====================================================================
--
-- multiplicador (~1,72× con los defaults actuales, Ayudante) = costo_mensual / remuneracion_mensual.
-- Contesta "¿cuánto termina costando la hora real contra el jornal pelado que dice el convenio,
-- antes de cualquier beneficio o carga?" — el número que un rubro tiene internalizado cuando ve
-- $5.399 en la tabla de UOCRA y sabe que en realidad sale mucho más.
--
-- valor_hora / valor_hora_sin_cargas (~1,53× con los defaults actuales, Ayudante) contesta una
-- pregunta distinta: "¿cuánto más caro es formalizar a alguien pagándole lo mismo en mano?" — SAC
-- y vacaciones quedan de los dos lados, solo se sacan contribuciones patronales y fijos del
-- empleador.
--
-- Ninguno deriva del otro. Si en algún momento dan el mismo número, sospechar del cálculo, no
-- asumir que es una coincidencia esperable.

-- =====================================================================
-- Falla explícita si falta la escala, nunca NULL en silencio
-- =====================================================================
--
-- Mismo criterio que motivó zona_uocra como columna propia (0038): un valor NULL que se propaga
-- hasta el presupuesto es un número equivocado sin ningún aviso. Si escala_salarial_uocra no tiene
-- fila para (categoria_uocra, zona_uocra, vigencia_desde <= p_fecha), la función frena con
-- RAISE EXCEPTION — no hay ningún valor razonable que devolver en ese caso.

create or replace function calcular_valor_hora_mano_obra(p_obra_id uuid, p_fecha date default current_date)
returns table (
  categoria_uocra text,
  valor_hora numeric,
  valor_hora_sin_cargas numeric,
  costo_mensual numeric,
  remuneracion_mensual numeric,
  multiplicador numeric,
  origen text
)
language plpgsql stable as $$
#variable_conflict error
-- Explícito a propósito (es el default de Postgres, no cambia nada hoy): cualquier ambigüedad
-- futura entre una columna de salida (RETURNS TABLE de arriba) y una columna real de tabla tiene
-- que frenar la función, nunca resolverse en silencio a favor de una u otra. Ver el error real que
-- motivó esto: escala_salarial_uocra.categoria_uocra colisionaba con la columna de salida del
-- mismo nombre — resuelto abajo con alias de tabla en cada consulta, no con esta directiva; queda
-- como red de seguridad para el próximo choque, no como el mecanismo que resuelve éste.
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
  -- Config de la obra. Ausencia de fila = usuario sin membresía (RLS de obra_presupuesto_config ya
  -- filtra) o algo verdaderamente anómalo (toda obra tiene fila desde el trigger de 0020) — en
  -- cualquier caso, sin fila no hay nada que calcular: se devuelve vacío, fail-closed silencioso,
  -- mismo criterio que el resto del proyecto para temas de permisos (distinto de la falta de
  -- escala, que sí es un error de datos y sí frena con RAISE EXCEPTION más abajo).
  select * into v_config from obra_presupuesto_config c where c.obra_id = p_obra_id;
  if not found then
    return;
  end if;

  for v_cat in select unnest(array['AYUD', 'MOFI', 'OFIC', 'OFES', 'SERE']) loop
    -- Alias "e" obligatorio: escala_salarial_uocra.categoria_uocra choca con la columna de salida
    -- del mismo nombre (RETURNS TABLE de arriba). Sin calificar, Postgres no sabe si "categoria_uocra"
    -- es la columna de la tabla o el parámetro de salida — bug real encontrado al ejecutar esto la
    -- primera vez (ERROR 42702, column reference "categoria_uocra" is ambiguous).
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

    -- Cadena verificada contra docs/seed/costo_laboral_uocra.xlsx, hoja "Calculo".
    v_subtotal_base := v_escala.jornal_basico + v_escala.adicional_zona;
    v_asistencia := v_subtotal_base * v_escala.porcentaje_asistencia / 100;
    v_total_jornal := v_subtotal_base + v_asistencia;

    if v_escala.tipo_liquidacion = 'mensual' then
      v_remuneracion_mensual := v_total_jornal;
      -- 25: días/mes de referencia para pasar de mensual a diario. Solo se usa acá (Sereno) — hoy
      -- no afecta ningún número de la app porque el Sereno no participa de ninguna APU (entra por
      -- Gastos Generales cuando exista el Factor K). Hardcodeado a propósito, no un descuido —
      -- revisar junto con esa pieza si algún día necesita ser ajustable.
      v_vacaciones := (v_remuneracion_mensual / 25) * v_config.vacaciones_jornales_mes;
    else
      v_remuneracion_mensual := v_total_jornal * v_config.horas_mensuales;
      -- 8: horas por jornal de referencia. Hardcodeado a propósito, no una simplificación: las
      -- vacaciones se pagan al jornal de convenio sin importar cuántas horas trabaje la empresa
      -- ese mes, así que no debe moverse si el PRO cambia horas_mensuales.
      v_vacaciones := (v_total_jornal * 8) * v_config.vacaciones_jornales_mes;
    end if;

    -- 1/12: definición legal del SAC (Ley 23.041), no una política de empresa. Hardcodeado a
    -- propósito, no columna.
    v_sac := v_remuneracion_mensual / 12;
    v_remunerativo := v_remuneracion_mensual + v_sac + v_vacaciones;

    v_fondo_cese_monto := v_remunerativo * v_config.fondo_cese_pct / 100;
    v_contribuciones :=
      v_remunerativo * (
        v_config.suss_pct + v_config.obra_social_patronal_pct + v_config.art_pct
        + v_config.fondo_cese_pct + v_config.uocra_empleador_pct
      ) / 100
      + v_fondo_cese_monto * (v_config.fics_pct + v_config.ieric_pct + v_config.fodeco_pct) / 100;

    -- adicional_hormigon_pct de la escala NUNCA entra acá. Corresponde solo a tareas de hormigón y
    -- lo aplica la APU de estructura como decisión aparte — sumarlo acá lo contaría dos veces. No
    -- "arreglar" esto agregándolo.

    v_costo_con_cargas := v_remunerativo + v_contribuciones + v_config.fijos_operario_mensual;

    -- aplica_cargas_sociales mueve el costo (contribuciones + fijos), nunca horas_productivas. El
    -- tilde es sobre cargas sociales, no sobre productividad — un solo interruptor moviendo dos
    -- cosas distintas haría que el número dejara de ser explicable. No fusionar esto con
    -- horas_improductivas_mensuales aunque parezca tentador.
    v_costo_efectivo := case when v_config.aplica_cargas_sociales then v_costo_con_cargas else v_remunerativo end;

    v_horas_productivas := v_config.horas_mensuales - v_config.horas_improductivas_mensuales;

    v_valor_hora := v_costo_efectivo / v_horas_productivas;
    v_valor_hora_sin_cargas := v_remunerativo / v_horas_productivas;
    v_multiplicador := v_costo_efectivo / v_remuneracion_mensual;

    -- Override del PRO: si existe, pisa valor_hora y origen — el resto de las columnas se devuelve
    -- igual, calculado, para que el Paso 5 pueda mostrarlo como referencia junto al valor fijado a
    -- mano.
    select o.valor_hora into v_override
    from obra_valor_hora_override o
    where o.obra_id = p_obra_id and o.categoria_uocra = v_cat;

    categoria_uocra := v_cat;
    valor_hora := round(coalesce(v_override, v_valor_hora), 2);
    valor_hora_sin_cargas := round(v_valor_hora_sin_cargas, 2);
    costo_mensual := round(v_costo_efectivo, 2);
    remuneracion_mensual := round(v_remuneracion_mensual, 2);
    multiplicador := round(v_multiplicador, 2);
    origen := case when v_override is not null then 'override' else 'calculado' end;

    return next;
  end loop;

  return;
end;
$$;
