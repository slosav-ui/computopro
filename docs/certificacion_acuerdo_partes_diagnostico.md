# Certificar como acuerdo entre partes — diagnóstico (2026-09-13, sin código)

Pedido de Seba: el ciclo de certificación construido trata la certificación como **carga
unilateral** (el que carga avance emite y listo) cuando en obra es un **acuerdo**: se propone, se
verifica, hay ida y vuelta. Más periodicidad pactada con aviso, quién conforma técnicamente, y
objeción del cliente que frena el pago. **Nada escrito todavía: esto mide antes de tocar.**

Textual de Seba: *"el constructor y profesional proponen avances de obra según porcentajes de
subítems dentro de los rubros, es un ida y vuelta entre ellos que lo puede iniciar uno u otro según
sea el caso"*. Y sobre el pago: *"el cliente no debe pagar si tiene dudas"*.

**Estado (2026-09-13, después de la ronda de ambigüedades):** las dos ambigüedades que bloqueaban
quedaron cerradas (§8.1 y §8.2) y Seba confirmó los dos hallazgos de forma: la objeción va como **eje
aparte** y no como estado nuevo (§5), y el avance global se **reparte en las filas por partida
ponderado por el monto congelado** (§6) — *"por la vía del Modelo B se perdería todo el ciclo, y eso
no conviene"*. **Tanda 1 (periodicidad y aviso): `0123` aplicada, Dart commiteado (§3.1). Tanda 2 (el acuerdo en
el borrador): migración `0124` escrita, con las tres decisiones de forma cerradas (§2.1); el Dart
va después de aplicarla.** Las tandas 3 y 4 siguen sin empezar.

**Aclaración que corrige un malentendido de fondo:** lo que Seba llama **certificación global no son
hitos con etapas pactadas**. Es **avance global sin desglose por partida** — un solo porcentaje de
toda la obra, o de una parte — que es otra cosa que el Modelo B que está en la base (§6).

---

## 1. Lo que ya existe, verificado contra el código

**Tablas y columnas**

- `certificados` (`0009`): `estado text` con check de 6 valores (`borrador`, `emitido`, `leido`,
  `pagado`, `impactado_cerrado`, `anulado` — el último lo agregó `0056`), `periodo text` (libre,
  tipo "Agosto 2026"), `numero` + `version`, y **4 check constraints** que atan cada estado a su
  fecha (`estado not in ('leido',…) or fecha_lectura is not null`, etc.).
- `certificado_subitems_avance` (`0052`): una fila por partida, `porcentaje_periodo` (0-100),
  `monto_periodo` calculado por trigger, `unique (certificado_id, obra_subitem_id)`, `creado_por`.
- **Un solo borrador por obra**: índice único parcial `certificados_un_borrador_por_obra` (`0053`).
- Config de certificación: **columnas en `obras`**, no una tabla —
  `dias_plazo_pago_certificados`, `anticipo_pct`, `fondo_reparo_pct`, `modelo_certificacion`,
  `monto_total_contratado`. El "`obra_config_certificacion`" que suena a tabla es el **repositorio
  Dart** (`lib/services/obra_config_certificacion_repository.dart`) que lee esas columnas.
- `hitos_certificacion` (`0006`): Modelo B. `descripcion` libre, **`monto numeric not null check
  (monto > 0)`**, `estado activo/finalizado/rescindido`, `contratista_nombre` para subcontratos.

**Funciones del ciclo** (una por transición, `security definer`):
`emitir_certificado` (borrador → emitido; exige `puede_editar_presupuesto`, recalcula el monto,
valida excesos del 100%, congela anticipo/fondo/plazo/CAC/cotización), `marcar_certificado_leido`
(cliente o apoderado; idempotente), `marcar_certificado_pagado` (**guard único:
`if v_estado not in ('emitido','leido')`** + `puede_gestionar_certificado`),
`marcar_certificado_impactado`, `subir_pdf_firmado_certificado`,
`proponer_anulacion_certificado` / `resolver_anulacion_certificado`.

**Quién puede qué, hoy**

| Acto | Quién |
| --- | --- |
| Crear borrador y cargar/editar/borrar avance | `admin_maestro`, `profesional`, `constructor` — **por RLS, solo mientras `estado = 'borrador'`** |
| Emitir | `puede_editar_presupuesto` (admin_maestro siempre; profesional/constructor con el permiso, `0121`) |
| Marcar leído | `cliente_principal` o `invitado_apoderado` |
| Pagar | `puede_gestionar_certificado`: cliente principal, o apoderado con `puede_aprobar_certificados` (con tope y delegación vigente) |
| Anular (proponer/resolver) | profesional y constructor, **nunca el cliente**, y nunca la misma persona en los dos lados |
| Ver | cualquier miembro (`is_obra_member`) — **incluye los borradores** |

**Dos precedentes de la casa que resuelven casi todo el diseño de esta pieza:**

1. **El sub-estado de la anulación (`0056`).** `anulacion_estado` (`propuesta`/`aprobada`/
   `rechazada`) + motivo + quién/cuándo propuso + quién/cuándo resolvió, con checks de coherencia,
   **sin tocar `certificados.estado`** hasta que se resuelve. Es exactamente la forma que necesita la
   objeción del cliente.
2. **"Si no hay contraparte, no se exige contraparte."** Ya está escrito en `mis_pendientes()` para
   quitas/demasías: `m.solicitado_por <> auth.uid() or not exists (otro profesional/constructor
   activo en la obra)`. Es la regla que pide el punto 3 (el profesional si está, el cliente si no),
   ya expresada en SQL en este repo.

---

## 2. Punto 1 — el acuerdo entre partes

**Lo que ya está, y es más de lo que parece:** el borrador **ya es un espacio compartido**. La RLS de
`certificado_subitems_avance` deja insertar, editar y borrar filas a `admin_maestro`, `profesional` y
`constructor` **mientras el certificado esté en borrador**, y hay uno solo por obra. O sea: el ida y
vuelta de cargar y corregir porcentajes por subítem **ya funciona hoy**, y cada fila guarda
`creado_por`. La vista previa con números reales también existe (`calcular_totales_certificado`,
`calcular_excesos_certificado`).

**Lo que falta son tres cosas, ninguna estructural:**

1. **El apretón de manos, registrado.** Hoy no hay forma de decir "esto que cargué es mi propuesta,
   revisala" ni "revisé y estoy conforme". Cabe como **columnas nuevas en `certificados`, con el
   mismo patrón que la anulación**: `acuerdo_estado` (`en_carga` / `propuesto` / `conforme`),
   `propuesto_por` + `propuesta_fecha`, `conforme_por` + `conforme_fecha`,
   `comentario_devolucion`. **`estado` sigue en `'borrador'` todo el tiempo** → no se toca ninguna de
   las 4 check constraints de fechas, ninguna función de cobro, ningún cálculo de avance.
   *Lo puede iniciar cualquiera de los dos*: no hay rol fijo en esas columnas, solo "quien propuso no
   puede ser quien da conformidad".
2. **Un guard en `emitir_certificado`.** Una condición más: si hay contraparte técnica en la obra,
   exigir `conforme_por is not null` y `conforme_por <> auth.uid()`. Si no hay contraparte, se emite
   como hoy (precedente 2 de arriba). Es la línea que convierte la emisión unilateral en emisión de
   lo acordado.
3. **Un pendiente nuevo**: "te proponen un avance para revisar" → `union all` en
   `mis_pendientes()`, destino la pantalla de carga de avance.

**La devolución con comentario cierra el ida y vuelta sin estados nuevos**: vuelve a `en_carga` con
`comentario_devolucion`, y el historial completo de cada vuelta queda en `audit_log`, igual que la
anulación hace con sus intentos.

---

### 2.1 Tanda 2, como quedó escrita — migración `0124`

**Siete pasos**: las 6 columnas del acuerdo en `certificados` (con el check `conforme_por <>
propuesto_por` **en la tabla**, no solo en la función), 4 helpers, las 2 policies de SELECT, las 3
funciones del circuito (proponer / dar conformidad / devolver con comentario), el trigger del paso 5,
el guard en `emitir_certificado` y la rama `certificado_propuesto` en `mis_pendientes()`.

**Quién es la contraparte — una sola regla para todo.** ¿Hay profesional activo en la obra? Sí →
conforma el otro lado técnico (propuso el constructor, conforma el profesional; propuso el
profesional, conforma el constructor) y el cliente no ve el borrador. No → conforma el
`cliente_principal` (o su apoderado), que entonces sí lo ve. Y encima de eso, el precedente de la
casa: **si no hay contraparte, no se exige contraparte** — una obra de un solo usuario emite
exactamente como antes de esta migración. Esa última cláusula es la que protege todo lo que ya está
andando.

**Las tres decisiones de forma (Seba, 2026-09-13), con su fundamento:**

1. **El trigger "si se toca el avance, se cae la conformidad" VA** (paso 5), aunque no estaba en el
   alcance de la tanda. *"Si se puede conformar un avance, cambiarle los números y emitir con esa
   conformidad, el acuerdo no vale nada. Es justo lo que la pieza viene a resolver."* El borrador
   sigue editable mientras es borrador (RLS de `0052`, a propósito), así que sin el trigger la
   conformidad podía quedar apuntando a otros números.

2. **El guard de emisión es "no emite el mismo que propuso"**, y no el `conforme_por <> auth.uid()`
   que proponía §2.2 de este mismo doc. *"Es más estricto y el caso que marcás tiene salida — el otro
   devuelve y lo vuelve a proponer. Prefiero eso a que el que propuso emita su propia propuesta."*
   El caso medido y aceptado: si la única persona con `puede_editar_presupuesto` es la que propuso,
   ese certificado no se emite hasta que se invierten los roles de la propuesta. El mensaje de error
   de la función dice exactamente eso.

3. **El `invitado_veedor` tampoco ve el borrador** mientras haya profesional. La regla escrita es
   "quien no carga avance no ve el borrador si hay profesional", y el veedor cae ahí. *"Es coherente
   con la regla y el borrador es la discusión técnica entre las partes. Al que mira desde afuera le
   alcanza el certificado emitido."*

**`0124` aplicada y verificada por Seba (2026-09-13).**

**Dart, hecho — `flutter analyze` sin errores ni warnings nuevos, sin verificar en el emulador
todavía:**
- `Certificado`: enum `AcuerdoCertificado` + 6 campos + `fueDevuelto`.
- `CertificadosRepository`: `proponerAvance`, `darConformidad`, `devolverAvance`, y dos consultas de
  autoridad que se le preguntan a la base en vez de calcularlas en Dart —
  `puedeDarConformidad(certificadoId)` y `hayContraparte(obraId, propuestoPor)`. `UserContext` **no
  cambia**: la autoridad depende de si la obra tiene profesional activo y de quién propuso, y
  `UserContext` solo conoce las membresías del usuario logueado.
- `CargaAvanceRubrosScreen`: el bloque del acuerdo con Proponer / Conforme / Devolver con
  comentario, y la relectura del certificado en cada carga (la foto que llega por parámetro
  envejece: el acuerdo lo mueve la otra parte desde otro dispositivo).
- `VistaPreviaCertificadoScreen`: el botón Emitir explica por qué está deshabilitado, adelantando
  las dos condiciones del guard de la base en el mismo orden.
- `GestionObraTab`: la tarjeta del borrador muestra en qué punto del acuerdo está, **solo una vez
  que el circuito arrancó** — un borrador recién creado, o uno de una obra sin contraparte, no
  muestra nada.
- Pendiente `certificadoPropuesto` (modelo, ícono, navegación) → abre la carga de avance, no el
  detalle: lo que hay que revisar son los números que se están conformando.
- `DetalleCertificadoScreen._copiarComoLeido`: los 6 campos nuevos copiados. Ese constructor a mano
  es el único lugar del proyecto donde un campo nuevo del modelo se pierde en silencio.

**Lo único que cambia de RLS en toda la pieza son dos policies, las dos de SELECT**:
`certificados_select` (los estados distintos de borrador siguen idénticos; el borrador pasa por
`ve_borradores_certificado`) y `certificado_subitems_avance_select` (lo mismo, para que esconder el
encabezado y dejar el detalle a la vista no sea una opción). `INSERT`/`UPDATE`/`DELETE` de las dos
tablas: sin tocar.

---

## 3. Punto 2 — periodicidad: **no existe**

Busqué en las 122 migraciones y en los docs: **no hay ninguna columna de periodicidad**. Lo que
existe y se parece es otra cosa: `dias_plazo_pago_certificados` (cada cuánto **se paga** un
certificado ya emitido, no cada cuánto **se certifica**). Y `certificados.periodo` es un **texto
libre** que hoy tipea la persona.

**Lo que faltaría, chico:**

- `obras.periodicidad_certificacion` (`semanal`/`quincenal`/`mensual`, nullable = sin pactar) y, si
  se quiere precisión, un ancla (`certificacion_dia_corte` o "desde el congelamiento"). Va en las
  mismas columnas de `obras` que ya maneja `ObraConfigCertificacionRepository` y su panel, con el
  mismo gate (`admin_maestro`).
- **El aviso sale del mecanismo de pendientes sin construir nada nuevo**: una rama más en
  `mis_pendientes()`, con la condición "pasó un período desde `max(fecha_emision)` (o desde el
  congelamiento si no hay ninguno) y no hay borrador propuesto". Toda la cañería —cartel del
  dashboard, contador por obra, navegación— ya está.
- **Única fricción medida**: `Pendiente.entidadId` es `String` no nulo, y este pendiente puede no
  tener entidad (si todavía no hay borrador). Se resuelve apuntando al borrador cuando existe y a la
  obra cuando no, o haciendo el campo nullable. Es una línea del modelo, no un rediseño.
- Regalo de paso: con periodicidad, `certificados.periodo` puede venir sugerido en vez de tipeado.

### 3.1 Tanda 1, como quedó diseñada — migración `0123`, escrita sin aplicar

**Una sola columna**: `obras.periodicidad_certificacion` (`semanal`/`quincenal`/`mensual`, nullable =
sin pactar), al lado de las otras columnas de certificación de `obras`, con el mismo panel y el mismo
gate (`admin_maestro`).

**El ancla del período se calcula, no se configura** — helper nuevo
`proximo_periodo_certificacion(obra_id)`:

1. El **último certificado emitido** de la obra (`max(fecha_emision)` excluyendo `anulado`), más el
   intervalo de la periodicidad.
2. Si no hay ninguno, el **congelamiento** (`presupuesto_congelado_en`) más el intervalo.
3. **Si la obra no está congelada, no se avisa.** Sin contrato firmado no hay período pactado que
   correr, y empujar a certificar contra precios vivos es justo lo que el Modelo A evita.

Sin columna de ancla y sin tabla de calendario: el dato ya está en la base.

**Cuándo aparece el aviso** (rama nueva de `mis_pendientes()`, tipo `certificacion_periodo`):
periodicidad pactada + Modelo A + obra congelada + venció el período + **no hay borrador en curso**
(si alguien ya está armando el certificado, el recordatorio es ruido) + el que mira es
`admin_maestro`, `profesional` o `constructor` (los que cargan avance; el cliente no inicia la
certificación). `entidad_id` en `null` — no es una fila de ninguna entidad —, y la app lleva a
**Gestión de Obra** de esa obra, que es donde se crea el borrador.

**Detalle de compatibilidad que permite aplicar la migración antes del Dart:**
`Pendiente.desdeRow` devuelve `null` para un `tipo` que la app no conoce y esa fila se saltea (0117).
Así que la `0123` se puede aplicar y verificar por SQL sin que la app vigente se entere.

**Decisión de alcance, confirmada por Seba (2026-09-13)**: el período corre **por intervalo desde el
ancla**, no por corte de calendario (fin de mes) — *"es un recordatorio, no una regla contable"*. Si
el uso real pide "siempre los días 30", es una columna más (`certificacion_dia_corte`) y un `case` en
el helper.

### 3.2 Período sugerido al crear el borrador — dentro de la Tanda 1

Confirmado por Seba: entra en esta tanda, *"evita que el usuario tipee el mismo texto cada vez"*.
Hoy `certificados.periodo` es texto libre que se tipea a mano en el diálogo de "nuevo borrador".

**Queda como sugerencia editable, nunca fijo** — es un default en el campo, no un valor calculado que
la base imponga: hay obras que van a querer escribir otra cosa ("Certificado de cierre", "Quincena de
lluvia"), y `periodo` es libre a propósito.

**Qué texto, según la periodicidad pactada** (todos derivados del fin del período que se está
certificando, o sea el valor de `proximo_periodo_certificacion`):

| Periodicidad | Sugerencia |
| --- | --- |
| `mensual` | el mes y el año del cierre del período — "Septiembre 2026" |
| `quincenal` | "1ª quincena de Septiembre 2026" si el cierre cae hasta el 15, "2ª quincena…" si no |
| `semanal` | "Semana del 08/09 al 14/09" (los 7 días que cierran en esa fecha) |
| sin pactar (`null`) | vacío, como hoy: lo tipea la persona |

**Dónde vive el cálculo**: en Dart, con las etiquetas (mismo criterio que el resto del proyecto), pero
**el ancla no se recalcula en Dart** — se pide por RPC a `proximo_periodo_certificacion(obra_id)`, que
ya sabe las tres reglas de ancla. Así no hay dos implementaciones de "cuándo cierra el período" que
puedan divergir.

---

## 4. Punto 3 — quién conforma técnicamente

La regla "el profesional si está, el cliente si no" es **la misma forma que ya existe** para
quitas/demasías (precedente 2). En SQL es un `exists` sobre `obra_members` con `rol = 'profesional'`
y `activo`.

**Pero hay una decisión de visibilidad que hay que tomar antes**, y es un hallazgo del relevamiento:
la RLS de `certificados` es `select using (is_obra_member(obra_id))`, **sin filtrar por estado**. O
sea que **hoy el cliente ya puede ver los borradores**. Si el flujo dice que el cliente recibe el
certificado *ya conformado*, hay dos caminos: dejarlo así (el cliente ve que se está armando, y solo
no participa) o esconderle el borrador (cambio de RLS, con efecto sobre `mis_pendientes` y las
pantallas). No lo resuelvo acá: es una de las ambigüedades de §8.

---

## 5. Punto 4 — la objeción del cliente

**No hace falta agregar un estado al ciclo — confirmado por Seba (2026-09-13).** Esto contradice la
intuición del pedido, y es la mejor noticia del diagnóstico: siguiendo el precedente de la anulación, la objeción es **un eje aparte**:

- `objecion_estado` (`abierta` / `aclarada` / `aceptada`), `objecion_fundamento text`,
  `objecion_por` + `objecion_fecha`, `objecion_resuelta_por` + `objecion_resuelta_fecha`, con checks
  de coherencia calcados de los de `anulacion_*` (**fundamento obligatorio a nivel base**, no solo en
  la UI: *una objeción sin motivo no sirve*).
- **El freno al pago es una sola línea** en `marcar_certificado_pagado`, que hoy tiene un único
  guard de estado. Leer sigue permitido (leer no es pagar).
- **La corrección no se reinventa: se conecta con la anulación que ya existe.** Si la objeción tiene
  razón → el circuito de anulación (profesional + constructor) anula y genera el reemplazo en
  borrador con las filas copiadas. Si no la tiene → se aclara, queda el rastro, el pago se habilita.
  Los dos circuitos encajan sin tocar la anulación: **el cliente objeta, las dos partes técnicas
  corrigen**, que es justo la matriz ("el Cliente observa el error, no participa del circuito").
- Un pendiente más ("te objetaron un certificado") y la UI en `DetalleCertificadoScreen`.

**Por qué esto importa para el riesgo:** mientras `certificados.estado` no gane valores nuevos, no se
tocan las 4 check constraints de fechas, ni `calcular_avance_acumulado_subitem` (que excluye
`borrador`/`anulado`), ni el índice de un borrador por obra, ni las otras transiciones.

---

## 6. El avance global — no es el Modelo B

**Modelo B es etapas con monto cerrado.** `hitos_certificacion.monto` es un importe fijo por hito, el
avance se calcula como `sum(monto) filter (estado = 'finalizado') / monto_total_contratado`, y un
hito se "certifica" cambiándole el estado a `finalizado`. **No hay porcentajes de avance, y no hay
ciclo de certificado**: la RLS de INSERT de `certificados` exige
`obra_modelo_es(obra_id, 'avance_medido')`. Traducido: **si el avance global se implementara como
Modelo B, perdería todo lo construido y verificado** — borrador, emitido/leído/pagado/cerrado,
anulación, anticipo y fondo de reparo, CAC, cotización congelada, avisos de pendientes.

**Lo que pide Seba es Modelo A con otra granularidad de carga**, y hay dos formas:

**Forma A — el porcentaje global se distribuye (recomendada).** Se carga un porcentaje del alcance
(toda la obra, o un rubro) y el sistema escribe las mismas filas de `certificado_subitems_avance`
repartidas por peso del monto congelado. Guardar en el certificado **cómo se cargó**
(`porcentaje_global_periodo`, `alcance_global`) para que quede dicho y no parezca medición partida por
partida. Ventaja: **cero cambios en el núcleo** — el 100% acumulado, los excesos, el CAC, la
anulación, el avance ponderado por rubro y la vista previa siguen funcionando sin tocarse. Costo: una
función de reparto y un modo de carga en la UI.

**Forma B — filas sin partida.** `obra_subitem_id` nullable + un discriminador de alcance + check de
"exactamente un alcance". Toca **el núcleo del cálculo**: el trigger `calcular_monto_periodo_avance`,
`calcular_avance_acumulado_subitem`, `calcular_excesos_certificado` (el candado del 100%),
`calcular_avance_ponderado_rubros`. Es el camino que sí pone en riesgo lo que ya anda.

**Elegida por Seba (2026-09-13): Forma A**, *"que el avance global se reparta en las filas por
partida ponderado por el monto congelado"*, **y el modo elegido por obra** (no mezclar dentro de la misma obra: si una
obra certifica global, que no muestre porcentajes por partida como si fueran medidos).

---

## 7. Radio de impacto medido

- **SQL**: 2 funciones a recrear (`emitir_certificado`, `marcar_certificado_pagado`) + 2 funciones
  nuevas por circuito (proponer/resolver conformidad, objetar/resolver) + `mis_pendientes()`
  (una rama por aviso). Columnas nuevas en `certificados` y en `obras`. **Ninguna tabla nueva.**
- **Dart**: `EstadoCertificado` se usa en 3 archivos fuera del modelo
  (`gestion_obra_tab.dart` ×14, `certificados_repository.dart` ×8, `detalle_certificado_screen.dart`
  ×8). Si en algún momento sí se agrega un valor al enum, los `switch` exhaustivos de Dart 3 hacen
  que `flutter analyze` liste exactamente qué falta — el compilador es la checklist.
- **Lo que no se toca** con las formas propuestas: las 4 check constraints de fechas, el índice de un
  borrador por obra, `calcular_avance_acumulado_subitem`, el candado del 100%, la anulación, el CAC,
  los snapshots de la `0107`/`0122`.

---

## 8. Ambigüedades a cerrar antes de escribir SQL

1. **¿El cliente ve el borrador? — CERRADA (Seba, 2026-09-13): depende de si hay profesional.**
   *"El cliente no ve el borrador cuando hay profesional en la obra. Si el flujo dice que recibe el
   certificado ya conformado, ver el borrador lo mete en una discusión que es entre las partes
   técnicas. Y si no hay profesional, sí lo ve, porque ahí es él quien acuerda."*

   **Consecuencia técnica (Tanda 2):** la RLS de SELECT de `certificados` deja de ser
   `is_obra_member(obra_id)` a secas. Pasa a ser: cualquier miembro para los estados distintos de
   `borrador`; y para `borrador`, miembro **menos** el cliente/apoderado **cuando existe un
   profesional activo en la obra**. Misma condición que ya usa el resto de la pieza ("¿hay
   profesional?"), y afecta también a `certificado_subitems_avance` (su policy de SELECT delega en
   `is_obra_member` de la obra del certificado) y a lo que el cliente ve en pantalla. **Es el único
   cambio de RLS de toda la pieza: va con su propia verificación, con un usuario cliente real.**
2. **Sin profesional, ¿el cliente conforma antes de emitir? — CERRADA (Seba, 2026-09-13): sí, ocupa
   el lugar del profesional.** *"Acuerda con el constructor y después paga. Si no, quedaría objetando
   algo que nunca acordó."*

   **Consecuencia técnica (Tanda 2):** quién puede dar conformidad no es un rol fijo — es "la
   contraparte": si hay profesional activo, el profesional (y el cliente no ve el borrador); si no
   hay, el `cliente_principal` (o apoderado habilitado), que entonces sí lo ve. El guard de
   `emitir_certificado` exige conformidad de esa contraparte, distinta de quien propuso.
3. **¿La objeción suspende el plazo de pago?** Hoy el vencimiento se cuenta desde `fecha_emision` con
   los días congelados al emitir.
4. **¿El constructor con `puede_editar_presupuesto` puede seguir emitiendo solo** cuando no hay
   profesional ni cliente que conforme?
5. **Avance global: ¿el modo se elige por obra o por certificado?** ¿Se permite mezclar?
6. **¿Los adicionales aprobados entran en el certificado global?** Hoy se certifican por su propia
   vía (`certificar_avance_adicional`, `0120`).

---

## 9. Tamaño y cómo partirlo

**Conviene partirlo en 4, y en este orden** — cada tanda entrega algo usable y las dos primeras no
tocan nada de lo que ya está probado:

| Tanda | Qué | Riesgo | Tamaño |
| --- | --- | --- | --- |
| **1 · Periodicidad y aviso** | 1-2 columnas en `obras`, 1 rama en `mis_pendientes`, 1 caso de enum + navegación, campo en el panel de config | **Nulo**: no toca ninguna transición | Chica |
| **2 · Acuerdo en el borrador** | columnas de propuesta/conformidad, guard en `emitir_certificado`, 1 pendiente, UI ("Proponer para revisión" / "Conforme" / "Devolver con comentario") | Bajo: `estado` no cambia; el único cambio de comportamiento es que emitir exige conformidad | Media |
| **3 · Objeción del cliente** | eje `objecion_*`, guard en `marcar_certificado_pagado`, 2 funciones, 1 pendiente, UI en el detalle | El más delicado: toca el cobro y engancha con la anulación | Media |
| **4 · Avance global** | función de reparto + modo de carga + cómo se guarda que fue global | Bajo con la Forma A, alto con la Forma B | Media, **aparte** |

**Por qué en ese orden:** la 1 es independiente de todo y da el aviso que hace que el resto se use.
La 2 instala el acuerdo *antes* de emitir, que es donde vive el ida y vuelta, y deja el cobro
intacto. La 3 recién después, porque la objeción es la contracara del acuerdo (si el acuerdo funciona
bien, la objeción es la excepción) y es la única que mete la mano en el pago. La 4 no comparte nada
con las otras tres: es la granularidad de la carga, no el circuito.

**Lo que NO conviene**: mezclar la 4 con la 2. Cambiar al mismo tiempo *cómo se carga* y *cómo se
acuerda* deja sin saber cuál de los dos cambios rompió algo si algo se rompe.
