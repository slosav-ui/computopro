import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/insumo_busqueda.dart';

/// Acceso de solo lectura a `insumos` para el selector de "cambiar material" de la edición de APU
/// (ver `PanelEditarItemApu`). No crea insumos nuevos — eso es una pieza aparte, sin diseñar
/// todavía (búsqueda previa + precio obligatorio + mecanismo colaborativo, ver diagnóstico de
/// "edición de APU en la Solapa APU").
class InsumosRepository {
  final SupabaseClient _client = Supabase.instance.client;

  /// Solo materiales (`tipo = 'material'`) — el swap de esta pieza está acotado a materiales, no a
  /// mano de obra ni equipos (decisión explícita de Seba). `texto` vacío no dispara ninguna
  /// consulta, devuelve lista vacía directo -- evita pedir "todos los materiales" por accidente.
  Future<List<InsumoBusqueda>> buscarMateriales(String texto) async {
    final termino = texto.trim();
    if (termino.isEmpty) return [];
    final data = await _client
        .from('insumos')
        .select('id, nombre, unidad')
        .eq('tipo', 'material')
        .ilike('nombre', '%$termino%')
        .order('nombre')
        .limit(30);
    return [
      for (final row in data as List)
        InsumoBusqueda(
          id: (row as Map<String, dynamic>)['id'].toString(),
          nombre: row['nombre'] as String,
          unidad: row['unidad'] as String,
        ),
    ];
  }
}
