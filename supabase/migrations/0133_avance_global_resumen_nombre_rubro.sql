-- 0133 -- El resumen del avance global devuelve también el nombre del rubro
--
-- Sale de poner el bloque "cargado como avance global" en `DetalleCertificadoScreen` -- el
-- certificado ya emitido, que es el documento que el cliente aprueba y paga. Decisión de Seba
-- (2026-09-14): *"si se midió global, tiene que saberlo. Si no, firma un detalle que parece medido
-- partida por partida y no lo es."*
--
-- EL PROBLEMA, chico y concreto: `certificado_avance_global_resumen` (0132) devuelve `rubro_id` y
-- nada más. La vista previa podía nombrarlo porque ya tenía cargado el catálogo de rubros para
-- armar el desglose; **el detalle del certificado no**, y para mostrar "Estructura" en vez de un
-- UUID tendría que traerse el catálogo entero de rubros en cada apertura, sumando dos repositorios
-- y una consulta a una pantalla que hoy no los necesita.
--
-- El nombre está en `rubros`, a un join de distancia de la función. Traerlo de la base es una línea
-- acá y le ahorra una consulta a **cada** pantalla que muestre esto -- hoy dos, y la de la vista
-- previa se simplifica de paso: venía buscando el nombre al revés, recorriendo las partidas del
-- certificado hasta encontrar una de ese rubro, y devolvía "Un rubro" cuando el reparto de ese
-- rubro se había corregido a cero y no quedaba ninguna.
--
-- `drop` + `create` y no `create or replace`: cambia la lista de columnas del `returns table`, y
-- Postgres no permite reemplazar en el lugar cuando eso pasa (mismo caso que
-- `calcular_totales_certificado` en la 0105 y `mis_pendientes` en la 0131). Sin dependencias que
-- romper: la llama la app por RPC y nada más.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project -> SQL Editor), después de `0132`. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

drop function if exists certificado_avance_global_resumen(uuid);

create function certificado_avance_global_resumen(p_certificado_id uuid)
returns table(
  rubro_id uuid,
  rubro_nombre text,          -- 0133: null cuando el alcance fue toda la obra
  porcentaje_cargado numeric,
  porcentaje_efectivo numeric,
  ajustado boolean
)
language sql
stable
security definer
set search_path = public
as $$
  with cert as (
    select c.obra_id from certificados c where c.id = p_certificado_id
  ),
  montos as (
    select * from calcular_monto_obra_subitems((select obra_id from cert))
  )
  select
    g.rubro_id,
    r.nombre as rubro_nombre,
    g.porcentaje_acumulado as porcentaje_cargado,
    e.efectivo as porcentaje_efectivo,
    coalesce(e.efectivo, 0) is distinct from round(g.porcentaje_acumulado, 2) as ajustado
  from certificado_avance_global g
  left join rubros r on r.id = g.rubro_id
  cross join lateral (
    select round(
      sum((calcular_avance_acumulado_subitem(os.id) + coalesce(csa.porcentaje_periodo, 0)) * m.monto_total)
      / nullif(sum(m.monto_total), 0), 2) as efectivo
    from obra_subitems os
    join montos m on m.obra_subitem_id = os.id
    left join certificado_subitems_avance csa
      on csa.obra_subitem_id = os.id and csa.certificado_id = p_certificado_id
    where os.obra_id = (select obra_id from cert)
      and (g.rubro_id is null or os.rubro_id = g.rubro_id)
  ) e
  where g.certificado_id = p_certificado_id
    and is_obra_member((select obra_id from cert));
$$;

grant execute on function certificado_avance_global_resumen(uuid) to authenticated;
revoke execute on function certificado_avance_global_resumen(uuid) from public, anon;

-- `left join rubros`, no `join`: con el alcance "toda la obra" `rubro_id` es null y un join común
-- se comería la fila entera -- el certificado dejaría de decir que se cargó global justo en el caso
-- en que se cargó de la forma más global posible.


-- =====================================================================
-- Verificación
-- =====================================================================
--
-- 1) La firma, ahora de 5 columnas:
--    select pg_get_function_result(oid) from pg_proc
--    where proname = 'certificado_avance_global_resumen';
--
-- 2) Sobre el borrador de la obra de prueba, con rubros cargados:
--    select * from certificado_avance_global_resumen('<borrador>');
--    -- rubro_nombre con el nombre del rubro, y los otros cuatro valores idénticos a los que
--    -- devolvía la 0132 (esta migración no cambia ningún cálculo).
--
-- 3) *** El caso del left join: cargar un avance global de TODA LA OBRA en un certificado y que la
--    fila salga igual, con rubro_id y rubro_nombre en null. Si desaparece, el join quedó mal.
