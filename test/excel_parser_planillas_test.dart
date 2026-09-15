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

    test('Bocián: de GLOVAL salen las 15 partidas ya interpretadas', () {
      // Estuvo saltado hasta que se pudo tocar el reconocimiento de encabezados: la fila 7 de esta
      // planilla dice "Un.", "Cant. Total" y "Precio uni Mano de Obra", y ninguno de los tres
      // figuraba entre los sinónimos.
      final partidas = ExcelParser.procesarFilas(leer(bocian), ['GLOVAL']);
      expect(partidas, hasLength(15));

      // Los rubros son filas de sección, sin número ni precio: su nombre vale para las partidas
      // que vienen abajo, hasta el próximo.
      expect(partidas.first['rubro_texto'], 'VARIOS');
      expect(partidas[1]['rubro_texto'], 'CERRAMIENTO EXTERIOR E INTERIOR');
      expect(partidas.last['rubro_texto'], 'ABERTURAS');
      expect(
        partidas.map((p) => p['rubro_texto']).toSet(),
        {
          'VARIOS',
          'CERRAMIENTO EXTERIOR E INTERIOR',
          'REVESTIMIENTOS INTERIORES',
          'CUBIERTA',
          'PINTURA',
          'PISOS Y CONTRAPISOS',
          'ABERTURAS',
        },
      );

      // Ninguna partida se lleva el número de la planilla en el campo de rubro. Era el bug: cada
      // fila llegaba a la revisión con "1", "2", "3" ahí, y había que reescribir el rubro a mano.
      final numeroComoRubro = RegExp(r'^\d+(\.\d+)*\.?$');
      expect(
        partidas.where((p) => numeroComoRubro.hasMatch('${p['rubro_texto']}')),
        isEmpty,
      );

      // El número no se pierde: queda de respaldo en datos_originales.
      expect(partidas.first['datos_originales']['codigo_planilla'], '1');
      expect(partidas.last['datos_originales']['codigo_planilla'], '15');
    });

    test('Bocián: la unidad sale de la planilla, no se le pide al usuario', () {
      final partidas = ExcelParser.procesarFilas(leer(bocian), ['GLOVAL']);
      // Las 15 traen unidad en la planilla: ninguna se le pregunta al usuario.
      expect(partidas.where((p) => p['unidad_texto'] != null), hasLength(15));
      expect(partidas.first['unidad_texto'], 'GL.');
      expect(partidas[1]['unidad_texto'], 'm2');
      expect(partidas.last['unidad_texto'], 'UND');
    });

    test('Hotel Milan: de COMPUTO salen partidas', () {
      final partidas = ExcelParser.procesarFilas(leer(milan), ['COMPUTO']);
      expect(partidas, hasLength(31));
      expect(partidas.first['descripcion_texto'], 'Replanteo');
      // "1 - TAREAS PRELIMINARES" es una fila sola, sin descripción ni precio, arriba de sus
      // partidas. "UND." no estaba entre los sinónimos de unidad y por eso se le pedía al usuario.
      expect(partidas.first['rubro_texto'], '1 - TAREAS PRELIMINARES');
      expect(partidas.first['unidad_texto'], 'Gl.');
      expect(partidas[1]['unidad_texto'], 'MES');
    });

    test('Hotel Milan: los números entran con dos decimales', () {
      // Excel no guarda lo que se ve: "286.839,00" en pantalla es 286839.00000000006 en el
      // archivo, y así entraban al Cómputo -- los diez decimales que Seba vio en el teléfono.
      final partidas = ExcelParser.procesarFilas(leer(milan), ['COMPUTO']);
      for (final p in partidas) {
        for (final campo in ['cantidad', 'precio_unitario']) {
          final v = p[campo] as double?;
          if (v == null) continue;
          expect(
            v,
            double.parse(v.toStringAsFixed(2)),
            reason: '$campo de "${p['descripcion_texto']}" trae más de dos decimales',
          );
        }
      }
      expect(partidas.first['precio_unitario'], 286839.0);
      expect(partidas[3]['precio_unitario'], 148.25); // 148.25135111111112 en el archivo
    });

    test('El total del ítem no se carga como precio unitario', () {
      // "Precio item" y "P. TOTAL ITEM" son cantidad x unitario. Ponerlos en la columna del
      // unitario multiplica la obra por la cantidad, en silencio.
      final partidas = ExcelParser.procesarFilas(leer(bocian), ['GLOVAL']);
      final pared = partidas[1];
      expect(pared['cantidad'], 49.4);
      expect(pared['precio_unitario'], 4350.0);
      expect(pared['datos_originales']['precio_total_planilla'], 214890.0);
    });

    test('Una cantidad chica de verdad no se redondea a cero', () {
      // 0,008 tn de hierro por m2 es un rendimiento real de un análisis de precios. Redondearlo a
      // 0,01 exagera; redondearlo a 0,00 deja la partida valiendo nada, sin avisar.
      final partidas = ExcelParser.procesarFilas(leer(milan), ['Hoja7']);
      final ceros = partidas.where((p) => p['cantidad'] == 0.0);
      expect(ceros, isEmpty, reason: 'Ninguna cantidad real quedó en cero por el redondeo');
    });
  });
}
