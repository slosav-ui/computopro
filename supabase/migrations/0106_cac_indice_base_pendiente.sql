-- Fix real encontrado por Seba probando en Galpón Mix: calcular_saldo_pendiente_avance_medido
-- devolvía 0 en silencio en vez de cortar -- justo el número más peligroso posible, "no queda
-- nada por certificar" cuando es lo contrario. Ver docs/cac_conectado_modelo_a_diseno.md §10 para
-- el diagnóstico completo.
--
-- Dos cosas separadas, las dos acá:
-- 1) Bug real en 0105: calcular_monto_congelado_ajustado devolvía 0 filas (fail-closed silencioso,
--    copiado sin querer del patrón de calcular_monto_obra_subitems) para un no-miembro, en vez de
--    cortar como ya hace factor_cac_obra -- corregido, mismo criterio en las dos.
-- 2) Caso real no cubierto por el diseño original: el CAC se publica con 1-2 meses de atraso, así
--    que CUALQUIER obra recién congelada va a tener, durante ese margen, el índice de su propio
--    mes base sin publicar todavía -- no es un caso raro, es lo esperable. Bloquear certificación
--    por completo durante esos 1-2 meses en toda obra nueva con CAC activo sería peor que el
--    problema que la regla de "no fallback" buscaba evitar.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor), después de `0105`. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

-- =====================================================================
-- calcular_monto_congelado_ajustado -- corte explícito + índice base pendiente ≠ error
-- =====================================================================
--
-- La regla de "sin fallback al mes anterior" (0102, palabras de Seba: "si alguien tiene una obra
-- con ajuste y todavía no se publicó el índice, hay que avisar, no calcular con el mes anterior en
-- silencio") sigue intacta para el mes DESTINO (el actual) -- factor_cac_obra sigue cortando ahí
-- exactamente igual, sin cambios en esta migración.
--
-- Lo nuevo es distinguir el mes ORIGEN (el mes base, el del congelamiento): si su índice no existe
-- todavía, no hay ningún valor que adivinar ni que completar con otro mes -- no se está
-- aproximando nada, se está mostrando la realidad tal cual: "no hay ajuste que aplicar todavía".
-- La obra certifica al precio pactado sin tocar, marcado (`serie_aplicada =
-- 'sin_ajustar_indice_pendiente'`) para que la próxima pasada de UI lo pueda señalar -- nunca en
-- silencio, pero tampoco bloqueando algo que no tiene por qué estar bloqueado.
--
-- Chequeo único, antes de branchear por cac_serie: como las 3 columnas de indices_cac son NOT NULL
-- (0102), si existe una fila para el mes las 3 series están garantizadas -- no hace falta
-- chequear serie por serie.
create or replace function calcular_monto_congelado_ajustado(p_obra_id uuid)
returns table(
  obra_subitem_id uuid,
  monto_total numeric,
  serie_aplicada text,
  fallback_general boolean
)
language plpgsql security definer set search_path = public stable as $$
declare
  v_congelado_en timestamptz;
  v_aplica_cac boolean;
  v_cac_serie text;
  v_tipo_presupuesto text;
  v_mes_base date;
  v_factor_general numeric;
  v_factor_materiales numeric;
  v_factor_mano_obra numeric;
begin
  -- Corregido: cortar, no devolver 0 filas -- mismo criterio que factor_cac_obra, que esta función
  -- llama más abajo. Antes de este fix, un no-miembro (o una sesión sin auth.uid(), como el SQL
  -- Editor sin login) recibía 0 en silencio en vez de un error -- el bug real que encontró Seba.
  if not is_obra_member(p_obra_id) then
    raise exception 'No sos miembro de esta obra.';
  end if;

  select o.presupuesto_congelado_en, o.aplica_cac, o.cac_serie
    into v_congelado_en, v_aplica_cac, v_cac_serie
  from obras o
  where o.id = p_obra_id;

  -- Obra sin congelar: nada que ajustar -- esto SÍ sigue siendo 0 filas legítimo (no un error),
  -- presupuesto_subitems_congelado está vacío para esta obra de cualquier forma.
  if v_congelado_en is null then
    return;
  end if;

  if coalesce(v_aplica_cac, false) is not true then
    return query
      select psc.obra_subitem_id, psc.monto_total, null::text, false
      from presupuesto_subitems_congelado psc
      where psc.obra_id = p_obra_id;
    return;
  end if;

  v_mes_base := date_trunc('month', v_congelado_en)::date;

  -- NUEVO -- índice del mes base todavía no publicado: no es un error, es la demora normal del
  -- CAC (1-2 meses). Sin ajuste, transparente, sin bloquear certificación.
  if not exists (select 1 from indices_cac where mes = v_mes_base) then
    return query
      select psc.obra_subitem_id, psc.monto_total, 'sin_ajustar_indice_pendiente'::text, false
      from presupuesto_subitems_congelado psc
      where psc.obra_id = p_obra_id;
    return;
  end if;

  select c.tipo_presupuesto into v_tipo_presupuesto
  from presupuesto_config_congelado c
  where c.obra_id = p_obra_id;

  if v_cac_serie = 'general' then
    -- A partir de acá, si factor_cac_obra corta, es porque falta el índice del mes ACTUAL
    -- (destino) -- el origen ya se confirmó arriba. Corte real, con el mensaje explícito de
    -- factor_cac_obra ("Todavía no se cargó el índice CAC... de este mes"), no en silencio.
    v_factor_general := factor_cac_obra(p_obra_id, 'general', v_mes_base);
    return query
      select psc.obra_subitem_id, psc.monto_total * v_factor_general, 'general'::text, false
      from presupuesto_subitems_congelado psc
      where psc.obra_id = p_obra_id;
    return;
  end if;

  v_factor_materiales := factor_cac_obra(p_obra_id, 'materiales', v_mes_base);
  v_factor_mano_obra := factor_cac_obra(p_obra_id, 'mano_obra', v_mes_base);
  v_factor_general := factor_cac_obra(p_obra_id, 'general', v_mes_base);

  return query
    select
      psc.obra_subitem_id,
      case
        when psc.costo_costo is null or psc.costo_costo = 0
          then psc.monto_total * v_factor_general
        when v_tipo_presupuesto = 'mano_obra_sola'
          then psc.monto_total * v_factor_mano_obra
        else
          psc.monto_total * (coalesce(psc.materiales_subtotal, 0) / psc.costo_costo) * v_factor_materiales
          + psc.monto_total * (1 - coalesce(psc.materiales_subtotal, 0) / psc.costo_costo) * v_factor_mano_obra
      end,
      case
        when psc.costo_costo is null or psc.costo_costo = 0 then 'general'
        when v_tipo_presupuesto = 'mano_obra_sola' then 'mano_obra'
        else 'materiales_mano_obra'
      end,
      (psc.costo_costo is null or psc.costo_costo = 0)
    from presupuesto_subitems_congelado psc
    where psc.obra_id = p_obra_id;
end;
$$;

grant execute on function calcular_monto_congelado_ajustado(uuid) to authenticated;
revoke execute on function calcular_monto_congelado_ajustado(uuid) from public, anon;

-- =====================================================================
-- Verificación
-- =====================================================================
--
-- 1) Repetir el caso de Galpón Mix (congelada agosto 2026, sin índice de agosto cargado):
--    calcular_saldo_pendiente_avance_medido YA NO da 0 -- da el saldo pendiente real, al precio
--    pactado sin ajustar. calcular_monto_congelado_ajustado muestra serie_aplicada =
--    'sin_ajustar_indice_pendiente' en sus 5 filas.
-- 2) Cargar índices_cac para agosto 2026 y repetir: ahora sí ajusta (o corta si falta septiembre,
--    según qué esté cargado en ese momento) -- serie_aplicada pasa a 'materiales_mano_obra' (o
--    'general'/'mano_obra' según corresponda por partida).
-- 3) Con agosto cargado pero SIN el mes actual: corta con excepción explícita de factor_cac_obra
--    ("Todavía no se cargó el índice CAC... de este mes"), no vuelve a dar 0 en silencio.
-- 4) Probar desde el SQL Editor sin usuario logueado (service_role, auth.uid() null): ahora corta
--    con "No sos miembro de esta obra." en vez de devolver 0 -- confirma el fix del bug real.
-- 5) Obra sin congelar, o con aplica_cac = false: sin cambios, mismo comportamiento que 0105.
