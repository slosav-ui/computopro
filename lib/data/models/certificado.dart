/// Certificado de Obra (Modelo A, Avance Medido) — ciclo de vida de 5 estados.
/// Ver supabase/migrations/0009_certificados.sql y
/// docs/certificados_ciclo_vida_diseno_datos.md para el diseño completo.
enum EstadoCertificado { borrador, emitido, leido, pagado, impactadoCerrado }

extension EstadoCertificadoLabel on EstadoCertificado {
  String get label {
    switch (this) {
      case EstadoCertificado.borrador:
        return 'Borrador';
      case EstadoCertificado.emitido:
        return 'Emitido';
      case EstadoCertificado.leido:
        return 'Leído por Propietario';
      case EstadoCertificado.pagado:
        return 'Pagado';
      case EstadoCertificado.impactadoCerrado:
        return 'Impactado y Cerrado';
    }
  }
}

class Certificado {
  final String id;
  final String obraId;
  final int numero;
  final String periodo;
  final double monto;
  final EstadoCertificado estado;

  final String creadoPor;
  final DateTime fechaCreacion;

  // Emitido
  final DateTime? fechaEmision;
  final String? emitidoPor;
  final int? diasPlazoPago;
  final bool? requiereFirmaFisica;

  // Leído por Propietario
  final DateTime? fechaLectura;
  final String? leidoPor;

  // Pagado
  final DateTime? fechaPago;
  final String? pagadoPor;
  final String? medioPago;
  final List<String> comprobantePagoAdjuntos;

  // Anticipo / Fondo de Reparo — snapshot al emitir
  final double? anticipoPctAplicado;
  final double? fondoReparoPctAplicado;
  final double? montoAnticipoDescontado;
  final double? montoFondoReparoRetenido;
  final double? montoNetoAPagar;

  // Impactado y Cerrado
  final DateTime? fechaImpacto;
  final String? impactadoPor;
  final List<String> facturaFinalAdjuntos;

  // Firma física — independiente del estado del ciclo
  final bool pdfFirmadoSubido;
  final DateTime? pdfFirmadoFecha;
  final List<String> pdfFirmadoAdjuntos;

  Certificado({
    required this.id,
    required this.obraId,
    required this.numero,
    required this.periodo,
    required this.monto,
    required this.estado,
    required this.creadoPor,
    required this.fechaCreacion,
    this.fechaEmision,
    this.emitidoPor,
    this.diasPlazoPago,
    this.requiereFirmaFisica,
    this.fechaLectura,
    this.leidoPor,
    this.fechaPago,
    this.pagadoPor,
    this.medioPago,
    this.comprobantePagoAdjuntos = const [],
    this.anticipoPctAplicado,
    this.fondoReparoPctAplicado,
    this.montoAnticipoDescontado,
    this.montoFondoReparoRetenido,
    this.montoNetoAPagar,
    this.fechaImpacto,
    this.impactadoPor,
    this.facturaFinalAdjuntos = const [],
    this.pdfFirmadoSubido = false,
    this.pdfFirmadoFecha,
    this.pdfFirmadoAdjuntos = const [],
  });
}
