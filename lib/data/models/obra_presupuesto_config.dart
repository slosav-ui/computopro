/// Configuración de presupuesto de una obra — selector de tipo de
/// presupuesto (Materiales + Mano de Obra / Mano de Obra Sola) y de
/// impuestos, más los coeficientes que la Solapa APU va a necesitar para el
/// recálculo de "APU sin materiales" (pieza siguiente, todavía sin conectar
/// acá).
///
/// 1:1 con `obras` — la fila se crea sola por trigger al crear la obra, ver
/// `supabase/migrations/0020_obra_presupuesto_config.sql`.
///
/// `tipo_suelo`/`zona_sismorresistente` (misma tabla) quedan fuera a
/// propósito: son de otra pieza (cálculo sismorresistente), no del selector
/// de presupuesto — por eso cada `update` del repositorio manda solo la
/// columna que cambia, nunca la fila entera, para no arrastrar/pisar esos
/// dos campos sin querer.
enum TipoPresupuesto { materialesManoObra, manoObraSola }

extension TipoPresupuestoLabel on TipoPresupuesto {
  String get label {
    switch (this) {
      case TipoPresupuesto.materialesManoObra:
        return 'Materiales + Mano de Obra';
      case TipoPresupuesto.manoObraSola:
        return 'Mano de Obra Sola';
    }
  }
}

class ObraPresupuestoConfig {
  final String obraId;
  final TipoPresupuesto tipoPresupuesto;
  final bool aplicaImpuestos;

  // Coeficientes del resumen APU — no editados por este selector todavía,
  // pero incluidos porque la pieza siguiente (recálculo de "APU sin
  // materiales") los necesita y no tiene sentido agregarlos después.
  final double ggPct;
  final double imprevistosPct;
  final double eppPct;
  final double costoFinancieroPct;
  final double beneficioPct;
  final double gestionMaterialesTercerosPct;

  ObraPresupuestoConfig({
    required this.obraId,
    required this.tipoPresupuesto,
    required this.aplicaImpuestos,
    required this.ggPct,
    required this.imprevistosPct,
    required this.eppPct,
    required this.costoFinancieroPct,
    required this.beneficioPct,
    required this.gestionMaterialesTercerosPct,
  });
}
