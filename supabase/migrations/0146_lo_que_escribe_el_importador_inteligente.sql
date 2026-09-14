-- 0146 -- Lo que el importador inteligente necesita escribir
--
-- Segunda migración del importador (docs/importador_inteligente_diagnostico.md). La 0145 puso el
-- tope; esta pone las tres columnas sin las cuales la lectura con modelo no se puede revisar bien.
--
-- **El grueso ya existe y no se toca.** `importaciones_items` ya tiene `rubro_texto`,
-- `descripcion_texto`, `unidad_texto`, `cantidad`, `precio_unitario`, `moneda` y `datos_originales`,
-- y `RevisarImportacionScreen` ya mapea fila por fila. Lo que cambia no es el destino: es que ahora
-- el que llena esas filas puede equivocarse de otra manera.
--
-- ================== POR QUÉ HACEN FALTA ==================
--
-- Un parser de Excel falla ruidosamente: si la columna no existe, no hay número. Un modelo falla en
-- silencio -- devuelve un número plausible en el lugar correcto. Seba lo dijo mejor: *"la app no
-- puede distinguir una lectura buena de una confiada"*.
--
-- Por eso la revisión es siempre visible, y por eso necesita dos cosas que hoy no tiene:
--
--   1. **Saber de qué filas dudar** (`confianza`), para ponerlas arriba en vez de que se pierdan
--      entre 97 partidas que están bien.
--   2. **Un control que no dependa del modelo** (`total_declarado`): el documento dice cuánto suma.
--      Si la suma de lo interpretado no da ese número, algo se leyó mal -- y eso se detecta sin
--      confiar en la misma lectura que está bajo sospecha. Es la única verificación de esta pieza
--      que no se apoya en el que puede haberse equivocado.
--
-- Y una tercera, que es de Seba y no del usuario:
--
--   3. **Qué se gastó de verdad** (`modelo`, `tokens_*`). El tope de la 0145 está puesto sobre una
--      estimación de entre uno y tres centavos por documento. Con esto el costo se mide en vez de
--      estimarse, y el día que haya que decidir si el límite sube, la respuesta sale de una consulta
--      y no de una cuenta de servilleta.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project -> SQL Editor), después de la `0145`. No
-- ejecutado automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.


-- =====================================================================
-- Paso 1 -- de qué filas dudar
-- =====================================================================
--
-- Mismos tres valores que `importaciones.confianza_general` (0080), a propósito: es la misma escala
-- en dos granularidades, no dos vocabularios.
--
-- **Nullable, y eso es el camino de Excel.** El parser determinístico no estima confianza porque no
-- adivina nada: una celda es una celda. `null` no quiere decir "no sé", quiere decir "no hubo
-- interpretación acá" -- y la pantalla lo trata como una fila normal, que es lo que es.

alter table importaciones_items
  add column confianza text
    check (confianza is null or confianza in ('alta','media','baja'));

comment on column importaciones_items.confianza is
  'Que tan segura es la interpretacion de ESTA fila. La pone el modelo; null cuando la fila vino del '
  'parser deterministico de Excel, que no interpreta. La pantalla de revision ordena por esta '
  'columna: primero lo dudoso.';


-- =====================================================================
-- Paso 2 -- el número que el documento dice de sí mismo
-- =====================================================================
--
-- No es el total calculado: es **el total impreso en el papel**. Los dos tienen que coincidir, y
-- cuando no coinciden el aviso va con la diferencia en pesos, no con un "revisá bien".
--
-- Nullable porque hay presupuestos sin total al pie, y porque una foto de una hoja puede cortarlo.
-- Sin total no hay control -- la pantalla lo dice en vez de callarse.

alter table importaciones
  add column total_declarado numeric;

comment on column importaciones.total_declarado is
  'El total tal como figura IMPRESO en el documento, no la suma de los items. Existe para '
  'contrastarlo contra esa suma: si no dan igual, algo se leyo mal. null = el documento no traia '
  'total (o no se pudo leer), y entonces esta verificacion no esta disponible.';


-- =====================================================================
-- Paso 3 -- qué costó, de verdad
-- =====================================================================

alter table importaciones
  add column modelo text,
  add column tokens_entrada int,
  add column tokens_salida int;

comment on column importaciones.modelo is
  'Que modelo leyo el documento (ej. claude-haiku-4-5). null = no lo leyo un modelo, lo parseo el '
  'Excel deterministico.';

-- **No se guarda el costo en pesos ni en dólares, a propósito.** Un precio guardado es un precio que
-- envejece: el día que el modelo cambie de tarifa, la columna estaría mintiendo sobre lo que ya
-- pasó y no habría forma de saber cuál de los dos números es el bueno. Los tokens son un hecho; el
-- precio es una tabla de afuera. Se multiplican al mirar.

create or replace function consumo_ia_del_mes()
returns table(mes date, documentos bigint, tokens_entrada bigint, tokens_salida bigint)
language sql
stable
security definer
set search_path = public
as $$
  select
    date_trunc('month', i.created_at at time zone 'America/Argentina/Buenos_Aires')::date,
    count(*),
    sum(coalesce(i.tokens_entrada, 0)),
    sum(coalesce(i.tokens_salida, 0))
  from importaciones i
  where i.uso_ia
  group by 1
  order by 1 desc;
$$;

-- Es la cuenta de Seba la que paga, así que esto mira **toda la app**, no la obra de quien pregunta.
-- Por eso no se le da a nadie: se consulta desde el SQL Editor. El día que haya una pantalla de
-- administración, ahí se decide quién puede verla; hoy no hay a quién concedérsela.
revoke execute on function consumo_ia_del_mes() from public, anon, authenticated;

comment on function consumo_ia_del_mes() is
  'Consumo real de modelo por mes, para toda la app. Sin grants: se consulta desde el SQL Editor. '
  'Multiplicar por la tarifa vigente del modelo para tener el costo -- ver 0146 Paso 3.';


-- =====================================================================
-- Verificación a mano después de aplicar
-- =====================================================================
--
-- 1) Que las importaciones de Excel que ya existen siguen enteras: todas tienen que quedar con
--    `confianza` null en sus items y `modelo` null en la cabecera. Ninguna columna es not null, así
--    que no hace falta backfill -- si algo se rompió, se rompió al agregar la columna y se nota acá:
--    select count(*) from importaciones_items where confianza is not null;  -- 0
--
-- 2) Que el check acepta los tres valores y rechaza cualquier otro:
--    update importaciones_items set confianza = 'media' where id = '<un item de prueba>';   -- pasa
--    update importaciones_items set confianza = 'regular' where id = '<el mismo>';          -- falla
--
-- 3) `select * from consumo_ia_del_mes();` -- hoy tiene que dar cero filas (ninguna importación usó
--    IA todavía). Vuelve a mirarse después de la primera lectura real, que es cuando sirve.
--
-- 4) Que la revisión sigue funcionando como antes: abrir una importación vieja en
--    `RevisarImportacionScreen`. Esta migración no cambia nada de lo que esa pantalla lee hoy; si
--    algo cambió, es un error de esta migración y no una mejora.
