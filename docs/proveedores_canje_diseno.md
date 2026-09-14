# Solapa Proveedores: el canje — diseño (2026-09-14, sin construir)

Salió de una conversación de hoy. **No hay nada construido de esta pieza** y no se escribió código
más allá de poner la solapa en "en construcción" (ver §8). Lo que sigue es el diseño tal como lo
planteó Seba, más lo que hace falta decidir antes de que alguien lo escriba.

Documentos que se cruzan con este y conviene leer antes: `docs/proveedores_digitales_bariloche.md`
(la investigación de los corralones reales, y una advertencia sobre membresías que aplica directo a
§5) y `docs/monetizacion.md`.

---

## 1. El problema, que es lo que hace que la pieza valga

> *"Hoy los precios los consigo yo pidiendo cotizaciones que no voy a comprar, y eso no escala ni a
> otra ciudad ni en el tiempo."*

Vale desarmar las dos mitades, porque son problemas distintos:

- **No escala a otra ciudad.** El catálogo de precios que hay hoy es de Bariloche, conseguido por
  Seba con sus contactos. Un usuario en Córdoba abre la app y los precios no le sirven. Y no hay
  ningún Seba en Córdoba.
- **No escala en el tiempo.** Peor, y menos visible: los precios que ya están **envejecen solos**.
  En una economía con la inflación argentina, un precio de hace seis meses no es un precio viejo,
  es un precio equivocado — y la app lo muestra con la misma cara de certeza que uno de ayer.

La segunda es la que hace que esto no se pueda posponer indefinidamente: el catálogo actual no se
queda quieto esperando, **se degrada**.

## 2. El canje

El trato, en una línea: **el proveedor carga sus precios y a cambio recibe pedidos de cotización
desde la app.**

Y la cotización que recibe **le llega con el cómputo ya hecho**. Esa es la ventaja concreta, y no es
menor: hoy un corralón recibe consultas sueltas por WhatsApp que tiene que interpretar y pasar a
planilla. Acá recibe una lista de materiales con cantidades, de alguien que ya decidió que va a
construir. **Es demanda cualificada, no una consulta más.**

## 3. Por qué el proveedor puede confiar: ningún precio individual queda expuesto

Es la parte del trato que decide si alguien se suma, y conviene decirla con precisión porque es
verificable:

- **La app calcula con el promedio de todos, nunca con el precio de uno.**
- **El precio real de cada proveedor aparece recién cuando el usuario le pide cotización directa** —
  o sea, cuando el proveedor eligió mostrarlo.

### Esto NO hay que construirlo: ya está, desde la `0013`

Hallazgo de revisar la base antes de escribir el documento, y cambia la conversación con un
proveedor. La arquitectura que sostiene la promesa **ya existe y está aplicada**:

| Pieza | Estado |
| --- | --- |
| `precios` con RLS: **solo el dueño del corralón lee sus propias filas** | Aplicada (`0013`) |
| `is_corralon_owner()` | Aplicada |
| `calcular_precio_promedio_insumo()`, `security definer`, **devuelve solo agregados** — nunca `corralon_id` ni el valor fila por fila | Aplicada |

El comentario de esa migración ya lo dice en los términos exactos de este trato: *"ni siquiera un
arquitecto autenticado puede hacer un SELECT crudo acá"*.

**Consecuencia práctica: la promesa se puede hacer hoy y es demostrable.** No es "vamos a proteger
tus precios", es "tus precios ya están protegidos y te puedo mostrar cómo". Frente a un corralón que
desconfía, la diferencia entre esas dos frases es toda la conversación.

### La grieta, que hay que mirar antes de prometer

`calcular_precio_promedio_insumo()` devuelve `promedio`, **`minimo`, `maximo` y
`cantidad_corralones`**. Con pocos proveedores eso deja de ser un agregado:

- con **1** proveedor, el promedio **es** su precio;
- con **2**, `minimo` y `maximo` **son** los dos precios, uno de los cuales el proveedor conoce
  porque es el suyo — así que sabe el del otro exactamente.

Es la misma clase de fuga que ya se documentó y se aceptó para el Factor K ("deducible por resta"),
pero **acá el contexto es distinto y por eso la conclusión puede ser otra**: allá el que deduce es
el dueño del dato; acá sería un competidor directo, sobre el dato más sensible que tiene.

Y no es hipotético: en Bariloche hay **dos** corralones digitalizados
(`docs/proveedores_digitales_bariloche.md`). El caso de 2 es el caso real de arranque.

**No lo cierro yo** — va como ambigüedad A.

## 4. Clasificar por rubro comercial

> *"Hoy le pediría porcelanato a un corralón que no vende."*

Los insumos se etiquetan por **rubro comercial** — obra gruesa, pinturería, maderera, sanitarios,
revestimientos — para que cada pedido vaya a quien corresponde.

**Es barato:** los ~175 insumos del catálogo ya están organizados, así que es agregarles una
etiqueta, no reclasificarlos desde cero.

Y **el rubro comercial no es el rubro de obra**. Son dos ejes distintos que se cruzan: un rubro de
obra (Mampostería) consume materiales de varios rubros comerciales, y un rubro comercial (pinturería)
abastece a varios rubros de obra. Conviene tenerlo claro antes de escribir la columna, porque la
tentación de reusar el rubro que ya existe va a estar.

**Y el usuario puede elegir un proveedor puntual**, porque conoce su zona mejor que la app. La
clasificación sugiere; no decide. (Eso ya está anticipado en la pantalla de "en construcción": *"si
ya trabajás con alguien, el pedido va a ese proveedor y listo"*.)

## 5. La membresía, y cuándo aparece

**No se cobra al principio, porque ellos están haciendo el favor.** Aparece cuando la app tenga
usuarios y estar adentro valga algo. Ahí puede haber niveles, con publicidad chica dentro de la
solapa.

El orden es el correcto y conviene dejar escrito por qué, para que no se adelante: cobrarle a un
proveedor por figurar en una app sin usuarios es pedirle que pague por nada. **El activo que se está
construyendo en esta etapa no es ingreso, es el catálogo de precios** — y el catálogo se paga con el
acceso a los pedidos, no con plata.

**Advertencia que ya está escrita y aplica entera acá:**
`docs/proveedores_digitales_bariloche.md` §"Advertencia sobre el modelo de membresías" — si alguna
vez se integra con XCONS, cobrarle membresía a corralones de su red por aparecer en la app es una
situación que hay que definir **en el acuerdo desde el principio, no después**.

## 6. El proceso con plazos, que es lo que evita que el catálogo se pudra

Cinco días para cargar precios → aviso → cinco más → **baja hasta que los suba**.

Esta es la parte del diseño que resuelve §1 segunda mitad, y por eso no es un detalle
administrativo: **sin el plazo, el canje entrega un catálogo que se degrada solo.** Un proveedor que
cargó una vez y nunca más no está sosteniendo su lado del trato — y lo que es peor, sus precios
viejos siguen ensuciando el promedio que la app le muestra a todos.

### Y necesita el programador de tareas — **van cuatro**

El proyecto no tiene `pg_cron` habilitado, y esta es la **cuarta** pieza que lo pide:

| # | Pieza | Cómo se resolvió |
| --- | --- | --- |
| 1 | Vencimiento de la objeción (`0131`) | Esquivado: "calcular al leer, materializar al tocar" |
| 2 | Aviso de vencimiento de objeción (`0143`) | Esquivado igual |
| 3 | Push Tanda 3 | **Bloqueada** esperando scheduler |
| 4 | Este proceso de plazos | Sin resolver |

El truco de "calcular al leer" que salvó a las dos primeras **no sirve acá**, y vale entender por
qué: ahí el vencimiento se evaluaba cuando alguien miraba la fila. Acá **hay que avisarle a alguien
que no está mirando** — un mail o un push al proveedor a los 5 días. Nadie va a abrir nada que
dispare el cálculo.

O sea: **esta pieza no se puede construir entera sin resolver el scheduler primero.** Se puede
construir todo lo demás (el canje, el rubro comercial, los pedidos) y dejar los plazos para después,
pero conviene saber que quedaría a medias por ese motivo y no por falta de diseño.

## 7. Lo que hay que decidir antes de escribir

**A. El mínimo de proveedores para mostrar un promedio.** Ver §3. Con 1 o 2 proveedores el agregado
no agrega nada y la promesa que le hiciste al proveedor deja de ser cierta. Las salidas posibles:
no devolver nada por debajo de N (¿3?), devolver solo el promedio sin `minimo`/`maximo` cuando hay
pocos, o aceptarlo como está y no prometer más de lo que da. **Es la única de las cinco que toca
una función ya aplicada**, y es la que más pesa en la conversación comercial.

**B. Quién es el proveedor dentro de la app.** Hoy `corralones` **no tiene política de INSERT**: el
alta es a mano por SQL Editor, porque nunca hubo flujo de autoregistro. El canje lo necesita —
alguien tiene que poder entrar, cargar precios y recibir pedidos. ¿Es un usuario de la app con un
rol nuevo, fuera de las obras (que hoy son la unidad de permisos de todo el sistema)? ¿O sigue
entrando a mano y solo recibe mails? La respuesta cambia el tamaño de la pieza de varias semanas a
un par de días — **y la de los plazos depende de esta**, porque no hay a quién avisarle hasta que
exista una cuenta.

**C. Qué ve el proveedor del cómputo.** "La cotización le llega con el cómputo ya hecho" es la
ventaja del trato, pero también es información del usuario: las cantidades de materiales dicen
bastante sobre el tamaño y el tipo de la obra. ¿Va el cómputo completo, o solo los insumos del rubro
comercial de ese proveedor? Recomiendo lo segundo por default — al corralón de obra gruesa no le
sirve saber cuántos metros de porcelanato lleva, y es gratis no contárselo.

**D. Qué significa "baja".** ¿Deja de recibir pedidos pero sigue listado, o desaparece? Y la que más
importa: **¿sus precios viejos siguen contando en el promedio?** Si siguen contando, la baja no
resuelve el problema que la justifica — el catálogo se sigue pudriendo igual, solo que en silencio.
Mi lectura es que dar de baja tiene que sacar sus precios del promedio, y que eso es el verdadero
punto del mecanismo.

**E. La publicidad dentro de la solapa, contra PRO.** Un usuario que paga PRO y además ve publicidad
es una combinación que se siente mal, y es difícil de revertir una vez que el proveedor la compró.
¿La publicidad la ven todos, o solo los usuarios Free? No hace falta resolverlo ahora — pero sí
antes de venderla.

## 8. Lo único que se construyó hoy: la solapa dice "en construcción"

Pedido de Seba para la demo de esta semana: *"se la voy a mostrar a unos arquitectos y prefiero que
vean que va a estar, a que entren a un borrador."*

**Y era peor de lo que parecía.** Había *dos* mocks de Proveedores en el proyecto:

1. `lib/presentation/obra_detalle/tabs/proveedores_tab.dart` — un directorio con proveedores
   inventados ("Corralón El Valle", "Electrostock S.A."), con alta que guardaba en memoria y se
   perdía al salir. **No lo usaba nadie**: código muerto.
2. `_buildTabProveedores()` dentro de `presupuestos_screen.dart` — **esta es la que se veía en la
   app**, con otros tres proveedores inventados y totales inventados ("Corralón San Martín —
   $ 12.450.000").

Ahora hay un solo lugar: el archivo del punto 1 pasó a ser la pantalla de anticipo y el punto 2 la
devuelve. Dice lo que va a hacer la solapa **desde el lado del usuario** — pedir cotización sin
recargar nada, pedidos que van al proveedor del rubro correcto, y la posibilidad de elegir uno
puntual — y **no cuenta el trato con el proveedor**, que no es asunto del arquitecto que mira la
demo.

Cierra apuntando a Mat y MO, que sí está funcionando, para que la solapa vacía no sea un callejón.
