import 'subitem.dart';

class SubitemBase {
  final String id;
  final String codigo;
  final String descripcion;
  final String unidad;
  final double precioSugerido;

  // --- NUEVOS CAMPOS INTEGRADOS ---
  final String macrorrubro; // Asignación al macrorrubro correspondiente
  final bool esOficial;     // true: Pertenece a biblioteca precargada (Free) | false: Creado por usuario (Pro)

  SubitemBase({
    required this.id,
    required this.codigo,
    required this.descripcion,
    required this.unidad,
    required this.precioSugerido,
    this.macrorrubro = '2. Estructura y Albañilería',
    this.esOficial = true,
  });

  /// Convierte un ítem de la biblioteca base a un Subitem activo para una obra específica
  Subitem aSubitemObra({
    double cantidadInicial = 0.0,
    double? precioPersonalizado,
    bool esAplicable = true,
  }) {
    return Subitem(
      id: id,
      codigo: codigo,
      descripcion: descripcion,
      unidad: unidad,
      cantidad: cantidadInicial,
      precioUnitario: precioPersonalizado ?? precioSugerido,
      macrorrubro: macrorrubro,
      esAplicable: esAplicable,
      esPersonalizado: !esOficial,
    );
  }

  /// Copia modificable de SubitemBase
  SubitemBase copyWith({
    String? id,
    String? codigo,
    String? descripcion,
    String? unidad,
    double? precioSugerido,
    String? macrorrubro,
    bool? esOficial,
  }) {
    return SubitemBase(
      id: id ?? this.id,
      codigo: codigo ?? this.codigo,
      descripcion: descripcion ?? this.descripcion,
      unidad: unidad ?? this.unidad,
      precioSugerido: precioSugerido ?? this.precioSugerido,
      macrorrubro: macrorrubro ?? this.macrorrubro,
      esOficial: esOficial ?? this.esOficial,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'codigo': codigo,
      'descripcion': descripcion,
      'unidad': unidad,
      'precioSugerido': precioSugerido,
      'macrorrubro': macrorrubro,
      'esOficial': esOficial ? 1 : 0,
    };
  }

  factory SubitemBase.fromMap(Map<String, dynamic> map) {
    return SubitemBase(
      id: map['id']?.toString() ?? '',
      codigo: map['codigo']?.toString() ?? '',
      descripcion: map['descripcion']?.toString() ?? '',
      unidad: map['unidad']?.toString() ?? '',
      precioSugerido: (map['precioSugerido'] as num?)?.toDouble() ?? 0.0,
      macrorrubro: map['macrorrubro']?.toString() ?? '2. Estructura y Albañilería',
      esOficial: map['esOficial'] == 1 || map['esOficial'] == true,
    );
  }
}