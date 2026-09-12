-- Adicionales, Tanda 1 (docs/adicionales_quitas_demasias_diagnostico.md §11): schema + cálculo de
-- precio + creación. Sin aprobación todavía -- eso es la Tanda 2, después de aplicar y verificar
-- esta (mismo criterio que ya separó las dos tandas de la pieza 4 de Gestión de Obra: lo que se
-- puede probar sin necesitar el circuito completo con dos roles, primero).
--
-- Las 5 ambigüedades del diagnóstico, cerradas por Seba (2026-09-13):
-- A. Costo base manual, no composición de APU -- "el que lo cotiza pone su precio". Composición
--    propia queda como extensión futura, no parte de esta pieza.
-- B. La cascada se calcula en la base (calcular_precio_adicional, más abajo) -- mismo criterio que
--    el resto del proyecto, "el dinero se calcula server-side".
-- C. Corrección sobre el pedido original: los 6 conceptos de Factor K son la estructura de costos
--    del contratista, no algo que el cliente elija -- el adicional los hereda TAL CUAL del
--    contrato (vigente en el momento de aprobar, Tanda 2), sin togglearlos uno por uno. Lo único
--    que se elige por adicional es si lleva impuestos y si incluye materiales.
-- D. La foto (Tanda 2, config congelada) se toma al APROBAR, simétrico al presupuesto -- antes de
--    aprobado es una propuesta y puede cambiar (por eso acá, mientras está pendiente, el monto se
--    recalcula en cada edición, nunca queda fijo).
-- E. Sin restricción de rol para crear -- cualquier miembro de la obra puede solicitar un
--    adicional (la política `modificaciones_obra_insert`, 0004, ya alcanza tal cual: no hace falta
--    tocarla). La barrera real es la aprobación (Tanda 2), no la creación.
--
-- SIMPLIFICACIÓN EXPLÍCITA, marcada para que la confirmes -- no la des por buena en silencio:
-- "Gestión de materiales de terceros" (el 6º concepto) NO se aplica acá. Ese concepto solo tiene
-- sentido cuando existe una partida real con un Costo-Costo separable en materiales/mano de obra,
-- para comparar la vista "con" contra "sin materiales" de la MISMA partida (0077/0078) -- un
-- adicional cotizado a mano, con un solo número, no tiene ese split y no hay una vista alternativa
-- que comparar. Los otros 5 conceptos (GG, Imprevistos, EPP, Costo Financiero, Beneficio) sí
-- aplican siempre, secuenciales, igual que la cascada real. Si esto no es lo que querías decir con
-- "hereda los seis conceptos", avisame antes de que se use en producción -- es un cambio de una
-- línea en `calcular_precio_adicional`, no una migración nueva.
--
-- `incluye_materiales`: se guarda como dato descriptivo de qué pactó este adicional (para la
-- etiqueta corta de §10.1 cuando difiere del contrato), pero -- dada la simplificación de arriba --
-- no cambia el cálculo del monto, porque no hay ningún split materiales/mano de obra que aplicarle.
-- `incluye_impuestos` sí cambia el cálculo: es el único de los dos toggles que corresponde a un
-- paso real de la cascada (multiplicar o no por el total de impuestos vigente).
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor), después de `0111`. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

-- =====================================================================
-- Paso 1 — columnas nuevas, solo para tipo='adicional'
-- =====================================================================
--
-- `cantidad` (NOT NULL desde 0002, sin default) sigue exigiendo un valor para todo tipo -- para
-- adicional no representa nada físico (es un monto de una sola vez, no cantidad × precio unitario),
-- así que se fija en 1 por convención, mismo criterio que ya usa `ajuste_contrato` (0008: "no hay
-- cantidad física distinta de un precio unitario"). `precio_unitario_heredado` queda sin usar para
-- este tipo, como ya lo está para demasia/quita -- no se le agrega ninguna restricción nueva.
alter table modificaciones_obra
  add column costo_costo_base numeric,
  add column incluye_materiales boolean not null default true,
  add column incluye_impuestos boolean not null default true;

alter table modificaciones_obra
  add constraint modificaciones_obra_adicional_check check (
    tipo <> 'adicional'
    or (costo_costo_base is not null and costo_costo_base >= 0 and cantidad = 1)
  );

-- =====================================================================
-- Paso 2 — calcular_precio_adicional: la cascada, sin derivar nada de una composición
-- =====================================================================
--
-- Lee `obra_presupuesto_config`/`obra_impuestos` VIGENTES -- mientras el adicional está pendiente,
-- este es justamente el comportamiento que hace falta (Tanda 2 lo vuelve a llamar al aprobar, para
-- congelar el resultado de ESE momento en la foto propia). `security definer` + `is_obra_member`
-- interno, mismo patrón que el resto de las funciones de precio del proyecto.
create or replace function calcular_precio_adicional(
  p_obra_id uuid,
  p_costo_costo_base numeric,
  p_incluye_impuestos boolean
)
returns numeric
language sql security definer set search_path = public stable as $$
  with autorizado as (
    select is_obra_member(p_obra_id) as ok
  ),
  config as (
    select gg_pct, imprevistos_pct, epp_pct, costo_financiero_pct, beneficio_pct
    from obra_presupuesto_config c
    cross join autorizado a
    where c.obra_id = p_obra_id and a.ok
  ),
  impuestos as (
    select coalesce(sum(oi.porcentaje), 0) / 100 as impuestos_pct_total
    from obra_impuestos oi
    cross join autorizado a
    where oi.obra_id = p_obra_id and a.ok
  ),
  costo_total_trabajo as (
    -- Mismo producto de factores que la cascada real (0077), acotado a los 5 conceptos que
    -- aplican acá -- ver la simplificación explicada en la cabecera de este archivo.
    select
      coalesce(p_costo_costo_base, 0)
        * (1 + co.gg_pct / 100) * (1 + co.imprevistos_pct / 100) * (1 + co.epp_pct / 100)
        * (1 + co.costo_financiero_pct / 100) * (1 + co.beneficio_pct / 100) as v
    from config co
  )
  select ctt.v * (1 + case when p_incluye_impuestos then imp.impuestos_pct_total else 0 end)
  from costo_total_trabajo ctt
  cross join impuestos imp;
$$;

grant execute on function calcular_precio_adicional(uuid, numeric, boolean) to authenticated;
revoke execute on function calcular_precio_adicional(uuid, numeric, boolean) from public, anon;

-- =====================================================================
-- Paso 3 — recalcular monto_total en vivo mientras el adicional sigue pendiente
-- =====================================================================
--
-- Mismo patrón que `calcular_monto_periodo_avance` (0052): trigger BEFORE INSERT OR UPDATE, no
-- cálculo en Dart. Se aplica a la tabla entera (todos los tipos pasan por acá) pero es no-op
-- inmediato para todo lo que no sea `adicional` -- demasia/quita/ajuste_contrato no cambian de
-- comportamiento. Recalcula solo mientras `estado = 'pendiente'` -- una vez aprobado o rechazado,
-- el monto no se vuelve a tocar acá (Tanda 2 lo congela en la aprobación; un rechazado no debería
-- volver a escribirse, y si se reabre alguna vez, ese es el momento de decidir si corresponde
-- recalcular de nuevo, no algo que se resuelve solo).
create or replace function calcular_monto_total_adicional()
returns trigger language plpgsql as $$
begin
  if new.tipo = 'adicional' and new.estado = 'pendiente' then
    new.monto_total := calcular_precio_adicional(
      new.obra_id, new.costo_costo_base, new.incluye_impuestos
    );
  end if;
  return new;
end;
$$;

create trigger modificaciones_obra_calcular_monto_adicional
  before insert or update on modificaciones_obra
  for each row execute function calcular_monto_total_adicional();

-- =====================================================================
-- Verificación
-- =====================================================================
--
-- 1) Insertar un adicional de prueba (costo_costo_base = 1000, incluye_impuestos = true, sin
--    mandar monto_total) -- la fila queda con monto_total = 1000 × cascada de los 5 conceptos ×
--    (1 + impuestos vigentes de la obra). Comparar a mano contra la config real de esa obra.
-- 2) Mismo adicional con incluye_impuestos = false -- monto_total sin el último factor,
--    verificable como monto_total_con_impuestos / (1 + impuestos_pct_total).
-- 3) Editar costo_costo_base de un adicional pendiente (UPDATE) -- monto_total se recalcula solo,
--    sin tocarlo a mano.
-- 4) Demasía/quita/ajuste_contrato existentes: insertar o editar una fila de esos tipos -- el
--    trigger corre pero no toca monto_total (sigue siendo lo que la app ya calculaba antes de esta
--    migración para esos tipos).
-- 5) anon/authenticated sin membresía de la obra: calcular_precio_adicional da `null` (autorizado.ok
--    en false vacía las CTEs config/impuestos, la consulta final queda sin filas) -- Dart lo
--    resuelve a 0 en la vista previa (`(data as num?)?.toDouble() ?? 0.0`), pero la función en sí
--    no expone ningún dato de otra obra ni tira error.
