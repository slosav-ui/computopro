# Modelos de Certificación (A: Avance Medido / B: Hitos de Precio Cerrado) — diseño de datos

Construido sobre Etapa 3 (`obra_members`, `modificaciones_obra`, `audit_log`, `libro_entradas`, con RLS
aplicado — ver `docs/etapa3_roles_permisos_diseno_datos.md`). No es una "Etapa 4" formal, es una pieza
nueva que se apoya en esa base. Solo diseño de datos en este paso — nada de lo que sigue está creado en
Supabase ni implementado en Dart todavía.

**Estado del documento**: las 8 ambigüedades originales de la sección 7 quedaron cerradas con el usuario
y su consultor (respuestas incorporadas más abajo), incluida la nota sobre Subcontratos en §4 (la
referencia era a la memoria persistente del proyecto del propio usuario con su consultor — algo externo
a este entorno, no algo que Claude Code tuviera disponible; quedó confirmada directamente por el usuario
en el intercambio). Diseño cerrado. **Los 3 pasos de implementación quedaron aplicados y verificados en producción**
(migraciones `0005`-`0008`) — ver detalle por paso en la sección 9. Referenciado también en
`CLAUDE.md`, sección "Modelos de Certificación A/B".

## 1. Diagnóstico: cómo está hoy el ciclo de certificados en el código

Verificado contra el código real, no contra lo que documentaba `CLAUDE.md` de memoria (que resultó
correcto, pero se confirma acá con detalle porque el pedido lo pide explícitamente).

**`lib/presentation/obra_detalle/tabs/gestion_obra_tab.dart`** es hoy el único lugar que modela algo
parecido a un "certificado", y es enteramente mock:

- Los certificados viven en `List<Map<String, dynamic>> _certificados`, estado local del `State`
  (`_GestionObraTabState`), inicializado con un único certificado hardcodeado de ejemplo. No hay clase
  `Certificado`/modelo en `data/models/`, no hay tabla en Supabase, no hay repositorio — nada se
  persiste, se pierde al cerrar la pantalla.
- **Ciclo de vida: solo 3 de los 5 estados documentados** en la especificación histórica
  (`especificacion_funcional_completa.md`). Confirmado en `_cambiarEstado`/`_getColorEstado`:
  `'Borrador'` → `'Emitido (Esperando Pago)'` → `'Pagado'`. Faltan por completo *Leído por Propietario*
  (notificación automática al abrir) e *Impactado y Cerrado* (verificación de cobro + factura final por
  parte de la Empresa/Constructor).
- Hay un botón "Subir PDF Firmado" (`pdfFirmadoSubido`) pero **no bloquea** la emisión del siguiente
  certificado, pese a que la especificación lo exige explícitamente cuando se opta por firma física.
- El **monto de cada certificado es un número tipeado a mano** en un modal (`montoCtrl`,
  `TextEditingController` numérico libre) — no hay ningún vínculo con cómputo métrico, subítems ni
  ningún cálculo de `%` de avance real. En otras palabras: **el Modelo A ("% de avance sobre el cómputo
  métrico real") tampoco está implementado como tal hoy**, más allá de la idea conceptual — coincide con
  lo que decía el pedido, confirmado.
- `_diasPlazoPago` (plazo de pago pactado) es un campo fijo en memoria (`int`, default `10`), sin UI
  para configurarlo y sin persistencia — la spec pide que se configure una única vez antes del
  Certificado N°1 y aplique a todos los siguientes.
- El widget recibe `obraId` como parámetro requerido pero **no lo usa en ningún lado** del cuerpo de la
  clase (ni para leer ni para guardar) — y el tab **no está conectado** a `PresupuestosScreen`, que sigue
  construyendo sus 6 solapas con métodos `_build*` inline (ver `CLAUDE.md`, "Data flow: two coexisting
  patterns").
- El selector de rol (`_rolActual`, dropdown binario `'Profesional / Empresa'` / `'Propietario / Cliente'`)
  es también estado local desconectado de `obra_members`/`UserContext` — no hay ninguna verificación real
  de quién puede aprobar/pagar un certificado.

**`lib/data/models/obra_model.dart`** (`ObraModel`) no tiene ningún campo relacionado con certificación,
modelo de contrato, hitos, anticipo ni fondo de reparo. Solo `montoTotal` (monto total de la obra, sin
distinguir si es "presupuestado desde cómputo" o "contratado a precio cerrado" — ver §7.1).

**Anticipo y Fondo de Reparo — hallazgo que corrige la premisa del pedido**: no reutilizan campos
existentes porque **no existen campos hoy, en ningún lado**:
- `"Anticipo"` aparece una sola vez en todo `lib/`, en `presupuestos_screen.dart:360`, como texto
  hardcodeado dentro de un label mock (`'Certificado N° 1 - Anticipo / T. Preliminares'`) — un string de
  ejemplo, no un campo de datos.
- `"Fondo de Reparo"` no aparece en ningún archivo de `lib/`. Solo figura en
  `docs/especificacion_funcional_completa.md:105` como ítem de roadmap ("Fondo de Reparo con deducción
  automática en el certificado") — nunca implementado.

Ver §6 para la propuesta de estos dos campos como **campos nuevos**, no reutilización.

**Tablas Supabase existentes** (Etapa 3, confirmadas por sus migraciones): `obra_members`,
`modificaciones_obra`, `audit_log`, `libro_entradas`. No hay tabla `certificados` ni nada equivalente —
es terreno enteramente nuevo, no una extensión de una tabla que ya existía.

## 2. Alcance de esta pieza (qué se diseña acá, qué queda afuera)

El pedido puntual son 3 cosas: (a) modelo activo por obra + historial, (b) tabla de hitos del Modelo B,
(c) relación con `modificaciones_obra`/`audit_log`. Ninguna de las tres requiere rediseñar el ciclo de
5 estados del certificado en sí (Borrador → … → Impactado y Cerrado) — eso es una pieza de trabajo
propia (la siguiente en el orden acordado con el usuario, ver §9), y como el diagnóstico de arriba
muestra, hoy no hay ni tabla `certificados` sobre la cual apoyarse todavía.

Esto tiene una consecuencia real sobre el diseño de la "no retroactividad" (§5): como no existe una
tabla `certificados` persistida hoy, el diseño de abajo logra la congelación del histórico **sin
necesitar una tabla de certificados** — se apoya en que `hitos_certificacion` es de por sí append-only
(mismo principio que `modificaciones_obra`/`audit_log`: nada se reescribe, se agregan filas nuevas). Si
más adelante se diseña la tabla `certificados` real para el Modelo A, el mismo principio aplica ahí sin
cambios en lo que se propone acá.

## 3. Modelo activo por obra: campo en `obras` + historial vía `audit_log`

**Decisión de diseño**: no crear una tabla de historial dedicada. `audit_log` ya está pensada
explícitamente para esto — el comentario en `audit_log_entry.dart` dice literalmente *"a futuro para
certificados, delegaciones de firma y moderación de contenido"*. Un cambio de modelo es exactamente el
tipo de transición que esa tabla ya modela para `modificaciones_obra` (aprobar/rechazar/devolver). Crear
una tabla `obra_modelo_certificacion_historial` aparte sería duplicar lo que `audit_log` ya resuelve.

### Supabase — columna nueva en `obras`

```sql
alter table obras
  add column modelo_certificacion text not null default 'avance_medido'
    check (modelo_certificacion in ('avance_medido', 'hitos_precio_cerrado'));
```

Default `'avance_medido'` porque es el modelo conceptual ya asumido hoy (Modelo A), y toda obra
existente antes de este cambio debe arrancar ahí sin intervención manual.

### Cambiar de modelo: solo el Administrador, motivo obligatorio, registrado en `audit_log`

No hace falta una tabla nueva ni una función RPC especial más allá de la disciplina ya usada para
`modificaciones_obra`: un `update` sobre `obras.modelo_certificacion` (solo permitido para
`admin_maestro` vía RLS, ver §8) acompañado, en la misma transacción de la capa de app, de un insert en
`audit_log`:

```sql
-- ejemplo del insert que hace la app junto con el update de obras.modelo_certificacion
insert into audit_log (obra_id, usuario_id, accion, entidad, entidad_id, detalle)
values (
  :obra_id, auth.uid(), 'cambiar_modelo_certificacion', 'obra', null,
  jsonb_build_object(
    'modelo_anterior', 'avance_medido',
    'modelo_nuevo', 'hitos_precio_cerrado',
    'motivo', :motivo_texto  -- obligatorio, ver §8
  )
);
```

`entidad_id` queda en `null` para `entidad='obra'` — **definición cerrada, §7.5**: `audit_log.obra_id`
ya identifica la obra sin necesidad de repetirlo en `entidad_id`. Esa columna se reserva para cuando
`entidad_id` sí aporta algo que `obra_id` no da, como `entidad='hito_certificacion'` con `entidad_id` =
id del hito puntual (ver §4), o `entidad='modificacion_obra'` con `entidad_id` = id de la modificación.

Para reconstruir "qué modelo tenía la obra en un momento dado" (el historial pedido), se consulta
`audit_log` filtrando `entidad='obra' and accion='cambiar_modelo_certificacion'` ordenado por
`created_at`, tomando la última entrada anterior a la fecha de interés — mismo patrón que ya se usaría
para reconstruir el historial de `modificaciones_obra`.

## 4. Modelo B: tabla `hitos_certificacion`

### Doble función de esta tabla — definición cerrada, §7.3

`hitos_certificacion` no modela solo el contrato principal de una obra en Modelo B: también es la base
de datos de los **Subcontratos** con terceros sin cuenta en el sistema (diseño cerrado en sesión previa
del usuario con su consultor). Confirmado por el usuario, sin campos adicionales a los ya definidos acá
más abajo: el diseño queda resuelto solo con `contratista_nombre` como discriminador (`null` = contrato
principal, cargado = Subcontrato) — nada de columnas nuevas para esta mitad de la tabla.

Documentación adjunta de los Subcontratos (presupuesto del subcontratista, recibos de pago) queda fuera
de esta pieza — es una extensión aparte, no bloqueante, pensada para reusar más adelante el mismo patrón
de columna `adjuntos jsonb` que ya usa `libro_entradas`.

Dos usos de la misma fila, distinguidos por si `contratista_nombre` está o no cargado:

- **(a) Contrato principal de la obra bajo Modelo B**: el "contratista" ya es el Constructor, que tiene
  su propia fila en `obra_members` (rol `constructor`) — no hace falta repetir su identidad en el hito.
  `contratista_nombre` queda `null`.
- **(b) Subcontratos con terceros**: proveedores/subcontratistas que no tienen usuario en el sistema, por
  lo que no hay ninguna fila de `obra_members` a la que enlazar. Ahí sí hace falta el texto libre:
  `contratista_nombre` viene cargado.

Esto es lo que ya cerraba §7.3 (texto libre en vez de FK a una entidad `contratistas`, porque esos
terceros no tienen cuenta) — la aclaración nueva es que ambos usos conviven en la misma tabla en vez de
ser dos tablas separadas.

**Consecuencia que esto agrega al diseño (no pedida explícitamente, pero necesaria para que §5 siga
siendo correcto)**: si subcontratos y contrato principal comparten `obra_id`, el cálculo de `%` de avance
del contrato principal (§5) no puede sumar indiscriminadamente todos los hitos de la obra — mezclaría el
avance certificado al Cliente con el estado de pagos a subcontratistas, que son dos cosas distintas. La
función de §5 ya está ajustada para filtrar solo `contratista_nombre is null` (hitos del contrato
principal). Marcalo si el criterio real para distinguirlos debería ser otro.

### Supabase

```sql
create table hitos_certificacion (
  id uuid primary key default gen_random_uuid(),
  obra_id uuid not null references obras(id) on delete cascade,
  descripcion text not null,               -- libre: "Pago mensual - Agosto 2026", "Al terminar la estructura"
  monto numeric not null check (monto > 0),
  estado text not null default 'activo'
    check (estado in ('activo', 'finalizado', 'rescindido')),
  contratista_nombre text,                 -- null = contrato principal (§7.3); con valor = Subcontrato
  hito_anterior_id uuid references hitos_certificacion(id),  -- ver nota abajo
  motivo_rescision text,
  creado_por uuid not null references auth.users(id),
  fecha_creacion timestamptz not null default now(),
  fecha_finalizacion timestamptz,          -- se completa al pasar a 'finalizado'
  check (estado <> 'rescindido' or motivo_rescision is not null)
);
```

Puntos de diseño:

- **`hito_anterior_id` en vez de un puntero hacia adelante en el hito viejo**: mismo patrón que
  `libro_entradas.entrada_padre_id` (autorreferencia, el hijo apunta al padre). El hito *nuevo* que
  retoma el trabajo restante apunta al hito *rescindido* que lo originó, en vez de tener que hacer un
  `update` sobre la fila vieja para agregarle un puntero "hacia el reemplazo" — eso mantiene la fila
  rescindida completamente congelada desde el momento en que se rescinde (append-only real, ni siquiera
  se le toca un campo de enlace).
- **`estado <> 'rescindido' or motivo_rescision is not null`**: el check constraint garantiza a nivel de
  base que no se puede rescindir sin motivo, coherente con "requiere motivo obligatorio (texto)" del
  pedido — no queda como validación solo de UI.
- **Sin columna de `%` de avance ni de "monto certificado" separada del `monto`** — **definición
  cerrada, §7.2**: el hito es binario, `0%` hasta `'finalizado'`, sin certificación parcial dentro de un
  hito. Si un Administrador necesita más granularidad, la solución acordada es partir el hito en varios
  más chicos, no agregar un mecanismo de avance parcial dentro de cada uno — eso duplicaría la
  complejidad que Modelo B busca evitar. Cuando un hito pasa a `'finalizado'`, su `monto` completo es lo
  que cuenta como certificado.
- **Sin FK a `obra_members` para "quién es el contratista de este hito"**: ver arriba (doble función,
  §7.3) — texto libre solo para el caso Subcontrato, `null` para contrato principal.
- **Edición de `descripcion`/`monto` mientras el hito está `'activo'`** — **definición cerrada, §7.4**:
  sí es editable mientras el hito está `'activo'`, mismo paralelo que un certificado en `'Borrador'`.
  Una vez `'finalizado'` o `'rescindido'` la fila queda congelada por convención de RLS (sin política
  `UPDATE` para esos estados, mismo patrón que `modificaciones_obra`/`audit_log`), no por constraint de
  base.
- **Sin constraint que limite `sum(monto)` de hitos contra `monto_total_contratado`** — **definición
  cerrada, §7.8**: no se bloquea a nivel de base. Queda como advertencia de UI si la suma de montos de
  hitos `'activo'`+`'finalizado'` (del contrato principal, `contratista_nombre is null`) supera
  `monto_total_contratado` — sin impedir guardar, porque las negociaciones de monto a veces se resuelven
  después.

### Dart — `data/models/hito_certificacion.dart` (archivo nuevo, propuesto)

```dart
/// Hitos de Modelo B (precio cerrado) — ver docs/modelos_certificacion_diseno_datos.md, sección 4.
/// Doble función: contrato principal (contratistaNombre == null) o Subcontrato con tercero
/// sin cuenta en el sistema (contratistaNombre cargado) — ver sección 4, §7.3.
enum EstadoHito { activo, finalizado, rescindido }

class HitoCertificacion {
  final String id;
  final String obraId;
  final String descripcion;
  final double monto;
  final EstadoHito estado;
  final String? contratistaNombre;
  final String? hitoAnteriorId;      // ver §4 — apunta al hito rescindido que este retoma
  final String? motivoRescision;
  final String creadoPorUsuarioId;
  final DateTime fechaCreacion;
  final DateTime? fechaFinalizacion;

  // toMap/fromMap/copyWith siguiendo el mismo patrón manual que ModificacionObra
  // (sin codegen). fromMap con fallback conservador ante un estado desconocido:
  // tratar como 'activo', nunca asumir 'finalizado' sobre datos corruptos.
}
```

## 5. Cálculo automático del % de avance (Modelo B)

Función SQL, mismo patrón de nombre que `calcular_precio_promedio_insumo()` (ya referenciada en
`CLAUDE.md` para el motor de proveedores). Filtra `contratista_nombre is null` para contar solo el
contrato principal, no los Subcontratos que comparten tabla (ver §4):

```sql
create or replace function calcular_avance_hitos(p_obra_id uuid)
returns numeric language sql stable as $$
  select coalesce(
    100.0 * sum(monto) filter (where estado = 'finalizado')
      / nullif((select monto_total_contratado from obras where id = p_obra_id), 0),
    0
  )
  from hitos_certificacion
  where obra_id = p_obra_id and contratista_nombre is null;
$$;
```

Solo cuentan los hitos `'finalizado'` — binario, **definición cerrada §7.2** (ver §4). Los
`'rescindido'` aportan `0` (su trabajo pendiente pasa al hito que lo reemplaza, si existe uno); los
`'activo'` aportan `0` hasta que se marcan `'finalizado'`. La capa Dart nunca escribe un `%` de avance a
mano — siempre llama a esta función (o a una vista equivalente) para mostrarlo, igual que el pedido
exige.

## 6. Anticipo y Fondo de Reparo: campos nuevos (corrección de la premisa, ver §1)

Como no existen hoy, se proponen como columnas nuevas en `obras` — compartidas por ambos modelos, tal
como pide el enunciado, pero calculadas sobre bases distintas según el modelo activo (cómputo métrico
certificado para A, `monto_total_contratado` para B):

```sql
alter table obras
  add column monto_total_contratado numeric,   -- Modelo B, ver §7.1
  add column anticipo_pct numeric,              -- % del monto base, ver §7.6
  add column fondo_reparo_pct numeric;          -- % retenido por certificado/hito, ver §7.6
```

Modelados como porcentaje (no monto fijo) porque es la práctica estándar en construcción argentina
(anticipo típico 10-30% del contrato; fondo de reparo típico 5-10% retenido de cada certificado/hito).

**Definición cerrada, §7.6**: un único valor de `anticipo_pct` y `fondo_reparo_pct` por obra — no varían
por hito ni por certificado dentro de la misma obra (mismo criterio ya usado para `_diasPlazoPago`, que
se fija una sola vez antes del Certificado N°1). Matiz entre los dos campos, tal como lo cerró el
usuario: **Fondo de Reparo** se fija una sola vez al configurar la obra y funciona como una retención
fija por certificado/hito; **Anticipo** también se fija una sola vez (el `%` no cambia dentro de la
obra), pero se **descuenta de forma proporcional** en cada certificado/hito a medida que se van
emitiendo — el `%` es constante, lo que varía es cuánto anticipo ya se descontó acumulado. Calcular ese
descuento acumulado por certificado/hito es parte del ciclo de pago/certificado (fuera de alcance de esta
pieza, ver §2) — lo que corresponde definir acá son las dos columnas en sí, ya incluidas arriba.

## 7. Definiciones cerradas — respuestas del usuario (revisadas con su consultor) a las 8 ambigüedades

**§7.1 — Relación entre `monto_total_contratado` (Modelo B) y `ObraModel.montoTotal` (ya existente).**
Cerrado: quedan separados. Bajo Modelo A el monto total de una obra es (o debería ser, cuando Solapa 1/2
se conecten de verdad a Supabase) un resultado calculado del cómputo métrico — un output. Bajo Modelo B,
`monto_total_contratado` es un input directo del Administrador. Mezclarlos rompería la fuente de verdad
de `ObraModel.montoTotal` el día que el cómputo métrico esté conectado de verdad.

**§7.2 — Certificación parcial dentro de un hito `'activo'`.** Cerrado: binario, `0%` hasta
`'finalizado'`, sin mecanismo de avance parcial dentro de un hito. Más granularidad = definir hitos más
chicos, no agregar complejidad al hito individual (contradice el propósito de Modelo B, que es evitar
justamente ese nivel de detalle). Ver aplicación en §4 y §5.

**§7.3 — "Otro contratista" al reemplazar un hito rescindido: texto libre vs. entidad real.** Cerrado:
`contratista_nombre` como texto libre — pero con una función más amplia de lo que se había planteado
originalmente: `hitos_certificacion` es también la base de los Subcontratos con terceros sin cuenta en
el sistema, no solo un dato accesorio del reemplazo de un hito rescindido. Sin columnas adicionales a
las de §4 — confirmado por el usuario. El filtro `contratista_nombre is null` en `calcular_avance_hitos`
(§5) queda confirmado como el criterio correcto para separar avance certificado al Cliente de pagos a
Subcontratistas. Documentación adjunta de Subcontratos (presupuesto, recibos) queda fuera de esta pieza,
para una extensión posterior con el mismo patrón `adjuntos jsonb` que ya usa `libro_entradas`
(`0003_libro_entradas.sql:22`).

**§7.4 — Edición de un hito `'activo'`.** Cerrado: sí es editable en `monto`/`descripcion` mientras esté
`'activo'`, mismo paralelo con el "Borrador" de un certificado. Aplicado en §4.

**§7.5 — `audit_log.entidad_id` para `entidad='obra'`.** Cerrado: `null`. `audit_log.obra_id` ya
identifica la obra, no hace falta repetirlo en `entidad_id` — esa columna queda para cuando aporta un
dato que `obra_id` no da (p. ej. el id de un hito o de una modificación puntual). Aplicado en §3.

**§7.6 — Anticipo/Fondo de Reparo: alcance del `%` (una vez por obra vs. por hito/certificado).**
Cerrado: una sola vez por obra para ambos, con un matiz entre ellos — ver desarrollo completo en §6
(Fondo de Reparo como retención fija repetida, Anticipo como `%` fijo pero descuento acumulado
proporcional).

**§7.7 — Editar `monto_total_contratado`: ¿edición libre del Administrador, o requiere aprobación?**
Este es el que cambia el criterio que yo había propuesto. Cerrado, y con peso distinto al resto: un
aumento de `monto_total_contratado` es plata que termina pagando el Cliente, mismo peso económico que un
Adicional — no puede ser una edición directa sin control. Debe pasar por el mismo flujo de aprobación
que ya existe en `modificaciones_obra` (motivo obligatorio + aprobación de quien tiene autoridad de
pago), consistente con el principio ya aplicado en todo el proyecto: ningún cambio de monto sin que la
parte que paga lo apruebe. Ver el diseño concreto de este flujo en §7.7-bis, más abajo (requiere un
ajuste de schema sobre `modificaciones_obra`, tabla de Etapa 3).

**§7.8 — Constraint entre `sum(monto)` de hitos y `monto_total_contratado`.** Cerrado: no se bloquea a
nivel de base. Advertencia en la UI si la suma de montos de hitos `'activo'`+`'finalizado'` del contrato
principal supera `monto_total_contratado`, sin constraint duro — coherente con la flexibilidad ya
definida para los hitos (algunas negociaciones de monto se resuelven después). Aplicado en §4.

### §7.7-bis — Diseño concreto: `monto_total_contratado` cambia vía `modificaciones_obra`

Dos momentos distintos, con reglas distintas:

- **Carga inicial** (primera vez que se define el valor — sea porque la obra arranca en Modelo B, o
  porque cambia de A a B y el Administrador carga el monto contratado por primera vez): edición directa
  y simple del campo, tal como describía el pedido original ("campo editable simple, cargado por el
  Administrador"). No hay todavía nada que "aumentar" — es la línea de base.
- **Cualquier cambio posterior** a un valor ya cargado (ampliación de contrato, renegociación de monto):
  **no** es una edición directa. Debe generar una fila en `modificaciones_obra` con un tipo nuevo,
  pendiente de aprobación por quien tiene autoridad de pago — mismo circuito que ya existe hoy para
  aprobar/rechazar/devolver un adicional.

Regla operativa para distinguir ambos casos a nivel de RLS/app (a definir en detalle en el paso de
implementación, ver §8): una `update` directa sobre `obras.monto_total_contratado` solo se permite
cuando el valor anterior es `null`; cualquier `update` que cambie un valor ya no-nulo debe ser
consecuencia de aprobar la `modificacion_obra` correspondiente, no una escritura directa.

**Ajuste de schema sobre `modificaciones_obra` (tabla de Etapa 3) que esto requiere**: el `check` de
`tipo` hoy es `check (tipo in ('adicional','demasia','quita'))`. Ninguno de los tres encaja bien —
`adicional` en el diseño actual "gradúa a un Subitem real del cómputo" al aprobarse (comentario en
`modificacion_obra.dart`), lo cual no tiene sentido en Modelo B, que no tiene subítems ni cómputo.
Se propone un cuarto valor, específico para esto:

```sql
alter table modificaciones_obra drop constraint modificaciones_obra_tipo_check;
alter table modificaciones_obra
  add constraint modificaciones_obra_tipo_check
  check (tipo in ('adicional', 'demasia', 'quita', 'ajuste_contrato'));
```

Para `tipo = 'ajuste_contrato'`:
- `subitem_id` y `apu_privado_id` quedan `null` (ya son nullable, sin cambios de schema ahí).
- `cantidad` y `monto_total` coinciden: no hay una cantidad física distinta de un precio unitario acá
  (es un ajuste puramente monetario al contrato), así que ambos campos llevan el mismo valor. El signo
  indica el sentido: positivo = aumenta `monto_total_contratado`, negativo = lo reduce.
- Al aprobarse (`estado = 'aprobado'`), la capa de app aplica el delta sobre
  `obras.monto_total_contratado` — mismo patrón que ya usa el proyecto para la graduación de un
  `adicional` a Subitem real: efecto de negocio resuelto en la app al momento de la aprobación, no vía
  trigger de base, para mantener consistencia con cómo ya funciona `modificaciones_obra`.
- El registro en `audit_log` de la aprobación no necesita un mecanismo nuevo: reusa exactamente el mismo
  flujo que ya deja rastro de aprobar/rechazar/devolver cualquier `modificacion_obra` hoy.

Este ajuste también implica agregar `ajusteContrato` a `TipoModificacion` en
`data/models/modificacion_obra.dart` cuando se implemente — señalado acá, no hecho (ver §9).

## 8. Cambio de modelo A↔B: reglas ya cerradas

- Solo `admin_maestro` puede cambiar `obras.modelo_certificacion` (mismo actor que ya aprueba/edita todo
  sin restricción en la matriz de permisos de Etapa 3).
- Motivo obligatorio en texto — va en `audit_log.detalle.motivo` (§3), no en una columna de `obras` (la
  columna de `obras` solo guarda el estado *actual*, nunca el motivo de cómo se llegó ahí).
- No retroactivo: nada de lo ya congelado (hitos `'finalizado'`/`'rescindido'`, o lo que en el futuro
  sea la tabla `certificados` de Modelo A) se reescribe al cambiar de modelo — se apoya en que ambas
  tablas son append-only por RLS (sin política `UPDATE` para filas en esos estados), no en un mecanismo
  de "congelamiento" explícito. Mismo principio que ya usa el proyecto para CAC y
  adicionales/demasías/quitas (ver `CLAUDE.md`, "CAC aplicado solo sobre el monto pendiente de
  ejecutar").
- Se puede cambiar en cualquier momento y las veces que se quiera, en cualquier dirección (A→B, B→A) —
  no hay restricción de "solo una vez" ni de dirección.
- `monto_total_contratado`: editable directo solo en su carga inicial (valor anterior `null`);
  cualquier cambio posterior pasa por `modificaciones_obra` con `tipo='ajuste_contrato'` y aprobación de
  quien tiene autoridad de pago (§7.7-bis) — regla a traducir en política `UPDATE` concreta en el paso
  de implementación.

RLS concreta para `hitos_certificacion`, para la política `UPDATE` de `obras.modelo_certificacion` y
para la regla de `monto_total_contratado` de arriba queda para el paso de implementación (mismo orden
que Etapa 3: diseño de datos primero, políticas después) — apoyada en las funciones helper
`tiene_rol_en_obra`/`is_obra_member`/`puede_aprobar_monto` que ya existen de `0004_rls_etapa3.sql`, sin
necesitar funciones helper nuevas más allá de, potencialmente, una variante de `puede_aprobar_monto` que
contemple `ajuste_contrato` si su regla de aprobación termina siendo distinta a la de adicionales — a
confirmar quién aprueba un `ajuste_contrato` en el paso de implementación si no es exactamente la misma
cadena que ya resuelve `puede_aprobar_monto`.

## 9. Qué NO hice en este paso — y orden de implementación propuesto

Lo que sigue sin diseñar en detalle, deliberadamente:

- No creé ninguna tabla ni columna en Supabase — todo lo de arriba es propuesta en SQL, no ejecutada.
- No toqué `gestion_obra_tab.dart`, `modificacion_obra.dart` ni ningún otro archivo de `lib/` — ni
  siquiera para agregar `ajusteContrato` al enum `TipoModificacion` (§7.7-bis) o conectar el `obraId`
  que hoy no se usa.
- No diseñé el ciclo completo de 5 estados del certificado de Modelo A (Borrador → … → Impactado y
  Cerrado) ni una eventual tabla `certificados` — sigue siendo la pieza de trabajo siguiente, fuera del
  alcance de este pedido puntual (§2).
- No diseñé las políticas RLS concretas de `hitos_certificacion`, la política `UPDATE` de
  `obras.modelo_certificacion`, ni la regla de "solo carga inicial" de `monto_total_contratado` — señalé
  sobre qué funciones helper se apoyarían (§8), pero el texto exacto de las políticas queda para cuando
  se implemente, igual que en Etapa 3.
- Documentación adjunta de Subcontratos (§4, §7.3): confirmada como extensión futura no bloqueante, sin
  diseñar en detalle acá — reusaría `adjuntos jsonb` (patrón ya en `libro_entradas`) cuando se necesite.

Orden de implementación acordado con el usuario: primero `obras.modelo_certificacion` +
`hitos_certificacion` (con el ajuste de `modificaciones_obra` de §7.7-bis, porque ambas piezas están
acopladas — `ajuste_contrato` no tiene sentido sin `monto_total_contratado` ya existiendo), dejando el
rediseño del ciclo de 5 estados del certificado de Modelo A para una pieza aparte.

**Estado de implementación**:
- ✅ **Paso 1** — `obras.modelo_certificacion` + función `cambiar_modelo_certificacion()` (update +
  insert atómico en `audit_log`, motivo obligatorio validado en la función): migración
  `supabase/migrations/0005_modelo_certificacion.sql`, **aplicada en producción** por el usuario
  (confirmado en Table Editor: columna presente, `'avance_medido'` en las obras existentes). Incluye una
  limitación conocida documentada inline en la migración: el `UPDATE` solo lo permite quien pasa la
  política `UPDATE` ya existente de `obras` (`id_admin_creador = auth.uid()`, patrón de dueño único
  anterior a Etapa 3), no una verificación explícita del rol `admin_maestro` de `obra_members` — pueden
  divergir si el Administrador de una obra fue reasignado después de creada.
- ✅ **Paso 2** — `hitos_certificacion` + `calcular_avance_hitos()` + RLS: migración escrita en
  `supabase/migrations/0006_hitos_certificacion.sql`, **aplicada y verificada en producción**. Incluye
  `obras.monto_total_contratado` (no era parte del paso 2 tal como se había nombrado, pero es una
  dependencia dura de `calcular_avance_hitos()` — sin esa columna la función no tiene contra qué
  dividir). `anticipo_pct`/`fondo_reparo_pct` (§6) quedan fuera, para una migración aparte que no
  depende de este paso.

  **RLS incluida en el mismo archivo de creación** (pedido explícito del usuario, no dejar la
  tabla abierta entre creación y RLS — a diferencia de cómo lo hizo Etapa 3, que la agregó como
  paso final consolidado en 0004 después de crear las 4 tablas). `SELECT` abierto a
  `is_obra_member`; sin `DELETE`. **Aplicada en producción tal como quedó en 0006**
  (`INSERT`/`UPDATE` para `admin_maestro` **o** `profesional`), y corregida por
  `supabase/migrations/0007_hitos_certificacion_solo_admin.sql` (`DROP POLICY` + `CREATE POLICY`
  sobre las 2 políticas de escritura, sin volver a correr 0006) — **decisión cerrada: solo
  `admin_maestro`** escribe hitos, mismo criterio que `obras.modelo_certificacion` ("únicamente el
  Administrador", §8), no la matriz general de Gestión de Obra que incluía a Profesional.
- ✅ **Paso 3** — ajuste de `tipo` en `modificaciones_obra` (`ajuste_contrato`) + función
  `aprobar_ajuste_contrato()` (aprueba + aplica el delta a `monto_total_contratado` + `audit_log`,
  atómico — mismo patrón que `cambiar_modelo_certificacion()` del paso 1): migración escrita en
  `supabase/migrations/0008_ajuste_contrato.sql`, **aplicada y verificada en producción**
  (`aprobar_ajuste_contrato` confirmada en Database → Functions). Reusa `puede_aprobar_monto`
  (0004) como cadena de autoridad, sin funciones helper nuevas.

  **2 límites documentados inline en la migración, dejados sin cerrar por decisión explícita del
  usuario** (consistentes con "no vía trigger de base" ya decidido en §7.7-bis) — **anotados como
  deuda técnica a revisar más adelante, no ahora**: (a) la política `modificaciones_obra_update`
  genérica sigue permitiendo aprobar un `ajuste_contrato` con un `UPDATE` directo sin pasar por
  `aprobar_ajuste_contrato()`, dejando la modificación aprobada sin aplicar el delta ni generar su
  `audit_log` específico — misma clase de límite que ya tiene `'adicional'` hoy (graduación a
  Subitem tampoco forzada a nivel de base); (b) la regla "`monto_total_contratado` editable
  directo solo en su carga inicial" (§7.7-bis) queda como convención de la capa de app, no forzada
  en la base — nada impide un `UPDATE` directo sobre un valor ya cargado. Riesgo aceptado por el
  usuario porque hoy es el único que toca la base directamente y el código Dart va a llamar siempre
  a la función — revisar si se suma otro desarrollador con acceso directo a la base.
