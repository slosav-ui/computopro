-- =====================================================================
-- 0151 — Un rubro puede pertenecer a una obra, no solo a una persona
-- =====================================================================
--
-- Tanda 2 de `docs/carpetas_importado_y_catalogo_diseno_datos.md`. **Leer §4 de ese doc antes de
-- tocar esto**: acá está el cómo, allá el por qué.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.
--
-- =====================================================================
-- QUÉ ARREGLA
-- =====================================================================
--
-- `rubros` y `subitems` no tienen forma de pertenecer a una obra: pertenecen al usuario
-- (`creador_usuario_id`). O sea que **no existe ningún lugar donde una partida pueda vivir que
-- signifique "esta obra"** -- todo lo que se importa o se crea cae en el catálogo personal y
-- aparece en el Cómputo de todas las obras de esa persona.
--
-- Es la causa de raíz de las partidas duplicadas que Seba vio en el teléfono. El script de carga
-- de Galpón Mix tenía dos defectos reales, pero el fondo era ese: **no era que la limpieza fallara,
-- era que hacía falta una limpieza.**
--
-- =====================================================================
-- ES UNA MIGRACIÓN DE ESTRUCTURA, NO DE DATOS
-- =====================================================================
--
-- **No hay backfill y no hay nada que se mueva.** Todas las filas existentes quedan con
-- `obra_id is null`, que reproduce exactamente el comportamiento de hoy. Ninguna de las 18
-- funciones que joinean `rubros` desde `obra_subitems` necesita cambios, y ninguna pantalla cambia
-- de aspecto.
--
-- Lo único que cambia de comportamiento observable es la RLS del paso 4, y en la dirección de
-- abrir: un miembro de la obra pasa a ver la carpeta de esa obra. Como todavía no hay ninguna
-- carpeta, hoy tampoco se nota.
--
-- **El orden importa**: los índices del paso 2 tienen que ir después de la columna del paso 1, y
-- el trigger del paso 3 antes de que exista cualquier fila con `obra_id`.
--
-- =====================================================================


-- =====================================================================
-- Paso 1 -- la columna
-- =====================================================================
--
-- `on delete cascade` a propósito, y es la diferencia de fondo con `creador_usuario_id`: una
-- carpeta de obra **no sobrevive a su obra**, es su estructura, no un dato reusable del usuario.
-- Mismo criterio que `obra_rubros_orden.rubro_id` (0026), cuyo comentario ya distingue "preferencia
-- de esta obra" de "dato del usuario".
--
-- Nullable y sin default: `null` = catálogo (oficial si `creador_usuario_id` es null, personal si
-- no). Es lo que hace que la migración sea un no-op sobre los datos que ya están.

alter table rubros   add column obra_id uuid references obras(id) on delete cascade;
alter table subitems add column obra_id uuid references obras(id) on delete cascade;

comment on column rubros.obra_id is
  'null = catalogo (oficial o personal del usuario). No nulo = carpeta de esa obra, el presupuesto '
  'importado tal cual. Ver docs/carpetas_importado_y_catalogo_diseno_datos.md (0151).';

comment on column subitems.obra_id is
  'null = catalogo. No nulo = partida de esa obra. Puede colgar de un rubro del catalogo (partida '
  'suelta agregada solo para esta obra) pero nunca de un rubro de OTRA obra -- ver el trigger (0151).';

-- Los dos filtros nuevos que van a correr en cada apertura de Cómputo.
create index rubros_obra_id_idx   on rubros (obra_id)   where obra_id is not null;
create index subitems_obra_id_idx on subitems (obra_id) where obra_id is not null;


-- =====================================================================
-- Paso 2 -- la unicidad de código pasa a ser por carpeta (decisión 3.2)
-- =====================================================================
--
-- Hoy rige `rubros_codigo_unique` (0025): único **global** sobre `codigo`, entre todos los
-- usuarios. El motivo escrito ahí es el presupuesto impreso -- *"dos ítems con el mismo número
-- confunden al cliente"* -- un documento que todavía no está construido.
--
-- **Por qué no molesta hoy y sí va a molestar:** la `0027` le puso a `rubros.codigo` el default
-- `gen_random_uuid()::text` y sacó el código de la UI, así que un rubro creado desde la app lleva
-- un UUID y dos UUID no chocan nunca. El índice global empieza a molestar con esta pieza, que es
-- **la primera que escribe códigos legibles**: el importador copiando el "1" del Excel.
--
-- Decisión de Seba: *"Conviven. La carpeta importada mantiene su numeración original, que es el
-- sentido de tal cual viene. La unicidad va por obra y por carpeta, no global."*
--
-- Se reemplaza por tres índices parciales que dicen la regla real -- **único dentro de su
-- carpeta**. Nada de lo que el índice global bloqueaba queda desprotegido: lo que se relaja es
-- exactamente lo que la decisión pide relajar.

-- PRECONDICIÓN. Si alguna de estas dos devuelve filas, resolver a mano ANTES de seguir: el
-- `create unique index` de abajo falla y deja la migración por la mitad.
--
--   -- códigos repetidos dentro de un mismo usuario
--   select creador_usuario_id, codigo, count(*) from rubros
--   where creador_usuario_id is not null group by 1, 2 having count(*) > 1;
--
--   -- códigos repetidos en el catálogo oficial (no debería haber, lo impedía la 0015)
--   select codigo, count(*) from rubros where creador_usuario_id is null group by 1 having count(*) > 1;

drop index rubros_codigo_unique;

-- El catálogo oficial: uno solo en todo el sistema. Es el índice que tenía la 0015 antes de que la
-- 0025 lo ampliara, con la condición de carpeta agregada.
create unique index rubros_codigo_oficial_unique on rubros (codigo)
  where obra_id is null and creador_usuario_id is null;

-- El catálogo personal: único por usuario, no entre usuarios.
create unique index rubros_codigo_propio_unique on rubros (creador_usuario_id, codigo)
  where obra_id is null and creador_usuario_id is not null;

-- La carpeta de una obra: único por obra. Acá es donde conviven el "1" oficial y el "1" importado.
create unique index rubros_codigo_obra_unique on rubros (obra_id, codigo)
  where obra_id is not null;

-- ---------------------------------------------------------------- subitems
--
-- `subitems_codigo_oficial_unique` (0016) ya era parcial (`where creador_usuario_id is null`), así
-- que dos subítems propios con el mismo código **ya conviven hoy**. Solo se le agrega la condición
-- de carpeta, para que un subítem de obra no entre nunca por esa rama.
drop index subitems_codigo_oficial_unique;
create unique index subitems_codigo_oficial_unique on subitems (codigo)
  where obra_id is null and creador_usuario_id is null;

-- Y el que no existía: dentro de la carpeta de una obra, el código es único.
--
-- **(obra_id, codigo) y no (obra_id, rubro_id, codigo), a propósito.** Es la carpeta entera la que
-- tiene que poder imprimirse sin dos "1.1", que es el motivo original del índice de la 0025. Los
-- presupuestos reales numeran jerárquicamente ("1.1, 1.2, 2.1") justamente porque son un documento,
-- así que en la práctica no aprieta.
--
-- **Si aprieta, es señal de un Excel que reinicia la numeración en cada rubro**, y la salida es del
-- importador, no de acá: prefijar con el código del rubro antes de insertar. Que falle es mejor que
-- aceptarlo -- dos "1.1" en la misma obra es exactamente lo que este índice existe para evitar.
create unique index subitems_codigo_obra_unique on subitems (obra_id, codigo)
  where obra_id is not null;


-- =====================================================================
-- Paso 3 -- la coherencia entre las dos carpetas (§4.2 del doc)
-- =====================================================================
--
-- La regla, en una línea:
--
--     rubros.obra_id is null  or  subitems.obra_id = rubros.obra_id
--
-- O sea: **un subítem nunca puede colgar de un rubro de OTRA carpeta**. Lo prohibido es "subítem de
-- la obra A adentro de un rubro de la obra B", y también "subítem del catálogo adentro de un rubro
-- de obra" (un rubro de la carpeta importada tiene sus propias partidas, no las del catálogo).
--
-- **Lo que sí se permite, y es a propósito**: `rubro.obra_id is null` + `subitem.obra_id = X`, un
-- subítem suelto de una obra colgado de un rubro del catálogo. Es el caso "quiero agregar una
-- partida al rubro 18 solo para esta obra", que hoy no existe y es otra de las formas en que el
-- catálogo personal se ensucia.
--
-- Va en un trigger porque es entre tablas: un `check` no puede mirar `rubros` desde `subitems`.

create or replace function subitems_carpeta_coherente()
returns trigger language plpgsql
set search_path = public as $fn$
declare
  v_rubro_obra uuid;
begin
  select r.obra_id into v_rubro_obra from rubros r where r.id = new.rubro_id;

  -- `is distinct from` y no `<>`: con null de un lado, `<>` da null (no false) y el if no entra.
  if v_rubro_obra is not null and new.obra_id is distinct from v_rubro_obra then
    raise exception
      'el subitem % no puede colgar de un rubro de otra carpeta (subitem.obra_id=%, rubro.obra_id=%)',
      coalesce(new.codigo, '(sin codigo)'), new.obra_id, v_rubro_obra;
  end if;

  return new;
end;
$fn$;

create trigger subitems_carpeta_coherente_trg
  before insert or update of obra_id, rubro_id on subitems
  for each row execute function subitems_carpeta_coherente();

-- El mismo chequeo del otro lado: mover un rubro a la carpeta de una obra no puede dejarle
-- subítems que pertenezcan a otra (o al catálogo).
--
-- El camino inverso -- **adoptar** un rubro de obra al catálogo, `obra_id = null` (decisión 3.1) --
-- nunca dispara esto: con el rubro en null la regla se cumple sola, cualquiera sea la carpeta de
-- sus subítems. Está bien que así sea; lo que la adopción tiene que resolver (renumerar el código,
-- y decidir si los subítems van con él) es de producto, no de integridad. Ver §6.1 del doc.

create or replace function rubros_carpeta_coherente()
returns trigger language plpgsql
set search_path = public as $fn$
begin
  if new.obra_id is not null and exists (
    select 1 from subitems s
    where s.rubro_id = new.id and s.obra_id is distinct from new.obra_id
  ) then
    raise exception
      'no se puede mover el rubro % a la carpeta de una obra: tiene subitems de otra carpeta',
      coalesce(new.codigo, '(sin codigo)');
  end if;

  return new;
end;
$fn$;

create trigger rubros_carpeta_coherente_trg
  before update of obra_id on rubros
  for each row execute function rubros_carpeta_coherente();


-- =====================================================================
-- Paso 4 -- RLS: la carpeta de la obra se ve por membresía (decisión 3.4)
-- =====================================================================
--
-- Hoy `rubros_select` (0015, ampliada en 0019) deja ver un rubro ajeno **solo si
-- `om.puede_ver_apu_ajena`** -- un permiso pensado para el APU de otra persona, no para la
-- estructura de la obra. Seba: *"Es la estructura de la obra, no el APU de nadie. Y sin eso ve un
-- cómputo vacío, que es peor."*
--
-- Se agrega la rama por membresía y **se conserva la de APU ajena**, que es otra cosa y sigue
-- valiendo para el catálogo personal de un compañero de obra.

alter policy rubros_select on rubros using (
  (obra_id is null and (creador_usuario_id is null or creador_usuario_id = auth.uid()))
  or (obra_id is not null and is_obra_member(obra_id))
  or tiene_apu_ajena_visible_por_rubro(id)
);

alter policy subitems_select on subitems using (
  (obra_id is null and (creador_usuario_id is null or creador_usuario_id = auth.uid()))
  or (obra_id is not null and is_obra_member(obra_id))
  or tiene_apu_ajena_visible_por_subitem(id)
);

-- ---------------------------------------------------------------- escritura
--
-- Para el catálogo personal no cambia nada: cada uno escribe lo suyo.
--
-- Para la carpeta de una obra el gate es `puede_editar_presupuesto(obra_id)` (0121), que es el
-- permiso que ya significa exactamente esto -- *"el que armó el presupuesto es el que lo edita;
-- los demás lo ven pero no lo tocan"*. **Deliberadamente no es `creador_usuario_id = auth.uid()`**:
-- en una obra compartida, la carpeta la importa uno y la puede corregir cualquiera con permiso de
-- editar el presupuesto. Si dependiera del creador, un profesional que se va de la obra dejaría una
-- carpeta que nadie puede tocar.
--
-- En el INSERT se sigue exigiendo `creador_usuario_id = auth.uid()` también para las filas de obra:
-- la columna deja de ser "quién manda" y pasa a ser "quién la trajo", que sigue sirviendo para el
-- audit y no cuesta nada.

alter policy rubros_insert on rubros with check (
  creador_usuario_id = auth.uid()
  and (obra_id is null or puede_editar_presupuesto(obra_id))
);

-- El `using` mira la fila VIEJA y el `with check` la NUEVA. Eso es justamente lo que hace posible
-- la adopción (§6.1): se sale de la carpeta con permiso sobre la obra y se entra al catálogo
-- personal siendo uno el dueño.
alter policy rubros_update on rubros using (
  (obra_id is null and creador_usuario_id = auth.uid())
  or (obra_id is not null and puede_editar_presupuesto(obra_id))
) with check (
  (obra_id is null and creador_usuario_id = auth.uid())
  or (obra_id is not null and puede_editar_presupuesto(obra_id))
);

alter policy rubros_delete on rubros using (
  (obra_id is null and creador_usuario_id = auth.uid())
  or (obra_id is not null and puede_editar_presupuesto(obra_id))
);

alter policy subitems_insert on subitems with check (
  creador_usuario_id = auth.uid()
  and (obra_id is null or puede_editar_presupuesto(obra_id))
);

alter policy subitems_update on subitems using (
  (obra_id is null and creador_usuario_id = auth.uid())
  or (obra_id is not null and puede_editar_presupuesto(obra_id))
) with check (
  (obra_id is null and creador_usuario_id = auth.uid())
  or (obra_id is not null and puede_editar_presupuesto(obra_id))
);

alter policy subitems_delete on subitems using (
  (obra_id is null and creador_usuario_id = auth.uid())
  or (obra_id is not null and puede_editar_presupuesto(obra_id))
);


-- =====================================================================
-- Verificación
-- =====================================================================
--
-- ---- 1. sin backfill: el catálogo existente quedó como estaba
--
--   select count(*) from rubros   where obra_id is not null;   -- 0
--   select count(*) from subitems where obra_id is not null;   -- 0
--   select calcular_presupuesto_vivo_obra('<obra_id>');        -- el mismo número que antes
--
-- ---- 2. la unicidad por carpeta, con una obra de prueba
--
--   -- (a) un rubro de obra con el código "1" convive con el oficial "1"  -> tiene que ANDAR
--   insert into rubros (codigo, nombre, orden, usa_apu, tipo_precio_manual, creador_usuario_id, obra_id)
--   values ('1', 'TAREAS PRELIMINARES (del Excel)', 1, false, 'unitario', auth.uid(), '<obra_id>');
--
--   -- (b) repetir exactamente el mismo insert                            -> tiene que FALLAR
--   --     (rubros_codigo_obra_unique)
--
--   -- (c) el mismo código "1" en OTRA obra                               -> tiene que ANDAR
--
--   -- (d) dos usuarios distintos, cada uno con un rubro propio de código '21' (obra_id null)
--   --                                                                    -> tiene que ANDAR
--   --     Era lo que el índice global de la 0025 impedía.
--
-- ---- 3. la coherencia del paso 3
--
--   -- un subítem de la obra A colgado de un rubro de la obra B           -> tiene que FALLAR
--   -- un subítem del catálogo (obra_id null) bajo un rubro de obra       -> tiene que FALLAR
--   -- un subítem de la obra A bajo un rubro del CATÁLOGO                 -> tiene que ANDAR
--   --   (es el caso permitido a propósito: partida suelta de esa obra)
--
-- ---- 4. el aislamiento, que es el punto de toda la pieza
--
--   -- crear un rubro con obra_id = A, abrir el Cómputo de la obra B      -> NO aparece
--   --   (después de la tanda 2 del lado de Dart, que es la que pasa obraId a la consulta)
--
-- ---- 5. la RLS, con dos usuarios reales -- el caso que hoy falla
--
--   -- un cliente invitado a una obra con carpeta importada TIENE que ver las partidas.
--   -- Antes de esta migración veía un cómputo vacío: la política pedía puede_ver_apu_ajena.
--   -- Probar además que un usuario que NO es miembro de esa obra sigue sin verlas.
--
-- ---- 6. escritura por permiso, no por creador
--
--   -- con puede_editar_presupuesto = true y sin ser el creador del rubro -> puede editarlo
--   -- con puede_editar_presupuesto = false                               -> no puede
