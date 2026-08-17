/// Roles combinables por obra — ver docs/etapa3_roles_permisos_diseno_datos.md, sección 2.
/// `admin_maestro` es un flag administrativo, no un rol económico aparte (definición cerrada, §6.2).
enum RolProyecto {
  adminMaestro,
  profesional,
  constructor,
  clientePrincipal,
  invitadoVeedor,
  invitadoApoderado,
}

/// Permisos y delegaciones específicos de una fila de ObraMember (un rol puntual
/// de una persona en una obra), no de la persona en general.
class PermisosEspeciales {
  final bool puedeAprobarCertificados;
  final bool puedeAprobarAdicionales;
  final double? topeMontoAprobacion;
  final DateTime? delegacionTemporalInicio;
  final DateTime? delegacionTemporalFin;
  final bool puedeInvitarTerceros;

  // Default siempre false: los "socios" invitados no heredan automáticamente
  // la caja blanca de quien los invitó (definición cerrada, §6.3).
  final bool puedeVerApuAjena;

  const PermisosEspeciales({
    this.puedeAprobarCertificados = false,
    this.puedeAprobarAdicionales = false,
    this.topeMontoAprobacion,
    this.delegacionTemporalInicio,
    this.delegacionTemporalFin,
    this.puedeInvitarTerceros = false,
    this.puedeVerApuAjena = false,
  });

  PermisosEspeciales copyWith({
    bool? puedeAprobarCertificados,
    bool? puedeAprobarAdicionales,
    double? topeMontoAprobacion,
    DateTime? delegacionTemporalInicio,
    DateTime? delegacionTemporalFin,
    bool? puedeInvitarTerceros,
    bool? puedeVerApuAjena,
  }) {
    return PermisosEspeciales(
      puedeAprobarCertificados: puedeAprobarCertificados ?? this.puedeAprobarCertificados,
      puedeAprobarAdicionales: puedeAprobarAdicionales ?? this.puedeAprobarAdicionales,
      topeMontoAprobacion: topeMontoAprobacion ?? this.topeMontoAprobacion,
      delegacionTemporalInicio: delegacionTemporalInicio ?? this.delegacionTemporalInicio,
      delegacionTemporalFin: delegacionTemporalFin ?? this.delegacionTemporalFin,
      puedeInvitarTerceros: puedeInvitarTerceros ?? this.puedeInvitarTerceros,
      puedeVerApuAjena: puedeVerApuAjena ?? this.puedeVerApuAjena,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'puedeAprobarCertificados': puedeAprobarCertificados,
      'puedeAprobarAdicionales': puedeAprobarAdicionales,
      'topeMontoAprobacion': topeMontoAprobacion,
      'delegacionTemporalInicio': delegacionTemporalInicio?.toIso8601String(),
      'delegacionTemporalFin': delegacionTemporalFin?.toIso8601String(),
      'puedeInvitarTerceros': puedeInvitarTerceros,
      'puedeVerApuAjena': puedeVerApuAjena,
    };
  }

  factory PermisosEspeciales.fromMap(Map<String, dynamic> map) {
    return PermisosEspeciales(
      puedeAprobarCertificados: map['puedeAprobarCertificados'] == true,
      puedeAprobarAdicionales: map['puedeAprobarAdicionales'] == true,
      topeMontoAprobacion: (map['topeMontoAprobacion'] as num?)?.toDouble(),
      delegacionTemporalInicio: map['delegacionTemporalInicio'] != null
          ? DateTime.tryParse(map['delegacionTemporalInicio'].toString())
          : null,
      delegacionTemporalFin: map['delegacionTemporalFin'] != null
          ? DateTime.tryParse(map['delegacionTemporalFin'].toString())
          : null,
      puedeInvitarTerceros: map['puedeInvitarTerceros'] == true,
      puedeVerApuAjena: map['puedeVerApuAjena'] == true,
    );
  }
}

/// Un rol puntual de un usuario en una obra. Roles combinables = varias filas
/// de ObraMember para el mismo (obraId, usuarioId) con distinto rol.
class ObraMember {
  final String id;
  final String obraId;
  final String usuarioId;
  final RolProyecto rol;
  final String? invitadoPorUsuarioId;
  final bool activo;
  final DateTime fechaAlta;
  final PermisosEspeciales permisosEspeciales;

  ObraMember({
    required this.id,
    required this.obraId,
    required this.usuarioId,
    required this.rol,
    this.invitadoPorUsuarioId,
    this.activo = true,
    required this.fechaAlta,
    this.permisosEspeciales = const PermisosEspeciales(),
  });

  ObraMember copyWith({
    String? id,
    String? obraId,
    String? usuarioId,
    RolProyecto? rol,
    String? invitadoPorUsuarioId,
    bool? activo,
    DateTime? fechaAlta,
    PermisosEspeciales? permisosEspeciales,
  }) {
    return ObraMember(
      id: id ?? this.id,
      obraId: obraId ?? this.obraId,
      usuarioId: usuarioId ?? this.usuarioId,
      rol: rol ?? this.rol,
      invitadoPorUsuarioId: invitadoPorUsuarioId ?? this.invitadoPorUsuarioId,
      activo: activo ?? this.activo,
      fechaAlta: fechaAlta ?? this.fechaAlta,
      permisosEspeciales: permisosEspeciales ?? this.permisosEspeciales,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'obraId': obraId,
      'usuarioId': usuarioId,
      'rol': rol.name,
      'invitadoPorUsuarioId': invitadoPorUsuarioId,
      'activo': activo,
      'fechaAlta': fechaAlta.toIso8601String(),
      'permisosEspeciales': permisosEspeciales.toMap(),
    };
  }

  factory ObraMember.fromMap(Map<String, dynamic> map) {
    return ObraMember(
      id: map['id']?.toString() ?? '',
      obraId: map['obraId']?.toString() ?? '',
      usuarioId: map['usuarioId']?.toString() ?? '',
      rol: RolProyecto.values.firstWhere(
        (e) => e.name == map['rol'],
        // Fallback más restrictivo posible ante un valor corrupto o desconocido:
        // nunca asumir un rol con más acceso del que corresponde.
        orElse: () => RolProyecto.invitadoVeedor,
      ),
      invitadoPorUsuarioId: map['invitadoPorUsuarioId']?.toString(),
      activo: map['activo'] == null ? true : map['activo'] == true,
      fechaAlta: map['fechaAlta'] != null
          ? DateTime.tryParse(map['fechaAlta'].toString()) ?? DateTime.now()
          : DateTime.now(),
      permisosEspeciales: map['permisosEspeciales'] != null && map['permisosEspeciales'] is Map<String, dynamic>
          ? PermisosEspeciales.fromMap(map['permisosEspeciales'])
          : const PermisosEspeciales(),
    );
  }
}
