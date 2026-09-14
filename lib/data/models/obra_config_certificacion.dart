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

/// Cómo se carga el avance en esta obra (`0132`). **No es por certificado a propósito**: con el modo
/// suelto, alguien carga global los rubros que van bien y detallado los que van mal, y el avance de
/// la obra deja de significar algo (decisión de Seba, 2026-09-14). Se elige al configurar la obra y
/// la base lo congela con el primer certificado emitido.
enum ModoCargaAvance {
  /// Una partida por vez, lo de siempre.
  porPartida,

  /// Un porcentaje **acumulado** por rubro (o de toda la obra) que siembra las filas por partida,
  /// repartido por monto. El reparto sembrado se puede corregir a mano antes de proponer.
  global,
}

extension ModoCargaAvanceColumna on ModoCargaAvance {
  String get columna => switch (this) {
        ModoCargaAvance.porPartida => 'por_partida',
        ModoCargaAvance.global => 'global',
      };

  String get label => switch (this) {
        ModoCargaAvance.porPartida => 'Partida por partida',
        ModoCargaAvance.global => 'Porcentaje global por rubro',
      };
}

/// Ante un valor que esta versión de la app no conoce, `por_partida`: es el modo que no inventa
/// nada: muestra las partidas como están y no siembra ningún reparto.
ModoCargaAvance modoCargaAvanceDesdeColumna(String? valor) =>
    valor == 'global' ? ModoCargaAvance.global : ModoCargaAvance.porPartida;

class ObraConfigCertificacion {
  final String obraId;
  final ModeloCertificacion modeloCertificacion;
  final int? diasPlazoPagoCertificados;
  final double? anticipoPct;
  final double? fondoReparoPct;
  final double? montoTotalContratado;

  /// `null` = sin pactar (y sin aviso). Ver `PeriodicidadCertificacion`.
  final PeriodicidadCertificacion? periodicidadCertificacion;

  /// Ver `ModoCargaAvance`. Nunca null: la columna es `not null default 'por_partida'`.
  final ModoCargaAvance modoCargaAvance;

  /// Si esta obra usa los libros (`0135`). Apagarlos saca la puerta y los avisos, **no lo ya
  /// escrito**: las entradas siguen existiendo y siguen siendo legibles. Un respaldo legal no
  /// se hace desaparecer con un switch de configuración.
  final bool librosHabilitados;

  const ObraConfigCertificacion({
    required this.obraId,
    required this.modeloCertificacion,
    this.diasPlazoPagoCertificados,
    this.anticipoPct,
    this.fondoReparoPct,
    this.montoTotalContratado,
    this.periodicidadCertificacion,
    this.modoCargaAvance = ModoCargaAvance.porPartida,
    this.librosHabilitados = true,
  });
}
