# computoPRO — Diagnóstico general del producto

**Estado al 9 de septiembre de 2026.** Cubre fortalezas, debilidades, riesgos, backlog y orden de ejecución. La estrategia comercial va aparte, en `docs/monetizacion.md`.

## 0 · Contexto

App Flutter/Supabase de cómputo, presupuesto, APU y gestión de obra para arquitectos, contratistas y propietarios. Desarrollador único. Mercado inicial Bariloche, Zona B UOCRA.

Freemium: Free ve datos y composiciones pero **no la estructura de precios** —la cascada de Factor K—; PRO edita rendimientos, permuta materiales, edita impuestos, usa el importador y ve el desglose completo.

## 1 · Fortalezas — lo que no hay que romper

**El diferencial está bien elegido.** Gestión de Obra y certificación es territorio vacío. Sismat es una calculadora de presupuesto sin certificación; los marketplaces son catálogo de precios; OneEstimate genera APU con IA pero no cierra el ciclo. Nadie cierra presupuesto → certificación → ajuste por CAC.

**El Factor K es el activo intelectual.** Seis conceptos en cascada con verificación de cierre. El criterio del split en la vista sin materiales —GG, EPP y Costo Financiero fijos por ser estructura de empresa; Imprevistos y Beneficio recalculados por variar con riesgo y margen— es criterio profesional real, no una fórmula copiada.

**La metodología es sólida.** Decisiones primero, lista de archivo y línea aprobada antes de escribir, sin reescrituras de bloque, commit solo de lo verificado.

**Los datos son reales.** Costos UOCRA desde el convenio con cargas reales. Cinco proveedores de Bariloche, 273 precios normalizados a unidad de uso, **175 insumos todos con precio**, duplicados unificados. 770 ítems de composición de una obra real. Catálogo regional genuino.

**Decisiones validadas por el mercado.** Precios a contado y sin flete, con el flete al geolocalizar. Los tres agregadores argentinos de 2026 llegaron a lo mismo por su cuenta.

**Y trabajo de fondo resuelto.** Ciclo de certificación cerrado. Importador Excel funcionando. Parser numérico argentino con 24 casos. Llamadas paralelizadas con timeout global. Reordenamiento con indexación fraccionaria. Soft-delete en cascada.

## 2 · Debilidades

### 2.1 · Certificación subfacturando — LA MÁS GRAVE

Los certificados se calculan sobre **costo desnudo**: sin gastos generales, imprevistos, beneficio ni impuestos.

`calcular_monto_obra_subitems` sigue llamando a la función sin cascada, y de ahí cuelga todo lo monetario de Gestión de Obra. Se conectó el 2 de septiembre a lo único que existía y nadie la actualizó cuando se construyó el Factor K.

**No es un bug de cálculo cualquiera: le hace perder plata al usuario sin que se entere.** Es la peor categoría de error en un producto de costos.

Confirmado por Seba el 8 de septiembre: el certificado tiene que facturar el precio final con la cascada completa.

Dato que reduce el alcance del arreglo: la vista previa y la emisión comparten la misma función, así que no hay una segunda cuenta divergente. El problema está solo en la raíz.

### 2.2 · Los parámetros UOCRA tienen 8% de error conocido

ART al 10,23% es un placeholder sin verificar contra póliza. FCL al 12% es conservador. Horas por mes en 176 contra 190,67 reales.

**La mano de obra es la mitad del presupuesto.** Un profesional que compare contra su número y vea 8% de diferencia no vuelve, y no avisa por qué se fue.

### 2.3 · El .ods es un punto único de falla

`PLANILLA_BASE_2_0_v3_CORREGIDA.ods` contiene el criterio del split de Factor K, que **no está en ningún `.md` del repositorio.**

Y la fórmula de "MANO DE OBRA TOTAL (A)" apunta cinco filas de más, confirmado en dos partidas sobre 97 sin auditar.

### 2.4 · Sin tests sobre el motor de cálculo

Hay 24 casos para el parser de números, que es la parte determinista y fácil. **La cascada, el prorrateo, el presupuesto vivo y la certificación no tienen tests de regresión.**

En un producto cuyo valor entero es que la aritmética esté bien, los tests están en el lugar equivocado.

### 2.5 · Deriva entre repositorio y base — ya no es teórica

Las migraciones se escriben en un lado y se aplican a mano. Con 93 acumuladas, no hay forma de verificar que el esquema de producción coincide con el del repositorio.

**Dejó de ser incertidumbre:** el 9 de septiembre la 0091 ya estaba aplicada cuando fuimos a correrla, y la 0089 quedó reemplazada por la 0090 sin saber si llegó a aplicarse.

### 2.6 · Sin telemetría ni reporte de errores

No hay forma de medir activación, retención ni dónde abandona el usuario. Las métricas de compuerta definidas en la estrategia comercial hoy no se pueden medir.

Y con un motor de cálculo, el problema no es que haya un bug: es no enterarse. Un cálculo mal puede correr semanas sin que nadie lo reporte.

### 2.7 · Densidad de información en pantalla chica

La solapa APU tiene cinco columnas más equipos más la cascada. Ya apareció en el HONOR X7b con fuente grande y costó tres intentos resolverlo.

La verificación se hace en dos dispositivos de pantalla razonable; la fragmentación real de Android incluye pantallas más chicas.

### 2.8 · Pantalla vacía en el primer uso

El usuario nuevo entra y no ve nada. Sismat precarga modelos de 80, 120 y 200 m², y esa es probablemente su mejor jugada de producto.

### 2.9 · Sin papelera ni archivado de obras

Hay soft-delete para rubros y subítems del usuario, pero no para obras, y no se puede editar la metadata. No poder deshacer se percibe como riesgo de perder trabajo, y frena la carga de la segunda obra.

### 2.10 · Solo Android y web

Entre arquitectos la penetración de iPhone es alta, y entre propietarios más todavía. No es urgente en Bariloche, pero define un techo de mercado.

## 3 · Riesgos

### 3.1 · La obra no tiene señal — EL MÁS SERIO

Gestión de Obra se usa parado en la obra. Bariloche, pendiente, sin cobertura. Hoy la app es Supabase con timeout de 15 segundos: sin datos no hace nada.

**El módulo que constituye el diferencial es exactamente el que se usa donde no hay conectividad.** Si medir avance requiere señal, el profesional vuelve al papel y transcribe después — y ahí ya perdió contra el cuaderno.

No se arregla tarde porque **condiciona el modelo de datos.** Mínimo viable: lectura offline de la obra activa y cola de escritura para el avance.

### 3.2 · La superficie RLS crece más rápido que la capacidad de revisarla

La 0085 corrigió `calcular_factor_k_subitem`, que no verificaba pertenencia y exponía el Factor K entre usuarios distintos.

**No fue mala suerte: fue el primer caso visible de una clase de bug que se reproduce con cada RPC nuevo.** Hace falta un checklist obligatorio por RPC y prueba sistemática con dos usuarios.

### 3.3 · La clave anónima viaja en el APK

El manejo por `--dart-define-from-file` evita el hardcodeo, pero el APK igual la contiene. **Toda la seguridad descansa en RLS**, sin segunda línea de defensa. Eso agrava el 3.2.

### 3.4 · La spec de roles combinables no está escrita

`obra_members`, invitaciones y permisos están pausados esperando reconstruirla: una persona con varios roles, vinculaciones por pares, autogestión.

Se discutió con Gemini y nunca se escribió. **Mismo problema que el split de Factor K viviendo solo en la planilla.** Y bloquea el plan Estudio.

### 3.5 · Histórico de precios: VERIFICADO 2026-09-09 — pisa, no existe serie histórica todavía

No se pudo verificar consultando la base (cada precio tiene una sola fila porque se cargó una sola vez — no hay caso donde ya se haya pisado un cambio real). Se verificó revisando el código y las 93 migraciones: **la tabla `precios` no tiene ningún camino de escritura desde la app** — cero código en `lib/` la toca. Las 221 filas actuales se cargaron a mano por migración SQL (0058-0086), corralón por corralón.

**El problema está en cómo se escriben esas migraciones, no en la app.** Cada vez que hubo que corregir un precio ya cargado (0066, 0068, 0069, 0070, 0083, 0086), se hizo `UPDATE precios SET valor = X` — el valor anterior se pierde en el mismo statement. Dos de esas migraciones (0068, 0083) encontraron filas duplicadas para el mismo (insumo, corralón) y las promediaron y borraron, tratándolas como ruido de importación — por lo que se pudo reconstruir de los comentarios, eran duplicados de una fusión de insumos sinónimos (0066), no historia real perdida, pero el criterio usado destruiría una serie histórica genuina si existiera.

**No hace falta tocar el esquema** — no hay ningún `UNIQUE (insumo_id, corralon_id)` en `precios`, nada impide insertar una segunda fila con fecha nueva hoy mismo. Lo que sí hace falta, y es más de lo que parece: cuatro funciones activas hoy hacen `avg(valor) from precios where insumo_id = X` sin filtrar por fecha ni por fila más reciente por corralón — `calcular_composicion_detalle_subitem` (Factor K/APU), `calcular_precio_apu_subitems` (certificación), `consolidado_insumos_obra` (Mat y MO) y `calcular_precio_promedio_insumo` (sin uso en vivo). Empezar a insertar filas nuevas sin tocar las cuatro en el mismo golpe contamina el precio "automático" de toda la app con precios viejos, en silencio. Falta además un criterio para distinguir "el corralón cambió el precio" (amerita fila nueva) de "corregimos un error de tipeo/unidad, nunca fue un precio real" (amerita seguir corrigiendo en el lugar) — hoy no existe esa marca, y sin ella la próxima limpieza de duplicados puede repetir el mismo problema.

Detalle completo en `docs/relevamiento_sincronizacion_config_precios.md` (Hallazgo #6, actualizado). **La serie histórica de Bariloche todavía no existe — pero tampoco se perdió nada real hasta ahora, según lo que se pudo reconstruir.** El punto 6 del orden de ejecución (tests de regresión de la cascada) es buen momento para meter este cambio junto, porque toca las mismas cuatro funciones.

**Criterio decidido, sin el cual lo de arriba no es viable:** el corralón cambió su precio real → fila nueva con fecha nueva (`INSERT`). Corregimos un error nuestro —conversión de unidad, tipeo, precio del paquete cargado como si fuera el de la unidad de uso— → se corrige en el lugar (`UPDATE`), nunca fue un precio real. Sin esta distinción escrita, la próxima limpieza de duplicados repite el mismo patrón que 0068/0083 y vuelve a borrar historia sin poder distinguirla de ruido de importación. Detalle en el relevamiento, Hallazgo #6.

### 3.6 · El importador está del lado equivocado del muro

La barrera número uno de adopción es que todo profesional ya tiene su Excel. El importador es lo que la elimina.

**Tenerlo detrás de PRO es cobrarle a alguien por permitirle entrar.** Que importe, vea sus datos adentro, y recién ahí se le cobra Factor K y certificación.

Recomendación: moverlo a Free con límite de filas u obras. **Contradice la decisión del 8 de septiembre**, así que va como propuesta a evaluar, no como cambio.

### 3.7 · Encierro de datos

Un profesional no carga tres obras en una app de la que no puede sacar nada. Exportar a Excel parece regalar el trabajo, pero es al revés: **el que puede exportar no se va.**

### 3.8 · Multimoneda y cotización BNA

La actualización automática con aviso ante variación mayor al 5% está pendiente. Una obra en dólares certificada con cotización vieja reproduce el mismo error que la certificación sin Factor K: el usuario pierde plata sin enterarse.

### 3.9 · Rama única

Sirve con un solo desarrollador y ningún usuario. Con 50 usuarios y un bug de cálculo en producción, no hay forma de hacer un arreglo urgente teniendo algo a medias en el árbol.

### 3.10 · El presupuesto emitido es un documento comercial

Cuando alguien lo firme y se lo entregue a un cliente y el número esté mal, la discusión no va a ser técnica. Términos y condiciones, límite de responsabilidad y leyenda de precios de referencia con fecha, antes del primer usuario pago.

### 3.11 · Datos personales de terceros

La app guarda datos de los clientes del profesional. Cae bajo la Ley 25.326. No urge con diez usuarios; sí antes de cobrar.

### 3.12 · Bundle ID sin renombrar

**No se puede cambiar después de publicar en Play.** Publicar con el provisorio obliga a crear una app nueva, perdiendo instalaciones, reseñas e historial.

### 3.13 · Bloqueo geográfico

Solo Zona B cargada, sin selector. Impide distribuir fuera de Neuquén, Río Negro y Chubut. La Pampa sin resolver.

### 3.14 · Pruebas de PRO inválidas

El botón Free/PRO del dashboard es cosmético a propósito. Las pruebas de gating hechas con él no son válidas: la verificación real exige edición manual en base.

### 3.15 · Concentración en una persona

Sin mitigación real, pero con paliativo: **que todo el criterio profesional esté escrito.** Hoy la parte más valiosa vive en una planilla y en la cabeza del fundador.

## 4 · Hallazgos del relevamiento de sincronización — 9 de septiembre

De `docs/relevamiento_sincronizacion_config_precios.md`. Todos del mismo patrón: una pieza se construyó apuntando a lo que existía, eso cambió, y nadie revisó qué quedó apuntando a lo viejo.

**Clave foránea sin acción de borrado en `certificado_subitems_avance.obra_subitem_id`.** Si una partida ya tiene avance certificado, borrarla choca. Mismo síntoma que los dos casos ya arreglados el 9 de septiembre. Confirmado por inspección, no reproducido.

**El diálogo de ajuste económico sigue escribiendo `obras.monto_total`** con una conversión estática, la misma columna que la 0091 dejó de usar como fuente de verdad. Hoy no se nota porque nadie la relee, pero es el patrón exacto del bug original.

**El interruptor `aplica_cac` es cosmético.** Su propio texto dice que ajusta el presupuesto por el índice CAC, y no existe código que lo haga. **Mismo caso que el interruptor de impuestos**, que guardaba bien y ningún cálculo lo miraba.

**`tipo_suelo` y `zona_sismorresistente`** no los lee ni los escribe nadie. A diferencia del resto, nunca se conectaron.

**La fórmula de precio promedio está duplicada** en una función y en línea. No diverge hoy, pero es el tipo de riesgo que ya mordió dos veces.

**Verificado y correcto:** el bloque completo de costo de mano de obra con sus 14 columnas, el tipo de presupuesto y el interruptor de impuestos, el contador de partidas por rubro, y las tres claves foráneas de rubros que importaban.

## 5 · Backlog funcional

**Bloqueantes o casi:** selector de zona UOCRA; conectar el costo laboral a la vista consolidada con el tercer origen "calculado"; selector de hormigón elaborado o in situ; actualización de cotización BNA.

**Segunda ola:** dos modelos de certificación, A por avance medido y B por hitos; modo certificado externo; registro de subcontratos; papelera y archivado; edición de metadata de obra.

**Y el motor de precio de referencia por m² y zona**, que no es solo una función: es el insumo del Índice de Costos Patagonia, el principal canal de adquisición de la etapa 1. Vale más de lo que su posición sugiere.

**Importador de PDF y foto** con prellenado asistido por IA, distinto del importador de Excel ya construido. Necesita decidir proveedor de IA y tiene costo por documento.

## 6 · Orden de ejecución

1. **Corregir la certificación** aplicando la cascada a los montos certificados. Diagnóstico
   previo en `docs/certificacion_correccion_diagnostico.md`. **Migración escrita 2026-09-09**
   (`supabase/migrations/0094_certificacion_usa_precio_final.sql`): cambia
   `calcular_monto_obra_subitems` para usar `calcular_precio_final_apu_subitems`, y fuerza el
   recálculo de cualquier borrador con avance ya cargado (decisión: la migración lo resuelve sola,
   no queda para avisar y tocar a mano). El único borrador de prueba existente (Obra de Prueba,
   certificado N°1, 3 filas) se borra antes de aplicar. Falta correr y verificar.
2. ~~Verificar INSERT contra UPDATE en el histórico de precios.~~ **VERIFICADO 2026-09-09 — pisa, ver §3.5.** Pendiente real que queda: cambiar la práctica de escritura de las migraciones de precio a INSERT con fecha nueva, y ajustar las 4 funciones que promedian `precios.valor` para que tomen la fila más reciente por corralón. Se puede meter junto con el punto 6 (tocan las mismas funciones).
3. **Auditar el .ods**: la fórmula corrida cinco filas en las 97 partidas, y extraer el criterio del split hacia `CLAUDE.md`.
4. **Escribir la spec de roles combinables.**
5. **Verificar ART y horas por mes** contra póliza y convenio reales.
6. **Tests de regresión de la cascada**, con dos o tres obras de referencia y totales esperados. Es lo que después permite tocar el motor sin miedo.
7. **Telemetría mínima y reporte de errores.**
8. **Selector de zona UOCRA.** Sin esto no hay mercado fuera de Zona B.
9. **Estrategia offline** para la obra activa.
10. **Obra tipo precargada** de 80 o 120 m², para que el primer uso muestre un presupuesto completo.
11. **Calidad del PDF de salida.** Es lo único que ve el cliente del profesional, lo que circula por WhatsApp, y la mejor publicidad del producto.

## 7 · La regla que ordena todo

**No agregar módulos nuevos hasta terminar el punto 6.**

La tentación con un producto que tiene tanto diseño acumulado sin implementar es seguir diseñando. **El riesgo real no es que falte funcionalidad: es que la que ya existe entregue un número equivocado.**

---

## Nota sobre este documento

El original venía de otra conversación y decía que el Factor K estaba "cero conectado a Dart/UI" y que la solapa APU era "enteramente mock". **Eso era cierto hasta el 6 de septiembre y dejó de serlo.**

Entre el 7 y el 9 se conectó la cadena completa: el listado de la solapa APU, el bloque de Factor K con montos reales, el precio con cascada en Cómputo, y el total del dashboard derivado del cómputo. Verificado en emulador con la obra Galpón Mix.

Actualizá este documento cuando algo cambie, en vez de dejarlo envejecer.
