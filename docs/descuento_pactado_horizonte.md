# El descuento pactado sobre el presupuesto — pieza anotada (2026-09-14, sin construir)

Salió de revisar los PDF reales de **Galpón Mix** (el presupuesto, un adicional y dos certificados)
contra lo que la app puede representar hoy.

> **El caso, con los números reales:** el presupuesto se cotizó en **USD 78.759,38** y el contrato se
> firmó en **USD 75.609,01**. Un **4% de descuento global**, negociado *después* de cotizar y
> aplicado parejo a todas las partidas.

**Hoy la app no puede representarlo.** `congelar_presupuesto_obra` (`0104`) congela el presupuesto
tal como se calculó, y no hay ningún lugar donde decir "se pactó un 4% menos". La única salida
disponible es ir partida por partida bajando precios — y eso, además de ser un trabajo absurdo en una
obra de 700 subítems, **ensucia el Factor K**: los precios dejarían de ser los que la empresa calculó
y pasarían a ser una mezcla de costo real y descuento comercial, que es justo lo que el Factor K
existe para mantener separado.

## Por qué importa más de lo que parece

No es un caso raro: **negociar un porcentaje global sobre el total cotizado es la forma normal de
cerrar una obra en Argentina.** Se cotiza con la estructura de costos que corresponde y después se
resigna un punto de beneficio para ganar el trabajo. La app hoy modela bien la primera mitad y no
tiene dónde poner la segunda.

Y tiene consecuencia aguas abajo, que es lo que lo vuelve una pieza y no un detalle: **todo lo que
certifica se calcula sobre el monto congelado**. Sin el descuento adentro, los certificados suman al
precio cotizado y no al contratado — o sea que la obra terminaría certificando **USD 3.150 de más**
sobre un contrato de 75.609.

## La forma que probablemente convenga

**Un porcentaje en la obra, aplicado al congelar.** Es decir: el descuento entra en
`presupuesto_subitems_congelado` en el momento del congelamiento, y el snapshot ya queda con los
montos pactados.

La ventaja es que **no toca nada aguas abajo**: los certificados, el avance ponderado, el CAC, la
cotización congelada y los adicionales leen el snapshot, y el snapshot ya dice la verdad. Es el mismo
razonamiento que hizo chica la Tanda 4 del avance global — si el número correcto está en la tabla que
todos leen, no hay que enseñarle el descuento a nadie más.

Lo que hay que guardar además del porcentaje: **el monto cotizado original**. El contrato dice las
tres cosas —cotizado, descuento, pactado— y sin el primero no se puede reconstruir ni explicar de
dónde salió el segundo.

## Ambigüedades a cerrar antes de escribir SQL

**A. ¿El porcentaje se congela con el presupuesto?** Debería: si se pudiera cambiar después, el
"precio pactado" dejaría de ser un número cerrado y volvería a moverse — que es exactamente lo que la
`0104` vino a evitar. Recomiendo que siga la misma regla que el resto del congelamiento: se puede
cambiar mientras no haya certificados emitidos, y después no.

**B. ¿Solo descuento, o también recargo? — CERRADA (Seba, 2026-09-14): los dos signos, y se llama
"ajuste pactado".** Cuesta lo mismo y cubre la obra que cierra por encima de lo cotizado, que también
pasa.

**C. ¿Los adicionales heredan el descuento?** Mi lectura es que **no**: un adicional se negocia
aparte y se aprueba con su propio monto. Pero hay que decirlo, porque la intuición puede ir para el
otro lado ("si toda la obra tiene 4% menos, el adicional también").

**D. ¿Qué pasa con las quitas y demasías? — CERRADA (Seba, 2026-09-14): una demasía posterior entra
CON el ajuste aplicado.** Las quitas y demasías modifican `presupuesto_subitems_congelado` **después**
del congelamiento (`0109`), así que había que decidir con qué precio entran. Textual: *"si no, dos
partidas de la misma obra tendrían precios de criterios distintos y nadie se enteraría"*. Era la más
fácil de pasar por alto de las cinco, y la que peor falla: el error no se vería en ninguna pantalla,
solo en el total.

**E. ¿Dónde se ve?** Como mínimo en el resumen del presupuesto: "Cotizado / Ajuste pactado / Total
contratado", las tres líneas. Y fijo en el PDF del presupuesto y del contrato cuando existan — es
información del acuerdo, no un detalle de cálculo.

## Con qué no confundirlo

- **No es `obras.monto_total_contratado`**, que es del Modelo B (hitos de precio cerrado) y no tiene
  nada que ver con esto.
- **No es el Factor K.** El Factor K es la estructura de costos con la que se cotiza; el ajuste
  pactado es lo que se resigna después de cotizar. Mezclarlos es justamente lo que esta pieza
  evita — y el motivo por el que bajar precios partida por partida no sirve como solución.
- **No es una quita.** Una quita saca trabajo del alcance; esto deja el mismo alcance a otro precio.
