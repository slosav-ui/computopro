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

### Límite conocido: el Factor K es deducible por resta — ACEPTADO, no se corrige (2026-09-10)

La regla genérica de arriba controla quién ve el *registro* de APU — no impide que alguien sin
acceso a ese registro **deduzca el Factor K igual, por resta**, si además tiene acceso al precio
final de una partida y al detalle de materiales/mano de obra de la obra (Mat y MO). Con dos o tres
partidas confirma el porcentaje, sin ninguna habilidad especial — es una resta.

Lo limita parcialmente que hace falta conocer los rendimientos exactos de la receta, que están en
la composición que esa persona no ve. Con rendimientos personalizados el número no cierra; con las
recetas oficiales del catálogo (rendimientos públicos, no de la obra) sí le sale.

**Decisión de Seba: se acepta como límite conocido, no se corrige.** En obra, el que quiere
estimar el margen de otro lo hace igual, con o sin app. Y cerrar el desglose de materiales y mano
de obra sería peor que el problema — ese dato hace falta para comprar. Detalle completo en
`docs/factor_k_apu_decisiones.md` (mismo texto en los dos documentos, a propósito, para que quede
anotado donde se diseña la privacidad del APU y donde se documenta el Factor K en sí).

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

---

## 8. Cambio de matriz: el `constructor` ve montos (2026-09-12)

### El problema: un error de nombres que arrastraba el diseño

La matriz definía al `constructor` como **"vista operativa sin montos"**, pensándolo como capataz:
carga avance, ve el cómputo, no ve precios. **En el rubro argentino el constructor es la empresa que
cotiza y ejecuta.** Textual de Seba: *"acá la mayoría de las veces el constructor es el que pasa
presupuesto parcial o global y construye la obra, y es el que HACE EL PRESUPUESTO. Nunca es el
capataz — el capataz es capataz"*. El rol le estaba ocultando montos justamente a quien los armó: el
nombre significaba una cosa en el diseño y otra en el rubro.

### El cambio

- `constructor` ve montos igual que `profesional`: cómputo con precios, Mat y MO con precios, la
  Solapa APU (receta oficial y la suya propia) y el Factor K de la obra, y los montos de Gestión de
  Obra y de Adicionales. En `UserContext`: `puedeVerMontosYAPU` y `puedeVerMontosGestionObra`
  incluyen `constructor`; `esVistaOperativa` deja de aplicarle (queda como "no ve montos en ningún
  lado" — hoy `invitado_veedor` y un apoderado sin delegación vigente — y no la usa ninguna
  pantalla).
- **No hay rol nuevo.** El capataz es alguien que el constructor invita, con los permisos que le
  quiera dar.
- **No se tocó la base**: todas las lecturas de precios, Factor K y montos ya estaban abiertas a
  cualquier miembro (`is_obra_member`); ocultarle montos al constructor era solo de la capa de app.

### Ver no es editar — y eso sí quedó igual

Las escrituras del presupuesto siguen siendo de `admin_maestro`/`profesional` en la RLS (0019, 0020,
0026, 0030, 0036, 0080) y en las funciones (presentar/congelar, emitir, subir PDF firmado). Como hasta
ahora solo esos dos roles llegaban a los controles de edición de la Solapa APU y de Mat y MO, esos
controles se gateaban solo por PRO. Abrirle la solapa al constructor sin más le habría mostrado
botones que la base rechaza — o, en un UPDATE, ignora sin error. Por eso se agregó
`UserContext.puedeEditarPreciosObra` (admin_maestro/profesional, mirror de esa RLS) y se aplicó al
selector de vista del presupuesto, al Factor K e impuestos, al lápiz y "Volver" de Mat y MO, al
tilde de cargas sociales y al campo de precio del panel de la composición (el rendimiento sí lo
puede editar: es su receta personal).

### Qué queda distinto entre constructor y profesional

Ver: nada — los dos ven exactamente lo mismo. Hacer:

| | profesional | constructor |
|---|---|---|
| Editar cómputo, precios, Factor K, vista del presupuesto, valor hora, orden de rubros, importar | sí | no |
| Presentar / congelar el presupuesto, emitir certificados, subir el PDF firmado | sí | no |
| Enviar un adicional presupuestado a aprobación | sí | solo el que él creó |
| Cerrar un certificado cobrado (impactado) | **no** | sí |
| Leer el audit_log completo de la obra | sí | solo sus propias acciones |
| Cargar avance, quitas/demasías, anulación, certificar avance de adicionales | sí | sí |

Con lo que dijo Seba ("es el que HACE EL PRESUPUESTO"), la primera fila es la inconsistencia que
queda: el constructor ve el presupuesto pero no lo puede armar en la app. Cambiarlo es RLS (varias
tablas y funciones), no `UserContext` — decisión aparte, pendiente.

### Lo que NO cambia, y un límite encontrado al verificar la premisa

- **La receta es de la persona** (§3, §6.1): cada uno ve su receta propia o la oficial, nunca la de
  otro salvo `puede_ver_apu_ajena` (default `false`). Sin tocar.
- **El Factor K NO es de la persona — es de la obra.** Verificado en el código: los % (GG,
  Imprevistos, EPP, Costo Financiero, Beneficio, Gestión de materiales de terceros) e impuestos viven
  en `obra_presupuesto_config`/`obra_impuestos`, **una fila por obra**, legibles por cualquier
  miembro; `puede_ver_apu_ajena` no los cubre (solo gobierna la visibilidad de recetas personales,
  0019). Hasta este cambio lo único que se los ocultaba al constructor era la app. **Desde este
  cambio, un empleado invitado como constructor ve el Factor K de la obra** en la Solapa APU — los
  coeficientes con los que se cotizó. Lo que sigue sin ver es la receta personal (rendimientos e
  insumos propios). Esto choca con el caso que planteó Seba ("no quiero que vea mi receta de los
  factores K con los cuales cotizo la obra") — **pendiente de su decisión**, sin tocar las APU ni
  `puede_ver_apu_ajena`, como pidió. Nota: aun sin el bloque, el Factor K es deducible por resta
  (§3, límite ya aceptado) desde que el constructor ve precios de partidas y de insumos.
- **Los precios y materiales que ve cada uno salen de SU receta.** `calcular_composicion_detalle_
  subitem` y `consolidado_insumos_obra` resuelven la composición por `auth.uid()` (propia u
  oficial). Un empleado sin recetas propias ve el cómputo y la lista de materiales calculados con la
  receta **oficial**, no con la personal de quien cotizó: si Seba cotizó con recetas propias, el
  empleado ve otras cantidades de materiales y otros precios de partida. `puede_ver_apu_ajena` le
  deja ver la receta ajena en la composición, pero no hace que los cálculos la usen. Ya pasaba entre
  profesional y constructor siendo personas distintas; con el constructor viendo montos se vuelve
  visible.

### `invitado_veedor`

No le cambia nada: no está en ninguna de las dos reglas de montos, y `esVistaOperativa` ahora lo
describe a él. Sigue sin montos en Cómputo, Mat y MO, APU (no ve la solapa), Gestión de Obra,
Adicionales, carga de avance y detalle de certificado. Excepciones que ya existían, ajenas a este
cambio: el dashboard (`ObrasListScreen`) muestra montos a cualquier miembro (nunca filtró por rol, no
tiene `UserContext` por obra), y la solapa Resumen es todavía un mock con números fijos.

## 9. Constructor igual a profesional también en lo que HACE — diagnóstico (2026-09-12)

Decisión de Seba, sobre §8: *"El constructor tiene que poder editar todo lo del presupuesto: cómputo,
precios, Factor K, valor hora, orden de rubros e importar. Y también los actos formales: presentar,
congelar, emitir certificados y subir el PDF firmado. Si él cotiza y ejecuta la obra, es el que emite
los certificados."* Sin SQL todavía — falta cerrar §9.3.

### 9.1 Qué hay que tocar — inventario de lo vigente, no supuesto

Script sobre la última definición de cada política y función de `supabase/migrations/`:

- **19 políticas** que nombran `profesional` sin `constructor`: `obra_subitems` insert/update/delete
  (0019/0028), `obra_rubros_orden` insert/update (0026), `obra_presupuesto_config` update y
  `obra_impuestos` update (0020), `obra_insumo_precios` insert/update/delete (0030),
  `obra_valor_hora_override` insert/update/delete (0036), `importaciones`/`importaciones_items`/
  storage (0080, 5 políticas), `audit_log_select` (0004).
- **6 funciones**: `presentar_presupuesto_obra` (0103), `congelar_presupuesto_obra` (0104),
  `emitir_certificado` (0107), `subir_pdf_firmado_certificado` (0011), `confirmar_importacion`
  (0081), `enviar_adicional_a_aprobacion` (0118).
- **Al revés, 1 función**: `marcar_certificado_impactado` (0011) — admin_maestro y constructor, NO
  profesional.
- **Dart**: los getters que espejan esas reglas (`puedeEditarComputo`, `puedeEditarPreciosObra`,
  `puedeEmitirCertificado`, `puedeMarcarCertificadoImpactado`, `puedeEnviarAdicional`) y los botones
  de presentar/congelar/importar/subir PDF.

### 9.2 ¿Quedan indistinguibles?

**En permisos, casi.** Después del cambio, lo único que los separa:

1. **Los libros de Órdenes de Servicio y Notas de Pedido** (`libro_entradas_insert`, 0004/§5): el
   profesional (Dirección Técnica) emite órdenes y el constructor acusa recibo; el constructor emite
   notas de pedido y el profesional responde. No es un privilegio de uno sobre otro: es la expresión
   legal de que son **contrapartes** — uno dirige, el otro ejecuta. Igualarlos borraría el sentido de
   los dos libros.
2. **Aprobar ajustes de contrato (Modelo B)**, vía `puede_aprobar_monto` (0004/0008): hoy
   admin_maestro/profesional/cliente. Sumar al constructor es que el contratista apruebe una suba de
   su propio contrato — ver §9.3-B.
3. **Identidad**: quién es quién en la lista de miembros, las invitaciones, el `perfil_creador` de
   la obra y la matrícula que va al PDF (la del profesional).

### 9.3 Ambigüedades

**A. ¿Fusionar o dejarlos separados?** Recomiendo **separados, con los permisos iguales por
construcción**: un solo helper SQL (`es_equipo_tecnico(obra)` = admin_maestro/profesional/
constructor) que usan todas las políticas y funciones del inventario, y un solo getter en Dart. Así
no pueden divergir por accidente, y si algún día se quiere que diverjan, es una línea. Motivos para no
fusionar:
- los libros (§9.2-1) necesitan la distinción, y son la parte legal de Gestión de Obra;
- en una obra con Dirección Técnica y contratista siendo personas distintas, siguen siendo dos partes
  enfrentadas aunque puedan hacer lo mismo — el cliente tiene que saber quién es quién, y la dupla de
  la anulación (propone uno, resuelve otro) solo tiene sentido entre dos partes;
- fusionar es la operación cara e irreversible: cambiar el check de `obra_members.rol`, migrar filas
  (y deduplicar a quien hoy tiene los dos roles), invitaciones, textos, el enum `RolProyecto`, cada
  política y función — para ninguna ganancia funcional sobre "separados con los mismos permisos". Si
  más adelante hace falta distinguirlos de nuevo (por ejemplo, una conformidad de la Dirección Técnica
  sobre el certificado del contratista), deshacer una fusión es mucho peor que cambiar un helper.

**B. Ajuste de contrato (Modelo B).** ¿El constructor aprueba ajustes de contrato? Recomiendo que
**no**: aprobaría un cambio del monto que él mismo cobra. Queda como hoy (admin_maestro/profesional/
cliente). Es la única excepción a "iguales en todo", y es la misma lógica que ya cerró los adicionales
("la aprobación la da el que paga", §7-B de adicionales).

**C. Cerrar un certificado cobrado.** Para que queden iguales, el profesional también puede marcarlo
impactado/cerrado (hoy solo admin_maestro/constructor). Recomiendo que **sí**: un profesional que
además construye es el que cobra.

**D. Libros.** Recomiendo **dejarlos asimétricos** (§9.2-1): no es una diferencia de permisos, es qué
es cada libro.

### 9.4 Nota sobre §8

El gate `puedeEditarPreciosObra` de §8 (constructor ve pero no edita) queda como está hasta aplicar la
migración de esta sección — espeja la RLS de hoy. Cuando la RLS incluya al constructor, el getter lo
incluye también; los controles no se tocan.

### 9.5 Cerradas por Seba (2026-09-12)

- **A.** Separados, con un helper común — "tu argumento es bueno". El helper pasa a ser el permiso de
  §10, no una lista de roles.
- **B.** El constructor **no** aprueba ajustes de contrato: "aprueba el que paga, igual que en
  adicionales". `puede_aprobar_monto` sin cambios.
- **C.** El profesional también puede cerrar un certificado cobrado.
- **D.** Los libros quedan como están.
- Y el Factor K visible al empleado (§8): "con el permiso de edición apagado no me preocupa, porque lo
  ve pero no lo cambia. Lo dejamos así." Cerrado.

## 10. Permiso `puede_editar_presupuesto` — diseño (2026-09-12)

Decisión de Seba: *"Un permiso nuevo que se otorga al invitar: puede_editar_presupuesto, apagado por
defecto. El que armó el presupuesto es el que lo edita; los demás lo ven pero no lo tocan. Si el
constructor es administrador, el profesional y el cliente ven precios pero no los editan. Hoy eso no
se puede expresar porque los permisos dependen del rol."* Y resuelve el hueco de §9: el empleado
entra como constructor sin el permiso — ve precios, compra, carga avance, no toca el presupuesto ni
emite. Sin rol nuevo. Sin SQL todavía — falta cerrar §10.6.

### 10.1 Cómo convive con los roles

La lectura de Seba es la correcta: **el rol define qué ves, el permiso define qué editás** del
presupuesto y qué actos formales firmás. Con un matiz: el permiso solo tiene sentido en los roles que
ven el presupuesto — `profesional` y `constructor`. A un cliente, veedor o apoderado no se le ofrece
(no se edita lo que no se ve), y la base no lo acepta en esas filas (check en `obra_members` e
`invitaciones`). Regla completa, un solo helper SQL usado en todos lados (el "helper común" de §9-A):

    puede_editar_presupuesto(obra) =
        admin_maestro
        or (profesional o constructor, fila activa, con puede_editar_presupuesto = true)

### 10.2 El administrador edita siempre, sin el permiso

Sí. `admin_maestro` es quien crea la obra (bootstrap, 0033) — en el caso normal, "el que armó el
presupuesto" —, y una obra nueva necesita al menos alguien que la edite. Vale para cualquier
`admin_maestro` de la obra (puede haber más de uno desde la 0108): es la administración de la obra,
no un rol económico (§6.2). Si el constructor crea la obra, él es admin y edita; el profesional y el
cliente que invite ven y no editan — exactamente el caso que planteó Seba. (El cliente, como hoy, ve
totales y certificados, no APU ni precios unitarios: eso lo define su rol, no cambia.)

### 10.3 Qué cubre — una sola llave, presupuesto y actos formales juntos

| Acción | Hoy | Propuesta |
|---|---|---|
| Editar cómputo (tildar, cantidades, precio manual), precios de insumos, Factor K e impuestos, vista del presupuesto, valor hora y cargas sociales, orden de rubros, importar | admin/profesional por rol | **permiso** |
| Presentar y congelar el presupuesto | admin/profesional | **permiso** |
| Emitir certificado, subir el PDF firmado | admin/profesional | **permiso** |
| Proponer/resolver la anulación de un certificado | profesional/constructor | **permiso** (§10.6-1) |
| Cerrar un certificado cobrado | admin/constructor | **permiso** (con §9-C, el profesional entra) |
| Aprobar quita/demasía (cambia cantidades del cómputo y del congelado) | profesional/constructor | **permiso** (§10.6-1) |
| Enviar un adicional presupuestado a aprobación (congela) | admin/profesional de la hija | **permiso** en la hija |
| Ver montos, APU, Factor K | por rol (§8) | por rol, sin cambios |
| Cargar avance en el borrador, certificar avance de un adicional, crear adicionales y quitas/demasías, libros | por rol | por rol, sin cambios |

**¿Separar algo?** Recomiendo **una sola llave**. El único corte natural sería presupuesto vs.
certificación — alguien que certifica sin poder tocar precios, típicamente una Dirección Técnica que
no cotizó. Pero Seba lo descartó de frente ("no tiene sentido que arme el presupuesto y después
dependa de otro para certificar"), y con el helper en su lugar, partirlo después es sumar una segunda
columna y cambiar qué helper usa cada función — no rehacer nada.

### 10.4 La protección va en la base, no en los botones

- **Cada política y función del inventario de §9.1**, más anulación, cierre y quitas/demasías, pasa a
  llamar al helper. Los botones de la app (vía `UserContext`) solo espejan lo que la base ya exige.
- **El "guardó pero no guardó"**: con RLS, un UPDATE sin permiso no da error — afecta 0 filas y la app
  cree que guardó (el caso que ya nos pasó). Además de la base, los repositorios que hacen UPDATE
  directo sobre esas tablas pasan a pedir la fila actualizada y tratan "0 filas" como error ("no
  tenés permiso para editar el presupuesto de esta obra"). Así, si algún día un botón quedara
  visible por error, el usuario ve el rechazo en vez de un falso "guardado".
- **Quién lo otorga**: solo `admin_maestro` (§10.6-3). Hoy `invitaciones_insert` deja que cualquiera
  con `puede_invitar_terceros` cree una invitación con cualquier permiso — con este permiso eso sería
  una escalada (alguien que no edita invita a otro que sí). `obra_members_update` ya es de
  admin_maestro, así que otorgarlo o sacarlo después de la invitación también. Nota: la misma
  escalada existe hoy con `puede_aprobar_certificados`/`puede_aprobar_adicionales`/
  `puede_ver_apu_ajena` — fuera de esta pieza, anotado.

### 10.5 Lo que arrastra

- `obra_members.puede_editar_presupuesto` e `invitaciones.puede_editar_presupuesto` (boolean, default
  false, check por rol); `aceptar_invitacion` lo copia; las dos copias de equipo de adicionales
  (`crear_adicional_presupuestado`, `enviar_adicional_a_aprobacion`) lo copian a la obra hija.
- Obra hija: quien crea el adicional es `admin_maestro` de la hija (bootstrap), así que edita su
  cómputo siempre, aunque en la madre no tenga el permiso — ver §10.6-4.
- Dart: `PermisosEspeciales.puedeEditarPresupuesto`; en `UserContext`, los getters de las acciones de
  §10.3 pasan a una sola regla espejo del helper; checkbox en invitar (solo para profesional/
  constructor, solo si quien invita es admin); verlo y cambiarlo en la lista de miembros; el chequeo
  de "0 filas" en los repositorios.

### 10.6 Ambigüedades — necesito tu respuesta antes de escribir la migración

**1. Anulación y quitas/demasías, ¿con el permiso?** Recomiendo que sí. Anular un certificado es
un acto formal de certificación, igual que emitirlo; aprobar una demasía cambia cantidades del
cómputo y del presupuesto congelado — es tocar el presupuesto. Sin esto, el empleado sin permiso
podría anular certificados o subir cantidades. (Solicitar una quita/demasía sigue siendo de
cualquiera; lo que pide permiso es aprobarla.)

**2. Los que hoy editan.** Hoy edita cualquier profesional por su rol. Con el permiso, un profesional
sin la marca deja de editar. Recomiendo que la migración marque `true` a los profesionales activos
que ya existen — nadie pierde lo que hoy tiene — y deje en `false` a los constructores (hoy no
editan; se otorga a mano). Alternativa: todos en `false` y se otorga uno por uno.

**3. Quién lo otorga.** Recomiendo **solo admin_maestro**, al invitar o después (§10.4).

**4. Adicional creado por alguien sin el permiso.** Por el bootstrap, quien crea un adicional
presupuestado es admin de la obra hija y edita su cómputo, aunque en la madre no pueda. Recomiendo
dejarlo así: el adicional es su cotización, y la barrera real es la aprobación del cliente (§7-B de
adicionales). Alternativa: que crear un adicional presupuestado también pida el permiso.

### 10.7 Cerradas por Seba (2026-09-12) y lo escrito

- **1.** Anular y aprobar quitas/demasías piden el permiso — "tu ejemplo lo justifica solo: sin eso,
  mi empleado podría anular certificados o subir cantidades". Solicitar sigue siendo de cualquiera.
- **2.** Backfill: profesionales activos en `true`, constructores en `false`.
- **3.** Solo admin_maestro lo otorga — "es la única forma de cerrar la escalada".
- **4.** El adicional creado por alguien sin el permiso queda como está.
- **Aparte, para su propia pieza**: hoy cualquiera con `puede_invitar_terceros` puede otorgar
  `puede_aprobar_certificados`, `puede_aprobar_adicionales` (con tope) y `puede_ver_apu_ajena` — la
  misma escalada, sin cerrar todavía.

**Migración escrita, sin aplicar**: `supabase/migrations/0121_permiso_editar_presupuesto.sql` — la
columna en `obra_members` e `invitaciones` con su check por rol, el backfill, el helper
`puede_editar_presupuesto(obra)`, las 18 políticas de escritura del presupuesto, 12 funciones (el
chequeo de autoridad o la copia de permisos; cada una verificada con diff contra su versión vigente:
no cambia nada más), `invitaciones_insert`/`obra_members_insert` (solo admin otorga) y
`audit_log_select` (el constructor ve el historial completo, por rol). Anulación y quitas/demasías
conservan además el requisito de rol técnico (profesional/constructor): un admin que no es técnico —
el cliente que creó la obra — edita el presupuesto pero no aprueba demasías ni resuelve anulaciones,
como hasta ahora. Después de la 0121 lo único que distingue a profesional de constructor en la base
es `puede_aprobar_monto` (ajustes de contrato, §9.5-B) — verificado con el mismo script de §9.1.

**Dart, después de aplicarla:**
- `lib/data/models/obra_member.dart` (`PermisosEspeciales.puedeEditarPresupuesto`) y
  `lib/data/models/invitacion.dart`.
- `lib/services/invitaciones_repository.dart` (mandarlo al invitar) y
  `lib/services/obra_members_repository.dart` (leerlo, y que el admin lo cambie).
- `lib/core/segurity/user_context.dart` — `puedeEditarPresupuesto`, espejo del helper, y los getters
  de §10.3 apoyados en él: `puedeEditarComputo`, `puedeEditarPreciosObra`, `puedeEmitirCertificado`,
  `puedeMarcarCertificadoImpactado`, `puedeGestionarAnulacionCertificado` y
  `puedeAprobarQuitaDemasia` (rol técnico + permiso), `puedeEnviarAdicional`.
- `lib/presentation/obra_detalle/screens/invitar_miembro_screen.dart` — el checkbox (solo para
  profesional/constructor, solo si quien invita es admin) y
  `lib/presentation/obra_detalle/screens/miembros_obra_screen.dart` — verlo y que el admin lo cambie.
- "0 filas es error" en los repositorios con UPDATE/DELETE directo sobre tablas protegidas:
  `obra_subitems_repository.dart`, `obra_presupuesto_config_repository.dart`,
  `obra_impuestos_repository.dart`, `obra_insumos_repository.dart` (el delete del valor hora) e
  `importaciones_repository.dart`. (`obra_rubros_orden_repository.dart` y los `upsert`/`insert` no
  lo necesitan: si la RLS los rechaza, Postgres tira error.)
- Los botones que hoy leen los getters de arriba (presentar/congelar en `presupuesto_estado_panel.dart`,
  emitir/cerrar/anular en `gestion_obra_tab.dart`/`detalle_certificado_screen.dart`/
  `vista_previa_certificado_screen.dart`, firma física en `cartel_firma_pendiente.dart`, importar en
  `revisar_importacion_screen.dart`, quitas/demasías, Solapa APU y Mat y MO) no cambian de código:
  toman el permiso nuevo a través de los getters. Se revisan uno por uno en la prueba.
- `CLAUDE.md` — la matriz, con "rol = qué ves, permiso = qué editás".
