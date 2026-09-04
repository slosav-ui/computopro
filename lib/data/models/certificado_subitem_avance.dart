/// Fila de `certificado_subitems_avance` — el % de avance cargado en UN certificado puntual para
/// UN subítem de la obra (no el acumulado, eso se calcula, ver
/// `CertificadoSubitemsAvanceRepository.getAcumuladoSubitem`).
/// Ver supabase/migrations/0052_certificado_subitems_avance.sql.
///
/// Apunta a `obra_subitems`, no al catálogo compartido de subítems — un mismo subítem puede
/// repetirse en distintos sectores de la misma obra, cada uno con su propio avance.
class CertificadoSubitemAvance {
  final String id;
  final String certificadoId;
  final String obraSubitemId;
  final double porcentajePeriodo;
  final double montoPeriodo; // snapshot server-side, ver el trigger de la 0052
  final String creadoPor;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CertificadoSubitemAvance({
    required this.id,
    required this.certificadoId,
    required this.obraSubitemId,
    required this.porcentajePeriodo,
    required this.montoPeriodo,
    required this.creadoPor,
    required this.createdAt,
    required this.updatedAt,
  });
}

/// Una línea del historial de avance de un subítem — su % en UN certificado puntual, con el
/// número y estado de ese certificado para poder mostrarlo ("Certificado N°1: 15%"). No es una
/// fila de `certificado_subitems_avance` directa: junta esa tabla con `certificados` (numero,
/// estado), que `CertificadoSubitemAvance` no trae.
class AvanceHistorialItem {
  final int numeroCertificado;
  final String estadoCertificado;
  final double porcentajePeriodo;
  final double montoPeriodo;

  const AvanceHistorialItem({
    required this.numeroCertificado,
    required this.estadoCertificado,
    required this.porcentajePeriodo,
    required this.montoPeriodo,
  });
}

/// Monto real de un `obra_subitems` en la obra — salida de `calcular_monto_obra_subitems` (0052).
class MontoObraSubitem {
  final String obraSubitemId;
  final double montoTotal;
  final bool tienePrecioCompleto;

  const MontoObraSubitem({
    required this.obraSubitemId,
    required this.montoTotal,
    required this.tienePrecioCompleto,
  });
}

/// Avance ponderado de un rubro — salida de `calcular_avance_ponderado_rubros` (0052).
class AvancePonderadoRubro {
  final String rubroId;
  final double? avancePct; // null si el rubro no tiene ningún subítem con monto (nullif del divisor)
  final double montoPonderado;

  const AvancePonderadoRubro({
    required this.rubroId,
    required this.avancePct,
    required this.montoPonderado,
  });
}

/// "Certificado y pagado a la fecha" de una obra — para el resumen chico de la pantalla de carga
/// de avance. No sale de ninguna función SQL nueva: es una suma simple sobre `certificados`, se
/// calcula en el repositorio.
class ResumenCertificadoObra {
  final double totalCertificado; // suma de monto de certificados que ya dejaron de ser borrador
  final double totalPagado; // suma de monto_neto_a_pagar de los certificados pagados/cerrados

  const ResumenCertificadoObra({
    required this.totalCertificado,
    required this.totalPagado,
  });
}
