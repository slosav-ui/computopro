-- Bug real, diagnosticado en conversación (no hay doc en docs/ para esta pieza): 6 call sites en
-- 4 repositorios de Dart escribían `updated_at` con `DateTime.now().toIso8601String()` sin
-- `.toUtc()` -- Dart devuelve la hora local del dispositivo sin ningún offset en el string, y
-- Postgres, al no ver offset en una columna `timestamptz`, la interpreta con el timezone de la
-- sesión (UTC en Supabase). Una hora local de Argentina (UTC-3) quedaba guardada como si fuera esa
-- misma hora en UTC -- 3 horas antes de lo real. Confirmado con una fila real: created_at 13:07,
-- updated_at 10:07, exactamente el offset de Argentina.
--
-- Por qué es un trigger y no alcanza con el `default now()` que ya tenían las 6 tablas: en
-- Postgres, `default` solo se aplica en INSERT, nunca en UPDATE. Si el arreglo hubiera sido
-- simplemente que Dart dejara de mandar `updated_at`, la columna habría quedado congelada en la
-- fecha de creación para siempre -- cada actualización posterior la habría dejado intacta, peor
-- que el bug original (que al menos actualizaba la fecha, aunque mal). Un trigger `BEFORE UPDATE`
-- que fuerza `new.updated_at = now()` es la única forma de que la base garantice la invariante
-- ("esta columna siempre tiene la hora real de la última modificación") sin depender de que cada
-- call site se acuerde de hacerlo bien -- mismo criterio que el trigger de bootstrap de
-- obra_members (0033_obra_members_bootstrap.sql). Dispara también en la rama `ON CONFLICT DO
-- UPDATE` de un upsert (Postgres lo trata como un UPDATE real a todos los efectos de triggers),
-- así que cubre por igual los `.update()` y los `.upsert()` que ya existían en Dart.
--
-- Alcance: las 6 tablas que tienen columna `updated_at` en todo el schema, no solo las 4 donde se
-- encontró el bug con datos reales. `apu_composiciones` (0018) y `obra_presupuesto_config` (0020)
-- hoy no las escribe ningún repositorio de Dart -- no tienen el bug todavía porque no tienen
-- ningún escritor todavía --, pero el día que se programe la edición de composiciones de APU o el
-- selector de presupuesto, heredarían el mismo problema si el trigger no estuviera puesto de
-- antes. El propio comentario de 0018 ya lo anticipaba ("se deja a cargo de la app por ahora") --
-- ese "por ahora" es exactamente el tipo de cosa que se olvida. Se decidió sumarlas ahora: el
-- costo es dos líneas más sobre una función que de todos modos había que escribir, y evita que
-- este mismo diagnóstico haya que rehacerlo cuando esas pantallas existan. (0018 no se edita para
-- reflejar esto -- es una migración ya aplicada, queda como registro de la decisión tomada en su
-- momento; esta migración es la que cuenta la historia completa.)
--
-- Datos existentes: 51 filas de prueba (obras 3, obra_insumo_precios 3, obra_subitems 38,
-- obra_rubros_orden 7 -- confirmado con consulta real, ninguna es dato real de producción) quedan
-- con `updated_at` corrido 3 horas, a propósito, sin reparar. Motivo: `updated_at` no se usa para
-- ordenar ni calcular nada en ningún lugar de la app (confirmado, ningún `.order()` de todo `lib/`
-- lo usa), y el único lugar donde se muestra (`obras_list_screen.dart`, pie de la tarjeta de obra)
-- es el string ISO8601 crudo sin formatear -- un desfasaje de 3 horas ahí es invisible a simple
-- vista. El riesgo de una reparación masiva de timestamps (elegir mal el offset, tocar filas que
-- no vinieron de este bug) supera el beneficio de corregir un dato que hoy no afecta nada
-- funcional.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

create or replace function set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger set_updated_at_obras
  before update on obras
  for each row execute function set_updated_at();

create trigger set_updated_at_obra_insumo_precios
  before update on obra_insumo_precios
  for each row execute function set_updated_at();

create trigger set_updated_at_obra_subitems
  before update on obra_subitems
  for each row execute function set_updated_at();

create trigger set_updated_at_obra_rubros_orden
  before update on obra_rubros_orden
  for each row execute function set_updated_at();

create trigger set_updated_at_apu_composiciones
  before update on apu_composiciones
  for each row execute function set_updated_at();

create trigger set_updated_at_obra_presupuesto_config
  before update on obra_presupuesto_config
  for each row execute function set_updated_at();
