# Vinculación de dispositivos: bloqueo de edición, QR de la PC, y publicar la web (2026-09-05)

Al desarmar la prioridad de "QR de vinculación PC/teléfono" aparecieron tres piezas distintas que
la especificación funcional histórica mezclaba en una sola (ver `CLAUDE.md`, sección "QR de
vinculación multiplataforma"): sincronización en tiempo real, bloqueo de edición, y la vinculación
de la PC en sí. La primera ya se construyó y verificó — ver la memoria de proyecto
`sincronizacion_tiempo_real.md` (Mat y MO / `obra_insumo_precios`, migración `0050`). Este
documento cierra el diagnóstico de las otras dos, más una tercera pieza que apareció al analizarlas
(publicar la versión web), y dos hallazgos que conviene que no se pierdan.

## 1. Bloqueo de edición — DESCARTADO, no postergado

Se evaluó como condición previa al diseño del QR (el bloqueo evita que dos ediciones simultáneas se
pisen) y **se decidió no construirlo**. No es un "todavía no" — es una decisión cerrada, para que
nadie lo revisite sin conocer el motivo.

**Por qué**: el único que edita precios y cómputo durante el armado del presupuesto es el
administrador de la obra. No hay editores simultáneos posibles sobre esos datos en el uso real de
la app. El caso de dos socios con permisos totales existe, pero es la excepción, y se coordinan
hablando entre ellos — un bloqueo automático ahí molesta más de lo que ayuda: si alguien deja la
obra abierta y se va, el otro queda trabado sin poder trabajar.

La especificación histórica menciona conflictos de edición concurrente y propone un registro de
conflictos por campo como solución. **Esa idea queda superada por la matriz de permisos ya
construida** (Etapa 3, `obra_members`/roles combinables), que hace el problema mucho más chico de
lo que la spec asumía en su momento, antes de que existiera esa matriz. Si algún día aparece un
choque real de ediciones, se resuelve con el Audit Log (quién hizo qué y cuándo, ya existente desde
Etapa 3) sabiendo cómo pasó — no se antipica con un mecanismo nuevo.

**Consecuencia directa para la pieza 2**: como no hay bloqueo de edición, la sincronización en
tiempo real (ya construida) es la única protección contra que dos sesiones muestren datos
desactualizados entre sí — y ya alcanza, porque no hay edición simultánea real que sincronizar.

## 2. Vinculación de la PC por QR — diseño definido, sin construir

**Función deseada, modelo WhatsApp Web**: el usuario abre la app en el navegador sin sesión, la
app muestra un QR, lo escanea con el teléfono (que ya tiene sesión iniciada), y el navegador queda
autenticado con la misma cuenta. Sin sincronización de datos que construir aparte — los dos
clientes leen y escriben la misma Supabase, ya es la única fuente de verdad, y Realtime ya anda
(ver punto 4).

**Supabase Auth no soporta esto de forma nativa.** Verificado contra la documentación oficial y las
discusiones del propio repo antes de proponer cualquier alternativa, no asumido:

- [Planned support for qr code login auth? (supabase/discussions#1139)](https://github.com/orgs/supabase/discussions/1139)
  — pedido original de abril 2021, retomado en febrero 2024 ("¿por qué no hay avance en esta
  función tan esperada?"). Sigue sin respuesta oficial del equipo de Supabase. Última actividad:
  septiembre 2024.
- [Device Authorization Flow (supabase/discussions#39437)](https://github.com/orgs/supabase/discussions/39437)
  — mismo patrón: pedido de un usuario, cero respuestas oficiales, sin camino documentado.
- El primitivo más parecido en espíritu, el **flujo PKCE**, prohíbe explícitamente el cruce entre
  dispositivos por diseño: la documentación oficial dice textual que *"the code exchange must be
  initiated on the same browser and device where the flow was started"* — el `code_verifier` queda
  guardado localmente en el dispositivo que inició el flujo, no hay forma de completarlo desde
  otro. No es un camino adaptable, es un mecanismo pensado para impedir justo esto.
- Lo único con "QR" en Supabase Auth es el enrolamiento de MFA/TOTP (la app autenticadora escanea
  un QR para configurar el segundo factor) — pieza completamente distinta, no transfiere sesión
  entre dispositivos.

**Hay que construirlo a mano.** Diseño acordado, sin implementar todavía:

- Tabla temporal de sesiones de vinculación (código + estado + expiración, sin diseño de columnas
  cerrado todavía).
- Código de un solo uso con expiración corta, del orden de uno o dos minutos.
- La web genera el código, muestra el QR, y espera la confirmación **por Realtime** — mecanismo ya
  construido y verificado (`sincronizacion_tiempo_real.md`), esta pieza lo reusa en vez de inventar
  polling.
- El teléfono, con sesión activa, lee el QR y confirma.
- Transferencia de la sesión al navegador.

**La transferencia de sesión es la parte delicada, a propósito sin diseñar todavía.** Un token de
sesión mal manejado es acceso completo a la cuenta de alguien — no se improvisa de pasada dentro de
otra pieza. Cuando se retome, esa transferencia necesita su propio diagnóstico de seguridad (cómo
viaja el token, con qué alcance, cómo se invalida si algo sale mal) antes de escribir una sola
línea, mismo criterio que ya se aplicó acá al no inventar nada sin la documentación oficial
verificada primero.

**Alternativa ya disponible, nativa, para si el QR se posterga indefinidamente**: el **magic link**
de Supabase Auth resuelve buena parte de la necesidad real (entrar sin tipear contraseña) aunque no
sea el mismo flujo — no vincula dos sesiones existentes, es un inicio de sesión nuevo por link.
Vale como salida más simple si esta pieza no se prioriza pronto.

**Descartado explícitamente**: sumar un proveedor externo de autenticación de terceros para esto
(apareció Keyri en la búsqueda, como integración externa que sí ofrece QR sign-in para apps con
Supabase). Es superficie de ataque y una dependencia nueva por una función que hoy es cosmética —
no se evalúa de nuevo salvo que cambie el contexto.

## 3. Publicar la app web — pendiente, con condición de disparo ya acordada

Hoy la versión web solo corre en la máquina de Seba vía `flutter run -d chrome`, que levanta un
servidor local temporal — nadie de afuera puede entrar, no es una publicación real.

Para que exista como página accesible hacen falta dos pasos, ninguno hecho: `flutter build web`
(genera los archivos estáticos) y publicarlos con una dirección propia — eventualmente bajo un
dominio propio, tipo `app.computopro.com.ar`. No es difícil ni caro.

**Dato tranquilizador para dejar escrito**: publicarla no expone datos de nadie. La web y el móvil
usan la misma Supabase con la misma RLS — cada usuario sigue viendo solo sus propias obras,
publicar el frontend no cambia nada del control de acceso, que vive en la base.

**Condición de disparo acordada**: se publica cuando se vaya a repartir el APK a colegas, junto con
el registro del software y el acuerdo de confidencialidad que ya están anotados como requisito
previo a eso (ver `CLAUDE.md`, "Riesgo de exposición" en el hallazgo de proveedores digitales de
Bariloche). Los tres — registro del software, NDA, y publicar la web — son el mismo momento: salir
al mundo. No tiene sentido publicar la web antes de tener resueltos los otros dos.

## 4. Dato ya verificado, sin querer, al construir la pieza 1

**La app compila y corre en web.** Se levantó con
`flutter run --dart-define-from-file=env.json -d chrome`, con login normal, y funcionó como tercer
cliente real en la verificación de Realtime de la pieza 1 (dos emuladores Android + Chrome, mismo
login, misma obra, editando y viendo los cambios propagarse entre los tres).

Era la incógnita más grande de toda la idea de "versión de PC = la app compilada a web" — si de
verdad compilaba y andaba sin ajustes — y quedó respondida sin proponérselo, como efecto colateral
de probar otra cosa. Queda escrito acá para que quien retome la pieza 2 o la pieza 3 no necesite
volver a probarlo desde cero.
