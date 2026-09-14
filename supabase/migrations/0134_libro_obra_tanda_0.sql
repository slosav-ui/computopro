-- 0134 -- Libro de Obra, tanda 0: la matriz de escritura definitiva, la numeración y el bucket
--
-- Diseño completo y las 4 decisiones cerradas por Seba el 2026-09-13: docs/libro_obra_horizonte.md
-- (§A la precisión de alcance, §D las decisiones). Esta migración va ANTES que el repositorio y la
-- pantalla, a propósito: conviene que la pantalla nazca contra la matriz definitiva en vez de
-- adaptarse después.
--
-- LO QUE YA ESTÁ Y NO SE TOCA, que es la mitad de la pieza: `libro_entradas` (0003) con los tres
-- libros discriminados, `autor_usuario_id` + `autor_rol` (el "quién" del respaldo legal),
-- `created_at` puesto por la base, `adjuntos jsonb` (que ya alcanza para audios y archivos sin
-- tocar el schema) y **`entrada_padre_id`, que ya modela el acuse como entrada hija** -- eso último
-- es lo que diferencia una Orden de Servicio con su acuse de un chat plano, y no hubo que
-- agregarlo. Sin `UPDATE` ni `DELETE` para nadie: append-only real, en la base, no por convención
-- de la UI.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project -> SQL Editor), después de `0133`. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.


-- =====================================================================
-- Paso 1 -- el cliente no escribe en ningún libro (decisión 0)
-- =====================================================================
--
-- **La RLS aplicada desde la `0004` no coincide con lo que Seba definió**, y esto es lo que
-- corrige: hoy el `cliente_principal` y el `invitado_apoderado` pueden escribir en el Libro de Obra,
-- y el `cliente_principal` puede responder una Nota de Pedido. La precisión de §A dice otra cosa --
-- *"la comunicación es entre el constructor y el profesional; el cliente solo lee"* -- y el motivo
-- es de fondo: el respaldo documenta la **comunicación técnica**, y meter al que paga adentro de esa
-- conversación cambia lo que el documento prueba.
--
-- Se puede hacer sin migrar ni un dato: **no hay ninguna entrada cargada todavía**. Es la última
-- oportunidad de cambiar esta matriz gratis.
--
-- `admin_maestro` SÍ sigue escribiendo en el diario, y no es un olvido: la decisión 0 saca al
-- cliente y a su apoderado, no al administrador de la obra -- que en la mayoría de las obras de esta
-- app es la misma persona que el profesional.

drop policy libro_entradas_insert on libro_entradas;

create policy libro_entradas_insert on libro_entradas for insert with check (
  autor_usuario_id = auth.uid()
  and tiene_rol_en_obra(obra_id, autor_rol)
  and case libro
    -- El diario: las tres partes técnicas. Sin cliente_principal ni invitado_apoderado (0134).
    when 'obra' then
      autor_rol in ('admin_maestro', 'profesional', 'constructor')
    -- Orden de Servicio: la abre el profesional, la acusa el constructor.
    when 'orden_servicio' then
      (entrada_padre_id is null and autor_rol = 'profesional')
      or (entrada_padre_id is not null and autor_rol = 'constructor')
    -- Nota de Pedido: al revés. Sin cliente_principal en la respuesta (0134).
    when 'nota_pedido' then
      (entrada_padre_id is null and autor_rol = 'constructor')
      or (entrada_padre_id is not null and autor_rol = 'profesional')
    else false
  end
);

-- La política de SELECT no se toca: sigue siendo `is_obra_member(obra_id)`. El cliente y el veedor
-- ven los tres libros completos -- leer es justamente lo que sí hacen.


-- =====================================================================
-- Paso 2 -- número correlativo por obra y por libro (decisión 1)
-- =====================================================================
--
-- En obra real las órdenes se citan por número ("la OS N° 7"), así que sin esto el respaldo se
-- vuelve incómodo de usar justo cuando hace falta.
--
-- **Sin candado de secuencia**, y esto es una decisión con precedente medido: se puede abrir la 8
-- aunque la 7 no tenga acuse. Este proyecto ya construyó un candado de ese tipo (no emitir hasta
-- subir el PDF firmado) y **lo sacó a propósito** en la `0055` porque bloqueaba de más; se reemplazó
-- por un aviso no bloqueante. La orden sin acuse se marca en pantalla, y más adelante puede avisar
-- por `mis_pendientes()`.
--
-- `numero` nullable, y null en las respuestas: **un acuse no consume número**. Es parte de la orden,
-- no una orden nueva. El índice único es parcial por eso mismo.

alter table libro_entradas add column numero int;

create unique index libro_entradas_numero_unico
  on libro_entradas (obra_id, libro, numero)
  where numero is not null;

comment on column libro_entradas.numero is
  'Numero correlativo por obra y por libro (0134), asignado por trigger al insertar. NULL en las '
  'entradas hijas: un acuse no consume numero, es parte de la orden. Sin candado de secuencia: se '
  'puede abrir la 8 con la 7 sin acusar (decision 1, y el precedente de la 0055).';

-- El trigger numera, y de paso cierra dos agujeros del hilo que la 0003 dejó abiertos y que hoy
-- salen gratis: que una respuesta cuelgue de una entrada de OTRA obra u OTRO libro, y que se pueda
-- responder una respuesta. Ninguna de las dos se puede expresar como check constraint (miran otra
-- fila), y las dos romperían la lectura de "una orden y su acuse" que es para lo que existe esto.
--
-- SECURITY DEFINER para el `max()`: si algún día la política de SELECT se angosta, un autor que vea
-- solo parte del libro empezaría a repetir números sin que nadie se entere.

create or replace function asignar_numero_libro_entrada()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_padre record;
begin
  if new.entrada_padre_id is not null then
    select obra_id, libro, entrada_padre_id into v_padre
    from libro_entradas where id = new.entrada_padre_id;

    if v_padre is null then
      raise exception 'la entrada padre no existe';
    end if;

    if v_padre.obra_id <> new.obra_id or v_padre.libro <> new.libro then
      raise exception 'una respuesta tiene que ir en el mismo libro y la misma obra que la entrada que responde';
    end if;

    if v_padre.entrada_padre_id is not null then
      raise exception 'no se responde una respuesta: el hilo es una entrada y sus acuses';
    end if;

    -- Una respuesta no lleva número, aunque se lo manden.
    new.numero := null;
    return new;
  end if;

  select coalesce(max(numero), 0) + 1 into new.numero
  from libro_entradas
  where obra_id = new.obra_id and libro = new.libro and numero is not null;

  return new;
end;
$$;

create trigger libro_entradas_numerar
  before insert on libro_entradas
  for each row execute function asignar_numero_libro_entrada();

-- Backfill de lo que hubiera: hoy la tabla está vacía, así que esto no hace nada -- va igual para
-- que la migración sea correcta si alguien la aplica sobre una base donde sí se cargó algo.
with raices as (
  select id, row_number() over (partition by obra_id, libro order by created_at, id) as n
  from libro_entradas
  where entrada_padre_id is null and numero is null
)
update libro_entradas e
set numero = r.n
from raices r
where r.id = e.id;

-- LÍMITE CONOCIDO Y ACEPTADO, el mismo que ya tiene `certificados.numero`: dos entradas raíz
-- insertadas exactamente a la vez pueden calcular el mismo `max() + 1`, y el índice único rechaza
-- una de las dos. Con dos personas escribiendo en una obra es un caso de laboratorio, y el precio de
-- resolverlo (una secuencia por obra y libro, o un lock) es peor que el problema.


-- =====================================================================
-- Paso 3 -- el bucket para audios y adjuntos (decisión 3)
-- =====================================================================
--
-- La decisión 3 es **audio + una línea de texto que escribe el autor**: el audio se guarda siempre
-- (es la prueba de lo que se dijo) y el texto es para leer y buscar, y va en `contenido`, que ya
-- existe y ya es `not null` -- sin retrabajo cuando más adelante se sume la transcripción
-- automática como función PRO.
--
-- El bucket va acá y no en la tanda de los audios porque es infraestructura, no comportamiento: sin
-- datos que migrar y sin riesgo para nada de lo que anda, y así el Dart de audios y adjuntos se
-- puede escribir de una sin volver a pedir una migración.
--
-- CONVENCIÓN DE PATH OBLIGATORIA, calcada del bucket `importaciones` (0080) porque es de lo que
-- depende la RLS: `{obra_id}/{uuid}-{nombre}`. El primer segmento del path tiene que ser SIEMPRE el
-- obra_id en texto plano. Lo hace cumplir el repositorio al subir.
--
-- Privado (`public = false`): son documentos de una obra, se leen con URL firmada.

insert into storage.buckets (id, name, public)
values ('libro-obra', 'libro-obra', false)
on conflict (id) do nothing;

-- Lee cualquier miembro de la obra -- incluido el cliente y el veedor, igual que la política de
-- SELECT de la tabla: el cliente no escribe, pero ve todo.
create policy libro_obra_storage_select on storage.objects for select using (
  bucket_id = 'libro-obra'
  and is_obra_member((storage.foldername(name))[1]::uuid)
);

-- Sube quien puede escribir alguna entrada en esa obra: las tres partes técnicas. La RLS de Storage
-- no puede saber en qué libro va a terminar el archivo (se sube antes de insertar la fila), así que
-- este es el conjunto más chico que cubre los tres casos sin abrirle la puerta al cliente.
create policy libro_obra_storage_insert on storage.objects for insert with check (
  bucket_id = 'libro-obra'
  and (
    tiene_rol_en_obra((storage.foldername(name))[1]::uuid, 'admin_maestro')
    or tiene_rol_en_obra((storage.foldername(name))[1]::uuid, 'profesional')
    or tiene_rol_en_obra((storage.foldername(name))[1]::uuid, 'constructor')
  )
);

-- Sin UPDATE ni DELETE, mismo criterio append-only que la tabla y que el bucket de importaciones: un
-- audio subido no se reemplaza ni se borra. Es exactamente lo que lo vuelve un respaldo.


-- =====================================================================
-- Verificación a mano después de aplicar
-- =====================================================================
--
-- 1) La matriz nueva. Desde la app, con usuarios reales (en el SQL Editor `auth.uid()` es null y la
--    RLS rechaza todo):
--    - el profesional abre una Orden de Servicio -> entra, con numero = 1;
--    - el constructor la acusa (entrada_padre_id = la de arriba) -> entra, con numero NULL;
--    - *** el CLIENTE intenta escribir en el Libro de Obra -> tiene que fallar. Antes de esta
--      migración entraba: ese es el cambio;
--    - *** el CLIENTE intenta responder una Nota de Pedido -> tiene que fallar, por lo mismo;
--    - el veedor intenta cualquier cosa -> falla, como antes;
--    - el constructor intenta abrir una Orden de Servicio -> falla (la abre el profesional).
--
-- 2) La numeración, en la misma obra:
--    select libro, numero, entrada_padre_id is null as es_raiz, contenido
--    from libro_entradas where obra_id = '<obra>' order by libro, numero nulls last, created_at;
--    -- correlativo 1, 2, 3... por libro, y NULL en las respuestas. Las Órdenes y las Notas
--    -- numeran cada una por su lado: las dos empiezan en 1.
--
-- 3) Los dos guards del hilo (correr desde la app o con claims; tienen que fallar):
--    - responder una entrada de OTRA obra -> "misma obra y mismo libro";
--    - responder un acuse -> "no se responde una respuesta".
--
-- 4) Que sigue sin poder editarse ni borrarse: un update y un delete sobre una entrada, desde
--    cualquier rol -> 0 filas afectadas (no hay política).
--
-- 5) El bucket:
--    select id, public from storage.buckets where id = 'libro-obra';  -- public = false
--    -- Y desde la app: el constructor sube un archivo a '{obra_id}/...' -> entra; el cliente
--    -- intenta subir -> falla; el cliente lo descarga con URL firmada -> funciona.
