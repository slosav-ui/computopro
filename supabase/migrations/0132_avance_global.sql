-- 0132 -- Avance global: un porcentaje por rubro que siembra las filas por partida
--
-- Tanda 4 de "certificar es un acuerdo entre partes" (pedido de Seba). Diagnóstico completo:
-- docs/certificacion_acuerdo_partes_diagnostico.md §6 y §6.1.
--
-- QUÉ RESUELVE: hasta acá el avance se carga partida por partida, y en una obra de 700 subítems eso
-- es media tarde de tipeo para decir algo que el que mide sabe de una: "estructura va por el 40%".
-- Esta migración deja cargar un porcentaje por rubro (o de toda la obra) y que el sistema escriba
-- las filas por partida.
--
-- ================== LO QUE **NO** HACE, Y ES LA MEJOR NOTICIA ==================
--
-- **No hay ninguna cuenta de reparto de plata.** El trigger `calcular_monto_periodo_avance`
-- (0052/0105) ya calcula `monto_del_subítem × porcentaje / 100`. Si todas las partidas del alcance
-- reciben el mismo porcentaje, la plata de cada una **ya sale proporcional a su monto congelado**:
-- el ponderado ocurre por aritmética, no por una función que lo distribuya.
--
-- Entonces lo único que se escribe acá es una función que **siembra las mismas filas que el usuario
-- hubiera cargado a mano**. Consecuencia: el candado del 100% (`calcular_excesos_certificado`), el
-- CAC, `monto_periodo_pactado`, la anulación, `calcular_avance_ponderado_rubros`, la vista previa,
-- los totales y `emitir_certificado` **no se tocan** -- reciben exactamente el mismo tipo de filas
-- que hoy, cargadas por otra puerta.
--
-- ================== LAS TRES DECISIONES DE SEBA (2026-09-14) ==================
--
-- **1. El modo se elige UNA VEZ, al configurar la obra** -- no por certificado. Textual: *"poder
-- elegir por certificado abre la puerta a certificar global lo que conviene y detallado lo que
-- conviene, y eso deja el acumulado sin sentido"*. Es exactamente el riesgo: con el modo suelto,
-- alguien carga global los rubros que van bien y detallado los que van mal, y el número de la obra
-- deja de significar nada. Paso 1 y paso 2.
--
-- **2. El alcance es el RUBRO, y entran varios por certificado** -- "cinco a ocho rubros, no uno
-- solo por obra: es lo que un constructor maneja sin volverse loco, y ya evita el reparto parejo
-- sobre toda la obra". Por eso es una tabla y no dos columnas en `certificados` (paso 3): con dos
-- columnas entraba un alcance por certificado, y descubrirlo después obliga a migrar certificados ya
-- emitidos. Toda la obra de una sigue siendo posible (`rubro_id` null), pero es el caso chico, no el
-- esperado.
--
-- **3. El reparto se puede corregir a mano antes de proponer** -- *"si no, el número es cómodo pero
-- mentiroso: la obra empieza por fundaciones, no por un poco de todo. Y el que firma sabe qué se
-- hizo de verdad"*. Esto NO necesita código nuevo: la RLS de `certificado_subitems_avance` (0052) ya
-- deja editar y borrar filas mientras el certificado esté en borrador. Lo que sí necesita es el
-- paso 5 -- si el reparto se corrigió, el certificado no puede seguir diciendo a secas "avance
-- global del 40%", porque ya no es el reparto que ese número describe.
--
-- ================== EL NÚMERO ES EL ACUMULADO, NO EL DEL PERÍODO ==================
--
-- `certificado_subitems_avance.porcentaje_periodo` es un incremento. La traducción literal ("sumale
-- 15 puntos a cada partida") funciona solo mientras las partidas estén parejas, y se despareja de
-- tres formas normales: una partida que se tilda después y nace en 0; una que ya llegó a 100 y no
-- puede recibir el incremento; o una obra que certificó por partida antes de pasarse a global. En
-- cualquiera de esas, el incremento se aplica disparejo y el número global miente.
--
-- Cargando el ACUMULADO ("el rubro está al 40%"), la función deriva el incremento de cada partida
-- como `40 − su propio acumulado`: se autocorrige, las desparejas convergen solas, y el candado del
-- 100% no se puede violar por construcción, porque nunca se pide más de 100.
--
-- **Y esto conviene tenerlo claro porque va a sorprender:** la corrección a mano de la decisión 3
-- **no se arrastra al período siguiente**. Si en marzo el reparto se corrigió para cargarle todo a
-- fundaciones, en abril el global vuelve a sembrar desde la realidad de cada partida y tiende a
-- emparejarlas de nuevo. Es a propósito: la corrección dice **qué se hizo ese mes**, no una regla de
-- reparto nueva. Si el mes que viene tampoco se avanzó parejo, se vuelve a corregir.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project -> SQL Editor), después de `0131`. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.


-- =====================================================================
-- Paso 1 -- el modo, en `obras`
-- =====================================================================
--
-- En `obras` y al lado de `periodicidad_certificacion`, que es donde ya vive la config de
-- certificación que administra el mismo panel. `not null default 'por_partida'`: todas las obras que
-- existen hoy cargan partida por partida y tienen que seguir exactamente igual.

alter table obras
  add column modo_carga_avance text not null default 'por_partida'
    check (modo_carga_avance in ('por_partida', 'global'));

comment on column obras.modo_carga_avance is
  'Como se carga el avance en esta obra (0132): por_partida (una por una, lo de siempre) | global '
  '(un porcentaje ACUMULADO por rubro que siembra las filas por partida). Se define al configurar '
  'la obra y se congela con el primer certificado emitido -- ver el trigger del paso 2. No es por '
  'certificado a proposito: mezclando modos, el avance de la obra deja de significar algo.';


-- =====================================================================
-- Paso 2 -- el modo se congela con el primer certificado emitido
-- =====================================================================
--
-- "Una sola vez, al configurar la obra" (decisión 1), pero sin trampa cazabobos: mientras la obra no
-- haya emitido nada, cambiar de opinión es gratis y no hay razón para castigarlo. Lo que se bloquea
-- es cambiarlo **después**, y el motivo es concreto: el avance ya certificado quedó medido con una
-- lógica, y a partir del cambio se lee con otra. Nadie va a poder explicar seis meses después por
-- qué las partidas saltaron todas juntas en el certificado 4.
--
-- Trigger y no chequeo en el repositorio: el panel de config escribe con un `update` directo sobre
-- `obras` (`ObraConfigCertificacionRepository`), así que un guard del lado del Dart sería una
-- sugerencia, no una regla.

create or replace function bloquear_cambio_modo_carga_avance()
returns trigger language plpgsql as $$
begin
  if new.modo_carga_avance is distinct from old.modo_carga_avance
     and exists (
       select 1 from certificados c
       where c.obra_id = old.id and c.estado <> 'borrador'
     ) then
    raise exception 'el modo de carga de avance se define al configurar la obra: esta obra ya tiene certificados emitidos, y cambiarlo ahora dejaría el avance ya certificado medido con una lógica y el que viene con otra';
  end if;
  return new;
end;
$$;

create trigger obras_modo_carga_avance_congelado
  before update of modo_carga_avance on obras
  for each row execute function bloquear_cambio_modo_carga_avance();


-- =====================================================================
-- Paso 3 -- `certificado_avance_global`: qué se cargó, y con qué alcance
-- =====================================================================
--
-- Una fila por alcance cargado en ese certificado. `rubro_id` null = toda la obra de una.
--
-- Los dos índices parciales, en vez de un `unique (certificado_id, rubro_id)`: en Postgres dos NULL
-- no chocan entre sí, así que un unique común dejaría cargar "toda la obra" dos veces en el mismo
-- certificado. Y el "un alcance u otro, no los dos" (toda la obra Y rubros sueltos se pisarían) lo
-- aplica la función del paso 4, que es donde se puede explicar con un mensaje.
--
-- Se guarda el porcentaje **como se cargó**, y no se recalcula nunca: es la intención declarada del
-- que midió. Si después el reparto se corrige a mano, lo que cambia es el efectivo, y esos son dos
-- datos distintos que el paso 5 muestra uno al lado del otro.

create table certificado_avance_global (
  id uuid primary key default gen_random_uuid(),
  certificado_id uuid not null references certificados(id) on delete cascade,
  rubro_id uuid references rubros(id),
  porcentaje_acumulado numeric not null
    check (porcentaje_acumulado > 0 and porcentaje_acumulado <= 100),
  cargado_por uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index certificado_avance_global_obra_unico
  on certificado_avance_global (certificado_id) where rubro_id is null;

create unique index certificado_avance_global_rubro_unico
  on certificado_avance_global (certificado_id, rubro_id) where rubro_id is not null;

create index certificado_avance_global_certificado_idx
  on certificado_avance_global (certificado_id);

comment on table certificado_avance_global is
  'Con que porcentaje ACUMULADO y sobre que alcance se cargo el avance global de un certificado '
  '(0132). rubro_id null = toda la obra. Es el registro de como se cargo, no la fuente de la plata: '
  'la plata sale de las filas de certificado_subitems_avance que esta carga siembra, que despues se '
  'pueden corregir a mano (ver certificado_avance_global_resumen).';

alter table certificado_avance_global enable row level security;

-- SELECT: lo ve quien ve el certificado. Sin políticas de INSERT ni UPDATE **a propósito**: la
-- siembra entra solo por `cargar_avance_global`, que es security definer -- si se pudiera insertar
-- una fila a mano, el certificado podría declarar un global que nunca se repartió.
create policy certificado_avance_global_select on certificado_avance_global for select
using (
  is_obra_member((select obra_id from certificados where id = certificado_id))
);

-- DELETE sí, con las mismas condiciones que las filas de avance: borrar la declaración de un alcance
-- cargado por error tiene que ser posible mientras el certificado siga en borrador. Ojo, y la UI lo
-- dice: **borrar esta fila no borra las filas por partida que sembró** -- quedan a la vista en la
-- carga, que es donde se editan.
create policy certificado_avance_global_delete on certificado_avance_global for delete
using (
  exists (
    select 1 from certificados c
    where c.id = certificado_id and c.estado = 'borrador'
      and (tiene_rol_en_obra(c.obra_id, 'admin_maestro')
        or tiene_rol_en_obra(c.obra_id, 'profesional')
        or tiene_rol_en_obra(c.obra_id, 'constructor'))
  )
);

create trigger set_updated_at_certificado_avance_global
  before update on certificado_avance_global
  for each row execute function set_updated_at();


-- =====================================================================
-- Paso 4 -- cargar_avance_global: la única lógica nueva de la migración
-- =====================================================================
--
-- EL ALCANCE SALE DE `calcular_monto_obra_subitems`, no de `obra_subitems ... where es_aplicable`, y
-- la diferencia importa: en una obra congelada esa función lee el **snapshot**
-- (`presupuesto_subitems_congelado`), no el tildado de hoy (ver 0111). Usando la misma fuente que
-- usa el trigger para calcular la plata, el conjunto que recibe porcentaje y el conjunto que recibe
-- plata son el mismo por construcción -- no hay forma de que una partida quede con porcentaje y sin
-- monto, ni al revés.
--
-- Autoridad: los mismos tres roles que ya cargan avance (la RLS de `certificado_subitems_avance`,
-- 0052). Cargar global no es un acto distinto de cargar avance: es el mismo, con otra granularidad.
--
-- Las partidas que ya están en el porcentaje pedido, o por encima, **no reciben fila** (y si tenían
-- una de una carga anterior de este mismo borrador, se les borra): una partida no retrocede, y una
-- fila en 0 no existe (`porcentaje_periodo > 0` desde la 0052).

create or replace function cargar_avance_global(
  p_certificado_id uuid,
  p_rubro_id uuid,
  p_porcentaje_acumulado numeric
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_obra_id uuid;
  v_estado text;
  v_modo text;
  v_filas int;
begin
  select c.obra_id, c.estado into v_obra_id, v_estado
  from certificados c where c.id = p_certificado_id;

  if v_obra_id is null then
    raise exception 'certificado % no encontrado', p_certificado_id;
  end if;

  if v_estado <> 'borrador' then
    raise exception 'el avance se carga en el borrador (estado actual: %)', v_estado;
  end if;

  if not (tiene_rol_en_obra(v_obra_id, 'admin_maestro')
       or tiene_rol_en_obra(v_obra_id, 'profesional')
       or tiene_rol_en_obra(v_obra_id, 'constructor')) then
    raise exception 'sin autoridad para cargar avance en esta obra';
  end if;

  select modo_carga_avance into v_modo from obras where id = v_obra_id;

  if v_modo <> 'global' then
    raise exception 'esta obra carga el avance partida por partida — el modo de carga se define al configurar la obra';
  end if;

  if p_porcentaje_acumulado is null
     or p_porcentaje_acumulado <= 0
     or p_porcentaje_acumulado > 100 then
    raise exception 'el avance global es el porcentaje ACUMULADO del alcance, entre 0 y 100 (recibido: %)', p_porcentaje_acumulado;
  end if;

  if p_rubro_id is null then
    if exists (
      select 1 from certificado_avance_global g
      where g.certificado_id = p_certificado_id and g.rubro_id is not null
    ) then
      raise exception 'este certificado ya tiene avance global cargado por rubro: se carga toda la obra de una, o rubro por rubro, no las dos cosas juntas';
    end if;
  else
    if exists (
      select 1 from certificado_avance_global g
      where g.certificado_id = p_certificado_id and g.rubro_id is null
    ) then
      raise exception 'este certificado ya tiene un avance global de toda la obra: no se le puede sumar además un rubro suelto';
    end if;
  end if;

  -- Las que ya llegaron: si quedó una fila de una carga anterior de este borrador, se va. El
  -- `delete` va PRIMERO para que bajar el número cargado (corregir un 40 que era 30) limpie de
  -- verdad lo que había, en vez de dejar filas viejas más altas dando vueltas.
  delete from certificado_subitems_avance csa
  using (
    select os.id as obra_subitem_id, calcular_avance_acumulado_subitem(os.id) as acumulado
    from obra_subitems os
    join calcular_monto_obra_subitems(v_obra_id) m on m.obra_subitem_id = os.id
    where os.obra_id = v_obra_id
      and (p_rubro_id is null or os.rubro_id = p_rubro_id)
  ) a
  where csa.certificado_id = p_certificado_id
    and csa.obra_subitem_id = a.obra_subitem_id
    and round(p_porcentaje_acumulado - a.acumulado, 2) <= 0;

  -- Y la siembra. `monto_periodo` lo calcula el trigger de la 0052/0105, igual que en una carga a
  -- mano: acá no se escribe ni un peso.
  insert into certificado_subitems_avance (certificado_id, obra_subitem_id, porcentaje_periodo, creado_por)
  select p_certificado_id, a.obra_subitem_id, round(p_porcentaje_acumulado - a.acumulado, 2), auth.uid()
  from (
    select os.id as obra_subitem_id, calcular_avance_acumulado_subitem(os.id) as acumulado
    from obra_subitems os
    join calcular_monto_obra_subitems(v_obra_id) m on m.obra_subitem_id = os.id
    where os.obra_id = v_obra_id
      and (p_rubro_id is null or os.rubro_id = p_rubro_id)
  ) a
  where round(p_porcentaje_acumulado - a.acumulado, 2) > 0
  on conflict (certificado_id, obra_subitem_id)
  do update set porcentaje_periodo = excluded.porcentaje_periodo,
                creado_por = excluded.creado_por;

  get diagnostics v_filas = row_count;

  if v_filas = 0 then
    raise exception 'no hay nada que certificar con ese porcentaje: todas las partidas del alcance ya están en % o más', p_porcentaje_acumulado;
  end if;

  -- La declaración de cómo se cargó. Delete + insert en vez de `on conflict`: son dos índices
  -- parciales distintos según el alcance, y `is not distinct from` resuelve el null de "toda la
  -- obra" sin dos ramas.
  delete from certificado_avance_global
  where certificado_id = p_certificado_id
    and rubro_id is not distinct from p_rubro_id;

  insert into certificado_avance_global (certificado_id, rubro_id, porcentaje_acumulado, cargado_por)
  values (p_certificado_id, p_rubro_id, p_porcentaje_acumulado, auth.uid());

  insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (
    v_obra_id, auth.uid(), 'cargar_avance_global', 'certificado', p_certificado_id,
    jsonb_build_object(
      'rubro_id', p_rubro_id,
      'alcance', case when p_rubro_id is null then 'obra' else 'rubro' end,
      'porcentaje_acumulado', p_porcentaje_acumulado,
      'partidas_sembradas', v_filas
    )
  );
end;
$$;

grant execute on function cargar_avance_global(uuid, uuid, numeric) to authenticated;
revoke execute on function cargar_avance_global(uuid, uuid, numeric) from public, anon;


-- =====================================================================
-- Paso 5 -- lo cargado y lo efectivo, uno al lado del otro
-- =====================================================================
--
-- Esta función existe por la decisión 3, y es la que evita que el documento mienta en el otro
-- sentido. Si el reparto se corrige a mano -- que es justamente lo que Seba quiere que se pueda
-- hacer, porque *"la obra empieza por fundaciones, no por un poco de todo"* -- el certificado ya no
-- puede decir a secas "avance global del 40%": el 40% describe un reparto que dejó de ser el que
-- tiene adentro.
--
-- Devuelve las dos cosas: **cargado** (lo que se declaró, tal cual) y **efectivo** (el avance
-- ponderado por monto que de verdad quedó en las filas, incluida la corrección), más el `ajustado`
-- que dice si difieren. La pantalla muestra los dos números cuando difieren; los dos son ciertos y
-- los dos hacen falta.
--
-- El efectivo se calcula con la misma cuenta que `calcular_avance_ponderado_rubros` (0052) --
-- acumulado por partida ponderado por su monto -- pero sumándole lo de ESTE borrador, que esa
-- función no ve (excluye borradores a propósito).

create or replace function certificado_avance_global_resumen(p_certificado_id uuid)
returns table(
  rubro_id uuid,
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
    g.porcentaje_acumulado as porcentaje_cargado,
    e.efectivo as porcentaje_efectivo,
    coalesce(e.efectivo, 0) is distinct from round(g.porcentaje_acumulado, 2) as ajustado
  from certificado_avance_global g
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


-- =====================================================================
-- Verificación a mano después de aplicar
-- =====================================================================
--
-- 1) El modo, y que lo que ya existe no se movió:
--    select nombre, modo_carga_avance from obras where obra_madre_id is null;
--    -- TODAS en 'por_partida'. Y una obra en 'por_partida' tiene que certificar exactamente igual
--    -- que antes de esta migración: cargar partida por partida, proponer, conformar, emitir.
--    -- Si esto falla, la migración tocó lo que no tenía que tocar.
--
-- 2) El congelamiento del modo (paso 2), en una obra que YA tiene un certificado emitido:
--    update obras set modo_carga_avance = 'global' where id = '<obra con certificados>';
--    -- tiene que fallar con el mensaje del trigger. Y en una obra sin nada emitido, tiene que
--    -- dejar (ese es el caso "todavía estoy configurando").
--
-- 3) *** LA SIEMBRA, en una obra en modo global con el presupuesto congelado y un borrador abierto:
--    select cargar_avance_global('<borrador>', '<rubro estructura>', 40);
--    select count(*), sum(porcentaje_periodo), sum(monto_periodo)
--    from certificado_subitems_avance where certificado_id = '<borrador>';
--    -- una fila por partida del rubro, todas en 40 (si el rubro venía en cero), y la suma de
--    -- monto_periodo tiene que dar el 40% del monto del rubro.
--
-- 4) *** QUE EL PONDERADO SEA EL DE VERDAD, que es el punto de toda la pieza: la suma de
--    `monto_periodo` de un rubro cargado al 40% tiene que ser el 40% de lo que vale ese rubro
--    (`calcular_avance_ponderado_rubros` devuelve `monto_ponderado` por rubro). Si el rubro tiene
--    partidas caras y baratas mezcladas, esto es lo que prueba que el reparto quedó ponderado por
--    monto y no repartido en partes iguales.
--
-- 5) Varios rubros en el mismo certificado (decisión 2): cargar 5 u 8 rubros con porcentajes
--    distintos, y que cada uno tenga sus partidas en su propio porcentaje.
--
-- 6) Que no se puedan mezclar alcances: con rubros ya cargados, `cargar_avance_global(cert, null, 30)`
--    tiene que fallar con el mensaje; y al revés también.
--
-- 7) EL ACUMULADO, que es lo que distingue esta pieza de "sumar puntos". Con el rubro ya certificado
--    al 40% en un certificado EMITIDO, en el borrador siguiente:
--    select cargar_avance_global('<borrador nuevo>', '<mismo rubro>', 55);
--    -- las filas nuevas tienen que salir en 15 (55 − 40), no en 55.
--    select cargar_avance_global('<borrador nuevo>', '<mismo rubro>', 30);
--    -- tiene que fallar: "no hay nada que certificar con ese porcentaje".
--
-- 8) Una partida despareja: tildar una partida nueva en un rubro que ya va por el 55% (o cargarle a
--    una sola partida un avance por separado antes de la carga global). Al cargar el rubro al 70%,
--    la nueva tiene que recibir 70 y las viejas 15 -- **cada una lo que le falta**. Ese es el
--    autocorregido, y es la razón por la que el número que se carga es el acumulado.
--
-- 9) *** LA CORRECCIÓN A MANO (decisión 3), de punta a punta:
--    - cargar el rubro al 40%;
--    - editar a mano las filas (subir fundaciones, bajar las demás) desde la pantalla de carga;
--    - select * from certificado_avance_global_resumen('<borrador>');
--      -- porcentaje_cargado = 40, porcentaje_efectivo = el real, ajustado = true;
--    - y sin tocar nada, `ajustado` tiene que dar false.
--
-- 10) El 100%: cargar un rubro al 100 y que `calcular_excesos_certificado` no devuelva nada (el
--     candado no se puede violar por construcción, pero conviene verlo). Después, intentar cargarlo
--     al 100 de nuevo en otro borrador -> "no hay nada que certificar".
--
-- 11) Autoridad: el cliente_principal llamando `cargar_avance_global` -> "sin autoridad". Y en una
--     obra en 'por_partida' -> "esta obra carga el avance partida por partida".
--
-- 12) Que el resto del ciclo siga igual sobre un certificado sembrado global: vista previa, totales,
--     proponer/conformar, emitir, y que después de emitir el avance ponderado por rubro de Gestión
--     de Obra muestre el 40% del rubro.
