# Generar el contrato de obra desde la app — pieza anotada (2026-09-14, sin construir)

Pedido de Seba: **poder generar el contrato de obra desde la app**, con **tres modelos a elegir** y
armado con lo que ya está cargado en Cómputo.

> Anotado como diseño a pedido suyo. **No construir sin cerrar antes las ambigüedades de §4.** La
> §4.A —la que no era de producto sino de responsabilidad profesional— ya está cerrada: **borrador
> para llevar al abogado, nunca un documento que se firma tal cual**. Quedan B a E.

## 1. Los tres modelos

| Modelo | Para qué | Qué lo distingue |
| --- | --- | --- |
| **Chicas y subcontratos** | una tarea o un gremio dentro de una obra más grande | alcance acotado, plazo corto, poca o ninguna certificación por período |
| **Parciales** | una etapa completa (la estructura, la instalación) | alcance por rubros, con certificación y plazos |
| **Obra total** | la obra entera | el más largo: anticipo, fondo de reparo, redeterminación, plazos, multas |

No son tres textos sueltos: son **el mismo contrato con distinto alcance y distintas cláusulas
prendidas**. Conviene tratarlos así desde el diseño de datos, o van a terminar siendo tres archivos
que se editan por separado y divergen al primer cambio de ley.

## 2. Lo que la app ya sabe y no habría que volver a pedir

Es la mitad del valor de la pieza: el contrato se llena solo con lo que ya está cargado.

- **Las partes**: `obra_members` + `perfiles` (nombre, teléfono y **matrícula profesional**, que la
  `0100` guardó justamente pensando en el PDF).
- **El objeto y el alcance**: los rubros y partidas tildadas de Cómputo, con sus cantidades.
- **El precio**: el total del presupuesto, y si está congelado (`0104`) **el precio pactado exacto,
  con su fecha** — que es lo que un contrato necesita, no el vivo.
- **La moneda y el ajuste**: moneda de la obra, `aplica_cac` y la serie, la cotización congelada.
- **La forma de pago**: `anticipo_pct`, `fondo_reparo_pct`, `dias_plazo_pago_certificados`,
  `periodicidad_certificacion`. Las cuatro ya se configuran en Gestión de Obra.
- **El modelo de certificación** (avance medido / hitos) y, desde la `0132`, **cómo se mide**.

Lo que **no** existe hoy y todo contrato pide: fecha de inicio y **plazo de ejecución en días**,
lugar/domicilio de la obra, datos fiscales (CUIT, condición frente al IVA), multas por mora, y quién
provee qué (materiales, agua, luz).

## 3. Forma probable

Una plantilla por modelo con marcadores, llenada del lado del servidor y exportada a PDF. **El mismo
mecanismo que va a necesitar la exportación del Libro de Obra**, así que conviene que salgan juntas o
al menos que la primera deje el generador de PDF hecho — hoy el proyecto **no tiene ninguno**.

## 4. Ambigüedades a cerrar antes de escribir una línea

**A. ¿Qué es lo que la app entrega, exactamente? — CERRADA por Seba (2026-09-14): (i) + (iii),
borrador para el abogado con el anexo técnico como lo de más valor.** Textual: *"nunca un documento
que se firma tal cual sale de la app"*.

Lo que sigue queda como el fundamento de esa decisión, no para reabrirla. No era una pregunta de
producto: un contrato de obra tiene efectos legales, y una plantilla mal usada perjudica a alguien de
verdad. Las tres opciones eran distintas en responsabilidad, no en trabajo: (i) un **borrador para llevar al
abogado**, con el aviso al pie —el mismo criterio que ya se usó con el Libro de Obra rubricado—;
(ii) un **modelo revisado por un abogado** contratado para eso, que es la única forma de que el
usuario lo firme tal cual; (iii) **solo el anexo técnico** (alcance, cómputo, precios, plazos) para
adjuntar a un contrato que redacta otro. **Recomiendo (i) para la primera versión y (iii) como lo que
más valor da con menos riesgo**: el anexo técnico es justamente lo que la app sabe y el abogado no.

**B. ¿Los textos son editables?** Si se pueden editar, hay que guardar la versión firmada (otro
snapshot, como `presupuesto_subitems_congelado`); si no, la plantilla tiene que servir tal cual para
todos, que es mucho pedir.

**C. ¿Queda atado a la obra?** Un contrato generado y firmado debería congelar el alcance y el
precio de ese momento, igual que el congelamiento del presupuesto. Y si después hay adicionales,
¿generan addenda?

**D. ¿Jurisdicción?** Las cláusulas cambian por provincia. La primera versión probablemente sea
nacional y genérica, pero conviene saber que ese límite existe antes de prometer.

**E. ¿PRO o gratis?** Cae del lado de PRO por olfato, pero es de las piezas que un profesional usa
una vez por obra y que puede justificar sola la suscripción.

## 5. Relación con lo que ya existe

- **No lo confundas con el Libro de Obra**: uno es el acuerdo inicial, el otro el registro diario.
  Comparten el generador de PDF y nada más.
- **Depende de que el presupuesto esté congelado** para el precio pactado: sin eso, el contrato sale
  con un número que se mueve.
- **`perfiles.matricula` ya existe para esto** (`0100`), y hoy no la usa ninguna pantalla.
