class Insumo {
  final String id;
  final String nombre;
  final String unidad;
  final double precio;
  final String tipo; // 'material', 'mano_obra', 'equipo'

  // --- NUEVOS CAMPOS INTEGRADOS ---
  final String? proveedor; // Nombre del corralón, distribuidor o categoría UOCRA
  final DateTime? fechaActualizacion; // Registro de actualización de lista de precios mensual
  final double porcentajeCargasSociales; // Aplica principalmente a mano de obra (UOCRA)

  Insumo({
    required this.id,
    required this.nombre,
    required this.unidad,
    required this.precio,
    required this.tipo,
    this.proveedor,
    this.fechaActualizacion,
    this.porcentajeCargasSociales = 0.0,
  });

  /// Precio con cargas sociales aplicadas (para Mano de Obra UOCRA)
  double get precioConCargas {
    if (tipo == 'mano_obra' && porcentajeCargasSociales > 0) {
      return precio * (1 + (porcentajeCargasSociales / 100));
    }
    return precio;
  }

  /// Permite clonar o modificar un insumo de forma segura
  Insumo copyWith({
    String? id,
    String? nombre,
    String? unidad,
    double? precio,
    String? tipo,
    String? proveedor,
    DateTime? fechaActualizacion,
    double? porcentajeCargasSociales,
  }) {
    return Insumo(
      id: id ?? this.id,
      nombre: nombre ?? this.nombre,
      unidad: unidad ?? this.unidad,
      precio: precio ?? this.precio,
      tipo: tipo ?? this.tipo,
      proveedor: proveedor ?? this.proveedor,
      fechaActualizacion: fechaActualizacion ?? this.fechaActualizacion,
      porcentajeCargasSociales: porcentajeCargasSociales ?? this.porcentajeCargasSociales,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nombre': nombre,
      'unidad': unidad,
      'precio': precio,
      'tipo': tipo,
      'proveedor': proveedor,
      'fechaActualizacion': fechaActualizacion?.toIso8601String(),
      'porcentajeCargasSociales': porcentajeCargasSociales,
    };
  }

  factory Insumo.fromMap(Map<String, dynamic> map) {
    return Insumo(
      id: map['id']?.toString() ?? '',
      nombre: map['nombre']?.toString() ?? '',
      unidad: map['unidad']?.toString() ?? '',
      precio: (map['precio'] as num?)?.toDouble() ?? 0.0,
      tipo: map['tipo']?.toString() ?? 'material',
      proveedor: map['proveedor']?.toString(),
      fechaActualizacion: map['fechaActualizacion'] != null
          ? DateTime.tryParse(map['fechaActualizacion'].toString())
          : null,
      porcentajeCargasSociales: (map['porcentajeCargasSociales'] as num?)?.toDouble() ?? 0.0,
    );
  }
}