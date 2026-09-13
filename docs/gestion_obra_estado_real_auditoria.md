# Gestión de Obra — estado real, verificado contra el código

**Auditoría original 2026-09-11. Reauditada de cero el 2026-09-13**, después de construir el ciclo
completo del certificado, los adicionales con su seguimiento, las quitas y demasías, el permiso de
editar presupuesto, la periodicidad de certificación y el cartel de pendientes.

Pedido explícito, las dos veces: **verificar contra `lib/` y `supabase/migrations/`, no contra otros
documentos** — *"ya nos pasó dos veces que un documento decía que algo faltaba y estaba hecho, o al
revés"*. Todo lo de abajo sale de lectura directa del código, con archivo y línea. Lo que la
auditoría anterior decía y hoy es falso está en §6, marcado como corrección.

**Cómo leer la columna de evidencia**: `archivo:línea` es donde se verificó, no donde "debería
estar". Si un ítem dice "0 resultados", el grep está escrito para que se pueda repetir.

---

## 1. Construido y funcionando

| Pieza | Estado | Verificado en |
| --- | --- | --- |
| **Ciclo del certificado, los 5 estados** Borrador → Emitido → Leído → Pagado → Impactado/Cerrado | Completo, con sus 3 transiciones envueltas en Dart y pantalla de detalle | `certificados_repository.dart:161/169/183`, `detalle_certificado_screen.dart`, `0011` |
| **Anulación** de un certificado emitido (proponer / resolver, dupla profesional+constructor, reemplazo con `version`) | Completo y verificado con 2 usuarios reales | `certificados_repository.dart:126/143`, `gestion_obra_tab.dart:462/798`, `0056` |
| **Carga de avance por partida**, con candado del 100% acumulado y bloqueo por excesos | Completo (rubros → subítems, dos pantallas anidadas) | `carga_avance_rubros_screen.dart:269`, `carga_avance_subitems_screen.dart`, `0052`/`0054` |
| **Vista previa** del certificado antes de emitir, con el mismo cálculo que la emisión | Completo | `vista_previa_certificado_screen.dart:42`, `calcular_totales_certificado` (`0105:401`) |
| **Certificación al precio final** (cascada de Factor K completa, no al costo) | **Corregido y verificado 2026-09-09** — ver §6.1 | `0094`, trigger vigente en `0105:360` |
| **Presentar / validez / congelar** el presupuesto, y el ajuste por CAC | Completo | `presupuesto_estado_panel.dart`, `0103`/`0104`/`0105` |
| **Cotización congelada** de los montos cerrados (pactado y adicional aprobado no se mueven en USD) | Completo y verificado en Galpón Mix | `0122`, `obras_list_screen.dart:_convertirMonto`, `presupuesto_estado_panel.dart:_fmtMonto` |
| **Firma física**: aviso persistente + subir el PDF, sin bloquear la emisión siguiente | Completo | `cartel_firma_pendiente.dart`, `certificados_repository.dart:110`, `0055` |
| **Configuración de certificación**: plazo de pago, anticipo, fondo de reparo, modelo, monto contratado, **periodicidad** | Completo | `panel_config_certificacion.dart`, `obra_config_certificacion_repository.dart:24` |
| **Quitas y Demasías**: crear, aprobar, rechazar, observar, historial de observaciones — y corrigen de verdad la cantidad del cómputo y el congelado | Completo | `modificaciones_obra_repository.dart:21-120`, `quitas_demasias_screen.dart`, `0109` |
| **Adicionales**: crear por monto fijo, presupuestar con la app (obra hija), enviar, aprobar/rechazar con monto congelado, seguimiento de avance | Completo salvo la tercera vía (ver §2.3) | `adicionales_repository.dart:74/111/186/199/218/228`, `adicionales_screen.dart`, `0112`-`0120` |
| **Rol vs. permiso** (`puede_editar_presupuesto`): emitir, congelar, anular y aprobar quitas exigen el permiso; cargar avance sigue por rol | Completo, espejado en la app | `user_context.dart:77/91/153/163/236`, `0121` |
| **Avisos de pendientes** (cartel del dashboard + contador por obra), 9 tipos incluido "ya se puede certificar" | Completo y verificado | `mis_pendientes()` (`0117`+`0123`), `pendiente.dart`, `cartel_pendientes.dart` |
| **Periodicidad de certificación** y su aviso, con el período sugerido al crear el borrador | Completo y verificado 2026-09-13 | `0123`, `periodo_certificacion.dart`, `gestion_obra_tab.dart:_pedirPeriodo` |
| **Barra de acciones** de la solapa, preparada para crecer a 6-8 acciones | Completo | `barra_acciones_obra.dart` |

## 2. Construido a medias — brechas medidas, no sospechas

Esto es lo que ningún documento iba a decir, y es el valor de auditar contra el código.

### 2.1 · El avance físico de la obra se calcula y **no se muestra en ninguna pantalla**

`calcular_avance_ponderado_rubros` y `calcular_avance_ponderado_obra` existen (`0052:249/272`),
**están envueltas en Dart** (`certificado_subitems_avance_repository.dart:117` y `:130`) y
`grep -rn "getAvancePonderado" lib/presentation/` da **0 resultados**: ninguna pantalla las llama.
La app sabe calcular "esta obra va al 42%" y no lo dice en ningún lado — ni en Gestión de Obra, ni
en la card del dashboard (donde Seba ya pidió una barra de avance), ni en Resumen (que sigue siendo
la maqueta de la demo, con 85.000.000 hardcodeado: `presupuestos_screen.dart:_buildTabResumenFinal`).
**Es la brecha más barata de cerrar de toda la solapa**: los datos y el acceso ya están.

### 2.2 · Un apoderado con delegación permanente no puede marcar leído ni pagado

Divergencia real y todavía abierta entre la base y la app: para la base, delegación **sin fechas =
permanente y vigente** (`0004`/`0011`/`0116`); en Dart hay **dos helpers** —
`_delegacionVigenteSegunBase` (correcto, `user_context.dart:281`) que usan los getters de
adicionales, y `_delegacionVigente` (`user_context.dart:290`) que trata "sin fechas" como **no
vigente** y es el que usan `puedeMarcarCertificadoLeido` (`:203`) y
`puedeMarcarCertificadoPagado` (`:211`). Efecto concreto: un apoderado con delegación permanente ve
la pantalla sin los botones, aunque el servidor lo autorizaría. El propio código lo tiene anotado
como pendiente. **Fix mecánico**: unificar en el helper correcto y borrar el otro.

### 2.3 · La tercera vía de carga de un adicional es un cartel de "próximamente"

El selector ofrece tres vías (monto fijo / presupuestar con la app / importar de Excel-PDF) y la
tercera llama a `_mostrarImportarProximamente()` (`adicionales_screen.dart:183`, ofrecida en
`:958`). No es un bug: está a la vista. Pero el menú promete algo que no existe.

### 2.4 · Un adicional aprobado no se cobra por ningún documento

`certificar_avance_adicional` (`0120`) guarda porcentaje y monto certificado **en la fila del
adicional**, y ahí termina: `calcular_saldo_pendiente_avance_medido` (`0105:245`) suma solo
`presupuesto_subitems_congelado`, y `calcular_totales_certificado` nunca mira
`modificaciones_obra`. O sea: **el avance de un adicional se registra pero no genera certificado, no
entra en el saldo pendiente del contrato y no tiene comprobante de cobro**. La card del dashboard sí
lo suma al total (`obras_list_screen.dart`, `0122`), así que el número que se le muestra al cliente y
lo que el circuito de cobro sabe facturar **no coinciden**. Es una decisión de negocio pendiente, no
un bug: ¿el adicional se certifica dentro del certificado del período, o emite el suyo?

### 2.5 · Modelo B elegible, sin ninguna pantalla

`grep -rn "hitos_certificacion\|HitoCertificacion" lib/` → **0 resultados** (igual que en la
auditoría anterior). El dato está completo desde `0006`/`0007`/`0012`, con CAC conectado. El panel de
configuración deja elegirlo y avisa con un cartel ámbar que no hay dónde gestionarlo
(`panel_config_certificacion.dart:256`), que es lo mínimo honesto, pero la obra queda sin circuito:
`certificados` tiene un guard de RLS que exige `avance_medido` (`0009`), así que en Modelo B no hay
certificados **ni borrador ni nada**. **Registro de subcontratos** es la misma tabla
(`hitos_certificacion.contratista_nombre`), mismo estado exacto.

## 3. Diseñado, sin construir

Todo esto tiene documento de diseño con decisiones cerradas y cero código.

| Pieza | Diseño | Qué falta |
| --- | --- | --- |
| **Certificar como acuerdo entre partes** (propuesta y conformidad en el borrador, con la contraparte que corresponda) | `docs/certificacion_acuerdo_partes_diagnostico.md` §2, Tanda 2 | Columnas de propuesta/conformidad, guard en `emitir_certificado`, 1 pendiente, UI. **Es la única pieza que toca RLS**: el cliente deja de ver el borrador cuando hay profesional |
| **Objeción del cliente que frena el pago** | mismo doc, §5, Tanda 3 | Eje `objecion_*` (como `anulacion_*`), una línea en `marcar_certificado_pagado`, 2 funciones, 1 pendiente, UI |
| **Avance global** (un porcentaje de toda la obra o de un rubro, repartido por peso del monto congelado) | mismo doc, §6, Tanda 4 | Función de reparto + modo de carga. No toca el núcleo |
| **Libro de Obra y los dos libros direccionales** | `docs/libro_obra_horizonte.md`, **4 decisiones cerradas 2026-09-13** | Migración de policy + columna `numero`, repositorio, pantalla tipo chat, Storage. El modelo Dart existe; `grep -rn "LibroEntrada" lib/` fuera del modelo → 0 |
| **Pantallas de Modelo B / subcontratos** | datos aplicados, UI nunca diseñada en detalle | Ver §2.5 |

## 4. Ni diseñado — no existe en código ni en ningún documento de diseño

| Pieza | Evidencia de que no existe |
| --- | --- |
| **"Certificado externo"** | **DEFINIDO el 2026-09-13** (`docs/documentacion_obra_tres_circuitos.md` §4): registrar en la app un certificado emitido y firmado por fuera, para que la obra quede completa sin rehacerlo. No es la firma física (eso ya está construido: emitido acá, firmado en papel, vuelve escaneado) ni el registro de subcontratos. Sin diseño de datos |
| **Fotos de obra** (avance fotográfico) | Alcance documentado el 2026-09-13 (`docs/documentacion_obra_tres_circuitos.md` §2: fotos con fecha, secuencia descargable, el video lo arma el profesional) pero **sin diseño de datos**: ninguna tabla es para esto. `file_picker:23` alcanza para subir una foto de la galería; sacarla en la app necesita `image_picker`/`camera`, que no están. **`libro_entradas.adjuntos` NO es el lugar** — ver §5 del doc nuevo |
| **Audios** | Decidido el formato (audio + una línea de texto) pero **sin dependencia de grabación** en `pubspec.yaml` y sin bucket |
| **Archivo de documentación** (remitos, facturas de corralón, presupuestos de subcontratos) | Alcance documentado el 2026-09-13 (`docs/documentacion_obra_tres_circuitos.md` §3) y **sin diseño de datos**. Ojo con dos confusiones ya anotadas ahí: no es el importador de Excel/PDF (ese lee, esto guarda) y no son los `*_adjuntos` de `certificados`, que son links pegados a mano, no archivos |
| **Gantt / curva de inversión** | Una línea en `docs/especificacion_funcional_completa.md:101` ("Calendario/Gantt de avance físico y financiero") y nada más en todo el repo |
| **Lluvia / fuerza mayor / partes diarios de obra** | 0 resultados en código y en migraciones |

## 5-bis. Libro de Obra / Órdenes de Servicio / Notas de Pedido — qué dice la spec real (2026-09-11)

Pedido explícito de Seba, antes de diseñar nada de esto: buscar en `CLAUDE.md` y en
`docs/especificacion_funcional*.md` (los 5 archivos, incluido `_parte2_fundacional.md`) qué ya
estaba definido en la etapa con Gemini, sin rediseñar. Búsqueda exhaustiva, no una lectura
salteada — grep de "libro"/"orden de servicio"/"nota de pedido"/"bitácora"/"audio" sobre los 5
archivos completos (813+1560+575+131+63 líneas) más `CLAUDE.md`.

**Resultado, y hay que decirlo tal cual salió**: ninguno de los 5 archivos de especificación
funcional contiene, ni una sola vez, las frases "Libro de Obra", "Orden de Servicio" o "Nota de
Pedido". Tampoco "bitácora". La única mención de "3 libros" en todo el proyecto (fuera de este
archivo) está en `CLAUDE.md:99`, que a su vez resume `docs/etapa3_roles_permisos_diseno_datos.md`
— **ese documento es la única fuente real de este diseño**, no la spec de Gemini. El propio
documento dice "corrige la redacción original de la spec" (§6.7) sin citar dónde vive esa
redacción — no pude encontrarla en ningún archivo del repo. Puede que exista en una conversación
con Gemini que nunca se pegó en ninguno de estos 5 documentos — si la tenés en otro lado, pasámela
y reviso de nuevo antes de asumir que el diseño actual es el punto de partida completo.

**Lo que sí define `docs/etapa3_roles_permisos_diseno_datos.md` §5/§6.7/§7.7** (esto es diseño
real, cerrado, no spec de Gemini):
- Tabla única `libro_entradas` con discriminador `libro` (`'obra'`/`'orden_servicio'`/`'nota_pedido'`),
  en vez de 3 tablas — decisión explícita, con su trade-off documentado (§5).
- Matriz de quién **genera** entrada raíz y quién solo **responde** como entrada hija
  (`entrada_padre_id`), por libro — Libro de Obra: escriben `admin_maestro`/`profesional`/
  `constructor`/`cliente_principal` (`invitado_veedor` siempre lectura, `invitado_apoderado` solo
  con delegación activa); Órdenes de Servicio: raíz solo `profesional`, `constructor` responde
  (acuse de recibo); Notas de Pedido: al revés, raíz `constructor`, responden `profesional`/
  `cliente_principal`.
- Append-only por diseño: sin `UPDATE` ni `DELETE` en ningún libro (coherente con "bitácora de
  tipo legal").
- Un aviso legal persistente ("no reemplaza al Libro de Obra rubricado") — **citado como `§F` pero
  esa sección no existe en ningún documento del repo** (`grep -n "§F"` da un único resultado: la
  propia cita, sin destino). El texto exacto del aviso nunca se terminó de escribir en ningún
  lado, solo la intención de que exista.

**Sobre la formalidad que preguntaste — numeración, firma, secuencia: no están definidas.**
Verificado con grep dedicado ("numera", "secuenc", "firma", "obligator" sobre el documento
completo): cero resultados relacionados con los 3 libros. A diferencia de `certificados` (que sí
tiene `numero` con `unique(obra_id, numero)`, un candado real de secuencia, y todo un concepto de
firma física con sus propias columnas), **ni el diseño ni el schema aplicado de `libro_entradas`
tienen concepto de numeración, de firma (ni digital ni física), ni de secuencia obligatoria** —
`entrada_padre_id` resuelve "quién responde a quién", pero no "esta Orden de Servicio Nº7 no se
puede emitir si la Nº6 sigue sin acuse". Es una laguna real del diseño, no algo que decidiste dejar
afuera a propósito en ningún momento que haya quedado registrado.

**Sobre los audios: cero menciones en todo el proyecto.** `grep -rin "audio|grabaci[oó]n|voz|transcrib"`
sobre todos los `docs/*.md` y `CLAUDE.md` no da ningún resultado relacionado con notas de voz de
obra — los 5 resultados que aparecen son coincidencias sueltas ("en voz alta", "transcribo una
conversación" como encabezado de un pegado de Gemini, "vuelve al papel y transcribe después" sobre
trabajar sin señal). **No hay ninguna definición de si un audio se guarda como archivo de audio o
se transcribe a texto** — no es una ambigüedad cerrada de otra forma, es un vacío total, tenés que
decidirlo de cero el día que se diseñe.

**Un concepto distinto que sí aparece en la spec, para no confundirlo**: "cargar documentación"
(`docs/especificacion_funcional_2.md`, alrededor de la línea 631) y el "Importador de PDF y foto"
del roadmap (`CLAUDE.md`, "Roadmap adicional pospuesto") se refieren a **subir planos/PDF/DWG para
pedir un Servicio Especial** (cómputo métrico, legajo técnico) — no es el Libro de Obra ni las
Notas de Pedido, es documentación técnica de la obra adjunta a una solicitud comercial. Dos piezas
distintas que comparten la palabra "documentación".

**Confirmado contra el código, con precisión sobre lo que ya había adelantado en §3**:
- `supabase/migrations/0003_libro_entradas.sql`: tabla aplicada, columnas exactas —
  `id, obra_id, libro, autor_usuario_id, autor_rol, contenido, adjuntos jsonb, entrada_padre_id,
  created_at`. Sin `numero`, sin ninguna columna de firma. `contenido` es un único `text` — no hay
  ninguna distinción de tipo (texto/audio/foto) más allá de lo que se pueda inferir del `jsonb` de
  `adjuntos`.
- `supabase/migrations/0004_rls_etapa3.sql:195-227`: RLS aplicada, la política `INSERT` reproduce
  la matriz de arriba exactamente (rama por `libro`, verificado línea por línea contra §5 del
  diseño) y usa `tiene_rol_en_obra`, que sí respeta la ventana de delegación del Apoderado — esta
  parte puntual del diseño está bien aplicada.
- `lib/data/models/libro_entrada.dart`: el modelo Dart existe, mapeado 1:1 al diseño.
- `grep -rln "libro_entrada\|LibroEntrada\|TipoLibro" lib/` fuera del propio modelo → **0
  resultados**. Sin repositorio, sin pantalla, sin ningún punto de entrada en la app — confirma lo
  que ya había encontrado en la auditoría anterior (§3/§4), ahora con el detalle de qué falta
  específicamente además de la pantalla: no hay número, no hay firma, no hay definición de audio.

## 5. Orden recomendado, con las dependencias reales

Ordenado por dos criterios: **lo que desbloquea el uso real primero**, y **lo barato antes que lo
caro cuando el valor es parecido**. Las dependencias están dichas explícitamente; lo que no aparece
como dependencia no la tiene.

**1 · Mostrar el avance de la obra** (§2.1). *No depende de nada — los datos, las funciones y el
repositorio ya existen.* Es la única pieza de esta lista que ya está construida por debajo y solo le
falta pantalla: el % ponderado por rubro y el total de la obra. Alimenta de una vez tres cosas
pedidas: la barra de avance de la card del dashboard, el "cómo van" de la portada, y el primer
contenido real de la solapa Resumen (hoy maqueta). **Lo pongo primero porque es horas de trabajo con
un efecto visible en tres pantallas.**

**2 · Unificar el helper de delegación** (§2.2). *No depende de nada.* Es un fix de una línea y
borrar el helper viejo, con un escenario de prueba: apoderado con delegación sin fechas tiene que
poder marcar leído y pagado. Va segundo porque es un permiso mal negado, o sea un usuario real
bloqueado, y cuesta menos que leer este párrafo.

**3 · Certificar como acuerdo entre partes** (§3, Tanda 2). *Depende de la decisión de RLS ya
cerrada (el cliente no ve el borrador cuando hay profesional).* Es el cambio de fondo que pidió
Seba: hoy el que carga emite. Va antes que la objeción porque **si el acuerdo funciona, la objeción
es la excepción**, y porque el acuerdo no toca el cobro.

**4 · Objeción del cliente** (§3, Tanda 3). *Depende del 3* — la objeción es la contracara del
acuerdo, y comparte el patrón de sub-estado. Es la única que mete la mano en `marcar_certificado_
pagado`, así que conviene que entre cuando el resto del circuito ya esté estable.

**5 · Cómo se cobra un adicional aprobado** (§2.4). *Depende de una decisión de negocio, no de
código.* Hay que resolverlo antes de que haya obras con adicionales certificados a mano y un cliente
preguntando por qué no le llega comprobante. Puede adelantarse a los puntos 3 y 4 si aparece una obra
real con adicionales en ejecución — es el único ítem de esta lista cuyo orden lo decide el uso, no la
técnica.

**6 · Libro de Obra, los dos libros direccionales** (§3). *Depende de la migración de la tanda 0
(policy sin el cliente + columna `numero`), ya decidida.* La barra de acciones ya está preparada para
las dos entradas nuevas. Primero texto; audios y fotos después, que necesitan dependencia nueva en
`pubspec.yaml`.

**7 · Avance global** (§3, Tanda 4). *No depende de nada, pero no mezclar con el 3*: cambiar al mismo
tiempo cómo se carga el avance y cómo se acuerda deja sin saber cuál de los dos rompió algo.

**8 · Modelo B: pantallas de hitos, y subcontratos como extensión de esa misma pantalla** (§2.5).
*No depende de nada.* Va acá abajo por una razón de negocio, no técnica: Seba trabaja en Modelo A, y
todo lo de arriba mejora la obra que existe hoy. Cuando se haga, subcontratos sale casi gratis de la
misma pantalla — separarlos en el tiempo duplicaría el trabajo de UI sobre la misma tabla.

**9 · Fotos, documentación tipada, Gantt/curva de inversión** (§4). *Fotos y documentación dependen
del punto 6* (el libro es donde cuelgan). Gantt y curva de inversión dependen de que exista un
calendario de obra, que no existe ni como idea — es la única pieza de toda la lista que necesita
diseño de negocio desde cero.

**10 · Certificado externo** (§4). Ya no está sin ubicar: quedó definido el 2026-09-13
(`docs/documentacion_obra_tres_circuitos.md` §4) y **no es** ni la firma física ni los subcontratos.
*Depende del punto 7* — un certificado que viene de afuera trae un monto y probablemente no traiga el
desglose por partida, que es la misma forma de problema que el avance global; conviene resolver los dos
con el mismo criterio en vez de inventar dos caminos.

**Los tres circuitos de documentación de la obra** (libros, avance fotográfico, archivo) están
documentados sin diseño de datos en `docs/documentacion_obra_tres_circuitos.md`. En esta lista, los
libros son el punto 6 y los otros dos el punto 9.

---

## 6. Correcciones a la auditoría anterior — lo que decía y hoy es falso

**6.1 · "La certificación factura al costo puro, sin Factor K" → CERRADO el 2026-09-09.** La `0094`
hizo que `calcular_monto_obra_subitems` use `calcular_precio_final_apu_subitems` (cascada completa),
y el trigger vigente (`0105:360`) calcula `monto_periodo` sobre eso. Confirmado como aplicado y
verificado en `docs/diagnostico_general_producto.md:37-43`. **La memoria de trabajo seguía
marcándolo como pendiente** — corregida en esta misma pasada.

**6.2 · "`modificaciones_obra` no tiene ningún repositorio y no lo importa ninguna pantalla" →
falso hoy.** Tiene dos repositorios (`modificaciones_obra_repository.dart`,
`adicionales_repository.dart`) y dos pantallas (`quitas_demasias_screen.dart`,
`adicionales_screen.dart`), más el modelo migrado al patrón `fromRow` del resto del proyecto.

**6.3 · "`subitem_id` apunta al catálogo, no hay forma de que una modificación apunte a una partida
de esta obra" → resuelto por la `0109`**, que agregó `obra_subitem_id` y lo hizo obligatorio para
quitas y demasías. `subitem_id` queda como columna histórica sin uso nuevo.

**6.4 · "Hace falta una función que gradúe un adicional aprobado a una fila real del cómputo" → se
resolvió de otra forma, a propósito.** Un adicional presupuestado con la app **no se grada a
`obra_subitems`**: vive como **obra hija** con su propio cómputo congelado (`0113`), y uno de monto
fijo no toca el cómputo en absoluto. La pregunta que quedó abierta no es la graduación sino el cobro
(§2.4).

**6.5 · Lo que la auditoría anterior listaba como "el ciclo se atasca en Emitido" está cerrado y
verificado**, igual que el orden que proponía en sus puntos 1 a 3: el 1 se hizo, el 2 y el 3 (Modelo
B y subcontratos) siguen intactos y pasaron a §2.5.
