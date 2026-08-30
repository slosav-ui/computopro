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
  /// Orden: oficiales primero (por `orden`, igual que siempre), propios
  /// después — mismo criterio documentado en `0015_rubros.sql` ("los rubros
  /// custom de un PRO se listan después"), sin depender de calcular a mano
  /// un `orden` más alto que 20 al crearlos. Dentro de cada bloque, por
  /// código (no por nombre: alfabético dejaba "22 - MOV C/MAQ" antes que
  /// "21 - PARQUIZADO", que se lee raro).
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
      return aOficial ? a.orden.compareTo(b.orden) : _compararCodigo(a.codigo, b.codigo);
    });
    return rubros;
  }

  /// Compara códigos numéricamente cuando ambos lo son (evita que "100"
  /// ordene antes que "21" por comparación de texto); si alguno no es
  /// numérico (código custom libre, ej. "C1"), cae a comparación de texto.
  int _compararCodigo(String a, String b) {
    final numA = int.tryParse(a);
    final numB = int.tryParse(b);
    if (numA != null && numB != null) return numA.compareTo(numB);
    return a.compareTo(b);
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
