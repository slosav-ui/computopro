import 'package:flutter_test/flutter_test.dart';
import 'package:mi_primera_app/core/utils/parser_numero_ar.dart';

void main() {
  group('ParserNumeroAr.parsear — tabla acordada', () {
    final casos = <String, double?>{
      '79.318': 79318,
      '8210.567': 8210.57,
      '123.456': 123456,
      '1.058': 1058,
      '9.66': 9.66,
      '8.5': 8.5,
      '1.200,50': 1200.50,
      '1.234.567': 1234567,
      '0.75': 0.75,
      '1500.50': 1500.50,
      '': null,
      'abc': null,
    };

    casos.forEach((entrada, esperado) {
      test('"$entrada" -> $esperado', () {
        expect(ParserNumeroAr.parsear(entrada), esperado);
      });
    });
  });

  group('ParserNumeroAr.parsear — casos borde agregados', () {
    test('negativo con separador de miles: "-79.318" -> -79318', () {
      expect(ParserNumeroAr.parsear('-79.318'), -79318);
    });

    test('negativo decimal: "-8.5" -> -8.5', () {
      expect(ParserNumeroAr.parsear('-8.5'), -8.5);
    });

    test('negativo con dos puntos: "-1.234.567" -> -1234567', () {
      expect(ParserNumeroAr.parsear('-1.234.567'), -1234567);
    });

    test('espacios alrededor: "  79.318  " -> 79318', () {
      expect(ParserNumeroAr.parsear('  79.318  '), 79318);
    });

    test('solo espacios -> null', () {
      expect(ParserNumeroAr.parsear('   '), null);
    });

    test('punto final a mitad de tipeo: "1500." -> 1500', () {
      expect(ParserNumeroAr.parsear('1500.'), 1500);
    });

    test('coma con miles de dos puntos: "1.234.567,89" -> 1234567.89', () {
      expect(ParserNumeroAr.parsear('1.234.567,89'), 1234567.89);
    });

    test('coma decimal sin puntos: "1,5" -> 1.5', () {
      expect(ParserNumeroAr.parsear('1,5'), 1.5);
    });

    test('ceros a la izquierda con miles: "079.318" -> 79318', () {
      expect(ParserNumeroAr.parsear('079.318'), 79318);
    });

    test('solo un signo, sin dígitos -> null', () {
      expect(ParserNumeroAr.parsear('-'), null);
    });

    test('mezcla de letras y números -> null', () {
      expect(ParserNumeroAr.parsear('12a34'), null);
    });

    test('tres dígitos a la izquierda, tres a la derecha: "500.000" -> 500000', () {
      expect(ParserNumeroAr.parsear('500.000'), 500000);
    });
  });

  group('ParserNumeroAr.esInterpretacionDeMiles', () {
    final casos = <String, bool>{
      '1.500': true,
      '79.318': true,
      '9.66': false,
      '1.234.567': false,
      '1.500,50': false,
      '8210.567': false,
    };

    casos.forEach((entrada, esperado) {
      test('"$entrada" -> $esperado', () {
        expect(ParserNumeroAr.esInterpretacionDeMiles(entrada), esperado);
      });
    });

    test('caso borde: negativo ambiguo "-1.500" -> true', () {
      expect(ParserNumeroAr.esInterpretacionDeMiles('-1.500'), true);
    });

    test('caso borde: vacío -> false', () {
      expect(ParserNumeroAr.esInterpretacionDeMiles(''), false);
    });

    test('caso borde: no numérico -> false', () {
      expect(ParserNumeroAr.esInterpretacionDeMiles('abc'), false);
    });
  });

  group('ParserNumeroAr.lecturaAlternativaSiEsMiles', () {
    test('"1.500" -> 1.5 (la lectura que se perdió)', () {
      expect(ParserNumeroAr.lecturaAlternativaSiEsMiles('1.500'), 1.5);
    });

    test('"79.318" -> 79.32 (redondeada a 2 decimales, igual que parsear)', () {
      expect(ParserNumeroAr.lecturaAlternativaSiEsMiles('79.318'), 79.32);
    });
  });
}
