# Libro de Obra — horizonte y diagnóstico

> ## ⚠ CAMBIO DE ALCANCE — 2026-09-14, LEER ANTES QUE NADA
>
> **Queda UN SOLO libro de comunicaciones de obra.** Textual de Seba:
>
> > *"En la realidad la empresa no responde adentro de la orden: contesta con una nota de pedido,
> > que es otro libro. Reproducir eso complica sin aportar, y el respaldo legal sigue siendo el
> > libro rubricado en papel."*
>
> Escriben y se responden el constructor y el profesional; el cliente solo lee. **Eso elimina los
> dos libros direccionales, la numeración correlativa, el acuse de recibo y el plazo para acusar.**
>
> Qué queda válido de lo que sigue: §A (quién escribe y quién lee), §B (lo que tiene la tabla), §D
> decisiones 0, 2 y 3 (el cliente no escribe, el aviso legal, el audio con una línea de texto), y la
> `0134` entera. Quedó sin efecto: §C en su parte de tres solapas y tarjetas de orden+acuse, §D
> decisión 1 (numeración), §D-quater punto 2 y §D-quinquies completo.
>
> Estado del código: `0134` y `0137` aplicadas, **`0138` escrita sin aplicar** — y esa última es
> un arreglo urgente: la `0135` **sí se había aplicado** (yo lo di por sentado al revés), así que
> `mis_pendientes()` quedó con sus dos ramas de libro seleccionando `e.numero`, la columna que la
> `0137` borró. La función **falla entera** hasta aplicar la `0138`, y con ella el cartel de todo
> el dashboard. Antes: `0134` aplicada, `0137` escrita (saca la numeración, deja los
> guards del hilo, suma el interruptor por obra). Las migraciones `0135` y `0136` se borraron sin
> haberse aplicado nunca; sus números quedan vacíos a propósito.
>
> El aviso quedó resuelto en la `0139` (ver §F) y los adjuntos en la tanda 3 (§G).

**Origen: conversación del 2026-09-11 (la visión). Diagnóstico técnico y precisión de alcance:
2026-09-13 — §A en adelante.** Sigue sin haber migración escrita ni pantalla: esto mide y decide,
no construye.

## La visión completa, en palabras de Seba

**"Todo llevar la obra acá"** — el respaldo documental completo de la obra, en un solo lugar
asociado a esa obra. Hoy vive repartido entre un cuaderno físico, WhatsApp y una carpeta de
papeles. Criterio rector: **"siempre simplificar para los profesionales y los constructores, que
no sea tedioso"** — nadie en obra, con el casco puesto, va a tipear un texto largo parado.

Son cuatro piezas, no una:

1. **El Libro de Obra** — notas escritas **y audios**. Poder dictar es clave, no un agregado
   menor: es la forma en la que alguien en obra realmente va a usarlo.
2. **Órdenes de Servicio** — lo que el Profesional le indica al Constructor.
3. **Notas de Pedido** — al revés, lo que el Constructor le pide al Profesional.
4. **Archivo de documentación de la obra** — remitos, facturas, presupuestos de terceros. **No es
   el importador de PDF del roadmap** (ese sube planos para pedir un Servicio Especial, pieza
   totalmente distinta que ya está anotada aparte en `docs/diagnostico_general_producto.md` §5) —
   acá es documentación administrativa de la obra en curso, sin relación con pedir un servicio.

Ningún competidor tiene esto en un solo lugar asociado a la obra — es una ventaja real, no una
pieza cosmética.

## Qué ya existe (auditado contra el código, ver `docs/gestion_obra_estado_real_auditoria.md` §5-bis)

- Tabla `libro_entradas` aplicada, con su discriminador (`obra`/`orden_servicio`/`nota_pedido`).
- La matriz de quién genera y quién responde, por libro, aplicada en RLS.
- Append-only (sin `UPDATE`/`DELETE`) — coherente con ser un respaldo, no un documento editable.
- Modelo Dart (`libro_entrada.dart`) ya existe.

**Falta el repositorio y la pantalla — ninguna de las 4 piezas tiene un solo punto de entrada
desde la app hoy.**

## Tres decisiones pendientes, para cuando se retome — necesitan a Seba, no se resuelven solas

**1 · Numeración y secuencia.** En obra real, las Órdenes de Servicio van numeradas y
correlativas, y normalmente la anterior se responde (acuse de recibo) antes de poder emitir la
siguiente — la misma lógica de secuencia que ya tiene `certificados.numero`. Hoy `libro_entradas`
no tiene ningún concepto de esto. Falta decidir si se quiere esa formalidad o si el diseño actual
(sin número, sin candado de secuencia) alcanza.

**2 · El aviso legal.** El libro rubricado en papel es el que tiene validez legal ante el colegio
profesional o el municipio — esto es un respaldo interno, y conviene que la app lo diga
explícitamente para no generar una falsa sensación de validez legal equivalente. La intención ya
estaba anotada en el diseño de Etapa 3 (citada ahí como "§F", una sección que en los hechos nunca
se escribió en ningún documento) pero el texto exacto del aviso nunca se redactó.

**3 · Los audios — cero definición en todo el proyecto hasta esta conversación.**

Lectura de Claude Code, para cuando se decida, no una definición cerrada: **guardar el audio
siempre, y transcribirlo si se puede** — el audio es la prueba (lo que realmente se dijo, con
fecha y quién lo dijo), el texto transcripto sirve para buscar y leer rápido sin tener que
escuchar cada nota. Transcribir necesita un servicio externo con costo por minuto/uso — se puede
arrancar guardando solo el audio (ya funciona la infraestructura real de subida de archivos,
Supabase Storage, probada en el importador de Excel/PDF) y sumar la transcripción como mejora
posterior, sin que eso bloquee la primera versión.

---

# §A · Precisión de alcance (Seba, 2026-09-13)

**Son dos libros, y la comunicación es entre el constructor y el profesional. El cliente solo lee,
no escribe.** Textual:

> *"Entre ellos dos sí pueden ir comunicándose las cosas de obra, lo diario — que el arquitecto le
> diga 'ya podés arrancar tal tarea' o 'suspendé tal tarea', y el constructor ahí el porqué. Que
> quede registrado como respaldo."*

Los dos libros son los **direccionales**: Órdenes de Servicio (profesional → constructor) y Notas de
Pedido (constructor → profesional). Es exactamente la matriz que la RLS ya aplica.

**El motivo de fondo es legal, y ordena el resto de las decisiones:** la app **no reemplaza al libro
rubricado** (eso ya estaba claro y anotado), pero **sí sirve como respaldo** si algo termina en una
discusión formal. De ahí se siguen dos cosas que ya estaban en el diseño y ahora tienen razón
explícita: las entradas **no se editan ni se borran**, y **queda registrado quién escribió qué y
cuándo**.

# §B · Qué tiene hoy la tabla, exactamente

`libro_entradas` (`0003`, RLS en `0004`):

| Columna | Para qué sirve en esta pieza |
| --- | --- |
| `libro` | `'obra'` / `'orden_servicio'` / `'nota_pedido'` — los tres libros ya discriminados |
| `autor_usuario_id` + `autor_rol` | **quién escribió, y con qué rol** — el "quién" del respaldo legal |
| `contenido` | el texto de la entrada |
| `adjuntos jsonb` | **ya alcanza para los audios y los archivos, sin tocar el schema** |
| `entrada_padre_id` (FK a sí misma) | **la respuesta/acuse ya está modelada**: una entrada raíz y sus hijas |
| `created_at` | el "cuándo", puesto por la base (`default now()`), no por el cliente |

**Hallazgo que cambia el tamaño de la pieza para bien: el hilo ya existe.** `entrada_padre_id` es
justamente lo que diferencia una Orden de Servicio con su acuse de un chat plano — no hay que
agregarlo.

**La RLS aplicada ya tiene la matriz de escritura por libro**: una Orden de Servicio la abre solo el
`profesional` y la responde solo el `constructor`; una Nota de Pedido al revés. `invitado_veedor` no
aparece en ninguna rama, así que no escribe. Sin `UPDATE` ni `DELETE` para nadie: append-only real, en
la base, no por convención de la UI.

**Lo que falta para que los dos libros funcionen:**

1. **Repositorio** (no existe): insertar una entrada, listar por libro, y traer un hilo con sus
   respuestas. Es el trabajo más mecánico de la pieza.
2. **Pantalla** (no existe): ver §C.
3. **Punto de entrada**: dos acciones en la barra de Gestión de Obra. Esa barra se rehízo el
   2026-09-13 como grilla justamente para que estas dos entren sin rediseñarla
   (`BarraAccionesObra`).
4. **Storage para audios/adjuntos** si se hacen: el mecanismo ya está probado (Supabase Storage, el
   importador de Excel/PDF lo usa), falta el bucket y su política.
5. Lo que salga de las decisiones de §D (numeración, aviso legal, audios).

**Conflicto real que hay que resolver antes de escribir la pantalla — la RLS aplicada NO coincide con
"el cliente solo lee"**: hoy el `cliente_principal` (y el `invitado_apoderado`) **pueden escribir en el
Libro de Obra** (`libro = 'obra'`) y el `cliente_principal` **puede responder una Nota de Pedido**. Las
dos ramas están aplicadas en producción desde la `0004`. Alinear la base con la precisión de §A es una
migración de una policy (drop + create), sin datos que migrar — no hay ninguna entrada cargada
todavía. Ver la decisión 0 de §D.

# §C · Cómo se ve: un chat, con una diferencia

Es una conversación entre dos partes, así que la forma es de chat y no de formulario: **burbujas**
alineadas por autor (el profesional de un lado, el constructor del otro), con **nombre, rol, fecha y
hora** visibles en cada una — el "quién y cuándo" es el valor de la pieza, no un detalle que se
esconde en un tooltip. Agrupadas por día, orden cronológico, el último abajo, y el scroll arranca al
final. Sin editar ni borrar: el menú de una burbuja no tiene esas opciones, porque la base tampoco.

**La diferencia con un chat común son los libros direccionales.** En Órdenes de Servicio y Notas de
Pedido, cada **hilo es una orden y su acuse**, no dos mensajes sueltos: la entrada raíz se ve como una
tarjeta con su estado ("sin acuse" / "acusada el 12/09 por Fulano") y la respuesta anidada abajo. Así
se lee en una discusión formal, que es para lo que existe. El Libro de Obra (`'obra'`) sí es el diario
plano: entradas sueltas, sin hilo obligatorio.

**Tres pantallas o una con selector**: recomiendo **una pantalla con tres solapas** (Libro de Obra /
Órdenes de Servicio / Notas de Pedido) y dos entradas desde la barra de acciones (Órdenes y Notas),
porque son dos flujos distintos que la gente busca por nombre; el diario queda como tercera solapa.

**El cliente**: ve los tres libros completos y **sin campo de escritura** (según la decisión 0). No es
un modo "deshabilitado" con el campo en gris: directamente no está.

**El compositor, pensado para obra**: el micrófono primero y el teclado después — *"nadie en obra, con
el casco puesto, va a tipear un texto largo parado"*. Adjuntar archivo al lado.

**Pendientes**: una Orden de Servicio sin acuse es un candidato natural a `mis_pendientes()` (una rama
más, el mecanismo ya está). No entra en la primera tanda, pero el diseño no lo estorba.

# §D · Las decisiones — **las 4 CERRADAS por Seba el 2026-09-13**

**Resumen de lo decidido, para no leer las opciones de abajo:**

1. **El cliente no escribe en ningún libro** — hay que alinear la RLS (migración de policy).
2. **Órdenes de Servicio numeradas y correlativas, sin candado de secuencia.**
3. **Aviso legal, redacción directa**: *"Este registro es un respaldo interno de la obra. No reemplaza
   al Libro de Obra rubricado ante el colegio profesional o el municipio, que es el que tiene validez
   legal."*
4. **Audio + una línea de texto** que escribe el autor. Transcripción automática, después, como PRO.

Las opciones que se descartaron quedan abajo con su fundamento, para no reabrirlas.

### 0 · ¿El cliente escribe en algún libro? — **CERRADA: A, no escribe en ninguno**

- **A — No escribe en ninguno** (fiel a lo textual de §A): se saca `cliente_principal` e
  `invitado_apoderado` de la rama `'obra'` y `cliente_principal` de la respuesta a Notas de Pedido.
  Una migración de policy. **Recomendada**: es lo que Seba dijo, y deja la app coherente con el
  criterio de que el respaldo documenta la comunicación técnica.
- **B — No escribe en los dos direccionales, pero sí comenta en el Libro de Obra**: la comunicación
  formal queda entre las partes técnicas y el cliente puede dejar constancia de algo que vio.
- **C — Como está hoy** (escribe en el Libro de Obra y responde Notas de Pedido): cero trabajo, pero
  contradice §A.

### 1 · Numeración y secuencia — **CERRADA: B, número correlativo sin candado**

- **A — Sin número** (como hoy): cero trabajo. En obra real las órdenes se citan por número ("la OS
  N° 7"), así que probablemente falte.
- **B — Número correlativo por obra y por libro, sin candado** (`numero` + `unique(obra_id, libro,
  numero)`, asignado al insertar, mismo criterio que `certificados.numero`): se puede emitir la 8
  aunque la 7 no tenga acuse, y la que no tiene acuse se marca en pantalla y puede avisar por
  pendientes. **Recomendada.**
- **C — Número + candado de secuencia**: no se emite la siguiente hasta que la anterior esté acusada.
  **Ojo con el precedente**: este proyecto ya construyó un candado así (el bloqueo de emisión hasta
  subir el PDF firmado) y **lo sacó a propósito** en la `0055` porque bloqueaba de más; se reemplazó
  por un aviso no bloqueante (`docs/certificados_ciclo_vida_diseno_datos.md` §11). Repetirlo acá es
  repetir un error ya medido.

### 2 · El texto del aviso legal — **CERRADA: A, la redacción directa**

Tres redacciones posibles (la decisión es el tono, no el contenido):

- **A — Directa**: *"Este registro es un respaldo interno de la obra. No reemplaza al Libro de Obra
  rubricado ante el colegio profesional o el municipio, que es el que tiene validez legal."*
  **Recomendada**: dice las dos cosas (sirve como respaldo / no reemplaza al rubricado) sin
  asustar.
- **B — Corta**: *"Respaldo interno. No reemplaza al Libro de Obra rubricado."*
- **C — Formal**: *"Las entradas de este libro se registran con autor, rol y fecha, y no pueden
  editarse ni eliminarse. Constituyen un respaldo documental interno y no sustituyen al Libro de Obra
  rubricado exigido por el colegio profesional o la autoridad municipal."*

**Dónde**: descartable la primera vez, con el ícono para volver a verlo — el mecanismo ya se usa tres
veces en la app (cartel UOCRA, aviso de desfasaje, aviso de presupuesto congelado) — **y fijo al pie
de cualquier exportación a PDF**, cuando exista. Un cartel permanente en pantalla se vuelve
invisible en dos días.

### 3 · Los audios — **CERRADA: C, audio + una línea de texto; transcripción como PRO después**

- **A — Solo audio, sin texto**: lo más rápido de construir (Storage ya probado). Contra: no se puede
  buscar nada, y con cincuenta notas el libro se vuelve inútil como respaldo — hay que escuchar una
  por una para encontrar algo.
- **B — Audio + transcripción automática**: la mejor experiencia y el mejor respaldo (se busca por
  palabra), pero suma un servicio externo con costo por minuto y una dependencia nueva. Encaja como
  función PRO.
- **C — Audio + una línea de texto opcional que escribe el autor** ("suspensión de hormigonado"):
  costo cero, búsqueda razonable, y el que graba decide cuánto escribir. **Recomendada para la
  primera versión**, con **B como mejora PRO después** — y sin retrabajo: la línea de texto va en
  `contenido`, que ya existe y ya es `not null`.

En los tres casos: el audio se guarda **siempre** (es la prueba de lo que realmente se dijo), y el
texto es para leer y buscar. Faltaría definir tope de duración y formato al construirlo, no ahora.

# §D-bis · Tanda 0 escrita — migración `0134` (2026-09-14, sin aplicar)

Las tres cosas que eran schema/RLS, en un archivo, antes del repositorio y la pantalla:

1. **`libro_entradas_insert` recreada sin el cliente** (decisión 0). Se sacan `cliente_principal` e
   `invitado_apoderado` del diario y `cliente_principal` de la respuesta a Notas de Pedido.
   `admin_maestro` **sigue** escribiendo en el diario: la decisión saca al que paga, no al
   administrador de la obra. Sin datos que migrar — la tabla está vacía, era la última oportunidad
   de cambiar la matriz gratis.
2. **`numero`** + índice único parcial + trigger (decisión 1). **Null en las hijas: un acuse no
   consume número**, es parte de la orden. Sin candado de secuencia, por el precedente de la `0055`.
3. **El bucket `libro-obra`** con sus dos policies (decisión 3), con la convención de path
   `{obra_id}/{uuid}-{nombre}` calcada de `importaciones` (0080), que es de lo que depende su RLS.
   Va ahora aunque los audios sean la tanda 3: es infraestructura sin riesgo, y evita pedir otra
   migración a mitad del Dart.

**De paso, dos agujeros del hilo que la `0003` dejó abiertos** y que el mismo trigger cierra gratis:
una respuesta podía colgar de una entrada de **otra obra u otro libro**, y se podía **responder una
respuesta** (hilos de profundidad arbitraria, que romperían la lectura de "una orden y su acuse").
Ninguna de las dos se puede expresar como check constraint, porque miran otra fila.

**Hallazgo del lado del Dart, para la tanda 1:** `LibroEntrada` existe pero **su `fromMap` no lee
filas de Supabase** — usa claves camelCase (`obraId`, `autorUsuarioId`, `fechaCreacion`) y
`TipoLibro.name` da `ordenServicio`, no `orden_servicio`. Se escribió antes de que hubiera
repositorio, contra un mapa propio. Hay que agregarle un `desdeRow` con los nombres reales de las
columnas, no reusar el que está.

# §D-ter · Tanda 1 escrita — repositorio y pantalla (2026-09-14)

Los dos libros direccionales, solo texto. `flutter analyze` sin errores ni warnings nuevos, sin
verificar en el emulador.

**Archivos:** `LibroEntrada` reescrito (`desdeRow` real, `numero`, `TipoLibro.columna`, y `HiloLibro`
= raíz + acuses), `LibroRepository` nuevo, `LibroObraScreen` nueva con dos solapas,
`CartelAvisoLegalLibro` nuevo, cinco getters + `rolParaEscribir` en `UserContext`, y las dos
`AccionObra` en `GestionObraTab`.

**Tres cosas que se decidieron al escribir:**

- **El repositorio no tiene guards de autoridad.** Quién abre, quién acusa y quién no escribe lo
  decide la policy de INSERT, del lado del servidor. `UserContext` responde lo mismo **solo** para
  decidir si se dibuja el compositor; si divergieran, manda la base y lo peor que pasa es un campo
  de texto que al enviar falla con el mensaje de Postgres.
- **Sin `update` ni `delete` en el repositorio**, porque la tabla no tiene esas políticas. Un
  método de edición ahí sería una mentira que falla siempre.
- **Las dos entradas de la barra son visibles para cualquier miembro**, incluido el cliente: leer es
  lo único que hace acá, y esconderle la entrada se lo sacaría.

**Un choque de nombres que apareció y conviene conocer:** ya existía un `rolDesdeColumna` en
`invitacion.dart`, pero es el subconjunto **invitable** — mapea `admin_maestro` a veedor a
propósito, porque no es un rol que se invite. Para `autor_rol` hace falta el mapeo completo (el
administrador **sí** escribe el diario), así que el par nuevo se llama `rolProyectoDesdeColumna` /
`rolProyectoAColumna` y vive en `obra_member.dart`, con `ObraMembersRepository` usando ese en vez de
su copia privada. Son dos funciones parecidas con semánticas distintas, no una duplicación.

# §D-quater · Lo que salió de probar la tanda 1 (Seba, 2026-09-14)

**1. Un solo ícono, no dos** (`0135` del lado del Dart). La pantalla ya tiene las dos solapas
adentro, así que la segunda entrada solo repetía la puerta -- y esta barra va a sumar por lo menos
dos íconos más (ver el punto 4).

**2. Los libros avisan** (`0135`). *"Escribí una orden con slosav y a seba2135 no le apareció nada
-- sin aviso, el libro es un papel en un cajón."* Dos ramas nuevas en `mis_pendientes()`:
`orden_sin_acuse` al constructor y `nota_sin_respuesta` al profesional, cada una al mismo conjunto
que la policy de INSERT deja responder, y **nunca al que escribió**. Era el agujero que §C ya había
anotado ("candidato natural a mis_pendientes()") y que se dejó para después: la primera prueba con
dos personas lo encontró de una.

**3. Los libros se prenden y se apagan por obra** (`0135`, `obras.libros_habilitados`). Apagar saca
la puerta y los avisos, **no lo ya escrito**: un respaldo legal no se hace desaparecer con un switch
de configuración.

**4. El compositor reserva el lugar del audio y la foto**, deshabilitados, antes del campo de texto
(micófono primero, teclado después). Y **la barra de Gestión de Obra va a sumar dos íconos más**,
anotados acá para que el próximo rediseño los contemple: **avance fotográfico** y **archivo de
documentación** (recibos, facturas, contratos) -- los dos circuitos que
`docs/documentacion_obra_tres_circuitos.md` ya tenía relevados. Con esos dos, la barra pasa de 5 a 7
íconos: la grilla los aguanta, pero conviene decidir el orden antes de agregarlos de a uno.

**5. Falta el plazo para acusar** (decisión abierta, ver §D-quinquies).

# §D-quinquies · El plazo para acusar — SIN EFECTO (cambio de alcance 2026-09-14)

> No hay acuse, así que no hay plazo que correr. Textual: *"un libro de comunicaciones es una
> conversación, no un trámite. Si algo tiene que responderse sí o sí, para eso está el libro
> rubricado en papel"*. La `0136` se borró sin aplicarse. Se conserva abajo el análisis de días
> hábiles, que sirve el día que haga falta un plazo en cualquier otra pieza.

Pedido de Seba: *"un plazo para acusar de los dos lados, con el mismo criterio que la objeción --
avisa cuando se acerca y queda registrado el silencio"*.

**La forma está probada y se calca de la `0131`**: se calcula al leer, se materializa al tocar, y el
silencio queda asentado con una marca propia que **no se puede confundir con un acuse**. Ahí el
equivalente de `aclarada` vs `vencida` es **acusada** vs **vencida sin acuse**, y la constancia es la
misma: sin firmante no hubo acto.

**Diferencia importante con la objeción, y es la que decide el número:** el vencimiento de una
objeción **destraba un pago**. Acá no destraba nada -- una orden que vence sin acuse **sigue sin
acuse**; lo único que cambia es que queda registrado que pasó el plazo y nadie contestó. Por eso el
plazo puede ser corto sin riesgo: no le saca un derecho a nadie.

**Propuesta: 48 horas hábiles, con aviso a las 24.** El fundamento:

- una Orden de Servicio en obra es **operativa** ("suspendé el hormigonado", "arrancá con la
  losa"): si el otro no la vio en dos días, el problema ya ocurrió. Cinco días, como la objeción,
  llegan tarde para lo que esto sirve;
- **hábiles y no corridos**, al revés que la objeción, y por una razón concreta: una orden escrita
  un viernes a la tarde vencería el domingo, cuando la obra está parada. El plazo de la objeción
  podía ser corrido porque eran cinco días y el fin de semana se diluía; en dos días, el fin de
  semana **es** el plazo. Esto sí necesita el calendario de feriados que la objeción evitó — o,
  como mínimo, saltear sábados y domingos, que es el 90% del problema y no necesita calendario;
- **el mismo número para los dos libros**: una Nota de Pedido sin responder frena al constructor
  igual que una Orden sin acusar frena al profesional. Dos plazos distintos serían dos reglas para
  explicar sin ninguna ventaja.

**Cerrado por Seba el 2026-09-14, tal cual la propuesta:** 48 h hábiles, aviso a las 24, y el
vencimiento **no genera pendiente nuevo** — solo la marca en la tarjeta.

**Y al escribirlo apareció algo mejor de lo previsto: no hace falta escribir nada.** La `0131` tuvo
que materializar `vencida` porque `objecion_estado` gateaba el cobro y alguien tenía que poder leer
ese estado. Acá los dos hechos que forman el vencimiento **ya están en la tabla** (la entrada con su
`created_at`, y si tiene hija o no), así que el silencio no hay que registrarlo aparte: **es** lo que
la tabla ya dice. Y hay una razón más fuerte que la economía de código — `libro_entradas` no tiene
política de UPDATE para nadie, append-only real, y eso es lo que la vuelve un respaldo. Agregarle la
primera escritura automática para anotar algo deducible habría sido un mal negocio.

Entonces la `0136` es solo lectura: `habiles_despues` (que cuenta **en hora de Argentina**, porque el
servidor está en UTC y un viernes 22:00 de Buenos Aires ya es sábado allá), los dos plazos como
funciones, `libro_estado_acuses` para la pantalla, y `vence` en las dos ramas de `mis_pendientes()`.

**Límite conocido y aceptado:** se saltean sábados y domingos, **no los feriados**. Es el 90% del
problema sin un calendario que hay que mantener año a año, y como el vencimiento no dispara nada más
que una marca, el costo de esa imprecisión es cero.

# §E · Tamaño y orden sugerido

| Tanda | Qué | Tamaño |
| --- | --- | --- |
| **1** | Repositorio + pantalla de los dos libros direccionales, solo texto, con el aviso legal y el "quién y cuándo" | Media |
| **2** | El Libro de Obra (diario plano) en la tercera solapa | Chica |
| **3** | Audios (según la decisión 3) + adjuntos | Media |
| **4** | Numeración/acuse (según la decisión 1) y, si se quiere, la rama de pendientes | Chica |

**Con las 4 decisiones cerradas, la tanda 0 es una migración sola** y va antes que todo lo demás: la
policy de INSERT recreada sin el cliente (decisión 0) **y** la columna `numero` con su `unique(obra_id,
libro, numero)` (decisión 1) — las dos son schema/RLS, entran juntas en un archivo, y conviene que la
pantalla nazca contra la matriz definitiva en vez de adaptarse después. La pieza 4 de la visión original (archivo de documentación
administrativa) queda afuera de este orden: es un gestor de archivos, no una conversación.

## Fuera de esto, sin tocar

El importador de PDF/foto con IA del roadmap (`docs/diagnostico_general_producto.md` §5) es una
pieza completamente aparte — comparten la palabra "documentación" pero no el propósito. No
confundirlos al retomar ninguno de los dos.

---

# §F · El aviso — lo que el cambio de alcance reabre (abierto, 2026-09-14)

**El acuse de recibo no era solo burocracia: era lo que hacía posible avisar.** Daba un estado
binario y objetivo -- la entrada tiene hija o no la tiene -- sin necesidad de rastrear quién leyó
qué. Con una conversación plana eso ya no se deduce de la tabla, y sin aviso vuelve intacto el
problema que Seba encontró probando la tanda 1: *"escribí una orden con slosav y a seba2135 no le
apareció nada -- sin aviso, el libro es un papel en un cajón"*.

Tres formas, de más a menos trabajo:

1. **Última lectura por usuario y obra** (recomendada): una tabla chica
   (`obra_id`, `usuario_id`, `ultima_lectura`) que se actualiza al abrir el libro, y un pendiente que
   diga "3 mensajes nuevos". **No toca `libro_entradas`**: es estado de interfaz, no respaldo, así
   que puede tener UPDATE sin comprometer el append-only de la tabla legal.
2. **Sin estado**: avisar mientras el último mensaje no sea tuyo. Cero infraestructura, pero el
   aviso no se apaga leyendo -- solo escribiendo, lo cual empuja a contestar cualquier cosa.
3. **Sin aviso**: el libro vuelve a ser el papel en el cajón.

**CERRADO por Seba el 2026-09-14: opción 1, y el aviso va también al cliente.** Las dos razones,
textuales: *"el libro es para leer; si hay que tocar algo para que se apague el aviso, aparece un
paso que nadie entiende y que se olvida siempre"* y *"leer es todo lo que puede hacer ahí: si no se
entera de que hay algo nuevo, para él el libro no existe"*. Lo segundo corrige mi recomendación
(yo lo dejaba afuera del cartel porque "leer no es una acción requerida"); el argumento es mejor:
para quien solo lee, enterarse **es** la acción. El texto del aviso quedó neutro y sirve para los
dos.

Escrito en la **`0139`**: tabla `libro_lecturas`, función `marcar_libro_leido(obra, hasta)` y la rama
`libro_mensajes_nuevos`. Dos detalles que no son obvios:

- **`hasta` y no `now()`**: la pantalla primero trae las entradas y después marca. Con `now()`, un
  mensaje que entra en ese intervalo quedaría leído sin haberse mostrado nunca.
- **Nunca retrocede** (`greatest`): marcar hacia atrás desde otro dispositivo haría reaparecer
  avisos ya leídos.

---

# §G · Tanda 3 · Foto y nota de voz (2026-09-14, escrita)

El compositor deja **sacar una foto, elegirla de la galería y grabar una nota de voz**. Van adentro
de la entrada (`adjuntos jsonb`), como parte del mensaje: no hay galería aparte. El bucket y sus
policies ya estaban desde la `0134`, así que **no hizo falta ninguna migración**.

**Los primeros plugins nativos del proyecto**, y eso trajo trabajo que no es Dart: `RECORD_AUDIO` en
el manifest de Android, los tres `NS...UsageDescription` en el `Info.plist` de iOS, y `minSdk`
subido a 23 (`maxOf(flutter.minSdkVersion, 23)`, que es el piso que pide `record`).

**No se declara `CAMERA` a propósito**: `image_picker` abre la app de cámara del sistema, y declarar
el permiso lo volvería obligatorio para instalar sin necesitarlo.

**Trampa de versiones, anotada porque cuesta media hora descubrirla:** `record: ^5.1.2` **rompe el
build** -- su paquete federado `record_linux 0.7.2` no implementa el `record_platform_interface 1.6.0`
que resuelve el pub, y el error aparece recién al compilar el kernel de Dart, **no en
`flutter analyze`**. Con `record: ^7.1.1` compila. Verificado de verdad: `flutter build bundle` y
`flutter build apk --debug` terminan OK.

Tres decisiones del compositor:

- **Los adjuntos se suben ANTES de crear la entrada.** Si algo falla no queda una entrada publicada
  prometiendo una foto que no está -- y al revés no se arregla, porque la tabla es append-only.
- **Se cancelan sin dejar basura**: viven en memoria hasta "Registrar". Un archivo huérfano en
  Storage no lo borra nadie nunca.
- **Las fotos se achican a 1600px y 70%**: una foto de teléfono actual pesa entre 5 y 10 MB y en obra
  se sube con datos móviles; así queda en el orden de los 300 KB, que para mirar un detalle alcanza.

El texto **sigue siendo obligatorio aunque haya audio** (decisión 3): el audio es la prueba de lo que
se dijo, y la línea de texto es para poder leer y buscar sin escuchar cincuenta grabaciones.

---

# §H · Dónde avisa el libro — corregido el 2026-09-14 (migración `0140`)

Probado con los tres usuarios, el aviso de la `0139` **funcionaba, y por eso se vio el problema**:
cada mensaje del libro generaba un aviso en la pantalla principal, y eso termina siendo ruido.

**La regla que fija Seba, y que vale para toda la app de acá en adelante:**

> *"La pantalla principal es para lo que requiere acción, no para conversaciones. Un certificado
> esperando, un adicional para aprobar, una objeción — eso sí. Un mensaje en el libro, no."*

No es una preferencia de esta pieza: un cartel de "acciones requeridas" que se llena de cosas que no
son acciones deja de mirarse, y el día que aparezca un certificado de verdad va a estar enterrado
entre diez mensajes de obra. **Cuando lleguen las notificaciones al teléfono, el mismo criterio**:
certificados y adicionales sí, el libro no salvo que lo prendan. Anotado también en
[[notificaciones-push-relevamiento]].

## Cómo quedó, después de dos vueltas (`0140` y `0141`)

La `0140` leyó la regla a medias: puso el aviso adentro de la obra **y** dejó un interruptor para
devolverlo al dashboard. Probado, Seba lo corrigió: *"los mensajes del libro nunca van a la pantalla
principal, ni prendida ni apagada"*. No es una preferencia de cada uno — es que una conversación no
requiere acción, nunca.

Entonces, en la `0141`:

- **Un globito con el número al lado del ícono del libro**, en la barra de Gestión de Obra, como el
  de WhatsApp. Con eso alcanza: se entra a la obra y se ve que hay tres sin leer. El número sale de
  `libro_novedades`.
- **Nada del libro en `mis_pendientes()`.** La rama se fue y **no se vuelve a agregar**: si algún
  día el libro tiene que avisar fuera de la obra, el lugar es una notificación al teléfono.
- **Sin cartel además del globito** dentro de la misma pantalla: decían lo mismo dos veces, que es
  el ruido que este ajuste vino a sacar. El "de quién" se ve entrando — `libro_novedades` igual lo
  devuelve, listo para el día que se quiera mostrar.
- **La campana se sacó.** Iba a cambiar de significado ("avisarme al teléfono") y quedar apagada
  hasta que exista el push; se eliminó en cambio, porque este proyecto ya tiene un control que
  promete y no cumple — el botón Free/PRO del dashboard — y está anotado como problema, no como
  gracia. **Cuando exista el push, la preferencia es por persona y por obra, apagada por defecto**:
  eso es lo que hay que releer acá ese día, y volver a crear la columna es una línea.

## Por qué el interruptor no es un capricho

Seba lo explicó y conviene que quede escrito, porque explica **qué NO va a intentar resolver la app**:

> *"En la realidad este circuito hoy vive en un grupo de WhatsApp con los tres, y siempre termina
> igual — se arman grupos separados, el constructor con el profesional por un lado y el profesional
> con el cliente por otro, para que no se entere uno u otro de ciertas cosas. Eso va a pasar igual y
> no es un problema a resolver: la app da la herramienta, y el que la quiere usar la usa."*

O sea: **no** hay que diseñar contra eso, ni intentar forzar que toda la comunicación pase por la
app. El interruptor es la expresión de ese criterio — cada uno decide cuánto quiere que este libro le
invada la pantalla.

# §I · Pieza futura · Un canal para las preguntas del cliente

**El libro queda como está: escriben las dos partes técnicas, el cliente lee.** Lo que se anota
aparte es un **canal propio para las preguntas del cliente**, para que no se mezclen con las
decisiones de obra.

El motivo es el mismo que ordenó todo el alcance: el libro documenta la comunicación **técnica**, y
meter ahí "¿cuándo terminan el baño?" cambia lo que el documento prueba. Un canal aparte deja las dos
cosas donde corresponden y no le saca al cliente la posibilidad de preguntar.

Sin diseñar. Cuando se retome, lo primero a decidir es si es otro valor de `libro_entradas.libro`
(barato, misma tabla, misma RLS con otra rama) o algo separado — y ahí pesa que **no es un
respaldo legal**, así que probablemente no necesite ser append-only ni cargar `autor_rol`.
