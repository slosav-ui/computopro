# Índices externos desconectados: CAC y cotización BNA (2026-09-10)

**Estado: puntos 1 y 2 aplicados en código, sin aplicar la migración ni verificar en el
emulador. Punto 3 (congelar el presupuesto del Modelo A) es la pieza siguiente, no construida
acá.** Migración `0102_indices_cac_cotizacion_dolar.sql`.

Dos índices que la app usa (o dice usar) y que hoy están desconectados o desactualizados, mismo
tipo de problema, dos fuentes distintas — se diagnosticaron y corrigieron juntos.

## 1. El CAC no hacía nada — y el cartel mentía

`obras.aplica_cac`/`mes_base_cac` existían, pero no había ninguna tabla con valores del índice —
el interruptor guardaba bien y ningún cálculo lo miraba (mismo hallazgo ya anotado en
`docs/diagnostico_general_producto.md` §4). Peor: el texto en pantalla decía que el presupuesto
se ajustaba por CAC, sin que eso fuera cierto.

**Serie CAMARCO** (camarco.org.ar, publicada ~día 20 de cada mes con el valor del mes anterior),
tres niveles — General, Materiales, Mano de Obra — porque la app ya separa esos dos costos en
toda la cascada de Factor K, y un solo índice general le erra a los dos (en junio 2026 materiales
acumulaba 12% en el año, mano de obra 22%).

Tabla `indices_cac` (mes, general, materiales, mano_obra), cargada por migración — igual para
todos los usuarios, no tiene sentido que cada uno la traiga. Automatizar la carga (traerla del
sitio de CAMARCO) queda anotado como mejora futura, no para ahora: con pocos usuarios, cargarla a
mano doce veces al año es más confiable que un proceso que puede fallar en silencio (decisión de
Seba).

**Los 7 meses de 2026 cargados** (enero a julio): los seis que confirmó Seba directamente, más
mayo — no confirmado por Seba, buscado en fuentes públicas y citado con su fuente exacta en la
migración (nota de prensa que reproduce el comunicado de CAMARCO del 22/06/2026 con los puntos
exactos). **Sin interpolar ni inventar**: la cifra de materiales de mayo no la calculó esta
pieza a partir de la variación porcentual — es la que cita la fuente, verificada además contra
esa variación como control de consistencia, no al revés.

## 2. Bug encontrado al diagnosticar: `mes_base_cac` mentía la fecha de todas las obras

No era parte del pedido original — apareció al revisar cómo se cargaba `mes_base_cac` para poder
calcular contra él. `lib/presentation/dashboard/obras_list_screen.dart` escribía el string
literal `'Agosto 2026'` en **cada obra nueva**, sin importar la fecha real de creación — nadie lo
notó porque nada leía la columna todavía.

**Corregido de paso**: la columna pasa de `text` libre a `date` (única forma de tener algo contra
lo que calcular un cociente de forma confiable), y la creación de obra usa el primer día del mes
en curso, no un literal fijo. Como el bug siempre escribía el mismo string, la conversión de las
filas existentes es un mapeo directo y seguro (`'Agosto 2026' → 2026-08-01`), sin necesidad de
adivinar fecha por fila.

## 3. El dólar: no estaba viejo, estaba compilado

`_dolarBnaCompra`/`_dolarBnaVenta` (`ObrasListScreen`) eran `final double` **hardcodeados en el
código Dart** — no había ninguna tabla. No es que la cotización estuviera desactualizada: **solo
podía cambiar recompilando la app entera y publicando una versión nueva.**

Tabla `cotizacion_dolar_bna`, fila única (no serie histórica como el CAC — es un valor de
referencia puntual para mostrar/convertir, no una redeterminación por cociente entre dos fechas).
Se pisa con `UPDATE` cada vez que se actualiza. Valores actuales: compra 1.485, venta 1.535.
Mismo criterio que el CAC: carga manual por ahora, automatización con aviso ante variación > 5%
pendiente — ya anotada desde antes en `docs/diagnostico_general_producto.md` §3.8, sigue
pendiente, no se resuelve acá.

`ObrasListScreen` ahora carga los dos valores (cotización + último índice CAC, para la variación
mensual que se muestra junto al interruptor) al iniciar, con los mismos números como placeholder
del primer frame — silencioso en el fracaso, mismo criterio que el resto de datos secundarios de
esa pantalla (`_presupuestoVivoSeguro`).

## 4. Dónde se aplica el ajuste — la pregunta que cambió el alcance

Diagnóstico central de esta pieza, verificado contra el código, no asumido:

**Un certificado emitido congela su monto — confirmado.** `emitir_certificado` lo snapshotea a
`certificados.monto` (`0054_certificado_totales_vista_previa.sql`); nada lo vuelve a tocar
después. Esa parte de la lectura de Seba era correcta.

**Pero "saldo pendiente de certificar" no es el mismo concepto en los dos modelos:**

- **Modelo B (hitos, precio cerrado)**: `obras.monto_total_contratado` es un monto fijo, cargado
  una sola vez (`0008_ajuste_contrato.sql`), y cada hito certificado tiene su propio `monto` fijo
  e inmutable una vez `'finalizado'` (`0006_hitos_certificacion.sql`). Saldo pendiente =
  `monto_total_contratado − suma de hitos finalizados`. **Limpio, con un monto congelado real
  contra el cual aplicar el cociente.**

- **Modelo A (avance medido, la cascada de Factor K)**: no tiene ningún monto congelado
  equivalente. `calcular_presupuesto_vivo_obra` (`0091`) recalcula en vivo desde los precios
  actuales de insumos cada vez que se llama — no es una foto de cuando se presentó el
  presupuesto, es "cuánto costaría hoy". Multiplicarlo por el CAC ajustaría dos veces: una porque
  el insumo ya subió en Mat y MO, otra por el índice. Y no hay ningún monto original guardado
  contra el que calcular el cociente índice-destino/índice-origen.

  **No es un hallazgo nuevo — es la decisión de negocio del 2026-08-31 sin su mecanismo técnico
  construido.** Memoria de proyecto "precio congelado vs. recalculado": *"el precio queda
  congelado a propósito [al presentar el presupuesto]. No se recalcula nunca desde el costo real
  de los insumos... Lo que se actualiza es el coeficiente de actualización pactado de
  antemano — CAC, dólar, u otro."* El criterio ya estaba cerrado; el snapshot que lo haría
  posible, no.

  **Confirmado por Seba en esta conversación, y esto es lo que cambió el orden del corte**: el
  congelamiento del Modelo A no es una pieza aparte para "más adelante" — es el prerrequisito
  para que el CAC sirva, porque **Modelo A es el que usa.** Palabras de Seba sobre cómo funciona
  en la realidad: *"el presupuesto se confecciona con los precios oficiales a la fecha y queda
  congelado ahí. Desde ese momento, el CAC es el que actualiza los precios de la obra en curso
  mes a mes, para certificar. Mat y MO sigue su propio camino con los precios reales del mercado,
  pero eso no toca el presupuesto ya presentado. Son dos cosas separadas."*

  **Aclaración de Seba, para que quede escrita antes de diseñar el snapshot**: el índice CAC
  actualiza los precios de lo que falta ejecutar, nunca lo ya ejecutado y certificado hasta la
  fecha de ese índice — un certificado emitido quedó pago a su valor y no se toca (coincide con
  lo ya verificado arriba: `emitir_certificado` congela el monto). **El ajuste se aplica sobre el
  saldo pendiente, no sobre el total de la obra** — mismo principio que ya rige
  `calcular_saldo_pendiente_hitos` en el Modelo B (arriba: `monto_total_contratado − hitos
  finalizados`, nunca el total bruto). Cuando se diseñe el snapshot del Modelo A, el "monto
  original" congelado tiene que ser por partida (o por lo que quede sin certificar de cada
  partida), no un número único de toda la obra — para que "lo ya certificado" pueda excluirse
  partida por partida, igual que hace el Modelo B a nivel de hito.

**Consecuencia para el corte**: se construyó lo que ya es correcto hoy (tabla de índices,
cotización, conexión al Modelo B) y se deja anotado — como la pieza siguiente, no como una idea
para después — el snapshot del Modelo A que el punto 3 necesita.

## 5. Segunda pregunta — series por separado: viable, con una asimetría

La cascada de Factor K ya separa materiales de mano de obra por partida
(`calcular_factor_k_subitem` calcula `materiales_subtotal` aparte) — aplicar dos índices
distintos es viable ahí, partida por partida, y es más natural que un solo número (es
justo el modelo que va a necesitar el snapshot del punto 3: `factor_cac_obra(obra, 'materiales')`
y `factor_cac_obra(obra, 'mano_obra')` ya están listos para eso).

En el Modelo B es al revés: `monto_total_contratado` es un monto único, sin ningún split
materiales/mano de obra guardado. Aplicar los dos índices ahí exigiría inventar una proporción
que hoy no existe — por eso `calcular_saldo_pendiente_hitos` usa únicamente la serie `'general'`.
Si algún día hace falta el split en Modelo B, es una pieza de diseño aparte, no una extensión
mecánica de la función.

## 6. Tercera pregunta — sin fallback al mes anterior: hecho

`factor_cac_obra` no calcula con el mes anterior si falta el índice de origen o de destino —
`raise exception` explícito en los dos casos, con el mes que falta en el mensaje. Nunca un valor
aproximado en silencio.

## 7. Archivos

Nuevos:
- `supabase/migrations/0102_indices_cac_cotizacion_dolar.sql` — conversión de `mes_base_cac` a
  `date`, tablas `indices_cac`/`cotizacion_dolar_bna` + RLS + seed, `factor_cac_obra`,
  `calcular_saldo_pendiente_hitos`.
- `lib/data/models/indicadores_economicos.dart` — `IndiceCac`, `CotizacionDolarBna`.
- `lib/services/indices_economicos_repository.dart`

Tocados:
- `lib/presentation/dashboard/obras_list_screen.dart` — reemplaza los valores hardcodeados de
  dólar y variación CAC por una carga real (`_cargarIndicadoresEconomicos`), y corrige el bug de
  `mesBaseCac` en la creación de obra (ver §2).

`flutter analyze` limpio (49 infos preexistentes, ninguna nueva). **Sin aplicar la migración, sin
verificar en el emulador.**

## 8. Qué queda para después

- **Punto 3 — el snapshot del Modelo A** (§4): diseño de datos pendiente, es la pieza siguiente,
  no un "algún día". Necesita decidir dónde vive el snapshot (¿columna en `obra_subitems`?
  ¿estado nuevo de la obra que deja de leer el motor en vivo?), con materiales y mano de obra
  separados para poder usar las dos series de `factor_cac_obra` como pidió Seba.
- **UI para el Modelo B**: `hitos_certificacion`/`calcular_avance_hitos` no tienen ninguna
  pantalla en la app todavía (verificado, cero referencias en `lib/`) — `calcular_saldo_pendiente_hitos`
  queda listo del lado de datos, pero nadie lo llama desde Dart todavía. Fuera de alcance de esta
  pieza (construir la pantalla es un trabajo aparte, no una extensión mecánica).
- **Automatización de las dos cargas** (CAC mensual, dólar): anotada como mejora futura, no para
  ahora — decisión de Seba, con pocos usuarios cargar a mano es más confiable.
- **Actualización automática del dólar con aviso ante variación > 5%**: pendiente desde antes
  (`docs/diagnostico_general_producto.md` §3.8), sigue sin resolver.
