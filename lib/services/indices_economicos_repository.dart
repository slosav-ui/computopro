import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/indicadores_economicos.dart';

/// Acceso a `indices_cac` y `cotizacion_dolar_bna` -- ver
/// `supabase/migrations/0102_indices_cac_cotizacion_dolar.sql`. Las dos tablas son catálogo
/// global (igual para todos los usuarios, cargado a mano vía migración, nunca por la app), mismo
/// criterio que `insumos` -- este repositorio es de solo lectura a propósito, no hay pantalla de
/// carga.
class IndicesEconomicosRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<CotizacionDolarBna?> getCotizacionDolar() async {
    final row = await _client.from('cotizacion_dolar_bna').select().maybeSingle();
    return row == null ? null : CotizacionDolarBna.fromRow(row);
  }

  /// Ordenados por mes ascendente -- quien llama usa los últimos dos para calcular la variación
  /// mensual mostrada junto al interruptor de CAC (mismo cálculo que publica CAMARCO, no
  /// guardado aparte).
  Future<List<IndiceCac>> getIndicesCac() async {
    final data = await _client.from('indices_cac').select().order('mes');
    return (data as List).map((row) => IndiceCac.fromRow(row as Map<String, dynamic>)).toList();
  }
}
