# Sobre qué base calcula el certificado — tres hallazgos (2026-09-14)

Salieron de cargar la obra real de Galpón Mix y verificar los montos contra `CERTIFICADO 1.pdf`, el
certificado que Seba emitió de verdad. **Ninguno de los tres se había detectado antes**, y el motivo
es el mismo: hasta ahora los certificados se probaron con obras armadas para la prueba, donde los
números se comparaban contra lo que la app misma calculaba. Contra un papel real aparecen.

El script de carga (`supabase/seed_staging/obra_real_galpon_mix.sql`, fuera de git) **no corrige
ninguno de los dos**: reproduce el papel y muestra la diferencia en su verificación final. Corregir
es una migración, y una decisión.

---

## Hallazgo 1 — el fondo de reparo se calcula sobre otra base que en el papel

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

Qué implicaría corregirlo:

- una migración sobre `calcular_totales_certificado`, de dos líneas;
- **decidir qué pasa con los certificados ya emitidos**, que guardan `monto_fondo_reparo_retenido` y
  `monto_neto_a_pagar` congelados. Son un snapshot de lo que se emitió, así que recalcularlos
  cambiaría documentos ya entregados. Lo más probable es que haya que dejarlos como están y que la
  corrección rija de acá en adelante — pero es una decisión, no un detalle de implementación;
- confirmar antes que la base correcta es la del PDF en general y no una particularidad de cómo
  factura esta empresa. **Lo primero es eso**, no el SQL.

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

## Hallazgo 3 — el certificado de un adicional no es representable — **CERRADO por la 0148**

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
