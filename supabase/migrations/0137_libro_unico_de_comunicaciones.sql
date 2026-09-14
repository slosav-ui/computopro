-- 0137 -- Un solo libro de comunicaciones: se saca la numeración, y el libro se prende y se apaga
--
-- CAMBIO DE ALCANCE (Seba, 2026-09-14), y el motivo es de obra, no de software:
--
--   *"En la realidad la empresa no responde adentro de la orden: contesta con una nota de pedido,
--   que es otro libro. Reproducir eso complica sin aportar, y el respaldo legal sigue siendo el
--   libro rubricado en papel."*
--
-- Queda **un solo libro de comunicaciones de obra**: escriben y se responden el constructor y el
-- profesional, y el cliente solo lee. Eso elimina de un saque los dos libros direccionales, la
-- numeración correlativa, el acuse de recibo y el plazo para acusar.
--
-- ================== POR QUÉ LOS NÚMEROS 0135 Y 0136 QUEDAN VACÍOS ==================
--
-- Existieron y se borraron **sin haberse aplicado nunca ni haberse commiteado**: la `0135` traía los
-- avisos de acuse y el interruptor por obra, la `0136` el plazo de 48 horas hábiles. Las dos dejaron
-- de tener sentido con el cambio de arriba. El hueco en la numeración es a propósito -- los números
-- no se reusan, así que si alguien tiene una copia vieja de esos archivos no hay forma de que se
-- confunda con otra cosa.
--
-- **El interruptor por obra sí se rescata de la `0135` y va acá**: esa parte no dependía de que
-- hubiera dos libros.
--
-- ================== LA 0134 NO SE TOCA ==================
--
-- Está aplicada, y una migración aplicada no se reescribe aunque parte haya quedado sin uso: el
-- archivo es el registro de lo que le pasó a la base, no de lo que hoy querríamos que dijera. Lo
-- que sigue vivo de ella y **sigue siendo exactamente lo que hace falta**:
--
--   * la policy de INSERT sin el cliente -- la rama `'obra'` ya autoriza a admin_maestro,
--     profesional y constructor, que es la matriz nueva sin cambiarle una coma;
--   * el bucket `libro-obra`, que las fotos y los audios adentro de una entrada siguen necesitando.
--
-- Y lo que **no** se saca, con un motivo concreto y no por comodidad: los valores `orden_servicio` y
-- `nota_pedido` siguen en el check de `libro_entradas.libro` y en la policy. Angostar el check a
-- `'obra'` **fallaría contra las filas de prueba que ya existen** con esos valores, y Seba pidió
-- expresamente conservarlas. Quedan como dos ramas que nadie escribe desde la app.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project -> SQL Editor), después de `0134`. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.


-- =====================================================================
-- Paso 1 -- fuera la numeración
-- =====================================================================
--
-- *"Numerar cada mensaje de una conversación no aporta: la fecha y la firma ya dan el orden"*
-- (Seba). El número tenía sentido cuando una Orden de Servicio se citaba en obra por su número
-- ("la OS N° 7"); un mensaje de una conversación no se cita así.
--
-- Y se saca de la base, no solo de la pantalla: *"dejarlo trabajando sobre una tabla que dice otra
-- cosa es justo lo que confunde al que lee el código en seis meses"*. Una columna que se sigue
-- llenando sola y que ninguna pantalla muestra es exactamente eso.
--
-- Orden obligado: primero el trigger, después la función (que referencia la columna), y recién
-- entonces la columna. El índice único se va solo con el `drop column` -- Postgres borra los índices
-- que dependen de ella.

drop trigger if exists libro_entradas_numerar on libro_entradas;
drop function if exists asignar_numero_libro_entrada();

alter table libro_entradas drop column if exists numero;


-- =====================================================================
-- Paso 2 -- lo que del trigger sí conviene conservar
-- =====================================================================
--
-- El trigger de la `0134` hacía dos cosas: numerar (se va) y **cuidar el hilo** (se queda). Los dos
-- guards cierran agujeros que la `0003` dejó abiertos y que no se pueden expresar como check
-- constraint, porque miran otra fila: que una respuesta cuelgue de una entrada de **otra obra u otro
-- libro**, y que se pueda **responder una respuesta**.
--
-- ¿Para qué, si el libro nuevo es una conversación plana y nada escribe `entrada_padre_id`?
-- Justamente por eso: la columna sigue existiendo y algún día alguien va a querer "responder
-- citando". El día que eso pase, la protección ya está puesta -- y ponerla después, con datos
-- cargados, es mucho más caro que dejarla ahora.
--
-- Nombre nuevo, `validar_hilo_libro_entrada`: la de antes se llamaba `asignar_numero_...` y ya no
-- asigna ningún número. Una función cuyo nombre miente es peor que ninguna.

create or replace function validar_hilo_libro_entrada()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_padre record;
begin
  if new.entrada_padre_id is null then
    return new;
  end if;

  select obra_id, libro, entrada_padre_id into v_padre
  from libro_entradas where id = new.entrada_padre_id;

  if v_padre is null then
    raise exception 'la entrada padre no existe';
  end if;

  if v_padre.obra_id <> new.obra_id or v_padre.libro <> new.libro then
    raise exception 'una respuesta tiene que ir en el mismo libro y la misma obra que la entrada que responde';
  end if;

  if v_padre.entrada_padre_id is not null then
    raise exception 'no se responde una respuesta';
  end if;

  return new;
end;
$$;

create trigger libro_entradas_validar_hilo
  before insert on libro_entradas
  for each row execute function validar_hilo_libro_entrada();


-- =====================================================================
-- Paso 3 -- el libro se prende y se apaga por obra
-- =====================================================================
--
-- Rescatado de la `0135`, que no llegó a aplicarse. No toda obra usa el libro, y una que no lo usa
-- no tiene por qué mostrar el ícono.
--
-- `not null default true`: las obras que existen hoy quedan con el libro prendido, que es lo que
-- tienen ahora. Apagarlo es una decisión explícita, no el estado inicial -- naciendo apagado, nadie
-- descubriría la pieza.
--
-- Apagar **no borra ni esconde lo escrito**: las entradas siguen ahí y siguen siendo legibles por
-- RLS. Se apaga la puerta, no el contenido.

alter table obras
  add column if not exists libros_habilitados boolean not null default true;

comment on column obras.libros_habilitados is
  'Si esta obra usa el libro de comunicaciones (0135 rescatada en la 0137). false apaga la puerta, '
  'NO lo ya escrito: las entradas siguen existiendo y siguen siendo legibles.';


-- =====================================================================
-- Lo que esta migración NO hace, y hay que decidir aparte
-- =====================================================================
--
-- **El aviso.** Y conviene que quede escrito acá, porque es el agujero que este cambio de alcance
-- reabre: el acuse de recibo no era solo burocracia, era **lo que hacía posible avisar**. Daba un
-- estado binario y objetivo -- la entrada tiene hija o no la tiene -- sin necesidad de rastrear
-- quién leyó qué.
--
-- En una conversación plana eso ya no se deduce de la tabla, y sin aviso vuelve intacto el problema
-- que Seba encontró probando la tanda 1: *"escribí una orden con slosav y a seba2135 no le apareció
-- nada"*.
--
-- La forma que recomiendo cuando se retome: una tabla chica de última lectura por usuario y obra,
-- que se actualiza al abrir el libro, y un pendiente que diga "3 mensajes nuevos". **No toca
-- `libro_entradas`**: es estado de interfaz, no respaldo, así que puede tener UPDATE sin
-- comprometer el append-only de la tabla legal. Ver docs/libro_obra_horizonte.md.


-- =====================================================================
-- Verificación a mano después de aplicar
-- =====================================================================
--
-- 1) Que la numeración no dejó restos:
--    select column_name from information_schema.columns
--    where table_name = 'libro_entradas';                        -- sin `numero`
--    select indexname from pg_indexes where tablename = 'libro_entradas';
--    -- sin `libro_entradas_numero_unico` (se fue con la columna)
--    select proname from pg_proc where proname like '%numero_libro%';   -- 0 filas
--    select tgname from pg_trigger where tgrelid = 'libro_entradas'::regclass and not tgisinternal;
--    -- solo `libro_entradas_validar_hilo`
--
-- 2) Que los datos de prueba siguen ahí (Seba pidió conservarlos):
--    select libro, count(*) from libro_entradas group by libro;
--    -- las filas de orden_servicio y nota_pedido siguen existiendo, sin su número.
--
-- 3) Que se puede seguir escribiendo, desde la app: el profesional y el constructor escriben en el
--    libro de comunicaciones; el cliente NO puede (eso lo aplica la policy de la 0134, sin cambios).
--
-- 4) Los dos guards del hilo, que sobrevivieron al cambio de nombre. Con `entrada_padre_id` a mano:
--    - responder una entrada de otra obra -> "misma obra y mismo libro";
--    - responder una respuesta -> "no se responde una respuesta".
--
-- 5) El interruptor:
--    select nombre, libros_habilitados from obras where obra_madre_id is null;   -- todas en true
--    update obras set libros_habilitados = false where id = '<obra>';
--    -- en la app desaparece el ícono, y `select count(*) from libro_entradas where obra_id = ...`
--    -- no cambia: lo escrito queda.
