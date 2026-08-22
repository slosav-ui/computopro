# Importador de Excel/PDF — Capa 1 (Lectura y extracción): diseño de datos

Estado: **diseño cerrado y aprobado, sin implementar todavía.** Las 7 ambigüedades quedaron
resueltas en conversación el 2026-08-22 (ver §3) — el schema de este documento ya las incorpora.
Ningún archivo de `lib/` ni tabla de Supabase fue tocado.

Contexto: pieza pausada al principio de su diseño al descubrir que el mapeo final del Importador
depende de Rubros/APU conectado a Supabase (`docs/rubros_apu_diseno_datos.md`, diseño cerrado pero
implementación bloqueada esperando el listado semilla de macrorrubros). Para no quedar bloqueados,
se separa en dos capas independientes:

- **Capa 1 — Lectura y extracción** (este documento, diseño completo): sube el archivo, la IA lo
  lee, se guarda como borrador genérico sin mapear a ningún catálogo. No depende de nada de
  `rubros_apu_diseno_datos.md` — se puede implementar ya.
- **Capa 2 — Mapeo y persistencia** (no diseñada, solo interfaz reservada — ver §2.2): confirmar a
  qué rubro/subítem del catálogo corresponde cada fila y guardar en `obra_subitems`. Bloqueada
  hasta que avance `rubros_apu_diseno_datos.md`.

---

## 1. Diagnóstico: reconfirmación (no cambió nada en el medio)

Verificado de nuevo contra el código real: `grep` sobre `lib/` por
`file_picker`/`FilePicker`/`package:excel`/`package:csv`/`Importador` sigue sin resultados, y
`pubspec.yaml` sigue sin ninguna de esas dependencias. Sigue sin existir ningún flujo de
importación de archivos en el proyecto.

---

## 2. Schema (actualizado con las 7 decisiones cerradas de §3)

### 2.1 Formato de las filas extraídas: híbrido, no jsonb puro ni columnas 100% rígidas

El formulario pre-completado que el usuario corrige necesita saber de antemano qué campos mostrar
como inputs (rubro, descripción, unidad, cantidad, precio unitario — el mismo mínimo que ya
describe `CLAUDE.md` para la plantilla de "Carga Externa de Presupuesto", Nivel 1). Un jsonb puro
obligaría a la UI a inspeccionar claves arbitrarias; un archivo real puede traer columnas que no
encajan en ese mínimo (marca, proveedor, observaciones) y no conviene perderlas.

**Propuesta**: columnas estructuradas para el mínimo conocido + una columna `jsonb` de resto —
mismo patrón que ya usa el proyecto en `libro_entradas.adjuntos` y `audit_log.detalle`.

```sql
create table importaciones (
  id uuid primary key default gen_random_uuid(),
  obra_id uuid references obras(id) on delete cascade,   -- NULLABLE, ver decisión §3.G
  usuario_id uuid not null references auth.users(id),    -- quien subió el archivo
  archivo_nombre text not null,
  archivo_storage_path text not null,                    -- obligatorio, ver decisión §3.F
  tipo_archivo text not null check (tipo_archivo in ('excel','pdf','foto')),
  hojas_seleccionadas text[],           -- elegidas por el usuario ANTES de leer, ver decisión §3.D
  moneda_default text check (moneda_default is null or moneda_default in ('ARS','USD')),  -- ver §3.E
  estado text not null default 'pendiente_revision'
    check (estado in ('pendiente_revision','confirmado','descartado')),
  pct_avance_manual numeric,           -- entrada mínima garantizada, decisión §3.A: vive acá,
  monto_certificado_manual numeric,    -- a nivel de documento completo, no en las filas
  confianza_general text check (confianza_general is null or confianza_general in ('alta','media','baja')),
  confirmado_por_usuario_id uuid references auth.users(id),
  confirmado_at timestamptz,
  created_at timestamptz not null default now()
);

create table importaciones_items (
  id uuid primary key default gen_random_uuid(),
  importacion_id uuid not null references importaciones(id) on delete cascade,
  orden int not null,                  -- preserva el orden original del archivo/planilla
  rubro_texto text,                    -- tal como lo escribió el profesional, sin normalizar
  descripcion_texto text,
  unidad_texto text,
  cantidad numeric,
  precio_unitario numeric,
  moneda text check (moneda is null or moneda in ('ARS','USD')),
    -- null = hereda importaciones.moneda_default; con valor = override puntual de esa fila
    -- (decisión §3.E — moneda por ítem, con default de archivo sobreescribible fila por fila)
  datos_originales jsonb,              -- catch-all: cualquier columna extra que la IA haya
                                        -- extraído y no encaje arriba (marca, proveedor, notas)
  -- Reservado para Capa 2, sin FK activa todavía — mismo patrón que
  -- modificaciones_obra.subitem_id/apu_privado_id (Etapa 3), que quedaron como uuid sueltos
  -- hasta que la tabla de destino existiera.
  rubro_id uuid,
  subitem_id uuid,
  created_at timestamptz not null default now()
);
```

Columnas nullable en `importaciones_items` a propósito: un campo `null` es literalmente "la IA no lo
identificó" — la UI resalta el input vacío correspondiente sin necesitar un flag de confianza
separado por campo. `confianza_general` en el header es solo para triage, no gobierna el resaltado
campo por campo.

**Regla de resolución de moneda** (decisión §3.E): `moneda_efectiva(item) = item.moneda ??
importacion.moneda_default`. Si ni el ítem ni el header tienen moneda cargada, la UI la trata igual
que cualquier otro campo no identificado — vacía y resaltada para que el usuario la complete.

### 2.2 Interfaz reservada para Capa 2 (sin diseñar, solo dejada abierta)

Cuando `rubros_apu_diseno_datos.md` esté implementado, Capa 2 necesita: (a) agregar las FKs de
`importaciones_items.rubro_id`/`subitem_id` hacia `rubros(id)`/`subitems(id)`, y (b) una
función/flujo que, para cada `importaciones_items` con `estado='confirmado'` en su `importaciones`
padre, cree las filas correspondientes en `obra_subitems` (y en `subitems` si el usuario elige
"crear nuevo"). **Punto nuevo que agrega la decisión §3.G** (obra_id nullable): cuando una
importación se confirma sin `obra_id` cargado, Capa 2 va a necesitar además resolver a qué obra se
asocia en ese momento — crear una obra nueva a partir de los datos importados, o vincularla a una
ya existente. No se resuelve en este documento (es diseño de Capa 2), solo queda anotado como
dependencia nueva que la nullability de `obra_id` le agrega a ese paso futuro.

### 2.3 RLS — mismo patrón ya establecido, con una rama nueva por `obra_id` nullable

- **Con `obra_id` cargado**: `SELECT` vía `is_obra_member(obra_id)`; `INSERT`/`UPDATE` vía
  `tiene_rol_en_obra('admin_maestro')`/`tiene_rol_en_obra('profesional')` — mismo criterio ya
  cerrado para `obra_subitems` (Constructor no edita cómputo/precios).
- **Con `obra_id` null** (decisión §3.G, ej. estimación rápida antes de crear la obra): visible y
  editable solo por `usuario_id = auth.uid()` — no hay obra de la cual derivar membresía todavía,
  así que la fila es estrictamente personal hasta que se asocie a una obra.
- Ambas funciones helper (`is_obra_member`, `tiene_rol_en_obra`) ya existen desde
  `0004_rls_etapa3.sql` — no hace falta ninguna función nueva, solo una política con dos ramas
  (`obra_id is not null and is_obra_member(obra_id)`) `or` (`obra_id is null and usuario_id =
  auth.uid()`).
- Sin política `DELETE`: descartar una importación es `estado='descartado'`, no un borrado físico
  — mismo criterio append-only que el resto del proyecto.

### 2.4 Supabase Storage — no solo la tabla

Decisión §3.F (guardar el archivo original) implica un bucket de Storage además de las tablas de
arriba, con su propia política de acceso (Storage tiene su propio sistema de RLS, separado del de
las tablas). Mismo criterio de RLS que 2.3: acceso restringido a `usuario_id` (o a los
`obra_members` de la obra, una vez asociada) — se define en detalle al escribir la migración, no en
este documento de diseño de tablas.

### 2.5 Límite mensual Free — sin tabla nueva, con una dependencia ya conocida

Decisión §3.C (límite de documentos/mes en Free, aplicado del lado servidor): no hace falta una
tabla nueva para *contar* — `importaciones` ya tiene `usuario_id` y `created_at`, así que la Edge
Function puede contar cuántas filas tiene ese usuario en el mes corriente antes de aceptar una
lectura nueva. Lo que sí falta, y no es nuevo — es la misma deuda técnica ya marcada en
`rubros_apu_diseno_datos.md` §3.G: **no existe ninguna tabla de plan/suscripción** de la cual la
Edge Function pueda leer si un usuario es Free o PRO, ni cuál es el número límite vigente. Hasta que
esa tabla exista, el límite tendría que vivir hardcodeado en la Edge Function (un solo número para
todos los Free) — funciona, pero es la misma clase de deuda ya aceptada en el otro documento, no
una nueva.

---

## 3. Definiciones cerradas — respuestas del usuario a las 7 ambigüedades

**A. Entrada mínima garantizada: vive en `importaciones` (el header), no en `importaciones_items`.**
Es un dato de nivel documento completo (% de avance general o monto total del período), no de una
fila puntual — confirmado, el schema de §2.1 ya la modela así.

**B. Mecanismo de lectura: Edge Function de Supabase del lado servidor, nunca desde el cliente
Flutter.** Dos motivos dados por el usuario: seguridad (nunca exponer la clave de un servicio de IA
en el binario de la app) y control de costo (permite aplicar el límite de documentos/mes de Free
desde el servidor, sin depender de que el cliente lo respete — ver §2.5).

**C. Límite Free/PRO: disponible para TODOS los usuarios, con límite de documentos/mes en el plan
Free** (no es una funcionalidad bloqueada para Free). El usuario citó "mismo criterio ya cerrado
para el importador de certificados externos" como precedente — **esa pieza no está documentada en
`CLAUDE.md` ni en `docs/` de este proyecto, así que la anoto tal como me la dieron, sin poder
verificar el número exacto del límite ni el mecanismo de esa otra pieza.** Ver §2.5 para lo que sí
se puede confirmar del lado de este documento (no hace falta tabla nueva para contar, sí falta la
tabla de plan/suscripción para saber el límite vigente por usuario).

**D. Selección de hoja en Excel multi-pestaña: la elige el usuario antes de leer, la IA no
adivina.** Motivo dado por el usuario: sus propios archivos reales tienen hojas con propósitos
distintos (cómputo, análisis de precios, certificados) — asumir cuál es la relevante sería
arriesgado. Cambio de schema respecto a la versión anterior de este documento: `hoja_seleccionada`
(una sola) pasó a `hojas_seleccionadas text[]`, porque un cómputo puede razonablemente necesitar
más de una hoja a la vez (ej. cómputo + análisis de precios).

**E. Moneda por ítem, con un default a nivel de archivo sobreescribible fila por fila.** Coherente
con la evidencia real ya encontrada (nombre de archivo "...con dólar a 460" sugiere cambios de
moneda de referencia a mitad de un presupuesto). Ver la regla de resolución exacta en §2.1.

**F. Sí, se guarda el archivo original además de lo extraído.** Sirve de respaldo si la lectura de
la IA se equivoca (revisar contra la fuente) y da trazabilidad, consistente con el resto del
proyecto. `archivo_storage_path` pasó de nullable a `not null` — ver también §2.4 sobre el bucket
de Storage.

**G. `obra_id` nullable: sí, puede haber una importación sin obra asociada todavía.** El usuario
referenció el "freemium de estimación rápida ya diseñado" como el caso de uso — **esa pieza tampoco
está documentada en `CLAUDE.md` ni en `docs/` de este proyecto, la anoto tal como me la dieron.**
Esto le agrega una dependencia nueva a la futura Capa 2 (resolver a qué obra se asocia una
importación al confirmarla, si no tenía una desde el arranque) — ver la nota en §2.2. La RLS
correspondiente ya está resuelta en §2.3.

---

## 4. Qué no hice en este paso

- No creé ninguna tabla en Supabase, ni escribí ningún archivo de migración.
- No implementé la Edge Function de lectura en sí — solo quedó confirmada su arquitectura (§3.B),
  falta el diseño detallado (prompt, formato de respuesta esperado, manejo de errores).
- No diseñé Capa 2 en detalle — solo se dejó la interfaz reservada (§2.2), que ahora incluye la
  dependencia nueva de resolver la obra al confirmar cuando `obra_id` llegó null.
- No definí el bucket de Storage ni sus políticas en detalle (§2.4) — solo la decisión de que el
  archivo se guarda.
- No tengo visibilidad de "el importador de certificados externos" ni del "freemium de estimación
  rápida" que el usuario citó como precedentes (§3.C, §3.G) — quedaron anotados tal como los
  describió, sin verificar contra ningún doc de este proyecto porque no existen todavía.
