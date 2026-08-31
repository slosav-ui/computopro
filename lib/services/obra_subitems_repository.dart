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

  /// Cuántos subitems están tildados (`es_aplicable = true`) por rubro, para
  /// una obra puntual — el indicador "N de M" de RubrosTab. Misma consulta
  /// plana agrupada en Dart que `getConteoOficialPorRubro` de
  /// `SubitemsRepository`; misma precondición temporal `sector is null` que
  /// `getMapaDeRubro` (ver ese método para el detalle).
  Future<Map<String, int>> getConteoTildadosPorObra(String obraId) async {
    final data = await _client
        .from('obra_subitems')
        .select('rubro_id')
        .eq('obra_id', obraId)
        .eq('es_aplicable', true)
        .isFilter('sector', null);
    final conteo = <String, int>{};
    for (final row in data as List) {
      final rubroId = (row as Map<String, dynamic>)['rubro_id'].toString();
      conteo[rubroId] = (conteo[rubroId] ?? 0) + 1;
    }
    return conteo;
  }

  /// Nombres de las obras donde el rubro `rubroId` ya tiene alguna fila en
  /// `obra_subitems` — tildada o no: la FK `obra_subitems.rubro_id` (ver
  /// 0019_obra_subitems.sql) no tiene `on delete cascade`, así que cualquier
  /// fila, incluso una destildada con cantidad cargada, alcanza para que
  /// Postgres rechace el DELETE de ese rubro. Se usa antes de ofrecer borrar
  /// un rubro propio (RubrosTab), para avisar en qué obra(s) está en vez de
  /// dejar al usuario buscando a ciegas.
  ///
  /// "obra sin acceso" como fallback si la política de SELECT de `obras`
  /// (dueño único, `id_admin_creador = auth.uid()`) no deja ver el nombre de
  /// alguna de esas obras — puede pasar si el dueño del rubro es colaborador,
  /// no dueño, de esa obra puntual. No debería darse en el caso típico (un
  /// PRO usa su propio rubro en sus propias obras), pero no hay que romper
  /// el diálogo si pasa.
  Future<List<String>> getNombresObrasConUso(String rubroId) async {
    final data = await _client
        .from('obra_subitems')
        .select('obra_id')
        .eq('rubro_id', rubroId);
    final obraIds = <String>{
      for (final row in data as List) (row as Map<String, dynamic>)['obra_id'].toString(),
    };
    if (obraIds.isEmpty) return [];

    final obrasData = await _client
        .from('obras')
        .select('id, nombre')
        .inFilter('id', obraIds.toList());
    final nombresPorId = <String, String>{
      for (final row in obrasData as List)
        (row as Map<String, dynamic>)['id'].toString(): row['nombre'].toString(),
    };
    return obraIds.map((id) => nombresPorId[id] ?? 'obra sin acceso').toList();
  }

  /// Igual que getNombresObrasConUso, pero por subítem en vez de por rubro —
  /// se usa antes de ofrecer borrar un subítem propio en SubitemsScreen. La
  /// FK `obra_subitems.subitem_id` (0019_obra_subitems.sql) tampoco tiene
  /// `on delete cascade`, mismo mecanismo de protección a nivel de base.
  Future<List<String>> getNombresObrasConUsoDeSubitem(String subitemId) async {
    final data = await _client
        .from('obra_subitems')
        .select('obra_id')
        .eq('subitem_id', subitemId);
    final obraIds = <String>{
      for (final row in data as List) (row as Map<String, dynamic>)['obra_id'].toString(),
    };
    if (obraIds.isEmpty) return [];

    final obrasData = await _client
        .from('obras')
        .select('id, nombre')
        .inFilter('id', obraIds.toList());
    final nombresPorId = <String, String>{
      for (final row in obrasData as List)
        (row as Map<String, dynamic>)['id'].toString(): row['nombre'].toString(),
    };
    return obraIds.map((id) => nombresPorId[id] ?? 'obra sin acceso').toList();
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

  /// Guarda el precio manual de un subítem que ya tenía fila — rubros con
  /// `usa_apu = false` (1, 18, 19, 20 y cualquier custom), donde el precio
  /// no puede venir nunca de una composición de APU. Mismo criterio que
  /// actualizarCantidad: la validación de numérico/no-negativo es
  /// responsabilidad de quien llama, acá se persiste tal cual se recibe.
  ///
  /// `precio` nullable: la columna siempre admitió `null` ("sin decidir
  /// todavía"), y desde que se permite vaciar un precio ya cargado (antes se
  /// bloqueaba, ver SubitemsScreen._guardarPrecio) también significa "el
  /// usuario lo sacó a propósito".
  Future<ObraSubitem> actualizarPrecioUnitarioManual({
    required String id,
    required double? precio,
    required String usuarioId,
  }) async {
    final updated = await _client
        .from('obra_subitems')
        .update({
          'precio_unitario_manual': precio,
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
