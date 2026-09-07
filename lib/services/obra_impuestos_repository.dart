import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/obra_impuesto.dart';

/// Acceso a `obra_impuestos` (ver `supabase/migrations/0020_obra_presupuesto_config.sql` y
/// `0079_obra_impuestos_nombre_otro_longitud.sql`). Sin `crear`/`eliminar` a propósito -- las 4
/// filas de una obra se siembran solas por trigger al crearse la obra, nunca se agregan ni se
/// borran desde acá (ver `PanelEditarImpuestos`: "uno solo, no se borra").
class ObraImpuestosRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<ObraImpuesto>> getImpuestos(String obraId) async {
    final data = await _client
        .from('obra_impuestos')
        .select()
        .eq('obra_id', obraId)
        .order('orden', ascending: true);
    return (data as List).map((row) => _fromRow(row as Map<String, dynamic>)).toList();
  }

  /// Para IVA/IIBB/Tasas Municipales -- esas 3 nunca tocan `nombre_otro` (siempre `null`, el check
  /// `obra_impuestos_nombre_otro_solo_en_otro` de 0020 ya lo exige).
  Future<ObraImpuesto> actualizarPorcentaje({
    required String id,
    required double porcentaje,
  }) async {
    final updated = await _client
        .from('obra_impuestos')
        .update({'porcentaje': porcentaje})
        .eq('id', id)
        .select()
        .single();
    return _fromRow(updated);
  }

  /// Para la fila `tipo = 'otro'` -- porcentaje y nombre juntos, en la misma llamada (evita que
  /// quede un porcentaje > 0 sin nombre, o un nombre sin porcentaje, a mitad de guardar).
  /// `nombreOtro` null o vacío = "vaciar el cuarto impuesto" (no un DELETE, ver `PanelEditarImpuestos`
  /// y el comentario de cabecera de este archivo).
  Future<ObraImpuesto> actualizarOtro({
    required String id,
    required double porcentaje,
    required String? nombreOtro,
  }) async {
    final updated = await _client
        .from('obra_impuestos')
        .update({
          'porcentaje': porcentaje,
          'nombre_otro': (nombreOtro == null || nombreOtro.trim().isEmpty) ? null : nombreOtro.trim(),
        })
        .eq('id', id)
        .select()
        .single();
    return _fromRow(updated);
  }

  ObraImpuesto _fromRow(Map<String, dynamic> row) {
    return ObraImpuesto(
      id: row['id'].toString(),
      obraId: row['obra_id'].toString(),
      tipo: tipoImpuestoDesdeDb(row['tipo'].toString()),
      nombreOtro: row['nombre_otro']?.toString(),
      porcentaje: (row['porcentaje'] as num).toDouble(),
      orden: (row['orden'] as num).toInt(),
    );
  }
}
