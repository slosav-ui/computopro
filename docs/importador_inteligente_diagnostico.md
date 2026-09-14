# Importador inteligente — diagnóstico (2026-09-14, sin código)

Replanteo del importador. El enfoque anterior —un lector programado contra el PDF de Seba— se
descarta por un motivo de producto, no técnico:

> *"No te van a mandar el ejemplo todos los usuarios de cómo trabajan para que los programes en
> particular para cada uno. Tenemos que hacer algo general para todos."*

**Y alcanza también al importador de Excel que ya está construido**: `ExcelParser._campos` reconoce
encabezados por lista de sinónimos (`descripcion`, `detalle`, `concepto`, `tarea`, `designación`…).
El que llame a su columna de otra forma no entra, y el que ponga el precio antes que la cantidad
tampoco cambia nada porque se busca por nombre, no por posición — pero el que no ponga encabezados,
o los ponga en una fila que no es la primera reconocible, queda afuera.

**La conclusión que hay que corregir del diagnóstico anterior:** decir que "el PDF con texto no
necesita IA" era mirar el problema equivocado. **La IA no hace falta para leer el texto: hace falta
para entenderlo.** Extraer caracteres de un PDF lo resuelve una librería; saber cuál de esas columnas
es la cantidad y cuál el precio unitario, en una planilla que nadie programó, no.

---

## 1. Cómo queda el mecanismo único

### Lo que NO cambia (y es la mayor parte)

Sigue valiendo lo que la Capa 2 dejó dicho: *"lo único que cambia es qué llena
`importaciones_items`"*. O sea que se conservan enteros:

- `importaciones` + `importaciones_items` con su RLS y su bucket (`0080`);
- **`RevisarImportacionScreen`** — mapear al catálogo, crear la partida como propia, descartar una
  fila, buscar rubro y subítem;
- la función SQL de confirmación, atómica;
- el gate de PRO.

### Lo que cambia: tres puertas, un solo extractor

```
   Excel  ──►  parser determinístico (el que ya existe)
                      │ ¿reconoció encabezados?
                 sí ──┤                        └── no ──┐
                      ▼                                 ▼
              importaciones_items  ◄──────────  EXTRACTOR (modelo)
                      ▲                                 ▲
   PDF    ────────────┼─────────────────────────────────┤
   Foto   ────────────┴─────────────────────────────────┘
                      │
                      ▼
            RevisarImportacionScreen  ──►  confirmar  ──►  obra_subitems
```

**El parser de Excel no se tira: pasa a ser el camino rápido.** Si los encabezados coinciden, resuelve
gratis y al instante, sin red y sin costo. Si no coinciden —que hoy es un callejón sin salida— la
misma planilla se manda al modelo. Es una decisión de dos líneas en el punto donde hoy
`_detectarEncabezados` devuelve `null`.

**El extractor tiene una sola salida**, la misma para las tres puertas: las filas de
`importaciones_items` que ya existen (`rubro_texto`, `descripcion_texto`, `unidad_texto`, `cantidad`,
`precio_unitario`, `datos_originales`). La capa de después no se entera de por dónde entró.

### Dónde corre: ahora sí, del lado del servidor

La Capa 2 movió el parseo al cliente con un argumento explícito, y **el mismo argumento ahora dice lo
contrario**. Textual de `excel_parser.dart`:

> *"El motivo real por el que valdrá la pena volver a un servidor en la segunda tanda es otro: ahí sí
> hay una clave de un modelo de visión que proteger y un costo por documento que controlar."*

Es exactamente el caso. Una clave de API en el binario de una app se extrae en minutos, y sin
servidor no hay dónde poner un tope de gasto. La Edge Function ya está escrita como referencia
(`supabase/functions/importar-excel/`), sin desplegar.

---

## 2. Qué proveedor y qué cuesta

### El número por documento

Supuestos: un presupuesto de **25 partidas en PDF de 2 páginas**, y una **foto de una hoja impresa**.
Para un PDF, el modelo recibe el texto extraído **y** la imagen de cada página (así no pierde la
estructura de columnas, que es justamente lo que importa acá).

| | Entrada | Salida | **Haiku 4.5** | **Sonnet 5** |
| --- | --- | --- | --- | --- |
| Presupuesto PDF, 25 partidas, 2 pág. | ~7.000 tok | ~1.200 tok | **US$ 0,013** | **US$ 0,026** |
| Foto de una hoja impresa | ~3.200 tok | ~1.200 tok | **US$ 0,009** | **US$ 0,018** |

Precios: Haiku 4.5 **US$ 1 / 5** por millón (entrada/salida); Sonnet 5 **US$ 2 / 10**; Opus 5
**US$ 5 / 25** (≈ US$ 0,065 por presupuesto, si algún día hace falta para un caso difícil).

**En plata: entre uno y tres centavos de dólar por documento.** Cargar la obra entera de Seba
—presupuesto, un adicional y dos certificados— cuesta **menos de diez centavos**.

> Las cuentas de tokens son estimadas (el peso de la imagen de página depende de la resolución).
> Antes de comprometer un número en la UI o un tope de gasto, se miden exactos con el endpoint de
> conteo de tokens sobre un documento real — no hace falta adivinar.

### Los descuentos que existen, y por qué casi no aplican

- **Batch: 50% de descuento**, pero es asincrónico (puede tardar horas). Para alguien que subió un
  PDF y está esperando la pantalla de revisión, no sirve. Descartado.
- **Caché de prompt**: descuenta el prefijo estable (las instrucciones y el esquema), que acá son
  ~700 tokens — por debajo del mínimo cacheable. **No es la palanca de este caso**: lo caro es el
  documento, y el documento es distinto siempre.

### Qué proveedor

**A uno o dos centavos por documento, la elección de proveedor no es una decisión de costo.** Aun con
100 obras por mes y 4 documentos cada una, son 400 documentos: entre **US$ 4 y US$ 10 al mes**. Un
proveedor 3 veces más barato ahorra unos dólares mensuales; no es lo que define nada.

Lo que sí define:

1. **Que lea PDF y foto sin un paso de extracción aparte** (ver §3).
2. **Que garantice el esquema de salida**, para que la respuesta no haya que parsearla a mano ni
   validarla con miedo.
3. **Un solo proveedor y una sola clave** que proteger, en un proyecto sostenido por una persona.

**Recomiendo Claude, con Haiku 4.5 como caballito de batalla y Sonnet 5 cuando el documento venga
difícil** (foto torcida, tabla rara, o cuando el propio extractor devuelva confianza baja). Los tres
puntos de arriba los cumple, el PDF entra nativo, y el costo de subir a Sonnet en el 10% de los casos
es despreciable contra el ahorro de que la pantalla de revisión tenga menos para corregir.

Gemini en su línea Flash es más barato por token (del orden de US$ 0,30 / 2,50 por millón) y es una
alternativa legítima si algún día el volumen cambia de orden. A este volumen, elegir por precio sería
optimizar centavos.

---

## 3. ¿Puede leer las tres formas?

**PDF y foto: sí, directo, sin paso previo.** El PDF va como documento (base64, hasta 32 MB y 100
páginas en modelos de 200K de contexto — un presupuesto de obra no se acerca) y la foto va como
imagen. **No hace falta extraer el texto primero**, que era justamente el problema técnico que trababa
el enfoque anterior: el proyecto no tiene con qué leer PDF en Dart, y ahora no lo necesita.

**Excel: no, y no hace falta.** La API no recibe `.xlsx`. Pero el proyecto **ya abre el archivo** con
el paquete `excel`, así que cuando los encabezados no se reconocen alcanza con volcar las filas de la
hoja a texto plano y mandarlas como texto. Es la entrada más barata de las tres.

O sea: **un solo prompt y un solo esquema de salida, con dos formas de adjuntar** — documento/imagen
para PDF y foto, texto para Excel. No son tres integraciones.

---

## 4. Qué pasa cuando se equivoca

Se va a equivocar, y no en lo que uno esperaría: los errores típicos no son "no entendió el
documento" sino **un número mal leído** (410,96 → 41096 si se come la coma) o una columna cruzada en
una fila suelta.

### El hallazgo: la pantalla de revisión NO alcanza

Revisada `RevisarImportacionScreen` contra este caso, cubre bien una mitad y **no cubre la otra**:

| El modelo se equivocó en... | ¿Se puede arreglar hoy? |
| --- | --- |
| A qué subítem del catálogo corresponde | **Sí** — "Elegir del catálogo" |
| Una partida que no está en el catálogo | **Sí** — "Crear como propia" |
| Una fila que no era una partida (subtotal, título) | **Sí** — "Descartar" |
| **La cantidad** | **NO** |
| **El precio unitario** | **NO** |
| **La descripción** | **NO** |

`cantidad` y `precio_unitario` se muestran como **texto de solo lectura**, y
`ImportacionesRepository` **no tiene ningún método para actualizar un ítem** — solo resolver,
desresolver, descartar y confirmar. Con el parser de Excel eso era tolerable (si la celda decía 410,96
el parser leía 410,96). **Con un modelo de por medio deja de serlo.**

Entonces falta, y es lo que hay que construir además del extractor:

1. **Editar cantidad, precio y descripción en la fila**, con su método en el repositorio.
2. **Confianza por fila**, devuelta por el extractor, para **ordenar las dudosas primero**. Con 97
   partidas, revisar de arriba a abajo es lo que hace que nadie revise.
3. **El texto original a la vista** al lado del valor interpretado. `datos_originales jsonb` ya existe
   para eso y hoy solo guarda el nombre de la hoja.
4. **El control de que cierre**: sumar las partidas y compararlo contra el total que dice el
   documento. Si no da, avisar antes de confirmar. Es la red que atrapa el número mal leído que nadie
   miró.

---

## 5. El segundo trabajo del importador: avisar cuando los números no cierran

Esto salió de los PDF reales y **un lector programado no lo habría encontrado nunca**.

> El presupuesto se cotizó en **USD 78.759,38** y el primer certificado se armó sobre **USD
> 75.609,01**. La diferencia es un **4% parejo en todas las partidas**: el replanteo pasa de 410,96 a
> 394,52; la platea, de 10.615,49 a 10.190,87.
>
> **Ese descuento no está declarado en ninguna parte del documento.** Se detecta comparando números.

Es una negociación real: se presentó el presupuesto, el cliente pidió una rebaja, se acordó el 4%.

**Entonces el importador tiene dos trabajos, no uno**: leer las partidas, y **contrastar lo leído
contra lo que ya está cargado**. Cuando importe un certificado y detecte una diferencia **pareja**
—mismo porcentaje en todas las partidas, no una diferencia dispersa— tiene que preguntar: *"los
precios de este certificado están un 4,00% por debajo del presupuesto congelado. ¿Se pactó un ajuste?"*
Y si se confirma, cargarlo como tal, con el porcentaje visible.

La diferencia entre **pareja** y **dispersa** es la que hace útil el aviso: pareja es una
negociación; dispersa es un error de lectura o un certificado de otra obra. Son dos mensajes
distintos.

Conecta directo con `docs/descuento_pactado_horizonte.md`: **son dos caminos para el mismo dato** —
cargarlo a mano al firmar, o que el importador lo detecte. El dato termina en el mismo lugar.

---

## 6. El orden

**El mecanismo se construye una vez; los destinos son tres.** Por eso no conviene hacerlos juntos:
el extractor y la revisión se comparten, pero cada destino tiene su propia validación y su propia
forma de fallar.

| Orden | Destino | Qué suma | Por qué ahí |
| --- | --- | --- | --- |
| **1** | **Presupuesto** → `obra_subitems` | El extractor, las tres puertas, la edición de valores y la confianza por fila | Es el único que reusa todo lo construido, y **los otros dos no existen sin él**: sin partidas cargadas no hay a qué imputar un certificado |
| **2** | **Certificado** → `certificado_subitems_avance` | El contraste contra el presupuesto congelado y **la detección del ajuste pactado** | Va segundo y no tercero: es donde aparece el 4%, y es lo que hace falta para cargar la obra real completa |
| **3** | **Adicional** → `modificaciones_obra` | Casi nada: una fila con monto y descripción | Es el más chico y el más independiente. No pasa por `importaciones_items` ni por la pantalla de revisión |

**El certificado antes que el adicional** invierte el orden que se venía manejando, y el motivo es
concreto: el adicional es una fila suelta que se puede cargar a mano en dos minutos, y el certificado
es donde está el trabajo interesante y el hallazgo del ajuste.

---

## 7. Que cargar la obra real no requiera quince pasos

Seba va a cargar Galpón Mix con el profesional y el cliente reales y su socio como constructor. **Esa
es la mejor verificación posible de toda la app**, no solo del importador — y el diseño no la tiene
que hacer imposible.

El camino completo, tal como queda:

1. crear la obra e invitar a los tres;
2. subir el PDF del presupuesto → revisar → confirmar;
3. presentar y congelar el presupuesto;
4. subir el certificado → **la app detecta el 4% y pregunta** → confirmar el ajuste;
5. el resto del circuito, que ya está construido y probado.

**Son cinco pasos y ninguno es de relleno.** El único que se puede perder de vista es el 3: si se
importa el presupuesto y no se congela, el certificado del paso 4 no tiene contra qué compararse — y
ahí el aviso del ajuste no puede existir. Vale la pena que la pantalla lo empuje.

---

## 8. El cupo: 5 lecturas por usuario y por mes (cerrado 2026-09-14, migración `0145`)

Decisión de Seba, tomada **antes de escribir una línea** y con el motivo explícito: *"el costo lo
paga mi cuenta y no quiero que se dispare mientras la app todavía no se monetiza… el límite tiene
que estar desde el principio, no agregarse después."*

El razonamiento vale más que el número. Un tope que se agrega después **siempre llega tarde**: el
día que se nota que hace falta es el día en que ya se gastó. Y el importador es exactamente la pieza
donde eso puede pasar rápido y en silencio, porque el costo no lo dispara Seba sino cualquier
usuario probando.

### Lo que NO es

§2.5 de Capa 1 había diseñado un límite mensual **para separar Free de PRO**, y Capa 2 lo eliminó al
volver el importador exclusivo de PRO: *"el gate es simplemente `perfiles.es_pro`"*.

**Este no es ese límite volviendo.** Es otro, con otro motivo y otro alcance:

| | Límite de Capa 1 (eliminado) | Cupo de la `0145` |
| --- | --- | --- |
| Para qué | Diferenciar planes | Proteger la cuenta que paga el modelo |
| A quién aplica | Solo Free | **A todos, PRO incluido** |
| Cuándo se saca | Nunca (era el producto) | Cuando el costo se traslade al usuario |

Vale dejarlo escrito para que dentro de seis meses no se lea como que se reabrió una decisión
cerrada. No se reabrió: son dos cosas distintas que se parecen en la forma.

### Dónde se aplica, y por qué ahí

**En la base, llamado desde la Edge Function, antes de mandarle el documento al modelo.** Las tres
partes de esa frase importan:

- **En la base** porque en el cliente un tope es una sugerencia.
- **Antes** y no después, porque si se marcara al terminar, el documento número seis ya se pagó. Es
  la diferencia entre un tope y una estadística.
- **La misma operación verifica y marca**, para que no haya hueco entre las dos.

### Qué consume cupo y qué no

**Solo las lecturas que gastan plata.** El parser determinístico de Excel corre en el cliente, no
llama a ningún modelo y **no consume nada** (`importaciones.uso_ia` queda en `false`).

Eso no es una concesión técnica: es lo que hace que el mensaje de "llegaste al límite" **pueda
ofrecer una salida real**. Sin eso sería una pared.

Y un reintento tampoco consume: si la lectura falla por red o el modelo devuelve algo inválido,
volver a intentar sobre el mismo documento no cobra dos veces. **El cupo es por documento, no por
intento** — de lo contrario un error de la app se le descontaría al usuario.

### El aviso

Seba pidió que fuera claro. Dice las tres cosas que hacen falta, en ese orden:

> *Llegaste a las 5 lecturas con IA de este mes. El contador se reinicia el 01/10/2026. Mientras
> tanto podés importar una planilla de Excel con encabezados reconocibles (descripción, cantidad,
> precio unitario): esa lectura no consume cupo.*

Qué pasó, cuándo se arregla solo, y qué se puede hacer mientras tanto. **Y se muestra antes de elegir
el archivo, no después de subirlo** — para eso existe `cupo_importaciones_ia()`, que devuelve cuántas
quedan y la fecha exacta de reinicio.

Esa fecha la calcula la base **en hora de Argentina**, no en UTC: es la primera vez que el proyecto
lo necesita, porque los plazos de la `0131` son intervalos rodantes desde un instante y no les
importa el huso, pero un mes calendario sí. Un 31 a las 22:00 de Buenos Aires ya es día 1 en UTC, y
el contador se reiniciaría un día antes de lo que dice el aviso.

### Lo que se mide, para que el número no quede congelado por inercia

El 5 salió de una estimación (entre uno y tres centavos por documento, §2). La `0146` guarda
`modelo`, `tokens_entrada` y `tokens_salida` en cada importación, y `consumo_ia_del_mes()` los
agrega. **El día que haya que decidir si el cupo sube, la respuesta sale de una consulta y no de una
cuenta de servilleta.**

No se guarda el costo en dólares a propósito: un precio guardado envejece cuando cambia la tarifa, y
entonces la columna miente sobre algo que ya pasó. Los tokens son un hecho; el precio es una tabla de
afuera.


---

## 9. Lo construido: el importador de presupuesto (2026-09-14)

Migraciones `0145` y `0146` aplicadas y verificadas. Lo que sigue es el código, y **el orden en que
hay que probarlo está al final**.

### La Edge Function: `supabase/functions/leer-documento/index.ts`

Un solo extractor para las tres puertas. El orden de las operaciones es la parte que importa:

1. **lee la importación con la auth del usuario** — la RLS de la `0080` decide si puede o no, y no
   hay un segundo chequeo de autoridad en el archivo (sería una regla que se puede desincronizar de
   la primera);
2. **consume el cupo** — antes de gastar. Si fuera después, el documento número seis ya está pagado
   cuando se lo rechaza;
3. **recién ahí llama al modelo.**

Usa **dos clientes de Supabase a propósito**: el del usuario para todo, y uno de servicio para una
sola cosa —llamar al cupo, que está revocado a `authenticated` justamente para que el cliente no
pueda saltearlo—. Es el privilegio más chico que alcanza.

**La consigna del modelo es la pieza, más que el código.** Cada párrafo está por un error concreto:
qué no es una partida (un subtotal de rubro entra sin ruido y después infla el presupuesto), cómo se
leen los números en Argentina (el punto es miles y la coma decimal, al revés de lo que el modelo ve
la mayor parte del tiempo — de ahí 410,96 → 41096), y **no inventes** (un modelo completa huecos con
algo plausible, que es el modo de fallar más difícil de detectar mirando la pantalla).

Sobre la confianza, la consigna dice algo que vale repetir: *"es mejor decir media de más que alta
de más. Una fila marcada alta que estaba mal es el peor resultado posible, porque nadie la va a
mirar."*

**Desplegar a mano**, como las migraciones:

```
supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
supabase functions deploy leer-documento
```

### La pantalla de importación: `importar_presupuesto_screen.dart`

Reemplaza a `importar_excel_screen.dart`, que se borró. Un solo lugar para las tres puertas:

- **Excel** intenta primero el parser determinístico. Si reconoce los encabezados, termina ahí:
  gratis, instantáneo y sin tocar el cupo. **Si no los reconoce, no es un error — es la otra
  puerta**, y se ofrece leerlo con IA. Se *ofrece*: gasta una lectura y esa decisión es del usuario.
- **PDF y foto** van directo al modelo, con el aviso de que consume una lectura **antes** de
  consumirla. Un costo que se descubre después de gastarlo no es una decisión de nadie.
- **"Sacar una foto"** con la cámara, además de elegir un archivo.

El cupo se muestra arriba de todo, desde que se abre la pantalla. Cuando se agotó **cambia de tono
pero no bloquea nada**: el Excel con encabezados reconocibles sigue entrando, y esa es la salida que
hace que el límite no sea una pared.

### La pantalla de revisión: lo que el diagnóstico marcó como el hallazgo

§4 decía que `RevisarImportacionScreen` no alcanzaba. Las cuatro cosas que faltaban, ahora están:

| Faltaba | Ahora |
| --- | --- |
| Corregir `cantidad`, `precio_unitario`, `descripcion` | Botón **"Corregir valores"** por fila, con diálogo |
| Saber de qué filas dudar | Las filas se **ordenan por confianza**: lo dudoso primero |
| El texto original a la vista | *"En el documento: …"* debajo de cada fila |
| Que la suma cierre contra el total | Cartel arriba de todo, con la diferencia en plata y en % |

Tres decisiones dentro de eso que conviene tener escritas:

**El orden por confianza no rompe el Excel.** Sin confianza todas las filas empatan, así que una
importación de Excel se sigue viendo en el orden del archivo. El orden original nunca se pierde:
sigue escrito en `orden` y se usa como desempate.

**Los números del diálogo se leen con `ParserNumeroAr`**, que ya existía en el proyecto y es la única
lógica de coma/punto que hay. Acá importa más que en ningún otro lado: el usuario está corrigiendo
justamente un número que se leyó mal, y sería absurdo que la corrección se guardara mal por la misma
clase de error. El diálogo muestra el valor interpretado mientras se escribe, y avisa en el caso
genuinamente ambiguo ("1.500" puede ser mil quinientos o uno con medio).

**Dejar un número vacío lo borra.** Una partida sin precio es una partida sin precio, y es mejor que
un número inventado — el mismo criterio que la consigna le da al modelo.

### El control del total, y por qué es el que más vale

Es **la única verificación de la pantalla que no se apoya en la lectura que está bajo sospecha**.
Todo lo demás —la confianza, el texto original, la descripción— sale del modelo. Esto sale de
comparar dos números que tienen que dar igual.

Tres estados, y los tres dicen algo:

- **coincide**: aclara que eso no garantiza que cada partida esté bien;
- **no coincide**: dice cuánto sobra o falta, en plata y en porcentaje;
- **el documento no traía total**: lo dice, en vez de callarse. Que no haya aviso no puede
  confundirse con que está todo bien.

La tolerancia es medio por ciento con piso de un peso: un presupuesto de 97 filas nunca cierra al
centavo porque los redondeos por partida se acumulan.

### Cómo probarlo, en orden

1. **El camino gratis primero**, que es el que no puede romperse: importar un Excel con encabezados
   reconocibles. Tiene que entrar igual que siempre, sin tocar el cupo
   (`select * from cupo_importaciones_ia();` no se mueve) y sin carteles nuevos.
2. **El PDF real de Galpón Mix.** Acá se mira todo junto: cuántas partidas sacó, si el total cierra,
   y **si las filas que marcó para revisar eran efectivamente las dudosas**. Esto último es lo que
   dice si la consigna sirve.
3. **Una foto de una hoja**, sacada con el teléfono y torcida a propósito. Es el caso peor y el que
   más dice sobre si la confianza está bien calibrada.
4. **Corregir un número** y confirmar que queda guardado al recargar.
5. **El cupo, al final**: repetir hasta llegar a cinco y ver el aviso. Leerlo completo — es el texto
   que va a ver un usuario que no sabe qué pasó.

Y un punto de atención para el paso 2: si el PDF de Galpón Mix está cotizado en USD 78.759,38 pero el
contrato dice 75.609,01, **el importador carga el precio cotizado**, que es lo correcto. El 4% es
otra pieza y entra por otro lado (ver `docs/descuento_pactado_horizonte.md`).


---

## 10. Se sale sin importador de PDF (2026-09-14)

**Decisión de Seba, y el motivo es de producto, no de presupuesto:**

> *"El de Excel ya funciona, no cuesta nada, y cubre al que tiene su planilla, que es la mayoría."*

Vale registrar la forma del razonamiento porque es reusable: **la pregunta no fue "¿está terminado?"
sino "¿a quién deja afuera si no sale?"**. La respuesta —al que no tiene su cómputo en una planilla—
es una minoría hoy, y para esa minoría el costo de esperar es bajo. Lo que sí tenía costo era salir
con una función que depende de una cuenta paga que todavía no se justifica.

La lectura con IA **queda construida entera y apagada**, con un interruptor:
`lecturaConIaDisponible` en `importar_presupuesto_screen.dart`. Apagada, la pantalla no ofrece lo
que no puede cumplir: solo acepta `.xlsx`/`.xls`, sin cámara, sin cupo a la vista, y un Excel que el
parser no entiende termina en un mensaje que dice **qué arreglar en la planilla** en vez de una
oferta de leerlo con IA. Es el mismo criterio que la solapa Proveedores: mejor "no está" que un
borrador que falla.

Para prenderlo hacen falta **las dos cosas o ninguna**: el interruptor en `true` *y* la Edge
Function desplegada. Prenderlo sin desplegar deja la pantalla ofreciendo un error, que es
exactamente lo que apagarla evita.

### Cuándo se retoma, y los dos caminos

**La condición que lo dispara: que la app genere ingresos.** No es una fecha ni un hito técnico —
está construido y anda; lo que falta es que el costo tenga de dónde salir.

Ahí hay dos caminos, y no son excluyentes:

| | Para qué sirve | Límite |
| --- | --- | --- |
| **Pagar la API de Anthropic** | El camino de producción: sirve para cualquier documento, de cualquier usuario | Cuesta plata desde el primer documento (1-3 centavos, §2) |
| **Probar con Gemini (capa gratuita)** | **Validar que el importador sirve**, sin pagar nada | **Solo documentos propios** — ver abajo |

**Gemini es para validar, no para producir.** Es una distinción que conviene no perder: sirve para
contestar "¿el extractor lee bien un presupuesto real?" sin gastar un peso, y esa pregunta se puede
contestar con los PDF de Galpón Mix, que son de Seba.

### Por qué cambiar de proveedor no invalida nada de lo construido

Vale decirlo porque es el riesgo obvio de leer esta sección sola. §2 ya había concluido que **a uno a
tres centavos por documento, la elección de proveedor no es una decisión de costo**: lo que decide es
que lea PDF y foto sin paso previo, que garantice el esquema de salida, y que haya una sola clave que
proteger. Gemini cumple las tres.

Y el cambio toca **un solo archivo**: `supabase/functions/leer-documento/index.ts`, y dentro de él
solo la llamada HTTP y la forma de la respuesta. No se mueven las migraciones, ni el cupo, ni la
pantalla de importación, ni la de revisión. **La consigna —que es la pieza real, no el código— se usa
tal cual**, porque no dice nada específico de un proveedor: dice qué es una partida, cómo se leen los
números en Argentina y que no invente.

O sea: lo construido esta semana **no es trabajo tirado si el proveedor cambia**, y ese era el punto
de que el extractor fuera un solo archivo detrás de una interfaz chica.

### La restricción que NO se puede relajar

> *"Probar con Gemini para validar — pero la capa gratuita de Google entrena con lo que recibe,
> así que no sirve para documentos de clientes reales."*

**Esto es una condición de uso, no una precaución.** La capa gratuita de Gemini usa el contenido
enviado para mejorar los modelos; la paga no. Mandar el presupuesto de un cliente por ahí sería
entregar información comercial ajena a un tercero sin que el cliente lo sepa — y el presupuesto de
una obra es exactamente el tipo de documento que nadie quiere que circule.

**Consecuencia práctica que hay que tener presente antes de que esto salga de la etapa de prueba:**

- **Para validar contra los PDF de Galpón Mix, la capa gratuita alcanza y está bien**: son documentos
  de Seba.
- **En el momento en que un usuario que no es Seba suba un documento, la capa gratuita deja de ser
  una opción.** No es un umbral de volumen ni de costo: es que el documento deja de ser propio.

Y notar que eso encaja solo con la condición de retomar: **si lo que destraba la pieza son ingresos,
para entonces hay usuarios que no son Seba** — o sea que el camino de producción es el pago, y
Gemini se queda del lado de la validación previa. Los dos caminos no compiten: uno contesta si vale
la pena, el otro lo pone en manos de la gente.

Conviene que eso quede escrito acá y no solo en la cabeza, porque el salto de "estoy probando" a
"hay alguien más usándolo" no avisa. **El cupo de la `0145` sigue siendo el mismo mecanismo y no
cambia** — si el proveedor pasa a tener costo, el tope ya está puesto, que era el punto de ponerlo
desde el principio. Es lo único de esta pieza que sigue vivo con la IA apagada: las migraciones
están aplicadas y las columnas existen, simplemente no se llenan hasta que haya lecturas.

### Qué hay que mirar en la prueba, más allá de si anda

Lo mismo que §9 paso 2, y con más razón cuando se compara un proveedor contra otro: no cuántas
partidas sacó, sino **si las filas que marcó para revisar eran efectivamente las dudosas**. Un
extractor que saca las 97 partidas pero marca todo "alta" es peor que uno que saca 90 y señala bien
las 7 que falló.
