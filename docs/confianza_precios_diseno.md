# Confianza en los precios: frescura, aviso legal y mecanismo colaborativo — diseño (2026-09-05/06)

Diseño de negocio y de datos, **cerrado en los puntos marcados CERRADO, sin ninguna migración
escrita ni código tocado** — no repite ni reemplaza `docs/rubros_apu_diseno_datos.md` ni
`docs/costo_mano_de_obra_decisiones.md`, es la pieza de confianza/frescura del motor de precios de
materiales que esos documentos y `docs/monetizacion.md` §5 ("Motor de precios de materiales (APU)")
ya anticipaban sin detallar. Corrige puntualmente esa sección: **el fallback a MercadoLibre que
`docs/monetizacion.md` §5 daba por sentado queda descartado como mecanismo de validación** — ver
§7 más abajo.

Origen: trabajar las primeras cotizaciones reales de corralones de Bariloche (Sólido, Felemax) y la
pregunta de fondo de cómo lograr que el usuario confíe en los precios de la app sin prometer algo
que no se puede cumplir.

## 1. El principio: no prometer precios frescos, prometer saber qué tan frescos están

Con 234 insumos, varios proveedores e inflación argentina, **siempre va a haber precios
desactualizados** — perseguir la actualización total es una carrera perdida. Lo que sí se puede
garantizar es que el usuario nunca se sorprenda, mostrando la edad del dato en vez de esconderla.

Referencia del propio mercado, verificada con las cotizaciones reales: Sólido escribe "sujetos a
variación sin previo aviso", Felemax le pone cinco días de validez a su cotización. Los corralones,
que tienen sus precios en su propio sistema, no se comprometen más allá de eso — la app no puede
prometer más.

**Concretamente:**

- Cada precio muestra **fecha y origen al lado del número**, no en letra chica: "Cemento $417/kg —
  Sólido, hace 3 días" en vez de "$417/kg" a secas.
- El presupuesto exportado lleva **la fecha de sus precios**.
- Tres capas según antigüedad: fresco pasa sin ruido; algunas semanas, aviso discreto; muy viejo,
  aviso que no se puede ignorar antes de exportar ("hay 14 insumos con precios de más de dos
  meses").
- El **CAC** (ya previsto en el proyecto, ver `docs/monetizacion.md` y "Ajuste Económico & Moneda"
  en `CLAUDE.md`) permite ofrecer actualización por índice cuando el precio tiene tiempo — no es
  exacto, pero es lo que el rubro acepta.

**Lo que NO se hace: actualizar precios en silencio.** Si el usuario armó un presupuesto con un
número y al abrirlo es otro sin aviso, ahí se pierde la confianza. Se sostiene la decisión ya
cerrada en `docs/precio_congelado_vs_recalculado.md` (memoria de proyecto, 2026-08-31, sin doc en
`docs/` — anotado acá porque es la premisa directa de este diseño): los precios se congelan al
presupuestar y se ajustan solo por coeficiente pactado (CAC/dólar), nunca recalculando desde
insumos.

## 2. Aviso y descargo

Texto propuesto, visible y no escondido:

> Los precios son de referencia, promediados de proveedores de la zona, con la fecha de última
> actualización a la vista. Pueden diferir del precio real de compra. Verificá los valores con tus
> proveedores antes de presentar un presupuesto en firme.

**Un descargo no reemplaza al producto funcionando bien.** La protección real es mostrar la fecha y
avisar cuando el dato está viejo (§1); el aviso legal acompaña eso, no lo sustituye. Un descargo
escondido es el que peor funciona — si va, va visible, no en letra chica.

El texto definitivo conviene que lo revise un abogado antes de publicar, junto con los términos y
condiciones — está en la misma lista que el registro del software y el acuerdo de confidencialidad
(ver "Riesgo de exposición" en `docs/proveedores_digitales_bariloche.md`).

## 3. El mecanismo colaborativo — CERRADO

El precio que un usuario carga para su obra puede alimentar el catálogo compartido de
`calcular_precio_promedio_insumo()` (`supabase/migrations/0013_rls_proveedores_precios.sql`, ver
"RLS del bloque proveedores/insumos/precios" en `CLAUDE.md`), con estas reglas:

**Separación fundamental:** el precio entra a la obra del usuario **siempre**, sin traba (mismo
mecanismo ya existente: `obra_insumo_precios`, por obra). Al catálogo compartido entra solo si pasa
la validación. Si alguien se equivoca, se equivoca en su presupuesto, no en el de todos.

**Validación por banda.** Se compara contra lo que ya hay para esa zona, ajustado por CAC del
período. Nunca contra MercadoLibre — ver §7.

**Si se sale de banda:** no se traba la carga, se informa. El aviso menciona precio y formato de
compra — algo del tipo "este precio está fuera de los valores de mercado que tenemos registrados,
¿confirmás el precio y el formato de compra?" — porque buena parte de los casos reales son un error
de envase, no de precio (ver §4, unidad de compra vs. uso). El usuario decide.

**Cómo se publica al catálogo compartido:** hacen falta **tres precios que coincidan dentro de un
10% entre sí**, y entra el promedio de los tres. La validación la hace el volumen, no un análisis
automático: si tres personas cargan el hierro a un valor nuevo, ese valor es el mercado y la banda
se corrige sola.

**Ventana temporal: un mes.** Los precios que no juntaron tres coincidencias en ese plazo se
descartan, para no mezclar épocas distintas.

**Al principio, con poco volumen:** si pasa el mes sin llegar a tres, se le avisa a Seba para que lo
verifique a mano. Es un mecanismo de arranque, no permanente — se retira cuando haya uso masivo.

## 4. Unidad de compra contra unidad de uso — CERRADO

**El criterio**: el usuario carga el precio en el formato en que se lo da el corralón — la bolsa de
cemento, la caja de cien tornillos, el rollo de lana de vidrio, la barra de hierro — y la app
convierte internamente a la unidad de uso para el APU. En la Solapa de Materiales se muestra el
precio comercial tal cual, lo que el usuario tipeó; el precio por unidad de uso aparece en el APU,
ya convertido. Nadie tipea un número que no le dio nadie.

Es exactamente para lo que existen `unidad_compra` y `factor_conversion` en `insumos`
(`0017_alter_insumos.sql`) — hoy cargadas en un solo insumo del catálogo, CEMENTO PORTLAND X 25KG
(`unidad_compra = 'bolsa 25kg'`, `factor_conversion = 25`, ver `0049_limpieza_catalogo_insumos.sql`
§5, "caso testigo de la distinción unidad de compra vs. unidad de uso", ya anotado como pieza
central del motor de precios en `docs/monetizacion.md` punto 5). El resto del catálogo (233 de 234
insumos) todavía no tiene el par cargado.

**El factor tiene que estar visible al lado del campo** — "bolsa de 25 kg" — para que el usuario lo
corrija si su corralón le vende otro formato. Mismo criterio de transparencia que la fecha/origen
del precio en §1: no esconder el número contra el que se calcula el precio por unidad de uso.

**Abierto: el factor no siempre es fijo por insumo, a veces es por producto.** La lana de vidrio
viene en rollos de metrajes distintos según el espesor, y el hierro depende del diámetro — un solo
`factor_conversion` por fila de `insumos` no alcanza si una misma fila del catálogo tiene que cubrir
variantes con distinto formato de compra. Sin diseño todavía: puede terminar resolviéndose con filas
de insumo separadas por variante (el catálogo de 234 ya separa por diámetro/espesor en varios
casos, sin verificar si en todos) o con un factor editable por obra en vez de fijo por insumo.

### Conexión con la validación por banda (§3)

Un error de formato es el que más se nota en el precio final: si alguien carga la bolsa de 50kg
donde la app espera 25kg, el precio por unidad de uso sale al doble, y la banda de §3 lo detecta
como si fuera un precio fuera de mercado.

Por eso el aviso de "fuera de banda" de §3 menciona precio y formato de compra, no solo precio — en
buena parte de los casos reales el problema va a ser el envase, no el número.

Funciona también al revés: si el precio cargado es correcto y la alarma salta igual, puede que el
`factor_conversion` cargado para ese insumo esté mal — la alarma de precio termina siendo,
indirectamente, una alarma sobre los datos maestros del catálogo.

## 5. El mismo problema, la misma solución: precio de referencia por m² por zona

Ya anotado como roadmap en `CLAUDE.md` ("Motor de precio de referencia por m² por zona"). Esta
sección lo amplía, no lo reemplaza, y se anota junto a §3 a propósito: es el mismo problema (un
valor de mercado que solo existe agregando datos de muchos usuarios, no algo que la app pueda
calcular sola) con la misma solución (publicar recién con volumen suficiente).

**Lo que ya estaba diseñado**: al elegir/tocar una zona geográfica (radio ~50km) en el Dashboard,
mostrar un valor de referencia $/m² en ARS y USD, separado en 3 categorías de obra (A, B, C según
tipo de materiales/construcción), calculado como el promedio real de las obras ya cargadas por
usuarios en esa zona y categoría (`monto_total` ÷ superficie de cada obra) — nunca un valor fijo
estimado.

**Lo que se agrega ahora**: el valor se muestra separado en dos — Materiales + Mano de obra por un
lado, Mano de obra sola por otro. Encaja directo con `SelectorTipoPresupuesto` (Solapa APU, Factor K
Paso A, ver "Factor K (Solapa APU)" en `CLAUDE.md`), que ya distingue esos dos modos ("Comp. Solo
MO") en toda la app — no necesita mecanismo nuevo, solo agregar el corte al promedio por categoría.

Es estrictamente referencial, con el mismo criterio de frescura y descargo que los precios de
insumos (§1-§2): fecha del promedio a la vista, aviso si está viejo, nunca un número presentado
como si fuera preciso.

**Comparte el problema del volumen mínimo con el mecanismo colaborativo de §3.** Hasta que no haya
obras suficientes cargadas en una zona y categoría, el valor no se puede publicar — mismo
principio que "tres precios que coincidan dentro de un 10%" para insumos, pero acá la cantidad
mínima de obras todavía no está definida. **Abierto.**

**Privacidad, misma línea que §6**: el monto de una obra puntual nunca se muestra a otro usuario,
solo entra al promedio anónimo — mismo criterio exacto que §6 ya cierra para precios de insumos,
aplicado acá a `obras.monto_total`/superficie en vez de `obra_insumo_precios`.

## 6. Privacidad — CERRADO

**Compartir es obligatorio, anónimo y agregado.** Va en los términos de uso, explicado.

- El precio **nunca se muestra atribuido a nadie**.
- Solo entra al promedio, y hace falta que tres coincidan para publicarse.
- **El precio de una obra puntual nunca se le muestra a otro usuario.** Ya lo garantiza el diseño
  actual: los precios editados son por obra (`obra_insumo_precios`), no globales — mismo principio
  que ya cerró el RLS de `precios` en `0013_rls_proveedores_precios.sql` (nadie fuera del dueño del
  corralón hace `SELECT` crudo; acá aplica el equivalente para el usuario y su obra).
- Mismo criterio para el promedio por m² de §5: el monto total de una obra puntual nunca se
  muestra, solo entra agregado al promedio de su zona y categoría.

## 7. Por qué MercadoLibre NO sirve como referencia de validación

Verificado con búsquedas reales el 06/09/2026, comparando contra las cotizaciones de Bariloche
(Sólido, Felemax):

- **Cemento**: MercadoLibre muestra la bolsa de 50 kg mayormente entre $9.000 y $13.000
  ($180-260/kg). Sólido $417/kg, Felemax $558/kg. Bariloche entre 60% y 130% arriba.
- **Hierro Ø8**: una publicación a $7.660 la barra de 12m ($1.630/kg). Sólido $2.196/kg, Felemax
  $2.959/kg. Entre 35% y 82% arriba.

**El motivo: casi todas las publicaciones son de Capital Federal y GBA.** Prácticamente nada de
Patagonia, y para materiales pesados esos vendedores no envían a Bariloche o el flete costaría más
que el material. Comparar contra MercadoLibre no es comparar canales, es comparar Buenos Aires
contra Bariloche — un margen fijo sobre MercadoLibre rechazaría precios correctos en la cordillera.

**Dato de Seba, para tener presente:** en una comparación propia anterior encontró que el precio de
MercadoLibre sin envío más un 30% se aproximaba al precio de Bariloche — coincide con el 35% que
dio el hierro acá. Sirve como **detección de precios raros**, no como validación: si un corralón
cotiza al doble de eso, algo pasa.

**La referencia correcta es el propio catálogo, por zona**, y la evolución histórica de cada
material (no sigue la misma curva entre sí: el hierro va atado al acero internacional, el cemento
es más local). Para eso el INDEC publica el índice de costos por capítulos y la CAC su índice, ya
previsto en el proyecto — no hace falta reconstruir la serie a mano.

**Consecuencia sobre `docs/monetizacion.md` §5**: el "fallback MercadoLibre" ahí anotado queda
descartado como mecanismo de *validación* de precio. Si algún día se retoma MercadoLibre para algo,
que sea acotado a detección de outliers (regla de Seba de arriba), nunca como banda de referencia
de precio de mercado en zonas fuera del AMBA.

## 8. Condiciones de pago — hallazgo nuevo, sin resolver

Felemax entregó **dos cotizaciones con los mismos materiales**: una a precio de lista y otra con
descuento al contado. La diferencia no es un error, es la condición de pago.

Un mismo insumo tiene más de un precio válido al mismo tiempo. **Si el promedio mezcla las dos
condiciones, no representa a ninguna.**

Queda anotado que el precio debería registrar en qué condición se pactó. No para intervenir en la
negociación — eso es oferta y demanda entre el profesional y su corralón, y ahí la app no se mete —
sino para que el promedio compare lo comparable.

**Sin diseño todavía** — afecta potencialmente el schema de `precios`/`obra_insumo_precios`
(agregar algo como `condicion_pago`), pero no se toca nada hasta que esto se diseñe puntualmente.

## 9. Automatizado contra humano — criterio de arquitectura

Distinguir dos mecanismos que se mezclan:

- **Precio de referencia**, para armar el presupuesto: tiene que ser automático y rápido.
- **Precio en firme**, para comprar: necesita que un corralón se comprometa, y ahí hay un humano
  que responde cuando puede.

**"Mandar a presupuestar"** (ver "Motor 'Mandar a Presupuestar'" en `CLAUDE.md`, no implementado)
**no puede ser el camino del precio de referencia**, porque depende de que alguien conteste y
trabaría el armado del presupuesto. Lo que sí se automatiza ahí es el envío del listado, el
seguimiento de quién respondió y la comparación de respuestas — no el precio con el que se computa
mientras tanto.

## 10. Y algo que vale más que todo lo anterior

Si cada usuario que pide cotización carga las respuestas, **la app acumula precios reales por zona
y por fecha**. Es un dato que hoy no tiene nadie en el rubro — ni siquiera XCONS, que tiene sus
propios precios pero no los de la competencia (ver "Por qué la conversación con XCONS vale la pena,
y cuándo" en `docs/proveedores_digitales_bariloche.md`).

Esto cambia el valor de esa conversación cuando llegue: no se negocia solo acceso a un catálogo,
se negocia con un dataset propio de precios reales multi-proveedor que XCONS no tiene.

## Para retomar

- **Condiciones de pago (§8)**: sin diseño, afecta schema de precios.
- **Textos legales (§2)**: revisión de abogado antes de publicar, junto con T&C, registro del
  software y acuerdo de confidencialidad.
- **Factor de conversión por variante de producto (§4)**: lana de vidrio (por espesor), hierro (por
  diámetro) — un `factor_conversion` fijo por fila de `insumos` no alcanza si hace falta cubrir
  varios formatos de compra bajo el mismo insumo. Sin diseño.
- **Cargar `unidad_compra`/`factor_conversion` en el resto del catálogo (§4)**: hoy solo está en
  CEMENTO PORTLAND X 25KG, de los 234 insumos.
- **Volumen mínimo del promedio por m² (§5)**: cuántas obras hacen falta por zona y categoría antes
  de publicar — sin definir, mismo problema que ya se resolvió para insumos con "tres precios que
  coincidan dentro de un 10%" (§3).
- **`obras.categoria` (A/B/C, §5)**: columna sin agregar, ya prevista en el roadmap de
  `CLAUDE.md` para esta misma pieza.
- Nada de esto tiene migración ni código todavía — ninguna de las piezas de este documento está
  bloqueando otro trabajo en curso (Factor K Paso B, zonas UOCRA, QR de vinculación).
