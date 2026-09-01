/// Interpreta un número tipeado a mano con la convención argentina (coma
/// decimal, punto de separador de miles), asumiendo que ningún campo de la
/// app necesita más de 2 decimales -- ver memoria de diseño
/// "bug_separador_miles_mat_y_mo" para el diagnóstico completo que motivó
/// esta regla.
///
/// Reglas, en orden:
/// - Con coma: la coma es el separador decimal, cualquier punto es de miles
///   y se descarta ("1.200,50" -> 1200.50).
/// - Sin coma y con más de un punto: todos los puntos son de miles, sin
///   ambigüedad posible ("1.234.567" -> 1234567).
/// - Sin coma y con un solo punto: si el grupo de dígitos a la izquierda del
///   punto tiene entre 1 y 3 dígitos Y el grupo de la derecha tiene
///   exactamente 3, es separador de miles ("79.318" -> 79318). Con 4 o más
///   dígitos a la izquierda no puede ser una separación de miles bien
///   formada (los miles se agrupan de a 3) aunque la derecha tenga 3
///   dígitos, así que se interpreta como decimal con redondeo
///   ("8210.567" -> 8210.57). Con 1 o 2 dígitos a la derecha siempre es
///   decimal ("9.66" -> 9.66).
/// - Sin coma ni punto: se interpreta tal cual.
///
/// El resultado final siempre se redondea a 2 decimales. No valida signo ni
/// rango (positivo, `>= 0`, etc.) -- eso queda a cargo de cada campo que lo
/// use, igual que antes de esta función.
class ParserNumeroAr {
  /// Único lugar con la lógica de decisión -- parsear() y
  /// esInterpretacionDeMiles() la consumen desde acá en vez de repetirla.
  static ({String normalizado, bool esMilesAmbiguo}) _interpretar(String t) {
    if (t.contains(',')) {
      return (normalizado: t.replaceAll('.', '').replaceAll(',', '.'), esMilesAmbiguo: false);
    }
    final cantidadPuntos = '.'.allMatches(t).length;
    if (cantidadPuntos >= 2) {
      // Miles sin ambigüedad real (nadie escribe dos puntos pensando en un
      // decimal) -- esMilesAmbiguo queda false a propósito, ver
      // esInterpretacionDeMiles.
      return (normalizado: t.replaceAll('.', ''), esMilesAmbiguo: false);
    }
    if (cantidadPuntos == 1) {
      final partes = t.split('.');
      final digitosIzquierda = partes[0].replaceAll('-', '').length;
      final digitosDerecha = partes[1].length;
      final esMiles = digitosDerecha == 3 && digitosIzquierda <= 3;
      return (
        normalizado: esMiles ? t.replaceAll('.', '') : t,
        esMilesAmbiguo: esMiles,
      );
    }
    return (normalizado: t, esMilesAmbiguo: false);
  }

  static double? _redondear(String normalizado) {
    final valor = double.tryParse(normalizado);
    if (valor == null) return null;
    return (valor * 100).roundToDouble() / 100;
  }

  static double? parsear(String texto) {
    final t = texto.trim();
    if (t.isEmpty) return null;
    return _redondear(_interpretar(t).normalizado);
  }

  /// true solo para el caso genuinamente ambiguo: un único punto, exactamente
  /// 3 dígitos a la derecha, grupo de 1 a 3 a la izquierda -- alguien pudo
  /// haber querido escribir un decimal con el punto "al revés" (p. ej.
  /// "1.500" por "1,50"). El caso de doble punto es miles sin ambigüedad real
  /// y no se marca a propósito: si el aviso apareciera siempre, dejaría de
  /// notarse. Usar para decidir si reforzar visualmente el preview de un
  /// campo -- nunca cambia qué se guarda, solo qué tan visible es el aviso.
  static bool esInterpretacionDeMiles(String texto) {
    final t = texto.trim();
    if (t.isEmpty) return false;
    final interpretacion = _interpretar(t);
    if (double.tryParse(interpretacion.normalizado) == null) return false;
    return interpretacion.esMilesAmbiguo;
  }

  /// Lectura alternativa para el caso ambiguo: el mismo texto leído con el
  /// punto como decimal en vez de miles ("1.500" -> 1.5). Solo tiene sentido
  /// llamarla cuando esInterpretacionDeMiles ya dio true -- en cualquier otro
  /// caso el resultado no representa una lectura real distinta.
  static double? lecturaAlternativaSiEsMiles(String texto) {
    return _redondear(texto.trim());
  }
}
