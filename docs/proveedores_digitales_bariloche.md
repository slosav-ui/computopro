# Proveedores digitales de Bariloche — investigación de negocio (2026-09-04)

Investigación de mercado sobre corralones de Bariloche y la comarca, para la Solapa Proveedores
(ver `CLAUDE.md`, "Solapa Proveedores: base de datos obligatoria en Supabase y monetización por
membresías") y el motor de precios de materiales anotado en `docs/monetizacion.md` (punto 5, "Motor
de precios de materiales (APU)": promedio de corralones + fallback MercadoLibre) y punto 6
("Onboarding de corralones sin fricción"). Es investigación de negocio, no una decisión de diseño
de datos — no toca schema, migraciones ni código.

## Hallazgo: solo dos corralones digitalizados, ninguno legible automáticamente

De los corralones de Bariloche y la comarca, solo dos tienen catálogo online. Ninguno de los dos se
puede leer de forma automática.

### HIZA (Miramar 53, Bariloche) — corre sobre XCONS

HIZA no tiene sitio propio: opera sobre **XCONS**, una plataforma compartida de e-commerce para
corralones, distribuidores y fabricantes de materiales de construcción, con marketplace propio en
`xcons.com.ar` y cuenta unificada para toda la red. Titular: **Ecosistema Digital S.A.S., CUIT
30-71714364-3**.

- **Catálogo público y perfectamente legible**: nombre normalizado con medidas, fabricante, SKU, ID
  de producto y un árbol de categorías que se parece mucho al de rubros de computoPRO. Ejemplo real:
  *"Ladrillo tabique 12 cerámico hueco no portante 6 tubos 120mm x 180mm x 330mm"*.
- **Precios no públicos**: exige elegir dirección de entrega, y probablemente estar logueado, antes
  de mostrarlos. Verificado sobre la categoría de ladrillos: los 19 productos salieron con
  "NO DISPONIBLE".
- **Términos y condiciones prohíben expresamente** la reproducción total o parcial de los contenidos
  sin autorización escrita.

### Felemax (Circunvalación km 10, Bariloche) — corre sobre Odoo

Sí publica precios, pero el sitio **bloquea bots**: el intento de lectura automática fue rechazado
por detección.

## Conclusión: el camino viable es un acuerdo comercial, no scraping

Las dos puertas están cerradas por decisión de los dueños, no por dificultad técnica — HIZA/XCONS
por contrato (ToS explícito), Felemax por bloqueo activo.

Esto confirma y extiende a los corralones la decisión de diseño que ya estaba tomada para
MercadoLibre: usar su **API pública de búsqueda, no scraping**, "más estable y evita problemas de
ToS" (`docs/computopro_rubros_apu_spec.md:81`). El mismo criterio aplica acá — no vale la pena
construir sobre una lectura que el proveedor puede cortar en cualquier momento y que ya te avisó
por escrito que no autoriza.

## Por qué la conversación con XCONS vale la pena, y cuándo

XCONS le habla exactamente al mismo usuario que computoPRO: en su propio material describen su
público como arquitectos y constructores, y publican preguntas como *"¿cuántas horas pasás
calculando los materiales para un proyecto que ni sabés si se va a llevar a cabo?"*.

Son complementarios, no competidores: computoPRO resuelve cómputo y análisis de precios unitarios;
XCONS resuelve catálogo, precios y red de distribución. Entre esas dos mitades hoy hay un Excel y
una cadena de WhatsApps.

**La conversación conviene tenerla cuando la app se pueda mostrar funcionando de punta a punta, no
antes.** Hoy llega hasta el costo de mano de obra pero no puede mostrar un presupuesto cerrado
porque faltan los precios de materiales — mostrarse a mitad de camino resta poder de negociación.

**Tres niveles posibles de integración, de menor a mayor compromiso:**

1. Acceso a la nomenclatura del catálogo sin precios — útil para mapear los 234 insumos del
   catálogo APU sembrado en `supabase/migrations/0022_seed_insumos_apu_rubros_2_17.sql` (el
   detalle de esa carga, incluida la verificación de qué insumos tienen precio real hoy, quedó en
   la memoria de proyecto de esta sesión, no en un doc de `docs/` — no hay ningún `.md` acá que lo
   narre todavía).
2. Precios de referencia por producto y zona, vía API.
3. Cotización directa del listado computado contra su red.

## Advertencia sobre el modelo de membresías — importante antes de negociar

El roadmap de monetización de computoPRO incluye membresías pagas para corralones que quieran
figurar y cotizar en la Solapa Proveedores (`CLAUDE.md`, misma sección citada arriba). Esto no choca
en principio con XCONS: ellos le cobran al corralón por la infraestructura de venta online,
computoPRO le cobraría por demanda cualificada — son cosas distintas, y un corralón puede pagar las
dos. Pero hay dos riesgos que conviene tener escritos antes de sentarse a negociar:

1. **Orden de los acuerdos.** Si XCONS entrega precios de toda su red y después computoPRO le cobra
   membresía a esos mismos corralones por aparecer en la app, la situación se vuelve incómoda. No es
   imposible, pero tiene que quedar definido en el acuerdo desde el principio, no después.
2. **Percepción de competencia.** XCONS puede leer el modelo de membresías como alguien cobrándole a
   sus propios clientes por algo paralelo, y eso puede trabar la integración antes de empezar.

Por eso, si se abre la conversación, **empezar por el Nivel 1** (solo nomenclatura, sin precios) es
lo más seguro: no toca el modelo de negocio de nadie y destraba el trabajo más pesado, que es
mapear los insumos contra el catálogo real del rubro.

## Riesgo de exposición

Mostrar la app completa a XCONS implica mostrarles el mapa de algo que ellos tienen capacidad de
construir: tienen plataforma, catálogo y equipo. Lo que no tienen es la curación técnica (97
partidas de APU contra bibliografía, escala UOCRA con cargas sociales, coeficientes) — meses de
trabajo de un arquitecto del rubro, no algo que se replique mirando una demo.

**Decisión ya tomada, anotada acá junto con el hallazgo**: antes de repartir el APK a colegas hay
que resolver el registro del software y un acuerdo de confidencialidad. Aplica con más razón antes
de mostrarle la app a un tercero comercial como XCONS.

## Datos de contacto verificados (2026-09-04)

- **XCONS / Ecosistema Digital S.A.S.** — CUIT 30-71714364-3. Sitios: `xcons.com` (corporativo),
  `xcons.com.ar` (marketplace). LinkedIn `linkedin.com/company/xcons`, Instagram `@xcons_ar`. No
  publican casilla de mail; el contacto es por formulario de demostración.
- **HIZA** — Miramar 53, Bariloche. `ventas@hizasrl.com`, `ventas2@hizasrl.com`,
  2944-485169 / 2944-585293.
- **Felemax** — Circunvalación km 10, Bariloche. `felemax.com`, 294-453-3910. Envíos a Villa La
  Angostura y El Bolsón.
