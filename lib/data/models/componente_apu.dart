import 'insumo_apu.dart';

class ComponenteApu {
  final List<InsumoApu> materiales;
  final List<InsumoApu> manoDeObra;
  final List<InsumoApu> equipos;

  ComponenteApu({
    this.materiales = const [],
    this.manoDeObra = const [],
    this.equipos = const [],
  });

  double get totalMateriales =>
      materiales.fold(0.0, (sum, item) => sum + item.costoParcial);

  double get totalManoDeObra =>
      manoDeObra.fold(0.0, (sum, item) => sum + item.costoParcial);

  double get totalEquipos =>
      equipos.fold(0.0, (sum, item) => sum + item.costoParcial);

  /// Costo Directo Total (CD = Materiales + M.O. + Equipos)
  double get costoDirectoTotal =>
      totalMateriales + totalManoDeObra + totalEquipos;

  /// Calcula el Precio Unitario Final (PU = CD * K) aplicando el Coeficiente de Pase (K)
  double calcularPrecioFinal(double coeficienteK) {
    if (coeficienteK <= 0) return costoDirectoTotal;
    return costoDirectoTotal * coeficienteK;
  }

  /// Permite modificar bloques específicos de la receta APU
  ComponenteApu copyWith({
    List<InsumoApu>? materiales,
    List<InsumoApu>? manoDeObra,
    List<InsumoApu>? equipos,
  }) {
    return ComponenteApu(
      materiales: materiales ?? this.materiales,
      manoDeObra: manoDeObra ?? this.manoDeObra,
      equipos: equipos ?? this.equipos,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'materiales': materiales.map((x) => x.toMap()).toList(),
      'manoDeObra': manoDeObra.map((x) => x.toMap()).toList(),
      'equipos': equipos.map((x) => x.toMap()).toList(),
    };
  }

  factory ComponenteApu.fromMap(Map<String, dynamic> map) {
    return ComponenteApu(
      materiales: map['materiales'] != null
          ? List<InsumoApu>.from(
              (map['materiales'] as List)
                  .map((x) => InsumoApu.fromMap(Map<String, dynamic>.from(x))),
            )
          : [],
      manoDeObra: map['manoDeObra'] != null
          ? List<InsumoApu>.from(
              (map['manoDeObra'] as List)
                  .map((x) => InsumoApu.fromMap(Map<String, dynamic>.from(x))),
            )
          : [],
      equipos: map['equipos'] != null
          ? List<InsumoApu>.from(
              (map['equipos'] as List)
                  .map((x) => InsumoApu.fromMap(Map<String, dynamic>.from(x))),
            )
          : [],
    );
  }
}