import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Importa tu archivo principal (ajusta la ruta según la ubicación de tu main.dart)
import 'package:mi_primera_app/main.dart';

void main() {
  // La app ahora arranca con AuthGate, que consulta Supabase.instance.client
  // en el primer build. Sin credenciales reales, mockeamos el canal de
  // shared_preferences (que usa internamente para restaurar la sesión) e
  // inicializamos el cliente sin red, para que el widget test pueda montar
  // el árbol.
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('plugins.flutter.io/shared_preferences');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      if (methodCall.method == 'getAll') return <String, dynamic>{};
      return null;
    });

    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
    );
  });

  testWidgets('Verificación de arranque de la app', (WidgetTester tester) async {
    // Usamos el nombre exacto de tu clase principal
    await tester.pumpWidget(const MiAppApu());

    // Verificación básica de que la app arranca correctamente
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
