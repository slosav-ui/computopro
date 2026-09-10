# Invitaciones a una obra — diseño de datos (2026-09-10)

**Estado: Tanda 1 aplicada y con Dart escrito, 2026-09-10.** Migración `0095_invitaciones.sql`
aplicada y verificada por Seba (2 políticas, 3 funciones, código de ejemplo generado sin
caracteres confusos). Del lado de Dart: modelo, repositorio, las dos pantallas
(`InvitarMiembroScreen`/`AceptarInvitacionScreen`), el getter `UserContext.puedeInvitarMiembros`,
y los puntos de entrada (ícono en `PresupuestosScreen` para invitar, ícono en `ObrasListScreen` y
enlace en `LoginScreen` para ingresar código) — todo escrito, sin verificar en el emulador
todavía. Tanda 2 (panel de miembros, revocar) sigue sin empezar. Es el punto 4 del orden de
ejecución
(`docs/diagnostico_general_producto.md`) y la dependencia real de
`docs/licitacion_privada_presupuestos_diseno.md` ("por invitación desde la app" no se puede
construir sin esto). Diagnóstico completo hecho contra el código real, no contra la spec —
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

**Diseño**: apenas se pega el código, se guarda en `SharedPreferences` — mismo mecanismo que ya usa
el proyecto para estado que cruza reinicios (`CartelCostoManoObra`, aviso de zona UOCRA).
`AuthGate` (ya reactivo a `onAuthStateChange`) chequea si hay un token pendiente cada vez que
detecta sesión activa: si lo hay, llama a `aceptar_invitacion`, muestra el resultado, borra el
token guardado. Cubre los tres casos por igual — aceptar en caliente ya logueado, registrarse y
confirmar por email más tarde, o cerrar la app en el medio — porque no depende de que el flujo en
memoria siga vivo.

## 8. Sacar a alguien de la obra — ya resuelto por lo que existe

No hace falta diseño nuevo. Verificado contra `0019_obra_subitems.sql` y
`0052_certificado_subitems_avance.sql`: lo que alguien carga queda con
`agregado_por_usuario_id`/`creado_por` apuntando a su `auth.users.id`, **sin ninguna relación con
`obra_members`** — ni FK, ni cascada. Sacar a alguien no puede borrar lo que cargó porque no hay
ningún camino de datos que los conecte.

El mecanismo ya es `activo = false`, el mismo que `obra_members` usa para "revocar sin borrar"
(`0001_obra_members.sql`: "Sin política DELETE: nadie borra filas"), con la política
`obra_members_update` ya permitiendo que `admin_maestro` lo haga. Nunca se toca `auth.users`,
nunca se borra una fila de `obra_members`. Falta solo la pantalla que dispare ese UPDATE — cero
cambio de schema o RLS para esta parte.

## 9. Alcance: dos tandas

**Tanda 1** (esta pieza): tabla `invitaciones` + RLS + las tres funciones (crear/revocar directo
bajo RLS, `aceptar_invitacion` `SECURITY DEFINER`) + pantalla de invitar (rol + permisos + aviso
PRO) + pantalla de ingresar código + persistencia del token pendiente en `AuthGate`. Cierra
"alguien nuevo entra a la obra por invitación", que es lo que bloquea la licitación privada.

**Tanda 2** (después, no bloquea la primera): panel de miembros de la obra — listar activos,
invitaciones pendientes/vencidas, botón revocar/quitar (usa el UPDATE de `activo=false` del §8).

## 10. Archivos (Tanda 1) — CERRADO 2026-09-10

Nuevos:
- `supabase/migrations/0095_invitaciones.sql` — aplicada y verificada.
- `lib/data/models/invitacion.dart` — `Invitacion`, `ResultadoInvitacionAceptada`,
  `columnaDesdeRol`/`rolDesdeColumna`, `etiquetaRol`.
- `lib/services/invitaciones_repository.dart` — `crearInvitacion`, `getInvitacionesPendientes`
  (para la Tanda 2), `aceptarInvitacion`, `revocarInvitacion`, y `InvitacionPendiente`
  (`SharedPreferences`, guardar/leer/borrar el código entre sesión y registro).
- `lib/presentation/obra_detalle/screens/invitar_miembro_screen.dart`
- `lib/presentation/auth/aceptar_invitacion_screen.dart`

Tocados:
- `lib/core/segurity/user_context.dart` — getter nuevo `puedeInvitarMiembros` (regla de
  visibilidad 10), mismo criterio que la política `invitaciones_insert`.
- `lib/presentation/obra_detalle/screens/presupuestos_screen.dart` — ícono "Invitar" en el AppBar,
  gateado por `puedeInvitarMiembros`.
- `lib/presentation/dashboard/obras_list_screen.dart` — ícono "Ingresar código" en el AppBar, y
  `_canjearInvitacionPendiente()` en `initState` (best-effort, silencioso en el fracaso).
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

## 11. Qué queda para después

- La pantalla de gestión de miembros (Tanda 2): listar, revocar (`getInvitacionesPendientes` ya
  existe en el repositorio, `revocarInvitacion` también — falta la pantalla).
- El deep link / Universal Links / App Links real — mejora pendiente en §5, condicionado a que la
  web esté publicada.
- Verificación en el emulador del circuito completo (ver arriba).
