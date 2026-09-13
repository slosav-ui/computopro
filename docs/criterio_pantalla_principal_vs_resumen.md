# Criterio: qué va en la pantalla principal y qué va en Resumen

**Cerrado por Seba el 2026-09-13.** Hasta acá se venía decidiendo caso por caso, en cada pieza, y
cada vez se volvía a discutir lo mismo. Esto lo fija de una vez.

Textual de Seba:

> *"pantalla principal esto que marcás me parece bien, y resumen bien técnica"*

---

## 1. Las dos pantallas, en una línea cada una

**Pantalla principal (`ObrasListScreen`) — panorámica y amable.** Es la primera llegada de
cualquier usuario nuevo: tiene que ser atractiva, intuitiva y fácil. De un vistazo: **qué obras
tenés, cómo van, qué te espera.**

**Resumen (solapa de la obra) — técnica y profunda.** De una obra: sus números, el avance por
rubro, los certificados, los adicionales con su detalle, los gráficos. **Ahí va el análisis.**

No son dos niveles de la misma pantalla: son dos públicos y dos momentos. La portada la mira
alguien que todavía no eligió una obra (o que recién se instaló la app); Resumen la mira alguien
que ya está trabajando una obra puntual y quiere entender qué pasa adentro.

---

## 2. Pantalla principal: qué va y qué no

**Va:**

- **Identidad de la obra**: nombre, propietario, ubicación, estado (Cotización / En curso).
- **Los montos cerrados**, con el mismo peso visual entre ellos: el presupuesto pactado y cada
  adicional aprobado, más el total. Son números firmados, ninguno es una estimación (§10.2 de
  `docs/adicionales_quitas_demasias_diagnostico.md`).
- **Referencias de comparación cortas**: m², CAC, el chip "Hoy · Desfasaje" de una obra congelada.
- **Qué te espera**: el contador de pendientes de esa obra y el cartel de `mis_pendientes()`
  (`docs/avisos_pendientes_diseno.md`).
- **Un vínculo a Resumen** cuando hay algo para profundizar. El "ver más" tiene que caer en la
  solapa correcta, no dejar al usuario buscándola.

**No va:**

- **Desgloses.** Ni de lo certificado, ni de lo que falta, ni de avance por rubro, ni de
  composición de un monto.
- **Certificados ni avance de un adicional.** Eso es seguimiento de ejecución: es de Resumen.
- **Texto explicativo de casos especiales**, etiquetas condicionales, aclaraciones de "ojo que acá
  se mezclan dos cosas". Si un caso necesita explicación, la explicación va adentro de la obra.
- **Listas sin tope.** Nada que crezca renglón a renglón sin límite con los datos de la obra: se
  muestran los primeros N y el resto se agrupa, con el vínculo a Resumen al lado (ver
  `_maxAdicionalesEnCard`).

**Dos reglas que resuelven casi todos los casos nuevos:**

1. **Se recorta el detalle, nunca la jerarquía de un número cerrado.** "Escueto" no puede significar
   esconder un monto firmado dentro de una suma — ese fue exactamente el error que hubo que
   corregir con los adicionales aprobados (§10.2). Si es un monto cerrado y es de esta obra, va con
   el mismo tratamiento que los demás montos cerrados.
2. **Si hace falta una aclaración para que el dato no se malinterprete, el dato no es de portada.**
   La aclaración es la señal: ese dato necesita contexto, y el contexto vive en Resumen.

---

## 3. Resumen: qué tiene que llegar a ser

- Los números de la obra en serio: pactado, certificado, saldo, adicionales con su detalle
  (qué incluye cada uno, cuánto se certificó, qué saldo queda), quitas y demasías.
- Avance por rubro, curva de inversión / tiempos, semáforos.
- Los gráficos y la comparación contra lo planificado.
- Todo lo que en la portada se decidió no poner: acá no hay límite de renglones ni problema con que
  haga falta una aclaración.

**Estado real hoy, para no engañarse:** la solapa Resumen sigue siendo la maqueta de la demo
(`_buildTabResumenFinal` en `lib/presentation/obra_detalle/screens/presupuestos_screen.dart`:
`costoDirectoTotal` hardcodeado en 85.000.000 y sliders de coeficientes). **No muestra ni los
adicionales ni los certificados de la obra real.** El vínculo "Ver el detalle en Resumen" de la card
ya apunta ahí porque ese es el lugar que le corresponde según este criterio — pero hasta que Resumen
sea de verdad, el vínculo cae en una pantalla que todavía no tiene el detalle. Es la pieza siguiente
natural de esta línea de trabajo.

---

## 4. Cómo quedó aplicado lo que ya existe

| Dato | Dónde vive | Por qué |
| --- | --- | --- |
| Presupuesto pactado | Portada (número cerrado) | Es *el* precio de la obra una vez firmado |
| Cada adicional aprobado | Portada, un renglón por cada uno, mismo peso que el pactado | Son montos firmados, no sumandos anónimos (§10.2) |
| Total pactado + adicionales | Portada, debajo de una línea | Cierra la cuenta sin tapar sus partes |
| "Hoy · Desfasaje" | Portada, chip chico de referencia | Es comparación, no un monto propio (`docs/presupuesto_congelado_validez_modelo_a_diseno.md` §8) |
| Certificado / saldo de un adicional | Resumen | Seguimiento de ejecución |
| Avance por rubro, gráficos | Resumen | Análisis |
| Etiqueta de condiciones de un adicional (§10.1) | Resumen | Necesita explicación → no es de portada |
| Monedas mezcladas entre contrato y adicional | Resumen (cuando exista) | Ver §15 del doc de adicionales: hoy no hay dónde mostrarlo porque el dato todavía no se guarda |

---

## 5. Pendientes anotados de la portada — no para ahora

Los dos salieron de la misma conversación del 2026-09-13 y quedan para cuando se trabaje la portada
en serio, no para la tanda que estaba en curso.

### 5.1 El primer uso — más importante que lo visual

Un usuario nuevo entra y ve una pantalla vacía, sin saber qué hacer. Ya está anotado como debilidad
en `docs/diagnostico_general_producto.md`, con la referencia a que **Sismat precarga modelos de 80,
120 y 200 m²** para que el que recién entra tenga de dónde arrancar.

**Palabras de Seba: "es más importante que lo visual: si alguien entra y no sabe qué hacer, no
vuelve."** Es decir: prioridad por encima del trabajo estético de la portada, no un detalle de
onboarding para el final.

### 5.2 Que se note cómo va cada obra — **HECHO el 2026-09-13**

Estaba anotado así: *"hoy la tarjeta muestra montos pero no dice si la obra está avanzada o parada;
una barra de avance lo resolvería de un vistazo"*. Construido, y con una vuelta más de la que decía
esta nota: **no es una barra por card, es una barra por monto cerrado** — el pactado con el avance del
contrato y cada adicional aprobado con el suyo, porque una obra con adicionales en ejecución no se
resume en el avance del contrato.

Se cumplió el criterio de la portada tal cual: **una barra y el porcentaje, sin desglose**. El detalle
por rubro vive en Gestión de Obra (`PanelAvanceObra`) y el de cada adicional en Resumen. Y el rótulo
dice **"Avance certificado"**, no "avance de obra": el número suma solo certificados que dejaron de
ser borrador.

Con esto **las tres preguntas de la portada están contestadas**: qué obras tenés, cómo van, qué te
espera.

### 5.3 Los m² como dato de identificación (2026-09-13)

Los m² estaban como chip grande abajo, entre los montos. Seba los movió al renglón de identificación,
junto al propietario y la ubicación: **"es un dato de identificación, como el nombre, no un número más
entre los montos"**. Pierden la presencia de los 15px que tenían como chip — se quedan un peso arriba
del resto del renglón, no dos.

Criterio que deja para la próxima vez: **el bloque de montos es solo para plata.** Lo que identifica a
la obra va arriba; lo que es condición del contrato (el chip de CAC) puede quedar con los montos.

### 5.4 Que se vea dónde termina una obra y empieza la otra (2026-09-13)

Consecuencia directa de todo lo que se le sumó a la tarjeta (los renglones de montos, las barras): la
lista empezó a leerse como **un bloque continuo**. Seba: *"de un vistazo se vea cuántas obras hay y
dónde está cada una"*, sin recargar el diseño.

Resuelto **sin agregar ningún elemento**: más aire entre tarjetas (12 → 18), un borde de 1px, sombra
más marcada, y el fondo de la pantalla más oscuro para que el blanco de la tarjeta se lea como blanco.
En Material 3 hizo falta además apagar el `surfaceTintColor`, que tiñe las superficies elevadas y
acercaba el blanco al gris del fondo.

El fondo se ajustó en **dos pasos, los dos mirados en el emulador**: `F4F6F9` → `E9EDF2` (todavía
quedaba justo) → **`E2E7EE`**. Ese es el tope recomendado: más oscuro que eso la pantalla se ve gris y
pesada, y el contraste hay que buscarlo en el **canto** de la tarjeta (borde más definido, esquina más
redondeada, sombra con desplazamiento) y no en el fondo. Si alguna vez hace falta más separación, ese
es el orden en que conviene probarlo.

**La causa real, encontrada en la tercera vuelta (2026-09-13): en Material 3 un `Card` no es blanco.**
Su color por defecto es `colorScheme.surfaceContainerLow`, derivado del `seedColor` azul del theme
(`lib/config/app_theme.dart`): un lavanda muy claro casi del mismo tono que el fondo del listado. Toda
la sensación de "bloque continuo" venía de ahí, más que de la sombra. La tarjeta de la portada pasó a
ser un `Container` con `BoxDecoration` — blanco declarado, radio 16, borde `black12` y **sombra navy al
10% con desplazamiento `(2, 3)`**, que `elevation` no puede dar porque reparte la sombra parejo
alrededor. Negro puro en esa sombra se lee como suciedad sobre el gris del fondo; agrandarla separa,
oscurecerla ensucia.

**Ojo, esto no es solo de la portada**: el mismo lavanda afecta a **todos los `Card` de la app** (unos
30, en una docena de pantallas). Se arregla en una línea del theme (`cardTheme.color: Colors.white` +
`surfaceTintColor: Colors.transparent`), y quedó como decisión aparte para no arrastrar un cambio
visual a pantallas que nadie miró todavía.

**Criterio que queda**: cuando una tarjeta de la portada gane contenido, revisar la **separación**
antes de revisar el contenido. El aire es lo que agrupa — una tarjeta alta con poco espacio alrededor
se pega a la de al lado por más borde que tenga. Y todo lo que se sume tiene que caber sin necesitar un
separador interno más: si hace falta dibujar líneas adentro para que se entienda, el problema es que la
tarjeta tiene demasiado.

---

## 6. Referencias

- `docs/adicionales_quitas_demasias_diagnostico.md` §10.2 — el caso que originó el criterio y el
  diseño final de la card; §15 — monedas distintas entre contrato y adicional.
- `docs/presupuesto_congelado_validez_modelo_a_diseno.md` §8 — pactado vs. "Hoy · Desfasaje".
- `docs/avisos_pendientes_diseno.md` — el cartel de pendientes de la portada.
- `docs/diagnostico_general_producto.md` — el primer uso, como debilidad de producto.
