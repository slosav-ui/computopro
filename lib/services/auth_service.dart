import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Excepción con mensaje ya traducido a español, lista para mostrar en la UI.
class AuthFriendlyException implements Exception {
  final String message;
  const AuthFriendlyException(this.message);
}

/// Envoltorio sobre Supabase Auth (email/contraseña) para la Etapa 1
/// del sistema de permisos. Traduce las excepciones de Supabase a
/// mensajes en español listos para mostrar en la UI.
class AuthService {
  final SupabaseClient _client = Supabase.instance.client;

  Session? get sesionActual => _client.auth.currentSession;
  User? get usuarioActual => _client.auth.currentUser;
  Stream<AuthState> get cambiosDeEstado => _client.auth.onAuthStateChange;

  /// [nombre]/[telefono]/[matricula] viajan como `data` del signup (`raw_user_meta_data` en
  /// `auth.users`) -- el trigger `handle_new_user_perfil`
  /// (`0099_perfiles_nombre_telefono.sql`/`0100_perfiles_matricula.sql`) los lee de ahí al crear
  /// la fila de `perfiles`. Sin esto acá, no hay otro momento en que la app conozca estos datos
  /// de alguien que recién se registra (la sesión todavía no existe para llamar
  /// `actualizar_mi_perfil` antes de este punto).
  Future<void> registrarse({
    required String email,
    required String password,
    required String nombre,
    String? telefono,
    String? matricula,
  }) async {
    try {
      final response = await _client.auth.signUp(
        email: email,
        password: password,
        data: {
          'nombre': nombre,
          if (telefono != null && telefono.isNotEmpty) 'telefono': telefono,
          if (matricula != null && matricula.isNotEmpty) 'matricula': matricula,
        },
      );
      if (response.user != null && (response.user!.identities?.isEmpty ?? false)) {
        throw const AuthFriendlyException('Ese email ya está registrado. Iniciá sesión en su lugar.');
      }
    } on AuthException catch (e) {
      throw AuthFriendlyException(_mensajeAmigable(e));
    }
  }

  Future<void> iniciarSesion({required String email, required String password}) async {
    try {
      await _client.auth.signInWithPassword(email: email, password: password);
    } on AuthException catch (e) {
      throw AuthFriendlyException(_mensajeAmigable(e));
    }
  }

  Future<void> cerrarSesion() => _client.auth.signOut();

  String _mensajeAmigable(AuthException e) {
    final msg = e.message.toLowerCase();
    if (msg.contains('invalid login credentials')) {
      return 'Email o contraseña incorrectos.';
    }
    if (msg.contains('already registered')) {
      return 'Ese email ya está registrado. Iniciá sesión en su lugar.';
    }
    if (msg.contains('unable to validate email') || msg.contains('invalid email')) {
      return 'El email ingresado no es válido.';
    }
    if (msg.contains('password') && (msg.contains('least') || msg.contains('short'))) {
      return 'La contraseña debe tener al menos 6 caracteres.';
    }
    if (msg.contains('email not confirmed')) {
      return 'Confirmá tu email antes de iniciar sesión.';
    }
    return e.message;
  }
}

/// El último mail con el que se entró en este dispositivo, para dejarlo precargado la próxima vez
/// (pedido de Seba, 2026-09-14: *"alguien en obra con el teléfono en la mano no va a querer tipear
/// la dirección completa cada vez"*). Mismo mecanismo que `InvitacionPendiente`:
/// `SharedPreferences`, una clave, tres métodos.
///
/// **Solo el mail, nunca la contraseña.** Guardar una contraseña acá sería guardarla en claro en el
/// dispositivo; la contraseña la recuerda el llavero del sistema o el navegador, que es para lo que
/// están los `autofillHints` y el `AutofillGroup` de la pantalla de login.
///
/// No se borra al cerrar sesión: cerrar sesión es irse por un rato, y volver a entrar con el mail
/// ya puesto es justamente el caso que esto resuelve. Se pisa solo cuando alguien entra con otro
/// mail -- en un teléfono compartido, el último que entró es el que queda.
class UltimoEmail {
  static const _clave = 'auth_ultimo_email';

  static Future<void> guardar(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_clave, email.trim());
  }

  static Future<String?> leer() async {
    final prefs = await SharedPreferences.getInstance();
    final valor = prefs.getString(_clave)?.trim();
    return (valor == null || valor.isEmpty) ? null : valor;
  }

  static Future<void> borrar() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_clave);
  }
}
