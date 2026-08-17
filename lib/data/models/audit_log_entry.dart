/// Historial inmutable de transiciones — genérico y reusable, no una tabla de
/// auditoría por feature. Ver docs/etapa3_roles_permisos_diseno_datos.md, sección 4.
/// Sirve para modificaciones_obra hoy, y a futuro para certificados, delegaciones
/// de firma y moderación de contenido (CLAUDE.md, "Blindaje legal").
class AuditLogEntry {
  final String id;
  final String? obraId;
  final String usuarioId;
  final String? ip;
  final String accion;   // ej. 'aprobar_adicional', 'rechazar_adicional', 'devolver_adicional'
  final String entidad;  // ej. 'modificacion_obra', 'certificado', 'delegacion_firma'
  final String? entidadId;
  final Map<String, dynamic>? detalle;
  final DateTime fechaCreacion;

  AuditLogEntry({
    required this.id,
    this.obraId,
    required this.usuarioId,
    this.ip,
    required this.accion,
    required this.entidad,
    this.entidadId,
    this.detalle,
    required this.fechaCreacion,
  });

  AuditLogEntry copyWith({
    String? id,
    String? obraId,
    String? usuarioId,
    String? ip,
    String? accion,
    String? entidad,
    String? entidadId,
    Map<String, dynamic>? detalle,
    DateTime? fechaCreacion,
  }) {
    return AuditLogEntry(
      id: id ?? this.id,
      obraId: obraId ?? this.obraId,
      usuarioId: usuarioId ?? this.usuarioId,
      ip: ip ?? this.ip,
      accion: accion ?? this.accion,
      entidad: entidad ?? this.entidad,
      entidadId: entidadId ?? this.entidadId,
      detalle: detalle ?? this.detalle,
      fechaCreacion: fechaCreacion ?? this.fechaCreacion,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'obraId': obraId,
      'usuarioId': usuarioId,
      'ip': ip,
      'accion': accion,
      'entidad': entidad,
      'entidadId': entidadId,
      'detalle': detalle,
      'fechaCreacion': fechaCreacion.toIso8601String(),
    };
  }

  factory AuditLogEntry.fromMap(Map<String, dynamic> map) {
    return AuditLogEntry(
      id: map['id']?.toString() ?? '',
      obraId: map['obraId']?.toString(),
      usuarioId: map['usuarioId']?.toString() ?? '',
      ip: map['ip']?.toString(),
      accion: map['accion']?.toString() ?? '',
      entidad: map['entidad']?.toString() ?? '',
      entidadId: map['entidadId']?.toString(),
      detalle: map['detalle'] != null && map['detalle'] is Map<String, dynamic>
          ? map['detalle'] as Map<String, dynamic>
          : null,
      fechaCreacion: map['fechaCreacion'] != null
          ? DateTime.tryParse(map['fechaCreacion'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
