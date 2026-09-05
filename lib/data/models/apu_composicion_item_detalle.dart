/// Una línea de la composición de APU de un subítem — mano de obra, material o equipo, con su
/// rendimiento y el precio unitario ya resuelto (ver `calcular_composicion_detalle_subitem`,
/// supabase/migrations/0060_calcular_composicion_detalle_subitem.sql).
///
/// `precioUnitario` es `null` cuando el insumo no tiene precio cargado — nunca `0`, mismo criterio
/// que `ApuPrecioSubitem` (no colapsar "sin precio" a un número real).
class ApuComposicionItemDetalle {
  final String tipoComponente; // 'material' | 'mano_obra' | 'equipo'
  final String insumoNombre;
  final String insumoUnidad;
  final double rendimiento;
  final double? precioUnitario;

  const ApuComposicionItemDetalle({
    required this.tipoComponente,
    required this.insumoNombre,
    required this.insumoUnidad,
    required this.rendimiento,
    required this.precioUnitario,
  });

  double? get subtotal => precioUnitario == null ? null : rendimiento * precioUnitario!;
}
