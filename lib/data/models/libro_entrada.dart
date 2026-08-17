import 'obra_member.dart';

/// Los 3 "libros" opcionales de Gestión de Obra — ver
/// docs/etapa3_roles_permisos_diseno_datos.md, sección 5.
enum TipoLibro { obra, ordenServicio, notaPedido }

/// Una entrada en cualquiera de los 3 libros. `entradaPadreId` modela acuse
/// de recibo / respuesta como entrada hija de la original — no hace falta
/// una tabla de "acuses" aparte.
///
/// Reglas de escritura por libro (definición cerrada, ver doc §5 y §6.7):
/// - `obra`: escriben admin_maestro, profesional, constructor, cliente_principal.
///   invitado_veedor es siempre de solo lectura; invitado_apoderado solo con
///   delegación activa.
/// - `ordenServicio`: solo profesional genera entradas raíz; constructor
///   solo responde con una entrada hija (acuse de recibo).
/// - `notaPedido`: solo constructor genera entradas raíz; profesional y
///   cliente_principal responden con una entrada hija.
class LibroEntrada {
  final String id;
  final String obraId;
  final TipoLibro libro;
  final String autorUsuarioId;
  final RolProyecto autorRol; // con qué rol firmó, relevante si tiene varios roles en la obra
  final String contenido;
  final List<String> adjuntos;
  final String? entradaPadreId;
  final DateTime fechaCreacion;

  LibroEntrada({
    required this.id,
    required this.obraId,
    required this.libro,
    required this.autorUsuarioId,
    required this.autorRol,
    required this.contenido,
    this.adjuntos = const [],
    this.entradaPadreId,
    required this.fechaCreacion,
  });

  LibroEntrada copyWith({
    String? id,
    String? obraId,
    TipoLibro? libro,
    String? autorUsuarioId,
    RolProyecto? autorRol,
    String? contenido,
    List<String>? adjuntos,
    String? entradaPadreId,
    DateTime? fechaCreacion,
  }) {
    return LibroEntrada(
      id: id ?? this.id,
      obraId: obraId ?? this.obraId,
      libro: libro ?? this.libro,
      autorUsuarioId: autorUsuarioId ?? this.autorUsuarioId,
      autorRol: autorRol ?? this.autorRol,
      contenido: contenido ?? this.contenido,
      adjuntos: adjuntos ?? this.adjuntos,
      entradaPadreId: entradaPadreId ?? this.entradaPadreId,
      fechaCreacion: fechaCreacion ?? this.fechaCreacion,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'obraId': obraId,
      'libro': libro.name,
      'autorUsuarioId': autorUsuarioId,
      'autorRol': autorRol.name,
      'contenido': contenido,
      'adjuntos': adjuntos,
      'entradaPadreId': entradaPadreId,
      'fechaCreacion': fechaCreacion.toIso8601String(),
    };
  }

  factory LibroEntrada.fromMap(Map<String, dynamic> map) {
    return LibroEntrada(
      id: map['id']?.toString() ?? '',
      obraId: map['obraId']?.toString() ?? '',
      libro: TipoLibro.values.firstWhere(
        (e) => e.name == map['libro'],
        orElse: () => TipoLibro.obra,
      ),
      autorUsuarioId: map['autorUsuarioId']?.toString() ?? '',
      autorRol: RolProyecto.values.firstWhere(
        (e) => e.name == map['autorRol'],
        // Mismo criterio conservador que ObraMember.fromMap: ante un rol
        // corrupto/desconocido, nunca asumir uno con más acceso del real.
        orElse: () => RolProyecto.invitadoVeedor,
      ),
      contenido: map['contenido']?.toString() ?? '',
      adjuntos: map['adjuntos'] != null ? List<String>.from(map['adjuntos']) : const [],
      entradaPadreId: map['entradaPadreId']?.toString(),
      fechaCreacion: map['fechaCreacion'] != null
          ? DateTime.tryParse(map['fechaCreacion'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
