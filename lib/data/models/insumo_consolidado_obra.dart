/// Resultado de `consolidado_insumos_obra` (ver
/// supabase/migrations/0032_consolidado_lee_precio_manual.sql) — un insumo real consumido por una
/// obra, agregado desde las composiciones de APU de sus subítems tildados.
///
/// Deliberadamente NO colapsa "sin precio" a 0: `precio`/`costoTotal` son nulos cuando
/// `tienePrecio` es `false`, mismo criterio que `ApuPrecioSubitem`.
///
/// `precio` puede venir de una carga manual (`origen == 'manual'`, ver `obra_insumo_precios`,
/// 0030) o del promedio automático de corralones (`origen == 'automatico'`) — no siempre es un
/// promedio, por eso el campo ya no se llama `precioPromedio`.
class InsumoConsolidadoObra {
  final String insumoId;
  final String nombre;
  final String unidad;
  final String tipo;
  final double cantidadTotal;
  final double? precio;
  final bool tienePrecio;
  final String origen;

  const InsumoConsolidadoObra({
    required this.insumoId,
    required this.nombre,
    required this.unidad,
    required this.tipo,
    required this.cantidadTotal,
    required this.precio,
    required this.tienePrecio,
    required this.origen,
  });

  double? get costoTotal => tienePrecio ? cantidadTotal * precio! : null;

  factory InsumoConsolidadoObra.fromMap(Map<String, dynamic> map) {
    return InsumoConsolidadoObra(
      insumoId: map['insumo_id'].toString(),
      nombre: map['nombre'] as String,
      unidad: map['unidad'] as String,
      tipo: map['tipo'] as String,
      cantidadTotal: (map['cantidad_total'] as num).toDouble(),
      precio: (map['precio'] as num?)?.toDouble(),
      tienePrecio: map['tiene_precio'] as bool,
      origen: map['origen'] as String,
    );
  }
}
