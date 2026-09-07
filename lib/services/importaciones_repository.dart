import 'dart:math';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/importacion.dart';
import '../data/models/importacion_item.dart';

/// Acceso a `importaciones`/`importaciones_items` + el bucket de Storage `importaciones` + la
/// función `confirmar_importacion`. Ver supabase/migrations/0080_importaciones.sql /
/// 0081_confirmar_importacion.sql y docs/importador_capa2_diseno_datos.md.
///
/// El parseo del Excel en sí NO pasa por acá -- corre en el cliente, `ExcelParser`
/// (lib/services/excel_parser.dart, ver el comentario de cabecera de ese archivo para el porqué de
/// sacar la Edge Function de esta ronda). Este repositorio solo sube el archivo original a Storage
/// (respaldo/trazabilidad, Capa 1 decisión F) y guarda lo que `ExcelParser` ya extrajo.
class ImportacionesRepository {
  final SupabaseClient _client = Supabase.instance.client;

  /// Sube el archivo a Storage y crea el header de la importación con las hojas ya elegidas, en
  /// ese orden -- si la subida falla, no queda un header huérfano sin archivo. Convención de path
  /// obligatoria para que la RLS de `0080` funcione: el primer segmento tiene que ser `obraId` en
  /// texto plano (ver el comentario de esa migración).
  Future<Importacion> subirYCrear({
    required String obraId,
    required String usuarioId,
    required String archivoNombre,
    required Uint8List bytes,
    required List<String> hojasSeleccionadas,
  }) async {
    final sufijo = _sufijoAleatorio();
    final path = '$obraId/$sufijo-$archivoNombre';
    await _client.storage.from('importaciones').uploadBinary(path, bytes);

    final inserted = await _client
        .from('importaciones')
        .insert({
          'obra_id': obraId,
          'usuario_id': usuarioId,
          'archivo_nombre': archivoNombre,
          'archivo_storage_path': path,
          'tipo_archivo': 'excel',
          'hojas_seleccionadas': hojasSeleccionadas,
        })
        .select()
        .single();
    return _fromRow(inserted);
  }

  /// Vuelca en `importaciones_items` lo que `ExcelParser.procesarFilas` ya extrajo en memoria --
  /// cada mapa de `filas` trae `orden`/`rubro_texto`/`descripcion_texto`/`unidad_texto`/`cantidad`/
  /// `precio_unitario`/`datos_originales`, se agrega acá el `importacion_id` que las une.
  Future<void> insertarItems(String importacionId, List<Map<String, dynamic>> filas) async {
    if (filas.isEmpty) return;
    final conImportacionId = filas.map((f) => {...f, 'importacion_id': importacionId}).toList();
    await _client.from('importaciones_items').insert(conImportacionId);
  }

  Future<Importacion> getImportacion(String importacionId) async {
    final row = await _client.from('importaciones').select().eq('id', importacionId).single();
    return _fromRow(row);
  }

  Future<List<ImportacionItem>> getItems(String importacionId) async {
    final data = await _client
        .from('importaciones_items')
        .select()
        .eq('importacion_id', importacionId)
        .order('orden', ascending: true);
    return (data as List).map((row) => _itemFromRow(row as Map<String, dynamic>)).toList();
  }

  /// Acción 1 y 2 de la revisión (§3 del diseño): elegir del catálogo o crear como propia terminan
  /// igual del lado de la fila -- las dos completan `rubro_id`/`subitem_id`. La creación en sí (si
  /// hace falta) la hace quien llama con `RubrosRepository`/`SubitemsRepository`, esta función solo
  /// deja el vínculo escrito en la fila importada.
  Future<void> resolverItem(String itemId, {required String rubroId, required String subitemId}) async {
    await _client
        .from('importaciones_items')
        .update({'rubro_id': rubroId, 'subitem_id': subitemId})
        .eq('id', itemId);
  }

  /// Deshace una resolución (por si el usuario se equivocó de fila del catálogo) -- vuelve al
  /// estado "sin resolver", mismo que "descartar" a nivel de base (ver ImportacionItem, doc §3).
  Future<void> desresolverItem(String itemId) async {
    await _client
        .from('importaciones_items')
        .update({'rubro_id': null, 'subitem_id': null})
        .eq('id', itemId);
  }

  Future<void> confirmarImportacion(String importacionId) async {
    await _client.rpc('confirmar_importacion', params: {'p_importacion_id': importacionId});
  }

  String _sufijoAleatorio() {
    final rnd = Random.secure();
    return List.generate(8, (_) => rnd.nextInt(16).toRadixString(16)).join();
  }

  Importacion _fromRow(Map<String, dynamic> row) {
    return Importacion(
      id: row['id'].toString(),
      obraId: row['obra_id'].toString(),
      usuarioId: row['usuario_id'].toString(),
      archivoNombre: row['archivo_nombre'].toString(),
      archivoStoragePath: row['archivo_storage_path'].toString(),
      tipoArchivo: row['tipo_archivo'].toString(),
      hojasSeleccionadas: ((row['hojas_seleccionadas'] as List?) ?? []).map((h) => h.toString()).toList(),
      monedaDefault: row['moneda_default']?.toString(),
      estado: row['estado'].toString(),
      pctAvanceManual: (row['pct_avance_manual'] as num?)?.toDouble(),
      montoCertificadoManual: (row['monto_certificado_manual'] as num?)?.toDouble(),
      confianzaGeneral: row['confianza_general']?.toString(),
      createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  ImportacionItem _itemFromRow(Map<String, dynamic> row) {
    return ImportacionItem(
      id: row['id'].toString(),
      importacionId: row['importacion_id'].toString(),
      orden: (row['orden'] as num).toInt(),
      rubroTexto: row['rubro_texto']?.toString(),
      descripcionTexto: row['descripcion_texto']?.toString(),
      unidadTexto: row['unidad_texto']?.toString(),
      cantidad: (row['cantidad'] as num?)?.toDouble(),
      precioUnitario: (row['precio_unitario'] as num?)?.toDouble(),
      moneda: row['moneda']?.toString(),
      rubroId: row['rubro_id']?.toString(),
      subitemId: row['subitem_id']?.toString(),
    );
  }
}
