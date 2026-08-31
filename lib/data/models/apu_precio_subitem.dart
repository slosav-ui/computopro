/// Resultado de `calcular_precio_apu_subitems` (ver
/// supabase/migrations/0029_calcular_precio_apu_subitem.sql) — precio derivado de la composición
/// de APU de un subítem.
///
/// Deliberadamente NO es un `double` pelado: `insumosConPrecio`/`insumosTotal` distinguen
/// "completo" de "incompleto" sin ambigüedad. Con solo 1 de 234 insumos con precio real cargado
/// hoy, incompleto es el caso normal — nada que consuma esto puede tratar `precioTotal` como un
/// número confiable sin mirar `completo` primero.
class ApuPrecioSubitem {
  final double precioTotal;
  final int insumosConPrecio;
  final int insumosTotal;

  const ApuPrecioSubitem({
    required this.precioTotal,
    required this.insumosConPrecio,
    required this.insumosTotal,
  });

  bool get completo => insumosTotal > 0 && insumosConPrecio == insumosTotal;
}
