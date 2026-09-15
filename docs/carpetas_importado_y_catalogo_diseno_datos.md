# Dos carpetas: lo importado y el catálogo

Diseño de datos. Decisiones cerradas por Seba el 2026-09-15. **Sin implementar** — este doc es el
paso previo, y el orden de construcción está en §7.

---

## 1. El hallazgo que origina la pieza

Salió de cargar la obra real (Galpón Mix) desde su PDF, y tiene dos mitades.

**La primera, de producto.** El bloque 2 del PDF se llama *"ESTRUCTURAS, EXCAVACIONES, HORMIGÓN
FUNDACIONES, PLATEA CON VIGAS"* y contiene partidas de **tres rubros distintos** del catálogo
(1 Tareas Preliminares, 3 Fundaciones, 7 Estructuras Metálicas). El título mismo lo anuncia.

Al mapear las 24 partidas contra el catálogo, 12 no tuvieron ningún subítem oficial que las
describiera: el panel isotérmico no es la chapa de 14.3, el tabique de steel frame no es un
revestimiento de una cara, la placa verde de locales húmedos no existe.

> **El rubro del usuario no es una unidad que se mapea.** Es una agrupación conveniente del que
> cotizó, y cada uno agrupa como quiere. El PDF agrupa como le conviene al que cotizó; el catálogo
> tiene su propia estructura. (Seba, 2026-09-15)

Y eso no es un problema del script de carga: **es el problema central del importador.** Cualquier
usuario que importe su planilla va a tener lo mismo, con otros nombres y otros cortes.

**La segunda, estructural, y es la que explica los duplicados de raíz.**

`rubros` y `subitems` **no tienen `obra_id`**. Pertenecen al *usuario*
(`creador_usuario_id`), no a la obra. `RubrosRepository.getCatalogoCompleto(usuarioId)`
(`rubros_repository.dart:35`) devuelve los oficiales más **todos** los del usuario, sin filtrar por
obra, y lo mismo hace `SubitemsRepository.getSubitemsDeRubro`.

O sea que hoy **no existe ningún lugar donde una partida pueda vivir que signifique "esta obra"**.
Lo que se importe entra al catálogo personal y aparece en el Cómputo de todas las obras de ese
usuario.

Eso reencuadra el bug de las partidas triplicadas que Seba vio en el teléfono. El script de carga
tenía dos defectos reales (un `do $$` anidado con el mismo delimitador que rompía el parseo, y una
limpieza que buscaba por prefijo de código), pero el fondo es otro:

> No era que la limpieza fallara. Era que hacía falta una limpieza. **Ninguna limpieza iba a
> resolver esto**, porque el dato estaba guardado en el lugar equivocado.

---

## 2. La idea

**El presupuesto importado entra tal cual, sin mapear.** Con sus rubros, sus descripciones y su
numeración original, exactamente como vienen del Excel o el PDF. Textual: *"que se copie literal
como viene del Excel"*.

**Y el catálogo de la app queda intacto al lado.**

En la solapa Cómputo hay **dos carpetas**: los rubros importados por un lado, los del catálogo por
otro. Se alterna con un toque y no se mezclan. Al crear un rubro o una partida nueva, se elige en
cuál va.

**Por qué resuelve el problema de raíz:** si no hay que mapear, no hay nada que salga mal. Se acaban
los rubros inventados, las partidas en el lugar equivocado y la numeración que no respeta nada. Las
12 partidas que no tenían equivalente dejan de ser un problema a resolver: entran como están.

**Lo que se pierde, y conviene decirlo:** las partidas importadas no tienen APU ni composición, así
que no aparecen en la solapa APU ni en el consolidado de insumos de Mat y MO. **Para certificar
alcanza; para recalcular el presupuesto, no.** Está bien: el importado sirve para traer una obra y
gestionarla; el que quiera trabajar con APU carga desde el catálogo. La lógica de las solapas queda
intacta — las APU siguen acompañando a los rubros y subítems del catálogo como hasta ahora.

---

## 3. Las cuatro decisiones

Cerradas el 2026-09-15.

**3.1 — Un rubro importado se puede adoptar al catálogo.** *"Si el usuario ve que le sirve siempre,
tiene que poder quedárselo: importás, trabajás, y lo bueno se queda."* Por lo tanto **`obra_id` es
editable, no inmutable**. Consecuencias en §6.1.

**3.2 — Las dos numeraciones conviven.** La carpeta importada mantiene su numeración original, que
es el sentido de "tal cual viene". **La unicidad de código va por obra y por carpeta, no global.**
De paso arregla un bug multi-inquilino existente: hoy dos PRO no pueden tener cada uno su rubro
"21". Detalle en §4.3.

**3.3 — Reimportar reemplaza, avisando.** *"Importar dos veces la misma obra es corregir, no
acumular."* Y el aviso tiene que decir qué va a pasar con lo que ya está tildado y con el avance
cargado, si lo hay. Es la parte con más filo: §6.2.

**3.4 — El cliente invitado ve la carpeta importada.** *"Es la estructura de la obra, no el APU de
nadie. Y sin eso ve un cómputo vacío, que es peor."* La RLS pasa a `is_obra_member`. Detalle en §4.4.

---

## 4. Diseño de datos

### 4.1 `obra_id` en `rubros` y en `subitems`

```sql
alter table rubros   add column obra_id uuid references obras(id) on delete cascade;
alter table subitems add column obra_id uuid references obras(id) on delete cascade;
```

Semántica, con `creador_usuario_id` que ya existe:

| `obra_id` | `creador_usuario_id` | Qué es |
|---|---|---|
| null | null | catálogo oficial (los 20 rubros, 116 subítems) |
| null | usuario | catálogo personal de ese usuario — como hoy |
| obra | usuario | **carpeta de esa obra** (importada o creada ahí) |

**`on delete cascade` a propósito.** Una carpeta de obra no sobrevive a su obra: es su estructura,
no un dato reusable. Hay precedente exacto en el proyecto — `obra_rubros_orden` (0026) también
cascadea, y su comentario ya distingue "preferencia de esta obra" de "dato del usuario".

**Por qué una columna `origen` no alcanzaría.** Una marca dice de dónde vino pero no lo saca del
catálogo personal: seguirías viendo la carpeta de Galpón Mix adentro de tu próxima obra. `obra_id`
hace cuatro cosas de una sola vez:

1. **la carpeta sale gratis** — el filtro *es* la carpeta, no hay que inventar un agrupador;
2. el aislamiento entre obras queda en la base, no en una rutina de limpieza;
3. `obra_id` pasa a ser la unidad de borrado (se va con la obra);
4. la unicidad de código puede pasar a ser por obra, que es lo que el presupuesto impreso necesita
   de verdad.

### 4.2 La regla de coherencia rubro ↔ subítem

Un subítem no puede estar en una carpeta distinta a la de su rubro. La combinación prohibida es
"subítem de la obra A adentro de un rubro de la obra B".

```
subitems.obra_id válido  ⟺  rubros.obra_id is null  or  subitems.obra_id = rubros.obra_id
```

Se permite a propósito el caso `rubro.obra_id is null` + `subitem.obra_id = X`: **un subítem suelto
de una obra, colgado de un rubro del catálogo**. Es el caso "quiero agregar una partida al rubro 18
solo para esta obra", que hoy no existe y es justamente otra de las formas en que el catálogo
personal se ensucia.

No se puede expresar con un `check` (es entre tablas), así que va un trigger `before insert/update`
sobre `subitems`. **Y hace falta también del otro lado**: cambiar `rubros.obra_id` (§6.1) tiene que
arrastrar o validar los subítems que cuelgan.

### 4.3 Unicidad de código (decisión 3.2)

Hoy rige `rubros_codigo_unique` (0025), **único global sobre `codigo` entre todos los usuarios**. El
motivo escrito en esa migración es el presupuesto impreso: *"dos ítems con el mismo número confunden
al cliente"* — un documento que todavía no está construido. Efectos colaterales:

- "que entre tal cual" choca literalmente: si el Excel trae un rubro "1", el insert falla;
- dos PRO distintos no pueden tener cada uno su rubro "21" (**bug multi-inquilino latente, hoy**).

Se reemplaza por tres índices parciales que dicen la regla real — *único dentro de su carpeta*:

```sql
drop index rubros_codigo_unique;

-- catálogo oficial: uno solo en todo el sistema (vuelve el índice original de la 0015)
create unique index rubros_codigo_oficial_unique on rubros (codigo)
  where obra_id is null and creador_usuario_id is null;

-- catálogo personal: único por usuario, no entre usuarios  <- arregla el bug multi-inquilino
create unique index rubros_codigo_propio_unique on rubros (creador_usuario_id, codigo)
  where obra_id is null and creador_usuario_id is not null;

-- carpeta de obra: único por obra
create unique index rubros_codigo_obra_unique on rubros (obra_id, codigo)
  where obra_id is not null;
```

Y el par que le corresponde en `subitems`, donde hoy solo existe el parcial de oficiales
(`subitems_codigo_oficial_unique`, 0016) y **dos propios con el mismo código ya conviven**:

```sql
create unique index subitems_codigo_obra_unique on subitems (obra_id, codigo)
  where obra_id is not null;
```

**Precondición para aplicar**: no puede haber códigos repetidos dentro de un mismo usuario. Hoy el
índice global lo impide, así que en principio no los hay. Chequeo antes de migrar:

```sql
select creador_usuario_id, codigo, count(*) from rubros
where creador_usuario_id is not null group by 1, 2 having count(*) > 1;
```

**Lo que NO cambia y conviene saber**: en Cómputo el número que se ve en cada tarjeta de rubro es
**posicional** (índice+1 dentro de la lista, ver `rubros_tab.dart` y
`docs/rubros_orden_diseno_datos.md` §3), no `rubro.codigo`. Así que dos carpetas numeran 1..N cada
una sin chocar visualmente, sin trabajo extra. El código sí se muestra a nivel **subítem**
(`SubitemsScreen`), y ahí es donde conviven los dos "1.1" — que es exactamente lo que la decisión
3.2 pide.

### 4.4 RLS (decisión 3.4)

Hoy `rubros_select` (0015, ampliada en 0019) deja ver un rubro de otro miembro **solo si
`om.puede_ver_apu_ajena`** — un permiso pensado para APU, no para la estructura de la obra. Y el
Dart ni lo intenta: filtra `creador_usuario_id.eq.$usuarioId`. Un cliente invitado a una obra
importada vería el Cómputo vacío.

```sql
alter policy rubros_select on rubros using (
  (obra_id is null and (creador_usuario_id is null or creador_usuario_id = auth.uid()))
  or (obra_id is not null and is_obra_member(obra_id))
  or tiene_apu_ajena_visible_por_rubro(id)   -- se conserva: es el caso de APU ajena, otra cosa
);
```

Ídem `subitems_select`. Para escribir en una carpeta de obra, el gate es
`puede_editar_presupuesto(obra_id)` (0121) — el permiso que ya existe y ya significa esto.

**La mitad de Dart importa tanto como la RLS**: aunque la política lo permita, la consulta actual
excluye lo ajeno del lado del cliente. `getCatalogoCompleto` pasa a recibir la obra:

```dart
getCatalogoCompleto(String usuarioId, {String? obraId})
// .or('obra_id.eq.$obraId,and(obra_id.is.null,or(creador_usuario_id.is.null,creador_usuario_id.eq.$usuarioId))')
```

### 4.5 Qué no cambia

- `obra_subitems` no se toca. Sigue siendo la tabla de "qué partidas tiene esta obra".
- El catálogo oficial no se toca.
- Ninguna de las 18 funciones SQL que joinean `rubros` desde `obra_subitems` necesita cambios
  (§5.1).
- `obra_id is null` reproduce exactamente el comportamiento de hoy, así que la migración de datos
  es **vacía**: no hay backfill.

---

## 5. Relevamiento: qué se rompe y qué no

### 5.1 Gestión de Obra — no se rompe

Los tres lugares que Seba pidió verificar, más dos que aparecieron.

**Presupuesto congelado — no se rompe.** `congelar_presupuesto_obra` (0122, recreada por la 0149)
joinea `rubros` solo para leer `usa_apu` y `tipo_precio_manual`. Un rubro importado
(`usa_apu = false`, `'unitario'`) entra por la rama manual como cualquier rubro de precio manual.

**Avance ponderado por rubro — no se rompe.** `calcular_avance_ponderado_rubros` (0052) agrupa por
`os.rubro_id` y no mira el catálogo en ningún momento. La `0133` ya resuelve el nombre con un
`left join`, previendo que el rubro pueda faltar.

**Numeración — no es el riesgo que parecía.** Ver §4.3: el número visible del rubro es posicional.
El riesgo real era el índice único global, y es lo que la decisión 3.2 resuelve.

**El que sí se rompe** — `carga_avance_rubros_screen.dart:138` filtra el catálogo *del usuario* por
los rubros con partidas tildadas:

```dart
_rubrosConTildados = rubros.where((r) => (conteo[r.id] ?? 0) > 0).toList();
```

Un rubro que no está en *su* catálogo desaparece de la pantalla de carga de avance: **no se puede
cargar avance de esas partidas**. Hoy es un caso raro (rubro propio de otra persona en una obra
compartida); con esta pieza pasa a ser el caso normal apenas haya dos personas en la obra. Se
arregla solo al pasar `obraId` a la consulta (§4.4). Tanda 5.

**Y uno cosmético, ya previsto en el código.** `panel_avance_obra.dart:81`,
`desglose_certificado.dart:99` y `vista_previa_certificado_screen.dart:153` resuelven el nombre
contra el catálogo del usuario y caen a un `'Rubro'` genérico si no lo encuentran. El total cierra;
el nombre no aparece. Mismo arreglo, misma tanda.

### 5.2 El monto de la obra suma las dos carpetas

Sí, y **sin tocar nada**. Ninguna de las 18 funciones que joinean `rubros` desde `obra_subitems`
filtra por `creador_usuario_id` ni por origen: `calcular_presupuesto_vivo_obra`,
`calcular_monto_obra_subitems` y `congelar_presupuesto_obra` recorren las partidas tildadas de la
obra, sea cual sea su rubro. El certificado certifica sobre las dos porque trabaja sobre
`obra_subitems`, no sobre rubros.

### 5.3 Las pantallas que leen el catálogo

Ocho, todas vía `getCatalogoCompleto` / `getCatalogoOficial` / `getSubitemsDeRubro`:
`rubros_tab`, `subitems_screen`, `carga_avance_rubros_screen`, `carga_avance_subitems_screen`,
`quitas_demasias_screen`, `revisar_importacion_screen`, `vista_previa_certificado_screen`,
`gestion_obra_tab`, `apu_listado_tab` y `desglose_certificado`.

Con `obra_id null` todas siguen andando igual. Las que necesitan ver la carpeta son las que están
adentro de una obra — que son casi todas, porque el parámetro `obraId` ya lo tienen a mano.

**`apu_listado_tab` es la excepción y está bien así**: usa `getCatalogoOficial()` a propósito. La
solapa APU no tiene por qué ver la carpeta importada — es justamente lo que §2 dice que se pierde.

---

## 6. Los flujos nuevos

### 6.1 Adoptar un rubro al catálogo (decisión 3.1)

Adoptar = `obra_id = null` + `creador_usuario_id = <el usuario>`. Dos cosas que hay que resolver, y
no son cosméticas:

**a) El código puede chocar.** El rubro importado "1" convive con el oficial "1" mientras está en la
carpeta de obra (§4.3), pero al adoptarlo pasa al catálogo personal, donde
`rubros_codigo_propio_unique` puede rechazarlo. **La adopción tiene que renumerar**, proponiendo el
siguiente libre del catálogo personal y mostrándolo antes de confirmar. Nunca renumerar en silencio:
el número es lo que el usuario reconoce.

**b) Los subítems van con él.** Adoptar un rubro adopta su contenido, o la regla de §4.2 se rompe.
Queda por decidir si se puede adoptar un subítem suelto dejando el rubro en la obra — ver §8.

**Lo que la adopción NO hace**: no toca `obra_subitems`. Las partidas de la obra siguen apuntando a
los mismos `rubro_id`/`subitem_id`; lo único que cambió es en qué carpeta vive el catálogo. El monto
de la obra no se mueve.

### 6.2 Reimportar reemplaza (decisión 3.3) — la parte con filo

Reemplazar la carpeta significa borrar sus `rubros`/`subitems`, y ahí aparece lo que ya está en la
base. Las cuatro FK relevantes, todas **sin `on delete cascade`, a propósito**:

| FK | Migración | Qué protege |
|---|---|---|
| `obra_subitems.rubro_id → rubros(id)` | 0019 | cantidades cargadas |
| `obra_subitems.subitem_id → subitems(id)` | 0019 | idem |
| `certificado_subitems_avance.obra_subitem_id → obra_subitems(id)` | 0052 | avance certificado |
| `presupuesto_subitems_congelado.obra_subitem_id → obra_subitems(id)` | 0104 | el monto pactado |

**Ya hay una red de seguridad: la base no deja.** Un `delete` sobre un rubro con partidas cargadas
falla con error de FK. Eso es bueno — pero un error de FK no es un aviso, es un choque. El flujo
tiene que decidir antes:

1. **Si hay algún certificado no-borrador sobre partidas de la carpeta: se rechaza.** Es plata ya
   emitida y congelada. Mismo criterio y misma forma que el guard que `congelar_presupuesto_obra`
   ya usa para impedir recongelar (*"ya hay certificados emitidos contra el presupuesto
   congelado"*).
2. **Si la obra está congelada pero sin certificados emitidos: se avisa que el reemplazo
   descongela**, porque el snapshot deja de corresponder a las partidas.
3. **Si no hay nada de eso: se avisa con números concretos** — cuántas partidas tildadas se van a
   perder, con cuánta cantidad y monto cargados, y cuántos borradores de avance se descartan. El
   aviso dice qué se pierde, no "¿estás seguro?".

**Y la regla que lo hace tolerable: lo que matchea por código y descripción se conserva tildado.**
Reimportar para corregir tres precios no debería costar volver a tildar 24 partidas. Es la
diferencia entre "corregir" y "empezar de nuevo", que es lo que la decisión 3.3 pide. Esto merece su
propia sub-decisión — ver §8.

### 6.3 Alta: elegir carpeta

Al crear un rubro o una partida desde la app, se elige carpeta. El default razonable es **la carpeta
en la que estás parado**: si estás mirando la importada, se crea ahí. Lo que no puede pasar es que
el default mande siempre al catálogo personal, que es el comportamiento de hoy y es el que ensucia.

---

## 7. El corte

| # | Tanda | Estado |
|---|---|---|
| 1 | **0149 — redondeo en los agregados.** Independiente de todo esto. | **escrita, lista para aplicar** |
| 2 | **`obra_id` en `rubros`/`subitems`** + índices de §4.3 + RLS de §4.4 + `obraId` en las consultas del repositorio. Sin UI, sin cambio visible. | por hacer |
| 3 | **Las dos carpetas en Cómputo**: el toggle y elegir carpeta al crear (§6.3). | por hacer |
| 4 | **El importador escribe en la carpeta importada.** Acá se reescribe el seed de Galpón Mix. | por hacer |
| 5 | **Los agujeros de miembros**: carga de avance (§5.1) y nombres de rubro en el certificado. | por hacer |
| 6 | **0150 — el precio manual gana sobre la cascada de APU.** | **escrita, marcada para no aplicar** |

**La tanda 2 es la única con riesgo real; las demás son consecuencia.** Es también la que decide
todo: si `obra_id` queda bien puesto, el resto es UI y consultas.

La **adopción** (§6.1) y el **reemplazo al reimportar** (§6.2) no están en el corte a propósito:
dependen de que exista la carpeta y merecen su propia tanda cada una, después de la 4.

---

## 8. Lo que queda abierto

Nada de esto bloquea la tanda 2.

1. **¿Se puede adoptar un subítem suelto**, dejando su rubro en la carpeta de obra? §4.2 lo permite
   al revés (subítem de obra bajo rubro de catálogo), no en esta dirección.
2. **Qué matchea al reimportar** (§6.2): ¿código, descripción, o los dos? De eso depende cuánto se
   conserva tildado, y es la diferencia entre "corregir" y "empezar de nuevo".
3. **El presupuesto impreso**, cuando exista: con dos carpetas conviviendo, cómo se numeran los
   ítems en el papel. Es el motivo original del índice único global de la 0025, y sigue sin
   documento que lo obligue.
4. **Las solapas vacías** (APU y Mat y MO en una obra 100% importada). Pieza chica y aparte: el
   vacío tiene que explicar por qué está vacío *en esta obra* en vez de dar una instrucción genérica
   imposible de seguir.

---

## 9. Verificación de la tanda 2

Lo que tiene que dar antes de seguir a la 3:

```sql
-- 1. sin backfill: todo el catálogo existente queda como estaba
select count(*) from rubros   where obra_id is not null;   -- 0
select count(*) from subitems where obra_id is not null;   -- 0

-- 2. el bug multi-inquilino, cerrado: dos usuarios pueden tener cada uno su "21"
--    (insertar dos rubros propios con el mismo código y distinto creador -> tiene que funcionar)

-- 3. la coherencia de §4.2: un subítem de la obra A bajo un rubro de la obra B -> tiene que fallar

-- 4. el aislamiento, que es el punto de toda la pieza:
--    crear un rubro con obra_id = A y abrir Cómputo de la obra B -> no aparece
```

Y en la app, con dos usuarios reales: **un cliente invitado a una obra con carpeta importada tiene
que ver las partidas**, que es hoy el caso que falla y la razón de la decisión 3.4.
