# Rubros: código vs. número impreso, reordenamiento por obra — diseño de datos

Estado: **diseño cerrado, implementación en curso.** Diagnóstico + 4 ambigüedades resueltas en
conversación el 2026-08-31. Etapas A, B y C **verificadas en el teléfono**. Etapa D **código escrito,
pendiente de aplicar la migración 0027 y de que el usuario lo verifique en el teléfono** — ver estado
detallado en §4. Falta E (numeración en el PDF).

Retoma el tema anotado en la memoria `rubros-codigo-orden-numeracion` (originado el 2026-08-30 al
diseñar la validación de código duplicado, migración `0025_rubros_codigo_unique_global.sql`, ya
aplicada). Esa migración resolvió el problema urgente (duplicados); este documento resuelve el
diseño grande que había quedado pendiente.

---

## 1. La decisión de fondo

Separar dos conceptos que hoy conviven en `rubros.codigo`:

- **Código**: identidad fija del rubro en el sistema. Fundaciones es y sigue siendo `"3"` para
  siempre, para todos — nunca cambia, nunca se muestra en la UI (ver §3, pregunta 2).
- **Número mostrado**: puramente posicional, calculado por la posición del rubro en la lista de
  **esa obra puntual**. El usuario reordena arrastrando; al soltar, toda la lista se renumera sola,
  correlativa y sin saltos. Nadie vuelve a tipear un número.

Consecuencia directa: los rubros propios dejan de ir siempre al final del catálogo — con
drag-and-drop pueden quedar en cualquier posición, igual que un oficial.

---

## 2. Schema

### 2.1 Tabla nueva: `obra_rubros_orden`

```sql
create table obra_rubros_orden (
  id uuid primary key default gen_random_uuid(),
  obra_id uuid not null references obras(id) on delete cascade,
  rubro_id uuid not null references rubros(id) on delete cascade,
  posicion numeric not null,
  updated_at timestamptz not null default now(),
  updated_by_usuario_id uuid references auth.users(id),
  unique (obra_id, rubro_id)
);
```

Solo guarda **overrides explícitos** — una fila existe únicamente para un rubro que alguien arrastró
en esa obra puntual. `rubro_id` con `on delete cascade` a propósito, a diferencia de
`obra_subitems.rubro_id` (sin cascade, para proteger cantidades cargadas — ver
`0019_obra_subitems.sql`): una fila acá es una preferencia de orden, no un dato del usuario:
perderla en silencio si el rubro se borra no arrastra nada de valor. El chequeo de borrado ya
implementado (`ObraSubitemsRepository.getNombresObrasConUso`) sigue mirando solo `obra_subitems`,
sin cambios — haber reordenado un rubro no debe bloquear borrarlo.

### 2.2 Indexación fraccionaria — por qué no hace falta reescribir todo al arrastrar

Misma técnica que usan Trello/Linear/Figma para listas con drag-and-drop:

- Para un rubro **sin** fila explícita, la posición default se deriva sin persistir nada:
  `rubros.orden * 1000` para oficiales (1000, 2000 ... 20000); para propios sin override, ver la
  decisión de §3 (tiebreaker por `created_at`, no por `codigo`).
- Al soltar un rubro en una posición nueva, se calcula el punto medio entre las posiciones (reales o
  default) de sus dos vecinos nuevos, y se hace **un solo upsert** sobre esa fila. El resto de la
  lista no se toca.
- `numeric` (no `double`) para no perder precisión tras reordenar muchas veces en el mismo hueco —
  con el volumen de esta app (reordenamientos manuales ocasionales) sobra margen sin necesitar lógica
  de renumeración periódica.

### 2.3 RLS

Mismo patrón que `obra_subitems` (`0019_obra_subitems.sql`) — reordenar es una acción de edición del
cómputo, misma autoridad:

```sql
alter table obra_rubros_orden enable row level security;

create policy obra_rubros_orden_select on obra_rubros_orden for select
using (is_obra_member(obra_id));

create policy obra_rubros_orden_insert on obra_rubros_orden for insert with check (
  tiene_rol_en_obra(obra_id, 'admin_maestro')
  or tiene_rol_en_obra(obra_id, 'profesional')
);

create policy obra_rubros_orden_update on obra_rubros_orden for update using (
  tiene_rol_en_obra(obra_id, 'admin_maestro')
  or tiene_rol_en_obra(obra_id, 'profesional')
) with check (
  tiene_rol_en_obra(obra_id, 'admin_maestro')
  or tiene_rol_en_obra(obra_id, 'profesional')
);
```

Sin política `DELETE` para el usuario — el `on delete cascade` de las FKs limpia solo cuando se borra
la obra o el rubro.

### 2.4 Obras donde nadie reordenó

Sin ninguna fila en `obra_rubros_orden` para esa obra, el merge cae 100% al default — mismo cálculo
que ya hace `RubrosRepository.getCatalogoCompleto` hoy (oficiales por `orden`, propios después). No
hace falta backfill ni migración de datos: pasa de ser *el único orden* a ser *el fallback cuando no
hay override*.

### 2.5 Visibilidad entre miembros de una obra

El orden es de la obra (una fila `(obra_id, rubro_id, posicion)` por override), no del usuario — si
el mismo rubro propio se usa en dos obras, cada obra tiene su propia fila independiente, sin diseño
extra. Si un colaborador sin `puede_ver_apu_ajena` no puede ver un rubro propio ajeno (política
`rubros_select` de `0015_rubros.sql`, sin tocar), esa fila directamente no aparece en su consulta a
`rubros` — y como el número mostrado se calcula por posición **dentro de la lista que esa persona
efectivamente ve** (nunca leyendo el valor crudo de `posicion`), no hay salto visible ni fuga de
información. Dos personas en la misma obra con distinta visibilidad de rubros propios pueden ver
numeraciones densas pero distintas entre sí — coherente con el resto del proyecto.

---

## 3. Definiciones cerradas — respuestas del usuario a las 4 ambigüedades

**1. Alta de un rubro nuevo: nace al final, se reordena arrastrando después.** Sin selector de
posición en el diálogo de alta — nace sin fila explícita en `obra_rubros_orden` (cae al fallback, al
final de esa obra) y usa el mismo mecanismo de drag que todo lo demás. Un solo flujo de
reordenamiento en toda la app, sin duplicar UI.

**2. La fila de cada rubro pasa a mostrar el número de posición en vez del código.** Afecta dos
lugares confirmados en el código: el título de cada fila en `RubrosTab`
(`'${rubro.codigo} - ${rubro.nombre}'`, `rubros_tab.dart:207`) y el `AppBar` de `SubitemsScreen`
(`'${widget.rubro.codigo} - ${widget.rubro.nombre}'`, `subitems_screen.dart:236`) — ambos pasan a
usar el número posicional calculado para esa obra. `rubro.codigo` deja de aparecer en cualquier
lugar de la UI, queda puramente interno.

**3. El código jerárquico de subitems ("12.10" = rubro 12, subitem 10, sembrado en
`0016_subitems.sql`) queda fuera de alcance por ahora.** Un subitem sigue mostrando su código fijo
tal cual, desacoplado de la posición visual de su rubro padre — puede leerse raro (rubro mostrado
como posición "5" pero sus subitems dicen "12.x"), pero no se resuelve en esta pieza. Anotado para
retomar más adelante si hace falta.

**4. La migración 0025 (unicidad global de `codigo`) se mantiene, con generación automática del lado
del servidor.** El índice único sigue como red de seguridad barata. Lo que cambia es quién genera
`codigo` al crear un rubro propio: deja de ser un input del usuario (Etapa D, ver §4) — pasa a
generarse automáticamente sin intervención ni chequeo de duplicado en Dart.

**Recomendación adicional, sin objeción del usuario — tratada como cerrada**: el tiebreaker de orden
default para rubros propios *sin* override en una obra pasa de "por `codigo`" (que deja de ser
visible) a **por `created_at`** — más intuitivo ("en el orden en que los creaste") que un código que
ya no significa nada para el usuario. Solo cambia la clave secundaria de desempate; oficiales siguen
yendo primero, ordenados por `rubros.orden`, igual que hoy.

---

## 4. Etapas de implementación (ninguna hecha todavía)

- **A — Base de datos**: migración `obra_rubros_orden` (este documento, §2.1-§2.3). **Aplicada y
  verificada en producción 2026-08-31** — el usuario confirmó las 3 políticas
  (`obra_rubros_orden_select`/`_insert`/`_update`) en `pg_policies`, sin errores al aplicar.
- **B — Lectura**: `RubrosTab` arma la lista ya mezclada (default + overrides, §2.4) y muestra el
  número posicional en cada fila (reemplaza a `codigo`, decisión §3.2). Sin drag todavía. **Código
  escrito 2026-08-31, pendiente de verificación del usuario en el teléfono.** Qué se tocó:
  - `RubroCatalogo` (`lib/data/models/rubro_catalogo.dart`) suma `createdAt` — desempate de orden
    default para propios sin override, reemplaza a `codigo` como criterio de sort en
    `RubrosRepository.getCatalogoCompleto` (que también perdió el ahora-muerto `_compararCodigo`).
  - `ObraRubrosOrdenRepository` nuevo (`lib/services/obra_rubros_orden_repository.dart`),
    `getOverridesDeObra(obraId)` — mapa `rubroId -> posicion`, vacío si nadie reordenó (caso normal).
  - `RubrosTab._mezclarOrden` combina el catálogo default (ya ordenado) con los overrides y
    devuelve la lista final ordenada; el número mostrado en cada fila es directamente su índice+1
    dentro de esa lista — nunca se guarda, se recalcula en cada carga.
  - Título de fila en `RubrosTab` y `AppBar` de `SubitemsScreen` (que ahora recibe
    `numeroPosicion` como parámetro nuevo) pasan de `'${rubro.codigo} - ...'` a
    `'$numeroMostrado - ...'`.
  - **No tocado a propósito**: los diálogos de confirmar/bloquear borrado en `RubrosTab` siguen
    mostrando `rubro.codigo` — no estaba en el alcance pedido para esta etapa. `codigo` sigue siendo
    un valor con sentido hoy (todavía lo tipea el usuario, Etapa D no llegó), así que no está roto,
    solo va a quedar inconsistente con el resto de la UI hasta que se toque en Etapa D.
  - Verificación pendiente: para ver un override en acción hay que insertar una fila a mano en
    `obra_rubros_orden` vía SQL Editor (drag-and-drop real es Etapa C) y confirmar que el número de
    esa fila salta a la posición esperada sin romper las demás.
  - Separado de C a propósito: aísla "leer y numerar bien" (mecánico) de "escribir al arrastrar"
    (más riesgoso).
  - **Verificado en el teléfono 2026-08-31** por el usuario: insertó a mano una fila en
    `obra_rubros_orden` mandando un rubro a `posicion=500`, y la lista se renumeró correctamente
    (correlativa, sin saltos ni repetidos) con los badges N/M siguiendo a su rubro.
- **C — Escritura (drag & drop)**: `ReorderableListView.builder` con `buildDefaultDragHandles: false`
  y un `Icons.drag_handle` dedicado como `leading`, envuelto en `ReorderableDragStartListener` — así
  el único gesto que arrastra es ese ícono, nunca toda la fila (no pisa el `onTap` que abre
  `SubitemsScreen`, el ícono de borrar ni el chip "Propio"). **Verificada en el teléfono 2026-08-31**
  — el usuario arrastró varios rubros seguidos (3 movimientos), la numeración quedó correlativa sin
  saltos ni repetidos, el orden persiste al salir y reentrar a la obra, y el descarte del aviso es
  por obra (confirmado cerrando en una obra y viéndolo seguir visible en otra). Qué se tocó:
  - `onReorderItem` (no el `onReorder` viejo, deprecado desde Flutter 3.41 en la versión instalada
    del SDK, 3.44.8) — ya entrega `newIndex` ajustado para indexar la lista sin el ítem removido, sin
    necesitar el clásico `if (oldIndex < newIndex) newIndex -= 1` a mano.
  - `RubrosTab._onReorder`: calcula la nueva posición como punto medio entre los dos vecinos reales
    en la lista sin el rubro movido (usando `_posicionesCatalogo`, no un índice recalculado desde
    cero — importante: un vecino puede ya tener un override persistido con una magnitud real
    distinta a la que le daría su posición en la lista, así que hace falta la posición real, no una
    sintética). Actualización optimista (`setState` antes del request) con revert al snapshot previo
    si el upsert falla.
  - `ObraRubrosOrdenRepository.moverRubro`: un solo `upsert` (`on_conflict=obra_id,rubro_id`) por
    arrastre — nunca reescribe el resto de la tabla.
  - Gating por rol: el ícono de arrastre no se renderiza (`leading: null`) si
    `!widget.puedeEditarComputo` — mismo criterio ya usado para el checkbox de `SubitemsScreen`, pero
    acá "no debería aparecer" en vez de "deshabilitado". `_onReorder` además tiene un `return`
    temprano si `!puedeEditarComputo`, como red de seguridad — no debería dispararse nunca en la
    práctica porque sin el handle visible no hay forma de iniciar el drag.
  - Aviso fijo pero descartable con X, por obra — decisión cerrada en conversación el 2026-08-31
    entre 4 opciones (banner fijo siempre / ícono con diálogo / una sola vez por obra / fijo
    descartable). Guardado en `SharedPreferences` con clave
    `orden_rubros_aviso_descartado_$obraId` — por dispositivo, no sincronizado entre
    dispositivos/usuarios, así que vuelve a aparecer en otra obra o en otro dispositivo que no lo
    haya descartado ahí. **`shared_preferences` pasó de dependencia transitiva a directa en
    `pubspec.yaml`** (ya estaba resuelta en el árbol de dependencias vía `supabase_flutter`/otros
    paquetes, misma versión 2.5.5, sin cambio de versión real). El aviso se muestra a cualquiera que
    mire la obra, no solo a quien puede arrastrar — la confusión de "veo otro número" no depende del
    rol.
  - **Ajuste post-verificación (mismo día)**: el texto original mezclaba dos ideas y una negación
    ("Ese orden es de esta obra: otra obra, o un colega que no reordenó acá, puede mostrar otros
    números...") — reemplazado por dos oraciones simples: "Los números se ajustan al orden que le
    des a esta obra. En otras obras la numeración puede ser distinta." Se sacó la mención al colega
    a propósito (caso raro, ensuciaba el mensaje). Además, descartar el aviso dejaba de mostrarlo
    para siempre en esa obra sin ninguna salida — se agregó un ícono `info_outline` chico
    (`_restaurarAviso`) que ocupa el lugar del banner una vez descartado y lo vuelve a mostrar al
    tocarlo; no reaparece solo (eso seguía siendo lo pedido), pero queda accesible.
- **D — Alta de rubro sin código**. Diagnóstico cerrado en conversación el 2026-08-31 (4 puntos, sin
  ambigüedades reales — el usuario invitó una recomendación en el punto 4, no un fork). **Código
  escrito el mismo día, pendiente de aplicar la migración y de verificación en el teléfono.** Qué se
  tocó:
  - `rubros.codigo` genera su valor solo, del lado de la base — `alter column codigo set default
    gen_random_uuid()::text` (migración `0027_rubros_codigo_default.sql`), mismo mecanismo que ya
    usa `rubros.id` en esta misma tabla. Elegido por sobre generarlo en Dart: cero dependencia
    nueva, colisión bajo concurrencia tan improbable como la que ya se acepta hoy para `id`, y cubre
    cualquier camino de escritura futuro, no solo `RubrosRepository.crearPersonalizado`. La migración
    0025 (índice único global) sigue exactamente igual, sin tocar — sigue de red de seguridad.
    **Hay que aplicar 0027 antes de que el cambio de Dart llegue a producción**: sin el default, el
    insert sin `codigo` rompería el `not null` de la columna.
  - `RubrosRepository.crearPersonalizado` deja de recibir `codigo` como parámetro y de mandarlo en
    el insert.
  - `RubrosTab._mostrarDialogoAltaRubro`: se sacó el `TextField` de Código, el `codigoCtrl`, el loop
    de chequeo de duplicado contra `_catalogo` (ya no aplica — nada que el usuario haya tipeado
    puede chocar) y el branch `23505` del catch de `PostgrestException` (colapsado en el mismo
    mensaje genérico que el resto de los errores). El diálogo mantiene su estructura (loading, error,
    texto explicativo) con Nombre como único campo — no se simplificó a otra cosa, seguía
    necesitando estado async y manejo de error igual. `autofocus: true` en el campo Nombre.
  - Diálogos de confirmar/bloquear borrado (anotado desde Etapa B): pasaron de mostrar
    `rubro.codigo` a mostrar el número posicional (`numeroMostrado`), enhebrado desde el
    `itemBuilder` a través de `_buildTrailingPropio` → `_onEliminarRubro` → ambos diálogos —
    incluida la segunda llamada a `_mostrarDialogoBloqueadoPorUso` dentro del catch de `23503`.
    Auditoría completa de `rubro.codigo` en `lib/`: no quedó ningún otro lugar de la UI mostrándolo
    crudo.
- **E — PDF**: filtrado a rubros con datos + renumeración correlativa sobre ese subconjunto. Solo
  diseño por ahora — no hay generador de PDF en el proyecto (`pdf`/`printing` en `pubspec.yaml` sin
  usar en ningún archivo de `lib/`, ver `CLAUDE.md`, "Dependencies not yet used in code").

---

## 5. Qué no hice en este paso

- No creé la tabla en Supabase ni escribí el archivo de migración de la Etapa A todavía — el
  siguiente paso después de este documento.
- No toqué `RubrosTab`, `SubitemsScreen` ni ningún repository — cero cambios en `lib/`.
- No diseñé el mecanismo exacto de generación automática de `codigo` (Etapa D) ni el texto del aviso
  de la Etapa C — quedan para cuando se llegue a esas etapas.
- No resolví la numeración de subitems (§3.3) — fuera de alcance por decisión explícita del usuario.
