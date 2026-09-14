# Moneda de pacto por monto — Nivel 2, diagnóstico (2026-09-14, sin código)

El Nivel 2 estaba pospuesto **hasta que hubiera una obra real pactada en otra moneda**
(`docs/adicionales_quitas_demasias_diagnostico.md` §15.4). Galpón Mix es esa obra, así que se
destraba por la condición que se había fijado, no por adelantarse.

Antecedentes que no se rediscuten acá: `docs/cotizacion_congelada_montos_cerrados_diseno.md`
(Nivel 1, aplicado en la `0122`) y §15.2/§15.3 del doc de adicionales, donde ya quedó cerrado **cómo
se muestra** un total de monedas distintas. Este documento releva el estado real, corrige dos cosas
que se daban por sabidas, y contesta las cinco preguntas.

---

## 0. Primero: la obra cargada está mal, y es mi error

**Hay que arreglarlo antes de la demostración, y es la mejor demostración del problema.**

`GALPON MIX - Emilio Frey 536` quedó con `moneda = 'USD'` y con los números del PDF (410,96;
10.615,49; 75.609,01) metidos en `obra_subitems.precio_unitario_manual`. Pero **todo el sistema de
precios guarda pesos** — `obras.moneda` es una lente, no una unidad — así que la app va a tomar esos
75.609 como pesos y dividirlos por la cotización congelada: la tarjeta va a mostrar **unos USD 58**
en vez de USD 75.609,01.

El script de carga no tiene forma de hacerlo bien, y ese es exactamente el punto: **hoy un contrato
genuinamente pactado en dólares no es cargable sin mentirle al esquema.** No es un bug del script, es
la pieza que falta.

Las dos salidas provisorias, para la demo:

| | Qué queda | Qué se pierde |
| --- | --- | --- |
| **A. `moneda = 'ARS'`** | Los montos se muestran tal cual el PDF: `$ 75.609,01` | Dice pesos donde el contrato dice dólares. La magnitud es correcta y la unidad no |
| **B. Multiplicar los precios por la cotización congelada** | La tarjeta muestra `USD 75.609,01`, correcto, **y no se mueve** porque la cotización ya está congelada | Los pesos guardados son fabricados a la cotización de hoy; para el Factor K son precios que la empresa nunca calculó |

**Recomiendo B**, y no como parche: "monto en pesos + cotización congelada" **es** la forma en que el
sistema representa hoy un monto fijo en dólares. `monto / cotizacion_congelada` es una constante.
Lo único que falta es el rótulo que diga cuál de los dos números es el pactado y cuál el derivado —
que es, en una línea, todo el Nivel 2.

## 1. Qué hay hoy, y qué falta de verdad

### Lo que el Nivel 1 ya dejó resuelto

Cada monto cerrado **ya tiene su propia cotización congelada**, y la tarjeta **ya convierte cada uno
con la suya**:

| Momento | Dónde está la cotización |
| --- | --- |
| Congelar el presupuesto | `obras.cotizacion_dolar_al_congelar` (`0122`) |
| Aprobar un adicional | `modificaciones_obra.cotizacion_dolar_al_aprobar` (`0122`) |
| Emitir un certificado | `certificados.cotizacion_dolar_promedio_al_emitir` (`0107`) |

`AdicionalesRepository.getAprobadosPorObra` devuelve el detalle por adicional **a propósito**, con su
cotización: *"devuelve el detalle y no el total justamente para que sumar sea decisión de quien
muestra, no del repositorio"*. Esa decisión de diseño es la que hace barata esta pieza.

### El hallazgo: el vehículo de la moneda por pacto YA EXISTE

Esto no estaba en el diagnóstico anterior, que hablaba de "agregar `modificaciones_obra.moneda_pactada`
y el monto en esa moneda" como si hubiera que inventar el dato.

**Un adicional presupuestado con la app ES una fila en `obras`** (obra hija, `0113`). Y una fila de
`obras` ya tiene **su propia `moneda` y su propio `aplica_cac`**. O sea:

- la moneda del **contrato** es `obras.moneda` de la madre;
- la moneda de **cada adicional** es `obras.moneda` de su hija;
- el gate del CAC ya es por pacto, porque `factor_cac` lee el `aplica_cac` **de la obra que recibe**,
  y la hija tiene el suyo.

La columna existe, la semántica existe. **Lo que falta es que alguien la pueda poner distinta y que
los lectores la miren.** Concretamente, lo que hay que tocar:

1. **`crear_adicional_presupuestado` copia la moneda de la madre** y no hay ninguna pantalla que la
   deje cambiar. Hoy un adicional hereda la moneda del contrato y no puede diferir.
2. **Los lectores usan la moneda de la madre para todo.** `getAprobadosPorObra` ni siquiera trae la
   de la hija: consulta `modificaciones_obra` sin join a `obras` por `obra_hija_id`.
3. **La tarjeta suma sin mirar moneda**: `_buildMontoCerrado('Total', monto + montoAdicionales,
   obra['moneda'])`. Hoy es inofensivo porque hay una sola moneda; deja de serlo el día 1 del
   Nivel 2.
4. **Nada impide la combinación incoherente**: un pacto en dólares con `aplica_cac = true`.

### La decisión de fondo, que es de negocio y no de esquema

Un monto guardado en pesos con su cotización congelada **ya define un monto fijo en dólares**. La
pregunta que el esquema no puede contestar solo es **cuál de los dos números es el pacto**:

- **el pacto es el peso** (dólares derivados) — lo que vale hoy para todo;
- **el pacto es el dólar** (pesos derivados) — lo que dice el contrato de Galpón Mix.

No es filosofía: cambia qué pasa si alguien recongela, cambia si el CAC corresponde, y cambia qué
número tiene que quedar fijo cuando el otro se mueve. **Es la ambigüedad A de §6.**

## 2. Cómo se muestra — tu lectura es la que ya estaba cerrada

Lo que proponés coincide exactamente con §15.3 del doc de adicionales, que se cerró el 2026-09-13:

> *"Cada renglón en su moneda de pacto y **dos totales, uno por moneda, sin conversión** — cero
> cotización en la portada."*

Y el criterio de portada lo refuerza: `docs/criterio_pantalla_principal_vs_resumen.md` §2 dice que
**un dato que necesita aclaración no es de portada**. Un total convertido "≈ a la cotización de hoy"
necesita aclaración; entonces la conversión, si se ofrece, va en Resumen.

**La buena noticia es que la tarjeta ya tiene la estructura.** Hoy muestra un renglón por adicional
con el mismo tratamiento visual que el pactado (corrección tuya del 2026-09-13: *"cada adicional es
un monto firmado por sí mismo, no un sumando anónimo"*). Lo único que cambia es el renglón `Total`:

- **todos los pactos en la misma moneda** → un `Total`, igual que hoy;
- **monedas distintas** → un total por moneda (`Total en USD`, `Total en $`), sin ninguna conversión
  entre ellos.

Y en el renglón agrupado ("Otros N adicionales aprobados") hay un detalle que se pasa fácil: **ese
renglón no puede agrupar monedas distintas**. O agrupa por moneda, o cuando hay mezcla se dejan de
agrupar y se listan todos.

**En `PresupuestoEstadoPanel` (Gestión de Obra)** vale el mismo criterio, con una diferencia: ahí sí
se puede mostrar la conversión, porque es la pantalla técnica y profunda. Lo que no puede es
**sumar** sin decir con qué cotización.

## 3. El CAC — el gate ya es por pacto, falta la regla

`factor_cac(obra)` devuelve `indice_actual / indice_base` y está gateado por `obras.aplica_cac` de la
obra que se está calculando. Como cada adicional es su propia obra, **el CAC ya se puede prender y
apagar por pacto**. No hace falta nada nuevo para eso.

Lo que falta es la regla que hoy nadie hace cumplir: **el CAC no puede ajustar un pacto en dólares.**
El CAC es un índice de costos en pesos; un monto pactado en dólares ya está protegido de la inflación
en pesos por su propia naturaleza, y ajustarlo además por CAC sería cobrar dos veces la misma
cobertura.

Los dos casos que planteaste, resueltos:

| Contrato | Adicional | Qué corresponde |
| --- | --- | --- |
| USD | ARS | El contrato **no** se ajusta. El adicional **sí**, con el CAC de su hija, desde su propio mes base |
| ARS | USD | El contrato **sí** se ajusta. El adicional **no** |

Y una consecuencia que conviene ver antes de que aparezca en pantalla: en el primer caso, el
`Total` estaría sumando **un monto en dólares fijo** con **un monto en pesos que se mueve todos los
meses**. Aunque se resolviera la conversión, ese total sería un número distinto cada vez que se
mira, sin que nada haya cambiado. Es otro motivo, independiente del de §2, para no sumarlos.

Cómo hacer cumplir la regla: lo natural es un `check` que impida `aplica_cac = true` con
`moneda = 'USD'`. **Recomiendo el check y no solo la UI**: es una incoherencia invisible que mueve
plata, y el proyecto ya tiene el antecedente de que un supuesto no escrito en la base termina roto
(la `0137` con `mis_pendientes`).

## 4. Los certificados — "no hay que tocar nada" es **casi** cierto

Confirmo la mitad: **el esquema no necesita nada.** Un certificado pertenece a **una** obra (la madre
o una hija), así que ya está inequívocamente en la moneda de ese pacto, y `0107` ya le guarda su
cotización. No hay mezcla posible dentro de un certificado.

**Pero hay un problema real en cuál cotización se usa para mostrarlo, y aparece justo con un pacto en
dólares.**

`emitir_certificado` congela la cotización **del día de la emisión**
(`cotizacion_dolar_promedio_al_emitir`). Para un pacto en pesos está perfecto. Para un pacto en
dólares, no: el monto certificado sale del snapshot congelado, que está en pesos a la cotización
**del congelamiento**. Convertirlo con la del día de emisión da:

```
monto_usd_certificado = %_avance × USD_contrato × (cotización_al_congelar / cotización_al_emitir)
```

O sea que **certificar el 10% de un contrato de USD 75.609 no daría USD 7.560,90**, sino ese número
movido por la variación del dólar entre la firma y la emisión. Es exactamente el síntoma que motivó
el Nivel 1 —*"si el número en dólares se mueve solo cuando sube el dólar, ese monto no está
cerrado"*— reaparecido un escalón más abajo.

La corrección no es de datos sino de **qué cotización usa cada cosa**: para un pacto en dólares, lo
certificado contra el contrato se convierte con la **cotización del pacto**, no con la del día. La
del día sigue haciendo falta para otra cosa distinta (cuántos pesos hay que pagar hoy por ese
certificado), así que las dos conviven — pero responden preguntas distintas y hoy se usa una sola
para las dos.

## 5. El tamaño y por dónde partirlo

Es más chico de lo que parecía, porque el vehículo ya existe (§1) y la tarjeta ya tiene la estructura
de renglones (§2). Lo que no se toca: la cascada de Factor K, el congelamiento, el esquema de
certificados, `calcular_monto_obra_subitems`.

**Tanda 0 — la obra cargada (hoy, antes de la demo).** Ver §0. No es parte del Nivel 2: es dejar
Galpón Mix mostrando los números de su PDF. Media hora, sin migración.

**Tanda 1 — la moneda por pacto, y la coherencia con el CAC.** Que `crear_adicional_presupuestado`
acepte la moneda, que se pueda elegir al cotizar el adicional, el `check` de USD + CAC, y que
`getAprobadosPorObra` traiga la moneda de la hija. Una migración chica y dos archivos de Dart. **No
cambia nada de lo que se ve todavía** — y eso es a favor: se puede aplicar y verificar sola.

**Tanda 2 — la portada y Gestión de Obra.** El total por moneda, el renglón agrupado que no mezcla,
y el aviso cuando no se pueden sumar. Solo Dart. Es la tanda que se ve, y la que conviene mirar en el
teléfono con la fuente grande (ver `docs/`, el caso de la tabla de APU).

**Tanda 3 — la cotización correcta del certificado de un pacto en dólares (§4).** Va última a
propósito: es la más delicada porque toca plata ya emitida, y **hay que decidir qué pasa con los
certificados ya emitidos**, que guardan su conversión congelada. Mismo problema de método que el
hallazgo del fondo de reparo (`docs/certificado_base_de_calculo_hallazgos.md`), y probablemente misma
respuesta: rige de acá en adelante.

**Riesgo del conjunto: bajo, salvo la 3.** Las tandas 1 y 2 agregan un caso que hoy no existe; no
cambian ningún número de una obra en una sola moneda. La 3 sí cambia cómo se lee un certificado.

## 6. Lo que hay que decidir antes de escribir

**A. ¿Cuál de los dos números es el pacto?** (§1, la decisión de fondo.) Si el pacto es el dólar, el
peso pasa a ser derivado, y hay que decidir qué pasa si alguien recongela el presupuesto: ¿el monto
en dólares se mantiene y los pesos se recalculan a la cotización nueva? Mi lectura es que sí —es lo
que significa pactar en dólares— pero cambia el comportamiento de `congelar_presupuesto_obra` y por
eso no lo cierro solo.

**B. ¿La moneda del adicional se elige al cotizarlo o al aprobarlo?** Cotizarlo es más natural (es
cuando se decide el precio), pero el monto se congela al **enviar a aprobación**, así que la moneda
tendría que quedar fija en ese mismo momento. Recomiendo: se elige al cotizar y se congela al enviar,
igual que el monto.

**C. ¿Se puede cambiar la moneda del contrato después de congelar?** Hoy `obras.moneda` es editable
siempre, porque no cambiaba ningún monto guardado. Con el Nivel 2 sí lo cambia. Recomiendo
bloquearla con el congelamiento, igual que `modo_carga_avance` (`0132`).

**D. ¿Qué monedas?** Hoy `ARS` y `USD`. ¿Alcanza? Sumar una tercera no cuesta nada ahora y cuesta
después, pero **no recomiendo agregarla sin un caso real** — es el mismo criterio con el que este
Nivel 2 estuvo esperando.

**E. El certificado de un pacto en dólares, ¿en qué moneda se cobra?** Es distinta de §4: una cosa es
qué número muestra el certificado y otra en qué moneda se paga. Si el contrato es en dólares pero se
paga en pesos al día del pago, hace falta un tercer momento (`cotización al pagar`) que hoy no
existe. **No lo metería en esta pieza** — pero conviene saber si ese es el caso real antes de cerrar
la 3, porque cambia si la cotización del día de emisión sigue haciendo falta o no.
