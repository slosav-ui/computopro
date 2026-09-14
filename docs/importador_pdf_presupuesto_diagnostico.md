# Importar el presupuesto desde PDF — diagnóstico (2026-09-14, sin código)

Pedido de Seba: cargar la obra real **Galpón Mix** en la app desde sus PDF. Son tres importadores
distintos —presupuesto, adicional y certificado— y se arranca por el de presupuesto, que es el que
los otros dos necesitan.

---

## 1. La buena noticia: el 80% ya está construido

Esto no es una pieza nueva. La Capa 2 del importador **ya dejó dicho exactamente esto**, y conviene
citarlo porque ahorra rediscutirlo:

> *"Todo el mapeo, la confirmación y la creación de partidas (el grueso de esta Capa 2) se reusa
> exactamente igual el día que se sume lectura de PDF/foto — lo único que cambia en la segunda tanda
> es qué llena `importaciones_items`, la capa de después no se entera de la diferencia."*

Lo que ya existe y no se toca:

| Pieza | Estado |
| --- | --- |
| `importaciones` + `importaciones_items` (`0080`) | Aplicadas. **`tipo_archivo` ya acepta `'pdf'`** |
| El bucket de Storage con su RLS | Aplicado |
| `RevisarImportacionScreen` (895 líneas) | Construida: revisar fila por fila, mapear a rubro/subítem, crear partidas |
| La función SQL de confirmación, atómica | Construida |
| El gate de PRO | Construido |

**El importador de PDF es, literalmente, un llenador nuevo de `importaciones_items`.** Todo lo que
viene después ya funciona y ya se probó con Excel.

## 2. "Sin IA" es cierto, pero no quiere decir fácil

Que estos PDF se lean sin un modelo de visión es verdad y es la decisión correcta — son PDF de texto,
no fotos escaneadas. Pero conviene separar dos cosas que suenan parecido:

- **Extraer el texto de un PDF**: resuelto por una librería.
- **Reconstruir una tabla a partir de ese texto**: el trabajo real.

Un PDF no tiene celdas. Lo que se extrae son **fragmentos de texto con su posición (x, y)**, y armar
"esta línea es una partida con estos cinco campos" es agruparlos por coordenada. En Excel una celda
es una celda; acá hay que deducir las columnas de dónde caen los números en la hoja.

**Consecuencia que define el alcance: un parser determinístico es un parser de UN formato.** No lee
"cualquier presupuesto en PDF" — lee el que exporta el programa con el que se hizo ese presupuesto.
Si todos los presupuestos de Seba salen del mismo lado, eso es perfectamente suficiente y es la mejor
relación esfuerzo/resultado que hay. Si van a venir PDF de terceros con formatos distintos, el
enfoque no escala y ahí sí aparece el modelo de visión.

**Primera pregunta del diagnóstico, entonces: ¿con qué se genera ese PDF?** (Excel exportado, un
software de cómputo, una plantilla propia.) La respuesta cambia el parser entero.

## 3. Dónde corre, y el problema de librería

La Capa 2 movió el parseo de Excel **al cliente** y sacó la Edge Function, con un argumento explícito:
sin IA no hay clave que proteger y sin límite de Free no hay nada que hacer cumplir del lado
servidor, así que no valía la pena sostener una segunda pieza de infraestructura. **Ese argumento
sigue valiendo tal cual para el PDF.**

Pero acá aparece algo que con Excel no pasaba: **el proyecto puede generar PDF y no puede leerlos.**
`pdf` y `printing`, que ya están en el `pubspec`, son de generación. Para extraer texto en Dart las
opciones son pocas y ninguna es obvia:

- una librería Dart de extracción — hay, pero conviene mirar la licencia antes de casarse con una;
- **pdfium** vía un plugin de rendering, que trae extracción de texto pero suma otro plugin nativo;
- **del lado del servidor**, en la Edge Function que ya está escrita como referencia, donde el
  ecosistema JS de PDF es mucho más maduro.

Es la decisión técnica de fondo de esta pieza, y **no la puedo cerrar sin ver el PDF**: si el texto
sale limpio y ordenado, cualquiera de las tres sirve y gana la más barata (el cliente). Si sale
desordenado y hay que pelear con coordenadas, el ecosistema del servidor vale la molestia.

## 4. Ojo: los tres importadores no son tres veces lo mismo

Vale aclararlo antes de que el orden "presupuesto, adicional, certificado" haga pensar que son tres
tandas iguales:

- **Presupuesto** → llena `importaciones_items` y termina creando `obra_subitems`. **Reusa todo lo
  construido.** Es el que se puede hacer casi enteramente con lo que hay.
- **Adicional** → no es una lista de partidas para mapear: es **una fila de `modificaciones_obra`**
  con su monto y su descripción, que después pasa por su propio circuito de aprobación. No pasa por
  `importaciones_items` ni por la pantalla de revisión.
- **Certificado** → tampoco: es **avance por partida** sobre partidas que ya existen
  (`certificado_subitems_avance`), y además tiene que caer sobre el presupuesto congelado correcto.
  Es el más delicado de los tres, porque un error acá mueve plata.

O sea: el de presupuesto es el barato y los otros dos son piezas propias. **Y el orden que elegiste
es el correcto**: sin las partidas cargadas, un certificado no tiene sobre qué apoyarse.

## 5. Lo que hay que decidir antes de escribir

**A. ¿Con qué se genera el PDF?** Ver §2. Es lo primero.

**B. ¿Qué pasa con las partidas que no matchean el catálogo?** Ya está resuelto para Excel —la
pantalla de revisión deja mapear a un subítem del catálogo o crear la partida con descripción
libre— así que la pregunta real es si el PDF trae códigos de rubro/partida que permitan un mapeo
automático o si va todo a mano, fila por fila. Con 97 partidas, la diferencia entre las dos cosas es
una tarde.

**C. ¿El precio importado es manual, como en Excel?** La Capa 2 cerró que sí, y con un motivo fuerte
(§4 de ese doc). Recomiendo **no reabrirlo**: un precio que viene de un PDF es tan "de afuera" como
uno que viene de una planilla.

**D. ¿El PDF trae el ajuste pactado?** Si el presupuesto en PDF está cotizado en 78.759,38 pero el
contrato dice 75.609,01, **importar el PDF sin más carga la obra al precio cotizado**. Las dos piezas
se cruzan: conviene decidir si el importador pregunta por el ajuste al confirmar, o si se carga
después a mano. Ver `docs/descuento_pactado_horizonte.md`.

**E. ¿Se importa sobre una obra nueva o una existente?** La Capa 2 dejó `obra_id not null`: se
importa sobre una obra ya elegida o recién creada, nunca "suelta". Para Galpón Mix eso significa
crear la obra primero y después importarle el presupuesto.

## 6. Lo que necesito para escribir el parser

**El PDF.** Un parser determinístico se escribe contra un formato concreto, y no lo puedo adivinar.

Lo más práctico: poner el del presupuesto en `supabase/seed_staging/` (esa carpeta está fuera de git,
así que no se sube a ningún lado) y lo leo desde ahí. Con eso puedo ver la estructura real —dónde
caen las columnas, cómo vienen los números, si hay subtotales por rubro, cómo se separan los
decimales— y recién ahí decidir §3 y escribir algo que funcione con **ese** archivo y no con uno
imaginario.

Si preferís no poner el archivo en el repo ni siquiera en una carpeta ignorada, la alternativa es
pegarme el texto de una página tal como sale de cualquier extractor. Alcanza para ver la estructura.
