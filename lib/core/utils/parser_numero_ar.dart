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
  static double? parsear(String texto) {
    final t = texto.trim();
    if (t.isEmpty) return null;

    final String normalizado;
    if (t.contains(',')) {
      normalizado = t.replaceAll('.', '').replaceAll(',', '.');
    } else {
      final cantidadPuntos = '.'.allMatches(t).length;
      if (cantidadPuntos >= 2) {
        normalizado = t.replaceAll('.', '');
      } else if (cantidadPuntos == 1) {
        final partes = t.split('.');
        final digitosIzquierda = partes[0].replaceAll('-', '').length;
        final digitosDerecha = partes[1].length;
        final esMiles = digitosDerecha == 3 && digitosIzquierda <= 3;
        normalizado = esMiles ? t.replaceAll('.', '') : t;
      } else {
        normalizado = t;
      }
    }

    final valor = double.tryParse(normalizado);
    if (valor == null) return null;
    return (valor * 100).roundToDouble() / 100;
  }
}
