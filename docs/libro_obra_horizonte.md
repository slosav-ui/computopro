# Libro de Obra — horizonte y diagnóstico

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
