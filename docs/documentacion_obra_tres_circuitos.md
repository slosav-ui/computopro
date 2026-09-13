# La documentación de la obra — tres circuitos distintos

**Material que Seba trabajó en la etapa con Gemini y nunca quedó escrito en el repositorio.** Salió
en la conversación del 2026-09-13. **Esto documenta, no diseña**: no hay diseño de datos, ni
migración, ni orden de ejecución decidido. Tercera vez que pasa lo mismo (antes: el split de Factor K
y la spec de roles), así que se escribe antes de decidir cualquier cosa.

Es lo que completa Gestión de Obra como **respaldo documental**. Criterio rector, palabras de Seba:
**"todo llevar la obra acá"**, con **"siempre simplificar para los profesionales y los constructores,
que no sea tedioso"** — nadie en obra, con el casco puesto, va a llenar un formulario largo parado.

**Son tres circuitos separados y conviene no mezclarlos**: los libros (conversación), el avance
fotográfico (secuencia temporal) y el archivo de documentación (papeles que se guardan tal cual).

---

## §0 · Qué encontré en la especificación funcional antes de escribir esto

Buscado sobre los 5 archivos de `docs/especificacion_funcional*.md` (3.142 líneas) más `CLAUDE.md`,
por "foto", "imagen", "video", "secuencia", "remito", "factura", "corralón", "subcontrato",
"documentación", "externo" y "por fuera". Resultado exacto, porque la mitad del valor de esta búsqueda
es saber qué **no** hay:

- **El avance fotográfico SÍ estaba, pero solo como nombre en la matriz de permisos.** Aparece como
  columna *"Avance Físico / Fotos"* (`especificacion_funcional_3.md:422`) y como permiso del veedor:
  *"Galería de fotos / bitácora de avances subida por el constructor o profesional"*
  (`:404`, también `:490`, `especificacion_funcional.md:704` y
  `especificacion_funcional_completa.md:63`). O sea: **quién lo ve estaba definido desde el principio;
  qué es y cómo funciona, nunca.** Ni una palabra sobre la fecha, la secuencia, el video final, ni si
  cuelga de una partida.
- **El archivo de documentación NO estaba.** Cero menciones de "remito". "Factura" aparece una vez y
  es otra cosa (el Cliente Autoconstructor *"ve todo — costos directos, facturas, compras"*,
  `especificacion_funcional_parte2_fundacional.md:25`). Lo más cercano es la solapa **Proveedores**
  — *"cotizaciones, órdenes de compra, acopios en corralones y control de entregas"*
  (`especificacion_funcional_3.md:324`) —, que es el circuito de **compra**, no un archivo de
  respaldo: guardar el remito que llegó con el camión no es lo mismo que gestionar la orden de compra.
- **El certificado externo NO estaba en ninguna spec.** La única mención en todo el repo es un bullet
  de "Segunda ola" en `docs/diagnostico_general_producto.md:230` (*"modo certificado externo"*), sin
  una línea de definición. Por eso la auditoría lo tenía bloqueado. **Ahora está definido, ver §4.**
- **Lo que sí estaba y es adyacente**: la firma física del certificado —*"opción de descargar PDF en
  blanco (medición en campo) o completo (firma en papel). Si se opta por firma física, el sistema
  bloquea la emisión del siguiente hasta subir el PDF/imagen firmado"*
  (`especificacion_funcional_parte2_fundacional.md:22`)—. Eso **está construido** (sin el bloqueo, que
  la `0055` sacó a propósito) y es el pariente más cercano del certificado externo.

---

## §1 · Los libros — ya diseñados, no se repiten acá

Libro de Obra, Órdenes de Servicio y Notas de Pedido: **`docs/libro_obra_horizonte.md`**, con las
cuatro decisiones cerradas el 2026-09-13 (el cliente no escribe; las órdenes van numeradas y
correlativas sin candado de secuencia; el aviso legal de que no reemplaza al libro rubricado; y el
audio con una línea de texto del autor).

Lo único que hace falta repetir acá es **por qué son un circuito aparte de los otros dos**: los libros
son **conversación** (alguien dice algo, el otro responde, queda el hilo). El avance fotográfico y el
archivo no tienen interlocutor: se suben y quedan.

---

## §2 · El avance fotográfico

**Fotos con fecha, para que quede la secuencia de cómo fue la obra.**

**Lo importante es la fecha, no la foto.** No es un álbum suelto: es un **registro temporal**. Se
sube una foto y queda anclada al momento en que se sacó — eso es lo que convierte un montón de
imágenes en la historia de la obra, y lo que la hace servir como respaldo (qué había el 12 de agosto).

**El uso final, que conviene tener presente desde ahora aunque no se construya:** poder **bajar toda
la secuencia** para armar un video del proceso y entregárselo al cliente. Textual de Seba: *"se puede
llegar a bajar y hacer un video, entregarles un video de cómo fue la obra — desde el inicio hasta el
final"*.

**La app no arma el video.** Guarda la secuencia ordenada y permite descargarla; el video lo arma el
profesional con otra herramienta. Esto es una decisión de alcance, no una limitación técnica a
resolver después: renderizar video en el teléfono es una pieza enorme y el valor está en tener la
secuencia completa y ordenada, que es justamente lo que hoy se pierde entre WhatsApp y la galería del
celular.

### CERRADO por Seba (2026-09-13): cuelgan de la obra, ordenadas por fecha

**Las fotos del avance fotográfico cuelgan de la obra, no de una partida** — *"no las compliquemos
asociándolas a partidas"*. Ordenadas por fecha, y nada más. La consecuencia es la que estaba
anticipada: el avance fotográfico es **memoria del proceso**, no evidencia de lo certificado. Si algún
día hace falta evidencia por partida, es otra pieza y otra decisión; no se deja el campo "por si
acaso".

Agrupar por etapa queda **afuera de la primera versión** por el mismo criterio: la fecha ya ordena la
secuencia, que es todo lo que hace falta para bajarla y armar el video.

### Dos usos distintos, que no se mezclan

Seba marcó una distinción que evita el error más fácil de esta pieza:

| | **Avance fotográfico** (galería) | **Fotos y documentos de una entrada del libro** |
| --- | --- | --- |
| Qué es | Memoria del proceso de la obra | **Parte de un mensaje**: explicar algo, mostrar un detalle constructivo, ilustrar una orden |
| De qué cuelga | De la **obra**, por fecha | De **esa entrada** del libro (`libro_entradas.adjuntos`) |
| Dónde se ve | En su propio lugar, como secuencia | Dentro del hilo, junto al texto que acompaña |
| Si se borrara el contexto | No tiene contexto: la fecha es el contexto | Pierde el sentido: la foto era el argumento del mensaje |

Una foto que ilustra una Orden de Servicio **no va a la galería de avance**, y una foto de avance
semanal **no es una entrada del libro**. Son dos circuitos y dos lugares, a propósito.

---

## §3 · El archivo de documentación

**Guardar en la obra cualquier documento que haga falta** — PDF, Excel o imagen —, tal cual llegó:

- **Presupuestos de subcontratos**, cuando se pide cotización por obras parciales.
- **Remitos de materiales.**
- **Facturas de corralones.**
- **Cualquier otra documentación** que el profesional o el constructor necesiten tener a mano.

**No confundir con el importador de PDF/Excel del roadmap.** Son dos cosas con la misma palabra:

| | Importador (roadmap, `docs/importador_capa1_diseno_datos.md`) | Archivo de documentación (esto) |
| --- | --- | --- |
| Qué hace con el archivo | Lo **lee** y extrae datos para cargar un cómputo | Lo **guarda** tal cual |
| Qué queda en la base | Partidas, cantidades, precios | El archivo y sus datos de identificación |
| Para qué sirve | Ahorrar tipeo al armar el presupuesto | Respaldo: tenerlo a mano y poder mostrarlo |

El mismo remito puede pasar por los dos circuitos y no se pisan.

---

## §4 · El certificado externo — definido

Estaba en el roadmap como un nombre sin definición (`docs/diagnostico_general_producto.md:230`), y la
auditoría de Gestión de Obra lo tenía **sin ubicar** porque nadie sabía qué era. **Seba lo definió el
2026-09-13**:

> *"Se puede certificar por fuera de la obra, se puede firmar, y de hecho los certificados, si
> necesitan papel, van, se certifican y vuelven."*

**Es una vía más de carga**: registrar en la app un certificado que **se emitió y se firmó por
fuera**, para que la obra quede completa sin tener que rehacerlo dentro del sistema.

**Lo que ya existe y NO es esto** (la distinción importa, porque a primera vista parecen lo mismo): la
app ya soporta el caso *"emitido acá, firmado en papel, vuelve escaneado"* — es la **firma física**,
construida (`certificados.pdf_firmado_adjuntos`, `subir_pdf_firmado_certificado`, `CartelFirmaPendiente`).
El certificado externo es el caso anterior a ese: el certificado **nunca se creó en la app**.

**Y no es lo mismo que el registro de subcontratos** (la otra hipótesis que estaba abierta en la
auditoría): ese usa `hitos_certificacion.contratista_nombre` y es cómo se le certifica **a** un
tercero. Acá se registra un certificado propio hecho afuera. Quedan como dos piezas separadas.

**Tensión de fondo, anotada para cuando se diseñe** (no se resuelve acá): el circuito actual construye
el monto de un certificado **desde el avance por partida** (`certificado_subitems_avance` + el candado
del 100% acumulado). Un certificado que vino de afuera **trae un monto y probablemente no traiga el
desglose por partida**. Es la misma forma de problema que el **avance global**
(`docs/certificacion_acuerdo_partes_diagnostico.md` §6), y conviene resolver los dos con el mismo
criterio en vez de inventar dos caminos.

---

## §5 · Qué de todo esto se apoya en lo que ya existe — verificado contra el código

Esto es lo que pidió Seba explícitamente, y el resultado es más mezclado de lo que parecía.

### Lo que ya existe y sirve

- **Supabase Storage funciona de verdad, con archivos reales.** `importaciones_repository.dart:32`
  → `_client.storage.from('importaciones').uploadBinary(path, bytes)`. **Es el único lugar del
  proyecto que sube un archivo**, y está probado en producción con el importador de Excel. No hay que
  inventar infraestructura: hay que crear el bucket y su política.
- **`file_picker` ya está en `pubspec.yaml:23` y en uso** (`importar_excel_screen.dart:43`), hoy
  restringido a `xlsx`/`xls` por configuración. **Sirve tal cual para PDF, Excel e imágenes ya
  guardadas en el teléfono**, cambiando la lista de extensiones. O sea: el archivo de documentación
  y subir una foto de la galería **no necesitan ninguna dependencia nueva**.
- **`pdf: ^3.10.8`, `printing: ^5.11.1` y `path_provider` están declarados en `pubspec.yaml` y NO se
  usan en ningún lugar de `lib/`** (`grep -rn "package:pdf\|package:printing" lib/` → 0 resultados).
  Dependencias ya elegidas, esperando la primera pieza que genere un PDF — que puede ser la descarga
  del legajo de documentación, el aviso legal al pie del libro, o el certificado.
- **`libro_entradas.adjuntos jsonb`** existe y es genérico (`0003:22`), con RLS append-only. Sirve
  para colgar el audio o la foto **de una entrada del libro**.

### Lo que NO existe, y conviene no asumir

- **Los adjuntos de Gestión de Obra no son archivos: son links pegados a mano.**
  `certificados.comprobante_pago_adjuntos`, `factura_final_adjuntos` y `pdf_firmado_adjuntos` son
  `text[]` de URLs hospedadas afuera (Drive, WhatsApp). Está dicho en el código, en
  `certificados_repository.dart:105-109`: *"la app no sube el archivo en sí... Storage sí se usa en el
  proyecto pero nunca se conectó a los adjuntos de Gestión de Obra"*. **Para el archivo de
  documentación esto no alcanza** — si el respaldo depende de un link de Drive que alguien puede
  borrar, no es respaldo.
- **Sacar una foto desde la app necesita dependencia nueva** (`image_picker` o `camera`, ninguna está
  en `pubspec.yaml`). Elegir una de la galería, no.
- **Grabar audio también necesita dependencia nueva** (nada de grabación en `pubspec.yaml`) — vale
  para la decisión ya tomada de los audios del libro.
- **`libro_entradas.adjuntos` NO sirve para los otros dos circuitos.** Es tentador reusarla y sería un
  error: una foto de avance no es una entrada de un libro (no tiene autor que dialogue, ni hilo, ni
  acuse), y un remito tampoco. Colgar los tres circuitos de la misma tabla obligaría a que todo tenga
  `contenido not null` y `autor_rol`, y a filtrar por tipo en cada consulta.

  **Confirmado por Seba (2026-09-13): comparten el bucket y el patrón de subida, no la tabla.** Lo que
  sí va en `libro_entradas.adjuntos` son las fotos y documentos que son **parte de un mensaje** del
  libro (ver el cuadro de §2) — eso no es reuso forzado, es su función.

### Resumen de lo que faltaría, sin diseñarlo

| Circuito | Se apoya en | Necesita propio |
| --- | --- | --- |
| Libros | `libro_entradas` + RLS (aplicadas), Storage para adjuntos | Repositorio, pantalla, bucket, dependencia de audio |
| Avance fotográfico | Storage, `file_picker` | Su propia tabla (foto + fecha + obra, y lo que se decida de partida/etapa), bucket, y `image_picker` solo si se saca la foto en la app |
| Archivo de documentación | Storage, `file_picker`, `pdf`/`printing` ya declaradas | Su propia tabla (archivo + tipo + fecha + quién lo subió), bucket |
| Certificado externo | Todo el circuito de `certificados` ya construido | Definir cómo entra un monto sin desglose por partida (ver la tensión de §4) |

---

## §6 · Lo que este documento NO decide

No hay diseño de datos, ni tablas, ni orden de ejecución. Las preguntas abiertas quedan anotadas en su
sección (§2: partida o obra, y etapas; §4: el monto sin desglose). El orden se decide aparte, junto con
el resto de lo que falta en Gestión de Obra
(`docs/gestion_obra_estado_real_auditoria.md` §5).
