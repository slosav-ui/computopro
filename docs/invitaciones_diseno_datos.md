# Invitaciones a una obra — diseño de datos (2026-09-10)

**Estado: Tanda 1 verificada de punta a punta por Seba, Tanda 2 aplicada y con Dart escrito, sin
verificar en el emulador — 2026-09-10.**

**Tanda 1**: tres migraciones (`0095`/`0096`/`0097`), tres bugs reales encontrados y corregidos al
probar (explicación insuficiente en la pantalla de pegar el código, canje silencioso a la cuenta
equivocada, y `42702` por ambigüedad de columna — ver §5/§7 para el detalle de cada uno). Generar,
compartir, previsualizar y aceptar funcionan, confirmado por Seba.

**Tanda 2** (`0098_quitar_miembro_obra.sql` + `MiembrosObraScreen`): ver miembros, ver
invitaciones, copiar código, revocar, y sacar miembro con la guarda del último administrador — ver
§10/§11 para el diagnóstico y los archivos. `flutter analyze` limpio, **sin correr en el emulador
todavía**.

Es el punto 4 del orden de ejecución (`docs/diagnostico_general_producto.md`) y la dependencia
real de `docs/licitacion_privada_presupuestos_diseno.md` ("por invitación desde la app" no se
puede construir sin esto). Diagnóstico completo hecho contra el código real, no contra la spec —
`etapa3_roles_permisos_diseno_datos.md` no contempla nada de este mecanismo (tiene
`invitado_por_usuario_id` e `invitado_por_rol`, pero asume que el UUID del invitado ya se conoce
al insertar en `obra_members`; acá no se conoce todavía).

## 1. Por qué hace falta una tabla nueva, no alcanza con `obra_members`

La política `obra_members_insert` (`0004_rls_etapa3.sql`) ya deja pasar un INSERT de
`admin_maestro`/`puede_invitar_terceros` para cualquier `usuario_id` — pero solo sirve si ese UUID
ya existe. No hay ningún camino para que alguien sin cuenta todavía "aparezca" en `obra_members`.
Como el caso real es justamente invitar a alguien que **no es usuario de la app** (un constructor
al que se le pide presupuesto, un cliente nuevo), hace falta una tabla intermedia de invitación
pendiente, canjeable recién cuando esa persona se registra.

## 2. Tabla `invitaciones`

Mismos nombres de columna que los campos de `PermisosEspeciales` en `obra_members`, para que
canjear sea una copia directa, no una traducción:

```
id                          uuid, pk
obra_id                     uuid, references obras(id)
rol                         text — uno de los 5 roles invitables (ver §3)
puede_aprobar_certificados  boolean
puede_aprobar_adicionales   boolean
tope_monto_aprobacion       numeric
delegacion_inicio           timestamptz
delegacion_fin              timestamptz
puede_invitar_terceros      boolean
puede_ver_apu_ajena         boolean — default false, ver §4
codigo                      text — código corto para pegar a mano (ver §5), no un uuid
invitado_por_usuario_id     uuid, references auth.users(id)
estado                      text check in ('pendiente','aceptada','revocada')
creado_at                   timestamptz, default now()
expira_en                   timestamptz — creado_at + 30 días (ver §6)
aceptada_por_usuario_id     uuid, references auth.users(id), nullable
aceptada_en                 timestamptz, nullable
```

Sin `email_destino` — decisión cerrada: el link no está atado a un email (mismo modelo que un
link de invitación de Slack/Notion, no una invitación nominal). El detalle de quién revocó y
cuándo va a `audit_log` (ya existe, genérico — `etapa3_roles_permisos_diseno_datos.md` §4), no una
columna nueva por transición.

**Crear una invitación**: INSERT directo bajo RLS (no necesita `SECURITY DEFINER`) — mismo criterio
que `admin_maestro`/`puede_invitar_terceros` ya usan en `obra_members_insert`.

**Revocar** (`revocar_invitacion(p_invitacion_id)`): ajuste sobre la primera versión de este
diseño — pasa a ser función `SECURITY DEFINER`, no un UPDATE bajo RLS. `invitaciones` no tiene
política UPDATE: los dos únicos cambios de estado (aceptar, revocar) pasan siempre por una de las
dos funciones, nunca por un UPDATE directo del cliente — es donde vive la autorización (quien
invitó, `admin_maestro`, o `puede_invitar_terceros`) y, en `aceptar_invitacion`, el freno de fuerza
bruta (ver §5).

**Canjear** (`aceptar_invitacion(p_token)`): tiene que ser `SECURITY DEFINER` — a diferencia de
crear/revocar, esto necesita que alguien que **todavía no es miembro de la obra** pueda insertar su
propia fila en `obra_members`, algo que la RLS normal no permite. Mismo patrón que
`is_obra_member`/`tiene_rol_en_obra` (`0004_rls_etapa3.sql`): valida token vigente y no usado,
inserta en `obra_members` copiando los campos de arriba, marca la invitación como aceptada, deja
una fila en `audit_log` — todo en la misma función, atómico porque una función PL/pgSQL corre
dentro de la transacción de quien la llama.

## 3. Roles invitables: los 5, sin `admin_maestro`

**Cerrado.** El selector de rol al invitar ofrece `profesional`, `constructor`,
`cliente_principal`, `invitado_veedor`, `invitado_apoderado` — nunca `admin_maestro`.
`admin_maestro` está definido en `etapa3_roles_permisos_diseno_datos.md` §6.2 como "un flag
administrativo, no un cuarto rol económico", ligado a quien crea la obra
(`0033_obra_members_bootstrap.sql` lo asigna solo, en el bootstrap). Un segundo administrador es
otra discusión, fuera de esta pieza — la constraint `check (rol in (...))` de `invitaciones` no
incluye `'admin_maestro'` en su lista de valores válidos.

## 4. Permisos ofrecidos y la regla "un permiso no regala PRO"

De `PermisosEspeciales`:

| Campo | Se ofrece al invitar | PRO |
|---|---|---|
| `puedeAprobarCertificados` | Sí — típico de Apoderado | No |
| `puedeAprobarAdicionales` + `topeMontoAprobacion` | Sí, combinados | No |
| `delegacionTemporalInicio/Fin` | Sí, si el rol es Apoderado | No |
| `puedeInvitarTerceros` | Sí | No |
| `puedeVerApuAjena` | Sí — el único que regala el diferencial pago | **Sí** |

`puedeVerApuAjena` es el caso real de la regla: `docs/monetizacion.md` §9 dice que el desglose de
Factor K es exclusivo de PRO — Free ve el precio final armado, no la cascada. Dar
`puedeVerApuAjena` a alguien es exactamente destapar esa cascada.

**Por qué el chequeo no puede hacerse al invitar**: en ese momento no se sabe si la persona
invitada tiene PRO — puede ni tener cuenta todavía. El cartel de "esto requiere PRO" junto al
toggle es un aviso genérico, siempre visible, no una verificación contra una persona puntual. La
verificación real es en el momento de uso: `puede_ver_apu_ajena == true AND
PerfilRepository.esPro(auth.uid())`, chequeado en vivo — mismo patrón ya usado en
`bloque_factor_k.dart`/`rubros_tab.dart` (`esPro` nunca se cachea de una carga anterior).

## 5. El código: pegado a mano, no enlace real — decisión cerrada con costo conocido

**No hay infraestructura de deep link en la app.** `main.dart` tiene dos rutas (`/` y
`/presupuesto`), sin `uni_links`/`app_links`, sin App Links de Android ni Universal Links de iOS
configurados. La web —el destino natural de un link de WhatsApp— hoy solo corre en la máquina de
Seba, no está publicada (`docs/vinculacion_dispositivos_decisiones.md` §3).

**Decisión cerrada**: arrancar con un código mostrado para copiar/pegar (por WhatsApp, como
texto), no como un link que abre la app solo. Adentro de la app hay una pantalla "Ingresar código
de invitación" donde se pega. Mismo circuito de datos que un link real —
`aceptar_invitacion(p_codigo)` no distingue cómo llegó el código— así que pasar a link real
después no pide rediseñar nada de esto, solo agregar el manejo de deep link (el código puede
seguir siendo el mismo dato, embebido en la URL en vez de tipeado).

**Ajuste sobre la primera versión de este diseño (2026-09-10, antes de escribir la migración)**: el
código no es un `uuid` — nadie copia bien 36 caracteres desde un WhatsApp, y un error de tipeo
frena a quien lo intenta. Es un código de **8 caracteres**, alfabeto de 31 símbolos sin los pares
que se confunden a mano (sin `0`/`O`, sin `1`/`I`/`L`): dígitos 2-9 más mayúsculas sin I/L/O — 31⁸
≈ 852.891 millones de combinaciones posibles, generado por `generar_codigo_invitacion()`
(`0095_invitaciones.sql`).

**Con un código corto, la fuerza bruta pasa a ser una amenaza real** — no lo era con un uuid.
`aceptar_invitacion` se defiende en dos capas: (1) cuenta los intentos fallidos del usuario
autenticado en los últimos 15 minutos (reusa `audit_log`, sin tabla nueva) y corta a partir de 5;
(2) código inexistente, vencido, o ya usado devuelven exactamente el mismo mensaje genérico —
nunca se distingue el motivo, para que probar códigos al azar no revele si alguno estuvo cerca de
ser válido. Límite conocido: el freno es por usuario autenticado, no por IP — mitigado por la
fricción propia de crear una cuenta de Supabase (email real + confirmación), no resuelto del todo.

**Limitación conocida, aceptada, con costo real de adopción**: el que recibe el WhatsApp tiene que
abrir la app y buscar dónde pegar el código — cada paso pierde gente, más en un flujo que ya
empieza con alguien reacio a usar la app (mismo problema de fricción que
`docs/licitacion_privada_presupuestos_diseno.md` §9 identifica para el constructor). **El enlace
real queda anotado como mejora prioritaria en cuanto la web esté publicada** — condición de
disparo ya definida en `docs/vinculacion_dispositivos_decisiones.md` §3 (se publica junto con el
registro del software y el NDA, al momento de repartir el APK a colegas).

**Bug real encontrado al probar en el emulador (2026-09-10), sin relación con lo de arriba**:
`aceptar_invitacion` fallaba con `42702, column reference "obra_id" is ambiguous` — mismo patrón
que ya mordió dos veces en la familia de funciones de edición de APU (`0075`/`0076`). Causa:
`returns table(obra_id uuid, obra_nombre text, rol text)` hace que PL/pgSQL exponga esas columnas
de salida como variables del cuerpo, y un `obra_id`/`rol` sin calificar en una consulta embebida
(el candidato más probable: `on conflict (obra_id, usuario_id, rol)`) queda ambiguo. Corregido en
`0097_invitaciones_variable_conflict_use_column.sql` con `#variable_conflict use_column` como
primera línea del cuerpo — mismo remedio de fondo que `0076`, aplicado a las tres funciones de esta
pieza (`aceptar_invitacion`, `revocar_invitacion`, `previsualizar_invitacion`), no solo a la que
falló: las otras dos comparten el mismo patrón de `RETURNS TABLE` y podrían clonar el bug la
próxima vez que se les toque el cuerpo.

## 6. Vencimiento: 30 días, revocable a mano

**Cerrado.** `expira_en = creado_at + 30 días`. Sin vencimiento automático era un riesgo real: un
WhatsApp reenviado meses después, o un teléfono que cambia de manos, dejaría entrar a alguien a ver
precios y montos de una obra ajena. 30 días es suficiente para el uso real (quien acepta lo hace el
mismo día) y acota la ventana de un link viejo dando vueltas — mismo orden de magnitud que Slack o
Notion. Revocación manual disponible en cualquier momento, independiente del vencimiento.

## 7. Cómo se sostiene el estado entre "pega el código → se registra → vuelve"

El riesgo real: Supabase Auth exige confirmación de email (`AuthService._mensajeAmigable` ya tiene
el mensaje "Confirmá tu email antes de iniciar sesión"), así que entre "toca Registrarme" y "vuelve
con sesión activa" pueden pasar minutos u horas, con la app cerrada en el medio. Nada en memoria
(`Navigator`, estado de widget) sobrevive eso.

**Diseño, versión final (ajustada tras probar el circuito, 2026-09-10)**: `SharedPreferences` sigue
siendo el mecanismo para cruzar el reinicio — mismo patrón que ya usa el proyecto
(`CartelCostoManoObra`, aviso de zona UOCRA) — pero la primera versión tenía dos problemas reales
que Seba encontró al probarla:

1. **La pantalla de pegar el código guardaba y volvía sin explicar nada.** Corregido con
   `previsualizar_invitacion(codigo)` (`0096_invitaciones_previsualizar.sql`), de solo lectura y
   sin sesión (primer `grant ... to anon` del proyecto — todo lo demás requiere estar logueado).
   `AceptarInvitacionScreen` pasa a dos pasos: pegar el código → ver "Te invitaron a la obra
   '{nombre}' como {rol}" con todas las letras → recién ahí, si no hay sesión, se guarda el código
   y se vuelve a `LoginScreen` (no a una pantalla neutra).
2. **El código se aplicaba al primer usuario que iniciara sesión en el dispositivo, sin
   preguntar.** Si el código quedaba guardado y después entraba una cuenta distinta a la que lo
   pegó (celular prestado, otra persona logueándose en el mismo instalador), se sumaba a quien no
   correspondía. Corregido: en vez de canjear directo, `ObrasListScreen.initState()` ahora
   previsualiza el código pendiente y pide confirmación explícita — "Tenés una invitación a la
   obra '{nombre}' como {rol}. ¿Sumarte ahora?" — antes de llamar a `aceptar_invitacion`. El
   código pendiente se borra apenas se resuelve la pregunta (confirme o no), para no insistir en
   cada login siguiente.

`previsualizar_invitacion` no tiene el freno de fuerza bruta de `aceptar_invitacion` (§5) — no
puede, porque `audit_log.usuario_id` es `not null` y quien previsualiza puede no tener sesión
todavía. Límite aceptado, no resuelto: revela el nombre de una obra real a quien adivine un código
válido, sin darle acceso (eso sigue exigiendo `aceptar_invitacion`, con sesión y con freno). El
espacio de 852.891 millones de combinaciones (§5) sigue siendo la defensa real contra la
adivinanza a ciegas.

## 8. Sacar a alguien de la obra — ya resuelto por lo que existe

No hace falta diseño nuevo. Verificado contra `0019_obra_subitems.sql` y
`0052_certificado_subitems_avance.sql`: lo que alguien carga queda con
`agregado_por_usuario_id`/`creado_por` apuntando a su `auth.users.id`, **sin ninguna relación con
`obra_members`** — ni FK, ni cascada. Sacar a alguien no puede borrar lo que cargó porque no hay
ningún camino de datos que los conecte.

El mecanismo ya es `activo = false`, el mismo que `obra_members` usa para "revocar sin borrar"
(`0001_obra_members.sql`: "Sin política DELETE: nadie borra filas"), con la política
`obra_members_update` ya permitiendo que `admin_maestro` lo haga.

**Ajuste al construir la Tanda 2**: en vez de que la pantalla dispare ese UPDATE directo, pasa por
`quitar_miembro_obra(p_obra_member_id)` (`0098_quitar_miembro_obra.sql`, `SECURITY DEFINER`,
mismo patrón que `aceptar_invitacion`/`revocar_invitacion`) — necesario para la guarda de §10 (no
dejar la obra sin ningún `admin_maestro` activo, algo que un UPDATE crudo bajo RLS no puede
expresar) y para el rastro garantizado en `audit_log`. Nunca se toca `auth.users`, nunca se borra
una fila de `obra_members` — eso no cambió.

## 9. Alcance: dos tandas — LAS DOS CERRADAS 2026-09-10

**Tanda 1**: tabla `invitaciones` + RLS + las funciones (crear/revocar directo bajo RLS,
`aceptar_invitacion`/`previsualizar_invitacion` `SECURITY DEFINER`) + pantalla de invitar (rol +
permisos + aviso PRO) + pantalla de ingresar código + persistencia del código pendiente. Cierra
"alguien nuevo entra a la obra por invitación", que es lo que bloquea la licitación privada.
Verificada de punta a punta por Seba: generar, compartir, previsualizar y aceptar funcionan.

**Tanda 2**: panel de miembros de la obra — listar activos, invitaciones pendientes/histórico,
copiar código, revocar, y sacar miembro (con la guarda del último administrador). Ver §10/§11.

## 10. Tanda 2: diagnóstico

**Quién ve la pantalla y quién actúa.** Los miembros activos los ve cualquier miembro de la obra —
coincide con la RLS: `obra_members_select` (`0004_rls_etapa3.sql`) ya es `is_obra_member(obra_id)`
sin restricción de rol. Las invitaciones (pendientes e histórico) **no** — `invitaciones_select`
solo deja verlas a `admin_maestro`, a quien tiene `puede_invitar_terceros`, o a quien invitó esa
fila puntual. La pantalla usa un solo getter (`puedeInvitarMiembros`, ya existente) para decidir si
pide y muestra esa sección — cubre los primeros dos casos; el tercero (invitaste una vez y después
perdiste `puede_invitar_terceros`) queda sin cubrir en la UI a propósito, es un caso borde que no
justifica un getter aparte, y el dato sigue protegido por RLS igual, solo no se muestra ahí.

Para **revocar** una invitación, la función `revocar_invitacion` ya acepta esos mismos tres casos
— la pantalla la ofrece bajo el mismo `puedeInvitarMiembros`, con la misma salvedad del párrafo de
arriba.

Para **sacar a un miembro**, la RLS cruda (`obra_members_update`) es más amplia que "solo
administrador": también deja que `cliente_principal` actualice filas de `invitado_apoderado`
(gestión de su propia delegación de firma). **Decisión: la Tanda 2 no cubre ese caso.** Es el
"Panel de Delegación de Firma" que `CLAUDE.md` ya prevé como pieza aparte — mezclarlo acá hubiera
sido una tabla más de casos especiales para un permiso que tiene su propia pantalla futura. Por
eso `quitar_miembro_obra` (§8) es estrictamente `admin_maestro`, más estricto que lo que la RLS
cruda permitiría, y `UserContext.puedeQuitarMiembros` (regla 11) refleja exactamente eso.

**Cambiar el rol de alguien ya adentro.** No hace falta "editar" una fila — el modelo ya resuelve
esto por diseño: roles combinables son *varias filas* de `obra_members` para el mismo
`(obra_id, usuario_id)`. Agregar un rol nuevo a alguien que ya está en la obra es un INSERT directo
(el admin ya conoce su `usuario_id`, no hace falta invitación — `obra_members_insert` ya lo permite
sin el chequeo de auto-atribución que sí exige `invitaciones_insert`); quitar un rol es desactivar
esa fila puntual con el mismo mecanismo que sacar a alguien. Lo que **no** tiene sentido es un
UPDATE que pise el campo `rol` de una fila existente — rompería contra el
`unique(obra_id, usuario_id, rol)` si esa persona ya tuviera el rol destino en otra fila, y no es
como el resto del esquema modela "cambiar de rol". **Fuera de alcance de esta tanda**: el pedido
explícito era "ver miembros, ver invitaciones, revocar y sacar" — agregar/quitar roles
individuales queda anotado acá para cuando haga falta, no construido ahora.

**Guarda del último administrador.** Resuelta del lado del servidor, no solo en la pantalla —
`quitar_miembro_obra` cuenta los `admin_maestro` activos de la obra antes de desactivar uno, y
si es el único, corta con una excepción clara en vez de dejar la obra sin nadie que la administre.
Server-side y no solo client-side a propósito: es la misma razón por la que el resto del proyecto
pone la autoridad real en RLS/funciones, nunca solo en la UI (`docs/diagnostico_general_producto.md`
§3.3, "toda la seguridad descansa en RLS").

**Dónde vive la pantalla.** Confirmado: desde la obra, en `PresupuestosScreen`. Cambio de diseño
sobre la Tanda 1: el ícono que antes abría `InvitarMiembroScreen` directo (gateado por
`puedeInvitarMiembros`) ahora abre `MiembrosObraScreen` sin gate de rol — la ve cualquier miembro,
como corresponde a "ver miembros" — y "Invitar" pasa a vivir *adentro* de esa pantalla, gateado ahí.
Un solo punto de entrada para toda la gestión de gente, no dos íconos.

**Gap real encontrado — RESUELTO el mismo día, ver `docs/perfiles_nombre_telefono_diseno.md`.**
No había ninguna forma de mostrar un nombre legible, ni de un miembro ni de quien invitó a
alguien — `perfiles` (`0014_perfiles.sql`) solo tenía `usuario_id`/`es_pro`. Se agregaron
`nombre`/`telefono` (`0099_perfiles_nombre_telefono.sql`), pedidos en el registro y editables
después (`EditarPerfilScreen`), visibles entre compañeros de obra vía `get_perfiles_de_obra` —
nunca `es_pro`, que sigue siendo estrictamente privado de cada uno.

## 11. Archivos (Tanda 2) — CERRADO 2026-09-10

Nuevos:
- `supabase/migrations/0098_quitar_miembro_obra.sql` — función con la guarda del último admin.
- `lib/presentation/obra_detalle/screens/miembros_obra_screen.dart` — miembros activos,
  invitaciones vigentes (copiar/revocar) e histórico, punto de entrada único.

Tocados:
- `lib/core/segurity/user_context.dart` — getter nuevo `puedeQuitarMiembros` (regla de
  visibilidad 11), `admin_maestro` únicamente, a propósito más estricto que la RLS cruda (ver §10).
- `lib/services/obra_members_repository.dart` — `quitarMiembro`, y un helper `_conLog` (mismo
  patrón que `InvitacionesRepository`, code/message/details/hint de Postgres a la consola antes de
  relanzar).
- `lib/services/invitaciones_repository.dart` — `getTodasLasInvitaciones` (todos los estados, para
  separar vigentes de histórico del lado de la UI).
- `lib/presentation/obra_detalle/screens/presupuestos_screen.dart` — el ícono del AppBar cambia de
  abrir `InvitarMiembroScreen` (gateado) a abrir `MiembrosObraScreen` (sin gate) — ver §10, "Dónde
  vive la pantalla".

`flutter analyze` limpio (49 infos preexistentes, ninguna nueva). **Sin verificar en el emulador
todavía.**

## 12. Archivos (Tanda 1) — CERRADO 2026-09-10

Nuevos:
- `supabase/migrations/0095_invitaciones.sql` — aplicada y verificada.
- `supabase/migrations/0096_invitaciones_previsualizar.sql` — `previsualizar_invitacion`, aplicada
  tras el ajuste de §7.
- `lib/data/models/invitacion.dart` — `Invitacion`, `ResultadoInvitacionAceptada`,
  `VistaPreviaInvitacion`, `columnaDesdeRol`/`rolDesdeColumna`, `etiquetaRol`.
- `lib/services/invitaciones_repository.dart` — `crearInvitacion`, `getInvitacionesPendientes`
  (para la Tanda 2), `previsualizarInvitacion`, `aceptarInvitacion`, `revocarInvitacion`, y
  `InvitacionPendiente` (`SharedPreferences`, guardar/leer/borrar el código entre sesión y
  registro).
- `lib/presentation/obra_detalle/screens/invitar_miembro_screen.dart`
- `lib/presentation/auth/aceptar_invitacion_screen.dart` — dos pasos: previsualizar y confirmar.

Tocados:
- `lib/core/segurity/user_context.dart` — getter nuevo `puedeInvitarMiembros` (regla de
  visibilidad 10), mismo criterio que la política `invitaciones_insert`.
- `lib/presentation/obra_detalle/screens/presupuestos_screen.dart` — ícono "Invitar" en el AppBar,
  gateado por `puedeInvitarMiembros`.
- `lib/presentation/dashboard/obras_list_screen.dart` — `_canjearInvitacionPendiente()` en
  `initState` (previsualiza y pide confirmación, ver §7), y el punto de entrada de "Ingresar
  código" plegado en un menú junto con "Ver obras en mapa" (`PopupMenuButton`, un solo ícono) en
  vez de un botón propio — ajuste de interfaz (feedback de Seba): un cuarto botón en el AppBar
  tapaba el indicador Free/PRO, que tiene que quedar siempre visible.
- `lib/presentation/auth/login_screen.dart` — enlace "¿Tenés un código de invitación?" para quien
  todavía no tiene cuenta.

**Sin usar `lib/main.dart` ni tocar `auth_gate.dart`**, a diferencia de lo que preveía la primera
versión de este documento: la navegación entre pantallas de esta pieza es `Navigator.push` directo
(mismo patrón que ya usa `ObrasListScreen` para abrir `PresupuestosScreen`), no rutas con nombre —
`main.dart` solo registra los dos puntos de entrada de toda la app (`/` y `/presupuesto`), no cada
pantalla intermedia. Y el chequeo del código pendiente quedó en `ObrasListScreen.initState()` en
vez de en `AuthGate`: es el primer momento con sesión activa que además tiene un `Scaffold` para
mostrar la confirmación, y corre una sola vez por sesión real porque `AuthGate` reusa la misma
instancia (es `const`) en los rebuilds que no cambian de sesión.

**Sin tocar `obra_members_repository.dart`** — el método para desactivar un miembro es
exclusivamente de la Tanda 2, no hizo falta adelantarlo.

**Sin verificar en el emulador todavía** — falta correr el circuito de punta a punta (generar
código, pegarlo sin sesión, registrarse, confirmar que se aplica solo; y con sesión activa,
directo).

## 13. Qué queda para después

- **Verificación en el emulador de la Tanda 2** — nunca se probó (Tanda 1 sí, de punta a punta).
- **Verificación de nombre/teléfono** (`docs/perfiles_nombre_telefono_diseno.md`) — migración
  0099 sin aplicar, sin correr en el emulador.
- **Agregar/quitar roles individuales** a alguien que ya está en la obra — mecánicamente simple
  (§10), pero fuera del pedido explícito de esta tanda.
- El **Panel de Delegación de Firma** (`cliente_principal` gestionando su `invitado_apoderado`) —
  mencionado en `CLAUDE.md`, deliberadamente no cubierto por `quitar_miembro_obra` (§10).
- El deep link / Universal Links / App Links real — mejora pendiente en §5, condicionado a que la
  web esté publicada.
