# Avisos de "algo te espera" — relevamiento y propuesta mínima

Pedido de Seba (2026-09-12): "no me hubiera enterado de que había un adicional para aprobar si no
entraba a la pantalla de adicionales". Vale para todo lo que espera la acción de alguien. Pedido
explícito: lo mínimo para que **al abrir la app se vea que hay algo esperándote** — no un sistema
completo de notificaciones.

**Estado: aplicado y verificado por Seba (2026-09-12)** con roles separados — el constructor ve
el adicional enviado como pendiente en la pantalla pero no en el cartel (no lo aprueba él); el
cliente registró el pago de un certificado y el cierre lo hizo quien corresponde. Ver §5.

## 1. Qué hay hoy — nada de notificaciones, verificado

- **Sin push ni email**: `pubspec.yaml` no tiene `firebase_messaging`, `flutter_local_notifications`
  ni nada parecido; ninguna migración crea una tabla de notificaciones. Ya estaba anotado en
  `docs/certificados_ciclo_vida_diseno_datos.md` §1: el "se notifica automáticamente" de la spec se
  resolvió solo del lado de los datos (un timestamp por evento), sin enviar nada.
- **Único antecedente de aviso**: `CartelFirmaPendiente` (Gestión de Obra, pieza 4) — cartel
  persistente de certificados con firma física pendiente, que "gana por cansancio" (no se descarta,
  desaparece cuando se resuelve). Pero vive **dentro** de una obra: hay que entrar para verlo, que es
  exactamente el problema de este pedido.
- **Lo que sí existe y alcanza**: cada estado "esperando a alguien" ya está en su tabla, y cada
  autoridad ya está en una función SQL — la que usa la propia transición para decidir quién puede
  hacerla. No falta ningún dato; falta juntarlo y mostrarlo en el dashboard.
- Tiempo real de Supabase ya se usa (Mat y MO, `obra_insumo_precios`), pero no hace falta para esto.

## 2. Qué espera a quién — verificado contra las funciones de transición

| Qué | Estado que espera | Quién tiene que actuar | Autoridad (la de la transición) |
|---|---|---|---|
| Adicional de monto fijo | `pendiente` | cliente_principal, o apoderado con `puede_aprobar_adicionales` | `puede_aprobar_adicional` (0116) |
| Adicional presupuestado | `pendiente` + `enviado_a_aprobacion_en` | ídem | ídem |
| Quita / demasía | `pendiente` | profesional o constructor | `puede_aprobar_quita_demasia` (0109) |
| Certificado emitido | `emitido` (sin leer) | cliente_principal o apoderado | `marcar_certificado_leido` (0011) |
| Anulación de certificado | `anulacion_estado = 'propuesta'` | profesional o constructor, **nunca quien la propuso** | `resolver_anulacion_certificado` (0056/0111) |
| Certificado leído | `leido` (sin pagar) | cliente o apoderado con `puede_aprobar_certificados` (+ tope) | `puede_gestionar_certificado` (0011) — ver §4-A |
| Certificado pagado | `pagado` (sin cerrar) | admin_maestro o constructor | `marcar_certificado_impactado` (0011) — ver §4-A |

Un adicional presupuestado todavía **en preparación** no figura: no espera a otro, es trabajo en
curso de quien lo cotiza (§4-D).

## 3. Propuesta mínima

**Una función SQL, `mis_pendientes()`**, que devuelva una fila por cosa que espera al usuario logueado,
en todas sus obras: `obra_id`, `obra_nombre`, `tipo` (`adicional` / `quita_demasia` /
`certificado` / `anulacion`), `entidad_id`, `descripcion` corta, `desde` (fecha del evento). Recorre
las obras donde el usuario es miembro activo y, por cada tipo, filtra por el estado de §2 **con la
misma función de autoridad que usa la transición**.

Por qué del lado de la base y no armado en Dart: la autoridad ya vive en SQL. Reconstruirla en Dart
con `UserContext` obra por obra es exactamente el tipo de copia que ya divergió una vez (delegación
sin fechas, `docs/adicionales_quitas_demasias_diagnostico.md` §13.4). Con la función, el aviso nunca
muestra algo que no podés resolver, ni esconde algo que sí — y es una sola llamada para todo el
dashboard. Solo lectura: sin tabla nueva, sin estado de "visto".

**En `ObrasListScreen`**, al cargar (y al volver de una obra, que ya recarga la lista hoy):
1. **Un cartel arriba de la lista** — "Tenés 3 cosas esperándote" — que al tocarlo abre una hoja con
   el detalle (obra, qué, desde cuándo); cada ítem lleva directo a la pantalla donde se resuelve
   (Adicionales, Quitas y Demasías, o Gestión de Obra de esa obra). Sin pendientes, no hay cartel.
   Mismo criterio que `CartelFirmaPendiente`: no se descarta, desaparece cuando se resuelve.
2. **En cada card, un contador chico** con los pendientes de esa obra, para ubicar dónde está.

**Qué no incluye, a propósito**: push (necesita Firebase, tokens por dispositivo y algo del lado del
servidor que dispare el envío — pieza aparte, si el uso la pide), email, avisos informativos ("tu
adicional fue aprobado"), marcar como visto, tiempo real. Se entera al abrir la app, que es lo que se
pidió.

**Tamaño**: una migración (una función, sin tablas), un método de repositorio, un cartel + una hoja
en el dashboard, y la navegación por tipo. Una tanda.

## 4. Ambigüedades — necesito tu respuesta antes de escribir la función

**A. ¿Qué estados de certificado entran?** Nombraste "emitido sin leer" y "anulación propuesta".
La cadena tiene dos esperas más: *leído sin pagar* (espera al cliente) y *pagado sin cerrar* (espera a
admin/constructor — es lo que le avisa al contratista que cobró). Recomiendo entrar las cuatro: es la
misma función, una condición más cada una, y dejar afuera "pagado sin cerrar" es dejar sin aviso
justamente al que cobra. La firma física pendiente ya tiene su cartel dentro de la obra — la dejaría
afuera de esta primera versión.

**B. Adicional que supera el tope del apoderado.** ¿Le aparece como pendiente? Recomiendo que no:
el aviso es para quien puede decir que sí (`puede_aprobar_adicional` con el monto real). El cliente
principal siempre califica, así que ningún adicional queda sin nadie avisado.

**C. Quita/demasía cargada por mí.** `aprobar_quita_demasia` no excluye a quien la cargó (se
puede aprobar la propia, decisión §7-A: "uno solo alcanza"). ¿Le aparece como pendiente a quien la
cargó? Recomiendo que no — ya sabe que existe, el aviso es para el otro —, salvo que sea el único
profesional/constructor de la obra: ahí sí, porque si no nadie la vería.

**D. Adicional en preparación.** ¿Le aparece a quien lo cotiza como "te falta enviarlo"?
Recomiendo que no: no espera a nadie más, y el aviso pierde fuerza si mezcla "te toca a vos decidir"
con "tenés trabajo a medio hacer".

## 5. Cerradas por Seba (2026-09-12)

- **A.** Entran los cuatro estados de certificado (emitido sin leer, leído sin pagar, pagado sin
  cerrar, anulación propuesta) **y también la firma física pendiente**: "hoy tiene su cartel pero
  está adentro de la obra, así que tiene exactamente el mismo problema que todo lo demás".
- **B.** Adicional con el tope del apoderado superado: no le aparece — "mostrárselo es ruido, el
  cliente principal lo ve igual".
- **C.** Quita/demasía cargada por uno mismo: no aparece, salvo que sea el único
  profesional/constructor activo — "si soy el único que puede aprobarla, tengo que verla o queda
  colgada para siempre".
- **D.** Adicional en preparación: no aparece.

**Hecho, aplicado y verificado:**
- `supabase/migrations/0117_mis_pendientes.sql` — `mis_pendientes()`, siete ramas (adicional,
  quita/demasía, cuatro de certificado, firma física), cada una con la autoridad de su transición.
  La anulación excluye a quien la propuso sin excepción de "único": la transición misma no la
  tiene (`resolver_anulacion_certificado`).
- `lib/data/models/pendiente.dart`, `lib/services/pendientes_repository.dart`,
  `CertificadosRepository.getPorId`.
- `lib/presentation/dashboard/cartel_pendientes.dart` + `ObrasListScreen`: cartel arriba de la
  lista, contador por card, y cada ítem lleva a Adicionales, Quitas y Demasías o al detalle del
  certificado (armando el `UserContext` de esa obra). Recarga al volver.

---

## 6. Ramas que faltan — auditoría del 2026-09-14

Seba reporta que **a `slosav` (admin_maestro + profesional) no le aparece el cartel** en momentos en
que la obra claramente lo esperaba, aunque al entrar a la obra ve todo. Revisadas una por una las
14 ramas de `mis_pendientes()` tal como quedó en la `0129`, contra el ciclo real después de la
`0124` (conformidad) y la `0125` (quién emite).

### 6.1 Falta la rama de EMITIR — confirmada, es un agujero estructural

**El certificado conformado y sin emitir no le aparece a nadie.** La tabla de §2 se escribió en la
`0117`, cuando el ciclo iba `borrador -> emitido` en un solo acto y emitir era la decisión de quien
ya estaba mirando el borrador. La `0124` partió ese acto en dos (`propuesto -> conforme -> emitido`)
y la `0125` le dio la emisión a **otra persona** que la que propone y la que conforma — el
profesional, que puede no haber participado de ninguno de los dos pasos anteriores. Desde entonces
existe un estado de espera nuevo, real, con nombre y con autoridad propia
(`estado='borrador' and acuerdo_estado='conforme'`, resuelto por `emitir_certificado`), y **ninguna
rama lo cubre**. `certificacion_periodo` ya se apagó (hay borrador), `certificado_propuesto` ya se
apagó (la conformidad se dio), y `certificado_emitido` todavía no se prende.

Es exactamente el caso de Seba: como profesional de la obra, era él quien tenía que emitir, y el
dashboard no se lo pidió nunca.

**Escrita en la `0130` el mismo día, por pedido de Seba** (*"ese es un bug real y no le aparece a
nadie, así que un certificado puede quedar esperando indefinidamente sin que la app avise"*), como
`certificado_conforme` — nombrada por el estado del certificado, como el resto
(`certificado_propuesto`, `certificado_leido`), no por la acción. En el dashboard abre la **vista
previa**, no la pantalla de carga: es donde vive el botón "Emitir", y mandar al que emite a la
pantalla de carga lo pone a un toque de modificar un avance, que por el trigger de la `0124` tira
abajo la conformidad que este mismo pendiente vino a cobrar.

La rama es de una línea y no inventa autoridad: `puede_emitir_certificado(obra_id)` ya existe desde
la `0125` y ya la llama la app por RPC para decidir si muestra el botón "Emitir". `desde` =
`conforme_fecha`.

### 6.2 Falta la vuelta de la devolución — mismo origen, misma tanda

`devolver_avance_certificado` (0124) manda el borrador a `en_carga` **con un comentario obligatorio**
y le deja la pelota a quien propuso. No hay rama para eso tampoco.

**Escrita en la `0131`** como `certificado_devuelto`, en la misma tanda del plazo de la objeción
(Seba, 2026-09-14: *"suma la también: es el mismo caso que el conformado sin emitir"*). Abre la
pantalla de carga, al revés que `certificado_conforme`: acá sí hay que editar los números.

No choca con el criterio de §4-D ("lo que está en preparación no figura, es trabajo en curso de
quien lo cotiza"): un borrador que alguien te devolvió con un comentario **no es trabajo que elegiste
tener abierto**, es una respuesta que te están esperando. La diferencia está en la base y es
consultable: `comentario_devolucion is not null` con `propuesto_por = auth.uid()`.

### 6.3 Las dos ramas de la objeción SÍ incluyen a `slosav` — hay que medirlo contra la base

`certificado_objetado` (0129) incluye `profesional`, `constructor` **y `admin_maestro`**, así que por
código tendría que haberle aparecido mientras la objeción estuvo abierta y sin respuesta. Y que
`certificado_pagado` (admin_maestro o constructor) sí le haya aparecido prueba que su fila de
`admin_maestro` está activa y que `tiene_rol_en_obra` le da true.

Quedan dos explicaciones, y se distinguen con una consulta, no discutiendo:

1. **La ventana**: entre la objeción de `seba_losa` y la respuesta de `seba2135` puede no haber
   habido ningún momento en que se mirara el dashboard de `slosav`. La rama se apaga en cuanto hay
   respuesta, por diseño.
2. **La función desplegada no es la del archivo**: la `0129` reescribe `mis_pendientes()` entera; si
   se aplicó por partes, en la base puede haber quedado el cuerpo de la `0126`, que no tiene ninguna
   de las dos ramas de objeción.

**`objecion_respondida` va solo al cliente, y eso está bien**: con la respuesta dada, la acción que
falta es del cliente (leer la aclaración y levantar la objeción). `mis_pendientes()` es "lo que
tenés que hacer vos", no "lo que está pasando en la obra" — si le mandáramos al técnico un aviso por
algo que no puede resolver, el cartel empieza a mentir. Lo que sí le falta al técnico en ese momento
es el **plazo** de esa espera, y eso se resuelve en la §5.2 del diagnóstico de certificación.

### 6.4 Cómo probar cualquier rama con un solo usuario, sin tres dispositivos

Hasta ahora todas las verificaciones de `mis_pendientes()` decían "el SQL Editor corre sin usuario
logueado". Se puede, dentro de una transacción, haciéndose pasar por el usuario — `auth.uid()` lee el
claim `sub`:

```sql
begin;
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"<uuid de slosav>","role":"authenticated"}';
  select tipo, obra_nombre, certificado_numero, desde from mis_pendientes();
rollback;
```

Y para saber cuál de las dos explicaciones de §6.3 es la buena, **antes** de cambiar nada:

```sql
select prosrc like '%certificado_objetado%' as tiene_la_rama_0129
from pg_proc where proname = 'mis_pendientes';
```
