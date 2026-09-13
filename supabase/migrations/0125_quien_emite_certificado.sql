-- 0125 -- Quién emite un certificado: el profesional, o el cliente si no hay profesional
--
-- CAMBIO DE MATRIZ (Seba, 2026-09-13). Corrige la autoridad de emisión que dejó la `0121` y el
-- guard que dejó la `0124`. Lo que sigue es el MOTIVO, y está escrito largo a propósito: esta es la
-- segunda vez que se mueve quién emite, y sin el porqué a la vista alguien lo "corrige" de vuelta
-- dentro de un mes mirando la 0121.
--
-- LO QUE DECÍA LA 0121: emitir = `puede_editar_presupuesto`, con este argumento textual de Seba --
-- "si cotiza y ejecuta la obra, es el que emite los certificados". O sea que el constructor con el
-- permiso emitía.
--
-- POR QUÉ CAMBIA: **el certificado es lo que va al cliente a pagar, y quien lo cierra no puede ser
-- el que cobra.** Emitir no es un paso administrativo más del que ejecuta: es el acto por el que la
-- medición acordada se convierte en un documento de cobro dirigido a la otra parte. El que va a
-- cobrar ese documento no puede ser el que lo emite -- no por desconfianza, sino porque entonces no
-- hay ningún acto de control entre "yo digo que hice esto" y "cobrame esto".
--
-- LA REGLA NUEVA, textual de Seba: "el profesional es siempre el que cierra el certificado para que
-- vaya al cliente a pagarlo. El constructor nunca tiene la potestad de cierre. Y si no hay
-- profesional en la obra, el que cierra es el cliente, que es el mismo que paga."
--
-- Y es INDEPENDIENTE de quién propuso: el profesional puede proponer el avance y emitir su propia
-- propuesta, una vez que el constructor le dio la conformidad. Por eso se cae el guard "no emite el
-- mismo que propuso" de la 0124 (ver el paso 2). Lo que protege la emisión no es que sean dos
-- personas distintas en propuesta y emisión -- eso ya lo garantiza la conformidad, que exige dos --
-- sino que el que emite no sea el que cobra.
--
-- OJO, NO confundir con "Impactado y Cerrado" (`marcar_certificado_impactado`): la palabra "cerrar"
-- aparece en los dos lados y son dos cosas distintas. Una es cerrar el certificado para que vaya a
-- cobrarse (emitir, esto); la otra es registrar que YA se cobró, y esa sí es del que cobra.
-- Confirmado por Seba el 2026-09-13: `marcar_certificado_impactado` NO se toca en esta migración.
-- Tampoco se toca la anulación: proponerla y resolverla sigue siendo de las dos partes técnicas,
-- porque anular es reconocer que la medición estuvo mal, y eso es de los dos -- no es una potestad
-- de cierre.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project -> SQL Editor), después de `0124`. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.


-- =====================================================================
-- Paso 1 -- la escalera: quién emite en esta obra
-- =====================================================================
--
-- Tres peldaños, cada uno solo cuando el de arriba NO existe en la obra:
--
--   1. profesional      -- si hay profesional activo, emite el profesional. Siempre.
--   2. cliente          -- si no hay profesional, emite el cliente_principal, o su apoderado con
--                          delegación vigente (mismo criterio con el que ya lee, paga y conforma).
--   3. admin_maestro    -- si no hay ni profesional ni cliente, emite el administrador de la obra.
--
-- El tercer peldaño NO es un agregado de comodidad: sin él se rompe el caso más común al arrancar,
-- que es la obra de un solo usuario. El bootstrap de la 0033 le da al creador el rol admin_maestro
-- y nada más -- ni profesional, ni cliente. Con la regla literal ("profesional, o cliente si no hay
-- profesional") esa obra se queda SIN NADIE que pueda emitir, y la certificación se muere ahí.
--
-- La escalera nunca le da la emisión al `constructor` como rol, en ninguna configuración. Un usuario
-- que sea admin_maestro Y constructor a la vez sí va a emitir, pero por su fila de admin_maestro:
-- en una obra donde esa persona es las dos cosas no hay dos partes que proteger.
--
-- Consecuencia que conviene tener presente, y es deliberada: en una obra con admin_maestro y
-- cliente pero SIN profesional, el administrador no emite -- emite el cliente. Es la regla tal cual
-- quedó definida ("si no hay profesional, el que cierra es el cliente, que es el mismo que paga").

create or replace function quien_emite_certificado(p_obra_id uuid)
returns text language sql security definer set search_path = public stable as $$
  select case
    when hay_profesional_en_obra(p_obra_id) then 'profesional'
    when exists (
      select 1 from obra_members m
      where m.obra_id = p_obra_id
        and m.activo
        and m.rol in ('cliente_principal', 'invitado_apoderado')
        and (m.rol <> 'invitado_apoderado'
          or (m.delegacion_inicio is null and m.delegacion_fin is null)
          or now() between m.delegacion_inicio and m.delegacion_fin)
    ) then 'cliente'
    else 'admin_maestro'
  end;
$$;

grant execute on function quien_emite_certificado(uuid) to authenticated;
revoke execute on function quien_emite_certificado(uuid) from public, anon;

-- ¿El que mira es ese? Una sola definición de la escalera (la de arriba) usada por las dos bocas:
-- este helper y el mensaje de error de emitir_certificado. La app también lo llama por RPC para
-- decidir si muestra "Vista previa"/"Emitir": igual que con la conformidad (0124), `UserContext` no
-- puede calcularlo -- necesita saber si la obra tiene profesional activo, y solo conoce las
-- membresías del usuario logueado.
create or replace function puede_emitir_certificado(p_obra_id uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select case quien_emite_certificado(p_obra_id)
    when 'profesional' then tiene_rol_en_obra(p_obra_id, 'profesional')
    when 'cliente' then tiene_rol_en_obra(p_obra_id, 'cliente_principal')
                      or tiene_rol_en_obra(p_obra_id, 'invitado_apoderado')
    else tiene_rol_en_obra(p_obra_id, 'admin_maestro')
  end;
$$;

grant execute on function puede_emitir_certificado(uuid) to authenticated;
revoke execute on function puede_emitir_certificado(uuid) from public, anon;


-- =====================================================================
-- Paso 2 -- emitir_certificado: la autoridad nueva, y un guard menos
-- =====================================================================
--
-- Cuerpo vigente de 0124 copiado tal cual, con DOS cambios y nada más:
--
--   1. `puede_editar_presupuesto(v_obra_id)` -> `puede_emitir_certificado(v_obra_id)`, con un
--      mensaje de error que dice quién emite en esa obra en vez de "sin autoridad" a secas.
--   2. Se elimina el guard "no emite el mismo que propuso" (0124). La conformidad sigue exigida
--      igual: son dos cosas distintas y solo se va una.
--
-- Lo que NO cambia: el candado del 100% (`calcular_excesos_certificado`), el monto > 0, y los
-- congelamientos de anticipo/fondo/plazo/CAC/cotización, todos en el mismo lugar.
--
-- `puede_editar_presupuesto` no desaparece del proyecto: sigue gobernando la edición del
-- presupuesto, `marcar_certificado_impactado`, `subir_pdf_firmado_certificado`, la anulación y los
-- adicionales. Lo que cambia es que deja de significar "firma todos los actos formales del
-- certificado" y pasa a significar, más chico y más honesto, "edita el presupuesto y cierra el
-- cobro".

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

  -- Autoridad de emisión (0125): la escalera del paso 1.
  if not puede_emitir_certificado(v_obra_id) then
    raise exception 'sin autoridad para emitir este certificado: en esta obra lo emite %',
      case quien_emite_certificado(v_obra_id)
        when 'profesional' then 'el profesional'
        when 'cliente' then 'el cliente (o su apoderado)'
        else 'el administrador de la obra'
      end;
  end if;

  -- Acuerdo entre partes (0124). Sigue igual: si hay contraparte, se emite lo acordado. Lo que se
  -- fue en la 0125 es la condición de que el emisor no fuera quien propuso -- el profesional puede
  -- proponer y emitir su propia propuesta una vez que el constructor la conformó. Que sean dos
  -- personas distintas ya lo garantiza la conformidad (check certificados_acuerdo_conformidad_check).
  if hay_contraparte_certificacion(v_obra_id, v_propuesto_por) then
    if v_acuerdo_estado <> 'conforme' then
      raise exception 'este certificado todavía no tiene la conformidad de la otra parte';
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
      'acuerdo_estado', v_acuerdo_estado,
      'emite_por_ser', quien_emite_certificado(v_obra_id)
    )
  );
end;
$$;

grant execute on function emitir_certificado(uuid, boolean) to authenticated;
revoke execute on function emitir_certificado(uuid, boolean) from public, anon;


-- =====================================================================
-- Verificación a mano después de aplicar (SQL Editor + app)
-- =====================================================================
--
-- Igual que la 0124: el SQL Editor corre como service_role sin usuario logueado, así que auth.uid()
-- es null y tanto la RLS como tiene_rol_en_obra dan false. La escalera SÍ se puede leer desde acá
-- (quien_emite_certificado no mira al usuario); el resto va desde la app.
--
-- 1) La escalera, obra por obra, sin usuario:
--    select o.nombre, quien_emite_certificado(o.id) from obras o where o.obra_madre_id is null;
--    -- una obra con profesional activo -> 'profesional';
--    -- una sin profesional y con cliente -> 'cliente';
--    -- una de un solo usuario -> 'admin_maestro'.
--
-- 2) *** LA QUE PROTEGE LO QUE YA ANDA: en una obra de un solo usuario (admin_maestro, sin
--    profesional, sin cliente, sin constructor), emitir tiene que seguir funcionando exactamente
--    como hasta hoy. Si esto falla, la migración rompió el caso más común.
--
-- 3) El cambio de fondo, con profesional + constructor en la misma obra:
--    - el constructor intenta emitir -> 'sin autoridad ... en esta obra lo emite el profesional',
--      TENGA O NO `puede_editar_presupuesto` (esto es lo que cambia respecto de la 0121);
--    - el profesional propone el avance, el constructor da la conformidad, y el profesional emite
--      SU PROPIA propuesta -> tiene que funcionar (esto es lo que cambia respecto de la 0124);
--    - el constructor propone, el profesional conforma, el profesional emite -> funciona.
--
-- 4) Sin profesional, con constructor y cliente:
--    - el constructor propone y el cliente conforma (0124);
--    - el constructor intenta emitir -> 'lo emite el cliente (o su apoderado)';
--    - el cliente emite -> funciona. Y el cliente ve el borrador y la vista previa, porque la RLS de
--      la 0124 le muestra el borrador justamente cuando no hay profesional.
--    - con un apoderado con delegación vigente en lugar del cliente -> también emite.
--    - con la delegación del apoderado VENCIDA y sin cliente_principal -> la escalera baja a
--      'admin_maestro'.
--
-- 5) Que no se haya movido nada de lo demás: marcar_certificado_impactado sigue siendo del que
--    cobra (admin/constructor con el permiso), subir_pdf_firmado_certificado sigue pidiendo
--    puede_editar_presupuesto, y proponer/resolver anulación sigue siendo de las dos partes
--    técnicas. Ninguna de las tres se tocó acá.
