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

  /// [nombre]/[telefono] viajan como `data` del signup (`raw_user_meta_data` en `auth.users`) --
  /// el trigger `handle_new_user_perfil` (`0099_perfiles_nombre_telefono.sql`) los lee de ahí al
  /// crear la fila de `perfiles`. Sin esto acá, no hay otro momento en que la app conozca el
  /// nombre de alguien que recién se registra (la sesión todavía no existe para llamar
  /// `actualizar_mi_perfil` antes de este punto).
  Future<void> registrarse({
    required String email,
    required String password,
    required String nombre,
    String? telefono,
  }) async {
    try {
      final response = await _client.auth.signUp(
        email: email,
        password: password,
        data: {'nombre': nombre, if (telefono != null && telefono.isNotEmpty) 'telefono': telefono},
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
