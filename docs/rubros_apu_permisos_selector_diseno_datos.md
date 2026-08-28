# Rubros / APU (Solapa 1 y 2): permisos Free/PRO, selector y coeficientes — parte 2

Estado: **aplicado en producción, 2026-08-28 — las 8 migraciones (`supabase/migrations/0014` a
`0021`) corridas y confirmadas por el usuario, de punta a punta.** Extiende
`docs/rubros_apu_diseno_datos.md` (diseño fundacional, cerrado 2026-08-22) con las reglas de
negocio de `docs/computopro_rubros_apu_spec.md`, verificadas contra el archivo real
`docs/seed/PLANILLA_BASE_2_0_v3_CORREGIDA.ods`. Resumen completo de cada migración aplicada en
`CLAUDE.md`, sección homónima — ese archivo es el índice vivo de estado de producción, este
documento queda como el registro del diseño y las decisiones que lo motivaron.

**Dos cosas quedan explícitamente fuera de esta pieza, no son un olvido**: (1) la carga de
composiciones reales de APU (materiales/rendimientos) — tarea de curación del usuario, requiere
expandir el catálogo de `insumos` primero; (2) la conexión a Dart/UI — ningún archivo de `lib/`
fue tocado, `RubrosTab`/`AnalisisPreciosTab` siguen en memoria pura tal como se diagnosticó al
principio.

El catálogo de `macrorrubros` (~17 valores) del diseño fundacional queda **descartado y
reemplazado**, no complementado, por el listado real de 20 rubros de la planilla (19 + el Rubro
20 "VARIOS", ver §2.1).

---

## 1. Las 9 definiciones — todas cerradas

**1-6 (cerradas en la revisión anterior, sin cambios):**
1. Coeficientes (GG/Imprevistos/EPP/Beneficio/Costo financiero): default único de obra
   (`obra_presupuesto_config`), sin override por partida en esta pieza.
2. "Gestión de materiales de terceros" (4% default): valor único de obra, misma tabla.
3. Impuestos: `obra_impuestos` con `tipo` restringido (`iva`/`iibb`/`tasas_municipales`/`otro`), no
   texto libre.
4. `rubros.usa_apu`: flag genérico, no hardcodeado a Rubro 1 (confirmado necesario — ver
   definición 8, aplica a 4 rubros).
5. Fila "OTRO": reusa `obra_subitems` (`subitem_id` nullable + `descripcion_libre`).
6. Free/PRO: tabla nueva mínima `perfiles` (`usuario_id` → `auth.users`, `es_pro boolean`).

**7. Rubro 20 existe y se llama "VARIOS", no "Limpieza de Obra".** Confirmado con captura real de
la fila 173 del `.ods` — el nombre correcto reemplaza la etiqueta provisoria que yo había puesto
al no encontrar el título en la hoja. Subitems: `20.1` Limpieza Periódica de Obra (GL), `20.2`
Limpieza Final de Obra (GL), `20.3` OTRO (mismo patrón genérico que la fila OTRO de cualquier
rubro — no necesita tratamiento especial más allá del ya diseñado en `obra_subitems`).

**8. `usa_apu = false` son 4 rubros, no 1 — y con dos comportamientos distintos entre sí.**
- **Rubro 1 (Tareas Preliminares) y Rubro 20 (Varios):** precio **unitario** editable directo —
  mismo comportamiento ya diseñado para Rubro 1 (cantidad × precio unitario = total del subítem).
- **Rubro 18 (Instalaciones) y Rubro 19 (Carpinterías):** precio **global** editable directo — el
  usuario carga un monto único para toda la partida, no un precio por unidad de medida técnica
  (coherente con que sus subitems ya usan unidad "GL" y con que estos rubros se cotizan
  típicamente por trabajo completo, no por m²/m³/ml).

  Se agrega un campo a `rubros` para distinguir el sub-caso — ver §2.1.

**9. Equipos se integra al itemizado igual que Mano de obra y Materiales.** El check constraint de
`apu_composicion_items.tipo_componente` (`'material' | 'mano_obra' | 'equipo'`) **ya estaba
preparado para esto desde el diseño fundacional** — no hace falta ningún cambio de schema, la
tabla ya admite filas de tipo `equipo` con `insumo_id` + `rendimiento`, mismo mecanismo que
material/mano de obra. Lo único que cambia es que deja de estar "sin uso confirmado" (como había
quedado marcado en la revisión anterior de este documento) y pasa a ser un tipo de componente
activo. **Sobre los datos concretos de Equipos que cargaste: ver la salvedad de §4 antes de dar
esto por aplicable a la migración semilla** — no encontré esas filas al releer el archivo, y la
instrucción explícita fue no inventar ni completar nada por mi cuenta.

---

## 2. Schema actualizado

### 2.1 `rubros` — 20 rubros reales, con el nuevo campo `tipo_precio_manual`

```sql
create table rubros (
  id uuid primary key default gen_random_uuid(),
  codigo text not null,                     -- "1".."20", o libre para custom PRO
  nombre text not null,
  orden int not null default 0,
  usa_apu boolean not null default true,    -- false = precio 100% manual, sin arrastre de APU
  tipo_precio_manual text                    -- NUEVO: distingue el sub-caso cuando usa_apu = false
    check (tipo_precio_manual in ('unitario', 'global')),
  creador_usuario_id uuid references auth.users(id),  -- null = catálogo oficial
  created_at timestamptz not null default now(),
  constraint rubros_tipo_precio_manual_coherente check (
    (usa_apu = true and tipo_precio_manual is null)
    or (usa_apu = false and tipo_precio_manual is not null)
  )
);
```

`tipo_precio_manual = 'unitario'`: la UI muestra cantidad + precio unitario, igual que un subítem
normal, pero el precio se tipea a mano en vez de arrastrarse de APU (Rubros 1 y 20).
`tipo_precio_manual = 'global'`: la UI muestra un único campo de monto para toda la partida, sin
desglose por unidad de medida técnica (Rubros 18 y 19). El `check` garantiza que todo rubro con
`usa_apu = false` tenga definido cuál de los dos es, y que ningún rubro con `usa_apu = true` lo
tenga seteado por error.

Se sigue eliminando del diseño fundacional (sin cambios respecto a la revisión anterior):
`macrorrubros`, `sistemas_constructivos`, `rubro_sistema_constructivo` — ver esa revisión para el
razonamiento (rubros 4-7 ya son de primer nivel, no hace falta relación N:M).

Seed real de los 20 rubros (código — nombre — `usa_apu` — `tipo_precio_manual`):

```
1  TAREAS PRELIMINARES              usa_apu=false  tipo_precio_manual=unitario
2  MOVIMIENTOS DE SUELOS            usa_apu=true
3  FUNDACIONES                      usa_apu=true
4  ESTRUCTURAS DE HORMIGON ARMADO   usa_apu=true
5  ESTRUCTURAS DE STEEL FRAME       usa_apu=true
6  ESTRUCTURAS DE BALLOON FRAME     usa_apu=true
7  ESTRUCTURAS METALICAS LIVIANAS   usa_apu=true
8  MAMPOSTERIAS                     usa_apu=true
9  CAPAS AISLADORAS                 usa_apu=true
10 REVOQUES Y YESERIA               usa_apu=true
11 CONTRAPISOS Y CARPETAS           usa_apu=true
12 PISOS Y ZOCALOS                  usa_apu=true
13 REVESTIMIENTOS HUMEDOS           usa_apu=true
14 REVESTIMIENTOS SECOS             usa_apu=true
15 CUBIERTAS                        usa_apu=true
16 CIELORRASOS                      usa_apu=true
17 PINTURAS                         usa_apu=true
18 INSTALACIONES                    usa_apu=false  tipo_precio_manual=global
19 CARPINTERIAS                     usa_apu=false  tipo_precio_manual=global
20 VARIOS                           usa_apu=false  tipo_precio_manual=unitario
```

### 2.2 `obra_impuestos` — sin cambios respecto a la revisión anterior

Ver esa revisión — `tipo` restringido (`iva`/`iibb`/`tasas_municipales`/`otro`), sembrada con 4
filas default al crear la obra.

### 2.3 `obra_subitems` — sin cambios estructurales

Igual que la revisión anterior: `subitem_id` nullable + `rubro_id` explícito + `descripcion_libre`
(fila OTRO) + `precio_unitario_manual`. El campo `precio_unitario_manual` sirve **para los dos
sub-casos** de `tipo_precio_manual` sin necesitar columnas separadas — en `'global'` simplemente
representa el monto total de la partida (con `cantidad` normalmente en 1, unidad "GL"), en
`'unitario'` representa el precio por unidad de medida técnica igual que cualquier subítem.

### 2.4 `apu_composiciones` / `apu_composicion_items` — confirmado, Equipos incluido

Sin cambios de schema — `tipo_componente check (in ('material','mano_obra','equipo'))` ya
contemplaba `'equipo'` desde el diseño fundacional. Se confirma que sí se usa, con el mismo
mecanismo insumo + rendimiento que material/mano de obra. La columna `insumos.tipo` (a agregar en
la migración C, ya prevista) también necesita el valor `'equipo'` — sin cambios respecto a lo ya
documentado.

### 2.5 `obra_presupuesto_config` — sin cambios respecto a la revisión anterior

### 2.6 `perfiles` — implementada en `supabase/migrations/0014_perfiles.sql`

Mismo schema de la revisión anterior (`usuario_id` → `auth.users`, `es_pro boolean default false`),
con una corrección de seguridad al llevarlo a migración: RLS queda **solo `SELECT`** para el
usuario, sin `UPDATE` ni `INSERT`. La versión anterior de este documento proponía
`UPDATE using(usuario_id = auth.uid())` "mismo patrón que corralones" — pero con esa política
cualquier usuario Free podría ejecutar `update perfiles set es_pro = true where usuario_id =
auth.uid()` llamando directo a la API de Supabase (sin pasar por la app) y ponerse PRO gratis.
Como `perfiles` no tiene hoy ninguna otra columna que un usuario deba poder editar por su cuenta,
queda de solo lectura: la fila se crea sola (trigger `AFTER INSERT` sobre `auth.users` + backfill
para cuentas ya existentes) y `es_pro` solo cambia a mano vía SQL Editor (`service_role`) hasta que
exista un sistema de pagos real que lo dispare de forma controlada.

### 2.7 RLS — sin cambios de criterio para el resto de las tablas de esta pieza

---

## 3. Ambigüedades

Ninguna pendiente de decisión de negocio — las 9 de §1 están cerradas. Queda una sola cosa a
verificar antes de tratar el diseño como aplicable a la migración semilla, que no es una
ambigüedad de diseño sino un chequeo de datos — ver §4.

---

## 4. Salvedad importante: no encontré las filas de Equipos al releer el archivo

Volví a leer `docs/seed/PLANILLA_BASE_2_0_v3_CORREGIDA.ods` completo (zip + `content.xml`, todas
las filas de las 3 hojas, no solo una muestra) buscando específicamente filas de tipo "Equipo"
—igual que las 2375 filas `Material` y 625 filas `Mano de obra` que sí encontré con nombre/unidad/
rendimiento. **No encontré ninguna fila etiquetada como Equipo en ninguna de las 125 partidas de
la hoja APU** — el patrón sigue siendo el mismo que en mi primera lectura: después de
`SUBTOTAL MATERIAL (B)` va directo a `3 EQUIPOS TOTAL (C)` como línea de total, sin filas de
detalle arriba. Tampoco cambió el conteo de filas de la hoja hasta este momento (5144 vs. 5145 de
la primera lectura, diferencia mínima de parsing, no de contenido nuevo).

**No estoy dando por hecho que el dato no existe** — el archivo tenía (y probablemente sigue
teniendo) un lockfile de LibreOffice puesto, señal de que lo tenías/tenés abierto en vivo, así que
es totalmente posible que hayas cargado los datos de Equipos en tu vista de LibreOffice y no se
hayan guardado a disco todavía (`Ctrl+S` / Guardar) antes de que yo volviera a leer el archivo.
**Antes de escribir la migración semilla, necesito que confirmes que guardaste el
archivo con esos datos y me avises para releerlo de nuevo** — no voy a completar ni inventar
ningún valor de Equipos por mi cuenta, tal como pediste, así que si no logro leerlos del archivo
real la migración semilla simplemente los deja vacíos/editables para que los cargues vos después,
en vez de asumir algo.

---

## 5. ¿Está el documento listo para pasar a implementación?

**El diseño de tablas está cerrado y listo** — las 9 definiciones de negocio no tienen ningún
punto abierto, y el schema de §2 no depende de ningún dato que todavía falte para *definirse*
(a diferencia del bloqueante de macrorrubros que sí frenaba todo antes). Se puede escribir la
primera migración (`rubros`, seed de los 20) sin esperar nada más.

**Lo único que sugiero resolver antes de la migración que siembra `apu_composiciones`/
`apu_composicion_items`** es la salvedad de §4 — no porque el schema dependa de eso (ya está
cerrado, admite `equipo` sin cambios), sino porque **la migración semilla sí depende de qué datos
reales terminemos leyendo del archivo**, y prefiero confirmar que estoy leyendo la versión
guardada más reciente antes de generar el `insert` de composiciones, para no tener que rehacerlo.

Orden sugerido para arrancar (no bloqueado, se puede empezar ya): (1) `perfiles` (no depende de
nada de esta pieza); (2) `rubros`, sembrada con los 20 reales de §2.1; (3) `subitems`; (4)
`alter table insumos` (migración C ya prevista, agrega `tipo`/`unidad_compra`/
`porcentaje_cargas_sociales`/`creador_usuario_id`); (5) `apu_composiciones` + `apu_composicion_items`
— acá conviene ya tener confirmada la salvedad de §4; (6) `obra_subitems`; (7)
`obra_presupuesto_config` + `obra_impuestos`; (8) cierre de FKs pendientes de
`modificaciones_obra` (Etapa 3).

## 6. Qué no hice en este paso

- No creé ninguna tabla en Supabase, ni escribí ningún archivo de migración.
- No toqué ningún archivo de `lib/`.
- No completé ni inventé ningún dato de Equipos — ver §4.
- No volví a dumpear el archivo completo en este documento — los dumps de verificación quedaron en
  el scratchpad de la sesión.
