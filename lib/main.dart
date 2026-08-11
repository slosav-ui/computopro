import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'config/app_theme.dart';
import 'presentation/dashboard/obras_list_screen.dart';
import 'presentation/obra_detalle/screens/presupuestos_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
            builder: (context) => const ObrasListScreen(),
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