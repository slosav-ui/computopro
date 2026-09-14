/// Un alcance cargado como avance global en un certificado (`0132`, tabla
/// `certificado_avance_global`), tal como lo devuelve `certificado_avance_global_resumen`.
///
/// **Los dos porcentajes son distintos a propósito y los dos son ciertos.** `porcentajeCargado` es
/// lo que se declaró al cargar ("estructura va por el 40%"); `porcentajeEfectivo` es el avance
/// ponderado por monto que de verdad quedó en las filas por partida, **incluida la corrección a
/// mano**. Seba pidió expresamente poder corregir el reparto antes de proponer —*"la obra empieza
/// por fundaciones, no por un poco de todo"*— y desde que eso es posible, el certificado no puede
/// decir a secas "global del 40%": ese 40% describe un reparto que quizá ya no tiene adentro.
class CertificadoAvanceGlobal {
  /// `null` = el alcance fue **toda la obra** de una, no un rubro.
  final String? rubroId;

  /// El nombre del rubro, que viene de la base desde la `0133`. `null` cuando el alcance
  /// fue toda la obra. Se pide del lado del servidor y no se resuelve en Dart para que
  /// cada pantalla que muestre esto no tenga que traerse el catálogo de rubros entero.
  final String? rubroNombre;

  final double porcentajeCargado;
  final double porcentajeEfectivo;

  /// Lo calcula la base comparando los dos de arriba. No se recalcula en Dart: la comparación
  /// incluye un redondeo que tiene que ser el mismo del lado del que escribe y del que lee.
  final bool ajustado;

  const CertificadoAvanceGlobal({
    required this.rubroId,
    required this.rubroNombre,
    required this.porcentajeCargado,
    required this.porcentajeEfectivo,
    required this.ajustado,
  });

  bool get esTodaLaObra => rubroId == null;

  /// Cómo se nombra este alcance en pantalla.
  String get etiquetaAlcance => esTodaLaObra ? 'Toda la obra' : (rubroNombre ?? 'Un rubro');

  static CertificadoAvanceGlobal desdeRow(Map<String, dynamic> row) => CertificadoAvanceGlobal(
        rubroId: row['rubro_id']?.toString(),
        rubroNombre: row['rubro_nombre']?.toString(),
        porcentajeCargado: (row['porcentaje_cargado'] as num?)?.toDouble() ?? 0,
        porcentajeEfectivo: (row['porcentaje_efectivo'] as num?)?.toDouble() ?? 0,
        ajustado: row['ajustado'] == true,
      );
}
