/// Una línea de la composición de APU de un subítem — mano de obra, material o equipo, con su
/// rendimiento y el precio unitario ya resuelto (ver `calcular_composicion_detalle_subitem`,
/// supabase/migrations/0060_calcular_composicion_detalle_subitem.sql, ampliada en
/// `0071_personalizacion_apu_pro.sql` con los 4 campos de acá abajo para poder editar).
///
/// `precioUnitario` es `null` cuando el insumo no tiene precio cargado — nunca `0`, mismo criterio
/// que `ApuPrecioSubitem` (no colapsar "sin precio" a un número real).
///
/// `itemId` es `null` para una fila virtual de mano de obra (0072_edicion_apu_correcciones.sql) —
/// una de las 5 categorías que la receta que se está mostrando todavía no tiene como línea real.
/// Editar esa fila ya no depende de `itemId` (ver `insumoId`, que sí está siempre): la ubicación
/// del lado del servidor pasó a ser por insumo, no por id de fila.
class ApuComposicionItemDetalle {
  final String? itemId;
  final String apuComposicionId;
  final bool esPersonal;
  final String tipoComponente; // 'material' | 'mano_obra' | 'equipo'
  final String insumoId;
  final String insumoNombre;
  final String insumoUnidad;
  final double rendimiento;
  final double? precioUnitario;

  const ApuComposicionItemDetalle({
    required this.itemId,
    required this.apuComposicionId,
    required this.esPersonal,
    required this.tipoComponente,
    required this.insumoId,
    required this.insumoNombre,
    required this.insumoUnidad,
    required this.rendimiento,
    required this.precioUnitario,
  });

  double? get subtotal => precioUnitario == null ? null : rendimiento * precioUnitario!;
}
