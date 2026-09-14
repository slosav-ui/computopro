# Notificaciones al teléfono — diagnóstico (2026-09-14, sin código)

Pedido de Seba: avisar al teléfono lo que hoy solo se ve abriendo la app. Salió de una prueba real:
*"cuando seba2135 pagó, a slosav no le llegó nada"*, y *"en obra la app se usa salteado, así que si
alguien tiene que abrirla para saber que lo esperan, las cosas se enfrían"*.

**El criterio ya está cerrado y no se rediscute** (ver `criterio_pantalla_principal_solo_acciones`):
**certificados y adicionales sí, el libro de obra no.** Un push por cada cosa que pasa en una obra
activa es la forma más rápida de que los apaguen todos.

---

## 1. Lo que ya está hecho y no hay que rehacer

**`mis_pendientes()` ya sabe qué le falta a quién**, con 13 ramas y la autoridad de cada transición.
Ese es el 80% difícil de un sistema de notificaciones —decidir a quién le importa cada hecho— y está
resuelto y probado. **Lo que falta es el transporte.**

Y hay algo que achica la pieza más de lo que parece: **el proyecto ya tiene Realtime** (Supabase
Realtime, verificado con tres clientes en Mat y MO). Con la app abierta, los datos ya se actualizan
solos. **El push sirve exclusivamente para cuando la app está cerrada** — que es el caso real de
obra, pero conviene tener claro que no reemplaza nada de lo que ya anda.

## 2. Supabase no tiene push nativo

No es un servicio que falte activar: **no existe**. La propia documentación de Supabase recomienda
**Database Webhook → Edge Function → FCM** (Firebase Cloud Messaging), con APNs por debajo para iOS.

O sea que la pieza **suma un proveedor externo al stack**, que hoy es solo Supabase. Es la decisión
de fondo de este diagnóstico, y no tiene alternativa razonable: FCM es el único camino a Android, y
APNs el único a iOS. Lo que sí se puede elegir es **quién habla con FCM**: una Edge Function propia,
o un servicio gestionado tipo OneSignal que se lleva los tokens y los datos de los usuarios adentro.
Para tres usuarios, el gestionado no se justifica.

## 3. Cuánto cuesta — y hoy la respuesta es cero

| | |
| --- | --- |
| **FCM (Android)** | **Gratis.** Sin costo por mensaje ni por usuario, a cualquier volumen razonable |
| **APNs (iOS)** | Gratis el envío, pero **exige Apple Developer Program: USD 99 por año** |
| **Google Play** | USD 25 por única vez, y **solo para publicar** — no hace falta para que el push funcione |
| **Supabase** | Edge Functions y webhooks entran en el plan que ya se usa |

**Y acá está el hallazgo que cambia el presupuesto: iOS está fuera de alcance hoy, así que el costo
real es $0.** Dos razones verificadas en el repo, no supuestas:

- **se desarrolla en Windows**, y compilar iOS necesita macOS — no es una cuestión de plata, es que
  hoy no se puede;
- **la app no está publicada en ningún lado**: `android/app/build.gradle.kts` sigue firmando el
  release con las claves de debug (`signingConfig = signingConfigs.getByName("debug")`, con el TODO
  original de Flutter). Los USD 25 de Play son de otra conversación.

Entonces: **push de Android, gratis, ahora**. El día que haya iOS, se suma el `.p8` de APNs al
proyecto de Firebase y el resto del diseño no cambia.

## 4. La arquitectura que recomiendo: una tabla de salida, no un webhook por tabla

Lo fácil es poner un Database Webhook en `certificados` y otro en `modificaciones_obra` y disparar
desde ahí. **Es lo fácil y lo equivocado**, por la misma razón que ya ordenó el diseño de los avisos:
un push no es "cambió una fila", es **"esto ahora te espera a vos"**. Con webhooks por tabla, la
Edge Function tendría que reconstruir en TypeScript la matriz de autoridad que hoy vive en SQL —
exactamente la duplicación que en este proyecto ya divergió una vez con la delegación.

**La forma que propongo:**

```
transición (emitir_certificado, aprobar_adicional, objetar_certificado, …)
        │  inserta N filas, una por destinatario, con la autoridad que ya usa
        ▼
   notificaciones   ← tabla de salida (outbox): usuario_id, tipo, obra_id, entidad_id,
        │             titulo, cuerpo, estado, creada_en, enviada_en, error
        │  Database Webhook (uno solo, sobre INSERT)
        ▼
   Edge Function  ──►  FCM  ──►  el teléfono
        │
        └─ marca la fila enviada, o guarda el error; borra el token si FCM dice que murió
```

Por qué así:

- **Un solo webhook** en vez de uno por tabla que algún día notifique.
- **El "a quién" se calcula en SQL**, al lado de la autoridad que ya decide lo mismo para
  `mis_pendientes()`. Una definición, no dos.
- **Se puede ver qué se mandó y qué falló.** Un push que no llegó, sin outbox, no deja rastro en
  ningún lado.
- **Reintento e idempotencia** salen gratis: la fila queda pendiente y se reintenta.
- **El horario y la agrupación se vuelven un `where`**, no una rama de código: "no mandar entre las
  22 y las 7" es una condición sobre la tabla.

Las **30 funciones de transición** del proyecto no se tocan todas: solo las de certificados y
adicionales, que son las que el criterio deja pasar.

## 5. Qué implica mantenerlo — la parte que se subestima

Esto es lo que hay que mirar antes de decir que sí, porque el costo no está en construirlo:

**Del lado de Firebase**

- La API moderna de FCM (v1) **no usa una API key**: pide un **OAuth2 de service account**, o sea
  firmar un JWT y canjearlo por un token cada hora. Es código real en la Edge Function y **un secreto
  para guardar** (Supabase secret), con su rotación eventual.
- Hay que **ser dueño de un proyecto de Firebase**. Si algún día cambia la cuenta de Google, el
  proyecto se muda con todo lo que cuelga.
- `google-services.json` entra en el repo (no es secreto) y **ata el build a ese proyecto**.

**Del lado de los tokens** — es lo que más mantenimiento real da:

- Un token **muere solo**: reinstalación, borrar datos de la app, o rotación de FCM. Hay que
  **re-registrarlo en cada arranque**, no solo al login.
- Cuando FCM contesta `UNREGISTERED`, **hay que borrar la fila**. Sin eso se acumula basura y se
  gastan envíos contra teléfonos que ya no existen.
- Un usuario tiene **varios dispositivos**: es una tabla, no una columna en `perfiles`.

**Del lado de la app**

- **Android 13+ pide permiso de notificaciones en runtime** (`POST_NOTIFICATIONS`). Es el segundo
  permiso nativo del proyecto, después del micrófono de la tanda 3 del libro.
- Tocar la notificación tiene que **abrir la pantalla donde se resuelve**. Eso ya existe
  (`_abrirPendiente` del dashboard); lo que falta es el ruteo desde el mensaje.
- **Probarlo necesita un dispositivo con Google Play services.** Un emulador con Google APIs recibe
  FCM, así que se puede — pero es más fiddly que todo lo que este proyecto probó hasta ahora.

**Y el costo recurrente de diseño**, que no es técnico: **cada rama nueva de `mis_pendientes()` va a
tener que decidir si empuja o no.** Es una pregunta más en cada pieza futura, para siempre.

## 6. Conviene partirlo, y en cinco tandas

Cada una se verifica sola, y **solo la tercera necesita Firebase funcionando**:

| Tanda | Qué | Cómo se verifica | Tamaño |
| --- | --- | --- | --- |
| **0** | Las decisiones de §7 + crear el proyecto de Firebase y bajar `google-services.json` | No hay nada que verificar: es la reunión y una consola | Chica |
| **1** | Tabla `dispositivos` + registrar/borrar el token en el arranque y el logout + permiso Android 13 | `select * from dispositivos` muestra el token. **Sin mandar nada** | Chica |
| **2** | Tabla `notificaciones` (outbox) + quién es el destinatario en SQL + escribir filas desde las transiciones de certificados y adicionales | En SQL: emitir un certificado y ver aparecer la fila con el destinatario correcto. **Sin mandar nada** | Media |
| **3** | La Edge Function + el webhook + FCM | *** El primer push que llega a un teléfono | Media |
| **4** | Tocar la notificación abre la pantalla + limpieza de tokens muertos + horario | Con la app cerrada, tocar y caer en el certificado | Chica |

**Por qué en ese orden:** las tandas 1 y 2 son las que tienen la lógica de negocio y **se prueban sin
Firebase**, con SQL y la app. Si algo está mal pensado —el destinatario equivocado, un aviso de más—
se descubre ahí, gratis, y no depurando por qué no llega una notificación. La tanda 3 es puro
transporte: cuando se llega, ya se sabe que el contenido está bien.

La **tanda 5, iOS**, no entra en el orden: depende de tener una Mac y de pagar los USD 99. El diseño
no cambia — se agrega el `.p8` al proyecto de Firebase y ya.

## 6-bis. Decidido por Seba (2026-09-14), y cómo quedó partida la Tanda 1

**Los eventos (A):** certificado emitido, adicional aprobado y certificado pagado — *"todos son de
plata, y el que espera plata tiene que enterarse"*. Más un cuarto (B): **el vencimiento de la
objeción cerca**, *"son cinco días, si alguien tarda tres en abrir la app ya se comió más de la
mitad"*.

> **Sobre el cuarto, un dato que conviene tener antes de la Tanda 2: el aviso de vencimiento de la
> objeción YA EXISTE adentro de la app desde la `0131`.** La rama `objecion_respondida` devuelve
> `vence` a partir de las 24 h y el cartel muestra *"respondida el 12/09 · se resuelve sola el
> 17/09"*. Lo que falta no es el aviso — es que salga del teléfono sin abrir la app. Así que ese
> pedido **no se puede adelantar a la Tanda 1**: la Tanda 1 no manda nada.

**El orden (C):** Tanda 1 ahora y **parar a mirar**. *"Si con el aviso dentro de la app alcanza, me
ahorro la infraestructura entera."*

Eso obliga a una aclaración honesta: **la Tanda 1 ya es un poco de infraestructura** (una tabla, un
plugin, un permiso). No es la cara —eso es la Tanda 3, con Firebase y la Edge Function— pero tampoco
es gratis. Si la idea es decidir **si** hace falta push, lo más barato es no construir nada y mirar
el uso durante unas semanas. Si la idea es dejar la plomería lista para no frenarse después, la
Tanda 1 sirve y se descarta con un `drop table` si al final no se sigue. **Las dos son razonables;
lo que no conviene es hacer la Tanda 1 creyendo que evita la decisión.**

### La Tanda 1 está partida en dos, y la mitad de Flutter está BLOQUEADA

| | Qué | Estado |
| --- | --- | --- |
| **1a · SQL** | Tabla `dispositivos` + RLS + `registrar_dispositivo` / `borrar_dispositivo` | **Escrita: `0142`.** No depende de Firebase ni manda nada |
| **1b · Flutter** | `firebase_messaging`, permiso de Android 13+, registrar el token en cada arranque | **Escrita** (proyecto `computopro-31a44`). Verificada con `flutter build apk --debug` |

### Cómo quedó la 1b (2026-09-14)

**Gradle:** el plugin `com.google.gms.google-services` declarado en `android/settings.gradle.kts`
(`apply false`, con la versión) y aplicado en `android/app/build.gradle.kts` **después** del plugin
de Flutter — necesita el módulo de Android ya configurado para inyectarle los recursos que genera de
`google-services.json`.

**`PushService`** (`lib/services/push_service.dart`) hace tres cosas y nada más: inicializa Firebase,
registra el token y lo borra al cerrar sesión. **Todo silencioso ante error**: que no se pueda
registrar un token no puede romper el arranque. El push es una comodidad, no algo de lo que dependa
ninguna función — si falla, el usuario no recibe algo que hoy tampoco recibe.

**Dónde se llama cada cosa, que es lo que se rompe fácil:**

- `Firebase.initializeApp()` en `main`, antes de `runApp`.
- **El registro del token va en `AuthGate`, no en `main`**: la fila de `dispositivos` es del usuario
  logueado, así que hace falta sesión abierta. `AuthGate` pasó de `StatelessWidget` a
  `StatefulWidget` para poder recordar con qué usuario ya se registró y no repetirlo en cada evento
  del stream — `onAuthStateChange` emite también por refresh de token. Y si en ese teléfono entra
  **otra** persona, se registra de nuevo: ahí el dispositivo cambia de dueño, que es justo lo que
  resuelve el `unique (token)` de la `0142`.
- **El borrado va ANTES del `signOut`.** Con la sesión ya cerrada, `auth.uid()` es null del lado de
  la base y el `delete` no matchea nada — el teléfono se quedaría recibiendo los avisos de quien se
  acaba de ir. Por eso el botón de cerrar sesión del dashboard ya no llama directo a
  `cerrarSesion()`.

**El permiso de Android 13+ no hizo falta declararlo**: `firebase_messaging` ya trae
`POST_NOTIFICATIONS` en su manifest y el merge lo incorpora (verificado en el manifest mergeado del
APK). Lo que sí hay que hacer es **pedirlo en runtime**, y eso es `requestPermission()`, que en
Android 13+ dispara el diálogo del sistema y en versiones anteriores devuelve autorizado sin
preguntar nada.

**Para probarlo hace falta Google Play services.** Un emulador con imagen *Google APIs* sirve; uno
sin ella **no consigue token** — `getToken()` devuelve null y no se registra nada, en silencio. Si
la tabla queda vacía, eso es lo primero a mirar.

> **Y esto no manda ninguna notificación todavía.** Es la plomería: la tabla tiene el token y nada
> más. Lo que envía es la Tanda 2 (la outbox) y la 3 (la Edge Function), y puede no construirse
> nunca — el plan era parar acá a mirar si el aviso adentro de la app alcanza.

No es "falta hacerlo": **sin `google-services.json` el build de Android falla al compilar**. Los tres
pasos que lo destraban (Tanda 0, minutos en la consola de Firebase) están al pie de la `0142`, e
incluyen uno que conviene resolver antes y no después: **el `applicationId` sigue siendo
`com.example.mi_primera_app`**, que no se puede publicar en Play y no se cambia después sin perder la
app.

### El `applicationId`, resuelto antes de Firebase (2026-09-14)

`com.example.mi_primera_app` → **`com.computopro.app`**. Se hizo **antes** de crear el proyecto de
Firebase a propósito: la app de Firebase se registra contra el `applicationId`, así que crearla con
el viejo obligaba a rehacerla.

**No era solo el archivo de configuración.** Fueron cuatro cosas:

1. `namespace` y `applicationId` en `android/app/build.gradle.kts` — son **dos cosas distintas**
   (el paquete del código generado y la identidad publicada) y podrían diferir, pero mantenerlos
   iguales evita tener que explicar cuál es cuál cada vez;
2. **`MainActivity.kt` se mudó de carpeta**: el archivo vive en un árbol que refleja el paquete, así
   que pasó de `kotlin/com/example/mi_primera_app/` a `kotlin/com/computopro/app/`, con su
   `package` adentro. Si solo se cambia el gradle, **no compila**;
3. el `AndroidManifest.xml` **no se toca**: declara la activity como `.MainActivity`, relativo al
   namespace, así que se reacomodó solo;
4. `PRODUCT_BUNDLE_IDENTIFIER` en el proyecto de iOS (6 lugares, incluidos los de RunnerTests), para
   que el día que haya iOS no haya que volver acá.

Verificado con `flutter build apk --debug`: el manifest mergeado declara `package="com.computopro.app"`.

**Lo que queda igual y no importa hoy:** los identificadores de Linux, Windows y macOS de escritorio
siguen con el nombre viejo. Solo importarían si algún día se publica una versión de escritorio.

**Ojo con esto al actualizar el teléfono:** para Android, **una app con otro `applicationId` es otra
app**. La instalada no se actualiza — queda ahí con sus datos, y la nueva se instala al lado, vacía.
En la práctica: **hay que iniciar sesión de nuevo** (la sesión de Supabase vive en el
almacenamiento de la app, que es por `applicationId`) y **conviene desinstalar la vieja a mano**,
porque el ícono se queda. Las obras no se pierden: están en la nube, no en el teléfono.

**Y esto ya no se cambia más.** El día que se publique, el `applicationId` es la identidad de la app
en Play para siempre.

### Dos decisiones de la `0142` que no son obvias

- **`unique (token)`, no `unique (usuario_id, token)`.** El token identifica una **instalación**, no
  a una persona: si en ese teléfono se cierra sesión y entra otro usuario, FCM devuelve el mismo
  token, y con la fila vieja en pie el aparato seguiría recibiendo los avisos del anterior. El
  registro transfiere la fila de dueño en vez de duplicarla.
- **Registrar en cada arranque, no solo al iniciar sesión.** Un token de FCM cambia al reinstalar, al
  borrar datos, y a veces solo porque FCM lo rota. Registrarlo únicamente en el login deja aparatos
  con tokens muertos **sin que nada falle de forma visible**: simplemente no llega.

## 7. Lo que hay que decidir antes de la tanda 1

**A. ¿Qué eventos exactamente?** El criterio dice "certificados y adicionales", pero eso son unos
diez hechos. Mi recomendación es arrancar con **los que mueven plata o tienen plazo**: certificado
emitido (al cliente), pago registrado (al que cobra), objeción planteada y respondida, adicional
esperando aprobación. Y **dejar afuera** los de trabajo en curso — propuesta de avance, borrador
conformado, período de certificación habilitado— que ya avisa el cartel y no son urgentes.

**B. ¿Se puede silenciar por obra?** Alguien con seis obras activas recibe seis veces más. La forma
barata es una fila por (usuario, obra) como la que ya existe para el libro; la cara es un centro de
preferencias. Recomiendo **lo barato**, y solo si aparece la necesidad.

**C. ¿Horario?** Un certificado emitido a las 23:30 despierta a alguien. Recomiendo **no mandar entre
las 22 y las 7**, acumulando para la mañana — con la outbox es un `where`, no una pieza aparte.

**D. ¿Y si la misma persona tiene tres dispositivos?** Le llega tres veces. Es lo normal y no lo
arreglaría; conviene saber que va a pasar.

**E. El texto.** Aplica el mismo criterio de tono que el cartel: qué pasó y de qué obra, sin sonar a
reproche, y **sin montos** — una notificación se ve en la pantalla bloqueada, y ahí el monto de un
certificado lo lee cualquiera que levante el teléfono. Esto último no es un detalle de redacción: es
la única parte de esta pieza que puede filtrar información a alguien que no es miembro de la obra.
