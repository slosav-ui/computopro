import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_primera_app/services/excel_lector_xlsx.dart';
import 'package:mi_primera_app/services/excel_parser.dart';

/// Que el importador pueda **abrir** las planillas reales de un arquitecto.
///
/// **El criterio es de producto, no técnico** (Seba, 2026-09-15): *"el usuario sube la planilla tal
/// como la tiene y la app la tiene que abrir. No se le pide que la modifique ni que pruebe con
/// otra."* Por eso estos tests viven en el repositorio: no son para diagnosticar una vez, son para
/// que abrir un Excel real no se vuelva a romper sin que nadie se entere.
///
/// Dos capas: los casos mínimos de `test/fixtures/`, que aíslan **una sola cosa rara cada uno** y
/// por eso dicen exactamente qué se rompió; y las planillas reales de `docs/planillas_prueba/`, que
/// son la prueba de verdad -- una planilla real siempre trae algo que ningún caso sintético previó.
void main() {
  Uint8List leer(String ruta) => File(ruta).readAsBytesSync();

  group('Casos mínimos: lo que rompía al abrir', () {
    test('formatos de número redefinidos por debajo de 164 (caso Hotel Milan)', () {
      // Excel redefine los ids 43 y 44 (contabilidad) en cualquier planilla con columnas de plata.
      // Es válido y Excel lo escribe siempre; `package:excel` cortaba con
      // "custom numFmtId starts at 164 but found a value of 43".
      expect(
        () => ExcelParser.listarHojas(leer('test/fixtures/caso_numfmt_43.xlsx')),
        returnsNormally,
      );
    });

    test('una fila con las 16.384 columnas (caso Bocián)', () {
      // `package:excel` cortaba con "Reached Max (16384) or (XFD) columns value", y encima por un
      // error de cuenta suyo: comparaba una CANTIDAD de columnas contra el límite de Excel.
      expect(ExcelParser.listarHojas(leer('test/fixtures/caso_16384_columnas.xlsx')), isNotEmpty);
    });
  });

  group('Planillas reales', () {
    const milan = 'docs/planillas_prueba/PLANILLA COTIZACION Hotel Milan.xlsx';
    const bocian = 'docs/planillas_prueba/PRESUPUESTO AMPLIACION J BOCIAN.xlsx';

    test('Hotel Milan abre y lista sus 11 hojas', () {
      final hojas = ExcelParser.listarHojas(leer(milan));
      expect(hojas, hasLength(11));
      expect(hojas, contains('COMPUTO'));
      // El orden de las pestañas no es el de los archivos internos (la primera es sheet8.xml), así
      // que esto también verifica que las hojas se resuelven por su relación y no por posición.
      expect(hojas.first, 'Hoja2');
    });

    test('Bocián abre y lista GLOVAL y Hoja1', () {
      expect(ExcelParser.listarHojas(leer(bocian)), ['GLOVAL', 'Hoja1']);
    });

    test('Bocián: GLOVAL queda en 12 columnas y sin los ColumnaN de la fila 1', () {
      final filas = LibroXlsx.desdeBytes(leer(bocian)).filasDe('GLOVAL');

      expect(filas, hasLength(49), reason: 'El alto sale del contenido, no del dimension A1:XFD81');

      final ancho = filas.map((f) => f.length).fold<int>(0, (a, b) => a > b ? a : b);
      expect(ancho, 12, reason: 'El contenido real va de la A a la L');

      final relleno = RegExp(r'^columnas?\s*\d+$', caseSensitive: false);
      final quedaron = filas
          .expand((f) => f)
          .whereType<String>()
          .where((t) => relleno.hasMatch(t.trim()))
          .toList();
      expect(quedaron, isEmpty, reason: 'Los ColumnaN de la fila 1 no son contenido');
    });

    test('Bocián: los textos se leen con sus acentos', () {
      // Leer el XML byte a byte en vez de como UTF-8 devolvía "DescripciÃ³n" y "BaÃ±o quimico". Un
      // acento roto en la descripción de una partida viaja hasta el presupuesto impreso.
      final textos = LibroXlsx.desdeBytes(leer(bocian))
          .filasDe('GLOVAL')
          .expand((f) => f)
          .whereType<String>()
          .toList();
      expect(textos, contains('Descripción'));
      expect(textos.any((t) => t.contains('Ã')), isFalse);
    });

    test('Bocián: GLOVAL tiene los rubros y las 15 partidas numeradas', () {
      // Se mide sobre la grilla, no sobre `procesarFilas`: el reconocimiento de encabezados es otra
      // pieza (ver el test de abajo). Acá lo que se prueba es que el LECTOR trae el contenido.
      final filas = LibroXlsx.desdeBytes(leer(bocian)).filasDe('GLOVAL');

      // Partidas: primera columna con un número correlativo.
      final numeradas = filas.where((f) => f.isNotEmpty && f[0] is num).length;
      expect(numeradas, 15, reason: 'Las 15 partidas numeradas de la planilla');

      // Rubros: filas sin número, con el título en la segunda columna.
      final textos = filas.expand((f) => f).whereType<String>().toList();
      expect(textos, contains('VARIOS'));
      expect(textos, contains('CERRAMIENTO EXTERIOR E INTERIOR'));
    });

    test('Hotel Milan: de COMPUTO salen partidas', () {
      final partidas = ExcelParser.procesarFilas(leer(milan), ['COMPUTO']);
      expect(partidas, isNotEmpty);
      expect(partidas.first['descripcion_texto'], isA<String>());
    });

    test('Bocián: de GLOVAL salen las 15 partidas ya interpretadas', () {
      // PENDIENTE, y no es del lector: GLOVAL **abre bien** -- 49 filas, 12 columnas, acentos
      // correctos, y el test de arriba encuentra las 15 partidas y los rubros en la grilla.
      //
      // Lo que falla es el reconocimiento de encabezados, que exige coincidencia exacta contra una
      // lista de sinónimos. La fila 7 de esta planilla dice:
      //
      //     Rubro | Descripción | Un. | Cant. Total | Precio uni Mano de Obra | Precio item
      //
      // "Un." no es "un", "Cant. Total" no es "cant.", y "Precio uni Mano de Obra" no figura. Como
      // se exige descripción + (cantidad o precio), no se detecta encabezado y no sale ninguna
      // partida.
      //
      // Arreglarlo es cambiar cómo el importador INTERPRETA la planilla, que quedó explícitamente
      // fuera de esta tanda ("esto es solo poder abrir el archivo"). Cuando se decida, se saca el
      // skip y esto tiene que dar 15.
      markTestSkipped(
        'Pendiente de decisión: los encabezados de GLOVAL no coinciden con los sinónimos actuales.',
      );
    });
  });
}
