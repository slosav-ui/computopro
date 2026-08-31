import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/insumo_consolidado_obra.dart';

/// Acceso a `obra_insumo_precios` (precio editado/en firme por obra, ver
/// `supabase/migrations/0030_obra_insumo_precios.sql`) y al consolidado real de insumos de una
/// obra (`consolidado_insumos_obra`, `0031_consolidado_insumos_obra.sql`).
class ObraInsumosRepository {
  final SupabaseClient _client = Supabase.instance.client;

  /// Paso 2 de Mat y MO: insumos reales que consume la obra según sus composiciones de APU
  /// tildadas, con el precio automático (promedio de corralones) cuando existe.
  Future<List<InsumoConsolidadoObra>> getConsolidado(String obraId) async {
    final data = await _client.rpc('consolidado_insumos_obra', params: {'p_obra_id': obraId});
    return (data as List)
        .map((row) => InsumoConsolidadoObra.fromMap(row as Map<String, dynamic>))
        .toList();
  }
}
