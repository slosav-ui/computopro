-- Corrige el bug más grave del diagnóstico (docs/diagnostico_general_producto.md §2.1, punto 1
-- del orden de ejecución): la certificación calculaba sobre costo puro, sin la cascada de Factor K
-- (GG/Imprevistos/EPP/Costo Financiero/Beneficio/Impuestos) -- se le facturaba al cliente el costo
-- de insumos y mano de obra, no el precio pactado. Diagnóstico completo, verificado contra el
-- código antes de escribir esto, en docs/certificacion_correccion_diagnostico.md -- no repetir ese
-- razonamiento acá, solo el resultado.
--
-- Confirmado por Seba (2026-09-08): un certificado tiene que facturar al precio final con la
-- cascada completa. Se certifica avance al precio pactado, no al costo.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado automáticamente
-- por Claude Code: sin acceso a la base de datos desde este entorno.

-- =====================================================================
-- Paso 1 — calcular_monto_obra_subitems: la rama con APU pasa a usar la cascada completa
-- =====================================================================
--
-- Único cambio real: `apu_precios` llama a `calcular_precio_final_apu_subitems` (0090/0092, ya
-- resuelve tipo_presupuesto/aplica_impuestos leyendo la config de la obra por su cuenta) en vez de
-- `calcular_precio_apu_subitems` (0059, sin cascada) -- y `apu` lee `precio_final` en vez de
-- `precio_total`. El resto de la función (rama manual, RLS, columnas de salida) queda idéntico --
-- el trigger que la llama, la vista previa del certificado y la emisión no necesitan saber que
-- cambió nada adentro.
--
-- `create or replace`, no DROP+CREATE: misma firma (argumentos y `returns table`) que 0052, así
-- que conserva el GRANT existente.

create or replace function calcular_monto_obra_subitems(p_obra_id uuid)
returns table(obra_subitem_id uuid, monto_total numeric, tiene_precio_completo boolean)
language sql security definer set search_path = public stable as $$
  with autorizado as (
    -- SECURITY DEFINER bypassa la RLS de obra_subitems, así que el chequeo de membresía se repite
    -- acá a mano — mismo motivo y mismo patrón que calcular_precio_apu_subitems (0034).
    select is_obra_member(p_obra_id) as ok
  ),
  base as (
    select os.id as obra_subitem_id, os.cantidad, os.precio_unitario_manual,
           os.subitem_id, r.usa_apu, r.tipo_precio_manual
    from obra_subitems os
    join rubros r on r.id = os.rubro_id
    cross join autorizado a
    where os.obra_id = p_obra_id and os.es_aplicable = true and a.ok
  ),
  manual as (
    select
      obra_subitem_id,
      case tipo_precio_manual
        when 'global' then coalesce(precio_unitario_manual, 0)
        else cantidad * coalesce(precio_unitario_manual, 0)
      end as monto_total,
      precio_unitario_manual is not null as tiene_precio_completo
    from base
    where usa_apu = false
  ),
  apu_ids as (
    select array_agg(subitem_id) as ids from base where usa_apu = true
  ),
  apu_precios as (
    -- Antes: calcular_precio_apu_subitems (costo puro, sin GG/Imprevistos/EPP/CF/Beneficio/
    -- Impuestos). Ahora: calcular_precio_final_apu_subitems, la misma función que ya usan Cómputo,
    -- la Solapa APU y el total del dashboard -- una sola cascada, un solo lugar donde vive la
    -- cuenta, certificación deja de ser la excepción que quedó atrás.
    select * from calcular_precio_final_apu_subitems(p_obra_id, (select ids from apu_ids))
  ),
  apu as (
    select
      b.obra_subitem_id,
      b.cantidad * p.precio_final as monto_total,
      (p.insumos_total > 0 and p.insumos_con_precio = p.insumos_total) as tiene_precio_completo
    from base b
    join apu_precios p on p.subitem_id = b.subitem_id
    where b.usa_apu = true
  )
  select * from manual
  union all
  select * from apu;
$$;

grant execute on function calcular_monto_obra_subitems(uuid) to authenticated;

-- =====================================================================
-- Paso 2 — recalcular los borradores que ya tengan avance cargado
-- =====================================================================
--
-- El trigger calcular_monto_periodo_avance (0052) recalcula monto_periodo SOLO en el INSERT o
-- UPDATE de esa fila puntual -- cambiar la función de arriba no reprocesa filas ya guardadas. Un
-- certificado en borrador que ya tenga algún % cargado antes de correr esto queda con el
-- monto_periodo viejo (costo puro) hasta que esa fila se vuelva a escribir -- silencioso, nadie se
-- entera, exactamente la clase de bug que motivó todo este diagnóstico.
--
-- DECISIÓN (Seba, 2026-09-09): la migración fuerza el recálculo, no deja el problema para después
-- con un aviso. Un usuario real con un borrador a medio cargar cuando esto se aplique no tiene por
-- qué enterarse de que existió un cambio de fórmula ni tiene por qué volver a tocar cada fila a
-- mano -- eso es exactamente el tipo de carga que un usuario no debería pagar por un bug nuestro.
--
-- Mecanismo: un UPDATE que no cambia ningún valor (porcentaje_periodo = porcentaje_periodo) sobre
-- toda fila de certificado_subitems_avance cuyo certificado padre siga en 'borrador' -- Postgres
-- dispara el trigger BEFORE UPDATE igual, sin importar que el valor asignado sea el mismo, y el
-- trigger recalcula monto_periodo con la función ya corregida del Paso 1. No hace falta ningún
-- caso especial: la fila puede seguir en cualquier obra, cualquier subítem, la RLS de la sesión que
-- corre esto en el SQL Editor (service_role) no bloquea nada.
--
-- Sin este paso, "en general" (no solo para el caso de prueba de Seba) cualquier borrador real con
-- avance cargado en el momento de aplicar quedaría con montos mentirosos hasta el próximo toque
-- manual -- lo mismo que causó el bug original, un cambio de fórmula que no llega a todos lados.
--
-- PATRÓN A REPETIR: cualquier migración futura que cambie qué función de precio usa
-- calcular_monto_obra_subitems (o cualquier función que alimente monto_periodo) tiene que incluir
-- este mismo UPDATE -- no es específico de este bug, es la consecuencia de que el trigger solo
-- recalcula al tocar la fila, nunca en el momento en que cambia la fórmula.

update certificado_subitems_avance
set porcentaje_periodo = porcentaje_periodo
where certificado_id in (select id from certificados where estado = 'borrador');

-- =====================================================================
-- Verificación
-- =====================================================================

-- 1) Partida con composición APU y avance certificado real (obra "Galpón Mix", partida 8.11 u
--    otra ya usada en esta sesión): el monto_periodo de la última fila de
--    certificado_subitems_avance para esa partida tiene que coincidir EXACTO con
--    cantidad × calcular_precio_final_apu_subitems(...).precio_final de esa misma partida --
--    el mismo número que ya muestra el bloque de Factor K y el precio de Cómputo.
-- select cantidad, cantidad * (
--   select precio_final from calcular_precio_final_apu_subitems(
--     '<obra_id>'::uuid, array[(select subitem_id from obra_subitems where id = '<obra_subitem_id>')]
--   )
-- ) as monto_esperado
-- from obra_subitems where id = '<obra_subitem_id>';

-- 2) Certificados ya EMITIDOS: su monto no cambió. Confirmar que certificados.monto de cualquier
--    certificado con estado <> 'borrador' es idéntico al valor de antes de correr esta migración
--    (guardar el número antes de aplicar, comparar después).

-- 3) Borrador con avance cargado (si existía alguno antes del Paso 2): su monto_periodo por fila
--    y el total de la vista previa (calcular_totales_certificado) tienen que reflejar la cascada
--    completa inmediatamente después de correr esta migración, sin que nadie haya tocado nada a
--    mano.

-- 4) Candado del 100% (calcular_avance_acumulado_subitem, calcular_excesos_certificado): sigue
--    funcionando igual -- no depende de monto, no lo tocó esta migración.
