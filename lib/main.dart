import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/app_theme.dart';
import 'core/network/timeout_http_client.dart';
import 'presentation/auth/auth_gate.dart';
import 'presentation/obra_detalle/screens/presupuestos_screen.dart';

// Se pasan en build/run time via --dart-define-from-file=env.json
// (ver env.example.json). Nunca hardcodear estos valores en el repo.
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: _supabaseUrl,
    publishableKey: _supabaseAnonKey,
    httpClient: TimeoutHttpClient(http.Client()),
  );
  runApp(const MiAppApu());
}

class MiAppApu extends StatelessWidget {
  const MiAppApu({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gestión de Obras y Presupuestos',
      debugShowCheckedModeBanner: false,

      // Configuración de Idioma / Localización
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('es', 'AR'),
        Locale('es', 'ES'),
      ],
      locale: const Locale('es', 'AR'),

      // Tema Global Integrado
      theme: AppTheme.lightTheme,

      // Enrutamiento Principal
      initialRoute: '/',
      onGenerateRoute: (settings) {
        if (settings.name == '/') {
          return MaterialPageRoute(
            builder: (context) => const AuthGate(),
          );
        }

        if (settings.name == '/presupuesto') {
          final args = settings.arguments;
          return MaterialPageRoute(
            builder: (context) => PresupuestosScreen(obra: args),
          );
        }

        return null;
      },
    );
  }
}