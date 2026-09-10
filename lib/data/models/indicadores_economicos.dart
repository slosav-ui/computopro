/// Un mes de la serie CAMARCO/CAC -- ver `supabase/migrations/0102_indices_cac_cotizacion_dolar.sql`.
/// `mes` es siempre el primer día del mes que describe el índice, no el día de publicación.
class IndiceCac {
  final DateTime mes;
  final double general;
  final double materiales;
  final double manoObra;

  const IndiceCac({
    required this.mes,
    required this.general,
    required this.materiales,
    required this.manoObra,
  });

  factory IndiceCac.fromRow(Map<String, dynamic> row) {
    return IndiceCac(
      mes: DateTime.parse(row['mes'].toString()),
      general: (row['general'] as num).toDouble(),
      materiales: (row['materiales'] as num).toDouble(),
      manoObra: (row['mano_obra'] as num).toDouble(),
    );
  }
}

/// Cotización de referencia del Banco Nación -- fila única, se pisa con UPDATE cada vez que se
/// actualiza (sin serie histórica, a diferencia del CAC: es un valor de referencia puntual, no
/// una redeterminación por cociente entre dos fechas).
class CotizacionDolarBna {
  final double compra;
  final double venta;
  final DateTime actualizadoEn;

  const CotizacionDolarBna({required this.compra, required this.venta, required this.actualizadoEn});

  double get promedio => (compra + venta) / 2;

  factory CotizacionDolarBna.fromRow(Map<String, dynamic> row) {
    return CotizacionDolarBna(
      compra: (row['compra'] as num).toDouble(),
      venta: (row['venta'] as num).toDouble(),
      actualizadoEn: DateTime.parse(row['actualizado_en'].toString()),
    );
  }
}
