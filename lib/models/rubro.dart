import 'subitem.dart';

class Rubro {
  final String id;
  final String item; // Ejemplo: "1.01", "2.00"
  final String nombre;
  final List<Subitem> subitems;

  // --- NUEVO CAMPO INTEGRADO ---
  final String macrorrubro; // Asignación a uno de los 6 Macrorrubros para el filtro por Chips

  Rubro({
    required this.id,
    required this.item,
    required this.nombre,
    required this.subitems,
    this.macrorrubro = '2. Estructura y Albañilería',
  });

  // Calcula automáticamente el costo total del rubro sumando todos sus subítems activos/aplicables
  double get totalRubro {
    return subitems.fold(0.0, (suma, subitem) => suma + subitem.total);
  }

  // --- SOLUCIÓN AL ERROR ---
  // Agregamos este getter para que la pantalla RubrosTab encuentre 'subtotalRubro'
  // y devuelva tu cálculo de 'totalRubro' sin romper nada.
  double get subtotalRubro => totalRubro;

  // Calcula la incidencia porcentual de este rubro sobre el costo total de la obra
  double calcularIncidencia(double totalObra) {
    if (totalObra <= 0) return 0.0;
    return (totalRubro / totalObra) * 100;
  }

  // Permite clonar o modificar un rubro de forma segura
  Rubro copyWith({
    String? id,
    String? item,
    String? nombre,
    List<Subitem>? subitems,
    String? macrorrubro,
  }) {
    return Rubro(
      id: id ?? this.id,
      item: item ?? this.item,
      nombre: nombre ?? this.nombre,
      subitems: subitems ?? this.subitems,
      macrorrubro: macrorrubro ?? this.macrorrubro,
    );
  }

  // Convierte el rubro y todos sus subítems a mapa para guardar
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'item': item,
      'nombre': nombre,
      'subitems': subitems.map((x) => x.toMap()).toList(),
      'macrorrubro': macrorrubro,
    };
  }

  // Reconstruye el rubro con toda su lista interna desde los datos guardados
  factory Rubro.fromMap(Map<String, dynamic> map) {
    return Rubro(
      id: map['id']?.toString() ?? '',
      item: map['item']?.toString() ?? '',
      nombre: map['nombre']?.toString() ?? '',
      subitems: map['subitems'] != null
          ? List<Subitem>.from(
              (map['subitems'] as List).map((x) => Subitem.fromMap(x)),
            )
          : [],
      macrorrubro: map['macrorrubro']?.toString() ?? '2. Estructura y Albañilería',
    );
  }
}