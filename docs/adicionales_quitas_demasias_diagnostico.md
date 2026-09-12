# Adicionales, Quitas y Demasías — diagnóstico

Verificado contra el código real (`supabase/migrations/`, `lib/`), no contra lo que dice `CLAUDE.md`
donde diverge — encontré una divergencia real, ver §3.

**Estado: las 3 ambigüedades de §7 quedaron cerradas con el usuario. La migración
`0109_quitas_demasias.sql` quedó escrita — sin aplicar ni verificar en Supabase todavía.**
Adicionales queda pospuesto a propósito (§8, confirmado): pieza aparte, después.

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
