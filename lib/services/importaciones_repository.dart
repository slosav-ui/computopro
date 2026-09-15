import 'dart:math';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/importacion.dart';
import '../data/models/importacion_item.dart';
import '../core/utils/filas_afectadas.dart';
import '../data/models/reemplazo_importacion.dart';

/// Acceso a `importaciones`/`importaciones_items` + el bucket de Storage `importaciones` + la
/// función `confirmar_importacion`. Ver supabase/migrations/0080_importaciones.sql /
/// 0081_confirmar_importacion.sql y docs/importador_capa2_diseno_datos.md.
///
/// **Dos caminos, un destino.** Desde el importador inteligente
/// (docs/importador_inteligente_diagnostico.md) hay dos formas de llenar `importaciones_items`, y
/// las dos terminan en la misma pantalla de revisión:
///
///   - **Excel con encabezados reconocidos** -> `ExcelParser` en el cliente, gratis e instantáneo,
///     y `insertarItems` guarda lo que extrajo. No consume cupo.
///   - **PDF, foto, o Excel que el parser no entendió** -> `leerConIa`, que llama a la Edge
///     Function `leer-documento`. Consume una lectura del cupo mensual (0145).
///
/// El primero sigue existiendo y no es un plan B: cuando funciona es mejor que el modelo en las
/// tres dimensiones que importan (velocidad, costo y exactitud).
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
    String tipoArchivo = 'excel',
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
          'tipo_archivo': tipoArchivo,
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
    // 0121: con `.select()` y el chequeo, un UPDATE que la RLS no deja pasar se ve como error en
    // vez de dejar la fila "resuelta" solo en pantalla.
    final filas = await _client
        .from('importaciones_items')
        .update({'rubro_id': rubroId, 'subitem_id': subitemId})
        .eq('id', itemId)
        .select('id');
    exigirFilasAfectadas(filas);
  }

  /// Deshace una resolución (por si el usuario se equivocó de fila del catálogo) -- vuelve al
  /// estado "sin resolver", mismo que "descartar" a nivel de base (ver ImportacionItem, doc §3).
  Future<void> desresolverItem(String itemId) async {
    final filas = await _client
        .from('importaciones_items')
        .update({'rubro_id': null, 'subitem_id': null})
        .eq('id', itemId)
        .select('id');
    exigirFilasAfectadas(filas);
  }

  /// Corrige un valor leído mal. **Faltaba, y era el agujero grande del importador.**
  ///
  /// La pantalla de revisión sabía mapear una fila al catálogo, crearla como propia o descartarla,
  /// pero no sabía arreglar un número: `cantidad` y `precio_unitario` se mostraban como texto de
  /// solo lectura y no había método para actualizarlos. Con el parser de Excel se podía vivir sin
  /// esto (si la columna no existe, no hay número y se nota). Con un modelo de por medio no: el
  /// error típico es un número mal interpretado -- 410,96 leído como 41096 -- que llega a la
  /// pantalla con toda la cara de estar bien.
  ///
  /// Solo se mandan los campos que cambiaron. Corregir un valor **no** vuelve a llamar al modelo ni
  /// consume cupo: es una escritura directa a la fila.
  Future<void> actualizarItem(
    String itemId, {
    String? descripcionTexto,
    String? unidadTexto,
    double? cantidad,
    double? precioUnitario,
    bool limpiarCantidad = false,
    bool limpiarPrecio = false,
  }) async {
    final cambios = <String, dynamic>{};
    if (descripcionTexto != null) cambios['descripcion_texto'] = descripcionTexto;
    if (unidadTexto != null) cambios['unidad_texto'] = unidadTexto;
    // Los dos `limpiar*` existen porque `null` ya significa "no lo toques" en la firma: sin ellos
    // no habría forma de borrar un valor que el modelo inventó y que en el documento no está.
    if (limpiarCantidad) {
      cambios['cantidad'] = null;
    } else if (cantidad != null) {
      cambios['cantidad'] = cantidad;
    }
    if (limpiarPrecio) {
      cambios['precio_unitario'] = null;
    } else if (precioUnitario != null) {
      cambios['precio_unitario'] = precioUnitario;
    }
    if (cambios.isEmpty) return;

    final filas = await _client
        .from('importaciones_items')
        .update(cambios)
        .eq('id', itemId)
        .select('id');
    exigirFilasAfectadas(filas);
  }

  /// Cuántas lecturas con IA le quedan a este usuario este mes (0145).
  ///
  /// Se consulta **antes** de que elija el archivo. Que alguien saque una foto, la suba y recién
  /// ahí se entere de que no le quedan lecturas es la peor forma de decirlo.
  Future<CupoIa> cupoIa() async {
    final data = await _client.rpc('cupo_importaciones_ia');
    final row = (data as List).first as Map<String, dynamic>;
    return CupoIa(
      limite: (row['limite'] as num).toInt(),
      usadas: (row['usadas'] as num).toInt(),
      quedan: (row['quedan'] as num).toInt(),
      seReiniciaEl: DateTime.tryParse(row['se_reinicia_el']?.toString() ?? '')?.toLocal(),
    );
  }

  /// Manda el documento ya subido a la Edge Function `leer-documento`, que lo lee con un modelo y
  /// llena `importaciones_items`.
  ///
  /// Corre del lado del servidor por dos motivos que el importador de Excel no tenía: hay una clave
  /// de API que no puede viajar en el APK, y hay un costo por documento que se paga de una cuenta
  /// personal y que el cliente no puede ser el encargado de limitar.
  ///
  /// Si el usuario agotó el cupo, tira [CupoAgotadoException] con **el mensaje que escribió la
  /// base** -- no uno reescrito acá, que sería el mismo texto en dos lugares con dos destinos de
  /// mantenimiento.
  Future<LecturaIa> leerConIa(String importacionId) async {
    final respuesta = await _client.functions.invoke(
      'leer-documento',
      body: {'importacion_id': importacionId},
    );

    final data = respuesta.data;
    if (respuesta.status == 429) {
      throw CupoAgotadoException(_mensajeDeError(data) ?? 'Llegaste al límite de lecturas del mes.');
    }
    if (respuesta.status != 200) {
      throw Exception(_mensajeDeError(data) ?? 'No se pudo leer el documento.');
    }

    final mapa = (data as Map).cast<String, dynamic>();
    return LecturaIa(
      partidas: (mapa['partidas'] as num?)?.toInt() ?? 0,
      confianzaGeneral: mapa['confianza_general']?.toString(),
      totalDeclarado: (mapa['total_declarado'] as num?)?.toDouble(),
    );
  }

  String? _mensajeDeError(dynamic data) {
    if (data is Map && data['error'] != null) return data['error'].toString();
    return null;
  }

  /// `confirmar_importacion` (0081) -- upsert simple, sin diff ni aviso.
  ///
  /// **Ya no lo usa ninguna pantalla desde la 0157**: `reemplazarDesdeImportacion` hace lo mismo y
  /// además compara, así que la revisión pasa siempre por ahí, también en la primera importación.
  /// Se conserva el método porque la función sigue existiendo en la base y es el camino de
  /// compatibilidad si alguna vez hace falta aplicar sin comparar.
  Future<void> confirmarImportacion(String importacionId) async {
    await _client.rpc('confirmar_importacion', params: {'p_importacion_id': importacionId});
  }

  /// El resumen del diff entre la planilla y lo que ya está cargado -- RPC a
  /// `previsualizar_reemplazo_importacion` (0157). **No toca nada**: es lo que abre el aviso.
  Future<ResumenReemplazo> previsualizarReemplazo(String importacionId) async {
    final data = await _client.rpc('previsualizar_reemplazo_importacion', params: {
      'p_importacion_id': importacionId,
    });
    final filas = (data as List).cast<Map<String, dynamic>>();
    if (filas.isEmpty) {
      throw StateError('La vista previa del reemplazo no devolvió nada');
    }
    return ResumenReemplazo.fromMap(filas.first);
  }

  /// El detalle, una fila por diferencia -- RPC a `diferencias_reemplazo_importacion` (0157).
  ///
  /// Se pide **solo cuando el usuario toca "ver el detalle"**: con cincuenta diferencias nadie las
  /// mira una por una, así que el diálogo abre con el resumen y esto llega después. El resumen se
  /// calcula agregando sobre estas mismas filas, así que no pueden desviarse.
  Future<List<DiferenciaReemplazo>> diferenciasReemplazo(String importacionId) async {
    final data = await _client.rpc('diferencias_reemplazo_importacion', params: {
      'p_importacion_id': importacionId,
    });
    return [
      for (final row in (data as List).cast<Map<String, dynamic>>())
        DiferenciaReemplazo.fromMap(row),
    ];
  }

  /// Aplica la planilla entera -- RPC a `reemplazar_desde_importacion` (0157).
  ///
  /// La planilla gana en todo, cantidad incluida: **la decisión de qué aplicar se tomó en el aviso**,
  /// no acá. Lo que la planilla ya no trae se **destilda**, no se borra, así que es reversible.
  Future<({int actualizadas, int nuevas, int destildadas})> reemplazarDesdeImportacion(
    String importacionId,
  ) async {
    final data = await _client.rpc('reemplazar_desde_importacion', params: {
      'p_importacion_id': importacionId,
    });
    final row = (data as List).first as Map<String, dynamic>;
    return (
      actualizadas: (row['actualizadas'] as num?)?.toInt() ?? 0,
      nuevas: (row['nuevas'] as num?)?.toInt() ?? 0,
      destildadas: (row['destildadas'] as num?)?.toInt() ?? 0,
    );
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
      totalDeclarado: (row['total_declarado'] as num?)?.toDouble(),
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
      confianza: row['confianza']?.toString(),
      textoOriginal: (row['datos_originales'] as Map?)?['texto_original']?.toString(),
    );
  }
}

/// Lo que devuelve `cupo_importaciones_ia()` (0145).
class CupoIa {
  final int limite;
  final int usadas;
  final int quedan;

  /// Cuándo vuelve a cero. La calcula la base **en hora de Argentina**, que es la que sabe en qué
  /// huso se cuenta el mes -- si se calculara acá con el reloj del teléfono, un usuario con el huso
  /// mal puesto vería una fecha que no es.
  final DateTime? seReiniciaEl;

  const CupoIa({
    required this.limite,
    required this.usadas,
    required this.quedan,
    this.seReiniciaEl,
  });

  bool get agotado => quedan <= 0;
}

/// Resultado de una lectura con modelo.
class LecturaIa {
  final int partidas;
  final String? confianzaGeneral;
  final double? totalDeclarado;

  const LecturaIa({required this.partidas, this.confianzaGeneral, this.totalDeclarado});
}

/// El usuario llegó a su límite mensual de lecturas con IA.
///
/// Excepción propia y no un `Exception` genérico para que la pantalla pueda tratarla distinto: no
/// es un error, es un límite conocido con una salida concreta. El [mensaje] viene de la `0145`,
/// escrito para leerse tal cual.
class CupoAgotadoException implements Exception {
  final String mensaje;
  const CupoAgotadoException(this.mensaje);

  @override
  String toString() => mensaje;
}
