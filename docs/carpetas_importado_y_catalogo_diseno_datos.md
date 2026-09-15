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

**Y el catálogo de la app queda intacto al lado.** Los rubros que trae el importador van **a la
carpeta de la obra, nunca al catálogo** — es la mitad que evita que se mezclen. Hecho en la tanda 5:
`RevisarImportacionScreen` pasa `obraId` en las dos llamadas a `crearPersonalizado`, y el `obraId`
del diálogo que las hace es `required` sin default a propósito, porque un `null` ahí reintroduce el
bug de las partidas duplicadas.

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

**3.1 — Un rubro se copia de una carpeta a la otra, en los dos sentidos.** *"Si el usuario ve que le
sirve siempre, tiene que poder quedárselo: importás, trabajás, y lo bueno se queda."*

**Ampliada y corregida el 2026-09-15**: el primer borrador decía "adoptar", en una sola dirección y
cambiando `obra_id`. Ahora son dos direcciones y es una copia:

> *"Copiar, no mover — el original se queda donde está. Adoptar uno de la obra al catálogo para
> reusarlo en otras obras, o bajar uno del catálogo a esta obra para modificarlo sin tocar el
> original."* (Seba)

**Eso cambia la mecánica**: no es editar `obra_id`, es **duplicar la fila con el `obra_id` nuevo**,
con renumeración cuando el código choca. `obra_id` sigue siendo una columna editable en el schema,
pero ningún flujo la edita. Consecuencias en §6.1.

**3.2 — Las dos numeraciones conviven.** La carpeta importada mantiene su numeración original, que
es el sentido de "tal cual viene". **La unicidad de código va por obra y por carpeta, no global.**
De paso saca del medio el índice único global de la `0025`, que hoy no molesta sólo porque nadie
escribe códigos legibles (ver la corrección en §4.3). Detalle ahí.

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
- dos PRO distintos no pueden tener cada uno su rubro "21".

**Corrección al primer borrador de este doc (2026-09-15):** el segundo punto es teórico hoy, no un
bug vigente. La `0027` le puso a `rubros.codigo` el default `gen_random_uuid()::text` y sacó el
código de la UI — un rubro creado desde la app lleva un UUID, y dos UUID no chocan nunca. **El
índice global no molesta hoy justamente porque nadie escribe códigos legibles.** Empieza a molestar
con esta pieza, que es la primera que los escribe: el importador copiando el "1" del Excel.

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

**Consecuencia que apareció construyendo la tanda 3, y que la tanda 5 tiene que respetar.** El
código de un subítem creado a mano sale de `SubitemsScreen._siguienteCodigoPropio`, que lo deriva
del número **posicional** del rubro en la lista de Cómputo. Ese número arranca de 1 **en cada
carpeta**, así que el tercer rubro del catálogo y el tercero de la carpeta importada producen los
dos un `3.x`. Con `subitems_codigo_obra_unique` siendo `(obra_id, codigo)`, los dos chocan si caen
en la misma obra — y el caso es alcanzable: una partida "solo en esta obra" colgada de un rubro del
catálogo convive con las partidas de la carpeta importada bajo el mismo `obra_id`.

Resuelto del lado de la app, no de la base: al crear en la carpeta se consultan los códigos ya
usados (`SubitemsRepository.getCodigosDeObra`) y se avanza hasta el primero libre. Un hueco en la
secuencia no significa nada — el catálogo ya los tiene por borrados.

**El importador (tanda 5) no puede apoyarse en eso**: trae los códigos del Excel, que es todo el
punto de "tal cual viene". Si el Excel reinicia la numeración en cada rubro, dos partidas van a
traer el mismo código y el índice las va a rechazar. La salida es prefijar con el código del rubro
antes de insertar, y está anotada en el paso 2 de la `0151`.

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
cargar avance de esas partidas**. Antes de esta pieza era un caso raro (rubro propio de otra persona
en una obra compartida); con las carpetas pasaba a ser el caso normal apenas hubiera dos personas en
la obra.

**Cerrado en la tanda 4 (2026-09-15)**, pasando `obraId` en los seis lugares que leían el catálogo
dentro de una obra: `carga_avance_rubros_screen`, `carga_avance_subitems_screen`,
`quitas_demasias_screen`, `vista_previa_certificado_screen`, `gestion_obra_tab` (que es de donde
`panel_avance_obra` saca los nombres) y `desglose_certificado`. El único que queda a propósito sin
`obraId` es `revisar_importacion_screen`, que es la tanda 5.

**Y uno cosmético, ya previsto en el código.** `panel_avance_obra.dart`,
`desglose_certificado.dart` y `vista_previa_certificado_screen.dart` resuelven el nombre contra el
catálogo del usuario y caen a un `'Rubro'` genérico si no lo encuentran. El total cierra; el nombre
no aparece. Cerrado en la misma tanda 4.

**Lo que ese fallback sigue tapando, y queda así por diseño**: un rubro propio de *otra persona*,
en su catálogo personal, usado en una obra compartida. No es de esta pieza — el catálogo personal de
cada uno es suyo, y resolverlo pediría una consulta aparte por membresía.

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

### 6.1 Copiar un rubro de una carpeta a la otra (decisión 3.1)

**Es una copia profunda: el rubro y sus subítems.** Un rubro sin partidas no sirve de nada, y
dejarlas atrás rompería la regla de §4.2. Filas nuevas, ids nuevos; el original queda intacto.

**`obra_subitems` no se toca en ningún caso.** Las partidas cargadas siguen apuntando a los ids
originales, así que **el monto de la obra no se mueve por copiar**. Es la propiedad que hace que
esto sea seguro de ofrecer.

**La renumeración, dirección por dirección.** Los índices de §4.3 no aprietan igual en las dos:

| Al copiar | Índice que puede chocar | Cuándo |
|---|---|---|
| obra → catálogo, el rubro | `rubros_codigo_propio_unique (creador_usuario_id, codigo)` | solo si ese mismo usuario ya tiene un rubro propio con ese código. **No choca contra los oficiales**: el índice del catálogo oficial es otro |
| obra → catálogo, los subítems | ninguno | los propios no tienen índice de unicidad (el de la 0016 es parcial sobre los oficiales) |
| catálogo → obra, el rubro | `rubros_codigo_obra_unique (obra_id, codigo)` | si la carpeta ya tiene ese código — probable al bajar un oficial ("14") a una carpeta importada que numera igual |
| catálogo → obra, los subítems | `subitems_codigo_obra_unique (obra_id, codigo)` | mismo caso, y es el más frecuente de los cuatro |

Cuando choca se renumera al siguiente libre, **y se muestra antes de confirmar**. Nunca en
silencio: el número es lo que el usuario reconoce.

---

**Dónde vive la acción**: en el menú del AppBar de `SubitemsScreen`, no en la tarjeta de
`RubrosTab`. Dos motivos: en la tarjeta habría que sumar un tercer elemento al trailing, que ya
tiene el badge N/M y compite por ancho en pantalla angosta; y la decisión de copiar un rubro se toma
mirando lo que tiene adentro, que es justamente esa pantalla. Un menú y no un botón: la acción
depende de en qué carpeta está el rubro, y son dos operaciones distintas con dos avisos distintos.

**El aviso de la dirección B no es un "¿estás seguro?"**: dice los dos efectos que la palabra
"copiar" no anuncia, con el número real de partidas que se mueven, y la frase del precio congelado
solo aparece si el rubro usa APU. Con 0 partidas cargadas, esa parte del aviso no aparece — no hay
nada que advertir.

Las dos direcciones **no tienen el mismo tamaño**, y por eso son dos tandas (§7).

**Dirección A — obra → catálogo ("adoptar"). Es la simple.** Los rubros de una carpeta son siempre
de precio manual (vienen del importador o del alta a mano, las dos ramas crean `usa_apu = false`),
así que la copia es un `insert` de rubro + N subítems y nada más. Sin APU que arrastrar, sin cómputo
que reacomodar.

**Dirección B — catálogo → obra ("bajarlo para modificarlo"). Tenía dos nudos; los dos cerrados el
2026-09-15.**

**b.1) El cómputo ya cargado pasa a la copia, y el diálogo lo dice con el número concreto.**

Si la obra ya tiene partidas tildadas en el rubro del catálogo y se lo baja a la carpeta sin más,
quedan **dos rubros con el mismo nombre en la misma obra**: el del catálogo con el cómputo, y la
copia vacía. Seba: *"Sin eso la función no sirve."*

Así que las partidas de *esta obra* pasan a apuntar a la copia — un `update` de
`obra_subitems.rubro_id`/`subitem_id` **conservando el `obra_subitems.id`**. Es un `update`, no un
`delete` + `insert`, y esa distinción es todo: `certificado_subitems_avance` y
`presupuesto_subitems_congelado` apuntan a `obra_subitems.id`, que no cambia, así que **el avance
certificado y el monto congelado sobreviven intactos**. La cantidad y el precio tampoco se mueven.
Y el original sigue en el catálogo, intacto para las demás obras — la copia sigue siendo copia.

Es un efecto que la palabra "copiar" no anuncia, así que **el diálogo lo dice antes de confirmar,
con el número real**: *"Esta obra tiene 6 partidas cargadas en este rubro. Pasan a la copia, con sus
cantidades y su avance."* Con cero partidas cargadas la frase no aparece: no hay nada que advertir.

**b.2) La copia nace de precio manual, con el precio que el APU da hoy congelado.**

Un rubro del catálogo puede tener `usa_apu = true` y sus subítems, composición cargada. Los subítems
de la copia son filas nuevas **sin `apu_composiciones`**, así que una copia con `usa_apu = true`
dejaría sus partidas sin precio — **cero, en silencio**, que es el mismo modo de falla que ya mordió
una vez con el mapeo del PDF.

Entonces la copia nace `usa_apu = false` / `tipo_precio_manual = 'unitario'`, y al copiar se escribe
en `obra_subitems.precio_unitario_manual` el `precio_final` que `calcular_precio_final_apu_subitems`
da **en ese momento**. Seba: *"Es lo que estoy pidiendo cuando bajo un rubro a la obra — sacarlo de
la cascada para esta obra puntual."*

Tres consecuencias que conviene tener a la vista:

- **El precio deja de seguir a los insumos** para ese rubro en esa obra. Es el punto, no un efecto
  lateral, pero el diálogo lo dice igual.
- **No hace falta la `0150`.** La copia es un rubro de precio manual de verdad, no un rubro con APU
  al que se le mete un precio a mano. Por eso la 8 no bloquea a la 7.
- **La receta no se duplica.** Descartadas las otras dos salidas que se habían escrito acá: copiar
  `apu_composiciones` metía la pieza en la propiedad del APU por persona
  (`docs/etapa3_roles_permisos_diseno_datos.md`), que es otra conversación; y prohibir bajar rubros
  con APU dejaba afuera justo los que más ganas dan de modificar, que son los de terminaciones.

### 6.2 Reimportar reemplaza (decisión 3.3) — la parte con filo

Reemplazar la carpeta significa borrar sus `rubros`/`subitems`, y ahí aparece lo que ya está en la
base. Las cuatro FK relevantes **no se comportan igual**, y la diferencia es la que importa:

| FK | Migración | `on delete cascade` | Qué pasa al borrar el rubro |
|---|---|---|---|
| `obra_subitems.rubro_id → rubros(id)` | 0019, **cambiada por la 0028** | **sí** | se lleva las partidas de la obra, en silencio |
| `obra_subitems.subitem_id → subitems(id)` | 0019, **cambiada por la 0028** | **sí** | idem |
| `certificado_subitems_avance.obra_subitem_id` | 0052 | no | **bloquea**: error de FK |
| `presupuesto_subitems_congelado.obra_subitem_id` | 0104 | no | **bloquea**: error de FK |

**Corrección al primer borrador de este doc (2026-09-15):** las dos primeras decían "sin cascade".
La `0028` se las puso, a propósito: la app usaba la FK para *bloquear* el borrado de un rubro propio
y se cambió por un cascade con confirmación en la UI. O sea que **la base no protege las cantidades
cargadas** — solo se planta si hay un certificado o un snapshot congelado de por medio.

Eso hace el reemplazo más filoso, no menos: un borrado descuidado destruye cantidades sin avisar, y
recién choca contra un error de FK si la obra ya certificó. **Un error de FK no es un aviso, es un
choque.** El flujo tiene que decidir antes:

1. **Si hay algún certificado no-borrador sobre partidas de la carpeta: se rechaza.** Es plata ya
   emitida y congelada. Mismo criterio y misma forma que el guard que `congelar_presupuesto_obra`
   ya usa para impedir recongelar (*"ya hay certificados emitidos contra el presupuesto
   congelado"*).
2. **Si la obra está congelada pero sin certificados emitidos: se avisa que el reemplazo
   descongela**, porque el snapshot deja de corresponder a las partidas.
3. **Si no hay nada de eso: se avisa con números concretos** — cuántas partidas tildadas se van a
   perder, con cuánta cantidad y monto cargados, y cuántos borradores de avance se descartan. El
   aviso dice qué se pierde, no "¿estás seguro?".

**Y la regla que lo hace tolerable, cerrada por Seba el 2026-09-15: lo que coincida por código Y
descripción se conserva tildado, con su cantidad.**

> *"Si no, corregir tres precios obliga a volver a tildar 24 partidas, y eso es empezar de nuevo en
> vez de corregir — que es justo lo contrario de lo que pedí."*

Los dos campos, no uno: solo por código, un Excel renumerado pisaría partidas distintas con la misma
cantidad; solo por descripción, un cambio de redacción perdería el vínculo. Los dos juntos fallan
hacia el lado seguro — ante la duda la partida se trata como nueva, que cuesta un tilde, en vez de
heredar una cantidad que no le corresponde, que cuesta un certificado mal emitido.

**Lo que se conserva es el tilde y la cantidad, nunca el precio** — reimportar es justamente traer
precios nuevos. Y lo que no matchea con nada entra como partida nueva, sin tildar: aparecer tildada
en cero sería decir que se cotizó en cero.

Implicancia técnica directa: **el reemplazo no puede ser un `delete` + `insert`**, porque el cascade
de la 0028 se llevaría las cantidades antes de poder rescatarlas. Tiene que ser un `upsert` sobre
`subitems` y `obra_subitems` que conserve los `id` de lo que matchea, y borrar al final solo lo que
quedó sin pareja.

### 6.3 Alta: elegir carpeta

Al crear un rubro o una partida desde la app, se elige carpeta. El default razonable es **la carpeta
en la que estás parado**: si estás mirando la importada, se crea ahí. Lo que no puede pasar es que
el default mande siempre al catálogo personal, que es el comportamiento de hoy y es el que ensucia.

---

## 7. El corte

| # | Tanda | Estado |
|---|---|---|
| 1 | **0149 — redondeo en los agregados.** Independiente de todo esto. | **APLICADA 2026-09-15** |
| 2 | **`obra_id` en `rubros`/`subitems`** + índices de §4.3 + RLS de §4.4 + `obraId` en las consultas del repositorio. Sin UI, sin cambio visible. | **`0151` APLICADA y verificada 2026-09-15** |
| 3 | **Las dos carpetas en Cómputo**: el toggle y elegir carpeta al crear (§6.3). | **hecha y verificada en emulador 2026-09-15** |
| 4 | **Los agujeros de miembros**: carga de avance (§5.1) y nombres de rubro en el certificado. | **hecha 2026-09-15, sin probar en emulador** |
| 5 | **El importador escribe en la carpeta importada.** Acá se reescribe el seed de Galpón Mix. | **hecha 2026-09-15, sin probar** |
| 6 | **Copiar obra → catálogo** ("adoptar lo bueno de lo importado"). §6.1, dirección A. | **`0154` escrita, pendiente de aplicar** |
| 7 | **Copiar catálogo → obra** ("bajarlo para modificarlo"). §6.1, dirección B, con b.1 y b.2 ya cerradas. | **`0155` escrita, pendiente de aplicar** |
| 8 | **0150 — el precio manual gana sobre la cascada de APU.** | **escrita, marcada para no aplicar** |

**La tanda 2 es la única con riesgo real; las demás son consecuencia.** Es también la que decide
todo: si `obra_id` queda bien puesto, el resto es UI y consultas.

**Las tandas 4 y 5 están invertidas respecto del primer borrador de este doc, y el motivo importa.**
Antes el importador iba cuarto y los agujeros de miembros quinto. Entre una y otra quedaba una
ventana en la que una obra importada le muestra al cliente invitado partidas cuyos rubros **no
aparecen en la pantalla de carga de avance** (`carga_avance_rubros_screen.dart:138` filtra por el
catálogo del usuario, §5.1). Con las carpetas vacías no se nota; con una obra cargada y compartida,
sí. **La regla general: los agujeros que una pieza destapa se tapan antes de llenarla, no después.**

**Las dos direcciones de copia son dos tandas y no una** (6 y 7), y el motivo no es el tamaño del
código —la mecánica de copiar es la misma— sino que la dirección B arrastra dos decisiones de
producto que la A no tiene (§6.1, b.1 y b.2). Partirlas deja salir la mitad que ya está resuelta en
vez de trabarla contra la que no.

**Las dos van después de la 5** porque las dos necesitan una carpeta con algo adentro para probarse,
y la carpeta la llena el importador. La 6 es además la que el usuario va a querer apenas importe
algo que le sirva.

El **reemplazo al reimportar** (§6.2) sigue fuera del corte: es parte de la 5 en su forma mínima
(reimportar y que no se duplique) y merece tanda propia en su forma completa (conservar lo tildado,
los tres casos de aviso).

---

## 8. Lo que queda abierto

Nada de esto bloquea la tanda 2.

1. **El importador no captura la numeración original, porque nunca la lee.** Encontrado
   construyendo la tanda 5. `importaciones_items` (0080) guarda `rubro_texto`, `descripcion_texto`,
   `unidad_texto`, `cantidad` y `precio_unitario` — **no hay columna de código de partida**, y la
   lista de sinónimos del parser mete "item"/"ítem" en la misma columna que "rubro"/"capítulo", así
   que en una planilla con columnas *Item* y *Descripción* el número de la partida termina pisando
   el nombre del rubro.

   O sea que §2 promete "con su numeración original" y el importador hoy solo puede cumplirlo a
   medias: los rubros y las descripciones entran tal cual, los códigos de partida se derivan. **El
   seed de Galpón Mix sí conserva la numeración** porque no pasa por el parser.

   Cerrarlo es una columna en `importaciones_items`, un sinónimo nuevo en el parser y un campo más
   en la revisión. Chico pero es una tanda, no un arreglo al pasar.

2. **¿Se puede copiar un subítem suelto**, sin su rubro? Las dos direcciones de §6.1 copian el rubro
   entero. Copiar una partida sola al catálogo tiene sentido ("esta me sirve siempre") y no está
   resuelto dónde cae si su rubro no existe del otro lado.
3. **El presupuesto impreso**, cuando exista: con dos carpetas conviviendo, cómo se numeran los
   ítems en el papel. Es el motivo original del índice único global de la 0025, y sigue sin
   documento que lo obligue.
---

## 9. Las solapas vacías — resuelto 2026-09-15

Era el punto 5 de la primera lista de la pieza. Se cerró en dos pasos, y el segundo cambió el
propósito de la pantalla, no su redacción.

**Lo que había:** APU y Mat y MO, en una obra 100% importada, mostraban un cartel suelto con una
instrucción imposible de seguir — *"tildá subítems con APU en el Cómputo"* — en una obra donde
**todo está tildado y ninguna partida tiene composición**.

**Primer intento, insuficiente:** cambiar el texto del cartel. Seba:

> *"Una solapa vacía parece rota; una con las partidas a la vista en gris se entiende sola y además
> muestra qué va a haber ahí."*

**Segundo intento, también equivocado, y la corrección es la que importa.** Mostré en gris las
partidas **de la obra**:

> *"Muestra en gris las partidas importadas, que nunca van a tener APU. Eso no muestra nada. Lo que
> tiene que aparecer en gris es el catálogo de la app —las partidas oficiales con sus recetas— y las
> propias del PRO. **Porque el punto no es explicar un vacío: es mostrar el potencial de la app. El
> que abre APU tiene que ver qué puede hacer.**"* (Seba, 2026-09-15)

**El criterio, que es general:** un estado vacío no es un problema de redacción ni de honestidad, es
una oportunidad desperdiciada. La pregunta correcta no es *"¿cómo explico que esto está vacío?"*
sino *"¿qué puede hacer esta pantalla que el usuario todavía no usó?"*.

Mostrar las partidas de la obra importada era honesto y **completamente inútil**: son justamente las
que nunca van a tener composición, porque su precio ya viene cerrado del presupuesto. En Mat y MO
era peor todavía — **los insumos salen de las recetas, no de un precio cerrado**, así que apuntaba
al lado contrario del que genera insumos.

**Tercera corrección, y es la que fija el criterio fino: cada solapa muestra SU materia prima.**
Puse el mismo listado de partidas en las dos. Seba:

> *"Mat y MO está mostrando las partidas de APU. Ahí no van partidas. Tienen que aparecer los
> materiales y la mano de obra del catálogo en gris — los 174 insumos con sus precios de los
> corralones, y las categorías de mano de obra con su valor hora. Eso es lo que muestra el potencial
> de esa solapa: el que la abre tiene que ver que la app trae precios reales de la zona."*

"Mostrar el potencial" no es un cartel reutilizable: **el potencial de cada pantalla es distinto.**
El de APU son las partidas con su análisis; el de Mat y MO son los precios reales de la zona que la
app ya tiene cargados. Poner partidas en Mat y MO repetía la solapa de al lado y no decía nada del
valor propio de esa.

**Lo que se muestra, entonces:**

- **APU** — las partidas del catálogo que tienen análisis cargado, oficiales y propias del usuario,
  agrupadas por rubro.
- **Mat y MO** — los materiales del catálogo con su precio promedio de corralón, y las categorías
  UOCRA con su valor hora de esta obra.

**Cuarta corrección: la pantalla real atenuada, no una vitrina aparte.** Las dos primeras versiones
dibujaban tarjetas grises propias, con su layout y su tipografía. Seba: *"la pantalla real atenuada,
no una vitrina aparte"*. La diferencia no es estética:

1. **Lo que se ve es lo que va a haber.** Una vitrina con diseño propio muestra una aproximación de
   la pantalla; la pantalla atenuada muestra la pantalla. Cuando el usuario tilda su primera
   partida, lo que aparece es exactamente lo que estaba viendo, ahora en color y tocable.
2. **No hay un segundo layout que mantener.** Un diseño paralelo se desactualiza solo: el día que la
   fila real gana una columna, la vitrina queda vieja y nadie se entera, porque la pantalla vacía es
   justamente la que nadie mira.

Implementación: cada solapa carga el catálogo en **su propio estado** (`_grupos` en APU, `_insumos`
en Mat y MO) con un flag `_vitrina`, y atenúa sus propios ítems con `Opacity`.

**Quinta corrección — se bloquea la edición, no el desplazamiento.** La primera implementación
envolvía la pantalla entera en `Opacity` + `IgnorePointer`. Seba la probó:

> *"Quedaron frías, no se pueden recorrer. El IgnorePointer bloquea todo el toque, incluido el
> deslizar, así que veo la primera pantalla y no puedo bajar. Y la gracia es justamente poder
> recorrer el catálogo para ver qué trae la app."*

**`IgnorePointer` no distingue entre editar y desplazar**: bloquea el gesto, y el scroll es un
gesto. Atenuar una pantalla para mostrarla y de paso impedir recorrerla es peor que no mostrarla —
se ve la primera pantalla de un catálogo de 174 insumos y ahí termina.

La regla que queda: **`Opacity` sí (no toca el hit-test), `IgnorePointer` nunca**, y la edición se
apaga donde vive — en el `onTap` de cada control, con el flag de vitrina. En APU es el tap de la
fila; en Mat y MO son el lápiz de precio y el enlace "Volver".

**Y no todo lo que está en una solapa vacía es una muestra.** En Mat y MO el bloque de costo de mano
de obra —cargas sociales, valor hora, los 7 parámetros— es dato real de esa obra y se edita aunque
no haya un solo insumo cargado. Queda **en color y funcionando**: atenuarlo lo haría parecer
inactivo cuando es lo único que sí sirve ahí.

**El cartel se descarta** (`widgets/cartel_vista_previa.dart`), con el mismo mecanismo que
`CartelAvisoLegalLibro`: `SharedPreferences` por obra y por dispositivo, con `scope` separando APU de
Mat y MO. Y en Mat y MO va **debajo** del bloque de mano de obra, no arriba de todo: arriba tapaba
justamente lo único editable de la pantalla.

Dos adaptaciones mínimas, cada una con su motivo:

- **En APU la columna de precio queda vacía**, no en "Incompleto". Una partida del catálogo que no
  está en la obra no tiene precio acá porque no fue tildada, no porque le falte algo: 97 renglones
  en naranja diciendo "Incompleto" sería lo contrario de mostrar lo que la app puede hacer.
- **En Mat y MO no se muestra la cantidad.** "Cantidad necesaria: 0" repetido 174 veces es ruido, no
  información. El resto de la tarjeta —ícono, nombre, precio, marca de precio fijado a mano— queda
  igual.

**Los precios necesitaron una migración, y el motivo no era obvio:** `precios_select` (0013) es
`is_corralon_owner(corralon_id)`, o sea que cada corralón ve solo los suyos. Consultar `precios`
desde la app devuelve **cero filas, sin error** — parecería que no hay precios cargados. La `0152`
agrega `catalogo_insumos_con_precio()`, `security definer`, que devuelve promedio y cantidad de
precios por insumo, nunca el precio de un corralón puntual.

**Cuándo desaparece: solo, y sin lógica nueva.** Las dos solapas muestran esto cuando su listado
real está vacío. En cuanto el usuario tilda en Cómputo una partida del catálogo con receta, esa
partida entra en APU con su precio desglosado y sus insumos aparecen en Mat y MO.

Tres detalles con su motivo:

- **Las filas van inertes.** Esas partidas no están en la obra: no hay una composición *de esta
  obra* que abrir. Un gris que se toca y no hace nada es peor que uno que se ve inerte.
- **La nota de función PRO aparece solo para un usuario Free.** Lo que es PRO es *editar* una receta
  y crear las propias; el listado y el precio unitario los ve Free igual, que es el criterio que ya
  regía en `ComposicionApuScreen`.
- **Las recetas propias se marcan con un chip "tu análisis"**, y el cartel cuenta cuántas son. Una
  receta propia es un clon por persona de la oficial (`0071_personalizacion_apu_pro.sql`), así que
  vive sobre el mismo subítem oficial: sin el chip, lo que el usuario ajustó se vería igual que lo
  que nunca tocó.
- **En Mat y MO los precios se ocultan para un rol sin montos** (`puedeVerMontosYAPU`), igual que en
  el resto de la solapa: quedan los nombres y las unidades. Ocultos, no deshabilitados.

### 9.2 "Receta" no va en la interfaz

Corrección de Seba en la misma tanda, y es de vocabulario pero vale escribirla porque **ya se había
corregido una vez y volvió**: *"receta" es jerga de cocina, no de presupuestos.* El término del
rubro es **análisis**, que además coincide con el nombre de la solapa (Análisis de Precios).

Rige para **todo texto visible al usuario**, no solo el cartel nuevo. En comentarios de código,
nombres de clase, archivos y funciones "receta" se puede quedar: `CatalogoConRecetas`,
`restaurar_receta_oficial_apu` y `getSubitemIdsConRecetaPropia` no los ve nadie.

Barrido hecho sobre los literales de string de todo `lib/`: 0 casos restantes. Los únicos que había
los había introducido yo en esta misma tanda — el resto de la app ya decía "APU" y "Volver a la
oficial".

### 9.1 Cómo crece el catálogo — criterio anotado, sin construir

Salió de la misma conversación y da el marco de por qué el catálogo es "el potencial de la app" y no
un dato estático:

> *"El PRO edita las recetas y crea las suyas, y una receta propia que se repita entre varios
> usuarios se evalúa para sumarla al catálogo oficial, siempre con revisión previa."* (Seba)

O sea que el catálogo oficial **se alimenta del uso**, con dos condiciones que conviene no perder:
la señal es la **repetición entre usuarios distintos** (no que a alguien le guste su receta), y la
incorporación es **con revisión previa**, nunca automática.

No hay nada construido de esto: hoy `apu_composiciones.creador_usuario_id` ya distingue la receta
oficial de la propia de cada persona, que es la mitad del dato que haría falta. Lo que no existe es
ninguna forma de detectar la repetición ni de promover una receta. **Pieza aparte, sin diseño.**

---

## 10. Verificación de la tanda 2

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
