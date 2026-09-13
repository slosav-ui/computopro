# Cotización congelada de los montos cerrados (Nivel 1)

**Estado: Nivel 0 hecho. Migración `0122_cotizacion_congelada_montos_cerrados.sql` escrita, SIN
aplicar. Dart hecho (`flutter analyze` limpio), sin verificar en el emulador — y sin efecto visible
hasta que la migración se aplique: las dos columnas nuevas llegan en `null` y todo cae al
comportamiento de hoy. La ambigüedad de §5 la cerró Seba: histórico puro.**

Pedido de Seba, 2026-09-13, después del relevamiento de
`docs/adicionales_quitas_demasias_diagnostico.md` §15:

> *"Si el número en dólares que le mostré al cliente se mueve solo cuando sube el dólar, ese monto no
> está cerrado. Y con la cotización proyectada editable, se mueven todos a la vez."*

---

## 1. El problema, en una línea

Todo el sistema de precios guarda **pesos**; `obras.moneda` es una **lente**. Una obra en dólares
mostraba el presupuesto pactado y cada adicional aprobado dividiendo un monto fijo en pesos por la
cotización **del día en que se los mira** — así que el número en USD que el cliente vio al firmar
cambiaba solo, y la cotización proyectada editable del dashboard (PRO) los movía todos juntos.

**Los certificados ya no tienen este problema**: la `0107` les agregó
`cotizacion_dolar_promedio_al_emitir`. Esta pieza extiende **ese mismo patrón** a los otros dos
momentos en que un monto queda firmado.

**Alcance (lo que NO hace):** no permite pactar en una moneda distinta a la de la obra. Eso es el
Nivel 2 (§15.2 del doc de adicionales) y queda para cuando haya una obra real así. Acá la moneda de
pacto sigue siendo una sola: lo que se arregla es que la lente deje de moverse sobre lo ya cerrado.

## 2. Los tres momentos en que un monto queda firmado

| Momento | Función | Snapshot |
| --- | --- | --- |
| Emitir un certificado | `emitir_certificado` | `certificados.cotizacion_dolar_promedio_al_emitir` — **ya existía** (0107) |
| Congelar el presupuesto | `congelar_presupuesto_obra` | `obras.cotizacion_dolar_al_congelar` — **0122** |
| Aprobar un adicional | `aprobar_adicional` | `modificaciones_obra.cotizacion_dolar_al_aprobar` — **0122** |

## 3. Datos (migración 0122)

Dos columnas `numeric` nullable, y el snapshot dentro de las dos funciones que ya existen —
recreadas con `create or replace` copiando el cuerpo vigente (0121 y 0118 respectivamente), con el
agregado y nada más. Ambas funciones anotan el valor en `audit_log`, como hace 0107.

La lectura es idéntica a la de 0107: `select (compra + venta) / 2 from cotizacion_dolar_bna limit 1`.

## 4. Decisiones tomadas (no son ambigüedades, quedan dichas para no rediscutirlas)

1. **Promedio compra/venta de BNA, sin la proyección personalizada PRO.** La proyección es local al
   dashboard y nunca se persiste: no hay nada que snapshotear de eso.
2. **La proyección personalizada no toca los montos cerrados.** Mueve lo vivo (presupuesto
   estimado/vivo, el "Hoy" del chip), nunca el pactado ni un adicional aprobado. Es exactamente el
   síntoma que Seba señaló.
3. **El desfasaje del chip "Hoy · Desfasaje" se calcula siempre en pesos.** Hoy el porcentaje sale
   de los dos montos ya convertidos y la conversión se cancela en la división. Con el snapshot dejan
   de usar la misma cotización, así que el porcentaje pasaría a incluir la variación del dólar —
   justo la mezcla que la `0110` sacó (desfasaje de precio vs. desfasaje de configuración). El
   desfasaje mide costos: se calcula en pesos y se muestra igual en cualquier moneda.
4. **Recongelar reescribe el snapshot.** Es un congelamiento nuevo, con su fecha y su cotización;
   se borra y rearma todo el snapshot en la misma transacción, igual que el resto.
5. **Filas viejas: `null` → cotización de hoy, marcado como aproximación.** Mismo criterio que 0107,
   y por el mismo motivo: `cotizacion_dolar_bna` es una fila única sin serie histórica, no hay cómo
   reconstruir qué cotización regía el día del congelamiento. No es retroactivo y no se inventa.
6. **Un adicional pendiente sigue mostrando su monto en dólares VIVO, a propósito.** Todavía no hay
   nada firmado. El snapshot se toma al aprobar, que es la firma.
7. **Por qué al aprobar y no al enviar** (camino de obra hija, donde el monto ya queda fijo en el
   envío): para el camino de monto fijo la aprobación es el único momento posible — el trigger
   `calcular_monto_total_adicional` (0112) recalcula mientras está pendiente. Un solo momento para
   los dos caminos, y es el que corresponde conceptualmente: la firma.
8. **La obra hija recibe de paso su propio `cotizacion_dolar_al_congelar`**, porque
   `enviar_adicional_a_aprobacion` llama a `congelar_presupuesto_obra(hija)`. Es inofensivo y no se
   usa para mostrar el adicional: el que manda es el de la aprobación.

## 5. Aritmética entre montos congelados a cotizaciones distintas — CERRADA (Seba, 2026-09-13)

**Decisión: Opción A, histórico puro.** Cada monto cerrado se muestra con su propia cotización, el
total en dólares es la suma de esos números y el saldo la resta. **Ningún número firmado se mueve
nunca.** Lo que sigue es el planteo completo, para no reabrirlo.

Después de esta pieza, cada monto cerrado tiene **su** cotización. Las **cuentas entre ellos** dejan
de tener una respuesta única en dólares. Dos casos reales:

- **Total de la card** = pactado (cotización del congelamiento) + cada adicional (cotización de su
  aprobación).
- **Saldo pendiente** (`PresupuestoEstadoPanel`) = pactado − certificados emitidos, y cada
  certificado tiene la suya desde la 0107.

**Opción A — histórico puro (ELEGIDA).** Cada monto a su cotización; el total en USD es la suma
de esos números, el saldo es la resta. **Nada se mueve nunca.** Es la continuación natural de 0107 y
de este pedido. Contra: si el dólar se movió mucho, el saldo en dólares no coincide con
"saldo en pesos ÷ cotización de hoy" — es un número histórico, no una valuación de hoy. La
aclaración de que es "a la cotización de cada momento" cabe dentro de la obra, donde las
aclaraciones están permitidas (`docs/criterio_pantalla_principal_vs_resumen.md`).

**Opción B — híbrido.** Los montos cerrados con su snapshot, pero los derivados (total, saldo) se
calculan en pesos y se convierten a la cotización de hoy. Contra: reintroduce el número que se mueve
solo, en el renglón que más importa.

**Opción C — derivados solo en pesos** cuando las cotizaciones difieren: no mostrar un total/saldo en
USD que no es de nadie. Contra: rompe la lectura en dólares justo donde el usuario la quiere.

### 5.1 Cómo quedó aplicada

| Monto | Cotización que usa |
| --- | --- |
| Presupuesto pactado | la del congelamiento (`obras.cotizacion_dolar_al_congelar`) |
| Cada adicional aprobado | la de su aprobación (`modificaciones_obra.cotizacion_dolar_al_aprobar`) |
| Total de la card (pactado + adicionales) | ninguna: es la suma de los USD de arriba, cada uno a su cotización |
| Certificado y saldo de un adicional | la de la aprobación de ESE adicional (son porciones de ese monto) |
| Adicional pendiente | la de hoy, a propósito: todavía no hay nada firmado |
| Presupuesto estimado / vivo, y el "Hoy" del chip | la de hoy, incluida la proyección personalizada PRO |
| Saldo pendiente del contrato **sin** CAC | la del congelamiento (es contrato puro) |
| Saldo pendiente **con** CAC | la de hoy — el rótulo ya dice "ajustado a hoy", es un número de hoy |
| Desfasaje del chip | ninguna: el porcentaje se calcula en pesos (decisión 3) |

**Avisos de conversión aproximada (filas sin snapshot, de antes de la 0122):** va uno en
`PresupuestoEstadoPanel`, que es donde vive el contrato y donde una aclaración está permitida. En la
card del dashboard **no** se avisa: la portada no lleva texto explicativo
(`docs/criterio_pantalla_principal_vs_resumen.md` §2) y esos montos se muestran hoy exactamente como
se mostraban antes, sin regresión. En la lista de Adicionales tampoco se marca por fila: el caso
desaparece con la primera aprobación posterior a la migración.

## 6. Dart — hecho (`flutter analyze` limpio, sin verificar en el emulador)

- `lib/services/obras_repository.dart` — mapear `cotizacion_dolar_al_congelar` en `_fromRow` y en
  `getEstadoPresupuesto`.
- `lib/services/adicionales_repository.dart` — `cotizacion_dolar_al_aprobar` en
  `getAprobadosPorObra` y en el `fromMap` del modelo (`lib/data/models/modificacion_obra.dart`).
- `lib/presentation/dashboard/obras_list_screen.dart` — convertir cada monto cerrado con su propia
  cotización en vez de `_cotizacionUsdEfectiva`; desfasaje en pesos (decisión 3).
- `lib/presentation/obra_detalle/tabs/presupuesto_estado_panel.dart` — pactado y saldo; hay un
  comentario que dice que acá no hay nada que congelar, hay que corregirlo.
- `lib/presentation/obra_detalle/screens/adicionales_screen.dart` — monto del aprobado, certificado
  y saldo del adicional.
- Aviso de conversión aproximada para filas viejas: el patrón ya estaba en
  `detalle_certificado_screen.dart` (`_cotizacionAUsar` + `_avisoConversionAproximada`).

**Cómo quedó en el código, para el que lo retome:** `_convertirMonto` (dashboard), `_fmtMonto`
(panel) y `_fmtMonto`/`_fmtMontoDe` (Adicionales) toman un parámetro opcional `cotizacion`: si viene
y es positiva se usa esa, si no la de hoy. Así el default sigue siendo el comportamiento vivo y solo
los montos firmados pasan su cotización — no hay que acordarse de nada en los lugares nuevos que
muestren montos vivos. `_fmtMontoDe(m, monto)` elige sola según el estado de la modificación.

## 7. Verificación

La migración trae las consultas al pie (columnas creadas, filas viejas en null, congelar y aprobar
de prueba contra el promedio del día, `audit_log`, y que recongelar y el candado de `monto_visto`
sigan funcionando igual).
