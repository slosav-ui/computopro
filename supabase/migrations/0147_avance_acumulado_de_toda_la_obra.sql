-- 0147 -- El avance acumulado de todas las partidas de una obra, de una sola vez
--
-- Pedido de Seba (2026-09-14), probando la obra real de Galpón Mix:
--
--   *"Cuando vaya a hacer el certificado 2 tengo que ver que la platea lleva 15% y le queda 85%, y
--   así con cada partida. Si no, no sé sobre qué cargar. En mi PDF cada certificado arrastra lo
--   anterior."*
--
-- **El dato ya existe y la app ya lo usa**: `calcular_avance_acumulado_subitem` (`0056`) es lo que
-- hace funcionar el candado del 100% y lo que detecta los excesos al emitir. Lo que faltaba no era
-- el cálculo: era poder **verlo** mientras se carga el avance, en vez de descubrirlo recién cuando
-- la base rechaza un exceso.
--
-- ================== POR QUÉ UNA FUNCIÓN Y NO UNA CONSULTA EN DART ==================
--
-- La regla de qué certificados cuentan —todos menos `borrador` y `anulado`— vive hoy en un solo
-- lugar. Escribir esa misma condición en un `select` de Dart la pondría en dos, y el día que cambie
-- (por ejemplo, si un estado nuevo tuviera que contar o dejar de contar) el candado del 100% y lo
-- que muestra la pantalla dirían cosas distintas **sin que nada falle**. Es exactamente la forma de
-- error que ya pasó en este proyecto con la delegación (`0144`).
--
-- Así que la condición se escribe una sola vez más, acá, y queda al lado de la original para que se
-- vean juntas.
--
-- **No reemplaza a `calcular_avance_acumulado_subitem`**: esa sigue existiendo para el caso de una
-- sola partida (el historial). Esta es la misma pregunta para toda una obra, en una llamada en vez
-- de una por partida -- con 24 partidas eran 24 viajes a la base cada vez que se abre la pantalla.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project -> SQL Editor). No ejecutado automáticamente
-- por Claude Code: sin acceso a la base de datos desde este entorno.


create or replace function calcular_avance_acumulado_obra(p_obra_id uuid)
returns table(obra_subitem_id uuid, acumulado numeric)
language sql
stable
set search_path = public
as $$
  select
    os.id,
    coalesce(sum(csa.porcentaje_periodo) filter (
      where c.estado not in ('borrador', 'anulado')
    ), 0)
  from obra_subitems os
  -- LEFT JOIN, no INNER: una partida sin ningún avance tiene que devolver 0, no desaparecer. Es la
  -- diferencia entre "le queda el 100% por certificar" y "esta partida no existe", y la pantalla
  -- que carga avance necesita justamente las que están en cero.
  left join certificado_subitems_avance csa on csa.obra_subitem_id = os.id
  left join certificados c on c.id = csa.certificado_id
  where os.obra_id = p_obra_id
  group by os.id;
$$;

grant execute on function calcular_avance_acumulado_obra(uuid) to authenticated;
revoke execute on function calcular_avance_acumulado_obra(uuid) from public, anon;

comment on function calcular_avance_acumulado_obra(uuid) is
  'Avance acumulado de cada partida de la obra, contando solo certificados que no sean borrador ni '
  'anulados -- misma regla que calcular_avance_acumulado_subitem (0056), escrita una sola vez acá '
  'para toda la obra. Las partidas sin avance devuelven 0, no se omiten.';


-- =====================================================================
-- Verificación a mano después de aplicar
-- =====================================================================
--
-- Sobre la obra real de Galpón Mix, que tiene el certificado 1 emitido con 6 partidas:
--
-- 1) Devuelve TODAS las partidas, no solo las certificadas:
--    select count(*) from calcular_avance_acumulado_obra('<obra>');
--    -- tiene que dar 24, no 6.
--
-- 2) Los seis avances del certificado 1, con sus porcentajes del PDF:
--    select a.acumulado, s.descripcion
--    from calcular_avance_acumulado_obra('<obra>') a
--    join obra_subitems os on os.id = a.obra_subitem_id
--    join subitems s on s.id = os.subitem_id
--    where a.acumulado > 0
--    order by a.acumulado desc;
--    -- Demoliciones 100, Replanteos 15, Movimientos de suelos 10, cloacal 10, platea 9, metálica 8.
--
-- 3) *** QUE DIGA LO MISMO QUE LA FUNCIÓN VIEJA, que es el punto de escribirla una sola vez:
--    select a.obra_subitem_id, a.acumulado, calcular_avance_acumulado_subitem(a.obra_subitem_id) as vieja
--    from calcular_avance_acumulado_obra('<obra>') a
--    where a.acumulado is distinct from calcular_avance_acumulado_subitem(a.obra_subitem_id);
--    -- tiene que dar CERO filas. Si devuelve alguna, las dos reglas se separaron y el candado del
--    -- 100% y la pantalla van a discrepar.
--
-- 4) Que un certificado anulado no cuente: anular uno y volver a correr el punto 2 -- los
--    porcentajes de ese certificado tienen que desaparecer del acumulado.
