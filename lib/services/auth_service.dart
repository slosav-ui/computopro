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

  Future<void> registrarse({required String email, required String password}) async {
    try {
      final response = await _client.auth.signUp(email: email, password: password);
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
