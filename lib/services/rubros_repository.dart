import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/rubro_catalogo.dart';

/// Acceso a la tabla `rubros` de Supabase (catálogo de Solapa 1).
///
/// Traduce entre las columnas snake_case de la tabla (ver
/// `supabase/migrations/0015_rubros.sql`) y el modelo `RubroCatalogo`.
/// Catálogo global, no por obra — las filas oficiales (`creador_usuario_id
/// is null`) están abiertas a cualquier autenticado por RLS.
class RubrosRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<RubroCatalogo>> getCatalogoOficial() async {
    final data = await _client
        .from('rubros')
        .select()
        .isFilter('creador_usuario_id', null)
        .order('orden', ascending: true);
    return (data as List)
        .map((row) => _fromRow(row as Map<String, dynamic>))
        .toList();
  }

  RubroCatalogo _fromRow(Map<String, dynamic> row) {
    return RubroCatalogo(
      id: row['id'].toString(),
      codigo: row['codigo'].toString(),
      nombre: row['nombre'].toString(),
      orden: (row['orden'] as num).toInt(),
      usaApu: row['usa_apu'] == true,
      tipoPrecioManual: row['tipo_precio_manual']?.toString(),
      creadorUsuarioId: row['creador_usuario_id']?.toString(),
    );
  }
}
