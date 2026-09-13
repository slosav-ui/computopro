import '../../data/models/obra_config_certificacion.dart';

/// Texto sugerido para `certificados.periodo` al crear un borrador, según la periodicidad pactada
/// en la obra (`obras.periodicidad_certificacion`, `0123`) — ver
/// docs/certificacion_acuerdo_partes_diagnostico.md §3.2.
///
/// **Es una sugerencia, no un valor impuesto**: `periodo` es texto libre a propósito (hay obras que
/// van a escribir "Certificado de cierre" o "Quincena de lluvia"), así que esto solo llena el campo
/// y el usuario lo cambia si quiere. Antes de la `0123` ya se sugería algo: el mes y año actuales,
/// hardcodeado en `GestionObraTab._pedirPeriodo`. Esto lo reemplaza haciéndolo consciente de la
/// periodicidad, y conserva ese comportamiento exacto cuando no hay ninguna pactada.
///
/// `cierrePeriodo` viene de la RPC `proximo_periodo_certificacion(obra_id)` — **el ancla no se
/// recalcula acá**: esa función ya sabe las tres reglas (último certificado emitido, si no el
/// congelamiento, y sin congelar no hay nada), y tener dos implementaciones de "cuándo cierra el
/// período" es pedirle a la próxima sesión que las haga divergir.
///
/// Sin `package:intl` (no es una dependencia limpia de este proyecto, ver CLAUDE.md): doce nombres
/// de mes a mano alcanzan, igual que ya hacía el diálogo.
String periodoSugerido({
  required PeriodicidadCertificacion? periodicidad,
  required DateTime? cierrePeriodo,
  DateTime? ahora,
}) {
  final hoy = ahora ?? DateTime.now();
  // Si el cierre todavía no llegó, el usuario está certificando antes de que venza el período: se
  // etiqueta con la fecha de hoy, que es lo que él tiene en la cabeza, no con un período futuro.
  // El caso normal (el aviso salta cuando el período YA venció) usa el cierre real.
  final base = (cierrePeriodo != null && !cierrePeriodo.isAfter(hoy)) ? cierrePeriodo.toLocal() : hoy;

  switch (periodicidad) {
    case null:
      // Sin periodicidad pactada: el comportamiento de siempre, mes y año.
      return _mesYAnio(base);
    case PeriodicidadCertificacion.mensual:
      return _mesYAnio(base);
    case PeriodicidadCertificacion.quincenal:
      final quincena = base.day <= 15 ? '1ª' : '2ª';
      return '$quincena quincena de ${_mesYAnio(base)}';
    case PeriodicidadCertificacion.semanal:
      // Los 7 días que cierran en esa fecha, el último incluido.
      final desde = base.subtract(const Duration(days: 6));
      return 'Semana del ${_diaYMes(desde)} al ${_diaYMes(base)}';
  }
}

const List<String> _meses = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

String _mesYAnio(DateTime f) {
  final mes = _meses[f.month - 1];
  return '${mes[0].toUpperCase()}${mes.substring(1)} ${f.year}';
}

String _diaYMes(DateTime f) =>
    '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}';
