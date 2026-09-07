# Importador — Capa 2 (mapeo y persistencia): diseño de datos

Estado: **diseño cerrado, sin implementar.** Continúa `docs/importador_capa1_diseno_datos.md`
(Capa 1, diseño cerrado desde 2026-08-22, tampoco implementada todavía) — ese documento no se
reabre ni se repite acá, solo se corrige donde el alcance mínimo de esta ronda lo pide (ver §1).

Contexto de negocio (ya cerrado en conversación, no se repite el razonamiento completo): la mayoría
de los profesionales ya armó su presupuesto en Excel y no lo va a rehacer partida por partida — sin
importador, la barrera de entrada a Gestión de Obra es cargar el cómputo a mano, y eso frena
exactamente lo que diferencia la app.

## 1. Alcance mínimo de esta ronda — 3 recortes sobre Capa 1, con motivo

**Importador exclusivo de PRO — corrige la decisión §3.C de Capa 1** ("disponible para todos, con
límite de documentos/mes en Free"). Mismo criterio que ya cerró el Factor K
(`docs/monetizacion.md` §9): si Free pudiera importar su presupuesto completo y usar Gestión de Obra
con eso, se lleva el diferencial de la app sin pagar — el importador es exactamente la puerta de
entrada que hace valioso el resto, no algo que se pueda regalar. Se cae de paso la necesidad de
contar documentos por mes (§2.5 de Capa 1) — el gate es simplemente `perfiles.es_pro`, que ya existe
y ya se usa en toda la app.

**Excel primero, sin IA — PDF/foto quedan para la segunda tanda.** Seba estima que la mayoría va a
subir PDF o foto, no Excel — el orden no es "lo más común primero", es "lo que se puede construir
determinístico primero, sin esperar un modelo de visión". Motivo real para no tirar nada de este
esfuerzo: todo el mapeo, la confirmación y la creación de partidas (el grueso de esta Capa 2) se
reusa exactamente igual el día que se sume lectura de PDF/foto — lo único que cambia en la segunda
tanda es qué llena `importaciones_items` (un parser de planillas vs. un modelo de visión), la capa
de después no se entera de la diferencia.

**`obra_id` pasa a `not null` para esta ronda — corrige el schema de Capa 1** (`obra_id uuid
references obras(id)`, nullable, decisión §3.G). La "estimación rápida sin obra" que motivaba la
nullability sigue sin poder verificarse en ningún doc de este proyecto (mismo hallazgo de Capa 1,
sin cambios) — construirla ahora sería resolver una dependencia (a qué obra se asocia la
importación al confirmar, ver Capa 1 §2.2) para un caso de uso que no está confirmado. Se importa
sobre una obra ya elegida o recién creada, nunca "suelta". El día que la estimación sin obra se
diseñe de verdad, viene con su propia migración (columna nullable de nuevo + la política de RLS
con la segunda rama que Capa 1 §2.3 ya había dejado escrita) — no hay que adivinarla ahora.

## 2. Sin APU, sin composiciones — lo que cambia el mapeo

Lo que se importa es la hoja de cómputo del profesional: rubro, partida, unidad, cantidad, precio
unitario ya cerrado. **No trae ni implica una composición de APU.** Esto simplifica Capa 2 en un
punto concreto: mapear una fila importada nunca es "encontrar o construir un APU", es únicamente
resolver a qué `subitems.id` (y `rubros.id`) corresponde una descripción en texto libre, y volcar
cantidad + precio en `obra_subitems`. `apu_composiciones`/`apu_composicion_items` no se tocan en
ningún punto de este flujo.

## 3. Mapeo por fila — 3 acciones, sin algoritmo automático en esta ronda

No hay ningún mecanismo de fuzzy-matching ya construido en este proyecto que reusar — la limpieza
de insumos duplicados (`limpieza_catalogo_insumos_apu.md`) se hizo a mano, en una sesión de
curación, no con un algoritmo corriendo en la app. Para no inventar uno nuevo sin necesidad, cada
fila de `importaciones_items` se resuelve con una de tres acciones, elegida por el usuario en una
pantalla de revisión:

1. **Elegir del catálogo** — buscador manual contra `subitems` reales, misma pieza que ya existe
   para agregar materiales/equipos a un APU (`InsumosRepository.buscarPorTipo`, mismo patrón:
   buscar, tocar, listo). Si el rubro tampoco matchea, se busca el rubro primero, de la misma forma.
2. **Crear como propia** — un toque, reusa `SubitemsRepository.crearPersonalizado` (y
   `RubrosRepository.crearPersonalizado` si el rubro tampoco existe) con la descripción/unidad ya
   extraídas como valores iniciales, editables antes de confirmar. Esto es lo que cambió desde
   agosto: en el diseño original, "no matchea" solo tenía descartar o quedar pendiente para
   siempre — ahora hay un tercer camino real porque la creación de rubros/subítems propios ya existe.
3. **Descartar la fila** — para lo que la extracción levantó por error (un encabezado, un subtotal,
   texto suelto que no es una partida real). El dato crudo queda igual en `importaciones_items`
   como respaldo — descartar no borra la fila extraída, solo decide no crear nada a partir de ella.

**Sin columna de estado nueva para esto**: una fila resuelta (acción 1 o 2) termina con
`rubro_id`/`subitem_id` cargados; una descartada (acción 3) los deja `null` para siempre. El propio
par de columnas que Capa 1 ya reservó (`importaciones_items.rubro_id`/`subitem_id`, hoy sueltos sin
FK) es el discriminador — no hace falta un booleano `descartado` aparte. Al implementar, esas dos
columnas ganan su FK real hacia `rubros(id)`/`subitems(id)` (exactamente lo que Capa 1 §2.2 ya
anticipaba).

**Mejora futura, no de esta ronda**: usar `pg_trgm` (extensión de similitud de texto de Postgres)
para ordenar los resultados del mismo buscador por parecido en vez de alfabético — sigue siendo el
usuario quien confirma, solo le acerca el candidato correcto arriba de la lista. No entra ahora
porque el buscador plano (acción 1) todavía no existe; ordenarlo mejor es una capa sobre algo que
primero tiene que funcionar.

## 4. El precio importado es manual siempre — hallazgo real, no un detalle menor

Esto no estaba anticipado en ningún doc y **cambia una pantalla que ya existe**, no solo agrega
código nuevo.

Un precio importado es un número ya cerrado por el profesional — no tiene que competir con (ni
depender de) si el subítem matcheado tiene una composición de APU real. Así que toda fila resuelta
escribe `obra_subitems.precio_unitario_manual`, sin importar si el rubro del subítem usa APU
(`usa_apu = true`) o no.

**El problema**: `SubitemsScreen._buildContenido()` hoy decide qué mostrar mirando el *rubro*
(`tipoPrecioManual`) y si el subítem es *propio* — nunca mira si `obra_subitems.precio_unitario_manual`
ya tiene un valor cargado. Un subítem oficial de un rubro con `usa_apu = true` (rubros 2 a 17 —
la mayoría real del catálogo, todo lo estructural/terminaciones) siempre cae en la rama "precio
derivado de la composición", ignorando cualquier `precio_unitario_manual` que tuviera. Si el
importador escribe ahí un precio manual y la pantalla lo ignora, el importador no sirve para la
mayoría de las partidas reales — no es un caso raro, es el caso típico.

**Arreglo necesario, chico**: en esa misma pantalla, antes de mirar `_subitemsConComposicion`,
chequear si `obraSubitem.precioUnitarioManual != null` — si lo tiene, mostrar el precio manual
editable (misma rama que ya usan los rubros sin APU), no el derivado. Sin riesgo de regresión: hoy
ningún camino existente escribe `precio_unitario_manual` en un subítem oficial con `usa_apu = true`
(solo lo hacen los rubros de precio manual y los propios), así que el chequeo nuevo es un no-op
para todos los datos que ya existen — recién importa el día que algo (el importador) empiece a
escribir ahí.

**Las dos vistas conviven sin pisarse**: `ApuListadoTab` (Solapa APU) sigue filtrando por
composición existente, sin mirar `precio_unitario_manual` — una partida con precio importado no
aparece ahí, correcto: no tiene nada que desglosar. Pero sigue apareciendo en el listado si además
tiene una composición oficial cargada (el filtro de `ApuListadoTab` es sobre composición, no sobre
si el precio actual es manual) — así que el camino a `ComposicionApuScreen` para esa partida no se
pierde, solo deja de ser el que gobierna el precio que se certifica en Cómputo.

## 5. Confirmación — una función SQL nueva, atómica

Cada fila se resuelve de a una durante la revisión (acción 1/2/3 de §3), con llamadas simples e
inmediatas a lo que ya existe — sin necesitar nada nuevo del lado de la base para ese paso.

**"Confirmar importación" sí necesita una función nueva**, `confirmar_importacion(p_importacion_id
uuid)`, por el mismo motivo que ya llevó a otras piezas de este proyecto a una función atómica en
vez de una secuencia de llamadas desde Dart (`emitir_certificado`, `aprobar_ajuste_contrato`): son
varias filas de `obra_subitems` a la vez (una por cada `importaciones_items` resuelto), y una
importación de 40 líneas que se corta a mitad de camino (13 partidas creadas, 27 no) deja la obra en
un estado confuso, no un error prolijo. La función recorre los `importaciones_items` de esa
importación con `rubro_id`/`subitem_id` no nulos, hace upsert de cada uno en `obra_subitems`
(`cantidad`, `precio_unitario_manual`, `es_aplicable = true`), y recién si todo el lote entra bien
marca `importaciones.estado = 'confirmado'` — todo o nada. RLS: mismo criterio ya cerrado en Capa 1
§2.3 para el caso con `obra_id` cargado (`admin_maestro`/`profesional`), sin la segunda rama (la de
`obra_id` null queda afuera de esta ronda, ver §1).

## 6. Moneda — sin conversión en esta ronda, con aviso

Capa 1 ya resuelve `moneda_efectiva(item) = item.moneda ?? importacion.moneda_default`. Lo que
falta, y no estaba planteado: si esa moneda efectiva no coincide con `obras.moneda` (un presupuesto
en USD importado a una obra en ARS, o al revés), no hay ninguna cotización histórica guardada en el
proyecto con la que convertir de forma confiable — el banner de USD Ref. BNA es un valor vigente
hoy, no una serie de fechas pasadas. **No se convierte automáticamente**: la pantalla de revisión
avisa si la moneda de una fila no coincide con la de la obra, y deja la decisión al usuario (cargar
el precio ya convertido a mano, o dejarlo así a sabiendas) — mismo criterio "avisar y dejar decidir"
que ya es el estándar del proyecto, no una excepción nueva.

## 7. Qué NO se resuelve en esta ronda, a propósito

- **PDF y foto** — necesitan lectura con visión, segunda tanda (ver §1). El mecanismo de esta ronda
  (Excel, parser determinístico de planillas por encabezado de columna reconocido — "Rubro",
  "Descripción", "Cantidad", "Precio Unitario" y sinónimos razonables, sin modelo de IA) es mucho
  más simple que "la IA lee el archivo" que anticipaba Capa 1 — sigue corriendo del lado del
  servidor (Edge Function), no ya para proteger una clave de IA (acá no hay ninguna), sino por el
  motivo que sigue vigente igual: aplicar el límite/gate desde el servidor, no confiar en que el
  cliente se autolimite.
- **`obra_id` nullable / estimación sin obra** — diferido, ver §1.
- **Fuzzy-matching automático del mapeo** — diferido, ver §3.
- **Conversión de moneda** — diferido, ver §6, queda en aviso manual.
- **Límite de documentos/mes** — ya no aplica, el gate es PRO exclusivo (ver §1).

## Archivos para esta ronda (tentativo, a confirmar antes de escribir código)

**Nuevos:**
- `supabase/migrations/00XX_importaciones.sql` — tablas `importaciones`/`importaciones_items` de
  Capa 1 (sin cambios de columnas más que `obra_id not null`, ver §1), bucket de Storage + política,
  RLS de la rama única (`obra_id` cargado).
- `supabase/migrations/00XX_confirmar_importacion.sql` — la función de §5, más las FKs de
  `importaciones_items.rubro_id`/`subitem_id` hacia `rubros`/`subitems`.
- Edge Function del parser de Excel (fuera de `lib/`, en `supabase/functions/`) — encabezados
  reconocidos, sin IA.
- `lib/data/models/importacion.dart`, `lib/data/models/importacion_item.dart`
- `lib/services/importaciones_repository.dart`
- Pantalla de subida (elegir obra, elegir archivo, elegir hojas) y pantalla de revisión (filas
  editables + las 3 acciones de §3 + "Confirmar importación") — nombres de archivo a definir cuando
  se escriba, probablemente 2 pantallas separadas en vez de una sola larga.

**Se modifica:**
- `lib/presentation/obra_detalle/screens/subitems_screen.dart` — el chequeo de
  `precio_unitario_manual` antes de la rama de composición (§4). Este cambio no depende de que el
  resto del importador exista — se podría hacer y verificar antes, aislado, si conviene probarlo
  por separado.

**No se tocan:** `apu_composiciones`/`apu_composicion_items`, `calcular_factor_k_subitem`,
`ApuListadoTab` (ver §4, coexiste sin cambios).
