-- 0145 -- El cupo de lecturas con IA: 5 por usuario y por mes
--
-- Primera migración del importador inteligente (docs/importador_inteligente_diagnostico.md).
-- **Va primera a pedido de Seba, y el motivo importa**: *"el costo lo paga mi cuenta y no quiero que
-- se dispare mientras la app todavía no se monetiza. Con pocos usuarios probando es menos de dos
-- dólares al mes, pero el límite tiene que estar desde el principio, no agregarse después."*
--
-- Un tope que se agrega después es un tope que llega tarde: cuando se nota que hace falta, ya se
-- gastó. Y el que llama al modelo es un servidor, así que este es el único lugar donde el tope se
-- puede aplicar de verdad -- en el cliente sería una sugerencia.
--
-- ================== NO ES EL LÍMITE VIEJO DE FREE ==================
--
-- Capa 1 §2.5 había diseñado un límite de documentos/mes **para distinguir Free de PRO**, y Capa 2 lo
-- eliminó al volver el importador PRO exclusivo (*"el gate es simplemente `perfiles.es_pro`"*).
--
-- Este es otro límite, con otro motivo y otro alcance: **no separa planes, protege la cuenta que
-- paga el modelo**, y por eso **aplica a todos, PRO incluido**. Si algún día la app se monetiza y el
-- costo se traslada, este número se sube o se saca; no es una decisión de producto sobre qué incluye
-- cada plan.
--
-- ================== QUÉ CUENTA Y QUÉ NO ==================
--
-- **Solo cuentan las lecturas que gastan plata.** El parser determinístico de Excel —que sigue siendo
-- el camino rápido cuando los encabezados se reconocen— corre en el cliente, no llama a ningún
-- modelo y **no consume cupo**. Eso no es una concesión: es lo que hace que el mensaje de "llegaste
-- al límite" pueda ofrecer una salida real en vez de ser una pared.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project -> SQL Editor), después de `0144`. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.


-- =====================================================================
-- Paso 1 -- marcar qué importaciones gastaron plata
-- =====================================================================
--
-- `not null default false`: las importaciones que ya existen son de Excel determinístico y no
-- consumieron nada, así que el default las deja bien sin backfill.

alter table importaciones
  add column uso_ia boolean not null default false;

comment on column importaciones.uso_ia is
  'Si esta importacion se leyo con un modelo (y por lo tanto gasto plata) o con el parser '
  'deterministico de Excel (gratis). Solo las que tienen true cuentan contra el cupo mensual -- ver '
  'consumir_cupo_importacion_ia (0145).';

-- El contador se consulta por mes calendario, así que el índice va sobre las dos columnas que
-- filtran. Parcial: las que no usaron IA no se cuentan nunca.
create index importaciones_cupo_ia_idx
  on importaciones (usuario_id, created_at)
  where uso_ia;


-- =====================================================================
-- Paso 2 -- el número, en un solo lugar
-- =====================================================================
--
-- Mismo criterio que los plazos de la objeción y del acuse: el número vive en una función y en
-- ningún otro lado. Subirlo el día que la app se monetice es cambiar un 5 acá, no buscar dónde
-- quedó escrito.

create or replace function limite_importaciones_ia_por_mes()
returns int language sql immutable as $$
  select 5;
$$;

grant execute on function limite_importaciones_ia_por_mes() to authenticated;

-- Desde cuándo cuenta el mes en curso. **En hora de Argentina, no en UTC.** Es la primera vez que el
-- proyecto necesita esto: los plazos de la 0131 son intervalos rodantes desde un instante
-- (`fecha + interval '5 days'`) y no les importa el huso. Un mes calendario sí: el servidor corre en
-- UTC, así que un 31 a las 22:00 de Buenos Aires ya es día 1 allá, y el contador se reiniciaría un
-- día antes de lo que el usuario ve en el calendario. Acá eso no es un detalle -- el aviso dice una
-- fecha, y esa fecha tiene que ser cierta.
create or replace function inicio_del_mes_ar()
returns timestamptz language sql stable set search_path = public as $$
  select date_trunc('month', now() at time zone 'America/Argentina/Buenos_Aires')
           at time zone 'America/Argentina/Buenos_Aires';
$$;

grant execute on function inicio_del_mes_ar() to authenticated;


-- =====================================================================
-- Paso 3 -- cuánto le queda al que mira
-- =====================================================================
--
-- Para la pantalla: se muestra ANTES de subir el archivo, no después. Que alguien elija un PDF, lo
-- suba y recién ahí se entere de que no le quedan lecturas es la peor forma de decirlo.
--
-- `se_reinicia_el` viaja con el resto para que el aviso pueda decir la fecha exacta en vez de "el
-- mes que viene" -- y para que esa fecha la calcule la base, que es la que sabe en qué huso cuenta.

create or replace function cupo_importaciones_ia()
returns table(limite int, usadas int, quedan int, se_reinicia_el timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  select
    limite_importaciones_ia_por_mes(),
    count(*)::int,
    greatest(limite_importaciones_ia_por_mes() - count(*)::int, 0),
    (inicio_del_mes_ar() + interval '1 month')
  from importaciones i
  where i.usuario_id = auth.uid()
    and i.uso_ia
    and i.created_at >= inicio_del_mes_ar();
$$;

grant execute on function cupo_importaciones_ia() to authenticated;
revoke execute on function cupo_importaciones_ia() from public, anon;


-- =====================================================================
-- Paso 4 -- consumir el cupo, antes de gastar
-- =====================================================================
--
-- **La llama la Edge Function ANTES de mandarle el documento al modelo, no después.** Es la
-- diferencia entre un tope y una estadística: si se marcara al terminar, el documento número seis ya
-- se pagó.
--
-- Marca `uso_ia` en la fila de la importación, que es la que cuenta. Que sea la misma operación que
-- verifica y que marca evita el hueco entre las dos.
--
-- El mensaje de error se muestra tal cual al usuario, así que dice las tres cosas que hacen falta:
-- que llegó al límite, cuándo se reinicia, y **qué puede hacer mientras tanto** -- el Excel con
-- encabezados reconocibles no consume cupo, así que no es una pared.

create or replace function consumir_cupo_importacion_ia(p_importacion_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_usuario uuid;
  v_uso_ia boolean;
  v_usadas int;
  v_limite int := limite_importaciones_ia_por_mes();
  v_reinicio date;
begin
  select usuario_id, uso_ia into v_usuario, v_uso_ia
  from importaciones where id = p_importacion_id;

  if v_usuario is null then
    raise exception 'importación % no encontrada', p_importacion_id;
  end if;

  -- Ya consumió: reintentar la lectura del mismo documento (porque falló la red, porque el modelo
  -- devolvió algo inválido) no se cobra dos veces. El cupo es por documento, no por intento.
  if v_uso_ia then
    return;
  end if;

  select count(*) into v_usadas
  from importaciones i
  where i.usuario_id = v_usuario
    and i.uso_ia
    and i.created_at >= inicio_del_mes_ar();

  if v_usadas >= v_limite then
    v_reinicio := (inicio_del_mes_ar() + interval '1 month')::date;
    raise exception
      'Llegaste a las % lecturas con IA de este mes. El contador se reinicia el %. Mientras tanto podés importar una planilla de Excel con encabezados reconocibles (descripción, cantidad, precio unitario): esa lectura no consume cupo.',
      v_limite, to_char(v_reinicio, 'DD/MM/YYYY');
  end if;

  update importaciones set uso_ia = true where id = p_importacion_id;
end;
$$;

-- Solo el servidor. Si el cliente pudiera llamarla, podría gastar cupo sin leer nada -- o peor,
-- saltear la Edge Function y leer sin consumir.
revoke execute on function consumir_cupo_importacion_ia(uuid) from public, anon, authenticated;

-- LÍMITE CONOCIDO Y ACEPTADO: dos importaciones disparadas exactamente a la vez pueden contar las
-- dos sobre el mismo número y pasar ambas, dejando 6 en el mes. Con un tope de 5 y una persona
-- subiendo documentos de a uno, es un caso de laboratorio, y el precio de resolverlo (un lock por
-- usuario) es peor que el problema: un centavo de más contra una cola de espera en el único punto
-- por el que pasa todo el importador.


-- =====================================================================
-- Verificación a mano después de aplicar
-- =====================================================================
--
-- 1) El estado inicial, con los claims de un usuario (truco de la 0130):
--    begin;
--      set local role authenticated;
--      set local request.jwt.claims = '{"sub":"<uuid de slosav>","role":"authenticated"}';
--      select * from cupo_importaciones_ia();
--    rollback;
--    -- limite 5, usadas 0, quedan 5, y `se_reinicia_el` el día 1 del mes que viene A LAS 00:00 DE
--    -- ARGENTINA (o sea 03:00Z). Si diera el día 1 a las 00:00Z, la cuenta está en UTC y el
--    -- contador se reiniciaría un día antes de lo que dice el aviso.
--
-- 2) Que las importaciones viejas no consumen: `select count(*) from importaciones where uso_ia;`
--    tiene que dar 0 -- todas las que existen son de Excel determinístico.
--
-- 3) *** EL TOPE, que es el punto de la migración. Con un usuario de prueba, crear 5 importaciones y
--    consumirlas:
--    select consumir_cupo_importacion_ia('<importacion>');   -- x5, las cinco pasan
--    select consumir_cupo_importacion_ia('<la sexta>');
--    -- tiene que fallar con el mensaje completo, con el número y la fecha adentro. Leerlo entero:
--    -- es el texto que va a ver el usuario.
--
-- 4) Que reintentar NO cobra dos veces: volver a llamarla sobre una importación que ya tiene
--    `uso_ia = true` no tiene que hacer nada ni fallar, y `cupo_importaciones_ia()` no se mueve.
--
-- 5) Que el cliente no la puede llamar:
--    begin;
--      set local role authenticated;
--      set local request.jwt.claims = '{"sub":"<uuid>","role":"authenticated"}';
--      select consumir_cupo_importacion_ia('<importacion>');
--    rollback;
--    -- tiene que fallar por permisos. Si pasara, el tope no existe.
--
-- 6) Que el cupo es por usuario: con el usuario A en 5, el usuario B tiene que seguir con 5
--    disponibles.
--
-- 7) Limpieza: `update importaciones set uso_ia = false;` deja el contador en cero para seguir
--    probando (las filas de prueba de importaciones se pueden borrar directamente).
