# Gestión de Obra — estado real, verificado contra el código (2026-09-11)

Pedido explícito: verificar contra `lib/`/`supabase/migrations/`, no contra otros documentos —
"ya nos pasó dos veces que un documento decía que algo faltaba y estaba hecho, o al revés". Todo
lo de abajo sale de grep/lectura directa del código, con el archivo y la línea citados. Donde un
doc anterior decía algo distinto, lo marco explícitamente.

## 1. Construido y funcionando de punta a punta

**Modelo A (avance medido), hasta "Emitido"**: crear obra → tildar cómputo → Factor K → congelar
presupuesto → cargar avance por partida (`CargaAvanceSubitemsScreen`) → vista previa
(`VistaPreviaCertificadoScreen`, mismo cálculo que `emitir_certificado`) → emitir. El candado del
100% acumulado, el bloqueo si hay excesos, y la anulación (proponer/resolver, con la dupla
Profesional/Constructor) están conectados de punta a punta — `gestion_obra_tab.dart` llama
`proponerAnulacion`/`resolverAnulacion`, verificado.

**Firma física**: aviso persistente (`CartelFirmaPendiente`) + subir el link del PDF — funciona,
no bloquea la emisión del siguiente certificado (decisión de Seba, `0055`).

**Congelamiento + CAC** (piezas de esta misma conversación): `PresupuestoEstadoPanel` conecta
presentar/vencido/congelar y el ajuste por CAC, verificado en Galpón Mix.

**Configuración de certificación**: `PanelConfigCertificacion` guarda plazo de pago, anticipo,
fondo de reparo, y la carga inicial de `monto_total_contratado` (Modelo B) — esto sí escribe en
Supabase y funciona.

## 2. Construido con una brecha real entre el schema y la app — esto es lo que un doc no te iba a
   decir

**El ciclo de 5 estados del certificado quedaba atascado en "Emitido" — CERRADO 2026-09-11.**
`marcar_certificado_leido`/`marcar_certificado_pagado`/`marcar_certificado_impactado` existían y
funcionaban en Supabase (`0011`) pero ningún repositorio Dart las envolvía y ninguna pantalla las
llamaba. Construido: los 3 métodos en `CertificadosRepository`, pantalla nueva
`DetalleCertificadoScreen` (abre con `onTap` desde la tarjeta del historial en
`gestion_obra_tab.dart`, solo para certificados que ya dejaron de ser borrador), con el desglose
pactado/ajuste CAC y la línea de tiempo de los 5 pasos. "Leído" se marca solo al abrir el detalle,
sin botón, tal como lo pedía la spec fundacional. Autoridad verificada contra el código real de las
3 funciones (`0011`), no asumida — 3 getters nuevos en `UserContext`
(`puedeMarcarCertificadoLeido`/`Pagado`/`Impactado`), que **corrigen una discrepancia real
encontrada al verificar**: el getter viejo `puedeAprobarCertificados` (nunca usado por ninguna
pantalla, confirmado) incluye `admin_maestro`, pero `puede_gestionar_certificado` — la función real
detrás de `marcar_certificado_pagado` — nunca lo incluye, solo `cliente_principal`/
`invitado_apoderado`. El comentario de ese getter cita "la Matriz de permisos consolidada" de
`CLAUDE.md` como fuente; lo que exige el servidor es distinto. Se dejó ese getter sin tocar (no lo
usa nada hoy) y los 3 nuevos no lo reusan.

**Obras en USD: el certificado seguía mostrando pesos — CERRADO 2026-09-11.** Encontrado al probar
el ciclo completo: `certificados.monto` siempre está en ARS (igual que todo el sistema de
precios), pero ninguna de las 3 pantallas (`DetalleCertificadoScreen`, el historial de
`GestionObraTab`, `VistaPreviaCertificadoScreen`) convertía a la moneda de la obra — sí lo hacía el
presupuesto vivo del dashboard (`ObrasListScreen._convertirMonto`), esto quedó afuera al
construirse antes de que existiera ese patrón. Además, un certificado YA EMITIDO tiene que
convertirse a la cotización del momento en que se emitió, no a la de hoy — el monto en pesos ya
está congelado, mismo criterio de "no retroactivo" que el resto del ciclo. Como
`cotizacion_dolar_bna` es una fila única sin historial, hizo falta un snapshot nuevo
(`certificados.cotizacion_dolar_promedio_al_emitir`, `0107`) — `null` en certificados emitidos
antes de esa migración, que caen a la cotización de hoy con un aviso visible de que es aproximado.

**El selector de Modelo de certificación bypaseaba la función dedicada — CERRADO 2026-09-11.**
`ObraConfigCertificacionRepository.actualizarConfig` hacía un `.update()` directo sobre
`obras.modelo_certificacion`, sin pasar por `cambiar_modelo_certificacion` (`0005`, motivo
obligatorio + `audit_log`). Ahora el cambio de modelo es una llamada aparte
(`cambiarModelo`), disparada solo cuando el modelo elegido difiere del guardado, con un diálogo que
pide el motivo antes de guardar — mismo candado que ya exigía el servidor, ahora repetido también
del lado del cliente para no gastar el viaje de red con algo que iba a rechazar seguro.

**`modificaciones_obra` (Adicionales/Demasías/Quitas) tiene un desajuste de fondo, no solo falta
de UI**: `subitem_id` referencia `subitems(id)` — el **catálogo** compartido (`0021`) — no
`obra_subitems(id)`, que es la tabla real del cómputo de una obra (la que usa congelamiento,
certificación, avance, todo). Tal como está el schema hoy, no hay forma de que un adicional
apunte a "esta línea nueva en el cómputo de esta obra puntual" — apuntaría, como mucho, a un
subítem del catálogo general. Además, de los 4 tipos (`adicional`/`demasia`/`quita`/
`ajuste_contrato`), **solo `ajuste_contrato` tiene una función de aprobación** (`aprobar_ajuste_contrato`,
`0008`, atómica: aprueba + aplica el delta a `obras` + `audit_log`). Los otros 3 solo tienen
`INSERT`/`UPDATE` por RLS — sin ninguna función que "gradúe" un adicional aprobado a una fila real
de `obra_subitems`, aunque el comentario del modelo Dart (`modificacion_obra.dart:13-14`) describe
esa graduación como si ya existiera. Y del lado de Dart: `ModificacionObra`
(`lib/data/models/modificacion_obra.dart`) es un modelo con `toMap()`/`fromMap()` en camelCase
directo — el patrón de los modelos viejos pre-Supabase (`ObraModel`), no el patrón
`_fromRow`/`_toRow` snake_case que usa el resto del proyecto — **no tiene ningún repositorio**, y
no lo importa ninguna pantalla (`grep -rln "modificacion_obra.dart" lib/` → 0 resultados fuera del
propio archivo). Confirmado también en el comentario de
`lib/services/obra_config_certificacion_repository.dart:57-61`: "sin UI todavía, fuera de esta
pieza".

## 3. Diseñado y con datos aplicados en producción — cero código Dart

**Modelo B (Hitos de Precio Cerrado)**: `hitos_certificacion` (tabla, RLS, `0006`/`0007`/`0012`),
`calcular_avance_hitos`, `calcular_saldo_pendiente_hitos` (con CAC ya conectado, `0102`) — todo
aplicado y verificado en su momento. Pero:

```
grep -rn "hitos_certificacion" lib/   →  0 resultados
```

Cero. Ni un modelo Dart, ni un repositorio, ni una pantalla. `PanelConfigCertificacion` dejaba
elegir "Hitos de Precio Cerrado" con un `RadioListTile` sin ningún aviso — **corregido
2026-09-11**: al elegir esa opción aparece un cartel ámbar explícito ("Todavía no hay ninguna
pantalla en la app para cargar o gestionar hitos") antes de guardar, no después de buscar y no
encontrar.

**Registro de subcontratos**: usa la MISMA tabla (`hitos_certificacion.contratista_nombre`, ya
diseñado con esa doble función desde `0006`) — mismo estado exacto, cero código Dart. No es una
pieza aparte del punto anterior a nivel de datos, comparte la tabla entera.

## 4. Ni diseñado — ni en código, ni en ningún doc de diseño cerrado

**"Certificado externo" / "modo certificado externo"**: no encontré una definición operativa en
ningún lado del proyecto, solo el nombre. Aparece como bullet de "Segunda ola" en
`docs/diagnostico_general_producto.md` §5, sin desarrollo. La única otra mención
(`docs/importador_capa1_diseno_datos.md:157/197`) lo usa como punto de comparación para el
importador de Excel y dice explícitamente *"no tengo visibilidad de 'el importador de
certificados externos'"* — ni siquiera esa pieza sabía qué era. **Antes de poder ordenarlo en la
secuencia necesito que lo definas vos** — ¿es certificar el avance de un subcontratista externo
(entonces es literalmente lo mismo que "registro de subcontratos" de arriba, con otro nombre)? ¿Es
importar un certificado ya emitido por otro sistema/otra empresa? Son piezas muy distintas y hoy
el nombre solo no alcanza para saber cuál.

**Presunción de Claude Code (2026-09-11), no una definición — para que Seba la confirme o la
corrija más adelante**: cargar en la app un certificado que se emitió por fuera de la app — en
papel o en una planilla Excel — para que el historial de la obra quede completo sin tener que
rehacerlo dentro del sistema. Sigue sin ubicación en el orden de la sección 5 hasta que se
confirme.

**Carga de fotos en obra**: ninguna tabla del proyecto está pensada para esto —
`grep -rln "foto\|imagen\|adjunto" supabase/migrations/*.sql` da 5 archivos, ninguno es "fotos de
obra": `libro_entradas` (adjuntos genéricos de texto libre), `certificados` (comprobante de pago,
factura final, PDF firmado — todos administrativos), `importaciones` (el archivo Excel/PDF que se
importa). El lugar donde conceptualmente encajaría — `libro_entradas`, el "Libro de Obra" — tiene
tabla y RLS aplicadas (`0003`/`0004`) pero **cero repositorio y cero pantalla**
(`grep -rln "libro_entrada\|LibroEntrada" lib/` → solo el propio modelo). Hoy no se puede ni
escribir una línea de texto en el Libro de Obra desde la app, mucho menos adjuntar una foto.

Dato a favor: el mecanismo técnico de subir un archivo real (no un link pegado a mano) **sí existe
y funciona** — `lib/services/importaciones_repository.dart:31`,
`_client.storage.from('importaciones').uploadBinary(...)`, Supabase Storage real. No es
infraestructura nueva que haya que inventar; hoy solo se usa para el importador, nunca se conectó
a nada de Gestión de Obra. El paquete `image_picker`/`camera` no está en `pubspec.yaml` — sacar una
foto desde la app (vs. subir una ya sacada) necesitaría sumarlo.

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

**1 — Cerrar el ciclo del certificado Modelo A (Leído/Pagado/Impactado). CERRADO 2026-09-11**, ver
§2 — `DetalleCertificadoScreen` + los 3 métodos de repositorio + 3 getters de autoridad nuevos en
`UserContext`. Sin verificar todavía en el emulador con los 4 roles reales.

**2 — Modelo B (pantallas de Hitos).** El dato ya está listo (tabla + las 2 funciones, con CAC
conectado). Es pura construcción de UI: listar hitos, crear uno, marcar finalizado/pagado. No
depende del punto 1 ni de nada nuevo.

**3 — Subcontratos, como extensión directa de la pantalla del punto 2**, no como pieza aparte
meses después — comparten la misma tabla y casi toda la UI (lista + alta + marcar finalizado),
solo cambia el filtro por `contratista_nombre` y el formulario de alta. Separarlos en el tiempo
duplicaría trabajo de pantalla para el mismo dato.

**4 — Adicionales/Demasías/Quitas.** Antes de cualquier pantalla, hace falta una decisión de
diseño de datos que no está resuelta: corregir a qué apunta `subitem_id` (hoy al catálogo, tiene
que poder referenciar `obra_subitems` de la obra puntual) y decidir si hace falta una función de
aprobación por tipo (como `aprobar_ajuste_contrato`) que gradúe un adicional aprobado a una fila
real del cómputo, o si eso se resuelve de otra forma. Es la pieza con más trabajo de diseño previo
de las cuatro — no depende de las anteriores, pero conviene ir después porque el diseño de datos
que hace falta corregir es más parecido al de Rubros/APU (ya cerrado) que al de certificación.

**5 — Certificado externo.** Sin poder ubicarlo hasta que se defina qué es (§4) — si termina
siendo lo mismo que subcontratos con otro nombre, se resuelve en el punto 3 y desaparece como
pieza aparte.

**6 — Carga de fotos en obra.** Necesita su propio mini-diseño de datos primero (¿cuelga del Libro
de Obra si se construye? ¿de una partida puntual? ¿del avance certificado, como evidencia?) — la
parte técnica (Storage) no es el riesgo, ya está probada. Lo pondría último porque depende de una
decisión de producto que todavía no existe en ningún lado, ni siquiera como bullet de roadmap con
más detalle que el nombre.
