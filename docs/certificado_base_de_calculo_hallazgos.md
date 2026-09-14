# Sobre qué base calcula el certificado — tres hallazgos (2026-09-14)

Salieron de cargar la obra real de Galpón Mix y verificar los montos contra `CERTIFICADO 1.pdf`, el
certificado que Seba emitió de verdad. **Ninguno de los tres se había detectado antes**, y el motivo
es el mismo: hasta ahora los certificados se probaron con obras armadas para la prueba, donde los
números se comparaban contra lo que la app misma calculaba. Contra un papel real aparecen.

El script de carga (`supabase/seed_staging/obra_real_galpon_mix.sql`, fuera de git) **no corrige
ninguno de los dos**: reproduce el papel y muestra la diferencia en su verificación final. Corregir
es una migración, y una decisión.

---

## Hallazgo 1 — el fondo de reparo se calcula sobre otra base que en el papel — **CONFIRMADO, a corregir**

**Este es el importante, porque no depende de ninguna pieza pendiente y afecta a todas las obras con
anticipo.**

`calcular_totales_certificado` (`0105`) hace las dos retenciones sobre el **mismo monto bruto**:

```sql
monto
  - round(monto * anticipo_pct / 100, 2)
  - round(monto * fondo_reparo_pct / 100, 2)  as monto_neto
```

El certificado real hace otra cosa: **descuenta el anticipo y recién sobre ese resto aplica el fondo
de reparo.** Se ve fila por fila en el PDF; la 1.1, con sus números exactos:

| Paso | PDF | La app |
| --- | --- | --- |
| Monto certificado | 59,18 | 59,18 |
| Anticipo 20% | −11,84 | −11,84 |
| **Subtotal a certificar** | **47,34** | (no existe) |
| Fondo de reparo 5% | 5% de **47,34** = −2,37 | 5% de **59,18** = −2,96 |
| Total a pagar | 44,98 | 44,38 |

Sobre el CERTIFICADO 1 completo la diferencia es de **USD 33,99**, que es exactamente el 5% del
anticipo — la fórmula de la diferencia es `fondo% × anticipo% × monto`, así que crece con el tamaño
del certificado y con las dos alícuotas.

**Y la columna del PDF se llama "SUBTOTAL A CERTIFICAR", que es el nombre del concepto que falta.**
No es un redondeo ni una interpretación: son dos cuentas distintas, y la del papel es la que rige
en el contrato.

### Confirmado por Seba (2026-09-14)

Era la pregunta que faltaba y quedó respondida:

> *"El fondo de reparo se retiene sobre el neto, después de descontar el anticipo. Es la base general
> en obra, no cómo factura mi empresa. La columna de mi planilla se llama 'subtotal a certificar'
> justamente por eso."*

O sea que **la app está mal y el papel está bien**, en general y no en un caso. El nombre de la
columna no era una etiqueta: era el concepto que falta.

### La decisión sobre lo ya emitido: rige de acá en adelante

También de Seba, y con un precedente del propio proyecto: *"igual que hicimos con la cotización"*.

Un certificado emitido guarda `anticipo_pct_aplicado`, `fondo_reparo_pct_aplicado`,
`monto_fondo_reparo_retenido` y `monto_neto_a_pagar` **congelados**. Eso no es una caché que se pueda
recalcular: es el registro de lo que se emitió y se entregó. Es exactamente el criterio con el que la
`0107` y la `0122` trataron la cotización — cada documento queda con la suya, y los anteriores no se
reescriben.

### Lo que hay que mirar igual, porque no es solo cosmético

**El fondo de reparo es plata que se devuelve al final de la obra.** Retener de menos no es un error
de visualización: al momento de la devolución, lo que se devuelve es lo que se retuvo. Así que una
obra con certificados emitidos bajo las dos reglas va a tener un **total retenido que mezcla dos
criterios**, y ese total es el que se liquida al cerrar.

Dos consecuencias concretas:

- la diferencia por certificado es `fondo% × anticipo% × monto` — con 20% y 5%, **el 1% de lo
  certificado**. No compone entre certificados, pero se acumula en el total del fondo;
- **Galpón Mix ya tiene un certificado emitido con la regla vieja** (USD 33,99 retenidos de menos).
  Si se quiere que la obra real quede fiel al papel, la salida no es tocar la fila sino **anular y
  reemplazar** ese certificado después de corregir — el circuito de anulación existe justamente para
  esto. Con el script de carga es más simple todavía: recargar la obra.

### Qué falta para corregirlo

- una migración sobre `calcular_totales_certificado`, de dos líneas: el fondo de reparo se aplica
  sobre `monto - monto_anticipo`, no sobre `monto`;
- **y decidir si el "subtotal a certificar" se muestra**, que es la parte de producto. Hoy la
  pantalla del certificado va del monto directo al neto; el papel tiene ese escalón en el medio, y
  sin él la cuenta no se puede seguir. Mi lectura es que tiene que estar — es el número sobre el que
  se calcula la retención, y un certificado que no deja reconstruir su propia cuenta obliga a
  confiar.

## Hallazgo 2 — con el ajuste pactado en el snapshot, la plata se calcula sobre la base sin descuento

Depende de la pieza del ajuste pactado (`docs/descuento_pactado_horizonte.md`), así que es más
esperable que el anterior — pero conviene tenerlo escrito porque **se activa en el momento en que
esa pieza se construya con la forma que ya se eligió**.

Cada fila de avance guarda dos montos (`0105`):

| Columna | De dónde sale | Lleva el ajuste pactado |
| --- | --- | --- |
| `monto_periodo` | `calcular_monto_obra_subitems`, los precios **vivos** | no |
| `monto_periodo_pactado` | `presupuesto_subitems_congelado` | **sí** |

Y `calcular_totales_certificado` calcula el anticipo, el fondo de reparo y **el neto a pagar** sobre
`monto_periodo`, el vivo. Solo `monto_pactado` sale del congelado.

Consecuencia concreta, medida sobre el CERTIFICADO 1 de Galpón Mix: el subtotal pactado da
**3.399,06 — exacto al PDF**, pero el neto a pagar se calcula sobre 3.540,67 en vez de 3.399,06, o
sea **sobre un 4% de más**. Es el mismo problema que el doc del descuento describe en grande
("certificaría USD 3.150 de más"), visto en un solo certificado.

La forma de resolverlo probablemente sea que las retenciones se calculen sobre el pactado y no sobre
el vivo, pero eso hay que pensarlo junto con la pieza del ajuste, no antes.

### Y un efecto cosmético del mismo origen

`calcular_totales_certificado` devuelve `monto_ajuste_cac = monto - monto_pactado`. Con el ajuste
pactado adentro del congelado, esa resta deja de ser solo CAC. En Galpón Mix, que tiene
`aplica_cac = false`, **todo lo que aparezca ahí es el descuento mal etiquetado** (unos USD 141 en el
certificado 1). No mueve plata, pero si aparece en una demo hay que saber qué es.

---

## El control que acota los dos primeros

Si se hace la cuenta a mano sobre el adicional —100% de la partida 1.1, anticipo 0%, fondo 5%— da
**930,06, idéntico al PDF**. No es casualidad: ese caso no tiene ninguno de los dos problemas, porque
el adicional no lleva descuento (hallazgo 2 no aplica) y con **anticipo 0%** las dos bases del
hallazgo 1 coinciden.

O sea que la aritmética de retenciones está bien donde las dos bases coinciden; lo que está mal es
**sobre qué base se aplican**. Eso acota el arreglo a `calcular_totales_certificado` y descarta que
haya algo roto aguas arriba.

(Ese número no se puede ver hoy en la app: el hallazgo 3 explica por qué un adicional no tiene
certificado.)

---

## Hallazgo 3 — el certificado de un adicional no es representable — **CERRADO y VERIFICADO**

Salió de la misma carga, cuando Seba vio en el teléfono que el adicional decía **0% certificado**
aunque su certificado estaba emitido.

**La causa era un error de la carga, y destapó una pieza que falta.** El script había emitido un
certificado sobre la obra hija, igual que en la madre. Está mal: **un adicional nunca certifica por
su cuenta** — `PresupuestosScreen` le esconde la solapa Gestión de Obra a una obra hija justamente
por eso. Ese certificado era un documento que ninguna pantalla de la app puede crear: existía en la
base y no lo veía nadie.

Lo que la app sí tiene es `certificar_avance_adicional` (`0120`), que acumula en
`modificaciones_obra.porcentaje_avance` y `monto_certificado`. Eso es lo que lee la lista de
adicionales, y por eso marcaba cero.

**Lo que falta:** `CERTIFICADO 1 ADICIONAL.pdf` es un documento con sus retenciones — descuenta 5% de
fondo de reparo y llega a USD 930,06 a pagar. La app **solo guarda el porcentaje y el monto bruto**:
no hay número de certificado, ni fecha de emisión, ni retenciones, ni plazo de pago para el avance de
un adicional.

Así que hoy la app puede decir *"se certificó el 26,77% del adicional, USD 979,01"* y no puede emitir
el papel que el comitente recibe. Para una obra con adicionales certificados —que es el caso normal—
es una asimetría notoria: el contrato tiene certificados de verdad y sus adicionales no.

**CERRADO el mismo día por la `0148`**, con la primera de las tres opciones: el adicional emite sus
propios certificados. Seba: *"el camino chico me deja a mitad de camino y hay que rehacerlo igual"*.

Y resultó ser la opción más chica de las tres, no la más grande: **un adicional ya ES una obra**
(`0113`), con partidas, miembros, retenciones propias y numeración de certificados por obra. La
maquinaria ya funcionaba sobre la hija; lo único que faltaba era usarla y que la madre se entere. La
`0148` no construye un segundo circuito — **borra el segundo circuito** (el porcentaje suelto) y deja
el que ya existía.

**Verificado en el teléfono por Seba (2026-09-14)**, con la obra real cargada: el certificado Nº 1
del adicional con su desglose por partida, el porcentaje del adicional actualizándose solo en la
lista (lo escribe el trigger, nadie lo tipea) y la configuración propia del adicional, con sus
retenciones distintas de las de la obra.

Lo que sigue abierto de esta pieza es el **hallazgo 1**: la base de cálculo del fondo de reparo. En
el adicional no se nota porque tiene anticipo 0% y ahí las dos cuentas coinciden -- por eso su neto
da exacto contra el PDF. En el certificado de la obra, con anticipo 20%, la diferencia es de USD
33,99.
