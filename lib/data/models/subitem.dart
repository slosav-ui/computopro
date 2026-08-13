class Subitem {
  final String id;
  final String codigo;
  final String descripcion;
  final String unidad;
  final double cantidad;
  final double precioUnitario;

  // --- NUEVOS CAMPOS INTEGRADOS ---
  final String macrorrubro; // Ej: '1. Preliminares', '2. Estructura y Albañilería', etc.
  final bool esAplicable;   // Checkbox [SI / NO] de activación/incidencia
  final bool esPersonalizado; // Identifica subítems creados por el usuario (Versión Pro)
  final String? ultimoModificador; // Para trazabilidad de cambios por parte de socios/invitados

  Subitem({
    required this.id,
    required this.codigo,
    required this.descripcion,
    required this.unidad,
    required this.cantidad,
    required this.precioUnitario,
    this.macrorrubro = '2. Estructura y Albañilería',
    this.esAplicable = true,
    this.esPersonalizado = false,
    this.ultimoModificador,
  });

  // Cálculo automático del total de este renglón (Respeta si está activo/aplicable)
  double get total => esAplicable ? (cantidad * precioUnitario) : 0.0;

  // --- SOLUCIÓN AL ERROR ---
  // Agregamos este getter para que la pantalla RubrosTab encuentre 'costoTotal'
  // y devuelva el valor de 'total' sin romper nada.
  double get costoTotal => total;

  // Calcula la incidencia porcentual sobre el costo total acumulado de la obra
  double calcularIncidencia(double totalObra) {
    if (totalObra <= 0 || !esAplicable) return 0.0;
    return (total / totalObra) * 100;
  }

  // Permite clonar o editar un subítem cambiando solo los campos necesarios
  Subitem copyWith({
    String? id,
    String? codigo,
    String? descripcion,
    String? unidad,
    double? cantidad,
    double? precioUnitario,
    String? macrorrubro,
    bool? esAplicable,
    bool? esPersonalizado,
    String? ultimoModificador,
  }) {
    return Subitem(
      id: id ?? this.id,
      codigo: codigo ?? this.codigo,
      descripcion: descripcion ?? this.descripcion,
      unidad: unidad ?? this.unidad,
      cantidad: cantidad ?? this.cantidad,
      precioUnitario: precioUnitario ?? this.precioUnitario,
      macrorrubro: macrorrubro ?? this.macrorrubro,
      esAplicable: esAplicable ?? this.esAplicable,
      esPersonalizado: esPersonalizado ?? this.esPersonalizado,
      ultimoModificador: ultimoModificador ?? this.ultimoModificador,
    );
  }

  // Convierte el subítem a un mapa para guardarlo en memoria o base de datos
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'codigo': codigo,
      'descripcion': descripcion,
      'unidad': unidad,
      'cantidad': cantidad,
      'precioUnitario': precioUnitario,
      'macrorrubro': macrorrubro,
      'esAplicable': esAplicable ? 1 : 0,
      'esPersonalizado': esPersonalizado ? 1 : 0,
      'ultimoModificador': ultimoModificador,
    };
  }

  // Reconstruye el subítem desde los datos guardados
  factory Subitem.fromMap(Map<String, dynamic> map) {
    return Subitem(
      id: map['id']?.toString() ?? '',
      codigo: map['codigo']?.toString() ?? '',
      descripcion: map['descripcion']?.toString() ?? '',
      unidad: map['unidad']?.toString() ?? '',
      cantidad: (map['cantidad'] as num?)?.toDouble() ?? 0.0,
      precioUnitario: (map['precioUnitario'] as num?)?.toDouble() ?? 0.0,
      macrorrubro: map['macrorrubro']?.toString() ?? '2. Estructura y Albañilería',
      esAplicable: map['esAplicable'] == 1 || map['esAplicable'] == true,
      esPersonalizado: map['esPersonalizado'] == 1 || map['esPersonalizado'] == true,
      ultimoModificador: map['ultimoModificador']?.toString(),
    );
  }
}