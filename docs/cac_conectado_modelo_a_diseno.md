# CAC conectado al Modelo A — diagnóstico, sin migración todavía

Punto 3 del corte de `docs/indices_cac_cotizacion_dolar_diseno.md` §4/§8, ahora que el
congelamiento (`docs/presupuesto_congelado_validez_modelo_a_diseno.md`, `0103`/`0104`) ya está
aplicado y verificado. Cierra la línea completa: índices → congelamiento → ajuste.

**Estado de este documento: las 3 ambigüedades de la sección 7 quedaron cerradas con el usuario
(respuestas incorporadas más abajo). La migración `0105_cac_conectado_modelo_a.sql` quedó
escrita — sin aplicar ni verificar en Supabase todavía.**

## 1. Viabilidad de las dos series — confirmada, con una corrección real

Tu lectura es correcta para el caso central, y hay dos casos límite que hacían falta precisar
antes de escribir la función.

**Caso central — partida con APU, vista "con materiales" (`tipo_presupuesto =
'materiales_mano_obra'`): la proporción es exacta, no aproximada.** La cascada de Factor K
(`calcular_factor_k_subitem`, `0077`) construye `precio_final` como un único multiplicador `K`
aplicado sobre todo `costo_costo`, sin que ningún paso distinga qué parte de ese costo es material
y qué parte es mano de obra:

```
precio_final = costo_costo × (1+gg%) × (1+imprevistos%) × (1+epp%) × (1+cf%) × (1+beneficio%) × (1+impuestos%)
             = costo_costo × K
```

Como `K` es el mismo número para cada peso de `costo_costo`, la parte de `precio_final` que vino de
materiales es exactamente `materiales_subtotal × K`, y la proporción `materiales_subtotal /
costo_costo` (lo que ya guarda `presupuesto_subitems_congelado`, `0104` §5) sigue siendo válida
después de toda la cascada, sin aproximar nada — no es una estimación, es álgebra.

**Caso límite 1 — vista "sin materiales" (`tipo_presupuesto = 'mano_obra_sola'`): la proporción NO
aplica, y usarla sería un error real.** En esa vista, `costo_costo` que quedó guardado en
`presupuesto_subitems_congelado` (`0104`) ya es `costo_costo_sm` — **sin** materiales, porque el
contratista no los compra en esa modalidad (los pone el cliente directo). `materiales_subtotal`
sigue guardado igual (viene de la otra vista, para tenerlo disponible), pero ya no es una porción
de ese `costo_costo`, es un número de otra cuenta — dividir uno por el otro daría una fracción sin
sentido (potencialmente mayor a 1). La corrección: en esta vista, el 100% del monto de cada partida
va a la serie **mano de obra**, 0% a materiales — coherente con que, en los hechos, el contratista
no está cobrando materiales en esa modalidad.

**Caso límite 2 — rubros de precio manual (`usa_apu = false`: rubros 1/18/19/20/personalizados).**
Estas partidas no pasan por Factor K en ningún momento — el usuario tipea un precio final
directamente. `presupuesto_subitems_congelado.costo_costo`/`materiales_subtotal` quedan `null` para
esas filas (`0104` §5, a propósito). Sin cascada, no hay de dónde sacar una proporción — van
siempre por la serie **general**, sin importar qué elija la obra para el resto. Mismo criterio,
mismo motivo, que ya usa el Modelo B para no poder separar series (`0102` §5: "aplicar dos índices
distintos ahí exigiría inventar una proporción que hoy no se carga en ningún lado").

**Mismo fallback para un caso residual**: una partida con APU cuyo `costo_costo` congelado haya
quedado en `0` (todos sus insumos sin precio al momento de congelar — caso raro pero no imposible,
`congelar_presupuesto_obra` no bloquea esto, `0104` §"congelar_presupuesto_obra") — división por
cero. Mismo tratamiento: cae a la serie general para esa partida puntual.

## 2. Punto 1 — dónde se aplica: confirmado el lugar, corregido el mecanismo

**El lugar es correcto, el mecanismo no puede ser igual al del Modelo B.**
`calcular_saldo_pendiente_hitos` (Modelo B) multiplica **un solo monto agregado** por **un solo
factor** (`0102` §"calcular_saldo_pendiente_hitos") — funciona porque el Modelo B no tiene ninguna
separación materiales/mano de obra que preservar. Acá cada partida tiene su propia proporción, así
que el ajuste tiene que calcularse **por partida, antes de sumar** — no se puede aplicar un factor
único sobre el total ya sumado de `presupuesto_subitems_congelado`.

**Corrección más importante**: no puede vivir *solo* en `calcular_saldo_pendiente_avance_medido`.
Tu punto 2 pide que la certificación use el mismo valor ajustado — si el cálculo se escribiera dos
veces (una en el saldo pendiente, otra en la certificación), sería exactamente el patrón de bug que
ya pasó dos veces en este proyecto: `calcular_monto_obra_subitems` quedó mirando una fuente de
precio vieja mientras el resto de la app ya usaba otra (`0091`→`0094`, y de nuevo `0094`→`0104`
recién la semana pasada). Este proyecto ya tiene una regla no escrita contra esto —
`calcular_precio_final_apu_subitems` (`0090`) existe justamente para que la cascada de Factor K
viva en un solo lugar y no se reescriba en cada función que la necesita.

**Propuesta: una función nueva, compartida por las dos**, algo como
`calcular_monto_congelado_ajustado(obra_id)` — devuelve, por `obra_subitem_id`, el monto congelado
ya ajustado por CAC (o el monto sin ajustar tal cual si `aplica_cac` es falso, o si la obra no está
congelada). Consumida por:
- `calcular_saldo_pendiente_avance_medido` — join con `calcular_avance_acumulado_subitem`, igual
  que hoy, pero leyendo el monto ajustado de acá en vez de `presupuesto_subitems_congelado.monto_total`
  directo.
- `calcular_monto_obra_subitems` (la rama `congelado` que ya agregamos en `0104`) — mismo cambio,
  lee de acá en vez de `presupuesto_subitems_congelado` directo.

Los dos lugares terminan leyendo el mismo número, calculado una sola vez.

## 3. Punto 2 — certificación: confirmado, con la implicancia completa

**Confirmado.** Con el cambio de arriba, `calcular_monto_obra_subitems` (que ya alimenta el
trigger `calcular_monto_periodo_avance`, y por lo tanto `certificado_subitems_avance.monto_periodo`
y `emitir_certificado`, `0052`/`0104`) pasa a devolver el monto ajustado al mes en que se llama —
que, porque un certificado se calcula y se congela en el momento de emitirlo (`now()`), es
automáticamente "el mes de la certificación" tal como pediste. No hace falta tocar
`emitir_certificado` ni el trigger para esto — ninguno de los dos sabe ni necesita saber que el
número que reciben ahora incluye CAC, exactamente el mismo desacople que ya logró el cierre del
cruce con la `0094`.

**Implicancia que vale la pena decir en voz alta**: dos certificados de la misma obra, por la misma
partida y el mismo % de avance, pero emitidos en meses distintos, van a dar montos distintos — el
segundo, más alto, por el CAC acumulado entre uno y otro. Es el comportamiento correcto (es
literalmente el propósito del ajuste), pero puede sorprender si nadie lo explica — de ahí el punto 3.

## 4. Punto 3 — qué se ve en pantalla

Propuesta mínima, extendiendo el panel que ya existe (`PresupuestoEstadoPanel`, estado
"congelado") en vez de agregar una pantalla nueva:

- **Pactado (congelado)**: suma de `presupuesto_subitems_congelado.monto_total`, sin ajuste — el
  número que se firmó.
- **Saldo pendiente, ajustado a hoy**: `calcular_saldo_pendiente_avance_medido` (ya con CAC
  adentro) — el número operativo real.
- **El factor o % del mes**, para que el ajuste no aparezca como un número sin explicación — algo
  como "CAC este mes: materiales +X%, mano de obra +Y%" (o "+X% general" si la obra eligió esa
  serie) — mismo dato que ya usa `factor_cac_obra`, mostrado, no oculto.

**Lo que NO incluyo en la propuesta mínima, y pregunto en vez de asumir (ambigüedad B)**: un
certificado ya **emitido** hoy solo guarda `monto` (un número, `0009`/`0052`) — no un desglose
pactado/ajuste. Para que la tarjeta de un certificado puntual en el historial de Gestión de Obra
muestre "de este monto, tanto es precio pactado y tanto es ajuste CAC", hace falta guardar esas dos
partes por separado al emitir (columnas nuevas en `certificados` o en
`certificado_subitems_avance`) — es una extensión real del schema de certificación, no solo de
lectura. Lo dejo marcado, no asumido dentro del alcance.

## 5. Hallazgo real — `mes_base_cac` no sirve tal cual para el Modelo A

`obras.mes_base_cac` se carga **una sola vez, al crear la obra** (`obras_list_screen.dart`,
`_primerDiaDelMesActual()`, confirmado en el código — no se vuelve a tocar en ningún otro lado). Es
el dato correcto para el Modelo B, donde `monto_total_contratado` normalmente se pacta cerca de la
creación. Para el Modelo A ya no es así: **el mes base tiene que ser el mes del congelamiento**
(tus propias palabras), y ahora que existe `presupuesto_congelado_en` (`0103`), puede haber semanas
o meses de cómputo y negociación entre crear la obra y firmarla — usar `mes_base_cac` para el
Modelo A calcularía el ajuste desde el mes equivocado.

**Propuesta, sin tocar `mes_base_cac` ni el Modelo B**: `factor_cac_obra` gana un parámetro nuevo
opcional, `p_mes_base date default null`. Sin pasarlo, se comporta exactamente igual que hoy (lee
`obras.mes_base_cac`) — **cero cambio de comportamiento para `calcular_saldo_pendiente_hitos`**, que
sigue llamándola sin ese parámetro. La función nueva de Modelo A (§2) sí lo pasa, calculado como
`date_trunc('month', presupuesto_congelado_en)` — que además se corrige solo si la obra se
recongela (ambigüedad C del diseño anterior), sin ninguna columna nueva para esto.

## 6. La decisión que dejaste abierta — general vs. separado, por obra

**Coincido con tu lectura: separado por default**, con la opción de general para contratos donde
eso fue lo pactado. Propuesta de dónde vive: columna nueva `obras.cac_serie` (`'general'` |
`'materiales_mano_obra'`, default `'materiales_mano_obra'`), **leída únicamente por la función
nueva del Modelo A** — `calcular_saldo_pendiente_hitos` (Modelo B) no la toca, sigue ignorando por
completo esta columna, tal como pediste.

Dónde editarla: no hay pantalla de configuración de CAC dedicada todavía — `aplicaCac` se edita hoy
en el diálogo de moneda de `ObrasListScreen` (el mismo `SwitchListTile` de "Ajuste por Índice CAC").
Ese es el lugar natural para sumar el selector de serie, mismo lugar donde ya se explica y se
decide si se ajusta o no — no propongo una pantalla nueva para esto.

## 7. Ambigüedades — cerradas con el usuario

**A. Default de `cac_serie`.** **Cerrado: `'materiales_mano_obra'`** (separado, Opción 1). Palabras
de Seba: "es lo más preciso y es lo que corresponde; el que pactó el general lo cambia a mano. Y
como esto aplica a obras que todavía no están en producción, no hay a quién sorprender."

**B. Desglose pactado/ajuste en un certificado ya emitido.** **Cerrado: sí, se guarda al emitir**
(Opción 2), en contra de mi propuesta de alcance mínimo. Palabras de Seba: "cuando un cliente
pregunte por qué el certificado 5 salió más caro que el 3 por la misma partida y el mismo avance,
tiene que haber una respuesta. Y una vez emitido, si no se guardó, esa información se perdió para
siempre. Es barato ahora y caro después." Implementado en `0105` §6:
`certificado_subitems_avance.monto_periodo_pactado` (snapshot por fila, mismo trigger que ya
snapshotea `monto_periodo`) y `certificados.monto_pactado` (snapshot al emitir, mismo patrón que
`anticipo_pct_aplicado`). El ajuste (`monto_ajuste_cac`) no se guarda aparte — se deriva restando,
sin significado de negocio propio más allá de esa resta.

**C. Transparencia del fallback a "general" en partidas puntuales.** **Cerrado: sí, marcarlo**
(Opción 2) — discrepé con mi propia recomendación inicial. Palabras de Seba: "los rubros de precio
manual son frecuentes: hay 17 rubros en el catálogo y varios se cotizan de forma global. Si una
partida se ajusta con otro criterio que el resto de la obra, el usuario tiene que poder enterarse."
Implementado: `calcular_monto_congelado_ajustado` (`0105` §3) devuelve `fallback_general boolean`
por partida — `true` solo cuando la obra eligió separar series pero esa partida puntual no tenía
de dónde sacar la proporción (rubro manual, o `costo_costo` congelado en 0). La vista "sin
materiales" (100% a mano de obra) queda con `fallback_general = false` — es el criterio correcto
de esa vista, no una excepción. La marca en sí en la UI queda para la próxima pasada (ver §9,
archivos Dart).

## 8. Alcance

El ajuste conectado (saldo pendiente + certificación), con las dos series, y el desglose
pactado/ajuste guardado al emitir cada certificado — sin tocar `calcular_saldo_pendiente_hitos` ni
ninguna otra pieza del Modelo B.

## 9. Bug real encontrado al probar (Galpón Mix) + ajuste de regla — `0106`

Probado en Galpón Mix (congelada, 5 partidas, CAC activo): `calcular_saldo_pendiente_avance_medido`
devolvía `0` en silencio — el número más engañoso posible, "no queda nada por certificar" cuando es
lo contrario.

**Causa real, verificada contra el código**: `calcular_monto_congelado_ajustado` (`0105`) copió el
patrón de "no-miembro → 0 filas, sin excepción" de `calcular_monto_obra_subitems` — pero la función
que llama después, `factor_cac_obra`, corta con excepción para no-miembro. Dos criterios distintos
en la misma pieza, y el más permisivo corre primero. Corregido en `0106`: ahora corta igual que
`factor_cac_obra`.

**Hallazgo de negocio, no cubierto por el diseño original**: el CAC se publica con 1-2 meses de
atraso — cualquier obra recién congelada va a tener, durante ese margen, el índice de su propio mes
base sin publicar todavía. No es un caso de prueba, es la situación normal de toda obra nueva.

**Ajuste de regla, cerrado en `0106`**: la regla de "sin fallback al mes anterior" (`0102`) sigue
intacta para el mes **destino** (el actual) — sigue cortando con excepción si falta. Se distingue el
mes **origen** (el mes base, el del congelamiento): si su índice no existe todavía, no hay ningún
valor que adivinar — la obra certifica al precio pactado sin ajustar, marcado explícitamente
(`serie_aplicada = 'sin_ajustar_indice_pendiente'`), nunca en silencio, sin bloquear certificación.
No es "completar con el mes anterior" — no se inventa ningún número, se muestra la realidad tal
cual.

**Nota, no resuelta acá a propósito**: el mismo problema (obra recién dada de alta, índice del mes
de creación sin publicar) podría afectar en teoría a `calcular_saldo_pendiente_hitos` (Modelo B) —
no se tocó, mismo límite de alcance que el resto de esta pieza. Si alguna vez se vuelve un problema
real ahí, es una pieza aparte.

## 10. Archivos

**Nuevo, Supabase — escrito, sin aplicar ni verificar todavía**:
- `supabase/migrations/0106_cac_indice_base_pendiente.sql` — corrige el bug de §9 (no-miembro
  devolvía 0 en vez de cortar) y agrega el caso "índice del mes base todavía no publicado" (sin
  ajustar, transparente, sin bloquear certificación).
- `supabase/migrations/0105_cac_conectado_modelo_a.sql` — `obras.cac_serie`; `factor_cac_obra` con
  `p_mes_base` opcional (sin tocar el Modelo B); `calcular_monto_congelado_ajustado` (la función
  compartida, §2); `calcular_saldo_pendiente_avance_medido` y `calcular_monto_obra_subitems`
  reescritas para consumirla; `certificado_subitems_avance.monto_periodo_pactado` +
  `certificados.monto_pactado` + el trigger/`calcular_totales_certificado`/`emitir_certificado`
  actualizados para snapshotear el desglose al emitir (ambigüedad B).

**Dart — hecho (pactado/saldo ajustado + las dos marcas), `flutter analyze` limpio (51 infos
preexistentes, ninguna nueva de fondo)**:
- `lib/presentation/obra_detalle/tabs/presupuesto_estado_panel.dart` — estado "congelado" suma
  Pactado, Saldo pendiente (rotulado "ajustado a hoy" solo si `aplica_cac`), y el aviso de índice
  base pendiente (`serieAplicada == 'sin_ajustar_indice_pendiente'` en alguna partida).
- `lib/presentation/obra_detalle/screens/carga_avance_subitems_screen.dart` — ícono con tooltip
  junto al nombre de cada partida que cayó al índice general (`fallbackGeneral`), ambigüedad C.
- `lib/services/obras_repository.dart` — `getMontoPactadoCongelado`, `calcularSaldoPendienteAvanceMedido`,
  `getMontoCongeladoAjustado`; `getEstadoPresupuesto` suma `aplicaCac`/`cacSerie`.
- `lib/data/models/certificado_subitem_avance.dart` — modelo nuevo `MontoCongeladoAjustado`
  (salida de `calcular_monto_congelado_ajustado`).

**Desglose pactado/ajuste en la UI — hecho** (Seba: "no tiene sentido guardarlo si no se ve"):
- `lib/data/models/certificado.dart` — `Certificado.montoPactado` (`null` = certificado emitido
  antes de `0105`, sin desglose reconstruible).
- `lib/services/certificados_repository.dart` — parsea `monto_pactado`.
- `lib/data/models/certificado_subitem_avance.dart` — `TotalesCertificado.montoPactado`/
  `montoAjusteCac`.
- `lib/services/certificado_subitems_avance_repository.dart` — parsea las 2 columnas nuevas de
  `calcular_totales_certificado`.
- `lib/presentation/obra_detalle/screens/vista_previa_certificado_screen.dart` — desglosa
  "Precio pactado"/"Ajuste CAC" antes del subtotal, solo cuando el ajuste es distinto de 0 (para no
  ensuciar la vista previa de las obras sin CAC, la mayoría hoy).
- `lib/presentation/obra_detalle/tabs/gestion_obra_tab.dart` — la tarjeta de cada certificado ya
  emitido suma una línea chica "Pactado $X · Ajuste CAC $Y" cuando hay algo que explicar (mismo
  criterio: nada si `montoPactado` es `null` o coincide con `monto`).

**No tocados**: `0102_indices_cac_cotizacion_dolar.sql`/`calcular_saldo_pendiente_hitos` (Modelo B,
sin cambios, confirmado); `0104_presupuesto_congelamiento_modelo_a.sql` (el congelamiento en sí
sigue igual, esta pieza solo cambia qué lee la certificación una vez congelada).
