import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/apu_precio_subitem.dart';

/// Acceso a `apu_composiciones`/`apu_composicion_items` de Supabase (receta
/// de un subítem — materiales/mano de obra/equipos, ver
/// `supabase/migrations/0018_apu_composiciones.sql`).
///
/// 97 partidas / 770 ítems de rubros 2-17 ya están cargados (migraciones
/// 0022-0024), pero ningún archivo de `lib/` los leía hasta el paso 1 de la
/// vinculación con APU.
class ApuComposicionesRepository {
  final SupabaseClient _client = Supabase.instance.client;

  /// Paso 1: de la lista de subitemIds dada, cuáles ya tienen al menos una
  /// composición cargada (oficial o propia, lo que la RLS de
  /// `apu_composiciones` deje ver) — sin distinguir cuál ni traer sus
  /// ítems, es solo para el chip "APU" de SubitemsScreen.
  Future<Set<String>> getSubitemIdsConComposicion(List<String> subitemIds) async {
    if (subitemIds.isEmpty) return {};
    final data = await _client
        .from('apu_composiciones')
        .select('subitem_id')
        .inFilter('subitem_id', subitemIds);
    return {
      for (final row in data as List) (row as Map<String, dynamic>)['subitem_id'].toString(),
    };
  }

  /// Paso 3: precio derivado de la composición, batch (una sola llamada
  /// para todos los subitemIds de la pantalla, ver
  /// `calcular_precio_apu_subitems` en
  /// 0029_calcular_precio_apu_subitem.sql). Solo tiene sentido llamarlo con
  /// subitemIds que ya se sabe que tienen composición (ver
  /// getSubitemIdsConComposicion) — para el resto, sin filas en el
  /// resultado, no se muestra nada.
  Future<Map<String, ApuPrecioSubitem>> calcularPreciosSubitems(List<String> subitemIds) async {
    if (subitemIds.isEmpty) return {};
    final data = await _client.rpc('calcular_precio_apu_subitems', params: {'p_subitem_ids': subitemIds});
    final resultado = <String, ApuPrecioSubitem>{};
    for (final row in data as List) {
      final map = row as Map<String, dynamic>;
      resultado[map['subitem_id'].toString()] = ApuPrecioSubitem(
        precioTotal: (map['precio_total'] as num?)?.toDouble() ?? 0,
        insumosConPrecio: (map['insumos_con_precio'] as num?)?.toInt() ?? 0,
        insumosTotal: (map['insumos_total'] as num?)?.toInt() ?? 0,
      );
    }
    return resultado;
  }
}
