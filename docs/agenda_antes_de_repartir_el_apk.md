# Antes de repartir el APK — agenda (2026-09-14)

Hasta hoy este requisito estaba **mencionado en cinco documentos y consolidado en ninguno**
(`confianza_precios_diseno.md`, `proveedores_digitales_bariloche.md`,
`vinculacion_dispositivos_decisiones.md`, `invitaciones_diseno_datos.md`, `CLAUDE.md`), siempre de
paso y siempre como "está en la misma lista que...". Esta es esa lista.

**Es la única pieza del proyecto que no se destraba escribiendo código**, y por eso es la que más
fácil se posterga. También es la que tiene fecha: el APK se reparte a colegas, y una vez repartido
no se puede des-repartir.

**Y la fecha se adelantó (2026-09-14): es esta semana, antes de que los arquitectos vean la app.**
Mostrar no es repartir —una demo en el teléfono de Seba no deja el APK en manos de nadie— pero es el
primer momento en que gente de afuera ve el trabajo, y el activo que se expone es el mismo: la
curación técnica, no el código. El orden correcto es iniciar el depósito **antes** de la muestra, no
después.

---

## 1. Depósito de obra inédita en la DNDA — **en marcha esta semana**

Dirección Nacional del Derecho de Autor. Es el registro que da fecha cierta sobre el código tal como
está hoy.

**Por qué importa acá y no es un trámite genérico:** lo que protege no es la idea de una app de
cómputo —eso no se protege— sino **la expresión concreta**, que en este proyecto es justamente donde
está el trabajo: las 97 partidas de APU curadas contra bibliografía, la escala UOCRA con cargas
sociales, los coeficientes, el catálogo de insumos canónicos. Meses de trabajo de un arquitecto del
rubro, que es lo que `proveedores_digitales_bariloche.md` §"Riesgo de exposición" identificó como el
activo real: *"lo que no tienen es la curación técnica… no algo que se replique mirando una demo"*.

**Tarea concreta: armar el archivo del código fuente para el sobre.** El depósito de obra inédita se
presenta cerrado, así que hay que decidir y dejar escrito qué entra:

- el código de `lib/` y `supabase/migrations/`;
- **las migraciones importan tanto como el Dart** — el modelo de datos y las reglas de autoridad
  (`mis_pendientes`, la matriz de emisión, la delegación) son parte de la obra, no infraestructura;
- los `docs/`, que son donde vive el razonamiento;
- **NO** `env.json`, `google-services.json`, ni nada de `supabase/seed_staging/` — son credenciales
  y datos de prueba, no obra.

Pendiente de decidir: si el depósito es una foto de hoy o se repite cuando la app cambie
sustancialmente. Un depósito envejece como cualquier foto.

## 2. Términos y condiciones — **esta semana**

Tres cosas distintas que suelen confundirse en una sola:

| | Qué es | Dónde ya está anotado |
| --- | --- | --- |
| **T&C** | La relación con el usuario de la app | Acá |
| **Descargo de precios** | Que los precios del catálogo son referencia y hay que verificarlos | `confianza_precios_diseno.md` §2, con el texto ya redactado |
| **NDA** | Para los colegas que reciban el APK | `proveedores_digitales_bariloche.md` §"Riesgo de exposición" |

**El descargo de precios ya tiene texto escrito** y una decisión tomada que conviene no perder: *"un
descargo escondido es el que peor funciona — si va, va visible, no en letra chica"*. Y la advertencia
que lo acompaña: **un descargo no reemplaza al producto funcionando bien.** La protección real es
mostrar la fecha del precio y avisar cuando está viejo; lo legal acompaña eso, no lo sustituye.

Los tres los revisa el abogado en la misma consulta. Y hay una cuarta cosa que va al mismo abogado y
está anotada aparte: el **borrador de contrato de obra** (`docs/contrato_obra_horizonte.md`), con la
regla que ya quedó cerrada — *"nunca un documento que se firma tal cual sale de la app"*.

## 3. Lo que ya está resuelto y no hace falta volver a pensar

- **Publicar la web no expone datos de nadie.** La web y el móvil usan la misma Supabase con la
  misma RLS; el control de acceso vive en la base, no en el frontend
  (`vinculacion_dispositivos_decisiones.md` §3).
- **Los tres son el mismo momento**: registro, NDA y publicar la web se disparan juntos, cuando se
  reparte el APK. No tiene sentido publicar la web antes de tener resueltos los otros dos.
- **La app compila y corre en web**, verificado sin querer al construir la vinculación de
  dispositivos.
