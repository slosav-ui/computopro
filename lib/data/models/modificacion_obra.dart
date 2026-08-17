/// Adicionales/Demasías/Quitas — ver docs/etapa3_roles_permisos_diseno_datos.md, sección 4.
enum TipoModificacion { adicional, demasia, quita }

/// `devuelto` no es terminal: se corrige el mismo registro y vuelve a
/// `pendiente` (definición cerrada, §6.5) — no crea un ModificacionObra nuevo.
enum EstadoModificacion { pendiente, devuelto, aprobado, rechazado }

class ModificacionObra {
  final String id;
  final String obraId;
  final TipoModificacion tipo;

  // 'adicional': null hasta que se aprueba — en ese momento se gradúa a un
  // Subitem real del cómputo y este campo pasa a apuntar a ese id (§6.4).
  final String? subitemId;

  final String descripcion;

  // Delta: positivo para adicional/demasía, cantidad a quitar para quita.
  final double cantidad;

  // Demasía: copia el precio ya calculado del Subitem existente, sin pasar
  // por un APU nuevo.
  final double? precioUnitarioHeredado;

  // Lo único que ve el Cliente — sin desglose interno (regla de privacidad
  // genérica del APU, sección 3 del doc de diseño).
  final double montoTotal;

  // Adicional: referencia al APU nuevo, privado por creador (sección 3).
  final String? apuPrivadoId;

  final String solicitadoPorUsuarioId; // quien lo detectó (puede ser el Constructor en terreno)
  final String subidoPorUsuarioId;     // Dirección Técnica, quien lo eleva formalmente

  final EstadoModificacion estado;
  final String? aprobadoPorUsuarioId;  // Cliente, o su Apoderado con delegación activa

  final DateTime fechaSolicitud;
  final DateTime? fechaResolucion;

  // Motivo de rechazo, o qué corregir si el estado es 'devuelto'.
  final String? comentarioResolucion;

  ModificacionObra({
    required this.id,
    required this.obraId,
    required this.tipo,
    this.subitemId,
    required this.descripcion,
    required this.cantidad,
    this.precioUnitarioHeredado,
    required this.montoTotal,
    this.apuPrivadoId,
    required this.solicitadoPorUsuarioId,
    required this.subidoPorUsuarioId,
    this.estado = EstadoModificacion.pendiente,
    this.aprobadoPorUsuarioId,
    required this.fechaSolicitud,
    this.fechaResolucion,
    this.comentarioResolucion,
  });

  ModificacionObra copyWith({
    String? id,
    String? obraId,
    TipoModificacion? tipo,
    String? subitemId,
    String? descripcion,
    double? cantidad,
    double? precioUnitarioHeredado,
    double? montoTotal,
    String? apuPrivadoId,
    String? solicitadoPorUsuarioId,
    String? subidoPorUsuarioId,
    EstadoModificacion? estado,
    String? aprobadoPorUsuarioId,
    DateTime? fechaSolicitud,
    DateTime? fechaResolucion,
    String? comentarioResolucion,
  }) {
    return ModificacionObra(
      id: id ?? this.id,
      obraId: obraId ?? this.obraId,
      tipo: tipo ?? this.tipo,
      subitemId: subitemId ?? this.subitemId,
      descripcion: descripcion ?? this.descripcion,
      cantidad: cantidad ?? this.cantidad,
      precioUnitarioHeredado: precioUnitarioHeredado ?? this.precioUnitarioHeredado,
      montoTotal: montoTotal ?? this.montoTotal,
      apuPrivadoId: apuPrivadoId ?? this.apuPrivadoId,
      solicitadoPorUsuarioId: solicitadoPorUsuarioId ?? this.solicitadoPorUsuarioId,
      subidoPorUsuarioId: subidoPorUsuarioId ?? this.subidoPorUsuarioId,
      estado: estado ?? this.estado,
      aprobadoPorUsuarioId: aprobadoPorUsuarioId ?? this.aprobadoPorUsuarioId,
      fechaSolicitud: fechaSolicitud ?? this.fechaSolicitud,
      fechaResolucion: fechaResolucion ?? this.fechaResolucion,
      comentarioResolucion: comentarioResolucion ?? this.comentarioResolucion,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'obraId': obraId,
      'tipo': tipo.name,
      'subitemId': subitemId,
      'descripcion': descripcion,
      'cantidad': cantidad,
      'precioUnitarioHeredado': precioUnitarioHeredado,
      'montoTotal': montoTotal,
      'apuPrivadoId': apuPrivadoId,
      'solicitadoPorUsuarioId': solicitadoPorUsuarioId,
      'subidoPorUsuarioId': subidoPorUsuarioId,
      'estado': estado.name,
      'aprobadoPorUsuarioId': aprobadoPorUsuarioId,
      'fechaSolicitud': fechaSolicitud.toIso8601String(),
      'fechaResolucion': fechaResolucion?.toIso8601String(),
      'comentarioResolucion': comentarioResolucion,
    };
  }

  factory ModificacionObra.fromMap(Map<String, dynamic> map) {
    return ModificacionObra(
      id: map['id']?.toString() ?? '',
      obraId: map['obraId']?.toString() ?? '',
      tipo: TipoModificacion.values.firstWhere(
        (e) => e.name == map['tipo'],
        orElse: () => TipoModificacion.adicional,
      ),
      subitemId: map['subitemId']?.toString(),
      descripcion: map['descripcion']?.toString() ?? '',
      cantidad: (map['cantidad'] as num?)?.toDouble() ?? 0.0,
      precioUnitarioHeredado: (map['precioUnitarioHeredado'] as num?)?.toDouble(),
      montoTotal: (map['montoTotal'] as num?)?.toDouble() ?? 0.0,
      apuPrivadoId: map['apuPrivadoId']?.toString(),
      solicitadoPorUsuarioId: map['solicitadoPorUsuarioId']?.toString() ?? '',
      subidoPorUsuarioId: map['subidoPorUsuarioId']?.toString() ?? '',
      estado: EstadoModificacion.values.firstWhere(
        (e) => e.name == map['estado'],
        // Fallback más conservador: si el estado es corrupto/desconocido,
        // tratarlo como pendiente de revisión, nunca como ya aprobado.
        orElse: () => EstadoModificacion.pendiente,
      ),
      aprobadoPorUsuarioId: map['aprobadoPorUsuarioId']?.toString(),
      fechaSolicitud: map['fechaSolicitud'] != null
          ? DateTime.tryParse(map['fechaSolicitud'].toString()) ?? DateTime.now()
          : DateTime.now(),
      fechaResolucion: map['fechaResolucion'] != null
          ? DateTime.tryParse(map['fechaResolucion'].toString())
          : null,
      comentarioResolucion: map['comentarioResolucion']?.toString(),
    );
  }
}
