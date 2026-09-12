import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/pendiente.dart';

/// Lo que espera la acción del usuario logueado, en todas sus obras -- RPC a `mis_pendientes()`
/// (0117, docs/avisos_pendientes_diseno.md). Una sola llamada para todo el dashboard.
class PendientesRepository {
  final SupabaseClient _client = Supabase.instance.client;

  /// El error real va a consola antes de relanzarlo -- mismo criterio que `_conLog` de
  /// `AdicionalesRepository`/`InvitacionesRepository`; quien llama decide qué hacer (el dashboard
  /// lo toma como "sin pendientes", sin tumbar la lista de obras).
  Future<List<Pendiente>> getMisPendientes() async {
    try {
      final data = await _client.rpc('mis_pendientes');
      return [
        for (final row in data as List) ?Pendiente.desdeRow(row as Map<String, dynamic>),
      ];
    } on PostgrestException catch (e) {
      debugPrint(
        'PendientesRepository.getMisPendientes falló (Postgrest) -- code=${e.code} '
        'message=${e.message} details=${e.details} hint=${e.hint}',
      );
      rethrow;
    } catch (e, st) {
      debugPrint('PendientesRepository.getMisPendientes falló: $e\n$st');
      rethrow;
    }
  }
}
