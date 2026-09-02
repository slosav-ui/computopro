import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/valor_hora_categoria.dart';

/// Acceso a `calcular_valor_hora_mano_obra` (ver
/// supabase/migrations/0039_calcular_valor_hora_mano_obra.sql y
/// 0043_valor_hora_con_cargas.sql). Devuelve siempre las 5 categorías (AYUD/MOFI/OFIC/OFES/SERE),
/// no solo la que se vaya a mostrar en un momento dado — el panel de edición del Paso 5 (tanda
/// siguiente) las va a necesitar todas.
class ValorHoraManoObraRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<ValorHoraCategoria>> getValorHoraPorCategoria(String obraId) async {
    final data = await _client.rpc('calcular_valor_hora_mano_obra', params: {'p_obra_id': obraId});
    return (data as List)
        .map((row) => ValorHoraCategoria.fromMap(row as Map<String, dynamic>))
        .toList();
  }
}
