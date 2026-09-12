/// Certificado de Obra (Modelo A, Avance Medido) — ciclo de vida de 5 estados + `anulado`.
/// Ver supabase/migrations/0009_certificados.sql, 0056_certificados_anulacion.sql y
/// docs/certificados_ciclo_vida_diseno_datos.md (§12 para la anulación) para el diseño completo.
enum EstadoCertificado { borrador, emitido, leido, pagado, impactadoCerrado, anulado }

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
      case EstadoCertificado.anulado:
        return 'Anulado';
    }
  }
}

class Certificado {
  final String id;
  final String obraId;
  final int numero;
  final int version;
  final String periodo;
  final double monto;
  // Desglose pactado/ajuste CAC, snapshoteado al emitir (0105) -- null para certificados emitidos
  // antes de esa migración, no reconstruible retroactivamente (ver docs/cac_conectado_modelo_a_diseno.md
  // §7, ambigüedad B). `monto - montoPactado` es el ajuste, no se guarda aparte -- sin significado
  // de negocio propio más allá de esa resta.
  final double? montoPactado;
  // Cotización promedio BNA (compra/venta) snapshoteada al emitir (0107) -- para obras en USD, la
  // conversión de un certificado YA EMITIDO tiene que usar ESTA, no la cotización de hoy: el monto
  // en pesos ya está congelado, así que el número en dólares que se le mostró al cliente tampoco
  // puede moverse después. `null` = certificado emitido antes de esta migración, o todavía en
  // borrador (nada que congelar todavía) -- quien muestra el monto cae a la cotización de hoy en
  // los dos casos, marcado como aproximación en el primero.
  final double? cotizacionDolarPromedioAlEmitir;
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

  // Anulación — ver supabase/migrations/0056_certificados_anulacion.sql. anulacionEstado es texto
  // plano ('propuesta'/'aprobada'/'rechazada'), no un enum, mismo criterio ya usado acá para
  // medioPago: es un valor que se muestra tal cual, sin lógica propia en Dart más allá de comparar
  // contra el string.
  final String? anulacionEstado;
  final String? anulacionMotivo;
  final String? anulacionPropuestaPor;
  final DateTime? anulacionPropuestaFecha;
  final String? anulacionResueltaPor;
  final DateTime? anulacionResueltaFecha;
  final String? anulacionMotivoRechazo;

  Certificado({
    required this.id,
    required this.obraId,
    required this.numero,
    this.version = 1,
    required this.periodo,
    required this.monto,
    this.montoPactado,
    this.cotizacionDolarPromedioAlEmitir,
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
    this.anulacionEstado,
    this.anulacionMotivo,
    this.anulacionPropuestaPor,
    this.anulacionPropuestaFecha,
    this.anulacionResueltaPor,
    this.anulacionResueltaFecha,
    this.anulacionMotivoRechazo,
  });

  /// "1", "1 bis", "1 ter" -- el número que ve el usuario, en TODAS las pantallas que lo muestran
  /// (antes de este getter, 6 de los 7 lugares que arman este string lo hacían a mano y se
  /// olvidaban del sufijo de versión, mostrando el reemplazo de un certificado anulado idéntico al
  /// original sin ninguna marca -- encontrado por Seba, 2026-09-11). El número en sí (`numero`)
  /// NUNCA cambia al anular (`resolver_anulacion_certificado`, 0056, preserva `numero` y solo
  /// incrementa `version`) -- a propósito, para no dejar un hueco en la numeración.
  ///
  /// "bis"/"ter", no "(v2)"/"(v3)" -- corrección de Seba (2026-09-12): es el vocabulario que un
  /// profesional reconoce en obra para "la corrección del certificado N", no una versión de
  /// software. Sin padding de ceros tampoco (antes "001") -- así es como se nombra en la práctica,
  /// no como un código. Más allá de "ter" (2 correcciones sobre el mismo certificado, un caso ya
  /// raro) cae a "corrección N", en vez de sumar más latinismos que ya nadie reconoce.
  static const _sufijosVersion = ['', 'bis', 'ter'];

  /// Extraído como estático para que `AvanceHistorialItem` (certificado_subitem_avance.dart) --
  /// que no tiene un `Certificado` completo, solo `numero`/`version` sueltos traídos con un join
  /// liviano -- pueda mostrar el mismo formato sin duplicar la lista de sufijos ni la regla de
  /// cuándo cae a "(corrección N)".
  static String formatearNumero(int numero, int version) {
    if (version <= 1) return numero.toString();
    final indice = version - 1;
    if (indice < _sufijosVersion.length) return '$numero ${_sufijosVersion[indice]}';
    return '$numero (corrección $version)';
  }

  String get numeroFormateado => formatearNumero(numero, version);
}
