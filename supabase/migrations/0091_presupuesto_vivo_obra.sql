-- El total de la pantalla inicial (ObrasListScreen) pasa a ser el "presupuesto vivo" de la obra --
-- la suma de todas las partidas tildadas, cantidad × precio final, con la misma cascada de Factor K
-- que ya usa la lista de Cómputo (0090). DECISIÓN DE SEBA: no es un campo editable a mano ni un
-- valor estático -- es lo que el usuario está cotizando en las tres primeras solapas, se actualiza
-- solo a medida que se carga cómputo y respeta el selector de vista de cada obra (con/sin
-- materiales).
--
-- Mismo patrón exacto que `calcular_monto_obra_subitems` (0052) -- rubros de precio manual
-- (usa_apu = false) suman precio_unitario_manual (global o × cantidad según tipo_precio_manual),
-- rubros con APU usan la función batch de precios. La diferencia real, la que importa: usa
-- `calcular_precio_final_apu_subitems` (0090, con la cascada completa) en vez de
-- `calcular_precio_apu_subitems` (sin cascada, la que sigue usando la certificación -- ver nota
-- abajo, eso NO se toca acá).
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado automáticamente
-- por Claude Code: sin acceso a la base de datos desde este entorno.
--
-- CREATE OR REPLACE, no CREATE: Seba ya había corrido este archivo una vez -- misma firma
-- (argumentos y tipo de retorno sin cambios), así que reemplaza sin necesitar DROP. A diferencia de
-- un DROP+CREATE, esto conserva el GRANT/REVOKE que ya tenía la función de la corrida anterior --
-- las dos sentencias de abajo quedan igual, ahora son idempotentes en vez de necesarias.

create or replace function calcular_presupuesto_vivo_obra(p_obra_id uuid)
returns numeric
language sql security definer set search_path = public stable as $$
  with autorizado as (
    -- SECURITY DEFINER bypassa la RLS de obra_subitems, así que el chequeo de membresía se repite
    -- acá a mano -- mismo motivo y mismo patrón que calcular_monto_obra_subitems (0052).
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
      case tipo_precio_manual
        when 'global' then coalesce(precio_unitario_manual, 0)
        else cantidad * coalesce(precio_unitario_manual, 0)
      end as monto
    from base
    where usa_apu = false
  ),
  apu_ids as (
    select array_agg(subitem_id) as ids from base where usa_apu = true
  ),
  apu_precios as (
    -- unnest(null) da 0 filas, no error -- caso obra sin ninguna partida de APU tildada todavía.
    select * from calcular_precio_final_apu_subitems(p_obra_id, (select ids from apu_ids))
  ),
  apu as (
    select b.cantidad * p.precio_final as monto
    from base b
    join apu_precios p on p.subitem_id = b.subitem_id
    where b.usa_apu = true
  )
  select coalesce(sum(monto), 0)
  from (select monto from manual union all select monto from apu) t;
$$;

grant execute on function calcular_presupuesto_vivo_obra(uuid) to authenticated;
revoke execute on function calcular_presupuesto_vivo_obra(uuid) from public, anon;

-- =====================================================================
-- PENDIENTE ANOTADO, NO SE TOCA ACÁ -- gravedad alta, para la pieza de Gestión de Obra
-- =====================================================================
--
-- `calcular_monto_obra_subitems` (0052) sigue usando `calcular_precio_apu_subitems` (SIN la
-- cascada de Factor K) -- es la función que alimenta `certificado_subitems_avance.monto_periodo`
-- (el trigger `calcular_monto_periodo_avance`, 0052) y por lo tanto todo certificado que se emite.
--
-- CONFIRMADO POR SEBA (2026-09-08): esto es un bug real, no una decisión de diseño -- un
-- certificado tiene que facturar al precio final pactado (con Gastos Generales, Imprevistos, EPP,
-- Costo Financiero, Beneficio e impuestos), no al costo puro de insumos y mano de obra. Se certifica
-- avance al precio pactado, no al costo. El origen más probable: `calcular_monto_obra_subitems`
-- (0052, 2 de septiembre) se escribió antes de que existiera Factor K (`calcular_factor_k_subitem`,
-- 0077/0078, varios días después) -- se conectó a lo único que había en ese momento y nadie volvió
-- a actualizarla cuando se construyó la cascada completa.
--
-- Impacto si se confirma en producción: todo certificado emitido hasta hoy podría estar facturando
-- muy por debajo de lo que corresponde -- la diferencia entre costo puro y precio final con la
-- cascada completa no es un redondeo, es GG+Imprevistos+EPP+CF+Beneficio+Impuestos.
--
-- Por qué NO se toca en esta migración: cambiar la base de `calcular_monto_obra_subitems` no
-- afecta certificados ya emitidos (el monto queda congelado al emitir, `emitir_certificado` lo
-- snapshotea a `certificados.monto`) -- pero SÍ cambia cuánto calculan los certificados nuevos
-- desde el momento en que se aplique, y esta pieza (certificación / Gestión de Obra) se trabaja
-- aparte, no ahora. Anotado acá para que quede en el historial de migraciones con la fecha y el
-- porqué, no solo en la conversación que lo encontró.
