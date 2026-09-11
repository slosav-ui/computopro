/// Fila de la tabla `audit_log` (Supabase) — historial inmutable de transiciones, genérico y
/// reusable, no una tabla de auditoría por feature (append-only: sin política de UPDATE/DELETE
/// para nadie). Sirve hoy para las observaciones del circuito de Quitas/Demasías
/// (`ModificacionesObraRepository.observar`, docs/adicionales_quitas_demasias_diagnostico.md §6) y
/// para lo que ya escribe `aprobar_quita_demasia` (0109); a futuro, certificados/delegaciones de
/// firma/moderación de contenido.
/// Ver supabase/migrations/0002_modificaciones_obra_audit_log.sql.
class AuditLogEntry {
  final String id;
  final String? obraId;
  final String usuarioId;
  final String? ip;
  final String accion; // ej. 'aprobar_quita_demasia', 'observar_modificacion'
  final String entidad; // ej. 'modificacion_obra', 'certificado'
  final String? entidadId;
  final Map<String, dynamic>? detalle;
  final DateTime fechaCreacion;

  const AuditLogEntry({
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

  factory AuditLogEntry.fromRow(Map<String, dynamic> row) {
    return AuditLogEntry(
      id: row['id'].toString(),
      obraId: row['obra_id']?.toString(),
      usuarioId: row['usuario_id'].toString(),
      ip: row['ip']?.toString(),
      accion: row['accion']?.toString() ?? '',
      entidad: row['entidad']?.toString() ?? '',
      entidadId: row['entidad_id']?.toString(),
      detalle: row['detalle'] != null && row['detalle'] is Map
          ? Map<String, dynamic>.from(row['detalle'] as Map)
          : null,
      fechaCreacion: DateTime.tryParse(row['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}
