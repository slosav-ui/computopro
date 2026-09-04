/// Configuración de certificación de una obra — Modelo A/B, plazo de pago, anticipo, fondo de
/// reparo y monto total contratado (Modelo B). Ver docs/modelos_certificacion_diseno_datos.md y
/// docs/certificados_ciclo_vida_diseno_datos.md para el diseño completo.
///
/// Vive en columnas de `obras`, no en una tabla propia — este modelo agrupa solo las que le
/// importan a la solapa de Gestión de Obra, mismo criterio que `ObraPresupuestoConfig` agrupa las
/// suyas de otra tabla. `ObrasRepository` no las toca a propósito: es Map-based, pensado para lo
/// que ya consume `ObrasListScreen`, no para esta pieza de negocio.
enum ModeloCertificacion { avanceMedido, hitosPrecioCerrado }

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

  const ObraConfigCertificacion({
    required this.obraId,
    required this.modeloCertificacion,
    this.diasPlazoPagoCertificados,
    this.anticipoPct,
    this.fondoReparoPct,
    this.montoTotalContratado,
  });
}
