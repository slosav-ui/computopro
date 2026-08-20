# Ciclo de vida del Certificado de Obra (5 estados, Modelo A) — diseño de datos

Construido sobre Etapa 3 y sobre Modelos de Certificación A/B (`docs/etapa3_roles_permisos_diseno_datos.md`,
`docs/modelos_certificacion_diseno_datos.md` — este último ya delimitaba explícitamente esta pieza como
"la siguiente", §2 y §9 de ese documento). Solo diseño de datos en este paso — nada de lo que sigue está
creado en Supabase ni implementado en Dart todavía.

**Estado del documento**: las 8 ambigüedades de la sección 10 quedaron cerradas con el usuario y su
consultor (respuestas incorporadas más abajo, sección 10 renombrada a "Definiciones cerradas"). **Los 3
pasos de implementación (migraciones `0009`-`0012`) quedaron aplicados y verificados en producción** —
ver detalle por paso en la sección 11. Referenciado también en `CLAUDE.md`, sección "Ciclo de vida del
Certificado de Obra".

## 1. Diagnóstico: releído y confirmado vigente

`lib/presentation/obra_detalle/tabs/gestion_obra_tab.dart` no cambió desde el diagnóstico anterior
(confirmado — mismo contenido byte a byte). Todo lo que ya se había señalado sigue siendo cierto:
certificados en `List<Map<String, dynamic>>` en memoria, sin tabla, sin repositorio; solo 3 de los 5
estados (`'Borrador'` → `'Emitido (Esperando Pago)'` → `'Pagado'`); botón "Subir PDF Firmado" que no
bloquea nada; monto tipeado a mano sin vínculo a cómputo métrico; `obraId` recibido pero no usado;
selector de rol como estado local desconectado de `obra_members`/`UserContext`.

**Encontré la fuente exacta de la especificación de los 5 estados**, que `CLAUDE.md` resume pero no
citaba con archivo/línea: `docs/especificacion_funcional_parte2_fundacional.md`, sección 2 (líneas
12-22). La transcribo completa acá porque el diseño de abajo depende de su redacción exacta, palabra por
palabra:

> 1. **Borrador (En Construcción/Revisión)**: carga de avances por Profesional/Empresa, con
>    notificaciones de ida y vuelta.
> 2. **Emitido (Esperando Pago)**: aprobado por el Profesional; se notifica al Propietario con la fecha
>    límite de pago (según días pactados en contrato).
> 3. **Leído por Propietario**: al abrir el certificado, se notifica automáticamente a la obra que fue
>    visto.
> 4. **Pagado por Propietario**: el Propietario marca el pago, selecciona medio (transferencia/efectivo)
>    y adjunta comprobante.
> 5. **Impactado y Cerrado**: la Empresa/Constructor verifica el cobro, tilda el impacto, adjunta
>    factura/recibo final — cierra el ciclo.
>
> Reglas especiales: Plazo de pago se configura una sola vez antes del Certificado N°1 y aplica a todos
> los siguientes. Impresión/firma física: opción de descargar PDF en blanco (medición en campo) o
> completo (firma en papel). Si se opta por firma física, el sistema bloquea la emisión del siguiente
> certificado hasta subir el PDF/imagen firmado.

Esta redacción es la base de varias decisiones de diseño de abajo, y también de varias ambigüedades
(§10) — en particular, "Profesional" aparece nombrado para el paso 2 y "Empresa/Constructor" para el
paso 5, dos términos distintos que no está claro si mapean 1:1 a `profesional`/`constructor` de
`RolProyecto`, o si son sinónimos coloquiales del mismo actor.

**No implementado en ningún lado, y fuera de alcance de esta pieza** (para que quede explícito y no se
asuma que este diseño lo resuelve): la matriz de permisos por tipo de relación cliente-obra (Cliente
Autoconstructor / Cliente con Profesional+Contratista / Cliente con Contratista Directo — también
documentada en la misma sección de la spec histórica, líneas 24-27) sigue sin ningún soporte de datos;
es una capa de visibilidad sobre lo que ya exista, no algo que cambie el schema de `certificados` en sí.
Tampoco hay sistema de notificaciones (push/email) en todo el proyecto — "se notifica automáticamente"
se resuelve acá solo del lado de los datos (un timestamp que registra el evento), no del lado de enviar
ninguna notificación real.

## 2. Alcance: solo Modelo A

`certificados` aplica únicamente cuando `obras.modelo_certificacion = 'avance_medido'`. Bajo Modelo B el
equivalente ya existe (`hitos_certificacion`, `docs/modelos_certificacion_diseno_datos.md` §4-5). El
diseño de abajo agrega un guard para esto en la política `INSERT` (§7).

**Gap retroactivo que encontré al revisar esto, no algo que esta pieza cause**: `hitos_certificacion`
(ya aplicada en producción) no tiene ningún guard equivalente — hoy se puede insertar un hito aunque la
obra esté en Modelo A. No lo arreglo acá sin que me confirmes que querés tocar una tabla ya aplicada;
queda listado en §10.

**El monto sigue sin vínculo a cómputo métrico real** — eso no cambia acá. Arreglar esto requeriría que
Solapa 1/2 (rubros/subítems/APU) estén conectadas a Supabase, lo cual no está hecho (`CLAUDE.md`, ver
"Divergencia con la Clean Architecture" y el resto del diagnóstico de brechas). `certificados.monto`
sigue siendo un valor cargado a mano, igual que en el mock de hoy — nombrarlo explícitamente para que no
se asuma que esta pieza lo resuelve.

## 3. Columnas nuevas en `obras` que esto necesita — algunas ya diseñadas, nunca migradas

Tres de estas ya estaban diseñadas en `docs/modelos_certificacion_diseno_datos.md` §6 pero se dejaron
sin migrar porque no eran dependencia dura de los pasos anteriores (mismo criterio que ya se usó para
`monto_total_contratado`, que sí se migró cuando pasó a ser dependencia dura de `hitos_certificacion`).
Ahora sí lo son: un certificado necesita el `%` de anticipo/fondo de reparo para calcular su neto, y el
ciclo de certificados necesita el plazo de pago pactado.

```sql
alter table obras
  add column dias_plazo_pago_certificados int,     -- nuevo, no estaba en el diseño anterior
  add column anticipo_pct numeric,                  -- ya diseñado, §6 del doc anterior, nunca migrado
  add column fondo_reparo_pct numeric;              -- ídem
```

Ya no incluye `requiere_firma_fisica_certificados` — definición cerrada en §10.1: la firma física se
decide por certificado al emitirlo, no una sola vez a nivel obra, así que no hace falta ninguna columna
nueva en `obras` para esto (ver §7/§8).

Las 3 restantes comparten el mismo patrón ya usado para `monto_total_contratado`/`dias_plazo_pago`
(mock): **configurables una sola vez, antes del Certificado N°1** ("Plazo de pago se configura una sola
vez antes del Certificado N°1 y aplica a todos los siguientes" — literal de la spec). Igual que con
`monto_total_contratado` (`docs/modelos_certificacion_diseno_datos.md` §7.7-bis), la regla de "editable
solo mientras no hay certificados todavía" queda como convención de capa de app en este diseño, no
forzada con trigger — mismo criterio ya aceptado explícitamente por vos para ese caso.

## 4. Tabla `certificados`

```sql
create table certificados (
  id uuid primary key default gen_random_uuid(),
  obra_id uuid not null references obras(id) on delete cascade,
  numero int not null,                     -- "Certificado N°1", asignado al crear (§9)
  periodo text not null,                   -- libre, igual que el mock: "Julio 2026"
  monto numeric not null check (monto > 0),
  estado text not null default 'borrador'
    check (estado in ('borrador', 'emitido', 'leido', 'pagado', 'impactado_cerrado')),

  creado_por uuid not null references auth.users(id),
  fecha_creacion timestamptz not null default now(),

  -- Emitido
  fecha_emision timestamptz,
  emitido_por uuid references auth.users(id),
  dias_plazo_pago int,                     -- snapshot de obras.dias_plazo_pago_certificados al emitir
  requiere_firma_fisica boolean,           -- decisión puntual al emitir, no snapshot de obras (§8)

  -- Leído por Propietario
  fecha_lectura timestamptz,
  leido_por uuid references auth.users(id),

  -- Pagado
  fecha_pago timestamptz,
  pagado_por uuid references auth.users(id),
  medio_pago text check (medio_pago is null or medio_pago in ('transferencia', 'efectivo', 'cheque', 'otro')),  -- definición cerrada §10.5
  comprobante_pago_adjuntos text[] not null default '{}',   -- mismo patrón que libro_entradas.adjuntos

  -- Anticipo / Fondo de Reparo — calculados y guardados (snapshot) al emitir, ver §6
  anticipo_pct_aplicado numeric,
  fondo_reparo_pct_aplicado numeric,
  monto_anticipo_descontado numeric,
  monto_fondo_reparo_retenido numeric,
  monto_neto_a_pagar numeric,

  -- Impactado y Cerrado
  fecha_impacto timestamptz,
  impactado_por uuid references auth.users(id),
  factura_final_adjuntos text[] not null default '{}',      -- mismo patrón que libro_entradas.adjuntos

  -- Firma física (independiente del estado del ciclo — puede subirse en cualquier momento después de emitido)
  pdf_firmado_subido boolean not null default false,
  pdf_firmado_fecha timestamptz,
  pdf_firmado_adjuntos text[] not null default '{}',        -- mismo patrón que libro_entradas.adjuntos

  unique (obra_id, numero),

  -- Coherencia: cada fecha implica que se pasó por los estados anteriores. Sigue sirviendo tal cual
  -- con "leído" salteable (definición cerrada §10.3) — ver la nota al final de §7 sobre por qué.
  check (estado not in ('emitido', 'leido', 'pagado', 'impactado_cerrado') or fecha_emision is not null),
  check (estado not in ('leido', 'pagado', 'impactado_cerrado') or fecha_lectura is not null),
  check (estado not in ('pagado', 'impactado_cerrado') or fecha_pago is not null),
  check (estado <> 'impactado_cerrado' or fecha_impacto is not null)
);
```

Tres campos separados de adjuntos (`comprobante_pago_adjuntos`, `factura_final_adjuntos`,
`pdf_firmado_adjuntos`) en vez de uno solo genérico: miré cómo está tipado `libro_entradas.adjuntos`
(`List<String>` en Dart, columna `text[]` — lista plana de URLs, sin distinguir qué es cada adjunto) y
decidí no reusar esa misma forma para un solo campo acá, porque en `certificados` sí importa distinguir
qué es cada adjunto (uno gatea la siguiente emisión, otro es prueba de pago, otro cierra el ciclo) — tres
columnas del mismo tipo (`text[]`, mismo patrón que `libro_entradas`) en vez de una sola con semántica
mezclada.

## 5. `numero`: asignado al crear, sin secuencia dedicada

`numero = (select coalesce(max(numero), 0) + 1 from certificados where obra_id = :obra_id)`, calculado
por la app antes del insert, con `unique(obra_id, numero)` como red de seguridad. Limitación conocida y
aceptada, no resuelta con más mecanismo: una carrera entre dos inserts simultáneos para la misma obra
podría violar el unique y requerir reintento — de bajo riesgo dado que normalmente hay un solo
Admin/Profesional creando certificados de a uno por obra, mismo nivel de rigor que ya se aceptó para
casos similares en este proyecto.

## 6. Anticipo y Fondo de Reparo: cálculo simple, no acumulado

Repasando `docs/modelos_certificacion_diseno_datos.md` §6, la única parte que había quedado
explícitamente diferida para esta pieza era "calcular ese descuento acumulado por certificado/hito". Al
diseñarlo ahora, no hace falta ningún mecanismo acumulado: el `%` se aplica de forma independiente sobre
el monto de **cada** certificado, no sobre un saldo corrido:

```
monto_anticipo_descontado   = round(monto * anticipo_pct / 100, 2)
monto_fondo_reparo_retenido = round(monto * fondo_reparo_pct / 100, 2)
monto_neto_a_pagar          = monto - monto_anticipo_descontado - monto_fondo_reparo_retenido
```

Se calculan y se guardan (no se recalculan en vivo) al momento de emitir (`emitir_certificado()`, §7),
tomando el `%` vigente de `obras` en ese instante — coherente con que esos `%` ya quedaron cerrados como
"fijos una sola vez por obra" (§7.6 del diseño anterior): en la práctica el valor snapshot y el valor
vivo en `obras` siempre van a coincidir, pero guardar el snapshot deja el certificado ya emitido como un
registro financiero congelado, sin depender de que nadie vuelva a tocar `obras` después (mismo espíritu
de "no retroactivo" que ya se aplicó en todo lo demás de esta pieza).

## 7. Autoridad por transición — funciones, mismo patrón que `cambiar_modelo_certificacion`/`aprobar_ajuste_contrato`

Cada transición con efectos secundarios (fechas, snapshots, bloqueo de firma física, `audit_log`) es una
función atómica, no una política `UPDATE` genérica. La creación del Borrador es la excepción: una
política `INSERT` simple alcanza, no tiene efectos secundarios que coordinar.

**Corrección importante sobre el patrón de las piezas anteriores — `SECURITY DEFINER`, no
`SECURITY INVOKER`.** `cambiar_modelo_certificacion`/`aprobar_ajuste_contrato` son `SECURITY INVOKER`
porque las políticas `UPDATE` de las tablas que tocan ya eran lo bastante permisivas como para dejarlas
completar su trabajo. Acá no: la política `certificados_update` (corregida en
`supabase/migrations/0010_certificados_update_solo_borrador.sql`, sobre lo aplicado en el paso 1) solo
permite un `UPDATE` directo mientras el certificado sigue en `'borrador'`, y su `with check` exige que
el resultado también quede en `'borrador'` — bloquea a propósito cualquier transición de estado hecha
por fuera de una función, incluida la primera (`'borrador'` → `'emitido'`). Como consecuencia, **las 4
funciones de abajo tienen que ser `SECURITY DEFINER`**, haciendo ellas mismas el chequeo de autoridad
(`tiene_rol_en_obra`/`puede_gestionar_certificado`) en el cuerpo de la función en vez de apoyarse en la
política `UPDATE` de la tabla para eso — acá RLS pasa a ser puramente el candado del Borrador editable a
mano, no la autoridad real de las demás transiciones.

### Nuevo helper: `puede_gestionar_certificado(obra_id, monto)`

`puede_aprobar_monto` (ya existente, `0004_rls_etapa3.sql`) no sirve tal cual para "quién puede leer/
pagar un certificado": esa función incluye `admin_maestro`/`profesional` sin restricción porque fue
pensada para aprobar el *costo* de un adicional — pero acá quien lee y paga es específicamente el
Cliente (o su Apoderado delegado), no el lado de la Empresa. Reusarla tal cual le daría a
`admin_maestro`/`profesional` la capacidad de marcarse a sí mismos el cobro de su propio certificado, lo
cual no tiene sentido de negocio. Hace falta un helper nuevo, mismo patrón `SECURITY DEFINER`:

```sql
create or replace function puede_gestionar_certificado(p_obra_id uuid, p_monto numeric)
returns boolean language sql security definer set search_path = public stable as $$
  select
    tiene_rol_en_obra(p_obra_id, 'cliente_principal')
    or exists (
      select 1 from obra_members
      where obra_id = p_obra_id and usuario_id = auth.uid() and activo
        and rol = 'invitado_apoderado' and puede_aprobar_certificados
        and (tope_monto_aprobacion is null or p_monto <= tope_monto_aprobacion)
        and ((delegacion_inicio is null and delegacion_fin is null)
             or now() between delegacion_inicio and delegacion_fin)
    );
$$;
```

Mismo criterio de delegación/tope que ya usa `puede_aprobar_monto`, pero sin el acceso incondicional de
`admin_maestro`/`profesional`, y chequeando `puede_aprobar_certificados` (no `puede_aprobar_adicionales`)
— son flags separados en `PermisosEspeciales` desde Etapa 3, hoy sin uso real hasta esta pieza.

### Nuevo helper: `obra_modelo_es(obra_id, modelo)`

Para el guard de §2 en la política `INSERT`. `SECURITY DEFINER`, mismo motivo que ya tienen
`is_obra_member`/`tiene_rol_en_obra`: si el guard hiciera un `select` directo contra `obras` dentro de
una política de `certificados`, esa subconsulta quedaría sujeta a la política `SELECT` de `obras` (que
no conozco en detalle — no tiene migración propia en este repo, ver nota en `0005_modelo_certificacion.sql`)
en vez de resolverse de forma directa — mismo problema de fondo que ya motivó `SECURITY DEFINER` en
`is_obra_member` para no depender de la RLS de la tabla consultada.

```sql
create or replace function obra_modelo_es(p_obra_id uuid, p_modelo text)
returns boolean language sql security definer set search_path = public stable as $$
  select exists (select 1 from obras where id = p_obra_id and modelo_certificacion = p_modelo);
$$;
```

### Las 4 funciones de transición, más una 5ª que resultó necesaria al implementar (§7-bis abajo)

**`crear_certificado_borrador`** — no es una función, es la política `INSERT` (§9): `admin_maestro`,
`profesional` o `constructor` (el Constructor puede *solicitar*/cargar un borrador, mismo criterio ya
documentado en `CLAUDE.md` para la matriz de Gestión de Obra: "Constructor/Capataz... puede solicitar la
aprobación de un certificado pero no aprobarlo él mismo").

**`emitir_certificado(p_certificado_id uuid, p_requiere_firma_fisica boolean)`** — Borrador → Emitido.
Autoridad: `admin_maestro` o `profesional` ("aprobado por el Profesional", literal de la spec —
**definición cerrada, §10.2**: `constructor` queda afuera de esto). Efectos: `fecha_emision = now()`,
`emitido_por`, snapshot de `dias_plazo_pago`/`anticipo_pct`/`fondo_reparo_pct` desde `obras`,
`requiere_firma_fisica = p_requiere_firma_fisica` (decisión del Profesional en el momento de emitir
*este* certificado puntual, **definición cerrada, §10.1** — ya no es un snapshot de `obras`, ver §8),
cálculo de los 3 montos de §6, y el **bloqueo de firma física**: si el certificado `numero - 1` de la
misma obra tiene `requiere_firma_fisica = true` y `pdf_firmado_subido = false`, la función lanza una
excepción y no emite — implementación literal de "el sistema bloquea la emisión del siguiente
certificado hasta subir el PDF/imagen firmado". `audit_log` con `accion='emitir_certificado'`.

**`marcar_certificado_leido(p_certificado_id uuid)`** — Emitido → Leído. Autoridad:
`tiene_rol_en_obra(obra_id,'cliente_principal')` o `tiene_rol_en_obra(obra_id,'invitado_apoderado')` (sin
el chequeo de tope/flag de `puede_gestionar_certificado` — ver por qué en la nota de abajo). Pensada para
que la app la llame **automáticamente** la primera vez que ese usuario abre el detalle del certificado,
no por un botón — "al abrir el certificado, se notifica automáticamente", literal de la spec. Idempotente:
si `fecha_lectura` ya está seteada, no hace nada (no lanza excepción) para que la app la pueda llamar sin
cuidado especial cada vez que se abre la pantalla. `audit_log` con `accion='marcar_certificado_leido'`
solo en la primera llamada real (no en los no-ops siguientes).

Por qué esta transición NO usa `puede_gestionar_certificado`: leer no es aprobar nada económico, es solo
un registro de que se vio — exigir `puede_aprobar_certificados`/tope acá le pondría una barrera de
permiso a un Apoderado que solo tiene delegación de *lectura* pero no de *aprobación de pago*, algo que
la spec no distingue explícitamente pero que me parece más fiel al espíritu de "Invitado Apoderado...
desbloquea los botones de aprobación" (la lectura no es un botón de aprobación). **Marcado como
ambigüedad §10** si esto debería ser más estricto.

**`marcar_certificado_pagado(p_certificado_id uuid, p_medio_pago text, p_comprobante_adjuntos text[] default '{}')`**
— Emitido **o** Leído → Pagado — **definición cerrada, §10.3**: "Leído" puede saltearse (un Propietario
puede pagar sin haber abierto nunca el certificado en la app). La función acepta el certificado en
`estado in ('emitido', 'leido')`; si `fecha_lectura` todavía es `null`, la propia función la completa
como efecto colateral (`fecha_lectura = now()`, `leido_por = auth.uid()` — es la misma persona que está
marcando el pago, con la misma autoridad de `puede_gestionar_certificado` que ya tendría para leerlo) y
lo deja registrado en el `detalle` del `audit_log` de esta acción (`'lectura_automatica': true`) para que
el historial distinga una lectura real de una inferida. Ver nota abajo sobre por qué el `check` de §4 no
necesitó cambiar para esto. Autoridad: `puede_gestionar_certificado(obra_id, monto)` — acá sí importa el
tope, porque marcar "pagado" es un acto económico. `audit_log` con `accion='marcar_certificado_pagado'`.

**`marcar_certificado_impactado(p_certificado_id uuid, p_factura_adjuntos text[] default '{}')`** —
Pagado → Impactado y Cerrado. Autoridad: `admin_maestro` o `constructor` — **definición cerrada, §10.2**:
cambié `profesional` por `constructor` respecto a la primera versión de este diseño. "Profesional"
(Dirección Técnica, quien emite) y "Empresa/Constructor" (quien cobra y cierra administrativamente) son
roles distintos, no el mismo actor con dos nombres — coherente con que la spec usa términos distintos a
propósito para los pasos 2 y 5. `audit_log` con `accion='marcar_certificado_impactado'`.

**Por qué el `check` de coherencia de fechas de §4 no necesitó ningún cambio para §10.3**: pedías
ajustarlo para permitir el salteo de "Leído", pero revisándolo de nuevo no hacía falta — los 4 `check`
solo exigen que, *en el estado final que tenga la fila en cada momento*, las fechas de los pasos previos
estén completas; no exigen que la fila haya pasado literalmente por el valor `estado = 'leido'` en algún
punto de su historia (eso no es algo que un `check` de Postgres pueda expresar, solo ve la fila actual).
Como `marcar_certificado_pagado` completa `fecha_lectura` en la misma actualización atómica en la que
pone `estado = 'pagado'`, el `check` `estado not in ('leido','pagado','impactado_cerrado') or
fecha_lectura is not null` queda satisfecho igual, con o sin el paso intermedio por `'leido'` como
estado. El schema de §4 queda sin cambios.

### §7-bis — 5ª función: `subir_pdf_firmado_certificado(p_certificado_id uuid, p_adjuntos text[])`

No es una transición de estado del ciclo de 5 pasos — no cambia `estado`, solo
`pdf_firmado_subido`/`pdf_firmado_fecha`/`pdf_firmado_adjuntos`. La encontré necesaria recién al
escribir la migración del paso 2, no estaba contada entre "las 4 funciones de transición" de la versión
original de este documento: con `certificados_update` restringida a solo `'borrador'`
(`0010_certificados_update_solo_borrador.sql`), no quedaba ningún camino para marcar el PDF firmado
como subido una vez que el certificado ya está emitido — sin esta función, el bloqueo de
`emitir_certificado` (§7, arriba) sería imposible de destrabar nunca, para cualquier certificado con
`requiere_firma_fisica = true`. No es una ampliación de alcance decidida por mí, es una dependencia dura
que faltaba.

Autoridad: `admin_maestro` o `profesional` — mismo par que emite (es quien gestiona la Dirección Técnica
el intercambio del PDF firmado con el Cliente). Puede llamarse en cualquier momento después de emitido,
sin restricción de estado del ciclo (`estado <> 'borrador'` es la única condición). `audit_log` con
`accion='subir_pdf_firmado_certificado'`.

## 8. Firma física: decisión cerrada — por certificado, no por obra

**Definición cerrada, §10.1.** La spec dice: *"opción de descargar PDF en blanco (medición en campo) o
completo (firma en papel). Si se opta por firma física, el sistema bloquea..."* — la lectura que se
confirmó es la literal: una elección **por certificado, en el momento de emitirlo**, no una configuración
fija de toda la obra. Tiene sentido práctico además: una misma obra puede manejar certificados
intermedios de forma digital y reservar la firma física para los que tienen más plata en juego (por
ejemplo, el último).

`requiere_firma_fisica` en `certificados` (§4) no es un snapshot de ninguna columna de `obras` — es un
parámetro que recibe `emitir_certificado(p_certificado_id, p_requiere_firma_fisica)` directamente del
Profesional en el momento de emitir (§7). No hay ninguna columna nueva en `obras` para esto (§3 ya no
incluye `requiere_firma_fisica_certificados`). El bloqueo de la emisión siguiente (§7) sigue funcionando
igual, mirando el certificado `numero - 1` de la misma obra — el bloqueo es "por certificado anterior",
no "por obra", así que este cambio no le afecta nada a esa lógica.

## 9. Relación con `audit_log`, `modificaciones_obra`, `hitos_certificacion`

- **`audit_log`**: reusado igual que en las piezas anteriores — `entidad='certificado'`, `entidad_id` =
  id del certificado, sin tabla de historial aparte. El comentario original en `audit_log_entry.dart`
  ("a futuro para certificados...") finalmente se usa acá.
- **`modificaciones_obra`**: sin relación directa — un adicional/demasía/quita se certifica *dentro* del
  monto de un certificado futuro (el monto de un certificado ya incluiría lo aprobado), no genera una
  fila propia en `certificados`. No identifiqué ningún caso donde `certificados` necesite escribir en
  `modificaciones_obra` o viceversa.
- **`hitos_certificacion`**: sin relación directa — tablas hermanas para modelos distintos (A vs. B), no
  se referencian entre sí. La única relación es indirecta, vía `obras.modelo_certificacion` (§2), y esa
  relación es justamente lo que estaba mal en `hitos_certificacion` — ver §10.8 abajo.

### Cierre del gap retroactivo de `hitos_certificacion` (§10.8)

Confirmado: se corrige en esta misma pieza. Hoy (`0006_hitos_certificacion.sql` + `0007_hitos_certificacion_solo_admin.sql`,
ya aplicadas) la política `hitos_certificacion_insert` no chequea `obras.modelo_certificacion` en
absoluto — se puede insertar un hito con la obra en Modelo A. Se corrige con el mismo `obra_modelo_es`
diseñado en §7 para `certificados`, vía `DROP POLICY` + `CREATE POLICY` (mismo mecanismo que ya usó
`0007` para ajustar `hitos_certificacion` sin recrear la tabla).

**Matiz que encontré al ir a escribir esto, no estaba en tu pedido original**: `hitos_certificacion`
tiene doble función (`docs/modelos_certificacion_diseno_datos.md` §4/§7.3) — además del contrato
principal de Modelo B, también aloja Subcontratos con terceros (`contratista_nombre` cargado), que según
ese mismo diseño **no dependen de qué modelo de certificación tenga la obra** (un Subcontrato puede
existir aunque la obra esté certificando al Cliente bajo Modelo A). Si el guard de `obra_modelo_es` se
aplicara a la política entera sin distinguir, bloquearía crear Subcontratos en cualquier obra que esté en
Modelo A — lo cual rompería algo que ya funciona hoy, no solo cerraría el gap. El guard queda entonces
condicionado al mismo discriminador que ya distingue ambos casos (`contratista_nombre`):

```sql
drop policy hitos_certificacion_insert on hitos_certificacion;

create policy hitos_certificacion_insert on hitos_certificacion for insert with check (
  creado_por = auth.uid()
  and tiene_rol_en_obra(obra_id, 'admin_maestro')
  and (contratista_nombre is not null or obra_modelo_es(obra_id, 'hitos_precio_cerrado'))
);
```

También extendí el mismo guard (con el mismo matiz de Subcontratos) a la política `UPDATE` de
`hitos_certificacion`, no solo a `INSERT` — vos mencionaste específicamente el caso de insertar, pero me
parece inconsistente permitir seguir editando/rescindiendo un hito del contrato principal después de que
la obra ya no está en Modelo B (por ejemplo, si cambia a Modelo A con un hito todavía `'activo'`). Es una
extensión que decidí yo, marcala si preferís dejar `UPDATE` como está:

```sql
drop policy hitos_certificacion_update on hitos_certificacion;

create policy hitos_certificacion_update on hitos_certificacion for update using (
  estado = 'activo'
  and tiene_rol_en_obra(obra_id, 'admin_maestro')
  and (contratista_nombre is not null or obra_modelo_es(obra_id, 'hitos_precio_cerrado'))
) with check (
  tiene_rol_en_obra(obra_id, 'admin_maestro')
  and (contratista_nombre is not null or obra_modelo_es(obra_id, 'hitos_precio_cerrado'))
);
```

Esto depende de que `obra_modelo_es` (§7) ya exista — condiciona el orden de implementación, ver más
abajo en la respuesta al mensaje.

## 10. Definiciones cerradas — respuestas del usuario (revisadas con su consultor) a las 8 ambigüedades

**§10.1 — Firma física: ¿configuración de obra o elección por certificado?** Cerrado: por certificado,
al emitirlo. Desarrollo completo en §8.

**§10.2 — "Profesional" (paso 2) vs. "Empresa/Constructor" (paso 5): ¿son el mismo actor con dos
nombres, o dos roles distintos de `RolProyecto`?** Cerrado: son roles distintos. `emitir_certificado`
sigue siendo `admin_maestro`/`profesional` (sin cambios); `marcar_certificado_impactado` cambia a
`admin_maestro`/`constructor` (ya no `profesional`) — Dirección Técnica (quien emite) y quien cobra/cierra
administrativamente son responsabilidades distintas en la práctica real. Aplicado en §7.

**§10.3 — ¿"Leído" es un paso obligatorio antes de "Pagado", o puede saltearse?** Cerrado: sí puede
saltearse. `marcar_certificado_pagado` acepta el certificado desde `'emitido'` o `'leido'`, y completa
`fecha_lectura` automáticamente como efecto colateral si todavía no estaba. El `check` de coherencia de
fechas de §4 no necesitó ningún cambio para esto — ver la nota al final de §7 sobre por qué.

**§10.4 — `marcar_certificado_leido`: ¿debería requerir `puede_aprobar_certificados`/tope como
`puede_gestionar_certificado`, o alcanza con el rol simple?** Cerrado, confirmado tal como estaba
diseñado: rol simple (`cliente_principal` o `invitado_apoderado`), sin el chequeo de tope — leer no es
aprobar plata. Sin cambios en §7.

**§10.5 — Medio de pago: ¿enum cerrado o texto libre?** Cerrado, confirmado tal como estaba diseñado:
enum con `'transferencia'`/`'efectivo'`/`'cheque'`/`'otro'` como escape. Sin cambios en §4.

**§10.6 — ¿Existe un estado "Cancelado"/"Descartado" para un Borrador que nunca se emite?** Cerrado: no,
por ahora. Un Borrador abandonado sin avanzar no genera ningún daño de negocio quedándose así — no
justifica la complejidad de un estado nuevo en este momento. Sin cambios en §4.

**§10.7 — Continuidad de numeración si una obra cambia de modelo A→B→A.** Cerrado: la numeración
continúa sin reiniciar, consistente con el principio de "no retroactivo" que ya rige el resto del
proyecto. Sin cambios en §5 (ya estaba diseñado así).

**§10.8 — Gap retroactivo en `hitos_certificacion`: ¿se corrige ahora o queda para otro momento?**
Cerrado: se corrige ahora, en esta misma pieza. Desarrollo completo (incluido un matiz sobre Subcontratos
que encontré al escribirlo) en la nueva subsección al final de §9.

## 11. Qué NO hice en este paso — y orden de implementación propuesto

- No creé ninguna tabla ni columna en Supabase — todo lo de arriba es propuesta en SQL, no ejecutada.
- No toqué `gestion_obra_tab.dart` ni ningún otro archivo de `lib/`.
- No diseñé la matriz de permisos por tipo de relación cliente-obra (§1) — capa de visibilidad aparte,
  no cambia el schema de `certificados`.
- Extendí el guard de `hitos_certificacion` a la política `UPDATE`, no solo `INSERT` como se pidió
  literalmente en §10.8 — decisión mía, marcada explícitamente en la subsección de §9 por si se prefiere
  dejar `UPDATE` como está.

Las 8 ambigüedades quedaron cerradas (§10). Confirmado por el usuario: RLS de `certificados` va en el
mismo archivo de creación (no dejar ninguna ventana sin RLS, mismo criterio que `hitos_certificacion`),
y el guard de §9 va también en `UPDATE` de `hitos_certificacion`, no solo `INSERT`.

Orden de implementación, mismo criterio incremental ya usado en Modelos A/B:

1. **`obras` (3 columnas nuevas, §3) + tabla `certificados` (§4) + RLS completa (`SELECT`/`INSERT`/`UPDATE`, §7)**.
   Ajuste sobre el plan original: `obra_modelo_es()` (helper que iba a ir en el paso 2) se adelanta a
   este paso 1, porque la política `INSERT` de `certificados` ya la necesita desde el guard "solo Modelo
   A" (§2) — no tiene sentido crear la tabla con RLS incompleta y parchearla después.
2. **Las 3 funciones de transición restantes + el helper `puede_gestionar_certificado`** (§7):
   `emitir_certificado`, `marcar_certificado_leido`, `marcar_certificado_pagado`,
   `marcar_certificado_impactado`.
3. **Guard retroactivo de `hitos_certificacion`** (`INSERT` y `UPDATE`, §9) — ya puede ir en paralelo
   con el paso 2 si hace falta, dado que `obra_modelo_es` ya existe desde el paso 1.

**Estado de implementación**:
- ✅ **Paso 1**: `supabase/migrations/0009_certificados.sql`, aplicada. Corregida por
  `supabase/migrations/0010_certificados_update_solo_borrador.sql` (política `certificados_update`
  original dejaba que cualquier usuario con uno de los 5 roles hiciera un `UPDATE` directo sobre un
  certificado ya emitido, sin pasar por ninguna función — riesgo real desde el uso normal de la app,
  no solo desde SQL a mano, a diferencia del límite ya aceptado para `ajuste_contrato`). Consecuencia
  para el paso 2: las 4 funciones tienen que ser `SECURITY DEFINER`, no `SECURITY INVOKER` — ver nota
  al principio de §7.
- ✅ **Paso 2**: `supabase/migrations/0011_certificados_funciones_transicion.sql`, aplicada y
  verificada en producción (Database → Functions, 6 funciones confirmadas: helper
  `puede_gestionar_certificado` + las 4 funciones de transición, todas `SECURITY DEFINER` ver nota
  de §7, más la 5ª función no contada originalmente `subir_pdf_firmado_certificado` — ver §7-bis,
  dependencia dura descubierta al implementar, no ampliación de alcance decidida sola). Confirmado
  por el usuario: `subir_pdf_firmado_certificado` queda `admin_maestro`/`profesional` tal como se
  escribió, sin agregar `constructor`.
- ✅ **Paso 3**: `supabase/migrations/0012_hitos_certificacion_guard_modelo.sql`, aplicada y
  verificada en producción (Database → Policies) — `DROP POLICY` + `CREATE POLICY` sobre
  `hitos_certificacion_insert`/`hitos_certificacion_update`, agregando el guard de `obra_modelo_es`
  condicionado a `contratista_nombre is null` (ver §9), con el guard también en `UPDATE` (extensión
  propuesta por Claude Code, confirmada por el usuario).

**Los 3 pasos quedaron aplicados y verificados en producción.** Pieza cerrada.
