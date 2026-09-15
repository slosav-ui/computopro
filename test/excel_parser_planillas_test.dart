import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_primera_app/services/excel_parser.dart';

/// Planillas reales que el importador tiene que poder abrir, y los dos casos mínimos que aíslan
/// por qué hoy no puede.
///
/// **El criterio es de producto, no técnico** (Seba, 2026-09-15): *"el usuario sube la planilla tal
/// como la tiene y la app la tiene que abrir. No se le pide que la modifique ni que pruebe con
/// otra."* Por eso estos tests viven en el repositorio: no son para diagnosticar una vez, son para
/// que abrir un Excel real no se vuelva a romper sin que nadie se entere.
///
/// Los dos archivos de `test/fixtures/` son **mínimos y sintéticos**: cada uno tiene una sola cosa
/// rara y nada más, así que cuando fallan dicen exactamente qué falla. Las planillas reales de
/// Seba (`docs/planillas_prueba/`) se suman cuando estén en el repositorio -- los tests que las
/// usan se saltean solos mientras no estén, en vez de fallar en rojo por un archivo ausente.
void main() {
  group('Casos mínimos: lo que hoy rompe al abrir', () {
    test('formatos de número redefinidos por debajo de 164 (caso Hotel Milan)', () {
      final bytes = File('test/fixtures/caso_numfmt_43.xlsx').readAsBytesSync();

      // Excel redefine los ids 43 y 44 (formatos contables) en cualquier planilla con columnas de
      // moneda. Es válido y Excel lo escribe siempre; el paquete `excel` lo rechaza.
      expect(
        () => ExcelParser.listarHojas(bytes),
        returnsNormally,
        reason: 'Una planilla con formatos de moneda tiene que poder abrirse',
      );
    });

    test('una fila con las 16.384 columnas (caso Bocián)', () {
      final bytes = File('test/fixtures/caso_16384_columnas.xlsx').readAsBytesSync();

      // Resto de una tabla con encabezados automáticos: la fila 1 tiene "Columna1".."Columna16384"
      // y el contenido real usa de A a L.
      expect(
        () => ExcelParser.listarHojas(bytes),
        returnsNormally,
        reason: 'Una planilla con una fila de relleno ancha tiene que poder abrirse',
      );
    });
  });

  group('Planillas reales', () {
    for (final nombre in const [
      'PLANILLA_COTIZACION_Hotel_Milan.xlsx',
      'PRESUPUESTO_AMPLIACION_J_BOCIAN.xlsx',
    ]) {
      test('abre $nombre', () {
        final archivo = File('docs/planillas_prueba/$nombre');
        if (!archivo.existsSync()) {
          markTestSkipped('Falta docs/planillas_prueba/$nombre');
          return;
        }
        final hojas = ExcelParser.listarHojas(archivo.readAsBytesSync());
        expect(hojas, isNotEmpty, reason: 'Tiene que devolver al menos una hoja');
      });
    }
  });
}
