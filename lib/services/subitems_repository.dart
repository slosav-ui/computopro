import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/subitem_catalogo.dart';

/// Acceso a la tabla `subitems` de Supabase (catálogo por rubro).
///
/// Traduce entre las columnas snake_case de la tabla (ver
/// `supabase/migrations/0016_subitems.sql`) y el modelo `SubitemCatalogo`.
class SubitemsRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<SubitemCatalogo>> getSubitemsDeRubro(String rubroId) async {
    final data = await _client
        .from('subitems')
        .select()
        .eq('rubro_id', rubroId)
        .isFilter('creador_usuario_id', null);
    final subitems = (data as List)
        .map((row) => _fromRow(row as Map<String, dynamic>))
        .toList();
    // Orden client-side, no server-side: `codigo` es texto jerárquico
    // ("1.1", "12.10", "12.2"...), un .order('codigo') de Supabase lo
    // ordenaría lexicográficamente ("12.10" antes que "12.2"). Se separa por
    // '.' y se compara cada segmento como número.
    subitems.sort((a, b) => _compararCodigoNatural(a.codigo, b.codigo));
    return subitems;
  }

  int _compararCodigoNatural(String a, String b) {
    final segmentosA = a.split('.');
    final segmentosB = b.split('.');
    final largo = segmentosA.length < segmentosB.length ? segmentosA.length : segmentosB.length;
    for (var i = 0; i < largo; i++) {
      final numA = int.tryParse(segmentosA[i]);
      final numB = int.tryParse(segmentosB[i]);
      if (numA == null || numB == null) {
        final cmp = segmentosA[i].compareTo(segmentosB[i]);
        if (cmp != 0) return cmp;
        continue;
      }
      if (numA != numB) return numA.compareTo(numB);
    }
    return segmentosA.length.compareTo(segmentosB.length);
  }

  SubitemCatalogo _fromRow(Map<String, dynamic> row) {
    return SubitemCatalogo(
      id: row['id'].toString(),
      rubroId: row['rubro_id'].toString(),
      codigo: row['codigo'].toString(),
      descripcion: row['descripcion'].toString(),
      unidad: row['unidad'].toString(),
      creadorUsuarioId: row['creador_usuario_id']?.toString(),
    );
  }
}
