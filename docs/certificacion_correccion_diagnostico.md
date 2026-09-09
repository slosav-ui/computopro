# Corrección de la certificación — diagnóstico previo a implementar (2026-09-09)

Punto 1 del orden de ejecución de `docs/diagnostico_general_producto.md`. **Solo diagnóstico —
nada de esto se implementó.** Objetivo: saber exactamente qué toca el cambio antes de escribir la
migración, con cada afirmación verificada contra el código actual, no asumida.

## El cambio, en una línea

`calcular_monto_obra_subitems` (0052) tiene una rama para partidas con APU (`usa_apu = true`) que
hoy llama a `calcular_precio_apu_subitems` (sin cascada). Cambiarla para que llame a
`calcular_precio_final_apu_subitems` (0090/0092, con la cascada completa y el selector de
vista/impuestos ya resueltos adentro) en su lugar. Cambio mecánico: renombrar la columna que lee
(`precio_total` → `precio_final`) en las CTEs `apu_precios`/`apu` de esa función. Nada más en SQL
necesita tocarse — el resto de la cadena (trigger, vista previa, emisión, avance ponderado, 100%)
consume `calcular_monto_obra_subitems` sin saber cómo calcula el precio adentro, así que el
arreglo vive en un solo punto.

## 1 · Qué depende de `calcular_monto_obra_subitems`, completo

Grep exhaustivo sobre `supabase/migrations/*.sql` y `lib/`. Cinco consumidores, sin ninguno más:

```
calcular_monto_obra_subitems (0052)
  ├─ calcular_monto_periodo_avance (trigger BEFORE INSERT/UPDATE en certificado_subitems_avance)
  │    └─ certificado_subitems_avance.monto_periodo
  │         └─ calcular_totales_certificado (0054) → vista previa Y emitir_certificado (comparten
  │              la función — sin divergencia entre lo que se previsualiza y lo que se congela)
  ├─ calcular_avance_ponderado_rubros(obra_id) (0052) → avance_pct + monto_ponderado por rubro
  │    └─ calcular_avance_ponderado_obra(obra_id) (0052) → avance_pct de la obra completa
  └─ CertificadoSubitemsAvanceRepository.getMontoObraSubitems (RPC directo desde Dart)
       └─ CargaAvanceSubitemsScreen._montoPorObraSubitem
```

**Lo que sube de valor:**

- `certificado_subitems_avance.monto_periodo` (filas nuevas o re-guardadas — ver punto 3, no es
  automático para lo ya cargado).
- `calcular_totales_certificado`: `monto`, `monto_anticipo`, `monto_fondo_reparo`, `monto_neto` —
  en la vista previa de un borrador y en lo que `emitir_certificado` congela al emitir.
- `calcular_avance_ponderado_rubros`: `monto_ponderado` (el peso mismo, expuesto como plata).
- El RPC que alimenta `getMontoObraSubitems`.

**Lo que en principio NO cambia de valor — verificado, no asumido:**

- `calcular_avance_acumulado_subitem` (usada por el candado del 100% y por
  `calcular_avance_ponderado_rubros` como "valor" de la ponderación): `select
  coalesce(sum(csa.porcentaje_periodo), 0) from certificado_subitems_avance ...` — solo suma
  `porcentaje_periodo`, cero referencia a monto o precio en toda la función. Confirmado, punto 5
  del pedido.
- `avance_pct` (el % ponderado por rubro/obra) es **matemáticamente invariante** en la vista
  "Materiales + Mano de Obra" (la default, y la única que ve Free): la cascada de esa vista
  multiplica el costo-costo de CADA partida por el MISMO factor (mismos `gg_pct`/
  `imprevistos_pct`/etc. de `obra_presupuesto_config`, sin ninguna rama que dependa de la
  composición de esa partida en particular) — cuando todos los pesos de un promedio ponderado se
  escalan por la misma constante, el promedio no cambia.
- **Matiz, no invariante en la vista "Mano de Obra Sola" (PRO)**: ahí la línea "Gestión de
  materiales de terceros" (0078) depende del `materiales_subtotal` propio de CADA partida, que no
  escala igual entre partidas con distinta proporción de materiales — el peso de cada partida ya
  no se escala por una constante única, así que `avance_pct` en esa vista puede moverse un poco
  (probablemente chico, el default de esa línea es 4% sobre materiales). No es un error del
  arreglo, es una consecuencia real de que el peso deja de ser un simple costo de insumos.

**Lo que existe pero no se ve en ningún lado hoy, así que su cambio de valor no tiene consecuencia
visible:**

- `calcular_avance_ponderado_rubros`/`calcular_avance_ponderado_obra`: expuestos en
  `CertificadoSubitemsAvanceRepository` (`getAvancePonderadoRubros`/`getAvancePonderadoObra`) con
  su propio modelo Dart (`AvancePonderadoRubro`), pero **ninguna pantalla los llama** — grep
  completo sobre `lib/presentation/` sin resultados. Van a devolver números más altos el día que
  se conecten, no antes.
- `CargaAvanceSubitemsScreen._montoPorObraSubitem`: se carga (`getMontoObraSubitems`) pero **no se
  lee en ningún lugar del archivo** (463 líneas, grep completo) — el único monto que muestra esa
  pantalla es `item.montoPeriodo`, que viene de `certificado_subitems_avance` ya guardado, no de
  este mapa. Es un fetch muerto, no aporta ni resta nada al cambio.

## 2 · Certificados ya emitidos — CONFIRMADO por código, no se mueven

Tres mecanismos independientes lo garantizan, verificados en el código actual:

1. `emitir_certificado` exige `estado = 'borrador'` antes de escribir — un certificado ya
   `'emitido'` no puede volver a pasar por esa función (`raise exception` si no está en borrador).
2. El trigger `calcular_monto_periodo_avance` (el que recalcula `monto_periodo`) exige lo mismo
   sobre el certificado padre: `if v_estado is distinct from 'borrador' then raise exception`.
   Ninguna fila de `certificado_subitems_avance` de un certificado ya emitido puede insertarse ni
   actualizarse nunca más — el trigger lo bloquea antes de llegar a recalcular nada.
3. Anular un certificado (`0056_certificados_anulacion.sql`) no lo reabre: crea una fila **nueva**
   en `certificados` (`version + 1`, en `'borrador'` desde cero) e inserta ahí de nuevo el avance —
   el propio comentario de esa migración lo dice: *"el trigger de la 0052 recalcula monto_periodo
   solo, así que no arrastra el monto viejo"*. Un certificado anulado y regenerado después del
   arreglo va a nacer ya con la cascada completa, sin ninguna acción manual — lo maneja el diseño
   existente.

**Consecuencia útil**: no hace falta ninguna migración de datos sobre certificados ya emitidos —
quedan como están, tal como tiene que ser.

## 3 · Borradores en curso — MATIZ IMPORTANTE, no es automático

El pedido asumía "sus montos se recalculan con la base nueva" — **verificado que NO es así para
filas que ya existen.**

El trigger recalcula `monto_periodo` **por fila, solo en el INSERT o UPDATE de esa fila puntual**.
Cambiar la función que llama por dentro no reprocesa filas que ya están guardadas — eso requiere
que la fila se vuelva a escribir.

- **Un borrador nuevo, creado después del arreglo** (sin ninguna fila cargada todavía): correcto
  de punta a punta, cada fila que se cargue nace con la cascada completa. Sin problema.
- **Un borrador que YA tiene algún % cargado antes del arreglo**: esas filas específicas quedan
  con el `monto_periodo` viejo (costo puro) hasta que alguien las vuelva a guardar — ya sea porque
  el usuario edita ese mismo % de nuevo (dispara el trigger, recalcula con la cascada), o porque se
  corre algo aparte que las toque a todas. `calcular_totales_certificado` (la vista previa) **suma
  la columna guardada**, no recalcula en vivo desde `calcular_monto_obra_subitems` — así que la
  vista previa de un borrador con filas viejas sin re-tocar va a seguir mostrando el total viejo
  hasta que se re-guarden.

**Confirmado con Seba (2026-09-09)**: existía exactamente un borrador con avance cargado —
certificado N°1 de "Obra de Prueba", 3 filas. Es de prueba, se borra antes de aplicar; no hace
falta migrar datos para ese caso puntual.

**DECISIÓN — qué hacer con esto en general, para cuando le pase a un usuario real:** la migración
fuerza el recálculo (Opción B de abajo), no deja el problema para después con un aviso. Un usuario
real con un borrador a medio cargar en el momento en que se aplique este tipo de cambio no tiene
por qué enterarse de que hubo un cambio de fórmula ni volver a tocar cada fila a mano — es carga
que no debería pagar por un bug nuestro. Implementado en el Paso 2 de
`supabase/migrations/0094_certificacion_usa_precio_final.sql`: un `update ... set
porcentaje_periodo = porcentaje_periodo` sobre toda fila de `certificado_subitems_avance` cuyo
certificado padre siga en `'borrador'` — dispara el trigger `calcular_monto_periodo_avance` sin
cambiar ningún valor real, y esa función recalcula `monto_periodo` con la cascada completa.

**Patrón a repetir**: cualquier migración futura que cambie qué función de precio alimenta
`monto_periodo` (no solo esta) tiene que incluir el mismo `update` — es consecuencia directa de que
el trigger solo recalcula al tocar la fila, nunca en el momento en que cambia la fórmula por
debajo. Anotado en el propio archivo de la migración para que no se pierda la próxima vez.

## 4 · El trigger de `certificado_subitems_avance` — cómo queda

El trigger en sí (`calcular_monto_periodo_avance`) **no se toca** — sigue haciendo exactamente lo
mismo (`new.monto_periodo := round(coalesce(v_monto_total_subitem, 0) * new.porcentaje_periodo /
100, 2)`, leyendo `monto_total` de `calcular_monto_obra_subitems`). El cambio real está un nivel
más abajo, adentro de `calcular_monto_obra_subitems`, en la rama `usa_apu = true`:

```sql
-- Hoy:
apu_precios as (
  select * from calcular_precio_apu_subitems(p_obra_id, (select ids from apu_ids))
),
apu as (
  select b.obra_subitem_id, b.cantidad * p.precio_total as monto_total, ...
  from base b join apu_precios p on p.subitem_id = b.subitem_id
  where b.usa_apu = true
)

-- Después:
apu_precios as (
  select * from calcular_precio_final_apu_subitems(p_obra_id, (select ids from apu_ids))
),
apu as (
  select b.obra_subitem_id, b.cantidad * p.precio_final as monto_total, ...
  from base b join apu_precios p on p.subitem_id = b.subitem_id
  where b.usa_apu = true
)
```

Consecuencia directa, y correcta: `calcular_monto_obra_subitems` empieza a respetar
`tipo_presupuesto` y `aplica_impuestos` de `obra_presupuesto_config` para la certificación también
— hoy no los respeta, porque `calcular_precio_apu_subitems` no los lee. Es lo mismo que ya se
corrigió para Cómputo/APU/dashboard (0090/0092); certificación pasa a estar en la misma cascada,
con el mismo criterio: se certifica al precio pactado vigente en la obra, sea cual sea la vista y
el estado del interruptor de impuestos en ese momento.

**Costo de performance, no bloqueante**: `calcular_precio_final_apu_subitems` es más cara que
`calcular_precio_apu_subitems` — llama a `calcular_factor_k_subitem` (la cascada completa, 6-7
filas por vista) por cada partida vía `LATERAL`, en vez de un simple promedio ponderado de
insumos. `calcular_monto_obra_subitems` se llama una vez por cada fila de avance que se guarda
(trigger) y una vez por obra completa en `calcular_avance_ponderado_rubros`. El mismo costo ya lo
paga hoy el dashboard (`calcular_presupuesto_vivo_obra`) y Cómputo/APU
(`calcular_precio_final_apu_subitems` directo) para TODAS las partidas tildadas de una obra — no
es una clase de costo nueva, solo un consumidor más pagándolo.

**Caso borde verificado, sin impacto real**: una partida tildada sin ninguna composición cargada
hoy directamente desaparece de la salida de `calcular_precio_apu_subitems` (su `composiciones` CTE
no encuentra fila, y el `group by` final no la incluye) — el trigger la recibe como "sin fila" y
usa `coalesce(v_monto_total_subitem, 0)`, dando `monto_periodo = 0`.
`calcular_precio_final_apu_subitems` sí devuelve una fila para ese caso (vía el `LATERAL` a
`calcular_factor_k_subitem`, que agrega sobre 0 filas y da `costo_costo = 0`), con
`precio_final = 0` e `insumos_total = 0`. Distinto mecanismo, mismo resultado final:
`monto_periodo = 0` en los dos casos. Sin consecuencia práctica, se anota por rigor.

## 5 · Validación del 100% — CONFIRMADO, sin cambios

`calcular_avance_acumulado_subitem` (usada por el candado de `emitir_certificado` vía
`calcular_excesos_certificado`) suma únicamente `porcentaje_periodo` — cero referencia a
`monto_total`, `precio_final` ni ninguna columna de plata en toda la función. El candado del 100%
sigue funcionando exactamente igual, sin ningún cambio de comportamiento.

## Lista de archivos — solo lo que hace falta tocar

**SQL — una sola migración nueva** (ej. `0094_certificacion_usa_precio_final.sql`,
`create or replace function calcular_monto_obra_subitems`): cambia únicamente las CTEs
`apu_precios`/`apu` de esa función, como se detalla en el punto 4. Nada más en `supabase/`
necesita un `create or replace` — ni el trigger, ni `calcular_totales_certificado`, ni
`calcular_excesos_certificado`, ni `emitir_certificado`, ni las funciones de avance ponderado.

**Dart — nada.** Confirmado: ningún archivo de `lib/` duplica el cálculo de precio para
certificación (se respetó siempre el criterio "no dupliques la cuenta en Dart" de 0054) —
`CertificadoSubitemsAvanceRepository`, `carga_avance_subitems_screen.dart`, y cualquier pantalla de
vista previa/emisión siguen consumiendo la misma RPC sin ningún cambio de forma.

**Fuera de código, antes de aplicar**: confirmar si hay algún certificado en `'borrador'` con
avance ya cargado (punto 3) y decidir cómo re-tocarlo si existe.

## La discontinuidad entre lo ya certificado y lo que sigue — cómo se ve, qué decidir

Al aplicar el arreglo, toda partida certificada A PARTIR de ese momento factura al precio final
(con Factor K); todo lo certificado ANTES queda congelado al costo puro (punto 2). Para una obra
con certificados ya emitidos, esto se ve concretamente así en
`CargaAvanceSubitemsScreen`(la lista de certificados por partida, línea ~438,
`'Certificado N°X: Y% — $Z'`):

```
Certificado N°1: 30% — $50.000    (costo puro, pre-arreglo)
Certificado N°2: 40% — $180.000   (precio final, post-arreglo)
```

Dos incrementos de avance parecidos (30% y 40%) con una relación $/% completamente distinta, en la
misma lista, para la misma partida. No es un error de datos — es exactamente el reflejo correcto
de que el criterio de cálculo cambió en el medio — pero es visualmente extraño si alguien lo mira
sin contexto, y en un certificado real (documento comercial, ver
`docs/diagnostico_general_producto.md` §3.10) puede generar una pregunta incómoda de un cliente.

**No se decide ninguna acción acá** (el pedido pide diagnóstico, no implementación), pero quedan
anotadas las opciones para cuando se decida:

1. No hacer nada — aceptar la discontinuidad como el costo de corregir el bug, documentada. Válido
   mientras solo haya obras de prueba (confirmado por el usuario: no importa ahí).
2. Antes de tener el primer usuario real con una obra en curso con certificados ya emitidos, tener
   pensada una comunicación explícita ("a partir del certificado N, el cálculo incluye gastos
   generales/beneficio/impuestos, antes no") — no un ajuste retroactivo de lo ya cobrado.

**Efecto colateral verificado, a tener en cuenta si algún día se usa (no aplica a las obras de
prueba de hoy)**: `puede_gestionar_certificado(obra_id, monto)` (0011) permite a un
`invitado_apoderado` con `tope_monto_aprobacion` aprobar el pago de un certificado solo si su monto
no supera ese tope — lee el monto YA CONGELADO de `certificados.monto`. Certificados emitidos
antes del arreglo no se ven afectados (su monto no cambia, punto 2). Certificados emitidos
DESPUÉS, con montos más altos por el mismo trabajo, podrían empezar a superar un tope que antes no
superaban — no es un bug del arreglo, es la consecuencia correcta de que el monto ahora refleja el
precio real, pero cambia quién puede aprobar qué. No aplica hoy porque no hay ninguna obra real con
ese rol configurado.
