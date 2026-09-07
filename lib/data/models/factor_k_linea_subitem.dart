/// Una línea del desglose de Factor K de una partida puntual — ver `calcular_factor_k_subitem`,
/// `supabase/migrations/0077_calcular_factor_k_subitem.sql` (redondeo en `0078`). Sirve tanto para
/// los conceptos (Gastos Generales, Imprevistos, EPP, Costo Financiero, Beneficio, Gestión de
/// materiales de terceros) como para las 4 líneas de impuesto (IVA, Ingresos Brutos, Tasas
/// Municipales, Otro) — la función de base ya las devuelve con la misma forma, no hace falta un
/// modelo aparte para impuestos.
class FactorKLineaSubitem {
  final int orden;
  final String concepto;
  final double pct;
  final String baseTexto;
  final double baseMonto;
  final double monto;

  const FactorKLineaSubitem({
    required this.orden,
    required this.concepto,
    required this.pct,
    required this.baseTexto,
    required this.baseMonto,
    required this.monto,
  });
}

/// Resultado completo de `calcular_factor_k_subitem` para una partida — las dos vistas juntas
/// (con y sin materiales). La función de base siempre calcula las dos: la vista sin materiales
/// necesita los montos absolutos de Gastos Generales/EPP/Costo Financiero de la vista con
/// materiales para copiarlos (no los recalcula), así que separarlas en dos llamadas no evitaría el
/// cálculo doble, solo agregaría un viaje de red.
///
/// `costoCosto*/costoTotalTrabajo*/precioFinal*` van separados por vista a propósito -- no son el
/// mismo número. `insumosConPrecio`/`insumosTotal`/`completo` sí son los mismos para las dos vistas
/// (dependen de la composición de la partida, no de qué cascada se mire).
class PrecioFinalSubitem {
  final List<FactorKLineaSubitem> lineasConMateriales;
  final double costoCostoConMateriales;
  final double costoTotalTrabajoConMateriales;
  final double precioFinalConMateriales;
  final bool cierraOkConMateriales;

  final List<FactorKLineaSubitem> lineasSinMateriales;
  final double costoCostoSinMateriales;
  final double costoTotalTrabajoSinMateriales;
  final double precioFinalSinMateriales;
  final bool cierraOkSinMateriales;

  final int insumosConPrecio;
  final int insumosTotal;

  const PrecioFinalSubitem({
    required this.lineasConMateriales,
    required this.costoCostoConMateriales,
    required this.costoTotalTrabajoConMateriales,
    required this.precioFinalConMateriales,
    required this.cierraOkConMateriales,
    required this.lineasSinMateriales,
    required this.costoCostoSinMateriales,
    required this.costoTotalTrabajoSinMateriales,
    required this.precioFinalSinMateriales,
    required this.cierraOkSinMateriales,
    required this.insumosConPrecio,
    required this.insumosTotal,
  });

  /// `false` = falta precio en al menos una línea de la composición -- ni Costo-Costo ni nada de
  /// lo que sigue es un número real todavía. Mismo criterio que `ApuPrecioSubitem.completo`.
  bool get completo => insumosTotal > 0 && insumosConPrecio == insumosTotal;
}
