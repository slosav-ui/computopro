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

/// El acuerdo entre partes DENTRO del borrador (0124, Tanda 2 de
/// docs/certificacion_acuerdo_partes_diagnostico.md §2.1). Es un eje aparte de
/// `EstadoCertificado` -- calcado del de la anulación: mientras el ida y vuelta pasa, el
/// certificado se queda en `borrador` de punta a punta.
///
/// `enCarga` es a la vez "recién creado" y "devuelto para corregir": los distingue
/// `comentarioDevolucion`, que solo existe en el segundo caso.
enum AcuerdoCertificado { enCarga, propuesto, conforme }

extension AcuerdoCertificadoLabel on AcuerdoCertificado {
  String get label {
    switch (this) {
      case AcuerdoCertificado.enCarga:
        return 'En carga';
      case AcuerdoCertificado.propuesto:
        return 'Propuesto para revisión';
      case AcuerdoCertificado.conforme:
        return 'Conforme';
    }
  }
}

/// La objeción del cliente (0129, Tanda 3 de docs/certificacion_acuerdo_partes_diagnostico.md §5).
/// Otro eje aparte, como el acuerdo y como la anulación: el certificado sigue `emitido`/`leido`
/// mientras se discute. `null` = nunca fue objetado, que es el caso de casi todos.
///
/// `abierta` **frena el pago**; leer sigue permitido (leer no es pagar).
enum ObjecionCertificado { abierta, aclarada, aceptada }

extension ObjecionCertificadoLabel on ObjecionCertificado {
  String get label {
    switch (this) {
      case ObjecionCertificado.abierta:
        return 'Objeción abierta';
      case ObjecionCertificado.aclarada:
        return 'Objeción aclarada';
      case ObjecionCertificado.aceptada:
        return 'Objeción aceptada';
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

  // Acuerdo entre partes dentro del borrador (0124). Se llenan con las funciones
  // proponer_avance_certificado / dar_conformidad_certificado / devolver_avance_certificado, nunca
  // con un update directo. En un certificado emitido antes de esa migración `acuerdoEstado` queda
  // en `enCarga` y no significa nada: la columna solo gobierna el borrador.
  final AcuerdoCertificado acuerdoEstado;
  final String? propuestoPor;
  final DateTime? propuestaFecha;
  final String? conformePor;
  final DateTime? conformeFecha;

  // "Este anulado no necesita reemplazo" (0128): la salida explícita cuando los certificados
  // emitidos después ya cubrieron lo que medía. Cierra el hueco de numeración sin inventar un
  // certificado de monto cero. Los tres van juntos o ninguno (check de la tabla).
  final String? reemplazoNoRequeridoPor;
  final DateTime? reemplazoNoRequeridoFecha;
  final String? reemplazoNoRequeridoMotivo;

  // Objeción del cliente (0129), en tres tramos: el planteo, la respuesta del lado técnico y el
  // cierre. Sin el tramo del medio, una objeción resuelta no dice qué se contestó, que es justo lo
  // que hay que poder releer después.
  final ObjecionCertificado? objecionEstado;
  final String? objecionFundamento;
  final String? objecionPor;
  final DateTime? objecionFecha;
  final String? objecionRespuesta;
  final String? objecionRespondidaPor;
  final DateTime? objecionRespondidaFecha;
  final String? objecionResueltaPor;
  final DateTime? objecionResueltaFecha;

  /// Por qué la contraparte devolvió la última propuesta. Presente solo si hubo una devolución --
  /// es lo que distingue un borrador "devuelto para corregir" de uno recién creado.
  final String? comentarioDevolucion;

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
    this.acuerdoEstado = AcuerdoCertificado.enCarga,
    this.propuestoPor,
    this.propuestaFecha,
    this.conformePor,
    this.conformeFecha,
    this.comentarioDevolucion,
    this.reemplazoNoRequeridoPor,
    this.reemplazoNoRequeridoFecha,
    this.reemplazoNoRequeridoMotivo,
    this.objecionEstado,
    this.objecionFundamento,
    this.objecionPor,
    this.objecionFecha,
    this.objecionRespuesta,
    this.objecionRespondidaPor,
    this.objecionRespondidaFecha,
    this.objecionResueltaPor,
    this.objecionResueltaFecha,
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

  /// Hubo una devolución con comentario y todavía no se volvió a proponer. No alcanza con mirar
  /// `comentarioDevolucion`: al volver a proponer, la función lo limpia, pero mientras el acuerdo
  /// esté `propuesto` el comentario viejo no es lo que hay que mostrar.
  /// Hay una objeción sin resolver: el pago está frenado (0129).
  bool get tieneObjecionAbierta => objecionEstado == ObjecionCertificado.abierta;

  /// El lado técnico ya contestó la objeción abierta y la pelota está del lado del cliente.
  bool get objecionEsperaAlCliente =>
      tieneObjecionAbierta && (objecionRespuesta?.isNotEmpty ?? false);

  /// Se decidió que este anulado no necesita reemplazo (0128). Distinto de "no tiene reemplazo":
  /// acá alguien lo dijo, con motivo y fecha.
  bool get reemplazoNoRequerido => reemplazoNoRequeridoFecha != null;

  bool get fueDevuelto =>
      acuerdoEstado == AcuerdoCertificado.enCarga && (comentarioDevolucion?.isNotEmpty ?? false);
}
