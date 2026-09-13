-- 0124 -- El acuerdo entre partes dentro del borrador (propuesta / conformidad / devolución)
--
-- Tanda 2 de "certificar es un acuerdo entre partes" (pedido de Seba, 2026-09-13). Diseño completo
-- y el resto de las tandas: docs/certificacion_acuerdo_partes_diagnostico.md §2, §8.1 y §8.2.
--
-- Qué resuelve: hasta acá certificar era una carga UNILATERAL -- el que carga el avance emite y
-- listo. En obra es un acuerdo: uno propone, el otro verifica, hay ida y vuelta, y recién después
-- se emite. El mecanismo del ida y vuelta ya existía sin que lo llamáramos así: el borrador ya es
-- un espacio compartido (la RLS de certificado_subitems_avance deja cargar y corregir a los tres
-- roles técnicos mientras el certificado siga en borrador, y hay un solo borrador por obra). Lo que
-- faltaba era el apretón de manos registrado y un guard en la emisión.
--
-- El estado del certificado se queda en 'borrador' TODO el tiempo. El acuerdo es un eje aparte,
-- mismo patrón que la anulación (0056). Consecuencia buscada: no se toca ninguna de las 4 check
-- constraints de fechas, ni el índice de un borrador por obra, ni calcular_avance_acumulado_subitem,
-- ni el candado del 100%, ni una sola de las funciones de cobro (leer / pagar / impactar).
--
-- *** ESTA ES LA ÚNICA TANDA DE LA PIEZA QUE TOCA RLS. Cambian DOS policies, las dos de SELECT:
-- *** certificados_select y certificado_subitems_avance_select. Ninguna policy de INSERT, UPDATE o
-- *** DELETE se toca. Verificar con un usuario cliente real antes de dar la tanda por cerrada (ver
-- *** el bloque de verificación al final).
--
-- Aplicar a mano en el SQL Editor de Supabase (Project -> SQL Editor), después de `0123`. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.


-- =====================================================================
-- Paso 1 -- las columnas del acuerdo, en `certificados`
-- =====================================================================
--
-- Calcadas del eje de la anulación (0056): un sub-estado propio + quién/cuándo de cada lado, con
-- checks de coherencia en la base y no solo en la UI.
--
-- `acuerdo_estado` not null con default 'en_carga' (y no nullable como anulacion_estado) porque acá
-- no existe el caso "nunca pasó nada": todo borrador está en carga hasta que alguien propone. Los
-- certificados que YA están emitidos cuando se aplica esta migración quedan en 'en_carga', y ahí ese
-- valor no significa nada -- son los que se emitieron antes de que existiera el acuerdo. La columna
-- solo gobierna el borrador.
--
-- 'en_carga' es también el estado al que se vuelve con una devolución: la diferencia entre "recién
-- creado" y "devuelto" la da `comentario_devolucion` (y el rastro completo de cada vuelta queda en
-- audit_log, igual que la anulación hace con sus intentos).
--
-- `propuesto_por` / `propuesta_fecha` NO se limpian al devolver: quedan como rastro de la última
-- propuesta. Lo que se limpia es la conformidad.

alter table certificados
  add column acuerdo_estado text not null default 'en_carga'
    check (acuerdo_estado in ('en_carga', 'propuesto', 'conforme')),
  add column propuesto_por uuid references auth.users(id),
  add column propuesta_fecha timestamptz,
  add column conforme_por uuid references auth.users(id),
  add column conforme_fecha timestamptz,
  add column comentario_devolucion text;

-- Una propuesta sin autor o sin fecha no es una propuesta.
alter table certificados add constraint certificados_acuerdo_propuesta_check
  check (acuerdo_estado = 'en_carga'
     or (propuesto_por is not null and propuesta_fecha is not null));

-- "Nunca la misma persona en los dos lados", a nivel base y no solo en la función -- mismo criterio
-- que ya rige la anulación. Es el check que hace que 'conforme' signifique siempre dos personas.
alter table certificados add constraint certificados_acuerdo_conformidad_check
  check (acuerdo_estado <> 'conforme'
     or (conforme_por is not null and conforme_fecha is not null and conforme_por <> propuesto_por));

comment on column certificados.acuerdo_estado is
  'Eje del acuerdo entre partes dentro del borrador (0124): en_carga | propuesto | conforme. NO es '
  'el estado del certificado (certificados.estado), que se queda en borrador todo el ida y vuelta.';
comment on column certificados.comentario_devolucion is
  'Por que la contraparte devolvio la ultima propuesta (0124). Obligatorio al devolver: una '
  'devolucion sin motivo deja al otro adivinando que corregir.';


-- =====================================================================
-- Paso 2 -- los helpers: quién es "la contraparte" y quién ve el borrador
-- =====================================================================
--
-- Regla única, cerrada por Seba (§8.1 y §8.2): la pregunta es SIEMPRE "¿hay profesional activo en
-- la obra?".
--
--   Sí hay  -> el borrador es cosa de las partes técnicas. El cliente (o su apoderado, o un veedor)
--              NO lo ve, y la conformidad la da el otro lado técnico: si propuso el constructor,
--              conforma el profesional; si propuso el profesional, conforma el constructor.
--              Textual de Seba: "ver el borrador lo mete en una discusión que es entre las partes
--              técnicas".
--   No hay  -> no hay quien verifique técnicamente del lado de la dirección: el cliente sí ve el
--              borrador y es él quien da la conformidad. "Acuerda con el constructor y después
--              paga. Si no, quedaría objetando algo que nunca acordó."
--
-- Y sobre esa regla, el precedente de la casa que ya está escrito en mis_pendientes() para
-- quitas/demasías: SI NO HAY CONTRAPARTE, NO SE EXIGE CONTRAPARTE. Una obra de una sola persona
-- (el caso más común hoy) sigue emitiendo exactamente como hasta ahora: sin nadie del otro lado no
-- hay conformidad que pedir.

create or replace function hay_profesional_en_obra(p_obra_id uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select exists (
    select 1 from obra_members
    where obra_id = p_obra_id and activo and rol = 'profesional'
  );
$$;

grant execute on function hay_profesional_en_obra(uuid) to authenticated;
revoke execute on function hay_profesional_en_obra(uuid) from public, anon;

-- ¿El que mira puede ver los borradores de esta obra? Los tres roles que cargan avance siempre --
-- tengan además el rol que tengan, porque roles combinables = varias filas en obra_members y
-- esconderle el borrador a alguien que además es profesional le rompería su rol técnico. El resto
-- (cliente, apoderado, veedor) solo cuando no hay profesional.
--
-- Consecuencia que conviene tener a la vista: el invitado_veedor también deja de ver los borradores
-- mientras haya profesional. Es coherente con la decisión (el borrador es la discusión técnica, no
-- el documento), pero es un cambio respecto de lo que veía hasta hoy.
create or replace function ve_borradores_certificado(p_obra_id uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select is_obra_member(p_obra_id)
     and (
       tiene_rol_en_obra(p_obra_id, 'admin_maestro')
       or tiene_rol_en_obra(p_obra_id, 'profesional')
       or tiene_rol_en_obra(p_obra_id, 'constructor')
       or not hay_profesional_en_obra(p_obra_id)
     );
$$;

grant execute on function ve_borradores_certificado(uuid) to authenticated;
revoke execute on function ve_borradores_certificado(uuid) from public, anon;

-- ¿Existe alguien que pueda dar la conformidad de una propuesta hecha por `p_propuesto_por`?
-- No mira al usuario logueado: contesta si la obra TIENE contraparte. Es la condición que decide si
-- emitir_certificado exige el acuerdo o emite como siempre.
--
-- El apoderado cuenta como contraparte solo con delegación vigente, con la regla de la base (sin
-- fechas = permanente), la misma que usa tiene_rol_en_obra.
create or replace function hay_contraparte_certificacion(p_obra_id uuid, p_propuesto_por uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select exists (
    select 1 from obra_members m
    where m.obra_id = p_obra_id
      and m.activo
      and (p_propuesto_por is null or m.usuario_id <> p_propuesto_por)
      and m.rol = any (case when hay_profesional_en_obra(p_obra_id)
                            then array['profesional', 'constructor']
                            else array['cliente_principal', 'invitado_apoderado']
                       end)
      and (m.rol <> 'invitado_apoderado'
        or (m.delegacion_inicio is null and m.delegacion_fin is null)
        or now() between m.delegacion_inicio and m.delegacion_fin)
  );
$$;

grant execute on function hay_contraparte_certificacion(uuid, uuid) to authenticated;
revoke execute on function hay_contraparte_certificacion(uuid, uuid) from public, anon;

-- ¿El que mira puede dar la conformidad de ESTE certificado, ahora? Una sola definición para las
-- tres bocas que la necesitan: dar_conformidad_certificado, devolver_avance_certificado y la rama
-- nueva de mis_pendientes(). La app también la llama por RPC para decidir si muestra el botón, así
-- no hay dos implementaciones de la autoridad que puedan divergir.
create or replace function puede_dar_conformidad_certificado(p_certificado_id uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select exists (
    select 1 from certificados c
    where c.id = p_certificado_id
      and c.estado = 'borrador'
      and c.acuerdo_estado = 'propuesto'
      and c.propuesto_por <> auth.uid()
      and case when hay_profesional_en_obra(c.obra_id)
               then tiene_rol_en_obra(c.obra_id, 'profesional')
                 or tiene_rol_en_obra(c.obra_id, 'constructor')
               else tiene_rol_en_obra(c.obra_id, 'cliente_principal')
                 or tiene_rol_en_obra(c.obra_id, 'invitado_apoderado')
          end
  );
$$;

grant execute on function puede_dar_conformidad_certificado(uuid) to authenticated;
revoke execute on function puede_dar_conformidad_certificado(uuid) from public, anon;


-- =====================================================================
-- Paso 3 -- RLS: las DOS policies de SELECT que cambian
-- =====================================================================
--
-- Este es el único paso de toda la pieza que toca la protección de filas.
--
-- ANTES: certificados_select = is_obra_member(obra_id), sin mirar el estado. O sea que el cliente
-- ya veía los borradores -- hallazgo del relevamiento, no un cambio de criterio.
-- AHORA: los estados distintos de 'borrador' siguen exactamente igual (cualquier miembro); el
-- borrador pasa por ve_borradores_certificado.
--
-- INSERT / UPDATE / DELETE de certificados: SIN CAMBIOS (0009 y 0010 siguen vigentes tal cual).

drop policy certificados_select on certificados;

create policy certificados_select on certificados for select
using (
  case when estado = 'borrador'
       then ve_borradores_certificado(obra_id)
       else is_obra_member(obra_id)
  end
);

-- La segunda policy: las filas de avance del borrador son el detalle de lo que se está discutiendo
-- (porcentajes y montos por partida). Esconder el encabezado y dejar visible el detalle no serviría
-- de nada.
--
-- Se podría haber dejado como estaba: la policy vieja resuelve la obra con un subselect sobre
-- `certificados`, que ahora ya no le devuelve el borrador al cliente, así que la restricción caería
-- sola por cascada. Se escribe explícita igualmente -- esconderle números de plata a un cliente es
-- justo el lugar donde no conviene depender de un efecto indirecto.
--
-- INSERT / UPDATE / DELETE de certificado_subitems_avance: SIN CAMBIOS (0052 sigue vigente tal
-- cual: los tres roles técnicos, solo mientras el certificado padre siga en borrador).

drop policy certificado_subitems_avance_select on certificado_subitems_avance;

create policy certificado_subitems_avance_select on certificado_subitems_avance for select
using (
  exists (
    select 1 from certificados c
    where c.id = certificado_id
      and case when c.estado = 'borrador'
               then ve_borradores_certificado(c.obra_id)
               else is_obra_member(c.obra_id)
          end
  )
);


-- =====================================================================
-- Paso 4 -- las tres funciones del ida y vuelta
-- =====================================================================
--
-- Ninguna toca `certificados.estado`. Las tres son SECURITY DEFINER con el chequeo de autoridad en
-- el cuerpo, mismo patrón que el resto del ciclo.
--
-- Límite conocido, heredado y aceptado: certificados_update (0010) deja que los tres roles técnicos
-- hagan un UPDATE directo sobre un borrador, así que alguien podría escribir a mano las columnas
-- del acuerdo sin pasar por estas funciones (y quedarse sin el audit_log). Es exactamente la misma
-- limitación ya documentada para la anulación y para modificaciones_obra. Lo que NO se puede
-- falsificar ni con un UPDATE directo es "la misma persona de los dos lados": eso lo impide el
-- check certificados_acuerdo_conformidad_check, que vive en la tabla.

-- Proponer: "esto que cargué es mi propuesta, revisala". Lo puede iniciar cualquiera de los que
-- cargan avance -- no hay rol fijo, el ida y vuelta lo arranca uno u otro según el caso.
create or replace function proponer_avance_certificado(p_certificado_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_obra_id uuid;
  v_estado text;
  v_acuerdo_estado text;
begin
  select obra_id, estado, acuerdo_estado
    into v_obra_id, v_estado, v_acuerdo_estado
  from certificados
  where id = p_certificado_id;

  if v_obra_id is null then
    raise exception 'certificado % no encontrado', p_certificado_id;
  end if;

  if v_estado <> 'borrador' then
    raise exception 'solo se propone el avance de un borrador (estado actual: %)', v_estado;
  end if;

  if not (tiene_rol_en_obra(v_obra_id, 'admin_maestro')
       or tiene_rol_en_obra(v_obra_id, 'profesional')
       or tiene_rol_en_obra(v_obra_id, 'constructor')) then
    raise exception 'sin autoridad para proponer el avance de este certificado';
  end if;

  -- Proponer un borrador vacío no es una propuesta. Alcanza con que haya una partida con avance del
  -- período: el monto fino lo sigue calculando emitir_certificado.
  if not exists (
    select 1 from certificado_subitems_avance
    where certificado_id = p_certificado_id and porcentaje_periodo > 0
  ) then
    raise exception 'no hay avance cargado para proponer';
  end if;

  -- Volver a proponer sobre una propuesta ya conforme es válido (es una propuesta nueva): se cae la
  -- conformidad anterior, que es justo lo que corresponde si el contenido cambió.
  update certificados
  set acuerdo_estado = 'propuesto',
      propuesto_por = auth.uid(),
      propuesta_fecha = now(),
      conforme_por = null,
      conforme_fecha = null,
      comentario_devolucion = null
  where id = p_certificado_id;

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (
    v_obra_id, auth.uid(), 'proponer_avance_certificado', 'certificado', p_certificado_id,
    jsonb_build_object('acuerdo_estado_previo', v_acuerdo_estado)
  );
end;
$$;

grant execute on function proponer_avance_certificado(uuid) to authenticated;
revoke execute on function proponer_avance_certificado(uuid) from public, anon;

-- Dar conformidad: "revisé y estoy de acuerdo". Los chequeos van por separado, y no como un solo
-- `if not puede_dar_conformidad_certificado(...)`, para poder decir cuál falló -- "sin autoridad" a
-- secas no le sirve a nadie para saber qué hacer.
create or replace function dar_conformidad_certificado(p_certificado_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_obra_id uuid;
  v_estado text;
  v_acuerdo_estado text;
  v_propuesto_por uuid;
begin
  select obra_id, estado, acuerdo_estado, propuesto_por
    into v_obra_id, v_estado, v_acuerdo_estado, v_propuesto_por
  from certificados
  where id = p_certificado_id;

  if v_obra_id is null then
    raise exception 'certificado % no encontrado', p_certificado_id;
  end if;

  if v_estado <> 'borrador' or v_acuerdo_estado <> 'propuesto' then
    raise exception 'no hay una propuesta de avance pendiente de conformidad en este certificado';
  end if;

  if v_propuesto_por = auth.uid() then
    raise exception 'la conformidad la da la otra parte: no se puede conformar la propia propuesta';
  end if;

  if not puede_dar_conformidad_certificado(p_certificado_id) then
    raise exception 'sin autoridad para dar la conformidad de este certificado';
  end if;

  update certificados
  set acuerdo_estado = 'conforme',
      conforme_por = auth.uid(),
      conforme_fecha = now()
  where id = p_certificado_id;

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (
    v_obra_id, auth.uid(), 'dar_conformidad_certificado', 'certificado', p_certificado_id,
    jsonb_build_object('propuesto_por', v_propuesto_por)
  );
end;
$$;

grant execute on function dar_conformidad_certificado(uuid) to authenticated;
revoke execute on function dar_conformidad_certificado(uuid) from public, anon;

-- Devolver con comentario: la otra mitad del ida y vuelta. Vuelve a 'en_carga' -- el borrador sigue
-- editable por los tres roles técnicos como siempre, así que la corrección se hace donde ya se
-- hacía. Misma autoridad que dar la conformidad: devuelve el que iba a conformar.
--
-- El comentario es obligatorio a nivel función: una devolución sin motivo deja al otro adivinando.
create or replace function devolver_avance_certificado(
  p_certificado_id uuid,
  p_comentario text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_obra_id uuid;
  v_estado text;
  v_acuerdo_estado text;
  v_propuesto_por uuid;
begin
  select obra_id, estado, acuerdo_estado, propuesto_por
    into v_obra_id, v_estado, v_acuerdo_estado, v_propuesto_por
  from certificados
  where id = p_certificado_id;

  if v_obra_id is null then
    raise exception 'certificado % no encontrado', p_certificado_id;
  end if;

  if v_estado <> 'borrador' or v_acuerdo_estado <> 'propuesto' then
    raise exception 'no hay una propuesta de avance pendiente para devolver en este certificado';
  end if;

  if p_comentario is null or btrim(p_comentario) = '' then
    raise exception 'la devolución necesita un comentario';
  end if;

  if not puede_dar_conformidad_certificado(p_certificado_id) then
    raise exception 'sin autoridad para devolver la propuesta de este certificado';
  end if;

  update certificados
  set acuerdo_estado = 'en_carga',
      comentario_devolucion = p_comentario,
      conforme_por = null,
      conforme_fecha = null
  where id = p_certificado_id;

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (
    v_obra_id, auth.uid(), 'devolver_avance_certificado', 'certificado', p_certificado_id,
    jsonb_build_object('comentario', p_comentario, 'propuesto_por', v_propuesto_por)
  );
end;
$$;

grant execute on function devolver_avance_certificado(uuid, text) to authenticated;
revoke execute on function devolver_avance_certificado(uuid, text) from public, anon;


-- =====================================================================
-- Paso 5 -- si se toca el avance, se cae la conformidad
-- =====================================================================
--
-- ESTE PASO NO ESTABA EN LA LISTA DE LA TANDA: se agrega porque sin él el acuerdo es de mentira.
-- El borrador sigue editable mientras está en borrador (RLS de 0052, a propósito), así que sin este
-- trigger se puede conformar un avance, después cambiarle los porcentajes, y emitir con una
-- conformidad que corresponde a otros números. Si molesta, se saca: son estas líneas y nada más
-- depende de ellas.
--
-- Vale para insert, update y delete de cualquier fila de avance del certificado. No hace nada si el
-- acuerdo ya estaba en 'en_carga', que es el caso normal mientras se carga.

create or replace function bajar_conformidad_si_cambia_avance()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_certificado_id uuid;
begin
  if tg_op = 'DELETE' then
    v_certificado_id := old.certificado_id;
  else
    v_certificado_id := new.certificado_id;
  end if;

  update certificados
  set acuerdo_estado = 'en_carga',
      conforme_por = null,
      conforme_fecha = null
  where id = v_certificado_id
    and acuerdo_estado <> 'en_carga';

  return null; -- after trigger: el valor de retorno se ignora
end;
$$;

create trigger certificado_avance_baja_conformidad
  after insert or update or delete on certificado_subitems_avance
  for each row execute function bajar_conformidad_si_cambia_avance();


-- =====================================================================
-- Paso 6 -- emitir_certificado: el guard del acuerdo
-- =====================================================================
--
-- Cuerpo vigente de 0121 copiado tal cual, con UN bloque agregado (y dos columnas más en el select
-- inicial). Ninguna otra línea cambia: la autoridad sigue siendo puede_editar_presupuesto, el
-- candado del 100% sigue igual, y los congelamientos de anticipo/fondo/plazo/CAC/cotización siguen
-- exactamente donde estaban.
--
-- El guard solo corre SI HAY CONTRAPARTE. Sin contraparte se emite como siempre -- una obra de una
-- sola persona no cambia en nada.
--
-- Dos condiciones cuando hay contraparte:
--   1) el acuerdo tiene que estar 'conforme' (que conforme_por <> propuesto_por lo garantiza el
--      check de la tabla, no hace falta revalidarlo acá);
--   2) no emite el mismo que propuso.
--
-- Sobre la 2: si la única persona con puede_editar_presupuesto es justo la que propuso, el
-- certificado no se puede emitir tal como está. NO es un bloqueo sin salida, y el mensaje de error
-- lo dice: devuelven la propuesta y la vuelve a proponer el otro, que es lo que el circuito ya
-- permite ("lo puede iniciar uno u otro"). Vale tenerlo medido igual, porque es el único caso en
-- que esta tanda le puede frenar la emisión a alguien que hoy emite sin problema.

create or replace function emitir_certificado(
  p_certificado_id uuid,
  p_requiere_firma_fisica boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_obra_id uuid;
  v_numero int;
  v_estado text;
  v_totales record;
  v_exceso record;
  v_cotizacion_promedio numeric;
  v_acuerdo_estado text;
  v_propuesto_por uuid;
begin
  select obra_id, numero, estado, acuerdo_estado, propuesto_por
    into v_obra_id, v_numero, v_estado, v_acuerdo_estado, v_propuesto_por
  from certificados
  where id = p_certificado_id;

  if v_obra_id is null then
    raise exception 'certificado % no encontrado', p_certificado_id;
  end if;

  if v_estado <> 'borrador' then
    raise exception 'certificado % no está en borrador (estado actual: %)', p_certificado_id, v_estado;
  end if;

  if not puede_editar_presupuesto(v_obra_id) then
    raise exception 'sin autoridad para emitir este certificado';
  end if;

  -- Acuerdo entre partes (0124)
  if hay_contraparte_certificacion(v_obra_id, v_propuesto_por) then
    if v_acuerdo_estado <> 'conforme' then
      raise exception 'este certificado todavía no tiene la conformidad de la otra parte';
    end if;

    if v_propuesto_por = auth.uid() then
      raise exception 'no emite el mismo que propuso el avance: que lo emita la otra parte, o devuelvan la propuesta y la vuelva a proponer quien no va a emitir';
    end if;
  end if;

  select * into v_exceso from calcular_excesos_certificado(p_certificado_id) limit 1;
  if v_exceso.obra_subitem_id is not null then
    raise exception '"%" ya tiene % certificado — quedan % disponibles, se intentó cargar %',
      v_exceso.descripcion, v_exceso.acumulado_previo, v_exceso.disponible, v_exceso.intentado;
  end if;

  select * into v_totales from calcular_totales_certificado(p_certificado_id);

  if v_totales.monto <= 0 then
    raise exception 'no se puede emitir un certificado sin avance cargado';
  end if;

  select (compra + venta) / 2 into v_cotizacion_promedio from cotizacion_dolar_bna limit 1;

  update certificados
  set estado = 'emitido',
      monto = v_totales.monto,
      monto_pactado = v_totales.monto_pactado,
      fecha_emision = now(),
      emitido_por = auth.uid(),
      dias_plazo_pago = v_totales.dias_plazo_pago,
      requiere_firma_fisica = p_requiere_firma_fisica,
      anticipo_pct_aplicado = v_totales.anticipo_pct,
      fondo_reparo_pct_aplicado = v_totales.fondo_reparo_pct,
      monto_anticipo_descontado = v_totales.monto_anticipo,
      monto_fondo_reparo_retenido = v_totales.monto_fondo_reparo,
      monto_neto_a_pagar = v_totales.monto_neto,
      cotizacion_dolar_promedio_al_emitir = v_cotizacion_promedio
  where id = p_certificado_id;

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (
    v_obra_id, auth.uid(), 'emitir_certificado', 'certificado', p_certificado_id,
    jsonb_build_object(
      'numero', v_numero,
      'monto', v_totales.monto,
      'monto_pactado', v_totales.monto_pactado,
      'monto_ajuste_cac', v_totales.monto_ajuste_cac,
      'requiere_firma_fisica', p_requiere_firma_fisica,
      'monto_neto_a_pagar', v_totales.monto_neto,
      'cotizacion_dolar_promedio_al_emitir', v_cotizacion_promedio,
      'propuesto_por', v_propuesto_por,
      'acuerdo_estado', v_acuerdo_estado
    )
  );
end;
$$;

grant execute on function emitir_certificado(uuid, boolean) to authenticated;
revoke execute on function emitir_certificado(uuid, boolean) from public, anon;


-- =====================================================================
-- Paso 7 -- mis_pendientes(): "te proponen un avance para revisar"
-- =====================================================================
--
-- Cuerpo vigente de 0123 copiado tal cual, con la rama nueva agregada antes del `order by` y el
-- comentario de la firma actualizado. Ninguna otra línea cambia.
--
-- La app vigente todavía no conoce el tipo `certificado_propuesto`: Pendiente.desdeRow (0117)
-- devuelve null para un tipo desconocido y saltea la fila, así que esta migración se puede aplicar
-- y verificar por SQL antes de tocar el Dart.

create or replace function mis_pendientes()
returns table(
  obra_id uuid,
  obra_nombre text,
  tipo text,                -- adicional | quita | demasia | certificado_emitido | certificado_leido
                            -- | certificado_pagado | anulacion | firma_fisica | certificacion_periodo
                            -- | certificado_propuesto
  entidad_id uuid,          -- modificaciones_obra.id o certificados.id, según tipo; null en
                            -- certificacion_periodo (no es una fila, es un período que venció)
  descripcion text,         -- descripción del adicional/quita/demasía, o período del certificado
  certificado_numero int,   -- solo certificados: la app arma "N° 3 bis" con Certificado.formatearNumero
  certificado_version int,
  desde timestamptz         -- desde cuándo espera (para ordenar y mostrar)
)
language sql
stable
security definer
set search_path = public
as $$
  with mis_obras as (
    select distinct o.id, o.nombre
    from obras o
    join obra_members om on om.obra_id = o.id
    where om.usuario_id = auth.uid() and om.activo and o.obra_madre_id is null
  )
  select mo.id as obra_id, mo.nombre as obra_nombre, 'adicional'::text as tipo, m.id as entidad_id,
         m.descripcion as descripcion, null::int as certificado_numero, null::int as certificado_version,
         coalesce(m.enviado_a_aprobacion_en, m.fecha_solicitud) as desde
  from modificaciones_obra m
  join mis_obras mo on mo.id = m.obra_id
  where m.tipo = 'adicional'
    and m.estado = 'pendiente'
    and (m.obra_hija_id is null or m.enviado_a_aprobacion_en is not null)
    and puede_aprobar_adicional(m.obra_id, m.monto_total)

  union all

  select mo.id, mo.nombre, m.tipo, m.id, m.descripcion, null::int, null::int, m.fecha_solicitud
  from modificaciones_obra m
  join mis_obras mo on mo.id = m.obra_id
  where m.tipo in ('quita', 'demasia')
    and m.estado = 'pendiente'
    and puede_aprobar_quita_demasia(m.obra_id)
    and (
      m.solicitado_por <> auth.uid()
      or not exists (
        select 1 from obra_members otro
        where otro.obra_id = m.obra_id and otro.activo
          and otro.rol in ('profesional', 'constructor')
          and otro.usuario_id <> auth.uid()
      )
    )

  union all

  select mo.id, mo.nombre, 'certificado_emitido'::text, c.id, c.periodo, c.numero, c.version, c.fecha_emision
  from certificados c
  join mis_obras mo on mo.id = c.obra_id
  where c.estado = 'emitido'
    and (tiene_rol_en_obra(c.obra_id, 'cliente_principal') or tiene_rol_en_obra(c.obra_id, 'invitado_apoderado'))

  union all

  select mo.id, mo.nombre, 'certificado_leido'::text, c.id, c.periodo, c.numero, c.version, c.fecha_lectura
  from certificados c
  join mis_obras mo on mo.id = c.obra_id
  where c.estado = 'leido'
    and puede_gestionar_certificado(c.obra_id, c.monto)

  union all

  select mo.id, mo.nombre, 'certificado_pagado'::text, c.id, c.periodo, c.numero, c.version, c.fecha_pago
  from certificados c
  join mis_obras mo on mo.id = c.obra_id
  where c.estado = 'pagado'
    and (tiene_rol_en_obra(c.obra_id, 'admin_maestro') or tiene_rol_en_obra(c.obra_id, 'constructor'))

  union all

  select mo.id, mo.nombre, 'anulacion'::text, c.id, c.periodo, c.numero, c.version, c.anulacion_propuesta_fecha
  from certificados c
  join mis_obras mo on mo.id = c.obra_id
  where c.anulacion_estado = 'propuesta'
    and (tiene_rol_en_obra(c.obra_id, 'profesional') or tiene_rol_en_obra(c.obra_id, 'constructor'))
    and c.anulacion_propuesta_por <> auth.uid()

  union all

  select mo.id, mo.nombre, 'firma_fisica'::text, c.id, c.periodo, c.numero, c.version, c.fecha_emision
  from certificados c
  join mis_obras mo on mo.id = c.obra_id
  where c.requiere_firma_fisica = true
    and c.pdf_firmado_subido = false
    and c.estado not in ('borrador', 'anulado')
    and (tiene_rol_en_obra(c.obra_id, 'admin_maestro') or tiene_rol_en_obra(c.obra_id, 'profesional'))

  union all

  -- Periodicidad pactada (0123): "ya se puede certificar". No sale de ninguna fila de certificados
  -- ni de modificaciones_obra -- es un período que venció, así que `entidad_id` va en null y la app
  -- lleva a Gestión de Obra de la obra, que es donde se crea el borrador.
  --
  -- Condiciones, en orden de lectura: hay periodicidad pactada; la obra certifica por avance medido
  -- (Modelo A -- en Modelo B no hay certificados, ver la policy INSERT de 0009); está congelada (sin
  -- contrato firmado no hay período que correr, y avisar empujaría a certificar contra precios
  -- vivos); el próximo período ya venció; y NO hay un borrador en curso -- si alguien ya está
  -- armando el certificado, el recordatorio es ruido.
  --
  -- Quién lo ve: los tres roles que cargan avance (mismo conjunto que la RLS de
  -- certificado_subitems_avance y que UserContext.puedeCargarAvance). El cliente no inicia la
  -- certificación: la recibe.
  select mo.id, mo.nombre, 'certificacion_periodo'::text, null::uuid,
         o.periodicidad_certificacion, null::int, null::int, p.vence
  from obras o
  join mis_obras mo on mo.id = o.id
  cross join lateral proximo_periodo_certificacion(o.id) as p(vence)
  where o.periodicidad_certificacion is not null
    and o.modelo_certificacion = 'avance_medido'
    and o.presupuesto_congelado_en is not null
    and p.vence is not null
    and p.vence <= now()
    and not exists (
      select 1 from certificados c where c.obra_id = o.id and c.estado = 'borrador'
    )
    and (tiene_rol_en_obra(o.id, 'admin_maestro')
      or tiene_rol_en_obra(o.id, 'profesional')
      or tiene_rol_en_obra(o.id, 'constructor'))

  union all

  -- Acuerdo entre partes (0124): "te proponen un avance para revisar". Va a la contraparte y nunca
  -- a quien propuso -- eso ya lo resuelve puede_dar_conformidad_certificado, que es la MISMA función
  -- que usan dar_conformidad_certificado y devolver_avance_certificado: el aviso no puede ofrecer
  -- algo que después la función rechace. Las dos condiciones de estado se repiten acá para que el
  -- planner filtre barato y para que la rama se lea sola.
  --
  -- `desde` = la fecha de la propuesta, que es desde cuándo el otro está esperando. La app lleva a
  -- la pantalla de carga de avance, que es donde se revisa lo propuesto.
  select mo.id, mo.nombre, 'certificado_propuesto'::text, c.id, c.periodo, c.numero, c.version,
         c.propuesta_fecha
  from certificados c
  join mis_obras mo on mo.id = c.obra_id
  where c.estado = 'borrador'
    and c.acuerdo_estado = 'propuesto'
    and puede_dar_conformidad_certificado(c.id)

  order by 8;
$$;

grant execute on function mis_pendientes() to authenticated;


-- =====================================================================
-- Verificación a mano después de aplicar (SQL Editor + app)
-- =====================================================================
--
-- El grueso de esta verificación NO se puede hacer desde el SQL Editor: corre como service_role sin
-- usuario logueado, así que auth.uid() es null y tanto la RLS como tiene_rol_en_obra dan false. Los
-- puntos 3 a 6 van desde la app, con usuarios reales.
--
-- 1) Las columnas y sus checks:
--    select column_name, data_type, is_nullable, column_default from information_schema.columns
--    where table_name = 'certificados'
--      and column_name in ('acuerdo_estado','propuesto_por','propuesta_fecha','conforme_por',
--                          'conforme_fecha','comentario_devolucion');
--    -- y que el check de "la misma persona de los dos lados" muerda:
--    update certificados set acuerdo_estado = 'conforme', propuesto_por = '<uid>',
--      propuesta_fecha = now(), conforme_por = '<el MISMO uid>', conforme_fecha = now()
--    where id = '<borrador_id>';
--    -- tiene que fallar por certificados_acuerdo_conformidad_check.
--
-- 2) Que las dos policies quedaron como se espera (y que no se tocó ninguna otra):
--    select tablename, policyname, cmd, qual from pg_policies
--    where tablename in ('certificados','certificado_subitems_avance') order by tablename, cmd;
--    -- certificados: select (nuevo), insert (0009), update (0010) -- los dos últimos sin cambios.
--    -- certificado_subitems_avance: select (nuevo), insert/update/delete (0052) sin cambios.
--
-- 3) *** LA VERIFICACIÓN QUE NO SE PUEDE SALTEAR: el cliente y el borrador. Con una obra que tenga
--    profesional activo y un usuario cliente_principal real, desde la app:
--    - el cliente NO ve el borrador en el historial de Gestión de Obra;
--    - el cliente SÍ sigue viendo todos los certificados emitidos/leídos/pagados/cerrados de
--      siempre, con los mismos montos;
--    - select * from certificado_subitems_avance where certificado_id = '<borrador_id>' devuelve
--      0 filas para el cliente (y las filas completas para el profesional).
--    Después, en una obra SIN profesional activo: el mismo cliente SÍ tiene que ver el borrador.
--
-- 4) El ida y vuelta completo, con dos usuarios técnicos (uno propone, el otro conforma):
--    - proponer con el borrador vacío -> "no hay avance cargado para proponer";
--    - cargar avance y proponer -> acuerdo_estado = 'propuesto';
--    - el que propuso intenta conformar -> "no se puede conformar la propia propuesta";
--    - el otro devuelve sin comentario -> "la devolución necesita un comentario";
--    - devuelve con comentario -> vuelve a 'en_carga' y comentario_devolucion queda escrito;
--    - vuelve a proponer, el otro conforma -> 'conforme', con conforme_por <> propuesto_por;
--    - tocar un porcentaje de avance -> el trigger del paso 5 lo devuelve a 'en_carga'.
--
-- 5) El guard de emisión:
--    - con contraparte y sin conformidad -> "todavía no tiene la conformidad de la otra parte";
--    - con conformidad, emitiendo el que propuso -> "no emite el mismo que propuso";
--    - con conformidad, emitiendo el otro -> emite, y el certificado queda idéntico a como quedaba
--      antes de esta migración (monto, neto, anticipo, fondo, plazo, cotización);
--    - *** en una obra de un solo usuario (sin contraparte): emitir tiene que seguir funcionando
--      exactamente como hasta hoy, sin proponer ni conformar nada. Esta es la que protege lo que ya
--      está andando.
--
-- 6) El aviso: con la propuesta hecha, `select tipo, obra_nombre, descripcion from mis_pendientes()`
--    tiene que devolver 'certificado_propuesto' para la contraparte y NO para quien propuso. Y que
--    las otras 8 ramas sigan devolviendo lo mismo que antes.
