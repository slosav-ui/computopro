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

/// El valor de la columna `rol` en la base (`obra_members.rol`, `libro_entradas.autor_rol`).
/// `RolProyecto.name` NO sirve: da `adminMaestro`, y la columna dice `admin_maestro`.
///
/// **No confundir con el par de `invitacion.dart`** (`columnaDesdeRol` / `rolDesdeColumna`), que es
/// el subconjunto INVITABLE: ese excluye `admin_maestro` a propósito —no es un rol que se invite, y
/// su check constraint tampoco lo acepta— y por eso mapea un `admin_maestro` inesperado a veedor.
/// Acá hace falta el mapeo completo: el administrador **sí** escribe en el Libro de Obra.
String rolProyectoAColumna(RolProyecto rol) => switch (rol) {
      RolProyecto.adminMaestro => 'admin_maestro',
      RolProyecto.profesional => 'profesional',
      RolProyecto.constructor => 'constructor',
      RolProyecto.clientePrincipal => 'cliente_principal',
      RolProyecto.invitadoVeedor => 'invitado_veedor',
      RolProyecto.invitadoApoderado => 'invitado_apoderado',
    };

/// La vuelta. **Fallback al rol con menos acceso** ante un valor corrupto o desconocido: nunca
/// asumir uno con más del que corresponde.
///
/// Vive acá y no adentro de un repositorio porque ya la necesitan dos (`ObraMembersRepository` y
/// `LibroRepository`), y una tercera copia de este `switch` es exactamente la clase de duplicación
/// que ya divergió una vez en este proyecto con la delegación.
RolProyecto rolProyectoDesdeColumna(String? valor) {
  switch (valor) {
    case 'admin_maestro':
      return RolProyecto.adminMaestro;
    case 'profesional':
      return RolProyecto.profesional;
    case 'constructor':
      return RolProyecto.constructor;
    case 'cliente_principal':
      return RolProyecto.clientePrincipal;
    case 'invitado_veedor':
      return RolProyecto.invitadoVeedor;
    case 'invitado_apoderado':
      return RolProyecto.invitadoApoderado;
    default:
      return RolProyecto.invitadoVeedor;
  }
}

/// Cómo se nombra el rol en pantalla.
String rolEtiqueta(RolProyecto rol) => switch (rol) {
      RolProyecto.adminMaestro => 'Administrador',
      RolProyecto.profesional => 'Profesional',
      RolProyecto.constructor => 'Constructor',
      RolProyecto.clientePrincipal => 'Cliente',
      RolProyecto.invitadoVeedor => 'Veedor',
      RolProyecto.invitadoApoderado => 'Apoderado',
    };

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

  // 0121 (docs/etapa3_roles_permisos_diseno_datos.md §10): el rol define qué ves, este permiso qué
  // editás del presupuesto y qué actos formales firmás. Solo aplica a profesional/constructor (check
  // en la base); admin_maestro edita siempre sin él. Default false; lo otorga solo admin_maestro.
  final bool puedeEditarPresupuesto;

  const PermisosEspeciales({
    this.puedeAprobarCertificados = false,
    this.puedeAprobarAdicionales = false,
    this.topeMontoAprobacion,
    this.delegacionTemporalInicio,
    this.delegacionTemporalFin,
    this.puedeInvitarTerceros = false,
    this.puedeVerApuAjena = false,
    this.puedeEditarPresupuesto = false,
  });

  PermisosEspeciales copyWith({
    bool? puedeAprobarCertificados,
    bool? puedeAprobarAdicionales,
    double? topeMontoAprobacion,
    DateTime? delegacionTemporalInicio,
    DateTime? delegacionTemporalFin,
    bool? puedeInvitarTerceros,
    bool? puedeVerApuAjena,
    bool? puedeEditarPresupuesto,
  }) {
    return PermisosEspeciales(
      puedeAprobarCertificados: puedeAprobarCertificados ?? this.puedeAprobarCertificados,
      puedeAprobarAdicionales: puedeAprobarAdicionales ?? this.puedeAprobarAdicionales,
      topeMontoAprobacion: topeMontoAprobacion ?? this.topeMontoAprobacion,
      delegacionTemporalInicio: delegacionTemporalInicio ?? this.delegacionTemporalInicio,
      delegacionTemporalFin: delegacionTemporalFin ?? this.delegacionTemporalFin,
      puedeInvitarTerceros: puedeInvitarTerceros ?? this.puedeInvitarTerceros,
      puedeVerApuAjena: puedeVerApuAjena ?? this.puedeVerApuAjena,
      puedeEditarPresupuesto: puedeEditarPresupuesto ?? this.puedeEditarPresupuesto,
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
      'puedeEditarPresupuesto': puedeEditarPresupuesto,
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
      puedeEditarPresupuesto: map['puedeEditarPresupuesto'] == true,
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
