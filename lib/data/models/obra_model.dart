enum CapaVisibilidad {
  cajaBlanca, // Admin / Profesional (Vista Completa con APU, K, etc.)
  cajaNegra,  // Cliente / Propietario (Vista Comercial)
  operativa,  // Constructor / Capataz (Cantidades y Avances sin $)
  observador, // Socio / Inversor / Familiar (Lectura Pasiva)
}

/// Permisos específicos de edición/visibilidad granulares
class PermisosModulo {
  final bool verComputo;
  final bool verPreciosFinales;
  final bool verApuYCoeficienteK;
  final bool cargarAvanceFisico;
  final bool editarComputo;
  final bool aprobarCertificados;
  final bool invitarTerceros;

  const PermisosModulo({
    this.verComputo = true,
    this.verPreciosFinales = true,
    this.verApuYCoeficienteK = false,
    this.cargarAvanceFisico = false,
    this.editarComputo = false,
    this.aprobarCertificados = false,
    this.invitarTerceros = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'verComputo': verComputo,
      'verPreciosFinales': verPreciosFinales,
      'verApuYCoeficienteK': verApuYCoeficienteK,
      'cargarAvanceFisico': cargarAvanceFisico,
      'editarComputo': editarComputo,
      'aprobarCertificados': aprobarCertificados,
      'invitarTerceros': invitarTerceros,
    };
  }

  factory PermisosModulo.fromMap(Map<String, dynamic> map) {
    return PermisosModulo(
      verComputo: map['verComputo'] ?? true,
      verPreciosFinales: map['verPreciosFinales'] ?? true,
      verApuYCoeficienteK: map['verApuYCoeficienteK'] ?? false,
      cargarAvanceFisico: map['cargarAvanceFisico'] ?? false,
      editarComputo: map['editarComputo'] ?? false,
      aprobarCertificados: map['aprobarCertificados'] ?? false,
      invitarTerceros: map['invitarTerceros'] ?? false,
    );
  }
}

class ObraModel {
  final int id;
  final String nombre;
  final String empresa;
  final String propietario;
  final String ubicacion;
  final String tipoObra;
  final String perfilCreador; // 'Profesional', 'Empresa Constructora', 'Propietario'
  final double montoTotal;

  // --- NUEVOS CAMPOS INTEGRADOS ---
  // A. Matriz Configurable mediante Checkboxes
  final bool esPropietarioActivo;
  final bool esProfesionalActivo;
  final bool esConstructorActivo;

  // B. Capa de Visibilidad y Permisos
  final CapaVisibilidad capaVisibilidad;
  final PermisosModulo permisos;

  // C. Gestión de Invitados y Notificaciones de Socio/Colaborador
  final String? idAdminCreador; // ID del Administrador originante
  final String? invitadoPorRol;  // 'Socio del Profesional', 'Socio del Cliente', etc.
  final List<String> notificacionesAdmin; // Registra acciones de socios con permiso de edición

  ObraModel({
    required this.id,
    required this.nombre,
    required this.empresa,
    required this.propietario,
    required this.ubicacion,
    required this.tipoObra,
    required this.perfilCreador,
    this.montoTotal = 0.0,
    this.esPropietarioActivo = false,
    this.esProfesionalActivo = true,
    this.esConstructorActivo = false,
    this.capaVisibilidad = CapaVisibilidad.cajaBlanca,
    this.permisos = const PermisosModulo(
      verComputo: true,
      verPreciosFinales: true,
      verApuYCoeficienteK: true,
      cargarAvanceFisico: true,
      editarComputo: true,
      aprobarCertificados: true,
      invitarTerceros: true,
    ),
    this.idAdminCreador,
    this.invitadoPorRol,
    this.notificacionesAdmin = const [],
  });

  /// Crear una copia del objeto modificando solo ciertos atributos
  ObraModel copyWith({
    int? id,
    String? nombre,
    String? empresa,
    String? propietario,
    String? ubicacion,
    String? tipoObra,
    String? perfilCreador,
    double? montoTotal,
    bool? esPropietarioActivo,
    bool? esProfesionalActivo,
    bool? esConstructorActivo,
    CapaVisibilidad? capaVisibilidad,
    PermisosModulo? permisos,
    String? idAdminCreador,
    String? invitadoPorRol,
    List<String>? notificacionesAdmin,
  }) {
    return ObraModel(
      id: id ?? this.id,
      nombre: nombre ?? this.nombre,
      empresa: empresa ?? this.empresa,
      propietario: propietario ?? this.propietario,
      ubicacion: ubicacion ?? this.ubicacion,
      tipoObra: tipoObra ?? this.tipoObra,
      perfilCreador: perfilCreador ?? this.perfilCreador,
      montoTotal: montoTotal ?? this.montoTotal,
      esPropietarioActivo: esPropietarioActivo ?? this.esPropietarioActivo,
      esProfesionalActivo: esProfesionalActivo ?? this.esProfesionalActivo,
      esConstructorActivo: esConstructorActivo ?? this.esConstructorActivo,
      capaVisibilidad: capaVisibilidad ?? this.capaVisibilidad,
      permisos: permisos ?? this.permisos,
      idAdminCreador: idAdminCreador ?? this.idAdminCreador,
      invitadoPorRol: invitadoPorRol ?? this.invitadoPorRol,
      notificacionesAdmin: notificacionesAdmin ?? this.notificacionesAdmin,
    );
  }

  /// Convertir la instancia a un Map (para SQLite, JSON, etc.)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nombre': nombre,
      'empresa': empresa,
      'propietario': propietario,
      'ubicacion': ubicacion,
      'tipoObra': tipoObra,
      'perfilCreador': perfilCreador,
      'montoTotal': montoTotal,
      'esPropietarioActivo': esPropietarioActivo ? 1 : 0,
      'esProfesionalActivo': esProfesionalActivo ? 1 : 0,
      'esConstructorActivo': esConstructorActivo ? 1 : 0,
      'capaVisibilidad': capaVisibilidad.name,
      'permisos': permisos.toMap(),
      'idAdminCreador': idAdminCreador,
      'invitadoPorRol': invitadoPorRol,
      'notificacionesAdmin': notificacionesAdmin,
    };
  }

  /// Crear una instancia de ObraModel desde un Map/JSON
  factory ObraModel.fromMap(Map<String, dynamic> map) {
    return ObraModel(
      id: map['id'] is int ? map['id'] : int.tryParse(map['id']?.toString() ?? '0') ?? 0,
      nombre: map['nombre']?.toString() ?? '',
      empresa: map['empresa']?.toString() ?? '',
      propietario: map['propietario']?.toString() ?? map['comitente']?.toString() ?? '',
      ubicacion: map['ubicacion']?.toString() ?? '',
      tipoObra: map['tipoObra']?.toString() ?? '',
      perfilCreador: map['perfilCreador']?.toString() ?? 'Profesional',
      montoTotal: (map['montoTotal'] as num?)?.toDouble() ?? 0.0,
      esPropietarioActivo: map['esPropietarioActivo'] == 1 || map['esPropietarioActivo'] == true,
      esProfesionalActivo: map['esProfesionalActivo'] == 1 || map['esProfesionalActivo'] == true,
      esConstructorActivo: map['esConstructorActivo'] == 1 || map['esConstructorActivo'] == true,
      capaVisibilidad: CapaVisibilidad.values.firstWhere(
        (e) => e.name == map['capaVisibilidad'],
        orElse: () => CapaVisibilidad.cajaBlanca,
      ),
      permisos: map['permisos'] != null && map['permisos'] is Map<String, dynamic>
          ? PermisosModulo.fromMap(map['permisos'])
          : const PermisosModulo(),
      idAdminCreador: map['idAdminCreador']?.toString(),
      invitadoPorRol: map['invitadoPorRol']?.toString(),
      notificacionesAdmin: map['notificacionesAdmin'] != null
          ? List<String>.from(map['notificacionesAdmin'])
          : const [],
    );
  }

  @override
  String toString() {
    return 'ObraModel(id: $id, nombre: $nombre, empresa: $empresa, propietario: $propietario, ubicacion: $ubicacion, tipoObra: $tipoObra, perfilCreador: $perfilCreador, montoTotal: $montoTotal, esPropietarioActivo: $esPropietarioActivo, esProfesionalActivo: $esProfesionalActivo, esConstructorActivo: $esConstructorActivo, capaVisibilidad: $capaVisibilidad)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is ObraModel &&
        other.id == id &&
        other.nombre == nombre &&
        other.empresa == empresa &&
        other.propietario == propietario &&
        other.ubicacion == ubicacion &&
        other.tipoObra == tipoObra &&
        other.perfilCreador == perfilCreador &&
        other.montoTotal == montoTotal &&
        other.esPropietarioActivo == esPropietarioActivo &&
        other.esProfesionalActivo == esProfesionalActivo &&
        other.esConstructorActivo == esConstructorActivo &&
        other.capaVisibilidad == capaVisibilidad &&
        other.idAdminCreador == idAdminCreador &&
        other.invitadoPorRol == invitadoPorRol;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        nombre.hashCode ^
        empresa.hashCode ^
        propietario.hashCode ^
        ubicacion.hashCode ^
        tipoObra.hashCode ^
        perfilCreador.hashCode ^
        montoTotal.hashCode ^
        esPropietarioActivo.hashCode ^
        esProfesionalActivo.hashCode ^
        esConstructorActivo.hashCode ^
        capaVisibilidad.hashCode ^
        idAdminCreador.hashCode ^
        invitadoPorRol.hashCode;
  }
}