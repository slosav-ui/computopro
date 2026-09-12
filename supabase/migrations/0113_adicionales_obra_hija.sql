-- Adicionales, corrección de alcance (docs/adicionales_quitas_demasias_diagnostico.md §12): un
-- adicional no es (solo) un monto tipeado -- es "una obra dentro de una obra", presupuestada con
-- las mismas solapas de Rubros/Materiales/Mat y MO/APU que una obra real, a los precios del
-- momento en que se pide. El monto manual de la `0112` NO se descarta -- pasa a ser una de tres
-- vías de carga (la otra es importar de Excel/PDF, sin código en esta migración -- reusa el
-- importador existente cuando se conecte, ver lista de archivos en el doc).
--
-- Alcance de ESTA migración: solo lo necesario para que un adicional pueda tener su propio
-- `obra_id` (Factor K propio + precios de hoy, decisiones A-E de §11 y la corrección de §12, todas
-- cerradas por Seba). La aprobación (congelar la obra hija, sumar su `presupuesto_subitems_
-- congelado` a `modificaciones_obra.monto_total`) sigue siendo la Tanda 2 -- no está acá, es la
-- migración siguiente.
--
-- Riesgo real marcado y NO resuelto a propósito (§12.2, decisión de Seba): `apu_composiciones` es
-- por usuario, no por obra -- una composición propia editada dentro de la obra hija afectaría en
-- silencio cualquier otra obra real del mismo usuario que use el mismo subítem con receta propia.
-- Esta migración no lo resuelve ni lo esconde: es responsabilidad de la pantalla (fuera de este
-- archivo, ver lista de archivos) no ofrecer "editar mi composición" dentro de una obra hija hasta
-- que se resuelva de raíz (obra_id en apu_composiciones, migración aparte, si el uso real la pide).
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor), después de `0112`. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

-- =====================================================================
-- Paso 1 — obras.obra_madre_id: una obra puede ser "hija" de otra
-- =====================================================================
--
-- `on delete cascade`: si la obra madre se borra, sus adicionales presupuestados con la app no
-- tienen sentido sin ella -- mismo criterio que ya usa el resto del schema para todo lo que cuelga
-- de una obra (obra_subitems, obra_presupuesto_config, etc., todas `on delete cascade` contra
-- `obras`). Nula para toda obra real -- ninguna obra existente hoy cambia de comportamiento.
alter table obras
  add column obra_madre_id uuid references obras(id) on delete cascade;

-- Nota para cuando se toque el listado del dashboard (ver lista de archivos, no en esta migración):
-- `ObrasListScreen.getObras()` tiene que filtrar `obra_madre_id is null` -- sin este cambio, cada
-- adicional presupuestado con la app aparecería como una obra más en la lista principal.

-- =====================================================================
-- Paso 2 — modificaciones_obra.obra_hija_id: el vínculo con SU obra
-- =====================================================================
--
-- Reemplaza el check de la `0112`, que solo conocía el camino de monto manual. Ahora un adicional
-- tiene que traer EXACTAMENTE uno de los dos: `costo_costo_base` (monto fijo) o `obra_hija_id`
-- (presupuestado con la app, o importado -- las dos vías terminan con una obra hija real, así que
-- comparten esta misma columna). `cantidad = 1` sigue aplicando a los dos caminos -- ninguno de
-- los dos tiene una cantidad física distinta de un monto.
-- unique (no en null -- Postgres nunca considera dos NULL iguales entre sí en un unique, así que
-- esto no molesta a demasia/quita/ajuste_contrato, que siempre lo dejan nulo): dos adicionales
-- distintos nunca pueden terminar apuntando a la misma obra hija, ni por un error manual fuera de
-- crear_obra_hija_adicional (que ya lo impide por su cuenta, esto es la red de seguridad de la
-- base, mismo criterio que el resto del proyecto).
alter table modificaciones_obra
  add column obra_hija_id uuid references obras(id),
  add constraint modificaciones_obra_obra_hija_id_key unique (obra_hija_id);

alter table modificaciones_obra
  drop constraint modificaciones_obra_adicional_check;

alter table modificaciones_obra
  add constraint modificaciones_obra_adicional_check check (
    tipo <> 'adicional'
    or (
      cantidad = 1
      and (
        (costo_costo_base is not null and costo_costo_base >= 0 and obra_hija_id is null)
        or (costo_costo_base is null and obra_hija_id is not null)
      )
    )
  );

-- El trigger de la 0112 (`calcular_monto_total_adicional`) solo tiene que recalcular en vivo el
-- camino de monto fijo -- para el camino de obra hija, `monto_total` se congela al aprobar (Tanda
-- 2, `congelar_presupuesto_obra` sobre la obra hija + suma de `presupuesto_subitems_congelado`),
-- nunca antes. Sin este ajuste, el trigger existente no rompía nada (nunca se ejecuta con
-- `costo_costo_base is null`, porque su condición ya lo exige no nulo) -- se deja explícito de
-- todos modos para que quien lea el trigger no tenga que inferirlo del check constraint de otra
-- migración.
create or replace function calcular_monto_total_adicional()
returns trigger language plpgsql as $$
begin
  if new.tipo = 'adicional' and new.estado = 'pendiente' and new.obra_hija_id is null then
    new.monto_total := calcular_precio_adicional(
      new.obra_id, new.costo_costo_base, new.incluye_impuestos
    );
  end if;
  return new;
end;
$$;

-- =====================================================================
-- Paso 3 — crear_adicional_presupuestado: la vía "presupuestar con la app"
-- =====================================================================
--
-- NO parte de un adicional ya creado -- a diferencia de lo que armé en el primer borrador de esta
-- migración (pensado como "vincular una obra hija a un adicional pendiente"), eso chocaba de
-- frente contra el check constraint del Paso 2: un adicional recién insertado sin `costo_costo_
-- base` NI `obra_hija_id` todavía no es una fila válida, así que no hay ningún `modificacion_id`
-- "pendiente de vincular" al que engancharse. La función arma las DOS cosas juntas, en la misma
-- transacción: la obra hija primero, el adicional recién después, ya con `obra_hija_id` resuelto
-- -- mismo motivo por el que `crearAdicional` (Tanda 1, camino de monto fijo) tampoco separa esos
-- dos pasos.
--
-- El resto es igual a lo que ya tenía pensado: la obra hija dispara sola los triggers de bootstrap
-- ya existentes (`on_obra_created_presupuesto`, 0020; `on_obra_created_member`, 0033 -- config/
-- impuestos default + el creador como admin_maestro), esta función PISA esa config/impuestos
-- default con los valores REALES vigentes de la obra madre (Factor K propio arrancando de la
-- config vigente, no del default genérico de una obra nueva) y copia el resto del equipo de la
-- madre (foto, no en vivo -- decisión de Seba, 2026-09-13: "de acuerdo con copiar el equipo...
-- como foto y no en vivo"). Todo atómico -- si algo falla a mitad de camino, no queda ni obra hija
-- ni adicional a medio crear.
--
-- Autoridad: cualquier miembro de la obra madre (ambigüedad E, §11.3 -- "que lo pueda crear
-- cualquier miembro está bien, la barrera real es la aprobación"). Mismo criterio que
-- `crearAdicional` (RLS `modificaciones_obra_insert`, sin gate de rol) -- acá se repite a mano
-- porque el insert de `modificaciones_obra` lo hace esta función (SECURITY DEFINER, bypassa esa
-- RLS), no el cliente directo.
--
-- Precios de insumos: a propósito NO se copian de la madre. `obra_insumo_precios` (0030) arranca
-- vacía para la obra hija -- la cascada de precios ya cae sola al promedio del catálogo de
-- corralones (`precios`, sin obra_id) cuando no hay override cargado, que es exactamente "precios
-- del momento en que se pide" sin copiar nada (§12.4). Si algún día hace falta heredar los precios
-- PUNTUALES que la madre negoció, es una mejora aparte, no parte de esta pieza.
create or replace function crear_adicional_presupuestado(
  p_obra_id uuid,
  p_descripcion text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_madre obras%rowtype;
  v_obra_hija_id uuid;
  v_modificacion_id uuid;
begin
  if not is_obra_member(p_obra_id) then
    raise exception 'sin autoridad para presupuestar un adicional en esta obra';
  end if;

  if p_descripcion is null or btrim(p_descripcion) = '' then
    raise exception 'el adicional necesita una descripción';
  end if;

  select * into v_madre from obras where id = p_obra_id;
  if not found then
    raise exception 'obra % no encontrada', p_obra_id;
  end if;

  insert into obras (
    nombre, propietario, ubicacion, tipo_obra, perfil_creador, monto_total, superficie_m2,
    estado, moneda, aplica_cac, mes_base_cac, revision, estado_servicio_especial,
    id_admin_creador, obra_madre_id
  ) values (
    'Adicional: ' || p_descripcion, v_madre.propietario, v_madre.ubicacion, v_madre.tipo_obra,
    v_madre.perfil_creador, 0, 0,
    'Cotización', v_madre.moneda, false, date_trunc('month', now())::date, 'Rev. 00', 'Ninguno',
    auth.uid(), p_obra_id
  )
  returning id into v_obra_hija_id;

  -- Pisa el default genérico (0020) con los valores REALES vigentes de la madre -- el trigger de
  -- bootstrap ya insertó una fila para v_obra_hija_id, así que acá es UPDATE, no INSERT.
  update obra_presupuesto_config dest
  set tipo_presupuesto = src.tipo_presupuesto,
      aplica_impuestos = src.aplica_impuestos,
      tipo_suelo = src.tipo_suelo,
      zona_sismorresistente = src.zona_sismorresistente,
      gg_pct = src.gg_pct,
      imprevistos_pct = src.imprevistos_pct,
      epp_pct = src.epp_pct,
      costo_financiero_pct = src.costo_financiero_pct,
      beneficio_pct = src.beneficio_pct,
      gestion_materiales_terceros_pct = src.gestion_materiales_terceros_pct,
      updated_at = now()
  from obra_presupuesto_config src
  where dest.obra_id = v_obra_hija_id and src.obra_id = p_obra_id;

  -- Mismo criterio: pisa los 4 impuestos default (IVA 21/IIBB 3/Tasas 1.5/Otro 0) con los
  -- porcentajes reales de la madre -- las 4 filas ya existen (mismo bootstrap), se actualizan por
  -- `tipo`, nunca se insertan de nuevo.
  update obra_impuestos dest
  set porcentaje = src.porcentaje,
      nombre_otro = src.nombre_otro
  from obra_impuestos src
  where dest.obra_id = v_obra_hija_id and src.obra_id = p_obra_id and dest.tipo = src.tipo;

  -- Equipo de la madre, foto -- `on conflict do nothing` porque el bootstrap ya insertó al
  -- creador como admin_maestro en la obra hija; si esa misma persona tiene además otros roles en
  -- la madre (combinación de roles), esos sí se copian, no chocan con el conflicto.
  insert into obra_members (
    obra_id, usuario_id, rol, invitado_por_usuario_id,
    puede_aprobar_certificados, puede_aprobar_adicionales, tope_monto_aprobacion,
    delegacion_inicio, delegacion_fin, puede_invitar_terceros, puede_ver_apu_ajena
  )
  select
    v_obra_hija_id, usuario_id, rol, invitado_por_usuario_id,
    puede_aprobar_certificados, puede_aprobar_adicionales, tope_monto_aprobacion,
    delegacion_inicio, delegacion_fin, puede_invitar_terceros, puede_ver_apu_ajena
  from obra_members
  where obra_id = p_obra_id and activo
  on conflict (obra_id, usuario_id, rol) do nothing;

  insert into modificaciones_obra (
    obra_id, tipo, descripcion, cantidad, obra_hija_id, solicitado_por, subido_por
  ) values (
    p_obra_id, 'adicional', p_descripcion, 1, v_obra_hija_id, auth.uid(), auth.uid()
  )
  returning id into v_modificacion_id;

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (
    p_obra_id, auth.uid(), 'crear_adicional_presupuestado', 'modificacion_obra', v_modificacion_id,
    jsonb_build_object('obra_hija_id', v_obra_hija_id)
  );

  return v_modificacion_id;
end;
$$;

grant execute on function crear_adicional_presupuestado(uuid, text) to authenticated;
revoke execute on function crear_adicional_presupuestado(uuid, text) from public, anon;

-- =====================================================================
-- Verificación
-- =====================================================================
--
-- 1) Llamar crear_adicional_presupuestado(obra_madre_id, 'Ampliación de galpón') -- nace una obra
--    nueva con obra_madre_id apuntando a la madre, obra_presupuesto_config/obra_impuestos con los
--    MISMOS valores que la madre (no los default de 0020), obra_members con el mismo equipo activo
--    de la madre (comparar conteo de filas), y una fila nueva en modificaciones_obra
--    (tipo='adicional', obra_hija_id seteado, costo_costo_base null).
-- 2) Cambiar después un % de Factor K en la obra HIJA (no en la madre) -- confirmar que la madre
--    no se mueve (son filas independientes, la copia fue una vez, no una vista compartida).
-- 3) El check `modificaciones_obra_adicional_check`: intentar un insert manual con
--    costo_costo_base y obra_hija_id los dos no nulos (o los dos nulos) tiene que rechazar.
-- 4) Con un usuario que no es miembro de la obra madre: crear_adicional_presupuestado rechaza
--    ("sin autoridad...").
-- 5) obra_insumo_precios de la obra hija recién creada: vacía. calcular_presupuesto_vivo_obra
--    sobre la obra hija (con alguna partida tildada de prueba) da un monto usando el promedio del
--    catálogo de corralones, no un error ni un 0 por falta de precios cargados.
-- 6) `modificaciones_obra_obra_hija_id_key`: intentar poner a mano el mismo obra_hija_id en dos
--    filas de modificaciones_obra distintas tiene que rechazar por la unique.
