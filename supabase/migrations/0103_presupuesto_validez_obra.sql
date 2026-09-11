-- Congelamiento del presupuesto (Modelo A), paso 1: validez y el evento "presentar". Diseño
-- completo, con las 5 ambigüedades cerradas, en
-- docs/presupuesto_congelado_validez_modelo_a_diseno.md. Punto 3 del corte de
-- docs/indices_cac_cotizacion_dolar_diseno.md §4/§8 -- el prerrequisito para que el CAC tenga
-- contra qué aplicarse en el Modelo A.
--
-- Este paso NO congela nada todavía (eso es 0104) -- solo dos columnas de estado en `obras` y la
-- función que registra "se presentó el presupuesto, arranca a correr la validez". El
-- congelamiento en sí necesita `presupuesto_congelado_en` desde este mismo paso porque
-- presentar_presupuesto_obra ya tiene que poder mirarla (ver más abajo, guard de re-presentación).
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

-- =====================================================================
-- Columnas nuevas en `obras`
-- =====================================================================
--
-- presupuesto_fecha_presentacion: null mientras nunca se presentó -- no hay validez que contar
-- todavía. presupuesto_validez_dias: 30 sugerido (docs, §3), editable por obra en cada
-- presentación -- nunca un valor tácito sin que alguien lo haya mirado, por eso no tiene sentido
-- como constante en código.
--
-- presupuesto_congelado_en/presupuesto_congelado_por viven acá (no en 0104) porque
-- presentar_presupuesto_obra ya necesita presupuesto_congelado_en para su propio guard (ver
-- abajo) -- separarlas en el paso 2 hubiera dejado esta función rota hasta aplicar la migración
-- siguiente.

alter table obras
  add column presupuesto_fecha_presentacion timestamptz,
  add column presupuesto_validez_dias int not null default 30
    check (presupuesto_validez_dias > 0),
  add column presupuesto_congelado_en timestamptz,
  add column presupuesto_congelado_por uuid references auth.users(id);

-- =====================================================================
-- presentar_presupuesto_obra -- arranca (o reinicia) la validez
-- =====================================================================
--
-- Misma función para la primera presentación y para "Actualizar" un presupuesto vencido
-- (docs, §3/§4) -- actualizar es literalmente volver a presentar, con la validez que se elija en
-- ese momento. No recalcula ni guarda ningún monto: mientras la obra no está congelada, el
-- monto sigue siendo el que ya da calcular_presupuesto_vivo_obra (0091), en vivo -- este paso
-- solo mueve la fecha desde la que se cuenta el vencimiento.
--
-- Autoridad: admin_maestro/profesional -- ambigüedad B, cerrada por Seba: "el profesional es el
-- que arma el presupuesto, así que tiene que poder firmarlo" -- mismo par que ya edita
-- obra_subitems (0019).
--
-- Guard de re-presentación: bloqueada solo si la obra YA está congelada Y ya hay al menos un
-- certificado que dejó de ser borrador -- ambigüedad C, cerrada por Seba con el mismo criterio
-- para presentar que para congelar (0104): "mientras no se certificó nada, no hay nada que
-- proteger". Antes de que exista el primer certificado no-borrador, se puede volver a presentar
-- (y recongelar en 0104) para corregir un error, incluso con la obra ya congelada. Si la obra
-- nunca se congeló, presentar siempre está permitido sin importar el historial de certificados
-- -- necesario para que una obra real con certificados viejos (ambigüedad D, sin congelamiento
-- retroactivo) pueda adoptar el mecanismo recién ahora.
create or replace function presentar_presupuesto_obra(
  p_obra_id uuid,
  p_validez_dias int default 30
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_congelado_en timestamptz;
  v_hay_certificado_no_borrador boolean;
begin
  if not (tiene_rol_en_obra(p_obra_id, 'admin_maestro') or tiene_rol_en_obra(p_obra_id, 'profesional')) then
    raise exception 'sin autoridad para presentar el presupuesto de esta obra';
  end if;

  if p_validez_dias is null or p_validez_dias <= 0 then
    raise exception 'la validez tiene que ser mayor a 0 días';
  end if;

  select presupuesto_congelado_en into v_congelado_en from obras where id = p_obra_id;

  if v_congelado_en is not null then
    select exists (
      select 1 from certificados where obra_id = p_obra_id and estado <> 'borrador'
    ) into v_hay_certificado_no_borrador;

    if v_hay_certificado_no_borrador then
      raise exception 'ya hay certificados emitidos contra el presupuesto congelado -- no se puede volver a presentar';
    end if;
  end if;

  update obras
  set presupuesto_fecha_presentacion = now(),
      presupuesto_validez_dias = p_validez_dias
  where id = p_obra_id;

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (
    p_obra_id, auth.uid(), 'presentar_presupuesto_obra', 'obra', null,
    jsonb_build_object(
      'validez_dias', p_validez_dias,
      'reintento', v_congelado_en is not null
    )
  );
end;
$$;

grant execute on function presentar_presupuesto_obra(uuid, int) to authenticated;
revoke execute on function presentar_presupuesto_obra(uuid, int) from public, anon;

-- =====================================================================
-- Verificación
-- =====================================================================
--
-- 1) Presentar una obra de prueba: presupuesto_fecha_presentacion/presupuesto_validez_dias
--    quedan seteados, y aparece una fila en audit_log con accion='presentar_presupuesto_obra'.
-- 2) Sin autoridad (rol distinto de admin_maestro/profesional): la función rechaza antes de
--    tocar nada.
-- 3) validez_dias <= 0 o null: rechaza con el mensaje de validez, sin llegar al update.
-- 4) Obra nunca congelada, con certificados viejos ya emitidos (caso de una obra real
--    preexistente): presentar igual funciona -- el guard de re-presentación solo mira
--    presupuesto_congelado_en, no el historial de certificados por sí solo.
