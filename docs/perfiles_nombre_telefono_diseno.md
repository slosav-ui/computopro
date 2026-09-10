# Nombre y teléfono en `perfiles` — diseño y estado (2026-09-10)

**Estado: aplicado en código, sin verificar en el emulador ni aplicar la migración.** Resuelve un
gap real encontrado al construir la Tanda 2 de invitaciones
(`docs/invitaciones_diseno_datos.md` §10): la pantalla de miembros mostraba un UUID acortado
porque no había ningún dato legible para mostrar — "un identificador cortado en vez de un nombre
no le sirve al usuario, no sabe quién es quién" (Seba).

## 1. Por qué no alcanza con una columna nueva y una política de lectura

`perfiles` (`0014_perfiles.sql`) tiene una sola columna editable en potencia, `es_pro`, y **a
propósito no tiene ninguna política UPDATE** — el propio comentario original explica por qué: un
`usuario_id = auth.uid()` genérico dejaría que cualquiera se ponga PRO gratis llamando la API
directo. Agregar `nombre`/`telefono` con una política UPDATE simple hubiera reabierto exactamente
ese agujero, porque una política es por fila, no por columna: no hay forma de decir "esta persona
puede editar `nombre` pero no `es_pro`" con una sola `USING`/`WITH CHECK`.

Mismo problema del otro lado, la lectura: `perfiles_select` es `usuario_id = auth.uid()`, estricto.
Ampliarlo a "compañeros de obra" para que se vea `nombre`/`telefono` también destaparía `es_pro`
de esa misma fila — RLS tampoco distingue columnas para lectura.

**Solución: dos funciones `SECURITY DEFINER`, mismo patrón que el resto del proyecto**
(`aceptar_invitacion`, `previsualizar_invitacion`, `quitar_miembro_obra`) — proyectan/tocan
exactamente lo que corresponde, nunca `es_pro`, sin necesidad de una política de tabla más
permisiva:

- **Escribir**: `actualizar_mi_perfil(p_nombre, p_telefono)` — solo la propia fila
  (`auth.uid()`), solo esas dos columnas. La tabla sigue sin política UPDATE.
- **Leer a otros**: `get_perfiles_de_obra(p_obra_id)` — nombre/teléfono de los compañeros activos
  de una obra puntual, nunca `es_pro`, y falla si quien pregunta no es miembro de esa obra.

Migración: `supabase/migrations/0099_perfiles_nombre_telefono.sql`.

## 2. Se pide en el registro

`AuthService.registrarse` ahora exige `nombre` (obligatorio) y acepta `telefono` (opcional), los
manda como `data` del `signUp` de Supabase Auth (`raw_user_meta_data` en `auth.users`), y el
trigger `handle_new_user_perfil` (ya existía, se lo actualizó) los lee de ahí al crear la fila de
`perfiles`. `LoginScreen` pide los dos campos solo en modo registro.

## 3. Usuarios que ya existen — sin backfill posible, con salida

Supabase Auth (email/contraseña) nunca capturó un nombre ni un teléfono — no hay ningún dato del
que inferirlos para quien ya se registró antes de esta pieza. Las columnas quedan `null` para
esas cuentas, sin backfill real (a diferencia de `es_pro`, que sí tenía un default razonable).

Dos salidas, ninguna bloqueante:

- La pantalla de miembros sigue degradando a `ID: xxxxxxxx…` cuando `nombre` es `null` — nunca se
  rompe por falta del dato.
- **`EditarPerfilScreen`** (nueva, reachable desde el menú de `ObrasListScreen`, "Mi perfil"):
  cualquiera — nuevo o existente — puede cargar o corregir su nombre/teléfono cuando quiera, sin
  que nadie se lo pida ni la app lo fuerce.

## 4. Teléfono, no solo nombre

Sumado por pedido explícito de Seba: en obra se llama por teléfono, no se manda mail. Mismo
mecanismo de escritura acotada (`actualizar_mi_perfil`) y lectura acotada
(`get_perfiles_de_obra`), mismo criterio de privacidad — visible entre compañeros de obra, no a
cualquier usuario del sistema. Opcional en el registro y en "Mi perfil": no todos van a querer
compartirlo, y no hay razón para bloquear el alta por eso.

## 5. Archivos

Nuevos:
- `supabase/migrations/0099_perfiles_nombre_telefono.sql`
- `lib/data/models/perfil_basico.dart`
- `lib/presentation/dashboard/editar_perfil_screen.dart`

Tocados:
- `lib/services/perfil_repository.dart` — `actualizarMiPerfil`, `getMiPerfil`,
  `getPerfilesDeObra`, logging `_conLog` (mismo patrón que `InvitacionesRepository`).
- `lib/services/auth_service.dart` — `registrarse` pide `nombre`/`telefono`.
- `lib/presentation/auth/login_screen.dart` — campos nuevos, solo en modo registro.
- `lib/presentation/dashboard/obras_list_screen.dart` — "Mi perfil" en el menú.
- `lib/presentation/obra_detalle/screens/miembros_obra_screen.dart` — muestra nombre (o el UUID
  acortado si no hay), teléfono, y **quién invitó a cada miembro** — esto último era parte del
  pedido original de la Tanda 2 y había quedado afuera de la primera versión de la pantalla; se
  corrige de paso acá, aprovechando que ya se resuelve el nombre.

`flutter analyze` limpio (49 infos preexistentes, ninguna nueva). **Sin aplicar la migración,
sin correr en el emulador todavía.**
