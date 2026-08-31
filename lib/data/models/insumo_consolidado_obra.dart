/// Resultado de `consolidado_insumos_obra` (ver
/// supabase/migrations/0031_consolidado_insumos_obra.sql) — un insumo real consumido por una obra,
/// agregado desde las composiciones de APU de sus subítems tildados.
///
/// Deliberadamente NO colapsa "sin precio" a 0: `precioPromedio`/`valorReferencial` son nulos
/// cuando `tienePrecio` es `false`, mismo criterio que `ApuPrecioSubitem`. Con casi ningún insumo
/// con precio real cargado hoy, "sin precio" es el caso normal, no la excepción.
class InsumoConsolidadoObra {
  final String insumoId;
  final String nombre;
  final String unidad;
  final String tipo;
  final double cantidadTotal;
  final double? precioPromedio;
  final bool tienePrecio;

  const InsumoConsolidadoObra({
    required this.insumoId,
    required this.nombre,
    required this.unidad,
    required this.tipo,
    required this.cantidadTotal,
    required this.precioPromedio,
    required this.tienePrecio,
  });

  double? get valorReferencial => tienePrecio ? cantidadTotal * precioPromedio! : null;

  factory InsumoConsolidadoObra.fromMap(Map<String, dynamic> map) {
    return InsumoConsolidadoObra(
      insumoId: map['insumo_id'].toString(),
      nombre: map['nombre'] as String,
      unidad: map['unidad'] as String,
      tipo: map['tipo'] as String,
      cantidadTotal: (map['cantidad_total'] as num).toDouble(),
      precioPromedio: (map['precio_promedio'] as num?)?.toDouble(),
      tienePrecio: map['tiene_precio'] as bool,
    );
  }
}
