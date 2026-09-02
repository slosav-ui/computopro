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
  final String? categoriaUocra;
  final double cantidadTotal;
  final double? precio;
  final bool tienePrecio;
  final String origen;

  const InsumoConsolidadoObra({
    required this.insumoId,
    required this.nombre,
    required this.unidad,
    required this.tipo,
    required this.categoriaUocra,
    required this.cantidadTotal,
    required this.precio,
    required this.tienePrecio,
    required this.origen,
  });

  double? get costoTotal => tienePrecio ? cantidadTotal * precio! : null;

  /// Colapsa los 5 valores posibles de `origen` a los 2 estados visuales de la grilla — el usuario
  /// no necesita saber de qué tabla sale el número, solo si se actualiza solo o quedó fijado por
  /// alguien. Lista blanca a propósito (ver docs/costo_mano_de_obra_decisiones.md §12 para el
  /// mapeo exhaustivo de los 5 valores): un `origen` nuevo que no se sume acá cae del lado
  /// "automático" por default, así que agregar uno sin revisar esta lista puede dejar un precio
  /// puesto por el usuario sin su marca.
  bool get fijadoAMano => origen == 'manual' || origen == 'presupuesto_firme' || origen == 'override';

  factory InsumoConsolidadoObra.fromMap(Map<String, dynamic> map) {
    return InsumoConsolidadoObra(
      insumoId: map['insumo_id'].toString(),
      nombre: map['nombre'] as String,
      unidad: map['unidad'] as String,
      tipo: map['tipo'] as String,
      categoriaUocra: map['categoria_uocra'] as String?,
      cantidadTotal: (map['cantidad_total'] as num).toDouble(),
      precio: (map['precio'] as num?)?.toDouble(),
      tienePrecio: map['tiene_precio'] as bool,
      origen: map['origen'] as String,
    );
  }
}
