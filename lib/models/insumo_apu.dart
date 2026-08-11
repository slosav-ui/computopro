import 'insumo.dart';

class InsumoApu {
  final Insumo insumo;
  final double rendimiento; // Consumo físico por unidad de medida (ej: 0.15 m³ / m² o HH)

  InsumoApu({
    required this.insumo,
    required this.rendimiento,
  });

  /// Costo parcial monetario desvinculado (se recalcula según el precio base o mano de obra con cargas)
  double get costoParcial => insumo.precioConCargas * rendimiento;

  /// Permite modificar rendimiento o insumo sin romper la receta
  InsumoApu copyWith({
    Insumo? insumo,
    double? rendimiento,
  }) {
    return InsumoApu(
      insumo: insumo ?? this.insumo,
      rendimiento: rendimiento ?? this.rendimiento,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'insumo': insumo.toMap(),
      'rendimiento': rendimiento,
    };
  }

  factory InsumoApu.fromMap(Map<String, dynamic> map) {
    return InsumoApu(
      insumo: Insumo.fromMap(
        map['insumo'] != null ? Map<String, dynamic>.from(map['insumo']) : {},
      ),
      rendimiento: (map['rendimiento'] as num?)?.toDouble() ?? 0.0,
    );
  }
}