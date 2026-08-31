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

  /// Oficiales + rubros propios del usuario, en una sola consulta. Sin esto,
  /// un rubro custom nunca aparecería en la lista — getCatalogoOficial()
  /// filtra explícitamente `creador_usuario_id is null`.
  ///
  /// Orden default (fallback cuando la obra no tiene overrides en
  /// `obra_rubros_orden` — ver docs/rubros_orden_diseno_datos.md): oficiales
  /// primero (por `orden`, igual que siempre), propios después. Dentro de
  /// cada bloque: oficiales por `orden`; propios por `createdAt` — cambiado
  /// desde `codigo` (que ordenaba antes) porque el código deja de ser
  /// visible en la UI, así que ordenar por él ya no tiene sentido para el
  /// usuario; "en el orden en que los creaste" es más intuitivo.
  Future<List<RubroCatalogo>> getCatalogoCompleto(String usuarioId) async {
    final data = await _client
        .from('rubros')
        .select()
        .or('creador_usuario_id.is.null,creador_usuario_id.eq.$usuarioId');
    final rubros = (data as List)
        .map((row) => _fromRow(row as Map<String, dynamic>))
        .toList();
    rubros.sort((a, b) {
      final aOficial = a.creadorUsuarioId == null;
      final bOficial = b.creadorUsuarioId == null;
      if (aOficial != bOficial) return aOficial ? -1 : 1;
      return aOficial ? a.orden.compareTo(b.orden) : a.createdAt.compareTo(b.createdAt);
    });
    return rubros;
  }

  /// Alta de un rubro personalizado (PRO). Nace con `usaApu = false` y
  /// `tipoPrecioManual = 'unitario'` siempre, sin selector en el alta —
  /// decisión de negocio: 'global' queda reservado para los 2 casos
  /// oficiales que ya lo usan (Instalaciones, Carpinterías, resueltos con
  /// presupuesto cerrado de un tercero); un PRO recién no tiene por qué
  /// pensar en esa distinción al crear su propio rubro. Se habilita
  /// `usaApu = true` cuando exista la Solapa 2 (APU) de verdad — hoy un
  /// rubro con usaApu = true no tendría manera de tener precio nunca.
  Future<RubroCatalogo> crearPersonalizado({
    required String codigo,
    required String nombre,
    required String creadorUsuarioId,
  }) async {
    final inserted = await _client
        .from('rubros')
        .insert({
          'codigo': codigo,
          'nombre': nombre,
          'usa_apu': false,
          'tipo_precio_manual': 'unitario',
          'creador_usuario_id': creadorUsuarioId,
        })
        .select()
        .single();
    return _fromRow(inserted);
  }

  /// Borra un rubro propio. La política RLS `rubros_delete` (0015_rubros.sql)
  /// ya restringe esto a `creador_usuario_id = auth.uid()` — un intento de
  /// borrar un rubro ajeno o el catálogo oficial no encuentra fila para
  /// borrar, sin necesidad de chequear el dueño acá también. RubrosTab valida
  /// antes de llamar acá que el rubro no tenga uso en `obra_subitems` (ver
  /// ObraSubitemsRepository.getNombresObrasConUso), pero quien realmente lo
  /// impide a nivel de base es la FK `obra_subitems.rubro_id` (sin cascade,
  /// ver 0019_obra_subitems.sql) si esa validación quedó desactualizada.
  Future<void> eliminar(String rubroId) async {
    await _client.from('rubros').delete().eq('id', rubroId);
  }

  RubroCatalogo _fromRow(Map<String, dynamic> row) {
    return RubroCatalogo(
      id: row['id'].toString(),
      codigo: row['codigo'].toString(),
      nombre: row['nombre'].toString(),
      orden: (row['orden'] as num).toInt(),
      usaApu: row['usa_apu'] == true,
      createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ?? DateTime.now(),
      tipoPrecioManual: row['tipo_precio_manual']?.toString(),
      creadorUsuarioId: row['creador_usuario_id']?.toString(),
    );
  }
}
