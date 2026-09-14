import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login_screen.dart';
import '../dashboard/obras_list_screen.dart';
import '../../services/push_service.dart';

/// Punto de entrada de la app: muestra "Mis Obras" si hay una sesión de
/// Supabase Auth activa, o el login/registro si no la hay. Reacciona en
/// vivo a login/logout mediante `onAuthStateChange` (Etapa 1 del sistema
/// de permisos: ver CLAUDE.md).
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final PushService _push = PushService();

  /// Con qué usuario se registró ya el token en esta corrida. Evita repetir el registro en cada
  /// evento del stream (`onAuthStateChange` emite también por refresh de token, que pasa solo cada
  /// tanto), y a la vez fuerza el registro de nuevo si en este teléfono entra OTRA persona -- ahí el
  /// dispositivo tiene que cambiar de dueño, que es justo lo que resuelve el `unique (token)` de
  /// la 0142.
  String? _registradoPara;

  /// Acá y no en `main`: el token se registra **con sesión abierta**, porque la fila de
  /// `dispositivos` es del usuario logueado. En cada arranque con sesión, no solo al iniciar
  /// sesión -- el token de FCM rota solo.
  void _registrarSiHaySesion(Session? session) {
    final usuarioId = session?.user.id;
    if (usuarioId == null || usuarioId == _registradoPara) return;
    _registradoPara = usuarioId;
    _push.registrarEsteDispositivo();
  }

  @override
  void initState() {
    super.initState();
    _registrarSiHaySesion(Supabase.instance.client.auth.currentSession);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = Supabase.instance.client.auth.currentSession;
        if (session != null) {
          _registrarSiHaySesion(session);
          return const ObrasListScreen();
        }
        _registradoPara = null;
        return const LoginScreen();
      },
    );
  }
}
