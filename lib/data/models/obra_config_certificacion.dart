/// Configuración de certificación de una obra — Modelo A/B, plazo de pago, anticipo, fondo de
/// reparo y monto total contratado (Modelo B). Ver docs/modelos_certificacion_diseno_datos.md y
/// docs/certificados_ciclo_vida_diseno_datos.md para el diseño completo.
///
/// Vive en columnas de `obras`, no en una tabla propia — este modelo agrupa solo las que le
/// importan a la solapa de Gestión de Obra, mismo criterio que `ObraPresupuestoConfig` agrupa las
/// suyas de otra tabla. `ObrasRepository` no las toca a propósito: es Map-based, pensado para lo
/// que ya consume `ObrasListScreen`, no para esta pieza de negocio.
enum ModeloCertificacion { avanceMedido, hitosPrecioCerrado }

/// Cada cuánto se certifica, pactado de antemano en la obra (`obras.periodicidad_certificacion`,
/// `0123`). `null` en el modelo = no se pactó ninguna, y entonces no hay aviso de "ya se puede
/// certificar" (ver docs/certificacion_acuerdo_partes_diagnostico.md §3.1).
///
/// NO confundir con `diasPlazoPagoCertificados`, que es cada cuánto se **paga** un certificado ya
/// emitido. Son las dos cosas que más se mezclan de esta configuración.
enum PeriodicidadCertificacion { semanal, quincenal, mensual }

extension PeriodicidadCertificacionColumna on PeriodicidadCertificacion {
  /// Valor tal cual lo guarda la base (el check de la `0123`).
  String get columna => name;

  String get label {
    switch (this) {
      case PeriodicidadCertificacion.semanal:
        return 'Semanal';
      case PeriodicidadCertificacion.quincenal:
        return 'Quincenal';
      case PeriodicidadCertificacion.mensual:
        return 'Mensual';
    }
  }

  /// Para textos corridos ("Certificación mensual"), donde la mayúscula del label queda mal.
  String get labelMinuscula => label.toLowerCase();
}

/// `null` si la columna viene vacía (sin pactar) o con un valor que esta versión de la app no
/// conoce -- se trata como "sin pactar" en vez de romper la pantalla de configuración.
PeriodicidadCertificacion? periodicidadDesdeColumna(String? valor) {
  switch (valor) {
    case 'semanal':
      return PeriodicidadCertificacion.semanal;
    case 'quincenal':
      return PeriodicidadCertificacion.quincenal;
    case 'mensual':
      return PeriodicidadCertificacion.mensual;
    default:
      return null;
  }
}

extension ModeloCertificacionLabel on ModeloCertificacion {
  String get label {
    switch (this) {
      case ModeloCertificacion.avanceMedido:
        return 'Avance Medido';
      case ModeloCertificacion.hitosPrecioCerrado:
        return 'Hitos de Precio Cerrado';
    }
  }
}

class ObraConfigCertificacion {
  final String obraId;
  final ModeloCertificacion modeloCertificacion;
  final int? diasPlazoPagoCertificados;
  final double? anticipoPct;
  final double? fondoReparoPct;
  final double? montoTotalContratado;

  /// `null` = sin pactar (y sin aviso). Ver `PeriodicidadCertificacion`.
  final PeriodicidadCertificacion? periodicidadCertificacion;

  const ObraConfigCertificacion({
    required this.obraId,
    required this.modeloCertificacion,
    this.diasPlazoPagoCertificados,
    this.anticipoPct,
    this.fondoReparoPct,
    this.montoTotalContratado,
    this.periodicidadCertificacion,
  });
}
