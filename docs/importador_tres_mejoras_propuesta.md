# Importador: tres mejoras — propuesta, sin construir

Escrito el 2026-09-15, a pedido de Seba, después de las cinco correcciones del commit `0af19f6`
(refresco, decimales, emparejado, encabezados de Bocián, unidades). **Nada de acá está construido.**
Las tres piezas son independientes: se pueden tomar en cualquier orden, o ninguna.

Las tres salen del mismo lugar: hoy el importador entiende bien la planilla, pero le pide al usuario
que confirme a mano cosas que la planilla ya dice.

---

## 1. Confirmación partida por partida

### El problema

Hoy cada fila se resuelve de a una: elegir del catálogo, crear como propia o descartar. Un
presupuesto de 60 partidas son 60 diálogos. Y el diálogo es el mismo aunque no haya nada que
decidir.

### Lo que propongo

**Que la app resuelva sola lo que puede, y pregunte solo por lo que no.** Al abrir la revisión se
clasifica cada fila en tres grupos, con un cartel arriba que los cuenta:

| Grupo | Qué es | Qué pasa |
|---|---|---|
| **Listas** | La descripción coincide con una partida del catálogo | Se resuelven solas, tildadas |
| **Nuevas** | No coincide con nada | Se crean en la carpeta de la obra, tildadas |
| **Dudosas** | Coincide con dos o más | **Quedan sin tildar, y se muestran arriba** |

Y un solo botón: **"Crear las N partidas"**.

La revisión pasa de ser un trámite obligatorio a una pantalla que **se puede mirar y aceptar**, o
abrir y corregir. Nada se pierde: toda fila sigue teniendo sus tres acciones, y destildar una la
deja afuera.

**La posibilidad de revisar no se toca; cambia el default.** Hoy el default es "nada está resuelto";
pasaría a ser "todo está resuelto salvo lo dudoso". El paso de diferencias antes de pisar (`0157`)
sigue igual y sigue siendo el último freno.

### Cómo se decide "coincide"

Reusando lo que ya existe, sin inventar un algoritmo nuevo:

- `insumo_nombre_normalizado()` (migración `0153`) ya es la definición canónica de "el mismo texto"
  en este proyecto — minúsculas, sin acentos, sin espacios de más. Se aplica a la descripción.
- Coincidencia **exacta normalizada** → lista.
- Coincidencia exacta con **más de una** partida del catálogo → dudosa.
- Sin coincidencia → nueva.

Deliberadamente **no** propongo coincidencia parcial ni por parecido en esta pieza. "Pared exterior"
y "Pared interior" se parecen mucho y son partidas distintas; una app que las confunde sola es peor
que una que pregunta. Si más adelante se quiere, entra como un cuarto grupo ("parecidas"), nunca
como resolución automática.

### Qué cuesta

Una pantalla, cero migraciones. El agrupado se calcula en el cliente con los datos que la pantalla
de revisión **ya carga**. La creación masiva es el mismo `crearPersonalizado` que hoy se llama de a
uno, en un `for`.

**El único punto delicado**: crear 60 partidas son 60 llamadas, y si la número 40 falla hay que
saber en qué quedó. Se resuelve mostrando el avance ("creando 40 de 60") y dejando las que fallaron
sin tildar, con su motivo — nunca un "no se pudo" que borre el trabajo de las 39 anteriores.

---

## 2. Unidad sugerida cuando la planilla no la trae

### El problema

Desde `0af19f6` la unidad sale de la planilla cuando existe — en las dos planillas de prueba,
siempre existe. Pero cuando no está, hoy se le pide al usuario partida por partida.

### Lo que propongo

**Una sugerencia, no una decisión.** El campo se prellena con la unidad más probable según la
descripción, y queda marcado como sugerido (en gris, con la palabra "sugerida"). El usuario lo
cambia escribiendo encima.

La regla es una lista de palabras, corta y legible, sin IA:

| Si la descripción menciona | Unidad sugerida |
|---|---|
| colocación de / provisión y colocación de, puerta, ventana, artefacto, bacha, inodoro, luminaria, tablero | **un** |
| pared, muro, revoque, revestimiento, pintura, piso, contrapiso, cielorraso, techo, cubierta, aislación, carpeta | **m2** |
| hormigón, excavación, relleno, viga, columna, base, movimiento de suelos | **m3** |
| cañería, caño, zócalo, cordón, cerco, zanja, cinguería, cumbrera | **ml** |
| hierro, alambre, clavo, cemento, cal, pegamento | **kg** |
| replanteo, obrador, limpieza, ayuda de gremio, dirección, baño químico | **gl** |

**El orden importa, y es lo que hace que funcione**: se busca de la más específica a la más general.
"Colocación de puertas" tiene que dar **un**, no m2 — por eso la fila de "un" se consulta primero. Es
justo el ejemplo que vos diste, y la planilla de Bocián lo tiene tal cual: *"Colocacion de puertas,
UND, 2"*.

### Lo que hay que aceptar

**Se va a equivocar, y está bien** — siempre que se vea que es una sugerencia. Lo que no puede pasar
es que entre una unidad inventada sin que se note: una partida de 120 m2 cargada como 120 un es un
presupuesto mal por un factor cualquiera. De ahí que vaya en gris y con la palabra escrita.

### Qué cuesta

Un archivo nuevo de unas 60 líneas y un cambio chico en el diálogo. Cero migraciones. Se prueba con
las descripciones reales de las dos planillas, que ya están en el repositorio.

---

## 3. Actualizar precios viejos con el índice CAC

### El problema

El presupuesto de Bocián dice **"24 de SEPTIEMBRE DE 2021"** y sus precios son de esa fecha ($4.350
el m2 de pared). Importado tal cual, entra a la obra un presupuesto que no sirve para cotizar nada.

### Lo que la app ya tiene

Bastante más de lo que esperaba:

- **La tabla `indices_cac`** (migración `0102`), una fila por mes, con **las tres series que hacen
  falta**: `general`, `materiales`, `mano_obra`. Exactamente la separación que pedís.
- **Las tres series ya se usan en serio**: la `0105` reparte cada partida entre materiales y mano de
  obra según su propio APU, y tiene resueltos los casos raros (partidas de precio manual → serie
  general; obra "sin materiales" → 100% mano de obra).
- **El criterio de qué hacer si falta un índice, ya decidido y escrito**: `factor_cac_obra` **corta
  con un error, nunca estima con el mes anterior**. Pedido tuyo, textual, cuando se diseñó la `0102`.

### Lo que falta, que es lo importante

**1. Los índices viejos no están cargados.** `indices_cac` tiene **7 meses: enero a julio de 2026**.
Para actualizar Bocián hace falta **septiembre de 2021**, que no está. Sin ese número no hay cuenta
posible — y por la regla de arriba, la app tiene que **decirlo**, no aproximar.

Cargar la serie del CAC desde 2018 son unas 100 filas × 3 series. Es trabajo de buscar y verificar
datos reales, no de programar. **Es el verdadero costo de esta pieza**, y conviene mirarlo antes de
escribir una línea de código: si la serie histórica no se consigue verificada, la pieza no existe.

**2. No hay una función de mes a mes.** `factor_cac_obra` calcula el factor de *una obra* contra
*hoy*, leyendo `obras.mes_base_cac`. Acá hace falta el factor entre dos meses cualesquiera. Es una
función hermana corta: mismo cuerpo, los dos meses por parámetro, el mismo error si falta alguno.

**3. Nadie carga el mes nuevo.** Los 7 meses entraron a mano, en la migración. Cada mes que pasa, la
tabla se atrasa sola. **Es la quinta pieza del proyecto que pide un scheduler** (van: notificaciones
tanda 3, canje de proveedores, avisos de pendientes, cotización del dólar, y ahora esto). En algún
momento conviene resolverlo una vez para todas.

### Lo que propongo

Un paso más en el importador, **antes** de la pantalla de revisión, y solo si se detecta una fecha
vieja:

1. **Detectar la fecha en la planilla.** Las dos de prueba la escriben en las primeras filas, en
   castellano: *"San Carlos de Bariloche, 24 de SEPTIEMBRE DE 2021"*, *"23 de MARZO de 2025"*. Una
   expresión regular sobre las primeras diez filas alcanza. **Siempre se muestra para confirmar**,
   nunca se toma sola: una planilla puede traer la fecha de otra cosa.
2. **Preguntar la serie**, con el default puesto: materiales, mano de obra o general. Bocián dice
   *"PRESUPUESTO POR MANO DE OBRA"* en su primera fila — se puede sugerir leyendo eso, y el usuario
   confirma.
3. **Mostrar la cuenta antes de aplicarla**, con un ejemplo concreto de la propia planilla:

   > Presupuesto de **septiembre 2021**, serie **mano de obra**.
   > Índice sep-2021 → sep-2026: **× 34,7**
   > Pared exterior: $4.350 → **$150.945** el m2
   >
   > [ Actualizar los precios ]  [ Dejarlos como están ]

4. **"Dejarlos como están" tiene que ser una salida real.** Alguien puede querer el presupuesto
   viejo tal cual, como registro.

**Qué se guarda**: el precio actualizado como precio de la partida, y en `datos_originales` el precio
original, el mes y el factor. Así siempre se puede contestar "¿de dónde salió este número?" — que es
la pregunta que va a aparecer el día que un cliente discuta un monto.

### Lo que no propongo

**Actualizar solo, sin preguntar.** Multiplicar los precios de alguien por 34 sin que lo pida es la
clase de cosa que hace desconfiar de una app para siempre.

---

## Si hay que elegir un orden

**1, después 2, después 3.** La 1 es la que más tiempo le ahorra al usuario y no depende de nada. La
2 es chica y además mejora la 1 (menos campos que completar en las nuevas). La 3 es la más valiosa de
las tres para presupuestos viejos, pero está bloqueada por un trabajo que no es programar:
**conseguir la serie histórica del CAC, verificada**. Ese es el primer paso de la 3, y conviene
hacerlo antes de decidir si la pieza entra.
