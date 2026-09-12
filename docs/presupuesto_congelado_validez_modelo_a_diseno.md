# Congelamiento del presupuesto y validez (Modelo A) — diagnóstico, sin migraciones todavía

Punto 3 del corte de `docs/indices_cac_cotizacion_dolar_diseno.md` (§4/§8), el que ese documento
ya dejaba anotado como "la pieza siguiente, no un algún día": sin esto, `factor_cac_obra` está
construido y conectado al Modelo B, pero el Modelo A — el que usa Seba — no tiene contra qué
aplicarlo, porque `calcular_presupuesto_vivo_obra` (`0091`) recalcula en vivo desde los precios de
insumos de hoy, nunca es una foto de cuando se presentó el presupuesto.

**Estado de este documento: las 5 ambigüedades de la sección 10 quedaron cerradas con el usuario
(respuestas incorporadas más abajo). Las 2 migraciones (`0103`/`0104`) quedaron escritas — sin
aplicar ni verificar en Supabase todavía.** Sigue el mismo criterio que ya usó este proyecto para
Modelos A/B y Ciclo de vida del Certificado: doc primero, ambigüedades cerradas con el usuario,
migración por migración después.

## 1. Confirmación del diagnóstico central (releído contra el código real)

- `calcular_presupuesto_vivo_obra` (`0091_presupuesto_vivo_obra.sql`) — suma cantidad × precio
  final de cada partida tildada, con la cascada completa de Factor K
  (`calcular_precio_final_apu_subitems`, `0090`). Recalcula en cada llamada, contra los precios
  vigentes de `insumos`/`obra_insumo_precios`. No hay ningún estado de obra que lo convierta en
  una foto — confirmado, no existe ninguna columna `obras.presupuesto_*` ni tabla de snapshot hoy.
- `emitir_certificado` (`0011` → `0055`) sí congela — pero congela el **certificado**, no el
  presupuesto: `certificados.monto` queda fijo desde que se emite. No ayuda acá porque lo que hace
  falta es un monto pactado contra el que restar lo certificado, no otro monto certificado más.
- No existe hoy ningún estado de obra equivalente a "presentado" o "contrato firmado" —
  confirmado, `obras` no tiene ninguna columna de ese tipo, y no hay ninguna función que registre
  ese evento. Este documento tiene que proponerlo desde cero, no está extendiendo algo a medio
  construir.
- El Modelo B no tiene este problema porque ya tiene un monto congelado real por otra vía:
  `obras.monto_total_contratado` (fijo desde que se carga, `0008`) y cada hito
  `'finalizado'` es inmutable (`0006`). `calcular_saldo_pendiente_hitos` (`0102`) ya resta hitos
  finalizados de ese monto fijo. El diseño de abajo es, a propósito, el mismo patrón trasladado al
  Modelo A — con la diferencia real de que acá el monto no es uno solo, es por partida.

## 2. Dos eventos de negocio distintos, no uno

Dos momentos que hoy no existen como estado de la obra, y que hay que distinguir con cuidado
porque tienen efectos distintos:

1. **Presentar el presupuesto** — el presupuesto sigue vivo/recalculable (todavía se puede
   renegociar), pero arranca a correr su validez. No congela nada todavía.
2. **Firmar el contrato (o dar el anticipo, si no hay contrato)** — acá sí se congela: cantidad y
   precio final de cada partida tildada quedan fijos desde ese momento.

Entre uno y otro puede pasar tiempo (la negociación), y el presupuesto puede vencer en el medio —
por eso la validez cuelga del evento 1, y el candado de "no dejar firmar vencido" se chequea en el
evento 2.

## 3. Validez del presupuesto

**Columnas nuevas en `obras`** (propuesta, sin migración escrita):
- `presupuesto_fecha_presentacion` (timestamptz, nullable — null mientras nunca se presentó)
- `presupuesto_validez_dias` (int, sugerido 30, editable por obra)

Vencimiento = `presupuesto_fecha_presentacion + presupuesto_validez_dias` — no hace falta guardarlo
como columna aparte, se calcula.

**Dónde vive la acción "presentar"**: hoy no existe ningún flujo de enviar/imprimir el presupuesto
en la app (grep confirma: ni PDF ni exportación de presupuesto en `lib/`, solo de certificados —
`docs/obras_papelera_archivado_exportacion.md` ya tenía la exportación anotada como pendiente, sin
implementar). No hay un botón existente donde "colgar" el cartel de validez.

Propongo una acción nueva y explícita — **"Presentar presupuesto"**, en `presupuestos_screen.dart`
(donde ya se ve el total vivo) — que:
1. Muestra el cartel de validez (30 días sugeridos, editable) **antes** de confirmar — nunca un
   valor por defecto que nadie miró, como pediste.
2. Al confirmar, guarda `presupuesto_fecha_presentacion = now()` y el `presupuesto_validez_dias`
   elegido.

Es la misma función tanto para la primera presentación como para "Actualizar" un presupuesto
vencido (§4) — actualizar es literalmente volver a presentar, con los precios de hoy (que
`calcular_presupuesto_vivo_obra` ya da) y una validez nueva. Cuando el día de mañana se construya
exportar/enviar el PDF real, ese flujo dispara la misma función en vez de inventar un segundo
mecanismo.

## 4. Qué pasa cuando vence

Se chequea en dos lugares distintos, con dos comportamientos distintos:

- **Al abrir el presupuesto (solo mirar)**: si `now() > vencimiento` y la obra todavía no está
  congelada, banner persistente ("vencido hace N días") con botón "Actualizar" → llama la misma
  acción de presentar (§3), recalcula con precios de hoy, resetea la validez. No bloquea nada,
  mismo criterio de "aviso, no candado" que ya se usó para `CartelFirmaPendiente`
  (`docs/certificados_ciclo_vida_diseno_datos.md` §11) — que sea persistente y no plegable importa
  acá tanto como allá, mismo motivo: que el cansancio no termine ganándole.
- **Al firmar (congelar, §5)**: si está vencido, la función de congelamiento **rechaza** con una
  excepción — no deja avanzar hasta actualizar primero. Acá sí es candado duro, no aviso, porque
  es la protección real contra firmar a un precio de hace tres meses.

## 5. El congelamiento — qué se congela

**Confirmando tu presunción del punto 1, con una corrección**: por partida tildada (`obra_subitems`
con `es_aplicable = true`), se congela **cantidad y precio final** de ese momento — eso sí, tal
cual lo planteaste. La corrección es sobre Factor K/impuestos:

**No hace falta guardar los porcentajes de Factor K/impuestos aparte para que "el presupuesto
firmado no se mueva"** — si lo que se congela es directamente `precio_final` (el número ya
resuelto, después de aplicar toda la cascada), ese número no depende de que nadie vuelva a leer
`obra_presupuesto_config`/`obra_impuestos` después. Cambiar el % de Beneficio de la obra el mes que
viene no toca una fila ya guardada, se mire o no se guarde el % en sí.

Dicho esto, **guardar los porcentajes igual tiene valor real, y sale gratis**: `calcular_factor_k_subitem`
ya los expone en la misma llamada que da `precio_final` — no es una consulta aparte. Sirve para
poder mostrarle al Constructor/Cliente "con qué Beneficio/GG se firmó este presupuesto" (útil el
día que haya un PDF de salida, y para una discusión eventual), y para poder auditar si alguna vez
un número congelado parece no cerrar. **Lo marco como decisión abierta, no cerrada — ver
ambigüedad A.**

**Lo que sí propongo guardar aparte, y no es solo para transparencia sino que hace falta para el
punto 5 de `docs/indices_cac_cotizacion_dolar_diseno.md`**: `costo_costo` y `materiales_subtotal`
de cada partida (ambos ya calculados por `calcular_factor_k_subitem`, sin costo extra). El diseño
de CAC ya anotaba que el split materiales/mano de obra tenía que vivir "por partida" en este
snapshot para poder usar `factor_cac_obra(obra, 'materiales')` y `factor_cac_obra(obra,
'mano_obra')` por separado — si no se guarda ahora, se pierde el dato de origen y el día de mañana
habría que reconstruirlo a partir de una composición de APU que para entonces ya pudo haber
cambiado. Guardarlo ahora no conecta el CAC (eso sigue para después, tal como pediste), solo evita
tener que recalcular con datos viejos cuando llegue ese momento.

## 6. Dónde vive el congelamiento

**Dos tablas nuevas**, no columnas en `obra_subitems`. Descarté guardarlo directamente en
`obra_subitems` por un motivo concreto: esa tabla sigue siendo el cómputo **vivo** (se sigue
editando después de firmar, vía `modificaciones_obra` para adicionales/demasías/quitas —
mecanismo que ya existe). Si el snapshot fueran columnas ahí mismo, cualquier corrección posterior
de `cantidad` pisaría el valor congelado sin querer. Con tablas aparte, `obra_subitems` sigue
siendo "qué hay tildado hoy" y lo nuevo pasa a ser "qué se firmó", sin que una edite a la otra —
mismo patrón que ya usa el proyecto para `certificado_subitems_avance` apuntando a `obra_subitems`
en vez de al catálogo.

**`presupuesto_subitems_congelado`** — una fila por partida congelada: `obra_subitem_id`,
`cantidad`, `monto_total` (el número que realmente importa, mismo nombre que ya usa
`calcular_monto_obra_subitems` a propósito — ver §9), y `precio_final`/`costo_costo`/
`materiales_subtotal` (§5), nullable porque solo aplican a partidas con APU. `unique(obra_id,
obra_subitem_id)` — un recongelamiento (ambigüedad C, cerrada a favor de permitirlo) borra el
snapshot entero y lo vuelve a armar, no hace un `upsert` fila por fila.

**`presupuesto_config_congelado`** — corrección sobre el planteo original de este documento: los 6
porcentajes de Factor K (ambigüedad A, cerrada a favor de guardarlos) **no van repetidos en cada
fila de `presupuesto_subitems_congelado`** — son configuración de la obra
(`obra_presupuesto_config`, 1:1, `0020`), la misma para todas sus partidas. Van en una tabla aparte,
también 1:1 con la obra: los 6 % más `impuestos_pct_total` (la suma plana de `obra_impuestos` al
momento de congelar, sin desglose por tipo — eso quedó fuera de la ambigüedad A) y
`tipo_presupuesto` (qué vista, con/sin materiales, estaba activa).

`obras` gana además `presupuesto_congelado_en` (timestamptz, null = todavía no congelada — este es
el campo que responde la pregunta 3) y `presupuesto_congelado_por`. Viven en `0103`, no en `0104`,
porque `presentar_presupuesto_obra` ya necesita `presupuesto_congelado_en` para su propio guard de
re-presentación (§10, ambigüedad C).

**Convivencia con `calcular_presupuesto_vivo_obra`**: no se toca, sigue funcionando exactamente
igual — de hecho pasa a tener un segundo uso después de congelar, ver punto 8. Antes de congelar
sigue siendo el único número que existe (como hoy). Después de congelar, el monto "pactado" ya no
sale de ahí, sale de sumar `presupuesto_subitems_congelado.precio_final` — pero el motor en vivo no
se apaga ni se reemplaza.

**Función nueva para el saldo pendiente**, mismo patrón que `calcular_saldo_pendiente_hitos`
(`0102`) pero por partida: para cada fila congelada, `precio_final × (100 −
calcular_avance_acumulado_subitem(obra_subitem_id)) / 100`, sumado — el índice CAC se multiplicaría
acá cuando se conecte (fuera de alcance ahora), exactamente como pediste: **el ajuste corre sobre
el saldo, nunca sobre el total ni sobre lo ya certificado**, mismo principio que el Modelo B.

## 7. Obras existentes (cómputo cargado, certificados ya emitidos)

**No hace falta ningún backfill.** `presupuesto_congelado_en` nace `null` para toda obra
existente — arrancan exactamente como hoy: `calcular_presupuesto_vivo_obra` sigue siendo el único
número, la certificación sigue el camino que ya tiene (con el bug conocido de §9, sin relación
directa con esta pieza). Nada se rompe porque nada obliga a pasar por el congelamiento — es
estrictamente aditivo.

Si en algún momento se quisiera que una obra real en curso empiece a usar el mecanismo, el camino
sería presentar + congelar manualmente sobre el cómputo actual — con una salvedad real que hay que
decir en voz alta: eso congelaría el cómputo de **hoy**, no el que se pactó originalmente (que no
quedó registrado en ningún lado porque este mecanismo no existía). Es una aproximación aceptable
para arrancar, no una reconstrucción fiel del presupuesto original. Marcado como ambigüedad D si
hace falta resolver esto con más cuidado para alguna obra puntual.

## 8. Cómo se ve la diferencia

Una vez congelada, conviven dos números:
- **Pactado**: suma de `presupuesto_subitems_congelado.precio_final` (o, para el saldo, la función
  de §6).
- **Hoy**: `calcular_presupuesto_vivo_obra` de siempre, sin cambios — recalculado contra insumos
  actuales.

Tiene sentido mostrar los dos, coincido con tu lectura — es la única forma de que el Constructor
vea el desfasaje sin tener que hacer la cuenta a mano. Propongo Gestión de Obra (donde ya se ve el
avance/certificación) como lugar principal, con un chip simple "Pactado $X · Hoy $Y ·
desfasaje +Z%" — no un gráfico ni nada más elaborado por ahora. No lo doy por decidido, es una
recomendación: el `alcance` que marcaste deja esto fuera de lo obligatorio de este corte, así que
puede quedar señalado y no construido si preferís.

**Actualización 2026-09-12 — de opcional a necesario, y en el dashboard, no en Gestión de Obra.**
El origen real: `ObrasListScreen` mostraba el "Monto Estimado Base" de una obra congelada sin
ninguna aclaración, así que un usuario lo leía como el pactado — exactamente la confusión que este
párrafo ya anticipaba, pero en la pantalla equivocada (acá se proponía Gestión de Obra, que sí tiene
el desglose Pactado/Saldo pendiente desde `cac_conectado_modelo_a_diseno.md` §4, pero el dashboard,
donde vive la confusión real, había quedado sin tocar — ver §12, "no tocados").

Cerrado por Seba: el dashboard tiene que decir explícitamente que ese monto es el de HOY, y el chip
Pactado/Hoy/Desfasaje pasa a ser obligatorio ahí, no opcional. Primera implementación (2026-09-12,
misma sesión): rótulo "Valor de HOY (no es el pactado)" + chip "Pactado $X · Hoy $Y · Desfasaje
±Z%" comparando contra `calcular_presupuesto_vivo_obra`.

**Corrección el mismo día, antes de aplicar nada (Seba, revisando el resultado): el número
principal se invierte.** *"Una vez pactado, el número de la obra es el pactado... el precio de la
obra debe ser en grande el que se pactó, por más que se quiera jugar con las opciones de APU."* La
primera implementación dejaba el vivo como número grande -- exactamente lo que este documento (§8)
nunca pidió; el pactado es el que tiene que ir en grande, sin rótulo que lo relativice, y el "Hoy"
pasa a ser la referencia de abajo, junto con el desfasaje.

**Y un bug real que esa revisión destapó**: el "Hoy" del chip venía de
`calcular_presupuesto_vivo_obra`, que recalcula con la configuración VIGENTE de Factor K
(`obra_presupuesto_config`/`obra_impuestos` -- los interruptores de la Solapa APU), no con la que
regía al congelar. Caso real: obra congelada con impuestos aplicados (25,5%), interruptor de
impuestos apagado después -- el chip mostraba 20,3% de desfasaje que no existía, era pura
diferencia de configuración. Corrección en `0110_presupuesto_hoy_config_congelada.sql`: nueva
función `calcular_presupuesto_hoy_config_congelada_obra`, que reutiliza `calcular_factor_k_subitem`
(ahora con un parámetro `p_config_congelada`, sin duplicar la cascada -- mismo criterio que ya fijó
0090) leyendo `presupuesto_config_congelado` en vez de la configuración vigente. Detalle completo
en el comentario de esa migración.

**Estado final de la card, obra congelada:**
- Número grande: **Pactado**, sin aclaración (ícono de candado chico, nada más).
- Debajo: "Hoy $Y · Desfasaje ±Z%", calculado con la MISMA configuración congelada -- mide
  únicamente el costo de insumos de hoy, nunca un cambio de interruptor.
- Fallback (pactado no pudo cargarse -- fallo de red puntual): vuelve al vivo con su aclaración
  ("Valor de HOY, pactado no disponible") -- nunca un número sin decir qué es.
- Aviso descartable (primera vez, SharedPreferences por obra, mismo mecanismo que la zona UOCRA de
  `CartelCostoManoObra`) explicando qué mide el desfasaje, para no volver a generar la misma
  confusión que esta sección documenta.

## 9. Cierre — el cruce con la certificación (ambigüedad E)

**Cerrado por vos**: el presupuesto congelado es el número contra el que hay que certificar — "se
certifica avance sobre el precio pactado, no sobre el de hoy, ese es todo el sentido de
congelarlo".

Con eso confirmado, apareció una precisión sobre el estado real de la `0094` que hacía falta
anotar: `0094_certificacion_usa_precio_final.sql` (aplicada el 2026-09-08/09) ya había corregido
el bug más grave — certificar contra costo puro, sin la cascada de Factor K
(`docs/certificacion_correccion_diagnostico.md`) — pero apuntando `calcular_monto_obra_subitems` a
`calcular_precio_final_apu_subitems`, que recalcula **en vivo**. Para una obra congelada, eso
certificaría contra los precios de insumos del día de la certificación, no contra el precio
pactado al firmar — exactamente lo que este congelamiento existe para evitar. La `0094` quedó
incompleta, no equivocada: en su momento no existía ningún concepto de obra congelada contra el
cual comparar.

**Resuelto en esta misma pieza (`0104`), no separado**: `calcular_monto_obra_subitems` bifurca por
`obras.presupuesto_congelado_en` — obra congelada lee `presupuesto_subitems_congelado.monto_total`
directo, sin recalcular nada; obra sin congelar sigue exactamente igual que la `0094`, sin
cambios de comportamiento para ninguna obra que no pase por este mecanismo. Detalle completo en el
comentario de esa migración, sección "Cierre del cruce con la 0094".

## 10. Ambigüedades — cerradas con el usuario

**A. ¿Guardar los 6 % de Factor K + impuesto total, o alcanza con `precio_final` ya resuelto (§5)?**
**Cerrado: sí, guardarlos** (Opción 2). Palabras de Seba: "dentro de un año, cuando alguien
pregunte con qué beneficio se firmó esa obra, el número está". El detalle de impuestos por tipo
(no solo el total) queda afuera hasta que haya un caso concreto que lo pida. Implementado como
tabla aparte 1:1 con la obra, no repetido por partida — ver la corrección de criterio en §6.

**B. Autoridad para presentar/congelar.** **Cerrado: `admin_maestro` o `profesional` para las dos
acciones** (Opción 1), mismo par que ya edita `obra_subitems` (`0019`). Palabras de Seba: "el
profesional es el que arma el presupuesto, así que tiene que poder firmarlo".

**C. ¿Se puede volver a congelar una obra ya congelada?** **Cerrado: sí, mientras no haya ningún
certificado que dejó de ser borrador** (Opción 2) — en contra de mi recomendación original de no
permitir nunca recongelar. Palabras de Seba: "entre firmar y empezar a certificar puede pasar una
semana, y obligar a cargar un error de tipeo como adicional es una vuelta larga por algo que no lo
amerita... mientras no se certificó nada, no hay nada que proteger". Un recongelamiento reemplaza
el snapshot entero (`presupuesto_subitems_congelado` + `presupuesto_config_congelado`), no hace un
ajuste fila por fila.

**D. Obras existentes que quieran adoptar el mecanismo a mitad de camino (§7).** **Cerrado:
alcanza con "congelar el cómputo de hoy tal cual está"** (Opción 1) — no tiene sentido reconstruir
presupuestos viejos que nunca quedaron registrados. Sin carga manual aparte para esos casos.

**E. El cruce con el bug de certificación sin Factor K.** **Cerrado: sí, se certifica contra el
congelado, resuelto en esta misma pieza** — ver §9.

## 11. Tamaño de la pieza — evaluación pedida

No resulta más grande de lo que parecía, pero tiene más partes de las que el pedido original
nombraba explícitamente: además de congelamiento + validez + aviso, hace falta construir desde
cero la noción de "presentar" (hoy no existe ningún estado de obra parecido, ni ningún flujo de
envío/impresión al que engancharse — §3) y la función de saldo pendiente equivalente a la del
Modelo B (§6). Ninguna de las dos es una pieza aparte real — son dependencias directas de lo que
pediste, no alcance agregado — pero las nombro para que la lista de archivos de abajo no aparezca
sin explicación.

## 12. Archivos

**Nuevos, Supabase — escritos, sin aplicar ni verificar todavía**:
- `supabase/migrations/0103_presupuesto_validez_obra.sql` — `obras.presupuesto_fecha_presentacion`/
  `presupuesto_validez_dias`/`presupuesto_congelado_en`/`presupuesto_congelado_por`, función
  `presentar_presupuesto_obra(obra_id, dias_validez)`.
- `supabase/migrations/0104_presupuesto_congelamiento_modelo_a.sql` — tablas
  `presupuesto_subitems_congelado`/`presupuesto_config_congelado` + RLS, función
  `congelar_presupuesto_obra(obra_id)`, función `calcular_saldo_pendiente_avance_medido(obra_id)`
  (§6), y el `create or replace` de `calcular_monto_obra_subitems` que cierra el cruce con la
  `0094` (§9) + el recálculo de borradores en curso (mismo paso que ya pedía la nota "PATRÓN A
  REPETIR" de la `0094`).

**Dart — hecho, `flutter analyze` limpio (50 infos preexistentes del proyecto, mismo tipo que ya
había — ninguna nueva de fondo). Sin verificar en el emulador todavía.**
- `lib/presentation/obra_detalle/tabs/presupuesto_estado_panel.dart` — nuevo. Un solo panel para
  los tres estados (sin presentar / presentado-vigente / vencido / congelado), con los botones
  "Presentar presupuesto", "Actualizar" (vencido) y "Firmar (congelar)". Terminé poniendo las tres
  acciones acá en vez de repartirlas entre `presupuestos_screen.dart` y `gestion_obra_tab.dart`
  como decía el plan original de este documento — un solo lugar, con la misma narrativa que ya
  tiene Gestión de Obra ("antes de certificar, hay que presentar y firmar el presupuesto"), en vez
  de partir la lógica entre dos archivos.
- `lib/presentation/obra_detalle/tabs/gestion_obra_tab.dart` — agrega el panel de arriba, visible
  para cualquiera (el estado es informativo para todos), con los botones ocultos solos adentro del
  panel para quien no tiene `puedeEditarComputo` (ambigüedad B).
- `lib/services/obras_repository.dart` — `getEstadoPresupuesto`/`presentarPresupuesto`/
  `congelarPresupuesto`. Sin wrapper para `calcular_saldo_pendiente_avance_medido` todavía — nada
  lo llama desde Dart, no tenía sentido agregarlo sin uso (§8, el chip Pactado/Hoy, sigue sin
  construirse — no era obligatorio).

**No tocados, a propósito**: `presupuestos_screen.dart` (el panel terminó viviendo entero en
Gestión de Obra, ver arriba); `0091_presupuesto_vivo_obra.sql` (sigue sirviendo tal cual, §6);
`obras_list_screen.dart` (el menú "Imprimir/Exportar → Presupuesto" sigue siendo el mock que ya
era — "Generando Presupuesto..." sin generar nada real — no se conectó a `presentar_presupuesto_obra`
en esta pasada; cuando exista una exportación real, ese es el lugar natural para reusar la misma
acción, tal como ya preveía este documento).
