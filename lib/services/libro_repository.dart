import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/libro_entrada.dart';
import '../data/models/obra_member.dart';

/// Acceso a `libro_entradas` — el libro de comunicaciones de obra (0003, RLS en 0004 corregida por
/// la 0134, numeración sacada por la 0137). Diseño: docs/libro_obra_horizonte.md.
///
/// **Acá no hay guards de autoridad, y es a propósito.** Quién escribe y quién no lo decide la
/// policy de INSERT, que es una sola definición y corre del lado del servidor. La app pregunta lo
/// mismo por `UserContext` solo para decidir si muestra el compositor — si las dos divergieran, la
/// que manda es la base, y lo peor que pasa es un campo de texto que al enviar falla con el mensaje
/// de Postgres.
///
/// **Sin `update` ni `delete`, porque no existen**: la tabla no tiene esas políticas. Un método de
/// edición acá sería una mentira que falla siempre.
/// Lo que esta persona tiene sin leer en el libro de una obra (`0140`).
class NovedadesLibro {
  final int cuantos;

  /// Los nombres de quienes escribieron, sin repetir y sin incluir al que pregunta. Puede venir
  /// vacío si nadie cargó su nombre en el perfil -- ahí la pantalla dice cuántos mensajes hay y
  /// nada más, que es mejor que inventar un nombre.
  final List<String> autores;

  final DateTime? masViejo;

  const NovedadesLibro({required this.cuantos, this.autores = const [], this.masViejo});

  bool get hay => cuantos > 0;
}

class LibroRepository {
  final SupabaseClient _client = Supabase.instance.client;

  static const _columnas =
      'id, obra_id, libro, autor_usuario_id, autor_rol, contenido, adjuntos, '
      'entrada_padre_id, created_at';

  Future<T> _conLog<T>(String metodo, Future<T> Function() accion) async {
    try {
      return await accion();
    } on PostgrestException catch (e) {
      debugPrint(
        'LibroRepository.$metodo falló (Postgrest) -- code=${e.code} message=${e.message} '
        'details=${e.details} hint=${e.hint}',
      );
      rethrow;
    } catch (e, st) {
      debugPrint('LibroRepository.$metodo falló: $e\n$st');
      rethrow;
    }
  }

  /// El libro entero de una obra, cronológico, la más vieja primero -- que es como se lee un libro.
  /// La pantalla arranca abajo.
  ///
  /// Plano, sin hilos: la conversación no tiene acuses ni respuestas anidadas (cambio de alcance del
  /// 2026-09-14). Si algún día se agrega "responder citando", `entrada_padre_id` está en el modelo y
  /// el trigger de la `0137` ya lo protege.
  Future<List<LibroEntrada>> getEntradas({
    required String obraId,
    TipoLibro libro = TipoLibro.obra,
  }) {
    return _conLog('getEntradas', () async {
      final data = await _client
          .from('libro_entradas')
          .select(_columnas)
          .eq('obra_id', obraId)
          .eq('libro', libro.columna)
          .order('created_at', ascending: true);
      return [
        for (final row in data as List) LibroEntrada.desdeRow(row as Map<String, dynamic>),
      ];
    });
  }

  /// Marca el libro como leído hasta `hasta` -- RPC a `marcar_libro_leido` (`0139`).
  ///
  /// **`hasta` es la fecha de la última entrada que se cargó, no `now()`**, y no es prolijidad: la
  /// pantalla primero trae las entradas y después marca. Si en ese intervalo entra un mensaje nuevo,
  /// marcar con `now()` lo daría por leído sin haberlo mostrado nunca.
  ///
  /// Silenciosa ante error a propósito: si falla, el aviso queda prendido una vuelta más. Es
  /// molesto; romperle la pantalla al que vino a leer, peor.
  Future<void> marcarLeido({required String obraId, DateTime? hasta}) async {
    try {
      await _client.rpc('marcar_libro_leido', params: {
        'p_obra_id': obraId,
        'p_hasta': hasta?.toUtc().toIso8601String(),
      });
    } catch (e) {
      debugPrint('LibroRepository.marcarLeido falló (se reintenta al volver a abrir): $e');
    }
  }

  // ===========================================================================
  // Adjuntos: foto y nota de voz (tanda 3)
  // ===========================================================================
  //
  // Van adentro de la entrada, en `adjuntos jsonb`, como parte del mensaje -- no hay galería
  // aparte (Seba, 2026-09-13). El bucket `libro-obra` y sus policies existen desde la 0134.

  static const bucket = 'libro-obra';

  /// Sube un archivo y devuelve el path que hay que guardar en `adjuntos`.
  ///
  /// **La convención del path no es decorativa: es de lo que depende la RLS del bucket.** El primer
  /// segmento tiene que ser el `obra_id` en texto plano, porque las dos policies de la 0134 hacen
  /// `is_obra_member((storage.foldername(name))[1]::uuid)`. Un path armado de otra forma sube (o no)
  /// según el azar y después no lo puede leer nadie.
  Future<String> subirAdjunto({
    required String obraId,
    required String nombreArchivo,
    required Uint8List bytes,
  }) {
    return _conLog('subirAdjunto', () async {
      final path = '$obraId/${DateTime.now().microsecondsSinceEpoch}-$nombreArchivo';
      await _client.storage.from(bucket).uploadBinary(path, bytes);
      return path;
    });
  }

  /// URL firmada para mostrar o reproducir un adjunto. El bucket es privado: sin firma no se abre.
  ///
  /// Una hora de validez -- alcanza de sobra para mirar una foto o escuchar un audio, y no deja
  /// links eternos dando vueltas si alguien copia la URL.
  Future<String> urlAdjunto(String path) {
    return _conLog('urlAdjunto', () async {
      return _client.storage.from(bucket).createSignedUrl(path, 3600);
    });
  }

  /// Qué hay sin leer en el libro de esta obra -- RPC a `libro_novedades` (`0140`). Es el aviso
  /// que va **adentro de Gestión de Obra**, donde el usuario ya está mirando esa obra.
  ///
  /// Siempre devuelve una fila: `cuantos = 0` cuando no hay nada nuevo.
  Future<NovedadesLibro> getNovedades(String obraId) {
    return _conLog('getNovedades', () async {
      final data = await _client.rpc('libro_novedades', params: {'p_obra_id': obraId});
      final filas = data as List?;
      if (filas == null || filas.isEmpty) return const NovedadesLibro(cuantos: 0);
      final row = filas.first as Map<String, dynamic>;
      return NovedadesLibro(
        cuantos: (row['cuantos'] as num?)?.toInt() ?? 0,
        autores: row['autores'] == null
            ? const []
            : List<String>.from((row['autores'] as List).map((a) => a.toString())),
        masViejo: DateTime.tryParse(row['mas_viejo']?.toString() ?? '')?.toLocal(),
      );
    });
  }

  /// Escribe una entrada.
  ///
  /// `created_at` no se manda: es el "cuándo" del registro y lo pone la base con su reloj, no el
  /// teléfono del que escribe — que puede tener la hora mal.
  ///
  /// `autorRol` es con qué rol firma, y tiene que ser un rol que la persona realmente tenga en la
  /// obra: la policy lo valida con `tiene_rol_en_obra(obra_id, autor_rol)`.
  Future<LibroEntrada> crearEntrada({
    required String obraId,
    required String contenido,
    required RolProyecto autorRol,
    required String autorUsuarioId,
    TipoLibro libro = TipoLibro.obra,
    List<String> adjuntos = const [],
  }) {
    return _conLog('crearEntrada', () async {
      final row = await _client
          .from('libro_entradas')
          .insert({
            'obra_id': obraId,
            'libro': libro.columna,
            'autor_usuario_id': autorUsuarioId,
            'autor_rol': rolProyectoAColumna(autorRol),
            'contenido': contenido,
            if (adjuntos.isNotEmpty) 'adjuntos': adjuntos,
          })
          .select(_columnas)
          .single();
      return LibroEntrada.desdeRow(row);
    });
  }
}
