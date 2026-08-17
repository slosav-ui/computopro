# Etapa 3 — Roles y Permisos: diseño de datos (arquitectura de información)

Estado: **diseño cerrado y aprobado (revisado por el usuario con su consultor), sin implementar todavía.** Ningún archivo de `lib/` ni tabla de Supabase fue tocado para este documento. Falta solo definir el orden de implementación (qué se crea primero: `obra_members`, o el reemplazo de `UserContext`, etc.) antes de pasar a código.

Contexto: reemplaza la pausa registrada en la memoria del proyecto sobre Etapa 3 (roles combinables, vinculaciones, autogestión) ahora que el usuario cerró la spec funcional completa. Reconcilia con el esquema `ProyectoUsuarios` ya esbozado en la sección "Módulo Core" de `CLAUDE.md` en vez de inventar desde cero. Las 7 preguntas abiertas de la versión anterior de este documento ya fueron respondidas — ver §6.

---

## 1. Diagnóstico: ¿alcanza con extender lo que ya existe?

**No alcanza con extender `UserContext`/`PermisosModulo`/`CapaVisibilidad`. Hace falta una estructura relacional nueva.** Razón concreta, no genérica:

- `core/segurity/user_context.dart` → `UserContext(userId, role)` asume **un solo rol por usuario, global, sin obra asociada**. La spec (A) exige lo opuesto en dos ejes: roles combinables dentro de una misma obra, y rol distinto por cada obra en la que participa la misma persona. Esto no es extensible agregando campos — necesita pasar de "un valor" a "una relación" (tabla).

- `data/models/obra_model.dart` → `CapaVisibilidad capaVisibilidad` y `PermisosModulo permisos` están definidos **una sola vez por obra** (`ObraModel.capaVisibilidad`, `ObraModel.permisos`), como si toda la obra tuviera una única audiencia homogénea. La regla (B) —el APU es privado *por actor que lo generó*, no por rol del que mira— **no se puede expresar como un flag a nivel obra**. Un `PermisosModulo.verApuYCoeficienteK = true/false` no puede responder "¿el Profesional ve el APU del Constructor?" porque esa pregunta depende de *quién generó ese APU en particular*, no de un permiso fijo de la obra.

- Conclusión práctica: `PermisosModulo`/`CapaVisibilidad` quedan **obsoletos como fuente de verdad** para permisos reales. Pueden sobrevivir como una proyección/resumen calculado en UI (ej. para pintar un badge "Caja Blanca/Negra" rápido), pero no como el mecanismo de control de acceso — el control de acceso real tiene que resolverse por fila (¿quién generó este APU puntual?), no por obra.

- Lo que sí se puede reutilizar: `ObraModel.idAdminCreador` (ya existe) y `ObraModel.invitadoPorRol` (ya existe, con valores como `'Socio del Profesional'` — ver §6.3) encajan bien como conceptos dentro del nuevo esquema, no hace falta descartarlos.

**Se necesita**: una tabla de relación tipo `obra_members` (el `ProyectoUsuarios` ya anticipado en `CLAUDE.md`) para roles combinables por usuario+obra, **más** un cambio de enfoque en cómo se modela la privacidad del APU: en vez de un permiso a nivel obra, un **campo de dueño (`creador_usuario_id`) en cada registro económico**, y una regla de visibilidad genérica evaluada en tiempo de consulta (`visible = creador_usuario_id == viewer_usuario_id`), no una matriz de casos hardcodeada por combinación.

---

## 2. Roles combinables por obra: `obra_members`

### Decisión de diseño: una fila por (obra, usuario, rol) — no un array de roles en una fila

Dos formas de modelar "roles combinables":

- **Opción A** — una fila por `(obra, usuario)` con `roles: List<Rol>` (columna array).
- **Opción B** — una fila por `(obra, usuario, rol)`, con `UNIQUE(obra_id, usuario_id, rol)`. Combinar roles = insertar varias filas para el mismo usuario en la misma obra.

**Recomiendo Opción B.** Motivo: varios de los campos de la spec (tope de monto de aprobación, ventana de delegación temporal, permiso de invitar terceros) son *específicos de un rol*, no de la persona en general — por ejemplo, la delegación de firma del Apoderado (tope de monto, fechas) no tiene sentido colgada de una fila que además representa su rol de Cliente. Con una fila por rol, cada grant lleva sus propios campos sin ambigüedad. Además es el mismo patrón relacional que ya usa el proyecto para roles/permisos (no introduce un concepto nuevo de "array de enums" en Postgres).

### Dart — `data/models/obra_member.dart` (nuevo archivo)

```dart
enum RolProyecto {
  adminMaestro,
  profesional,
  constructor,
  clientePrincipal,
  invitadoVeedor,
  invitadoApoderado,
}

class ObraMember {
  final String id;
  final String obraId;
  final String usuarioId;
  final RolProyecto rol;                 // un rol por fila — combinable insertando varias filas
  final String? invitadoPorUsuarioId;
  final bool activo;                     // revocar sin borrar (auditoría)
  final DateTime fechaAlta;
  final PermisosEspeciales permisosEspeciales;
}

class PermisosEspeciales {
  final bool puedeAprobarCertificados;
  final bool puedeAprobarAdicionales;      // reusa el mismo tope que certificados (ver §4)
  final double? topeMontoAprobacion;
  final DateTime? delegacionTemporalInicio;
  final DateTime? delegacionTemporalFin;
  final bool puedeInvitarTerceros;
  final bool puedeVerApuAjena;             // default false — concesión manual explícita, caso por caso (ver §6.3)
}
```

`puedeVerApuAjena` default **siempre `false`**: los "socios" invitados por el Profesional o el Cliente (`ObraModel.invitadoPorRol == 'Socio del Profesional'`, etc.) **no** heredan automáticamente la caja blanca de quien los invitó. Es una concesión que el invitador activa a mano, colaborador por colaborador, si confía en esa persona puntual — nunca un default compartido (definición cerrada, ver §6.3).

`RolProyecto` reemplaza/absorbe a `UserRole` (hoy en `user_context.dart`, roles `adminMaestro/profesional/constructor/clientePrincipal/veedor/apoderado`) alineándolo a los nombres ya usados en la sección "Roles de proyecto" de `CLAUDE.md` (`invitado_veedor`, `invitado_apoderado`). Es un rename/consolidación, no dos conceptos paralelos — si se aprueba este diseño, `UserContext` pasaría a ser un helper calculado a partir de una fila (o varias) de `obra_members`, no una clase con su propio enum separado.

### Supabase — tabla `obra_members`

```sql
create table obra_members (
  id uuid primary key default gen_random_uuid(),
  obra_id uuid not null references obras(id) on delete cascade,
  usuario_id uuid not null references auth.users(id),
  rol text not null check (rol in (
    'admin_maestro','profesional','constructor',
    'cliente_principal','invitado_veedor','invitado_apoderado'
  )),
  invitado_por_usuario_id uuid references auth.users(id),
  activo boolean not null default true,
  puede_aprobar_certificados boolean not null default false,
  puede_aprobar_adicionales boolean not null default false,
  tope_monto_aprobacion numeric,
  delegacion_inicio timestamptz,
  delegacion_fin timestamptz,
  puede_invitar_terceros boolean not null default false,
  puede_ver_apu_ajena boolean not null default false,
  created_at timestamptz not null default now(),
  unique (obra_id, usuario_id, rol)
);
```

No incluyo políticas RLS todavía (es implementación, fuera de este paso) — solo la nota de que la función helper típica sería algo como `is_obra_member(obra_id uuid) returns boolean` para reusar en las políticas de `obras`, `subitems`, futuras tablas de APU, `modificaciones_obra` y `libro_entradas`.

---

## 3. Privacidad de APU/Coeficiente K: regla genérica, no matriz por combinación

Esto es lo que pediste evitar hardcodear caso por caso, y la buena noticia es que **la spec (B) ya es genérica por sí misma** si se modela como propiedad del registro, no del rol:

> `visible_para(usuario_viewer, registro_apu) = (registro_apu.creador_usuario_id == usuario_viewer.id)`

Ninguna de las 5 combinaciones de (A) necesita un caso especial:
- Cliente+Profesional / Cliente+Constructor / Profesional+Constructor / cadena de 3 separados: cada persona solo ve el APU cuyo `creador_usuario_id` coincide con su propio id. Automático.
- Cliente+Profesional+Constructor (autogestión, una sola persona): esa persona es `creador_usuario_id` de todo lo que genera, así que ve "su" APU — no porque haya una regla especial de autogestión, sino porque la regla genérica da ese resultado cuando el creador y el viewer son la misma persona. Coincide exactamente con la frase de la spec "ve su propio APU, porque es el único".

**Definición cerrada (ver §6.1):** el dueño del APU es la *persona* (`creador_usuario_id`), no el par (rol, persona). Si alguien combina Profesional+Constructor en una misma obra, hay **un solo conjunto de APU compartido** entre ambos roles suyos — no dos cajas separadas por rol. Confirmado, no queda abierto.

Esto todavía no requiere crear la tabla de APU en este paso (ese diseño es el de la Solapa 2, más adelante en el orden ya acordado: Dashboard+Solapa1 → Solapa2 APU → ...). Lo único que hay que dejar anotado *ahora*, para no tener que migrar después, es: **cuando se diseñe la tabla de APU, necesita sí o sí una columna `creador_usuario_id`** — es el único requisito que la Etapa 3 le impone a la Etapa de APU.

`PermisosModulo.verApuYCoeficienteK` (el flag actual a nivel obra) queda **sin uso real** bajo este esquema — no hace falta borrarlo ahora (fuera de alcance de este paso), pero no va a ser lo que decida la visibilidad real.

---

## 4. Adicionales / Demasías / Quitas

### Dart — `data/models/modificacion_obra.dart` (nuevo archivo)

```dart
enum TipoModificacion { adicional, demasia, quita }
enum EstadoModificacion { pendiente, devuelto, aprobado, rechazado }

class ModificacionObra {
  final String id;
  final String obraId;
  final TipoModificacion tipo;
  final String? subitemId;              // 'adicional': null hasta que se aprueba, ver graduación más abajo
  final String descripcion;
  final double cantidad;                 // delta: + para adicional/demasía, cantidad a quitar para quita
  final double? precioUnitarioHeredado;  // demasía: copia el precio ya calculado del subitem
  final double montoTotal;               // lo único que ve el Cliente (regla B: sin desglose interno)
  final String? apuPrivadoId;            // adicional: referencia al APU nuevo, privado por creador (§3)
  final String solicitadoPorUsuarioId;   // quien lo detectó (puede ser el Constructor en terreno)
  final String subidoPorUsuarioId;       // quien tiene Dirección Técnica y lo eleva formalmente
  final EstadoModificacion estado;
  final String? aprobadoPorUsuarioId;    // Cliente o su Apoderado delegado (mismo tope que certificados)
  final DateTime fechaSolicitud;
  final DateTime? fechaResolucion;
  final String? comentarioResolucion;    // motivo de rechazo, o qué corregir si vuelve 'devuelto'
}
```

Puntos de la spec que quedan cubiertos:
- **Cadena jerárquica**: `solicitadoPorUsuarioId` (quien detectó) vs. `subidoPorUsuarioId` (Dirección Técnica, quien formaliza) — separados a propósito, porque la spec aclara que pueden ser personas distintas.
- **Demasía hereda precio**: `precioUnitarioHeredado` se copia del `Subitem`/línea de cómputo existente, sin pasar por un APU nuevo.
- **Adicional trae APU propio**: `apuPrivadoId` referencia un registro de APU nuevo, que hereda automáticamente la regla de privacidad genérica de §3 (el Cliente ve `montoTotal`, no ve el APU detrás de `apuPrivadoId`).
- **No retroactivo**: no necesita un campo propio — se resuelve en tiempo de cálculo comparando `fechaSolicitud`/`fechaResolucion` contra el historial de certificados ya emitidos de esa obra (que ya vive en `gestion_obra_tab.dart`, aunque hoy solo con 3 de los 5 estados documentados). No se está modelando el ciclo de certificados en este documento — es un dato que este esquema consume, no que redefine.

**Definiciones cerradas (ver §6.4, §6.5, §6.6):**
- **Estado `devuelto`** (nuevo, cuarto valor de `EstadoModificacion`, mismo patrón que la devolución de Servicios Especiales): un adicional/demasía/quita con un error simple (descripción, dato mal cargado) se devuelve para corregir en vez de rechazarse del todo. `devuelto` no es terminal: se edita el mismo registro (`descripcion`/`cantidad`/`montoTotal`) y vuelve a `pendiente` — no se crea un `ModificacionObra` nuevo. El historial completo de cada transición (`pendiente`→`devuelto`→`pendiente`→`aprobado`, etc.) vive en `audit_log`, no en la fila de `modificaciones_obra`, que solo guarda el estado *actual*.
- **Graduación a `Subitem` real**: un adicional se gradúa a un `Subitem` del cómputo **en el momento exacto en que pasa a `aprobado`** — ni antes (hasta la aprobación del Cliente no es un compromiso real) ni después (para cuando haya que certificar avance sobre eso, ya tiene que existir como ítem). Al aprobar: el sistema crea el `Subitem` nuevo y completa `ModificacionObra.subitemId` con su id. Desde ese momento, la Solapa 4 (certificación) no distingue entre ítems originales y adicionales aprobados — son lo mismo para efectos de certificar avance.
- **Autogestión total, auto-aprobación sin fricción**: cuando Cliente+Profesional+Constructor son la misma persona, la `ModificacionObra` **se sigue generando** (para mantener historial/trazabilidad completo de la obra) pero nace directamente en estado `aprobado`, con `aprobadoPorUsuarioId` igual al propio `solicitadoPorUsuarioId` — sin pedirle a esa persona un click extra de "aprobarse a sí misma".

### Trazabilidad: reusar un Audit Log genérico en vez de duplicar campos

La spec pide "fecha, quién solicitó, motivo, ítem afectado, cantidad/monto, estado" — todo eso ya vive en los campos de `ModificacionObra` de arriba (es un registro con estado, no hace falta una tabla de auditoría paralela solo para esto). Lo que sí conviene separar es el **historial inmutable de transiciones** (pendiente→aprobado, pendiente→rechazado, pendiente→devuelto→pendiente, y a futuro también aprobaciones de certificados, delegaciones de firma, moderación de contenido — todo lo que `CLAUDE.md` ya pide bajo "Audit Log inalterable"). Propongo una única tabla genérica reusable, no una por feature:

```sql
create table modificaciones_obra (
  id uuid primary key default gen_random_uuid(),
  obra_id uuid not null references obras(id) on delete cascade,
  tipo text not null check (tipo in ('adicional','demasia','quita')),
  subitem_id uuid,                         -- FK futura, cuando exista la tabla subitems (Solapa 2)
  descripcion text not null,
  cantidad numeric not null,
  precio_unitario_heredado numeric,
  monto_total numeric not null,
  apu_privado_id uuid,                     -- FK futura, cuando exista la tabla de APU
  solicitado_por uuid not null references auth.users(id),
  subido_por uuid not null references auth.users(id),
  estado text not null default 'pendiente' check (estado in ('pendiente','devuelto','aprobado','rechazado')),
  aprobado_por uuid references auth.users(id),
  fecha_solicitud timestamptz not null default now(),
  fecha_resolucion timestamptz,
  comentario_resolucion text
);

create table audit_log (
  id uuid primary key default gen_random_uuid(),
  obra_id uuid references obras(id) on delete cascade,
  usuario_id uuid not null references auth.users(id),
  ip inet,
  accion text not null,              -- ej. 'aprobar_adicional', 'rechazar_adicional', 'aprobar_certificado'
  entidad text not null,             -- ej. 'modificacion_obra', 'certificado', 'delegacion_firma'
  entidad_id uuid,
  detalle jsonb,
  created_at timestamptz not null default now()
);
```

`audit_log` genérica sirve para esto y para lo que ya pide `CLAUDE.md` en "Blindaje legal" (user_id, timestamp, IP, acción) — un único mecanismo, no uno por funcionalidad.

**Nota de implementación (2026-08-17):** `subitem_id` y `apu_privado_id` se aplicaron sin foreign key — `create table ... references subitems(id)` falló en producción (`relation "subitems" does not exist`, 42P01) porque esa tabla es alcance de la Solapa 2, todavía no existe. Quedan como `uuid` sueltos; cuando exista `subitems` (y la futura tabla de APU), agregar las FKs con un `alter table ... add constraint ... foreign key (...) references ...(id)` en una migración aparte — no bloquear esta tabla esperando a la otra. Ver `supabase/migrations/0002_modificaciones_obra_audit_log.sql` para el detalle exacto de los `alter table` sugeridos.

---

## 5. Los 3 "libros" de Gestión de Obra: tabla genérica vs. 3 tablas

**Recomiendo la tabla genérica**, con un trade-off concreto a tener en cuenta:

```sql
create table libro_entradas (
  id uuid primary key default gen_random_uuid(),
  obra_id uuid not null references obras(id) on delete cascade,
  libro text not null check (libro in ('obra','orden_servicio','nota_pedido')),
  autor_usuario_id uuid not null references auth.users(id),
  autor_rol text not null,                       -- con qué rol firmó (relevante si esa persona tiene varios roles en la obra)
  contenido text not null,
  adjuntos jsonb,                                 -- URLs a Storage (fotos/planos)
  entrada_padre_id uuid references libro_entradas(id),  -- acuse de recibo / respuesta, como hija de la entrada original
  created_at timestamptz not null default now()
);
```

**A favor de la tabla única**: una sola pantalla/query/paginación para los 3 libros, un solo lugar para el aviso legal persistente (§F: "no reemplaza al Libro de Obra rubricado"), y agregar un 4° libro el día de mañana no pide migración. `entrada_padre_id` modela limpio el caso asimétrico de Órdenes de Servicio (solo Profesional genera, Constructor "acusa recibo") y Notas de Pedido (al revés) como una entrada hija de la original, sin inventar una tabla de "acuses" aparte.

**En contra / costo real**: la regla de quién puede *escribir* difiere por `libro` — eso obliga a una política RLS (o validación en capa de servicio) que ramifica por `libro` + `autor_rol` en el INSERT. Con 3 tablas separadas esa misma lógica sería 3 políticas más simples en vez de 1 política con ramas. Es la misma cantidad de reglas de negocio en ambos casos — la tabla única ahorra en estructura de datos, no en complejidad de las reglas de escritura. Si en algún momento un libro necesita campos que los otros dos no tienen, ahí sí conviene partir esa tabla puntual; hasta entonces, genérica.

### Matriz de escritura por libro (definición cerrada, ver §6.7 — corrige la redacción original de la spec)

| Libro | Genera entradas raíz | Solo lee / responde como hija |
|---|---|---|
| **Libro de Obra** (bitácora general) | `admin_maestro`, `profesional`, `constructor`, `cliente_principal` | `invitado_veedor` (solo lectura, sin excepción), `invitado_apoderado` sin delegación activa |
| **Libro de Órdenes de Servicio** | `profesional` (Dirección Técnica) | `constructor` (acusa recibo, entrada hija) |
| **Libro de Notas de Pedido** | `constructor` | `profesional` y `cliente_principal` (responden, entrada hija) |

Corrección respecto a la redacción original de la spec ("escritura abierta a todos los roles con acceso" en el Libro de Obra): **`invitado_veedor` queda en modo solo lectura también en este libro**, sin excepción — mantiene el mismo patrón de lectura pasiva que tiene en el resto de la app (avance, fotos, certificados aprobados), no escribe en la bitácora oficial. `invitado_apoderado` escribe en el Libro de Obra únicamente si tiene una delegación activa vigente (mismo mecanismo de `delegacion_inicio`/`delegacion_fin` de `obra_members`, §2) — fuera de esa ventana, también es de solo lectura.

### Dart — `data/models/libro_entrada.dart` (nuevo archivo)

```dart
enum TipoLibro { obra, ordenServicio, notaPedido }

class LibroEntrada {
  final String id;
  final String obraId;
  final TipoLibro libro;
  final String autorUsuarioId;
  final RolProyecto autorRol;
  final String contenido;
  final List<String> adjuntos;
  final String? entradaPadreId;
  final DateTime fechaCreacion;
}
```

La UI del `admin_maestro` para tildar/destildar qué libros están activos por obra no necesita tabla nueva — es un campo de configuración a nivel obra (ej. `librosActivos: List<TipoLibro>` en `ObraModel`, o 3 booleanos), no una relación.

---

## 6. Definiciones cerradas — respuestas del usuario (revisado con su consultor) a los 7 puntos abiertos de la versión anterior

1. **Ownership del APU: por persona, no por rol combinado.** Confirmado tal como se había asumido. Si una misma persona combina Profesional+Constructor en una obra, hay un solo conjunto de APU compartido entre sus roles — no cajas separadas por rol. El dueño sigue siendo `creador_usuario_id` (§3), no `obra_member_id`.

2. **`admin_maestro` es un flag administrativo, no un cuarto rol económico.** Confirmado. El creador de la obra queda por defecto como Administrador sobre uno de los 3 roles económicos que ya ocupa — no es un actor aparte con su propio APU. No hay caso de "administrador puro" a contemplar en este diseño.

3. **Socios del Profesional/Cliente: NO comparten la caja blanca de quien los invitó por defecto.** `puede_ver_apu_ajena` (§2) es la concesión explícita, caso por caso, activada manualmente por quien invita — default siempre `false`. Es la opción más segura (evita exponer plata por accidente); el invitador la habilita a mano si confía en ese colaborador puntual.

4. **Graduación a `Subitem`: en el momento en que se aprueba.** Ni antes (hasta la aprobación del Cliente no es un compromiso real) ni después (para certificar avance ya tiene que existir como ítem). Ver el mecanismo completo en §4 — la Solapa 4 no distingue ítems originales de adicionales aprobados.

5. **Cuarto estado `devuelto` agregado a `EstadoModificacion`.** Mismo patrón que la devolución de Servicios Especiales: un error simple de descripción/dato se corrige sobre el mismo registro (vuelve a `pendiente`) en vez de rechazarse del todo. Ver §4.

6. **Autogestión total: `ModificacionObra` se auto-aprueba sin fricción, pero el registro se genera igual.** Nace en estado `aprobado`, con `aprobadoPorUsuarioId == solicitadoPorUsuarioId`, para no pedir un click extra de "aprobarse a sí mismo" — pero preserva historial/trazabilidad completo de la obra. Ver §4.

7. **Libro de Obra: `invitado_veedor` queda en modo solo lectura, también acá.** Corrige la redacción original de la spec ("escritura abierta a todos los roles con acceso") — el Veedor mantiene el mismo patrón de lectura pasiva que en el resto de la app. Escriben `admin_maestro`, `profesional`, `constructor` y `cliente_principal`; `invitado_apoderado` solo si tiene delegación activa. Ver la matriz de escritura en §5.

---

## 7. Qué NO hice en este paso

- No creé ninguna tabla en Supabase.
- No toqué `core/segurity/user_context.dart` ni `data/models/obra_model.dart`.
- No creé los archivos Dart nuevos mostrados arriba (son propuesta, no código real todavía).
- No diseñé la tabla de APU completa (insumos, mano de obra, equipos, Coeficiente K heredable) — eso es alcance de la Solapa 2, más adelante en el orden ya acordado; acá solo se deja anotado el único requisito que le impone Etapa 3 (`creador_usuario_id`).
- No definí el orden de implementación (qué se crea primero: `obra_members`, o el reemplazo de `UserContext`, etc.) — queda para la próxima conversación, ahora que el diseño está cerrado.
