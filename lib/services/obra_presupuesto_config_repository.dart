import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/obra_presupuesto_config.dart';

/// Acceso a `obra_presupuesto_config` (1:1 con obras, ver
/// `supabase/migrations/0020_obra_presupuesto_config.sql`). La fila se crea
/// sola por trigger al crear la obra, más backfill para las obras
/// anteriores (verificado sin filas huérfanas, 2026-09-01) — este
/// repositorio nunca inserta, solo lee y actualiza.
///
/// Cada método de escritura manda solo la columna que cambia, nunca la fila
/// entera — así un update del selector nunca pisa `tipo_suelo`/
/// `zona_sismorresistente` (misma tabla, otra pieza, sin modelo acá).
/// `updated_at` lo mantiene el trigger de `0035_updated_at_trigger.sql`, no
/// se manda desde acá.
class ObraPresupuestoConfigRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<ObraPresupuestoConfig> getConfig(String obraId) async {
    final row = await _client
        .from('obra_presupuesto_config')
        .select()
        .eq('obra_id', obraId)
        .single();
    return _fromRow(row);
  }

  Future<ObraPresupuestoConfig> actualizarTipoPresupuesto({
    required String obraId,
    required TipoPresupuesto tipo,
  }) async {
    final updated = await _client
        .from('obra_presupuesto_config')
        .update({'tipo_presupuesto': _columnaDesdeTipo(tipo)})
        .eq('obra_id', obraId)
        .select()
        .single();
    return _fromRow(updated);
  }

  Future<ObraPresupuestoConfig> actualizarAplicaImpuestos({
    required String obraId,
    required bool aplicaImpuestos,
  }) async {
    final updated = await _client
        .from('obra_presupuesto_config')
        .update({'aplica_impuestos': aplicaImpuestos})
        .eq('obra_id', obraId)
        .select()
        .single();
    return _fromRow(updated);
  }

  /// Tilde de cargas sociales del cartel de mano de obra (ver
  /// docs/costo_mano_de_obra_decisiones.md §6/§14) — de obra entera, Free y PRO por igual.
  Future<ObraPresupuestoConfig> actualizarAplicaCargasSociales({
    required String obraId,
    required bool aplicaCargasSociales,
  }) async {
    final updated = await _client
        .from('obra_presupuesto_config')
        .update({'aplica_cargas_sociales': aplicaCargasSociales})
        .eq('obra_id', obraId)
        .select()
        .single();
    return _fromRow(updated);
  }

  ObraPresupuestoConfig _fromRow(Map<String, dynamic> row) {
    return ObraPresupuestoConfig(
      obraId: row['obra_id'].toString(),
      tipoPresupuesto: _tipoDesdeColumna(row['tipo_presupuesto']?.toString()),
      aplicaImpuestos: row['aplica_impuestos'] == true,
      ggPct: (row['gg_pct'] as num).toDouble(),
      imprevistosPct: (row['imprevistos_pct'] as num).toDouble(),
      eppPct: (row['epp_pct'] as num).toDouble(),
      costoFinancieroPct: (row['costo_financiero_pct'] as num).toDouble(),
      beneficioPct: (row['beneficio_pct'] as num).toDouble(),
      gestionMaterialesTercerosPct:
          (row['gestion_materiales_terceros_pct'] as num).toDouble(),
      aplicaCargasSociales: row['aplica_cargas_sociales'] == true,
      artPct: (row['art_pct'] as num).toDouble(),
      fondoCesePct: (row['fondo_cese_pct'] as num).toDouble(),
      sussPct: (row['suss_pct'] as num).toDouble(),
      obraSocialPatronalPct: (row['obra_social_patronal_pct'] as num).toDouble(),
      ficsPct: (row['fics_pct'] as num).toDouble(),
      iericPct: (row['ieric_pct'] as num).toDouble(),
      fodecoPct: (row['fodeco_pct'] as num).toDouble(),
      uocraEmpleadorPct: (row['uocra_empleador_pct'] as num).toDouble(),
    );
  }

  String _columnaDesdeTipo(TipoPresupuesto tipo) {
    switch (tipo) {
      case TipoPresupuesto.materialesManoObra:
        return 'materiales_mano_obra';
      case TipoPresupuesto.manoObraSola:
        return 'mano_obra_sola';
    }
  }

  TipoPresupuesto _tipoDesdeColumna(String? valor) {
    switch (valor) {
      case 'mano_obra_sola':
        return TipoPresupuesto.manoObraSola;
      case 'materiales_mano_obra':
      default:
        // Fallback más conservador ante un valor corrupto o desconocido: el
        // default de la tabla y el único valor permitido para Free.
        return TipoPresupuesto.materialesManoObra;
    }
  }
}
