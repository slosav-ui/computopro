import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/obra_subitem.dart';

/// Acceso a la tabla `obra_subitems` de Supabase (el cómputo métrico real de
/// una obra: qué subítem está tildado, con qué cantidad).
///
/// Traduce entre las columnas snake_case de la tabla (ver
/// `supabase/migrations/0019_obra_subitems.sql`) y el modelo `ObraSubitem`.
/// Tildar/destildar (`esAplicable`) y `cantidad` ya conectados;
/// `precioUnitarioManual` sigue sin tocar.
class ObraSubitemsRepository {
  final SupabaseClient _client = Supabase.instance.client;

  /// Mapa subitemId -> ObraSubitem para un rubro de una obra puntual, para que
  /// la pantalla sepa qué checkbox mostrar tildado al abrir.
  ///
  /// `sector is null` es una precondición temporal: hoy no hay UI para cargar
  /// el mismo subítem en más de un sector de la misma obra (ver
  /// docs/rubros_apu_diseno_datos.md §3.C), así que se asume una sola fila por
  /// (obraId, subitemId). Cuando exista esa UI, esta consulta y el mapeo
  /// subitemId -> fila única dejan de alcanzar y hay que revisarlos.
  Future<Map<String, ObraSubitem>> getMapaDeRubro({
    required String obraId,
    required String rubroId,
  }) async {
    final data = await _client
        .from('obra_subitems')
        .select()
        .eq('obra_id', obraId)
        .eq('rubro_id', rubroId)
        .isFilter('sector', null);
    final mapa = <String, ObraSubitem>{};
    for (final row in data as List) {
      final obraSubitem = _fromRow(row as Map<String, dynamic>);
      if (obraSubitem.subitemId != null) {
        mapa[obraSubitem.subitemId!] = obraSubitem;
      }
    }
    return mapa;
  }

  /// Tilda un subítem por primera vez en la obra (todavía no tenía fila).
  /// `esAplicable` queda en `true` y `cantidad` en el default de la columna (0).
  Future<ObraSubitem> crear({
    required String obraId,
    required String rubroId,
    required String subitemId,
    required String agregadoPorUsuarioId,
  }) async {
    final inserted = await _client
        .from('obra_subitems')
        .insert({
          'obra_id': obraId,
          'rubro_id': rubroId,
          'subitem_id': subitemId,
          'es_aplicable': true,
          'agregado_por_usuario_id': agregadoPorUsuarioId,
        })
        .select()
        .single();
    return _fromRow(inserted);
  }

  /// Tilda/destilda un subítem que ya tenía fila. Nunca borra: preserva
  /// `cantidad` y el resto de los campos para que, si se vuelve a tildar, el
  /// usuario recupere lo que había cargado.
  Future<ObraSubitem> actualizarEsAplicable({
    required String id,
    required bool esAplicable,
    required String usuarioId,
  }) async {
    final updated = await _client
        .from('obra_subitems')
        .update({
          'es_aplicable': esAplicable,
          'ultima_modificacion_usuario_id': usuarioId,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', id)
        .select()
        .single();
    return _fromRow(updated);
  }

  /// Guarda la cantidad de un subítem que ya tenía fila (solo se edita
  /// cantidad estando tildado, ver SubitemsScreen). La validación de que el
  /// valor sea numérico y no negativo es responsabilidad de quien llama —
  /// acá se persiste tal cual se recibe.
  Future<ObraSubitem> actualizarCantidad({
    required String id,
    required double cantidad,
    required String usuarioId,
  }) async {
    final updated = await _client
        .from('obra_subitems')
        .update({
          'cantidad': cantidad,
          'ultima_modificacion_usuario_id': usuarioId,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', id)
        .select()
        .single();
    return _fromRow(updated);
  }

  ObraSubitem _fromRow(Map<String, dynamic> row) {
    return ObraSubitem(
      id: row['id'].toString(),
      obraId: row['obra_id'].toString(),
      rubroId: row['rubro_id'].toString(),
      subitemId: row['subitem_id']?.toString(),
      descripcionLibre: row['descripcion_libre']?.toString(),
      sector: row['sector']?.toString(),
      cantidad: (row['cantidad'] as num?)?.toDouble() ?? 0.0,
      precioUnitarioManual: (row['precio_unitario_manual'] as num?)?.toDouble(),
      esAplicable: row['es_aplicable'] == true,
      agregadoPorUsuarioId: row['agregado_por_usuario_id'].toString(),
      ultimaModificacionUsuarioId: row['ultima_modificacion_usuario_id']?.toString(),
      createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(row['updated_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}
