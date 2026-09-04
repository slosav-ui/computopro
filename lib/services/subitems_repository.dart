import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/subitem_catalogo.dart';

/// Acceso a la tabla `subitems` de Supabase (catálogo por rubro).
///
/// Traduce entre las columnas snake_case de la tabla (ver
/// `supabase/migrations/0016_subitems.sql`) y el modelo `SubitemCatalogo`.
class SubitemsRepository {
  final SupabaseClient _client = Supabase.instance.client;

  /// Sin `usuarioId` (o sin sesión): solo catálogo oficial, mismo criterio
  /// de fail-safe que `RubrosRepository.getCatalogoOficial()`. Con
  /// `usuarioId`: oficiales + propios del usuario, mismo patrón `.or()` que
  /// `RubrosRepository.getCatalogoCompleto()`.
  Future<List<SubitemCatalogo>> getSubitemsDeRubro(String rubroId, {String? usuarioId}) async {
    final data = usuarioId == null
        ? await _client
            .from('subitems')
            .select()
            .eq('rubro_id', rubroId)
            .isFilter('creador_usuario_id', null)
        : await _client
            .from('subitems')
            .select()
            .eq('rubro_id', rubroId)
            .or('creador_usuario_id.is.null,creador_usuario_id.eq.$usuarioId');
    final subitems = (data as List)
        .map((row) => _fromRow(row as Map<String, dynamic>))
        .toList();
    // Orden client-side, no server-side: `codigo` es texto jerárquico
    // ("1.1", "12.10", "12.2"...), un .order('codigo') de Supabase lo
    // ordenaría lexicográficamente ("12.10" antes que "12.2"). Se separa por
    // '.' y se compara cada segmento como número. Los propios se cargan con
    // un código "N.M" que sigue la secuencia del rubro (ver
    // SubitemsScreen._siguienteCodigoPropio), así que el mismo comparador
    // los ordena bien sin lógica aparte.
    subitems.sort((a, b) => _compararCodigoNatural(a.codigo, b.codigo));
    return subitems;
  }

  /// Alta de un subítem personalizado (PRO), en cualquier rubro — no solo
  /// en rubros sin APU. Sin selector de nada más que nombre/unidad: el
  /// código lo arma quien llama (SubitemsScreen, siguiente en la secuencia
  /// visible de ese rubro), esta función no lo infiere.
  Future<SubitemCatalogo> crearPersonalizado({
    required String rubroId,
    required String codigo,
    required String descripcion,
    required String unidad,
    required String creadorUsuarioId,
  }) async {
    final inserted = await _client
        .from('subitems')
        .insert({
          'rubro_id': rubroId,
          'codigo': codigo,
          'descripcion': descripcion,
          'unidad': unidad,
          'creador_usuario_id': creadorUsuarioId,
        })
        .select()
        .single();
    return _fromRow(inserted);
  }

  /// Borra un subítem propio. La política RLS `subitems_delete`
  /// (0016_subitems.sql) ya restringe esto a `creador_usuario_id =
  /// auth.uid()`. Quien llama valida antes que no tenga uso en
  /// `obra_subitems` (ver
  /// ObraSubitemsRepository.getNombresObrasConUsoDeSubitem), pero quien
  /// realmente lo impide a nivel de base es la FK `obra_subitems.subitem_id`
  /// (sin cascade) si esa validación quedó desactualizada — mismo patrón
  /// que `RubrosRepository.eliminar`.
  Future<void> eliminar(String subitemId) async {
    await _client.from('subitems').delete().eq('id', subitemId);
  }

  /// Total de subitems del catálogo oficial por rubro, para el indicador
  /// "N de M tildados" de RubrosTab. Una sola consulta plana agrupada acá en
  /// Dart, no una consulta por rubro (serían 20 roundtrips).
  Future<Map<String, int>> getConteoOficialPorRubro() async {
    final data = await _client
        .from('subitems')
        .select('rubro_id')
        .isFilter('creador_usuario_id', null);
    final conteo = <String, int>{};
    for (final row in data as List) {
      final rubroId = (row as Map<String, dynamic>)['rubro_id'].toString();
      conteo[rubroId] = (conteo[rubroId] ?? 0) + 1;
    }
    return conteo;
  }

  /// Filas de `subitems` por id — para resolver descripciones en la vista previa del certificado
  /// (subítems de varios rubros a la vez, a diferencia de `getSubitemsDeRubro`). Sin filtro de
  /// `creador_usuario_id`: la propia RLS de `subitems_select` (0016, extendida en 0019 con
  /// `tiene_apu_ajena_visible_por_subitem`) decide qué filas puede ver quien llama — un id que
  /// exista pero no sea visible simplemente no vuelve, y quien llama tiene que resolverlo con un
  /// fallback (mismo criterio que `coalesce(s.descripcion, ...)` ya usa del lado SQL). Lista vacía
  /// si `ids` viene vacía, sin ida al servidor.
  Future<List<SubitemCatalogo>> getPorIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final data = await _client.from('subitems').select().inFilter('id', ids);
    return (data as List)
        .map((row) => _fromRow(row as Map<String, dynamic>))
        .toList();
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
