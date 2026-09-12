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
