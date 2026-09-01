import 'package:supabase_flutter/supabase_flutter.dart';

/// Acceso a la tabla `obra_rubros_orden` de Supabase (overrides explícitos de
/// orden de rubros, por obra).
///
/// Ver supabase/migrations/0026_obra_rubros_orden.sql y
/// docs/rubros_orden_diseno_datos.md. Solo guarda filas para rubros que
/// alguien arrastró a mano en esa obra puntual — la ausencia total de filas
/// para una obra es el caso normal (nadie reordenó todavía) y cae al orden
/// default de `RubrosRepository.getCatalogoCompleto`.
class ObraRubrosOrdenRepository {
  final SupabaseClient _client = Supabase.instance.client;

  /// Mapa rubroId -> posicion para los overrides explícitos de una obra.
  /// Vacío si nadie reordenó nada todavía en esa obra — caso normal, no un
  /// error.
  Future<Map<String, double>> getOverridesDeObra(String obraId) async {
    final data = await _client
        .from('obra_rubros_orden')
        .select('rubro_id, posicion')
        .eq('obra_id', obraId);
    final overrides = <String, double>{};
    for (final row in data as List) {
      final fila = row as Map<String, dynamic>;
      overrides[fila['rubro_id'].toString()] = (fila['posicion'] as num).toDouble();
    }
    return overrides;
  }

  /// Guarda (o actualiza) la posición explícita de un rubro en una obra —
  /// un solo upsert por arrastre, nunca reescribe el resto de la lista. La
  /// posición ya viene calculada por quien llama (punto medio entre los dos
  /// vecinos nuevos, ver RubrosTab._onReorder) — este método no calcula
  /// nada, solo persiste.
  Future<void> moverRubro({
    required String obraId,
    required String rubroId,
    required double posicion,
    required String usuarioId,
  }) async {
    // updated_at lo mantiene un trigger de la base (0035_updated_at_trigger.sql),
    // no se manda desde acá.
    await _client.from('obra_rubros_orden').upsert(
      {
        'obra_id': obraId,
        'rubro_id': rubroId,
        'posicion': posicion,
        'updated_by_usuario_id': usuarioId,
      },
      onConflict: 'obra_id,rubro_id',
    );
  }
}
