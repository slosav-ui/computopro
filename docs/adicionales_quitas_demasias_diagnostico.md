# Adicionales, Quitas y Demasías — diagnóstico

Verificado contra el código real (`supabase/migrations/`, `lib/`), no contra lo que dice `CLAUDE.md`
donde diverge — encontré una divergencia real, ver §3.

**Estado: las 3 ambigüedades de §7 quedaron cerradas con el usuario. La migración
`0109_quitas_demasias.sql` quedó aplicada y verificada en producción, con dos usuarios reales.**
Adicionales (pospuesto en §8) se retoma en §11 — diseño cerrado, diagnóstico técnico y lista de
archivos, sin escribir SQL todavía.

## 1. Los dos circuitos — ¿alcanza una sola tabla?

**Sí, con la corrección del FK.** `modificaciones_obra.tipo` ya distingue
`adicional`/`demasia`/`quita`/`ajuste_contrato` (este último, `0008`, un cuarto tipo para ajustes
puramente monetarios del Modelo B, no se toca acá). El comportamiento distinto que describís no
necesita dos tablas — necesita que la política de aprobación y la función que aplica el efecto
**se ramifiquen por `tipo`**, cosa que este proyecto ya hace en otros lados (`libro_entradas_insert`
ramifica por `libro`, `hitos_certificacion` por `contratista_nombre`). Una tabla, comportamiento
distinto por columna discriminadora — mismo patrón, no uno nuevo.

## 2. El desajuste del FK — resuelto, con el criterio que pediste confirmar

Confirmado exactamente como lo planteaste: `subitem_id` (`0002`, sin FK porque `subitems` no
existía todavía) apuntaría al **catálogo compartido** si se le pusiera la FK tal cual — no puede
representar "esta línea, en esta obra puntual, con la cantidad que tiene ahí". Corrección:

- **Quita/Demasía**: necesitan referenciar `obra_subitems(id)`, no `subitems(id)` — es
  literalmente la partida cuya cantidad están corrigiendo. Propongo agregar una columna nueva
  `obra_subitem_id uuid references obra_subitems(id)`, obligatoria para estos dos tipos.
- **Adicional**: no referencia ninguna fila existente — es trabajo que no estaba, no hay nada que
  corregir. `apu_privado_id` (para cuando el adicional se cotiza con una composición de APU
  propia) sigue teniendo sentido, pero también sin FK real hoy — mismo arreglo, referencia a
  `apu_composiciones(id)`.
- El `subitem_id` viejo (catálogo) queda sin usar en la práctica para estos dos circuitos — no
  propongo borrarlo todavía por si `ajuste_contrato` u otro caso lo necesitara, pero ningún flujo
  nuevo lo escribe.

Un `check` por tipo (mismo patrón que ya usa `ajuste_contrato` en `0008`, que fuerza
`subitem_id`/`apu_privado_id` nulos): `demasia`/`quita` exigen `obra_subitem_id` no nulo;
`adicional` lo exige nulo.

## 3. Autoridad de aprobación — la divergencia real que encontré

**Tu instrucción de hoy**: quitas/demasías las aprueban profesional y constructor; adicionales los
aprueba el cliente (o el apoderado con tope). Constructor solo puede solicitar un adicional, nunca
aprobarlo.

**Lo que dice `CLAUDE.md` — dos pasajes que no coinciden entre sí, y ninguno de los dos coincide
con lo de hoy:**

- Línea 202-206 (resumen de la spec): *"Admin Maestro / Profesional: ... aprobación de
  certificados y adicionales sin restricción... Cliente/Propietario Principal: ... aprobación
  final de certificados y adicionales."* — no menciona a Constructor para nada, y le da a
  Admin/Profesional aprobación **sin restricción**, no solo al Cliente.
- Línea 403 (documentando `0008_ajuste_contrato.sql`): *"no puede ser edición libre del
  Administrador, tiene que pasar por el mismo circuito de aprobación"* — apunta en la otra
  dirección, pero sin excluir explícitamente a Profesional tampoco.

**Lo que hace el código real, verificado, no asumido**: `puede_aprobar_monto` (`0004_rls_etapa3.sql`,
la función que hoy gobierna el `UPDATE` de `modificaciones_obra` para TODOS los tipos, incluidos
`adicional`/`demasia`/`quita`) da autoridad sin tope a `admin_maestro`, `profesional` **y**
`cliente_principal` por igual, más `invitado_apoderado` con tope+delegación. **Constructor no
aparece en ningún lado de esa función** — ni para aprobar, coincide con vos. Pero **Profesional y
Admin Maestro sí pueden aprobar un adicional hoy**, sin que el Cliente tenga ninguna exclusividad
real — contradice directamente lo que pedís hoy.

**Conclusión: no se puede reusar `puede_aprobar_monto` para ninguno de los dos circuitos nuevos.**
Esa función queda tal cual, sin tocar — sigue siendo la autoridad correcta para `ajuste_contrato`
(Modelo B, ya aplicada, no se toca). Hacen falta dos funciones nuevas, más angostas:

- `puede_aprobar_quita_demasia(obra_id)`: profesional o constructor. **Ambigüedad — ver §7**:
  ¿alcanza con que uno de los dos apruebe, o hace falta que los dos estén de acuerdo (como la
  anulación de certificados, que sí exige una dupla propone/resuelve)? Tu texto ("entre ellos")
  admite las dos lecturas.
- `puede_aprobar_adicional(obra_id, monto)`: cliente_principal sin tope, o invitado_apoderado con
  `puede_aprobar_adicionales` + tope + delegación vigente — el campo `puede_aprobar_adicionales`
  de `PermisosEspeciales` ya existe en el schema (`0001`) y hoy no lo usa nada, esta seria su
  primera conexión real. **Ambigüedad — ver §7**: ¿admin_maestro queda afuera también, o el dueño
  de la obra conserva la potestad de aprobar un adicional aunque no sea quien paga?

## 4. Impacto en la certificación

**Demasía/Quita — confirmado, tu lectura es exactamente correcta y no hace falta tocar
certificación.** El avance se guarda como `porcentaje_periodo` (0 a 100), no como una cantidad
absoluta — es independiente de cuánto valga `obra_subitems.cantidad` en cada momento.
`calcular_avance_acumulado_subitem` sigue sumando porcentajes sin cambios; el próximo certificado
que se cargue va a calcular su `monto_periodo` contra el `monto_total` que resulte de la nueva
cantidad, automáticamente, sin ningún ajuste adicional en la cadena de certificación. Aprobar una
quita/demasía es, en el fondo, un `UPDATE obra_subitems.cantidad` con guarda de aprobación
alrededor — nada más en esa tabla cambia.

**Adicional — necesita mecanismo propio, y acá es donde hay que decidir cuánto construir.** Tu
decisión ("corren por su propio camino... si entrara al total, el % de avance de toda la obra se
recalcularía y bajaría de golpe") es correcta y tiene una implicancia que quiero remarcar: el
comentario original del modelo Dart (`modificacion_obra.dart:13-14`, "'adicional': null hasta que
se aprueba — en ese momento se gradúa a un Subitem real del cómputo") queda **contradicho por tu
propia decisión de hoy**. Graduarlo a un `obra_subitems` real es exactamente lo que NO hay que
hacer — entraría a `calcular_presupuesto_vivo_obra`/`calcular_avance_ponderado_obra` y diluiría el
% de avance, el problema que vos mismo señalás. Ese comentario viejo queda anotado como
**incorrecto a la luz de esta decisión**, no como algo a implementar.

Propuesta mínima para "su propio seguimiento": dos columnas nuevas en la propia fila de
`modificaciones_obra` (solo para `tipo='adicional'`, y solo una vez `aprobado`) —
`porcentaje_avance numeric default 0` y `monto_certificado numeric default 0` — con una función
`certificar_avance_adicional(modificacion_id, porcentaje)` que valide que no se pase de 100%
acumulado (mismo candado que ya existe para partidas normales, reimplementado en chico) y
recalcule `monto_certificado = monto_total × porcentaje / 100`. No propongo reusar
`certificado_subitems_avance` ni el ciclo de 5 estados de `certificados` — sería exactamente
"entrar al total" por la puerta de atrás. **Esto es una pieza de diseño real, no solo plomería —
márcala en la ambigüedad §7 si preferís otra forma.**

## 5. El presupuesto congelado — encontré una interacción real que tu pregunta hizo aparecer

Acá está el hallazgo más importante de este diagnóstico, y es la razón principal por la que esta
pieza es más grande de lo que parece.

**Demasía/Quita en una obra YA congelada**: si solo se actualiza `obra_subitems.cantidad` y se
deja `presupuesto_subitems_congelado` intacto, la certificación de esa obra —que para una obra
congelada lee **exclusivamente** el snapshot congelado, nunca `obra_subitems` en vivo
(`calcular_monto_obra_subitems`, rama congelada, `0105`)— **nunca se entera de la cantidad
nueva**. Los metros de más (demasía) quedarían ejecutados pero **imposibles de certificar**; los
metros de menos (quita) seguirían facturándose de más. Esto no es un caso raro: es el caso normal,
porque una obra que ya está certificando avance normalmente ya está congelada.

**La corrección, consistente con el resto del diseño de congelamiento**: aprobar una
quita/demasía en una obra congelada tiene que actualizar, en la misma transacción, la fila
correspondiente de `presupuesto_subitems_congelado` — `cantidad` a la nueva, y `monto_total`
recalculado como `nueva_cantidad × precio_final` (reusando el `precio_final` YA CONGELADO de esa
misma fila, nunca recalculado contra el precio de insumos de hoy — mismo principio de "no se
recalcula desde el costo real de los insumos" que ya rige todo el congelamiento). `costo_costo`/
`materiales_subtotal` se re-escalan en la misma proporción (son por-unidad × cantidad, igual que
`monto_total`), para que el futuro ajuste por CAC (que ya usa esa proporción, `0105`/`0106`) siga
siendo correcto. Si la obra NO está congelada todavía, no hace falta tocar nada más allá de
`obra_subitems.cantidad` — no hay ningún snapshot con el que desincronizarse.

**No toca el congelamiento en sí** (no se re-congela la obra entera, no se pide `motivo`, no pasa
por `congelar_presupuesto_obra`) — es una corrección puntual de una fila, coherente con que esto
"no es un cambio de alcance, es lo que pasó en obra". Se registra en `audit_log` como cualquier
otra aprobación.

**Nota aparte, no bloqueante**: un caso borde real — una partida que ya está 100% certificada y
después sufre una quita. No hace falta ningún candado nuevo para esto: el % ya certificado sigue
siendo un % válido (es independiente de la cantidad, ver §4), simplemente termina representando
menos plata de la que representaba antes. Los certificados YA EMITIDOS no se tocan — mismo
principio de "no retroactivo" que rige todo lo demás del proyecto.

## 6. Cómo se informa al propietario

**`audit_log` alcanza tal cual está, sin ninguna migración.** Verificado: la política
`audit_log_insert` (`0004`) ya deja que **cualquier** miembro de la obra —incluido
`cliente_principal`— inserte su propia fila (`usuario_id = auth.uid() and is_obra_member(obra_id)`),
y no hay política de `UPDATE`/`DELETE` para nadie — append-only por diseño, así que una
observación **no puede trabar nada** aunque quisiera: no hay ningún mecanismo por el que insertar
una fila en `audit_log` bloquee o cambie el `estado` de la `modificacion_obra` que comenta. Esto
cumple exactamente lo que pediste ("que quede registrado... pero que no trabe nada") sin escribir
una sola línea de SQL nueva — alcanza con que el repositorio Dart arme el `insert` con
`accion='observar_modificacion'`, `entidad='modificacion_obra'`, `entidad_id=<id>`, y
`detalle={comentario: "..."}`.

**Nota, no para esta pieza**: el lugar conceptualmente perfecto para esto es el Libro de Obra vos
mismo lo comparaste ("se asienta y se discute... como en el libro de obra") — pero esa pieza tiene
tabla aplicada y cero pantalla (`docs/gestion_obra_estado_real_auditoria.md` §5-bis). Usar
`audit_log` ahora no es una solución de paso descartable: es el mismo patrón que ya usa el resto
del proyecto para todo lo que todavía no tiene un lugar mejor (certificados, antes de tener su
propio ciclo). Si el día de mañana se construye el Libro de Obra, migrar estas observaciones ahí
es straightforward — mismo `entidad_id`, otro lugar de lectura.

## 7. Ambigüedades — cerradas con el usuario

**A. Quita/Demasía — ¿uno solo o los dos?** **Cerrado: uno solo** (profesional o constructor,
cualquiera de los dos alcanza), Opción 1. Palabras de Seba: "las demasías son lo más frecuente y
lo que se necesita es que quede asentado, no negociado. Si hace falta que los dos firmen por tres
metros de contrapiso, nadie lo usa." Implementado en `0109`, `puede_aprobar_quita_demasia`.

**B. Adicional — ¿admin_maestro también aprueba?** **Cerrado: no, estrictamente
cliente_principal/apoderado**, Opción 1. Palabras de Seba: "si el profesional o el administrador
pueden aprobar un adicional, deja de ser una aprobación del que paga y se vuelve un trámite
interno — y ese es justamente el punto del circuito." Queda para la migración de Adicionales
(pospuesta, §8) — no aplica a `0109`.

**C. Seguimiento del adicional — ¿cuánto construir?** **Cerrado: la propuesta mínima**
(porcentaje + monto, sin ciclo propio), Opción 1. Palabras de Seba: "construir un segundo circuito
de certificación reducido para adicionales sería duplicar lo que ya existe, y todavía no sabemos
si hace falta... si con el uso resulta que un adicional se cobra en partes como una obra chica, ahí
se evalúa." Queda para la migración de Adicionales (pospuesta, §8) — no aplica a `0109`.

## 8. Tamaño — confirmando lo que ya sospechabas

**Conviene el corte que proponés: quitas y demasías primero, adicionales después — y con una
razón concreta, no solo por frecuencia de uso.** Quitas/demasías, una vez resuelto el FK y la
función de autoridad, son plomería relativamente contenida: un `UPDATE` de `obra_subitems.cantidad`
con guarda de aprobación, más la corrección puntual de `presupuesto_subitems_congelado` (§5) — no
inventan ningún concepto nuevo, reusan el 100% de la certificación existente. Adicionales, en
cambio, necesitan una pieza de diseño real todavía sin cerrar (§4/§7-C) antes de poder escribir una
sola línea de SQL — encararlos juntos mezclaría una pieza casi lista con una que todavía no está
definida del todo.

## 9. Archivos

**Nuevo, Supabase — escrito, sin aplicar ni verificar todavía**:
- `supabase/migrations/0109_quitas_demasias.sql` — `modificaciones_obra.obra_subitem_id` + `check`
  por tipo; `puede_aprobar_quita_demasia` (uno solo, profesional o constructor, ambigüedad A);
  `aprobar_quita_demasia(modificacion_id, comentario)` (aprueba + actualiza
  `obra_subitems.cantidad` + corrige `presupuesto_subitems_congelado` si la obra está congelada +
  `audit_log`, atómica — mismo patrón que `aprobar_ajuste_contrato`, `0008`); política
  `modificaciones_obra_update` ramificada por `tipo`, sin tocar el comportamiento de
  `adicional`/`ajuste_contrato` (siguen con `puede_aprobar_monto`, sin cambios).

**Pospuesto a propósito (Adicionales, después de esta pieza)**: `apu_privado_id` con FK real;
`puede_aprobar_adicional` (cliente_principal/apoderado, nunca admin_maestro/profesional,
ambigüedad B); columnas + función de seguimiento mínimo (ambigüedad C); `aprobar_adicional`.

**A tocar en Dart — siguiente pasada, después de aplicar y verificar `0109`**:
- `lib/data/models/modificacion_obra.dart` — reescribir a patrón `_fromRow`/`_toRow` snake_case
  (hoy es camelCase directo, patrón pre-Supabase, ver `docs/gestion_obra_estado_real_auditoria.md`
  §2) + `obraSubitemId`.
- `lib/services/modificaciones_obra_repository.dart` (nuevo) — no existe ningún repositorio hoy;
  incluye el `insert` directo a `audit_log` para la observación del propietario (§6, sin RPC nueva).
- Pantalla nueva en Gestión de Obra para crear/aprobar/observar quitas y demasías.
- `lib/core/segurity/user_context.dart` — getter nuevo mirroreado contra
  `puede_aprobar_quita_demasia` (mismo criterio que ya se usó para el ciclo del certificado — nunca
  reusar un getter existente cuya autoridad real ya se sabe distinta).

**No tocados**: `puede_aprobar_monto`/`aprobar_ajuste_contrato` (Modelo B, siguen sirviendo tal
cual, comportamiento sin cambios); `calcular_presupuesto_vivo_obra`/`calcular_avance_ponderado_obra`/
todo lo que compone el % de avance de la obra (a propósito — adicionales nunca deben tocar esto, es
el punto central de
tu decisión).

## 10. Cómo se ven los adicionales en el dashboard — dato nuevo, sin construir (2026-09-12)

Agregado a partir de la corrección del chip Pactado/Hoy del presupuesto congelado
(`docs/presupuesto_congelado_validez_modelo_a_diseno.md`), que hizo aparecer la pregunta natural
siguiente: cuando exista un adicional aprobado, ¿qué muestra la card de `ObrasListScreen`? Esto es
**diseño, no implementación** — depende del circuito de Adicionales (§8, pospuesto), que sigue sin
una sola línea de SQL escrita.

### 10.1 Cada adicional tiene su propia foto, no hereda la del contrato

Palabras de Seba: *"si en la obra original se pactó el precio con impuestos, cargas sociales y
materiales y mano de obra, el adicional se puede pactar sin alguno de estos o sin ninguno."*

Esto es una pieza de diseño real que §4/§7-C de este documento todavía no cubrían: la propuesta
mínima de ahí (`porcentaje_avance`/`monto_certificado`) resuelve el *seguimiento* de un adicional ya
aprobado, pero no dice nada sobre **cómo se fija su monto** ni **con qué configuración**. Con el
hallazgo de §10 de `presupuesto_congelado_validez_modelo_a_diseno.md` fresco (un desfasaje solo es
comparable si las dos puntas usan la misma configuración), la respuesta tiene que ser la misma que
ya rige el presupuesto: **el adicional se congela con su propia foto** — monto y los 6 % + impuestos
de Factor K vigentes en el momento en que se aprueba, mismo patrón que `presupuesto_config_congelado`
(`0104`) pero una fila por adicional, no una por obra.

**Que no se vuelva complicado (criterio de Seba para toda la app: flexible, intuitiva, fácil
aplicación)**: el caso normal — la inmensa mayoría de los adicionales — se pacta en las mismas
condiciones que el contrato. Proponer que el adicional **arranque con la config vigente de la obra
al momento de crearlo** (copiada, no referenciada — mismo motivo que el propio presupuesto: si se
referenciara y la config de la obra cambiara después, el adicional se movería solo) y que cambiarla
sea una opción detrás de un toggle/expansor, no un paso obligatorio. El que hace lo habitual no
toca nada; el que necesita pactar distinto, puede.

**Y tiene que verse en texto claro, no en un desglose de porcentajes** — la propia palabra de Seba:
*"si no, dentro de seis meses nadie sabe qué se pactó."* Una etiqueta corta por adicional
("Con impuestos y cargas sociales" / "Solo mano de obra, sin impuestos" / etc.), derivada de
comparar su config congelada contra la del contrato. **Dónde se ve esto, corregido en §10.2**: no
en el dashboard — ver el criterio de pantalla principal que se sumó ahí.

### 10.2 Dónde vive cada cosa — corregido (Seba, 2026-09-12): el dashboard no acumula datos

**Criterio nuevo para toda la pantalla principal, no solo para esta pieza**: información clara y
escueta en el dashboard — la información completa vive en la solapa Resumen (el tablero de
situación de la obra) o al entrar a la obra, nunca en la card de `ObrasListScreen`. Corrige la
primera versión de esta sección, que proponía mostrar una aclaración de "condiciones distintas" en
el propio dashboard — eso ya es más dato del que la card tiene que cargar.

**La card, con esto aplicado:**
- **Pactado** sigue siendo el número grande (§8/§10 de la otra pieza, sin cambios) — el contrato
  original, tal cual se firmó.
- Debajo, una sola línea: **"Total con adicionales: $T (N aprobados)"** — la suma de Pactado + el
  monto congelado de cada adicional aprobado. Nada más — sin desglose, sin aclaración de
  condiciones mezcladas, sin etiquetas.
- Esa línea es tappable y lleva a la obra — nunca abre el detalle ahí mismo.
- Sin adicionales aprobados (caso de hoy, 100% de las obras): la card no cambia en nada.

**Todo lo demás — cada adicional con su monto, su etiqueta de configuración (§10.1), la aclaración
de condiciones mezcladas cuando corresponda, la entrada para ver/aprobar/observar uno — vive en la
solapa Resumen o en la pantalla de detalle dentro de la obra**, nunca en el dashboard. Mismo
criterio que ya separa "Pactado + Hoy + Desfasaje" (dashboard, resumido) de "Pactado + Saldo
pendiente + aviso de índice" (`PresupuestoEstadoPanel`, dentro de Gestión de Obra, con más detalle)
— la pieza anterior ya tenía este patrón sin nombrarlo; esto lo deja explícito para que la próxima
pantalla lo siga sin tener que redescubrirlo.

### 10.3 Cuándo construir esto — respondiendo lo que preguntás

**Conviene hacerlo junto con el circuito de Adicionales, no antes ni aparte.** Tres motivos
concretos:

1. Esta pantalla no tiene nada que mostrar sin el circuito — no hay tabla, no hay `monto_total`, no
   hay config congelada de adicional. Construirla antes sería una card vacía esperando datos que
   todavía no existen.
2. El circuito de Adicionales (§4/§7-B/§7-C, pospuesto) todavía tiene ambigüedades reales sin
   cerrar (autoridad de aprobación, cuánto seguimiento propio) — la config congelada de §10.1 es una
   pieza más de ese mismo diseño, no una capa aparte: cerrarla en el mismo diagnóstico evita firmar
   dos veces el mismo tipo de decisión.
3. Es plomería relativamente barata sumarla ahora que el circuito ya está sobre la mesa (una tabla
   más -- `modificaciones_obra_config_congelada` o columnas en la propia fila -- siguiendo
   exactamente el patrón que `presupuesto_config_congelado` ya dejó probado) — separarla en una
   pieza aparte más adelante significaría releer y re-diagnosticar todo esto por segunda vez.

**Siguiente paso concreto, cuando se retome Adicionales**: extender §4/§7 de este mismo documento
con (a) la config congelada por adicional (§10.1) como parte de la propuesta mínima de seguimiento,
y (b) el diseño de card de §10.2, antes de escribir la migración — mismo proceso que ya usa el
proyecto (diseño primero, ambigüedades cerradas con el usuario, migración después).

## 11. Adicionales — diagnóstico técnico y lista de archivos (2026-09-13)

Diseño ya cerrado por Seba, en esta sesión y en §10: propia foto (monto + config de Factor K),
arranca con la config vigente de la obra por default, etiqueta corta solo cuando difiere,
aprobación de cliente_principal/apoderado (nunca profesional/admin_maestro), seguimiento mínimo
(% + monto, sin ciclo propio). Esta sección verifica contra el código real qué de eso ya existe,
qué falta, y qué preguntas quedan genuinamente abiertas antes de poder escribir la migración.

### 11.1 Lo que ya existe y se puede reusar tal cual

- **`modificaciones_obra`** (`0002`/`0008`/`0109`) ya tiene `tipo='adicional'` en su check, y las
  columnas genéricas alcanzan sin agregar ninguna para el dato base: `descripcion`, `cantidad`,
  `precio_unitario_heredado`, `monto_total`, `solicitado_por`/`subido_por`, `estado`
  (`pendiente`/`devuelto`/`aprobado`/`rechazado`), `aprobado_por`, fechas. `obra_subitem_id` (0109)
  correctamente NO aplica a adicional (el check de esa migración ya lo exige nulo para este tipo).
- **`puede_aprobar_monto(obra_id, monto)`** (`0004`) ya tiene la mitad correcta de la regla nueva:
  `cliente_principal` sin tope, `invitado_apoderado` con `puede_aprobar_adicionales` + tope +
  delegación vigente. Le sobra `admin_maestro` y `profesional` — no se puede reusar tal cual (ver
  §3, la contradicción que ya había encontrado este documento), hace falta una función angosta
  nueva, mismo patrón que `puede_aprobar_quita_demasia` (0109) copiado y recortado.
- **`PermisosEspeciales.puedeAprobarAdicionales`/`topeMontoAprobacion`/delegación** (`lib/data/
  models/obra_member.dart`) ya existen en Dart y en la base (`obra_members`, columnas de `0001`) —
  cero trabajo de schema para esto, es literalmente el campo que hoy no conecta nada (confirmado en
  §3 del diagnóstico original).
- **`UserContext.puedeMarcarCertificadoPagado(monto)`** (`user_context.dart:170-177`) es el mirror
  exacto en Dart de la regla que hace falta — mismo cálculo, mismo campo de `PermisosEspeciales`
  (ahí es `puedeAprobarCertificados`, acá sería `puedeAprobarAdicionales`). Copiar ese patrón, no
  reinventar uno nuevo.
- **`presupuesto_config_congelado`** (`0104`) es el molde exacto para la config propia del
  adicional (§10.1): mismas 8 columnas (`tipo_presupuesto` + 6 % + `impuestos_pct_total`), mismo
  criterio de "una tabla aparte, no columnas sueltas repetidas".
- **`ModificacionesObraRepository`/`QuitasDemasiasScreen`** ya prueban el patrón completo de
  pantalla (historial + expandir + aprobar/rechazar + observar) — Adicionales necesita su propio
  repositorio/pantalla (el propio comentario de cabecera de ambos archivos ya lo dice: "acotado a
  demasia/quita", "deliberadamente NO incluye Adicionales"), pero no un patrón nuevo, el mismo
  clonado y adaptado a la autoridad distinta.
- **`docs/presupuesto_congelado_validez_modelo_a_diseno.md` §10.2** (esta misma sesión) ya cierra
  cómo se ve en el dashboard: Pactado grande + una línea "Total con adicionales" tappable, nada de
  detalle ahí — ver §10.2 de este documento.

### 11.2 Lo que falta construir

**Schema (migración nueva, después de `0111`):**
1. `modificaciones_obra_config_congelada` — 1:1 con una fila de `modificaciones_obra` (no con la
   obra), mismas columnas que `presupuesto_config_congelado`. Se llena al **crear** el adicional
   (no al aprobar — la foto es de las condiciones pactadas al solicitarlo, discutible, ver
   ambigüedad D más abajo).
2. `puede_aprobar_adicional(p_obra_id uuid, p_monto numeric)` — copia de `puede_aprobar_monto` sin
   las ramas `admin_maestro`/`profesional`.
3. `modificaciones_obra_update`, rama `adicional` separada de `demasia`/`quita` (ya ramificada,
   0109) y de `ajuste_contrato` (que sigue con `puede_aprobar_monto`, sin tocar — Modelo B, fuera
   de alcance de esta pieza).
4. `crear_adicional(...)` — inserta la fila + su config congelada en una transacción (mismo
   criterio atómico que `congelar_presupuesto_obra`), snapshoteando la config VIGENTE de la obra
   como default.
5. `aprobar_adicional`/`rechazar_adicional` — mismo patrón que `aprobar_quita_demasia`, pero sin
   tocar `obra_subitems`/`presupuesto_subitems_congelado` (un adicional nunca entra al cómputo, por
   decisión ya cerrada en §4: "diluiría el % de avance").
6. Columnas de seguimiento (§4 de este documento, propuesta mínima ya cerrada): `porcentaje_avance
   numeric default 0`, `monto_certificado numeric default 0`, con check `entre 0 y 100` y
   `certificar_avance_adicional(modificacion_id, porcentaje)` (valida que no pase de 100%
   acumulado, recalcula `monto_certificado`).
7. `calcular_total_adicionales_aprobados(obra_id)` — para la línea "Total con adicionales" del
   dashboard (§10.2) y la solapa Resumen.

**Dart:**
- `ModificacionObra` gana los campos de la config congelada (o un modelo aparte,
  `ModificacionConfigCongelada`, unido por `modificacionId`) y `porcentajeAvance`/`montoCertificado`.
- `ModificacionesObraRepository` gana `crearAdicional`/`aprobarAdicional`/`rechazarAdicional`/
  `certificarAvanceAdicional`/`getAdicionalesDeObra` — o un repositorio nuevo,
  `AdicionalesRepository`, dado que la autoridad y el shape de datos difieren bastante de
  quitas/demasías (a decidir en la lista de archivos final, ver Tandas).
- `UserContext.puedeAprobarAdicional(double monto)` — nuevo getter, mismo patrón que
  `puedeMarcarCertificadoPagado`.
- Pantalla `AdicionalesScreen` (historial + crear + aprobar/rechazar) — no una pestaña de
  `QuitasDemasiasScreen`, por la misma razón que esa pantalla ya se negó a incluirlos: autoridad y
  forma de los datos distintas.
- `ObrasListScreen`: línea "Total con adicionales" (§10.2), ya diseñada, falta conectar.
- Etiqueta corta de condiciones distintas (§10.1) — función pura en Dart que compara la config
  congelada del adicional contra `presupuesto_config_congelado` de la obra y arma el texto
  ("Con impuestos y cargas sociales" / etc.), sin necesitar SQL propio.

### 11.3 Ambigüedades reales, no cerradas todavía — necesito tu respuesta antes de escribir SQL

**A. ¿Cómo se carga el "costo base" del adicional, antes de aplicarle la cascada de Factor K?**
No hay ningún subítem de catálogo detrás de un adicional (es scope nuevo, §2) — así que no hay
ninguna composición de APU de la que derivar un Costo-Costo automáticamente, a diferencia de una
partida normal. Veo dos caminos:
- **Opción 1 (recomendada): monto manual.** Quien carga el adicional tipea directamente el
  Costo-Costo (o el monto final, si elige no aplicar cascada) — mismo criterio que ya usan los
  rubros de precio manual del cómputo (1/18/19/20/custom): no todo tiene que salir de una
  composición de insumos. `cantidad`/`precio_unitario_heredado` (columnas que ya existen en la
  tabla) alcanzan para esto sin agregar nada.
- **Opción 2: composición de APU propia** (`apu_privado_id`, mencionado en §2 de este documento
  desde el diagnóstico original) — el usuario arma una composición de insumos igual que una
  partida real, y se le aplica la misma cascada completa. Es la opción más potente pero es una
  pieza aparte considerable (un editor de composición de APU sin subítem de catálogo detrás, hoy no
  existe nada parecido) — la marcaría como una extensión futura, no parte de esta pieza.
- Mi recomendación es la Opción 1 para esta pieza, dejando la Opción 2 anotada para si en algún
  momento hace falta (el "flexible, intuitivo, fácil aplicación" que pediste para toda la app
  encaja mejor con tipear un monto que con armar una composición de insumos para un solo uso).

**B. Si es Opción 1: ¿la cascada de Factor K se recalcula en la base (una función nueva, chica) o
alcanza con que Dart la calcule para la vista previa y la base solo la valide/guarde?**
El criterio "no duplicar la cascada" (0090) aplica a `calcular_factor_k_subitem`, que resuelve
Costo-Costo desde una composición real — acá no hay composición, el Costo-Costo YA es un número
que alguien tipeó. La fórmula que queda por aplicar (producto de factores sobre un número ya dado)
es mucho más chica que toda `calcular_factor_k_subitem`, así que no sería "una segunda
implementación de la misma cascada" en el sentido que preocupaba a esa decisión — sería una fórmula
distinta, más simple, para un insumo de entrada distinto. Aun así, prefiero preguntarte: ¿una
función SQL nueva y chica (`calcular_precio_adicional`, dinero calculado server-side, mismo
criterio que el resto del proyecto) o te alcanza con que la valide del lado de Dart porque total el
monto final lo tipea/confirma una persona antes de guardar? Mi recomendación es la función SQL —
"el dinero se calcula en la base" es el criterio que ya sigue todo el resto del proyecto, no le
haría una excepción a esta pieza.

**C. ¿Qué conceptos de la cascada son togglables para un adicional, exactamente?**
Tus palabras: "se puede pactar sin alguno de estos [impuestos, cargas sociales, materiales y mano
de obra] o sin ninguno." Materiales/mano de obra ya tiene un selector real (`tipo_presupuesto`,
con/sin materiales — pero eso solo tiene sentido si hay composición con insumos de material, que
en la Opción 1 no existe: un monto manual no se separa solo en materiales/mano de obra). Impuestos
sí es directo (aplicar o no el `impuestos_pct_total` de la config). "Cargas sociales" no es un
concepto de la cascada de Factor K (es un multiplicador previo sobre el valor-hora de mano de
obra, `ObraPresupuestoConfig.aplicaCargasSociales`) — no tiene ningún efecto sobre un Costo-Costo
ya tipeado a mano. Necesito que me confirmes: para un adicional con Opción 1 (monto manual), ¿los
togglables reales son únicamente los 6 conceptos de Factor K + impuestos (igual que
`presupuesto_config_congelado`), cada uno con su propio on/off además de su %? Eso es una columna
booleana más por concepto (o un array/jsonb de "conceptos activos"), no estaba en el diseño
original de `presupuesto_config_congelado` (que asume los 6 siempre activos, solo varía el %) —
sería una diferencia real de shape entre las dos tablas, no una reutilización 1:1 como asumí en
§10.1.

**D. ¿La foto se toma al crear el adicional, o al aprobarlo?**
Entre que el Constructor solicita y el Cliente/Apoderado aprueba puede pasar tiempo — si la config
de la obra cambia en el medio (por ejemplo, se agrega un impuesto nuevo), ¿el adicional se congela
con la config de cuando se solicitó, o con la vigente al momento en que el Cliente dice que sí?
Mismo tipo de pregunta que ya resolvió el presupuesto (ahí la respuesta fue "al firmar/congelar",
no al presentar) — sospecho que la respuesta simétrica acá es "al aprobar", no "al solicitar", pero
lo dejo para que lo confirmes en vez de asumirlo.

**E. (Menor) ¿Quién puede crear/solicitar un adicional?**
La política de `INSERT` de `modificaciones_obra` (`0004`) no chequea rol hoy, solo
`solicitado_por = subido_por = auth.uid()` — cualquier miembro de la obra podría insertar una fila
de tipo `adicional` en `pendiente`, incluido el propio Cliente. ¿Alcanza con dejarlo así (la
aprobación es la barrera real, no la creación) o preferís acotar quién puede crear a
profesional/constructor/admin_maestro, dejando al Cliente solo del lado de la aprobación? No
bloquea la escritura de la migración (es un ajuste angosto si hace falta), pero prefiero
preguntarlo ahora que decidirlo solo.

### 11.4 Archivos (para cuando se cierren las ambigüedades de arriba)

**Supabase, migración nueva (`0112`, después de `0111`):**
- `modificaciones_obra_config_congelada` (o el nombre que resulte de la ambigüedad C) + RLS
  (select para `is_obra_member`, sin política de escritura directa — mismo criterio que
  `presupuesto_config_congelado`).
- Columnas de seguimiento en `modificaciones_obra`: `porcentaje_avance`, `monto_certificado`.
- `puede_aprobar_adicional(obra_id, monto)`.
- `modificaciones_obra_update`: rama `adicional` separada.
- `crear_adicional(...)`, `aprobar_adicional(...)`, `rechazar_adicional(...)` (o `update` directo
  para rechazar, como ya hace `rechazarModificacion` de demasía/quita — no tiene efecto colateral
  que coordinar).
- `certificar_avance_adicional(modificacion_id, porcentaje)`.
- `calcular_total_adicionales_aprobados(obra_id)`.
- Si la ambigüedad B se cierra a favor de una función SQL: `calcular_precio_adicional(...)`.

**Dart:**
- `lib/data/models/modificacion_obra.dart` — campos nuevos de config congelada + seguimiento.
- `lib/services/modificaciones_obra_repository.dart` (o `adicionales_repository.dart` nuevo) —
  métodos de creación/aprobación/rechazo/certificación/listado de adicionales.
- `lib/core/segurity/user_context.dart` — `puedeAprobarAdicional(double monto)`, y un getter
  angosto para "puede solicitar" si la ambigüedad E se cierra a favor de acotarlo.
- `lib/presentation/obra_detalle/screens/adicionales_screen.dart` (nueva) — historial + crear +
  aprobar/rechazar, mismo patrón que `QuitasDemasiasScreen` adaptado a la autoridad distinta.
- `lib/presentation/obra_detalle/tabs/gestion_obra_tab.dart` — botón "Adicionales", mismo lugar que
  "Quitas y Demasías".
- `lib/presentation/dashboard/obras_list_screen.dart` — línea "Total con adicionales" (§10.2).
- Solapa Resumen — detalle de cada adicional (monto, etiqueta de condiciones, link a
  `AdicionalesScreen`) — pieza que ya está en el orden que pediste (después de Modelo B/
  subcontratos/libro de obra en tu lista original, o antes si el detalle de adicionales necesita
  vivir ahí desde el arranque — a confirmar cuando se llegue).

### 11.5 ¿Conviene partir esto en dos tandas?

**Sí, mismo criterio que ya usó el proyecto para separar Quitas/Demasías (schema+backend) del resto
(pantalla), y para separar esta pieza entera de Quitas/Demasías en primer lugar.** Motivos
concretos, no solo por tamaño:

- **Tanda 1 — schema + backend + creación.** Todo lo de §11.4 del lado de Supabase, más el
  repositorio Dart y la pantalla de CREAR un adicional (con la vista previa del monto calculado).
  Esto ya es verificable de punta a punta sin la aprobación: se puede crear un adicional, ver que
  queda `pendiente` con su config congelada, y confirmar que el cálculo cierra.
- **Tanda 2 — aprobación + seguimiento + dashboard.** `puede_aprobar_adicional` conectado a
  pantalla, aprobar/rechazar con dos usuarios reales (mismo patrón de verificación que ya usó
  Quitas/Demasías: cliente_principal o apoderado aprueba, profesional ve que NO puede), la
  certificación de avance en partes, y la línea del dashboard (que necesita que ya haya al menos un
  adicional aprobado para tener algo real que mostrar).

La frontera entre las dos tandas es la misma que ya separa "algo existe y se puede probar" de "el
circuito completo con dos roles distintos" — igual que Tanda 1/Tanda 2 de la pieza 4 de Gestión de
Obra (vista previa+emitir primero, después lo que dependía de tener certificados reales para
probar).

### 11.6 Ambigüedades — cerradas por Seba (2026-09-13)

**A.** Costo manual, confirmado ("el que lo cotiza pone su precio") — composición de APU propia
queda como extensión futura, no parte de esta pieza.

**B.** La cascada se calcula en la base — confirmado, mismo criterio del resto del proyecto.

**C. Corrección sobre el pedido original, no ambigüedad de la pregunta.** Los 6 conceptos de
Factor K NO son togglables — son la estructura de costos del contratista, se heredan tal cual del
contrato. Lo único elegible por adicional es si lleva impuestos y si incluye materiales. Ver la
simplificación explícita en `0112` (comentario de cabecera): "Gestión de materiales de terceros"
(el 6º concepto) no se aplica a un adicional manual, porque ese concepto necesita un split
materiales/mano de obra de una partida real para tener sentido — un adicional cotizado con un solo
número no lo tiene. Los otros 5 (GG, Imprevistos, EPP, Costo Financiero, Beneficio) sí se aplican
siempre. **Marcada para confirmar** cuando se pruebe la Tanda 1 — es un cambio de una línea si no
es lo que Seba quiso decir.

**D.** La foto se toma al aprobar (Tanda 2), simétrico al presupuesto — mientras pendiente, el
monto se recalcula en cada edición (implementado vía trigger, `0112`).

**E.** Sin restricción de rol para crear — la política `modificaciones_obra_insert` (0004) ya
alcanza tal cual, no se tocó.

### 11.7 Tanda 1 — hecha, sin aplicar ni verificar todavía

Migración `0112_adicionales_creacion.sql`: columnas nuevas (`costo_costo_base`,
`incluye_materiales`, `incluye_impuestos`) + check por tipo, `calcular_precio_adicional` (la
cascada de 5 conceptos + impuestos condicional) y el trigger que recalcula `monto_total` en vivo
mientras el adicional sigue `pendiente`.

Dart: `AdicionalesRepository` (repositorio propio, no una extensión de
`ModificacionesObraRepository` — confirmado que la autoridad y el shape de datos difieren lo
suficiente); `ModificacionObra` con los 3 campos nuevos; pantalla `AdicionalesScreen` (historial +
crear, con vista previa del monto en el diálogo de creación); botón "Adicionales" en
`gestion_obra_tab.dart`, mismo lugar que "Quitas y Demasías".

**Recorte real encontrado al escribir, no anticipado en el diagnóstico**: "corregir mientras
pendiente" (que sí ofrece el análogo del presupuesto, presentar→actualizar) no es viable con la RLS
actual — `modificaciones_obra_update` (0109) solo deja tocar una fila `pendiente` a quien puede
aprobarla, no a `subido_por` en general (esa rama solo aplica con `estado = 'devuelto'`). Se sacó
del alcance de la Tanda 1 en vez de proponer un cambio de RLS sin que Seba lo pidiera — mismo límite
que ya tiene Quitas/Demasías (sin edición, solo aprobar/rechazar). Si hace falta poder corregir un
adicional antes de que se resuelva, es una decisión para la Tanda 2.

Sin conectar todavía: aprobación (`puede_aprobar_adicional`, Tanda 2), seguimiento de avance
certificado, línea "Total con adicionales" del dashboard (§10.2), etiqueta corta de condiciones
distintas (§10.1) — todo pendiente de la Tanda 2 y de aplicar/verificar la `0112` primero.

## 12. Corrección de alcance (2026-09-13): el adicional es un presupuesto propio, no un número

Seba se corrigió sobre el pedido de §11: un adicional no es un monto que alguien tipea — es **"una
obra dentro de una obra"**, presupuestada con las mismas solapas de cómputo/APU/materiales que una
obra real, a los precios del día en que se pide (no los del contrato) y con Factor K
potencialmente propio. El monto manual de la Tanda 1 (`0112`) **no se descarta** — pasa a ser una
de tres vías de carga, no la única. Diagnóstico técnico, sin código todavía (pedido explícito).

### 12.1 Respuesta directa a la pregunta central

**Sí, conviene que el adicional sea literalmente una fila de `obras`**, con una columna nueva
`obra_madre_id uuid references obras(id)` (nula para toda obra real). Verificado contra el schema
real, no supuesto: `obra_subitems`, `apu_composiciones`... casi todo lo que hace falta (cómputo,
tildado de partidas, precios de insumos, congelamiento) ya cuelga de un `obra_id` genérico — una
obra nueva hereda las 5 solapas relevantes (Rubros, Materiales, Mat y MO, APU, Resumen) gratis, sin
reescribir ninguna. Es la misma lógica que ya usa `presupuesto_config_congelado`/`obra_presupuesto_
config`: si el adicional tiene su PROPIO `obra_id`, automáticamente tiene su PROPIA fila de config
de Factor K — "puede ser propio" sale solo, sin ningún mecanismo nuevo.

**Pero hay un problema real con este camino, y es serio — lo digo antes de que lo descartes vos, no
lo escondo.**

### 12.2 El problema real: `apu_composiciones` es por usuario, no por obra

Verificado en `0018_apu_composiciones.sql`: la tabla es `unique(subitem_id, creador_usuario_id)` —
**una composición propia es global para ese usuario, en TODAS sus obras**, no una por obra. Hoy eso
no importa (nadie edita composición pensando en más de una obra a la vez), pero es exactamente lo
que rompería tu ejemplo: *"en ese adicional sí puedo cambiar las APU... capaz que cambió"* — si el
administrador ajusta su propia composición de Steel Frame PARA el adicional (porque en obra dentro
de obra el adicional es "una obra más" que usa el mismo mecanismo de composición propia), esa
composición corregida pasaría a aplicarse también a CUALQUIER OTRA obra real de ese mismo
administrador que use Steel Frame con su propia receta — silencioso, sin ningún aviso, porque hoy
nada distingue "mi receta para esta obra" de "mi receta en general".

Tres salidas, ninguna gratis, para que elijas antes de seguir:

1. **Alcance por esta pieza: el adicional NO toca `apu_composiciones` propia.** Puede tildar
   partidas con la receta OFICIAL (`creador_usuario_id is null`) tal cual, y ajustar el Factor K
   propio de su `obra_presupuesto_config`/`obra_impuestos` (eso sí es 100% seguro, ya es por obra).
   Si hace falta una composición distinta para un adicional puntual, queda para cuando se resuelva
   el problema de fondo — no se ofrece en la UI del adicional. Es la opción de menor riesgo y menor
   trabajo, a costa de no cubrir el 100% de tu ejemplo ("cambiar la APU") todavía.
2. **Agregar `obra_id` a `apu_composiciones`** (nullable, `null` = sigue siendo la composición
   "general" del usuario, con `obra_id` = específica de esa obra) — resuelve el problema de raíz,
   pero es una migración de schema real sobre una tabla ya poblada, con RLS que hoy no distingue
   por obra en ningún lado (`0018` está armada enteramente alrededor de usuario/oficial) — no es
   una pieza chica, y probablemente convenga como su propia migración, no colgada de Adicionales.
3. **Copiar (no referenciar) la composición propia del usuario hacia una fila nueva, atada al
   `obra_id` del adicional**, en el momento en que decide "quiero cambiar la receta para esto" —
   técnicamente es la Opción 2 sin la columna `obra_id` (usa `apu_composiciones` de una obra que
   NO es la del usuario general), pero necesita que la RLS/lectura de composición sepa buscar
   "la propia de este obra_id" antes que "la propia general" — mismo problema de fondo que la
   Opción 2, con menos alcance.

**Mi recomendación: Opción 1 para arrancar.** Cubre el caso de "precios de hoy" y "Factor K
propio" (que es donde está el 90% del valor real, según tus propios ejemplos: precios cambian
siempre, Factor K a veces, la composición casi nunca) sin tocar una tabla delicada. Si con el uso
real aparece la necesidad de veras de cambiar composición por adicional, ahí se evalúa la Opción 2
como pieza aparte — mismo criterio que ya usó el proyecto para no construir de más "por si acaso".

### 12.3 Membresía — quién puede entrar al cómputo del adicional

`is_obra_member(obra_id)`/`tiene_rol_en_obra` (0004) gobiernan CASI TODA la RLS del proyecto, y
leen `obra_members` filtrando por ese `obra_id` exacto — un `obra_id` nuevo sin sus propias filas
de `obra_members` bloquea todo (nadie puede tildar, tocar precios, ni nada) para cualquiera, incluido
quien lo creó.

Dos caminos, con costos muy distintos:
- **Copiar la membresía de la madre al crear el adicional** (mismos usuarios, mismos roles, una
  sola vez) — barato, contenido, no toca ninguna función usada en todo el resto del proyecto. Costo
  real: si el equipo de la obra madre cambia después, el del adicional no se entera solo — mismo
  tipo de "foto, no en vivo" que ya acepta el resto del congelamiento.
- **Enseñarle a `is_obra_member` a resolver hacia la madre cuando el `obra_id` es un adicional** —
  resuelve el problema de raíz pero toca la función más usada de todo el schema (decenas de
  políticas y funciones `security definer` dependen de ella) — el tipo de cambio de alto riesgo y
  alta superficie que este proyecto viene evitando activamente en toda la sesión.

**Recomiendo copiar membresía al crear**, mismo motivo que la Opción 1 de arriba: menor blast
radius, el costo aceptado (foto, no sincronización viva) ya es un patrón que el proyecto usa en
todos lados.

**Efecto colateral a tener en cuenta, no a resolver ahora**: crear una obra hoy dispara el bootstrap
existente (creador → `admin_maestro`, defaults de `mes_base_cac`, etc. — `0033` y afines). Crear el
adicional por el mismo camino de `insert into obras` hereda esa maquinaria automáticamente; copiar
el resto del equipo de la madre es un paso ADICIONAL después del insert, no un reemplazo de lo que
ya existe.

### 12.4 Qué se comparte y qué no — confirmando tu lectura, con el detalle que falta

Tu lectura (rubros/partidas compartidos, precios del momento, Factor K propio) es correcta y
verificable así:
- **Catálogo de rubros/subítems** (`rubros`, `subitems`) — global, sin `obra_id`, se comparte
  automáticamente con solo usar el mismo catálogo. Nada que construir.
- **Precios de insumos** (`obra_insumo_precios`, por `obra_id`) — un adicional recién creado
  arranca VACÍO en esta tabla, y la cascada de precios ya tiene un tercer nivel de fallback al
  promedio del catálogo global de corralones (`precios`, sin `obra_id` — confirmado en
  `calcular_precio_apu_subitems`, 0059/0090) cuando no hay override cargado. Esto significa que
  "precios de hoy" sale SOLO, sin copiar nada — un adicional sin ningún precio propio ya cotiza al
  promedio de mercado vigente. Si en algún momento se quisiera heredar los precios PUNTUALES que
  la obra madre negoció (no el promedio de mercado), ahí sí hace falta copiar `obra_insumo_precios`
  de la madre al crear — lo dejo como mejora, no como bloqueante.
- **Factor K/impuestos** (`obra_presupuesto_config`/`obra_impuestos`, por `obra_id`) — un `obra_id`
  propio le da al adicional su propia fila desde el arranque. Recomiendo copiar los valores
  vigentes de la madre como default (mismo criterio que ya se cerró para el resto de la pieza:
  "arranca con la config vigente, cambiarla es una opción"), no dejarlos en el default genérico de
  una obra nueva.
- **Composición de APU** — ver §12.2, el problema real, no compartido de forma segura todavía.

### 12.5 Cómo se congela — mejor de lo que parecía

Tu lectura ("se congela al aprobarse, con su propia foto, igual que el presupuesto") no solo sigue
valiendo — **se resuelve casi gratis reusando el mecanismo que ya existe.** Al aprobar el
adicional, llamar literalmente a `congelar_presupuesto_obra(adicional_obra_id)` congela su cómputo
completo (cantidad + precio final de cada partida tildada) con el 100% de la lógica ya escrita y
verificada (`0104`) — nada que reimplementar. El monto final del adicional
(`modificaciones_obra.monto_total`) pasa a ser la suma de `presupuesto_subitems_congelado` de ESE
`obra_id`, en vez de un número tipeado a mano. La foto de Factor K (§10.1, `presupuesto_config_
congelado`) también sale gratis, ya congela los 6% + impuestos vigentes en ese momento — es
literalmente la misma tabla, sin duplicar nada.

### 12.6 Las tres vías, conviviendo sin perder al usuario

- **Monto fijo** (ya construido, Tanda 1/`0112`) — sin cómputo, un número tipeado + la cascada de
  Factor K aplicada. Sigue existiendo tal cual.
- **Presupuestar con la app** — crea el `obra_id` hijo (bootstrap + copia de membresía + defaults
  de Factor K de la madre, §12.3/§12.4), abre las mismas pantallas de Rubros/Materiales/Mat y
  MO/APU pero SIN la solapa Gestión de Obra/certificación (un adicional nunca certifica por su
  cuenta, decisión ya cerrada en §4 — la certificación queda oculta por navegación, no bloqueada a
  nivel de RLS, mismo criterio ya aceptado en otras piezas de este proyecto: "no hay trigger que lo
  impida, la app no ofrece el camino"). Al aprobar, `congelar_presupuesto_obra` (§12.5).
- **Importar de Excel/PDF** — mismo importador de la solapa Cómputo, apuntado al `obra_id` hijo en
  vez de a una obra real. No debería necesitar cambios propios más allá de aceptar ese `obra_id`
  (a confirmar cuando se lea `docs/importador_capa1_diseno_datos.md` con este uso en mente).

El "+" de `AdicionalesScreen` pasa de abrir un solo diálogo a elegir entre las tres — un selector
simple (3 opciones con una línea de qué es cada una), no una pantalla nueva por sí sola.

### 12.7 Chequeo pendiente, no bloqueante

Verificar si algún límite de plan Free/PRO cuenta obras por cantidad — si lo hay, un adicional
"obra dentro de obra" no debería contar contra ese límite (es parte de la obra madre, no una obra
nueva del usuario). No encontré evidencia de que ese límite exista hoy (el botón Free/PRO del
dashboard es cosmético, según memoria de sesión), pero no lo di por descartado sin buscarlo primero
si se llega a construir esto.

### 12.8 Migración escrita — `0113_adicionales_obra_hija.sql`

`obras.obra_madre_id` (FK a sí misma, `on delete cascade`) + `modificaciones_obra.obra_hija_id`
(FK a `obras`, `unique`) + check ajustado (exactamente uno de `costo_costo_base`/`obra_hija_id`) +
`crear_adicional_presupuestado(obra_id, descripcion)`: crea la obra hija, pisa su config/impuestos
default con los valores reales de la madre, copia el equipo activo de la madre, y crea la fila de
`modificaciones_obra` ya vinculada — todo en una transacción. Detalle completo y verificación en el
propio archivo.

**Corrección sobre mi primer borrador, encontrada escribiendo, no antes:** había diseñado la función
para "vincular una obra hija a un adicional YA creado" — chocaba de frente contra el check
constraint (un adicional sin `costo_costo_base` ni `obra_hija_id` todavía no es una fila válida, no
hay ningún `modificacion_id` pendiente al que engancharse). La función arma las dos cosas juntas:
obra hija primero, adicional recién después, ya con el vínculo resuelto.

**Simplificación real que aparece de esto, no anticipada en §11**: la tabla
`modificaciones_obra_config_congelada` que había propuesto en §11.2/§11.4 **deja de hacer falta**.
Para el camino "presupuestado con la app", el propio `congelar_presupuesto_obra` (al aprobar, Tanda
2) ya congela la config de Factor K de la obra hija en SU PROPIA `presupuesto_config_congelado` —
es la misma tabla que ya existe, sin duplicar nada. Para el camino de monto fijo, no hace falta
ninguna foto aparte: sus campos (`costo_costo_base`/`incluye_materiales`/`incluye_impuestos`) dejan
de poder editarse solos en cuanto `estado` deja de ser `pendiente` (RLS ya lo impide). Una tabla
menos que construir.

### 12.9 Lista de archivos — hecha, sin aplicar/verificar todavía

**Supabase, aplicado**: `supabase/migrations/0113_adicionales_obra_hija.sql`, más el fix
`0114_fix_adicional_presupuestado_monto_total.sql` (el insert del adicional no mandaba
`monto_total`, `not null` sin default -- la función fallaba entera).

**Dart, hecho y verificado por Seba en el emulador (2026-09-12)**: crear un adicional
presupuestado lleva a las solapas de la obra hija, y la composición de una partida queda de
solo lectura con el banner. Fix 0114 + log de la RPC en el commit `44525e6`.
- `lib/services/obras_repository.dart` — `obraMadreId` mapeado en `_fromRow`; `getObras()` filtra
  `obra_madre_id is null`; `getObraPorId(obraId)` (traer la obra hija recién creada, sin el filtro
  de arriba); `esObraHija(obraId)` (chequeo liviano, una sola columna).
- `lib/data/models/modificacion_obra.dart` — campo `obraHijaId`.
- `lib/services/adicionales_repository.dart` — `crearAdicionalPresupuestado(obraId, descripcion)`
  (RPC a `crear_adicional_presupuestado` + traer la fila completa).
- `lib/presentation/obra_detalle/screens/adicionales_screen.dart` — el "+" abre
  `_SelectorViaAdicionalDialog` (3 opciones); "Presupuestar con la app" pide solo la descripción,
  llama `crearAdicionalPresupuestado` y navega a `PresupuestosScreen` de la obra hija; "Importar"
  muestra un aviso de "todavía no conectado" (no wireado, ver abajo); un adicional presupuestado
  pendiente queda tappable en el historial para volver a entrar a seguir cargando el cómputo, con
  "$ 0" reemplazado por un texto explícito en vez de mentir por omisión.
- `lib/presentation/obra_detalle/screens/presupuestos_screen.dart` — `_esObraHija` (de
  `obra['obraMadreId']`) esconde la solapa "Gestión de Obra" y su `TabBarView` (`TabController`
  pasa a `length: 5`) -- oculto por navegación, no bloqueado por RLS, mismo criterio ya aceptado en
  otras piezas de este proyecto.
- `lib/presentation/obra_detalle/screens/composicion_apu_screen.dart` — **la mitigación real de
  §12.2**. Autocontenida: llama `ObrasRepository.esObraHija(obraId)` ella misma (no necesita que
  ningún llamador se lo pase), así que los 3 call sites existentes (`SubitemsScreen`,
  `ApuListadoTab`, esta misma pantalla) quedan protegidos sin tocarlos. En una obra hija: sin
  "Agregar"/"Quitar" en materiales y equipos, sin el toque de editar rendimiento/precio por línea
  (ver nota de alcance abajo), sin el botón "Volver a la oficial" del banner de personalización
  (ese botón borra la receta personal del usuario en TODAS sus obras, no solo esta), y un banner
  fijo explicando por qué. El Factor K de la obra hija (Gastos Generales, Beneficio, etc., por
  `BloqueFactorKPartida`) sigue editable sin cambios -- eso sí es seguro, ya es por obra.

  **Nota de alcance, no resuelta del todo a propósito**: el toque de "editar" de cada línea abre un
  único diálogo con rendimiento Y precio juntos (`PanelEditarItemApu`) -- solo el rendimiento clona
  la receta personal (el precio ya vive en `obra_insumo_precios`, seguro por obra). Bloqueé el
  diálogo entero en vez de separar los dos campos, para no dejar el gate a medio verificar tocando
  ese panel sin revisarlo con cuidado. Costo real: en una obra hija tampoco se puede cargar precio
  a mano insumo por insumo desde acá -- no es grave (los precios ya caen solos al promedio de
  corralones, §12.4), pero es una restricción más de la estrictamente necesaria. Separarlo es una
  mejora futura, no bloqueante.
- Importador de Excel/PDF (tercera vía) — sin wirear, deliberadamente. Necesita revisar
  `docs/importador_capa1_diseno_datos.md` con este uso en mente antes de conectarlo.
- Tanda 2 (aprobación) -- diagnóstico en §13, que corrige lo que sigue: `puede_aprobar_adicional` + rama de
  `modificaciones_obra_update` + `aprobar_adicional`, que ahora bifurca por camino -- si
  `obra_hija_id is not null`, llama `congelar_presupuesto_obra(obra_hija_id)` y suma
  `presupuesto_subitems_congelado` de esa obra para `monto_total`; si `costo_costo_base is not
  null`, el monto ya está fijo desde que se cargó (sin tabla de config congelada propia, ver
  §12.8-bis).

### 12.10 Resumen para decidir

**"Obra dentro de obra" es el camino correcto** — reusa cómputo/APU/materiales/congelamiento
enteros, y el costo real (copiar membresía, filtrar el dashboard, no exponer Gestión de Obra) es
manejable y de bajo riesgo. El único punto que necesita tu decisión antes de escribir una sola
migración es **§12.2 — qué hacer con `apu_composiciones` siendo por usuario, no por obra.** Mi
recomendación es la Opción 1 (el adicional no toca composición propia por ahora, solo Factor K
propio + precios de hoy), dejando la Opción 2 (obra_id en apu_composiciones) como pieza aparte si
el uso real la termina pidiendo.

## 13. Tanda 2 — aprobación del adicional: diagnóstico (2026-09-12)

Punto de partida: 0112, 0113 y 0114 aplicadas y verificadas (§12.9). Hoy un adicional queda
`pendiente` para siempre — no hay función ni pantalla para aprobarlo, rechazarlo ni congelarlo.

Alcance de esta sección: aprobar y rechazar. El seguimiento de avance (§4,
`certificar_avance_adicional`) y la línea "Total con adicionales" del dashboard (§10.2) siguen
siendo Tanda 2, pero van después: necesitan adicionales aprobados reales para poder probarse.

Ambigüedades de §13.2 cerradas por Seba el mismo día — ver §13.6. Orden acordado: primero el fix
de seguridad de §13.5 (`0115`), después la migración de adicionales.

### 13.1 Lo que encontré verificando contra el código

**1. El monto cero no es el único agujero: hoy la base ya deja aprobar un adicional con un
`UPDATE` directo, sin pasar por ninguna función.** `modificaciones_obra_update` (0109) manda todo
lo que no es quita/demasía a `puede_aprobar_monto(obra_id, monto_total)`. Tres problemas, no uno:
- admin_maestro y profesional pasan — contradice §7-B (cerrada: solo cliente_principal/apoderado).
- el tope del apoderado se compara contra `monto_total`, que en un adicional presupuestado
  pendiente es 0 (0114) — cualquier apoderado con `puede_aprobar_adicionales` pasa.
- el mismo `UPDATE` puede escribir `monto_total` a mano: el trigger `calcular_monto_total_adicional`
  solo recalcula mientras `estado = 'pendiente'`, así que `set estado = 'aprobado', monto_total = X`
  queda con el X tipeado.
- de yapa, la rama `devuelto` (0004): `with check (... or subido_por = auth.uid())` deja que quien
  subió una fila devuelta la pase a cualquier estado, `aprobado` incluido. Para adicionales hoy no
  se alcanza (nadie devuelve), pero queda cerrado con lo mismo.

La app no hace hoy ningún `UPDATE` sobre adicionales, así que nada de esto se explota desde la
pantalla — pero `aprobar_adicional` sola no alcanza. La rama `adicional` de la política tiene que
cerrarse del todo: ninguna escritura directa sobre una fila de adicional, todas las transiciones
por funciones SECURITY DEFINER con su propio chequeo de autoridad (mismo criterio que certificados,
0010/0011).

**2. `modificaciones_obra_insert` deja insertar un adicional con `obra_hija_id` apuntando a
cualquier obra.** La política no mira esa columna. Un miembro podría crear un adicional "vinculado" a
otra obra suya, real, ya congelada y certificando — y si la aprobación congela la obra hija, estaría
re-congelando esa obra real. Doble cierre: la política de insert exige `obra_hija_id is null` (solo
`crear_adicional_presupuestado`, DEFINER, la setea), y toda función que toque la obra hija valida
`obras.obra_madre_id = modificaciones_obra.obra_id` antes de hacer nada.

**3. `congelar_presupuesto_obra` no se puede llamar desde la aprobación del cliente.** Exige
admin_maestro/profesional de la obra (en la obra hija el cliente tiene cliente_principal, copiado de
la madre, no admin), y que el presupuesto esté presentado y no vencido (la obra hija nunca se
presenta). SECURITY DEFINER no cambia `auth.uid()`: la función de adentro sigue viendo al cliente.

**4. La composición de APU que se congela depende de quién congela.** `calcular_composicion_
detalle_subitem` (0072) usa la receta propia de `auth.uid()` si existe, y si no la oficial. El
bloqueo de §12.2 impide *editar* recetas dentro de la obra hija, pero las recetas personales que el
que cotiza ya tiene de otras obras siguen aplicando cuando él mira la hija. Si congela el cliente, se
congela con las recetas del cliente (casi siempre las oficiales): el monto aprobado no sería el que
cotizó el constructor, sin ningún aviso.

**5. Un aprobador que no es miembro de la obra hija congelaría partidas en cero.** El equipo de la
hija es una foto al crearla (0113). Un cliente o apoderado invitado a la madre después no está en la
hija: `calcular_composicion_detalle_subitem` le devuelve 0 filas, la partida congela en $0 y el tope
se compara contra ese número. El mismo agujero del monto cero, por otro camino.

### 13.2 Ambigüedades — necesito tu respuesta antes de escribir SQL

**A. ¿Quién congela la obra hija, y cuándo? (la importante)**

- **Opción 1 — congela el aprobador, al aprobar** (literal §12.5/§11.6-D). Obliga a extraer el
  snapshot de `congelar_presupuesto_obra` a una función interna sin sus candados (tocar una función
  ya verificada), y arrastra 13.1-4 y 13.1-5: congela con las recetas del cliente, y en cero si no es
  miembro de la hija. Taparlos exige pasarle "de quién es la receta" a toda la cadena de precios
  (`calcular_factor_k_subitem` → `calcular_composicion_detalle_subitem`) — cambio de alto alcance.
- **Opción 2 (recomendada) — congela quien cotiza, al enviar a aprobación; el aprobador aprueba
  ese número.** Paso nuevo "Enviar para aprobación": una función que, con la identidad de quien envía
  (admin_maestro/profesional de la obra hija, los mismos que ya pueden editar su cómputo, 0019),
  llama `presentar_presupuesto_obra` + `congelar_presupuesto_obra` sobre la hija **tal como están
  hoy** — cero cambios en funciones verificadas — y copia la suma congelada a `modificaciones_obra.
  monto_total`. Recetas y precios del que cotizó; el cliente ve y aprueba un número fijo; el tope se
  valida contra ese número. Mientras siga pendiente, quien cotiza puede corregir y reenviar
  (recongela: la hija nunca tiene certificados, así que el candado de recongelamiento no la frena).

  Cómo queda §11.6-D con esto: D se cerró pensando en la config de la **madre** cambiando entre la
  solicitud y la aprobación. En la obra hija ese riesgo no existe (su Factor K es propio, solo lo
  cambia quien cotiza); lo que se mueve es el precio de los insumos, y lo razonable es aprobar el
  precio que se cotizó — igual que el presupuesto principal, que lo congela quien cotiza
  (admin/profesional), no el cliente. Para el monto fijo, D queda tal cual: se recalcula al aprobar.

**B. ¿Refrescar el equipo de la hija al enviar?** Con la Opción 2 el aprobador no necesita ser
miembro de la hija para aprobar (lee `monto_total`, que vive en la madre), pero sí para abrir el
detalle y ver qué está aprobando. Propongo que "enviar" vuelva a copiar el equipo activo de la madre
(el mismo insert `on conflict do nothing` de la 0113): sigue siendo una foto, solo que más reciente.
No saca a nadie.

**C. Obra sin cliente_principal.** Con §7-B, si la obra no tiene cliente_principal ni apoderado
cargado en la app, nadie puede aprobar un adicional: queda pendiente para siempre. ¿Alcanza con eso
(se invita al cliente, o quien hace todo se suma también el rol cliente_principal — autogestión) o
querés una salida, por ejemplo que admin_maestro apruebe solo cuando la obra no tiene ningún
cliente_principal activo? Recomiendo no abrir excepción: §7-B pierde sentido si hay un camino
alternativo.

**Decisiones menores que tomo así, salvo que digas otra cosa:**
- Rechazar: misma autoridad que aprobar, sin tope (decir que no no compromete plata). Un adicional
  presupuestado se puede rechazar aunque todavía no se haya enviado.
- Sin "devolver para corregir" en esta tanda (§11.4 listaba aprobar/rechazar). Con la Opción 2 el
  caso común no lo necesita: quien cotiza reenvía mientras está pendiente.
- Guarda contra "el monto cambió mientras lo miraba": `aprobar_adicional` recibe el monto que vio
  el aprobador y rechaza si no coincide con el que va a quedar (reenvío de la hija, o cambio de
  config de la madre en un monto fijo, en el medio).
- Sin candado de validez al aprobar: la hija se presenta con la validez default (30 días) solo
  porque congelar lo exige; que venza no frena la aprobación. Si querés que un adicional enviado
  venza como el presupuesto, es una línea más.
- Obra hija ya aprobada o rechazada: queda (historial, se borra con la madre), no se reenvía. No hay
  un modo de solo lectura reutilizable en las solapas (buscado) — en vez de inventarlo, un banner:
  "Adicional aprobado por $X — cambios acá no modifican el monto aprobado". Lo financiero ya está
  protegido por el congelamiento.

### 13.3 Qué se escribe (Opción 2, confirmada en §13.6)

**Supabase** (después del fix de §13.5, que va primero y aparte):
- `modificaciones_obra.enviado_a_aprobacion_en timestamptz` — null = en preparación. Lo mira la
  pantalla sin tener que leer la obra hija (que el aprobador puede no ver).
- `puede_aprobar_adicional(obra_id, monto)` — `puede_aprobar_monto` sin admin_maestro/profesional.
- `enviar_adicional_a_aprobacion(modificacion_id)` — valida pendiente + camino obra hija +
  `obra_madre_id`; refresca equipo (B); presentar + congelar la hija; `monto_total` = suma de
  `presupuesto_subitems_congelado` de la hija; `enviado_a_aprobacion_en = now()`; audit_log.
- `aprobar_adicional(modificacion_id, monto_visto, comentario)` — fila `for update`. Monto fijo:
  recalcula `calcular_precio_adicional` (D). Obra hija: exige enviado y vuelve a sumar lo congelado.
  Compara contra `monto_visto`, y recién con el monto real resuelto valida
  `puede_aprobar_adicional(obra_id, monto)`. Aprueba + audit_log, todo en una transacción.
- `rechazar_adicional(modificacion_id, comentario)`.
- `modificaciones_obra_update`: `tipo <> 'adicional'` en las tres ramas. `modificaciones_obra_
  insert`: `obra_hija_id is null and enviado_a_aprobacion_en is null`.

**Dart:**
- `AdicionalesRepository`: `enviarAAprobacion`, `aprobarAdicional`, `rechazarAdicional` (con `_conLog`).
- `ModificacionObra`: `enviadoAAprobacionEn`.
- `UserContext.puedeAprobarAdicional(double monto)` / `puedeRechazarAdicional`, mirroreados contra
  la función SQL (ver §13.4).
- `AdicionalesScreen`: "Enviado para aprobación — $X" vs. "Presupuestándose con la app"; botón
  Enviar/Reenviar para admin_maestro/profesional; Aprobar/Rechazar con el monto a la vista en el
  diálogo, para quien puede.
- `PresupuestosScreen` de una obra hija resuelta: el banner de las decisiones menores.

### 13.4 Divergencia Dart/SQL encontrada de paso

`UserContext._delegacionVigente` devuelve `false` si la delegación no tiene fechas; la base
(`puede_aprobar_monto`, 0004; funciones de certificados, 0011) la trata como permanente, o sea
vigente. Hoy un apoderado con delegación permanente puede marcar un certificado como pagado en la
base, pero la app le esconde el botón. `puedeAprobarAdicional` heredaría lo mismo si reusa ese
helper. Propongo alinear el helper a la base (una línea) — toca también los getters de
certificados, por eso lo marco en vez de hacerlo de pasada.

**Seba (2026-09-12): pendiente aparte, no se toca en esta pieza** — afecta a certificados. Para
no heredarlo, `puedeAprobarAdicional` replica la regla de la base (sin fechas = permanente) en
su propio chequeo, sin pasar por `_delegacionVigente`; cuando se alinee el helper, se unifican.

### 13.5 Regresión de seguridad en la 0110, ajena a adicionales

La 0110 hizo `drop` + `create` de `calcular_factor_k_subitem` para sumarle `p_config_congelada`, y
en el camino se perdieron dos cosas que la 0085 había cerrado:
- el gate de membresía (`autorizado`/`is_obra_member`) en la CTE `config`: un usuario autenticado
  que no es miembro vuelve a poder leer los % de Factor K (GG, beneficio, etc.) de una obra ajena si
  conoce su id — exactamente el caso de la verificación 1 de la 0085;
- el `revoke ... from public, anon`: una función creada de nuevo nace ejecutable por PUBLIC, así que
  anon también puede llamarla.

Fix chico e independiente: `create or replace` con el mismo cuerpo más el gate en las dos ramas de
`config`, y el revoke. Propuesto como migración propia, antes que la de adicionales.

**Escrita como `0115_fix_factor_k_subitem_gate_revoke.sql`, sin aplicar todavía.** Al armarla
apareció una tercera pérdida del mismo `drop` + `create`: el redondeo de salida a 2 decimales de
la 0078 (no es de seguridad; la 0110 decía comportarse "EXACTO igual que hoy" y no era así). Va
en la misma migración. Auditoría pedida por Seba sobre las 69 funciones de `supabase/migrations/`
(simulando create/replace/drop/grant/revoke/alter en orden): ningún otro gate perdido, ninguna
otra SECURITY DEFINER abierta a anon salvo `previsualizar_invitacion` (a propósito, 0096/0101), y
tres SECURITY INVOKER sin `search_path` (`calcular_totales_certificado` y
`calcular_monto_periodo_avance`, perdidos al recrearlas en la 0105; `calcular_monto_total_
adicional`, que nunca lo tuvo) — cerrados en la misma 0115 con `alter function`.

### 13.6 Ambigüedades — cerradas por Seba (2026-09-12)

**A. Opción 2: congela quien cotiza, al enviar para aprobación.** Palabras de Seba: "se usan las
recetas del que cotizó y el cliente aprueba un número fijo. Es como funciona en obra — te mandan
un presupuesto cerrado, no una hoja de cálculo abierta." Para el monto fijo, §11.6-D sigue igual
(se recalcula al aprobar).

**B. Sí: "enviar" vuelve a copiar el equipo activo de la madre a la hija**, para que un cliente
invitado después vea qué está aprobando.

**C. Sin excepción para admin_maestro.** Palabras de Seba: "si no hay cliente en la obra, se lo
invita o alguien se suma ese rol. Abrir una excepción rompería justamente lo que define el
circuito."

**Decisiones menores de §13.2: aceptadas tal como están propuestas.**

