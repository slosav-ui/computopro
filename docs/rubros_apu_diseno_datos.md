# Rubros / APU (Solapa 1 y 2): diseño de datos

Estado: **diseño cerrado y aprobado (revisado con el consultor), sin implementar todavía.**
Ningún archivo de `lib/` ni tabla de Supabase fue tocado para este documento. Las 8 decisiones
de diseño (2 grandes + 6 del segundo repaso) quedaron cerradas en conversación el 2026-08-22 —
ver §3. Falta solo el orden de implementación (§4, ya propuesto) y un dato de entrada que el
usuario todavía no tiene (el listado semilla de macrorrubros, ~17 valores — ver §3.D).

Contexto: pieza previa al Importador de Excel/PDF — se confirmó que Rubros/APU necesitan
persistencia real en Supabase antes de poder construir el Importador (el mapeo del Importador no
tiene a dónde aterrizar sin esto) y antes de poder cerrar el catálogo Freemium/PRO ya definido
conceptualmente. Sigue el orden ya acordado en `CLAUDE.md` ("Metodología de trabajo para las 6
solapas": Dashboard+Solapa1 → Solapa2 APU → Solapa3 → ...).

---

## 1. Diagnóstico: estado real del código (confirmación formal)

Verificado contra el código, no contra la spec histórica.

**Modelos Dart que ya existen, todos en memoria pura, sin ningún repository ni tabla de Supabase:**

- `Rubro` (`data/models/rubro.dart`): `id`, `item` (código jerárquico, ej. "1.01"), `nombre`,
  `subitems: List<Subitem>`, `macrorrubro` (string libre, default hardcodeado a
  `'2. Estructura y Albañilería'`).
- `Subitem` (`data/models/subitem.dart`): `id`, `codigo`, `descripcion`, `unidad`, `cantidad`,
  `precioUnitario`, `macrorrubro`, `esAplicable` (checkbox tildado/destildado),
  `esPersonalizado` (bool — "creado por el usuario, versión Pro"), `ultimoModificador`.
  **Mezcla en una sola clase propiedades de catálogo** (codigo/descripcion/unidad/macrorrubro)
  **con propiedades de instancia de una obra puntual** (cantidad, esAplicable,
  ultimoModificador) — es la separación que resuelve este documento.
- `SubitemBase` (`data/models/subitem_base.dart`): versión "catálogo" con `precioSugerido` y
  `esOficial` (bool: true = biblioteca precargada Free, false = creado por usuario Pro), con un
  método `aSubitemObra()` que lo convierte en un `Subitem` de instancia.
- `Insumo` (`data/models/insumo.dart`): `id`, `nombre`, `unidad`, `precio`, `tipo`
  (`'material'`/`'mano_obra'`/`'equipo'`), `proveedor`, `fechaActualizacion`,
  `porcentajeCargasSociales`.
- `InsumoApu` (`data/models/insumo_apu.dart`): `insumo` + `rendimiento` (consumo físico por
  unidad, ej. HH o m³/m²) → `costoParcial = insumo.precioConCargas * rendimiento`.
- `ComponenteApu` (`data/models/componente_apu.dart`): `materiales`/`manoDeObra`/`equipos`
  (`List<InsumoApu>` cada uno) → `costoDirectoTotal` y `calcularPrecioFinal(coeficienteK)`
  (el Coeficiente K se recibe como parámetro, no se guarda en ningún lado hoy).
- `BaseApuSeed`/`BaseInsumosSeed`: listas hardcodeadas de ejemplo (3 y 6 ítems respectivamente),
  sin relación con ninguna tabla real.

**UI:** `RubrosTab` (Solapa 1) está conectada a `PresupuestosScreen` (`presupuestos_screen.dart:164`),
pero recibe la lista de rubros como parámetro de widget y **se instancia sin pasar `rubros:`** →
arranca vacía en cada apertura de pantalla, sin persistencia entre sesiones. `AnalisisPreciosTab`
(candidato natural a Solapa 2) existe como archivo pero **no está wireada** a `PresupuestosScreen`
— la pestaña "2. APU" se arma con un método `_buildTabApu()` inline aparte, todavía mock.

**Confirmado: no existe ninguna tabla de Supabase para nada de esto.** Ninguna de las 13
migraciones aplicadas (`0001`–`0013`) crea `rubros`, `subitems`, `apu` ni un catálogo de insumos
para APU. Coincide con lo que ya dejó anotado `docs/etapa3_roles_permisos_diseno_datos.md` §3: el
único requisito que Etapa 3 le impone a la tabla de APU es una columna `creador_usuario_id`, con
la regla genérica `visible_para(viewer, registro) = (registro.creador_usuario_id == viewer.id)` —
dueño por **persona**, no por rol combinado ni por obra. Ese diseño está cerrado; este documento
lo hereda tal cual.

**Nota de naming:** el nombre de tabla `subitems` ya está reservado de hecho — `modificaciones_obra`
(Etapa 3) tiene `subitem_id uuid` sin FK porque esa tabla "todavía no existe", con la intención
explícita de agregar la FK después vía `alter table`. Este documento usa ese mismo nombre.

**Tabla `insumos` que ya existe hoy en Supabase** (dominio proveedores/corralones, RLS cerrada en
la migración 0013, 12 filas reales, relacionada con `precios`/`corralones`): **se reusa como
catálogo único de insumos también para APU** — ver decisión cerrada §3.A, cambia el diseño
original que proponía una tabla `insumos_apu` separada.

---

## 2. Schema (actualizado con las 8 decisiones cerradas de §3)

### 2.1 Rubros — catálogo con dueño nullable + sistemas constructivos como relación N:M

```sql
create table macrorrubros (
  id uuid primary key default gen_random_uuid(),
  nombre text not null unique,
  orden int not null default 0     -- para mantener el orden del catálogo semilla en la UI
);
-- Seed pendiente: falta el listado real (~17 valores) — ver §3.D. No inventar valores acá.

create table sistemas_constructivos (
  id uuid primary key default gen_random_uuid(),
  nombre text not null unique      -- ej. "Mampostería Tradicional", "Steel Frame", "Wood Frame",
                                    -- "Estructura Metálica" — candidatos tomados de CLAUDE.md
                                    -- §"Solapa 1", a confirmar junto con el seed de macrorrubros
);

create table rubros (
  id uuid primary key default gen_random_uuid(),
  codigo text not null,                     -- ej. "1.01", "2.00" (Rubro.item hoy)
  nombre text not null,
  macrorrubro_id uuid not null references macrorrubros(id),
  creador_usuario_id uuid references auth.users(id),  -- null = catálogo oficial
  created_at timestamptz not null default now()
);

create table rubro_sistema_constructivo (
  rubro_id uuid not null references rubros(id) on delete cascade,
  sistema_constructivo_id uuid not null references sistemas_constructivos(id) on delete cascade,
  primary key (rubro_id, sistema_constructivo_id)
);
-- Sin fila para un rubro = universal (aplica siempre, ej. "Instalaciones").
-- Con filas = aplica solo a esos sistemas. Un rubro puede tener varias (ej. "Estructura"
-- aplica a Tradicional + Steel Frame + Metálica a la vez) — decisión cerrada §3.H.
```

### 2.2 Subítems — mismo patrón dueño-nullable, ligado a un rubro

```sql
create table subitems (
  id uuid primary key default gen_random_uuid(),
  rubro_id uuid not null references rubros(id) on delete cascade,
  codigo text not null,
  descripcion text not null,
  unidad text not null,
  creador_usuario_id uuid references auth.users(id),  -- null = catálogo oficial
  created_at timestamptz not null default now()
);
```

Deliberadamente sin `precioSugerido`/`precioUnitario` acá — el precio de un subítem es el
resultado de su `apu_composicion` aplicada sobre los insumos vigentes, no un dato propio del
catálogo (evita una segunda fuente de verdad para el precio).

### 2.3 Obra ↔ Subítems elegidos (el cómputo métrico real de una obra)

```sql
create table obra_subitems (
  id uuid primary key default gen_random_uuid(),
  obra_id uuid not null references obras(id) on delete cascade,
  subitem_id uuid not null references subitems(id),
  sector text,                              -- opcional, distingue repeticiones del mismo subítem
                                             -- (ej. "Planta Baja", "Dormitorio 2") — decisión §3.C
  cantidad numeric not null default 0,
  es_aplicable boolean not null default true,   -- tildado/destildado sin perder la cantidad cargada
  agregado_por_usuario_id uuid not null references auth.users(id),
  ultima_modificacion_usuario_id uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
  -- sin unique(obra_id, subitem_id): un mismo subítem puede repetirse en sectores
  -- distintos de la misma obra — decisión cerrada §3.C.
);
```

Sin columna de precio: mientras la obra está en etapa de presupuesto/planificación (sin certificar
todavía), el precio se calcula en vivo desde `apu_composiciones` + `insumos` vigentes. Al emitir un
certificado que incluye este trabajo, el monto queda congelado — decisión cerrada §3.B, ver ahí el
detalle de por qué no hace falta un mecanismo nuevo.

### 2.4 Composición APU (materiales/mano de obra/equipos por subítem)

```sql
create table apu_composiciones (
  id uuid primary key default gen_random_uuid(),
  subitem_id uuid not null references subitems(id) on delete cascade,
  creador_usuario_id uuid references auth.users(id),  -- null = receta oficial
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (subitem_id, creador_usuario_id)   -- índice único parcial, null tratado como valor propio
);

create table apu_composicion_items (
  id uuid primary key default gen_random_uuid(),
  apu_composicion_id uuid not null references apu_composiciones(id) on delete cascade,
  tipo_componente text not null check (tipo_componente in ('material','mano_obra','equipo')),
  insumo_id uuid not null references insumos(id),   -- tabla ya existente, reusada — decisión §3.A
  rendimiento numeric not null,
  created_at timestamptz not null default now()
);
```

`coeficiente_k` deliberadamente **no vive acá** — `CLAUDE.md` ya documenta que Gastos
Generales/Imprevistos/Beneficio (y el Coeficiente K) se definen una vez a nivel obra y se heredan a
todas las planillas de APU, con override puntual por ítem como excepción Pro. Corresponde a Solapa 3
("Materiales y Mano de Obra... el motor de actualización de precios"), fuera de alcance de esta
pieza — queda señalado, no resuelto acá.

### 2.5 Tabla `insumos` reusada — diagnóstico en vivo confirmado (Paso 0, 2026-08-22)

**Decisión cerrada (§3.A): no se crea una tabla nueva, `apu_composicion_items.insumo_id` referencia
la `insumos` ya existente.** Paso 0 del plan de implementación (§4) ejecutado: el usuario confirmó
en vivo, en el Table Editor de Supabase (no solo por el comentario de la migración 0013), que las
columnas hoy son exactamente `id`, `created_at`, `nombre`, `unidad`, `categoria` — sin cambios
respecto a lo documentado en la migración. Dos hallazgos concretos de esa verificación, que cambian
lo que hace falta agregar:

- **`categoria` hoy solo tiene valores de MATERIAL** (áridos, cementos, hierros) — nada de mano de
  obra ni equipos. Confirma que la columna no sirve tal cual para el `tipo_componente`
  (`material`/`mano_obra`/`equipo`) que necesita `apu_composicion_items` — hace falta ampliar los
  valores de `categoria` para que cubra los tres casos, o agregar una columna `tipo` separada y más
  genérica (`material`/`mano_obra`/`equipo`) dejando `categoria` como la subclasificación fina que
  ya tiene hoy (áridos/cementos/hierros/etc. dentro de `material`). Preferible la segunda opción —
  evita mezclar un nivel de clasificación grueso (tipo de recurso) con uno fino (rubro del
  material) en la misma columna — pero queda para decidir al escribir la migración C.
- **El nombre del insumo mete la unidad de compra como texto libre** — ejemplo real encontrado:
  `"Cemento Holcim x 50kg"`, en vez de tener "Cemento Holcim" en `nombre` y "50kg" en un campo
  estructurado. Esto es evidencia concreta y no hipotética del problema que ya señalaba
  `docs/monetizacion.md` (ítem 5, "unidad de compra vs. unidad de uso con factor de conversión"):
  con el dato metido como texto dentro de `nombre`, el sistema no puede convertir cantidades — un
  rendimiento de APU necesita "kg de cemento por m²" (unidad de uso), mientras el corralón vende
  "bolsa de 50kg" (unidad de compra), y hoy no hay forma de que la app haga esa cuenta sola.

**Columnas a agregar en la migración C** (`alter table insumos add column ...`, no se rediseña
`insumos` desde cero, se extiende):

- `tipo` (`material`/`mano_obra`/`equipo`) — nueva, separada de `categoria`.
- `unidad_compra` / `factor_conversion` (cuántas `unidad` — la de uso — entran en una
  `unidad_compra`) — nuevas, resuelven el caso "Cemento Holcim x 50kg" de forma estructurada.
  Requiere además un paso de **limpieza de datos** sobre las 12 filas existentes (separar manualmente
  lo que hoy está mezclado en `nombre`, no algo que una migración de schema resuelva sola).
- `porcentaje_cargas_sociales` — específico de mano de obra (escala UOCRA), no tenía sentido antes
  en un insumo de corralón.
- `creador_usuario_id` nullable — para que un PRO pueda agregar su propio insumo custom (ej. una
  marca específica) sin tocar el catálogo oficial, mismo patrón que el resto de esta pieza.

La RLS ya cerrada de `insumos` en la migración 0013 (`SELECT` abierto a autenticados, sin política
de escritura) sigue sirviendo para las filas oficiales; las filas con `creador_usuario_id` no nulo
necesitan una política adicional de dueño (mismo patrón que el resto de esta pieza).

### 2.6 RLS — reuso de lo ya construido, sin helpers nuevos

- `is_obra_member(obra_id)` (ya existe desde `0004_rls_etapa3.sql`) cubre el `SELECT` de
  `obra_subitems`.
- `INSERT`/`UPDATE` de `obra_subitems` restringido a `admin_maestro`/`profesional` (los únicos con
  "edición total de cómputos" según la matriz de permisos ya cerrada) vía `tiene_rol_en_obra`.
- `rubros`/`subitems`/`apu_composiciones`/`apu_composicion_items`: filas oficiales
  (`creador_usuario_id is null`) con `SELECT` abierto a cualquier autenticado, sin política de
  escritura (alta/edición del catálogo oficial sigue siendo manual vía SQL Editor, mismo patrón que
  `insumos`). Filas personalizadas: visibles y editables por su dueño, **más** una política de
  lectura adicional para colaboradores con concesión — ver regla exacta abajo (decisión §3.E, la
  pieza más delicada de la RLS de este documento):

```sql
-- Ejemplo de política de SELECT para subitems/apu_composiciones personalizados:
-- visible si soy el dueño, O si existe una obra donde este ítem está tildado
-- (obra_subitems) y yo soy obra_member de esa obra con puede_ver_apu_ajena = true.
creador_usuario_id = auth.uid()
or exists (
  select 1 from obra_subitems os
  join obra_members om on om.obra_id = os.obra_id
  where os.subitem_id = subitems.id
    and om.usuario_id = auth.uid()
    and om.activo
    and om.puede_ver_apu_ajena
)
```

Esto resuelve la tensión que motivó la decisión §3.E: la personalización vive a nivel de persona
(reusable en todas sus obras), pero la visibilidad de un tercero sigue acotada exactamente a lo que
`puede_ver_apu_ajena` ya permite por obra en Etapa 3 — un colaborador con esa concesión en la Obra A
ve la personalización del dueño **únicamente en lo que está tildado en la Obra A**, no la biblioteca
completa del dueño en todas sus obras.

### 2.7 FKs pendientes que este diseño destraba

Migración chica aparte, al final de esta pieza: completar la FK que quedó pendiente desde Etapa 3 —
`modificaciones_obra.subitem_id → subitems(id)` y `modificaciones_obra.apu_privado_id →
apu_composiciones(id)`. Ya anticipado en `docs/etapa3_roles_permisos_diseno_datos.md` §4.

---

## 3. Definiciones cerradas — respuestas del usuario a las 8 preguntas abiertas

**A. Catálogo de insumos de APU: se reusa la tabla `insumos` ya existente (proveedores/precios, 12
filas reales), no se crea `insumos_apu`.** Motivo: si el APU usa "cemento", tiene que ser el mismo
insumo que después se puede cotizar contra corralones reales vía
`calcular_precio_promedio_insumo()` — dos tablas separadas hubiesen roto ese cruce. Ver §2.5 para
los cambios de columnas que probablemente hacen falta.

**B. Precio del subítem: vivo mientras la obra está en presupuesto/planificación; se congela al
emitir un certificado que incluye ese trabajo.** Mismo principio de "no retroactivo" que ya rige el
proyecto (CAC, redeterminación) — no se inventa un mecanismo de congelamiento aparte, se reusa la
lógica que `certificados`/`emitir_certificado()` ya tienen para anticipo/fondo de reparo. La
extensión concreta de `emitir_certificado()` para que también snapshotee el precio de los
`obra_subitems` incluidos queda para cuando se conecte el cómputo real a Gestión de Obra — fuera de
alcance de esta pieza, solo señalado para no reinventar el mecanismo más adelante.

**C. Un subítem puede repetirse en la misma obra.** `obra_subitems` permite varias filas del mismo
`subitem_id` por obra, con un campo opcional `sector` (texto libre) para distinguirlas — ej. mismo
"Contrapiso de hormigón" en dos sectores con cantidades distintas.

**D. `macrorrubro` pasa a ser una lista fija** (tabla `macrorrubros`, ~17 valores del catálogo
semilla ya armado), no texto libre. **Bloqueante real**: el listado concreto de esos ~17 valores
todavía no está en este documento — no lo tengo, no lo invento. Necesario antes de escribir la
migración que crea y siembra `macrorrubros`.

**E. La personalización PRO de un subítem/APU es de la persona, no de la obra** — mismo criterio
que Etapa 3 ya cerró para el ownership del APU ("por persona, no por rol combinado"). Un
profesional que personaliza un subítem lo reusa en todas sus obras sin recrearlo. La visibilidad de
un tercero con `puede_ver_apu_ajena` sigue acotada por obra, tal como ya estaba diseñado — ver la
política de RLS exacta en §2.6.

**F. Excel de 2 pestañas: pendiente, sin nada que resolver todavía.** Cuando esté listo, mapear
columna→campo contra el archivo real antes de escribir el script/migración de carga masiva —
probablemente una pestaña mapea a `rubros`+`subitems` y la otra a `apu_composicion_items`+`insumos`,
pero se confirma contra el archivo, no se asume la forma de antemano.

**G. Free/PRO en la escritura de `obra_subitems`/personalización: queda en capa de app por ahora —
marcado explícitamente como DEUDA TÉCNICA REAL, no como una convención cerrada.** A diferencia de
otras deudas técnicas ya aceptadas en el proyecto (ej. la de `ajuste_contrato`, ver
`docs/modelos_certificacion_diseno_datos.md`), esta es control de **monetización** — plata que la
app debería estar cobrando, no solo una convención administrativa interna entre el único desarrollador
y su propia base. Hoy no existe ninguna tabla de plan/suscripción en el proyecto de la cual colgar
ese control a nivel de RLS. **Queda pendiente hasta que se construya el sistema de planes/pagos** —
revisar esta pieza en ese momento para agregar el chequeo a nivel de base, no confiar en que la app
sola lo siga cumpliendo para siempre.

**H. `sistema_constructivo`: relación muchos-a-muchos (`rubro_sistema_constructivo`), no columna
única.** Un rubro como "Estructura" puede aplicar a varios sistemas constructivos a la vez
(Tradicional + Steel Frame + Metálica), coincide con el catálogo semilla ya armado. Ver §2.1.

---

## 4. Orden de implementación propuesto (sin escribir migraciones todavía)

1. **Paso 0 (diagnóstico, no migración) — CONFIRMADO en vivo, 2026-08-22** (ver detalle en §2.5):
   `insumos` tiene `id`/`created_at`/`nombre`/`unidad`/`categoria`, `categoria` solo cubre material,
   y el nombre mezcla la unidad de compra como texto libre (ej. "Cemento Holcim x 50kg"). Define
   qué agrega la migración C: `tipo`, `unidad_compra`, `factor_conversion`,
   `porcentaje_cargas_sociales`, `creador_usuario_id`, más una limpieza manual de datos sobre las
   12 filas existentes.
2. **Migración A**: `macrorrubros` + `sistemas_constructivos` (lookups) + `rubros` +
   `rubro_sistema_constructivo`, con RLS incluida desde el arranque (mismo criterio ya usado en
   `hitos_certificacion`/`certificados`, mejor que separar una migración de RLS al final).
   **Bloqueada hasta tener el listado semilla de macrorrubros (§3.D).**
3. **Migración B**: `subitems` (depende de `rubros`), RLS incluida.
4. **Migración C**: `alter table insumos` (agrega las columnas que falten según el paso 0) + ajuste
   de RLS para permitir personalización PRO (`creador_usuario_id` no nulo).
5. **Migración D**: `apu_composiciones` + `apu_composicion_items` (depende de `subitems` +
   `insumos`), con la política de RLS de §2.6 (la más delicada de toda la pieza — conviene
   verificarla con datos reales antes de dar el paso por cerrado).
6. **Migración E**: `obra_subitems` (depende de `subitems` + `obras`), RLS incluida.
7. **Migración F (cierre)**: completar las FKs pendientes de `modificaciones_obra` (`subitem_id`,
   `apu_privado_id`) ahora que las tablas de destino existen — ver §2.7.

Cada migración se aplica y confirma una por una, mismo mecanismo de siempre (Claude escribe el
archivo, el usuario lo corre a mano en el SQL Editor y confirma en el dashboard antes de seguir).

---

## 5. Qué no hice en este paso

- No creé ninguna tabla en Supabase, ni escribí ningún archivo de migración.
- No toqué `rubros_tab.dart`, `analisis_precios_tab.dart` ni ningún modelo Dart existente.
- No introspecté el schema real de `insumos` en producción (paso 0 de §4, pendiente).
- No definí dónde vive el Coeficiente K / Gastos Generales / Beneficio / Impuestos a nivel obra —
  corresponde a Solapa 3, según el orden de trabajo ya acordado.
- No tengo el listado semilla de macrorrubros (~17 valores) — bloqueante real para la Migración A.
