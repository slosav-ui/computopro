import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login_screen.dart';
import '../dashboard/obras_list_screen.dart';

/// Punto de entrada de la app: muestra "Mis Obras" si hay una sesión de
/// Supabase Auth activa, o el login/registro si no la hay. Reacciona en
/// vivo a login/logout mediante `onAuthStateChange` (Etapa 1 del sistema
/// de permisos: ver CLAUDE.md).
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = Supabase.instance.client.auth.currentSession;
        if (session != null) {
          return const ObrasListScreen();
        }
        return const LoginScreen();
      },
    );
  }
}
