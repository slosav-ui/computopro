import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Importa tu archivo principal (ajusta la ruta según la ubicación de tu main.dart)
import 'package:mi_primera_app/main.dart';

void main() {
  testWidgets('Verificación de arranque de la app', (WidgetTester tester) async {
    // Usamos el nombre exacto de tu clase principal
    await tester.pumpWidget(const MiAppApu());

    // Verificación básica de que la app arranca correctamente
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
