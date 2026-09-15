import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/rubro_catalogo.dart';

/// Acceso a la tabla `rubros` de Supabase (catálogo de Solapa 1).
///
/// Traduce entre las columnas snake_case de la tabla (ver
/// `supabase/migrations/0015_rubros.sql`) y el modelo `RubroCatalogo`.
/// Desde la migración 0151 una fila puede ser **de una obra** (`obra_id` no nulo) y no solo del
/// catálogo: es la carpeta del presupuesto importado tal cual, que convive con el catálogo sin
/// mezclarse. Ver docs/carpetas_importado_y_catalogo_diseno_datos.md. Las filas oficiales
/// (`creador_usuario_id is null`) siguen abiertas a cualquier autenticado por RLS; las de una
/// carpeta las ve cualquier miembro de esa obra.
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
  Future<List<RubroCatalogo>> getCatalogoCompleto(String usuarioId, {String? obraId}) async {
    final data = await _client
        .from('rubros')
        .select()
        .or(filtroCarpeta(usuarioId, obraId));
    final rubros = (data as List)
        .map((row) => _fromRow(row as Map<String, dynamic>))
        .toList();
    rubros.sort(_compararCatalogo);
    return rubros;
  }

  /// Filtro de carpeta, compartido con `SubitemsRepository` (misma regla en las dos tablas desde la
  /// migración 0151). Devuelve el catálogo —oficial más lo propio del usuario— y, si se pasa
  /// `obraId`, además la carpeta de esa obra.
  ///
  /// Tres ramas de primer nivel en vez de un `or` anidado adentro de un `and`: PostgREST soporta
  /// las dos formas, pero esta se lee y se debuggea como lo que es (tres orígenes posibles).
  ///
  /// **El `obra_id.is.null` de las dos primeras ramas es lo que hace el trabajo.** Sin él, la
  /// carpeta de una obra se colaría en el catálogo de todas las demás obras del usuario, que es
  /// exactamente el bug que la 0151 viene a cerrar.
  static String filtroCarpeta(String usuarioId, String? obraId) {
    const oficial = 'and(obra_id.is.null,creador_usuario_id.is.null)';
    final propio = 'and(obra_id.is.null,creador_usuario_id.eq.$usuarioId)';
    if (obraId == null) return '$oficial,$propio';
    return '$oficial,$propio,obra_id.eq.$obraId';
  }

  /// Oficiales, después los propios del catálogo, después la carpeta de la obra. Dentro de cada
  /// bloque: los oficiales por `orden`, el resto por `createdAt` ("en el orden en que los creaste").
  ///
  /// La carpeta de obra al final es provisorio y no se ve: hoy no hay ninguna fila con `obra_id`.
  /// **La tanda 3 la saca de esta lista** y la pone en su propia carpeta, que es donde el orden
  /// importado va a mandar de verdad.
  static int _compararCatalogo(RubroCatalogo a, RubroCatalogo b) {
    int bloque(RubroCatalogo r) => r.obraId != null ? 2 : (r.creadorUsuarioId == null ? 0 : 1);
    final ba = bloque(a), bb = bloque(b);
    if (ba != bb) return ba.compareTo(bb);
    if (ba == 0) return a.orden.compareTo(b.orden);
    return a.createdAt.compareTo(b.createdAt);
  }

  /// Alta de un rubro personalizado (PRO). Nace con `usaApu = false` y
  /// `tipoPrecioManual = 'unitario'` siempre, sin selector en el alta —
  /// decisión de negocio: 'global' queda reservado para los 2 casos
  /// oficiales que ya lo usan (Instalaciones, Carpinterías, resueltos con
  /// presupuesto cerrado de un tercero); un PRO recién no tiene por qué
  /// pensar en esa distinción al crear su propio rubro. Se habilita
  /// `usaApu = true` cuando exista la Solapa 2 (APU) de verdad — hoy un
  /// rubro con usaApu = true no tendría manera de tener precio nunca.
  ///
  /// Sin `codigo`: ya no lo elige el usuario (Etapa D de
  /// docs/rubros_orden_diseno_datos.md) — lo completa el default de la
  /// columna (`gen_random_uuid()::text`, ver migración 0027). El código
  /// queda puramente interno, nunca visible en la UI; el número que ve el
  /// usuario es el posicional que arma RubrosTab.
  /// `obraId`: null (el default, y lo que hacen todas las llamadas de hoy) crea el rubro en el
  /// catálogo personal, como siempre. Con obra, lo crea en la carpeta de esa obra -- el camino que
  /// van a usar el importador (tanda 4) y el alta con selector de carpeta (tanda 3).
  ///
  /// Cuando va a una carpeta, `codigo` sigue saliendo del default de la columna (un uuid, 0027).
  /// **El importador NO va a usar este método**: él trae el código del Excel, que es todo el punto
  /// de "tal cual viene", y lo escribe explícito.
  Future<RubroCatalogo> crearPersonalizado({
    required String nombre,
    required String creadorUsuarioId,
    String? obraId,
  }) async {
    final inserted = await _client
        .from('rubros')
        .insert({
          'nombre': nombre,
          'usa_apu': false,
          'tipo_precio_manual': 'unitario',
          'creador_usuario_id': creadorUsuarioId,
          if (obraId != null) 'obra_id': obraId,
        })
        .select()
        .single();
    return _fromRow(inserted);
  }

  /// Borra un rubro propio. La política RLS `rubros_delete` (0015_rubros.sql)
  /// ya restringe esto a `creador_usuario_id = auth.uid()` — un intento de
  /// borrar un rubro ajeno o el catálogo oficial no encuentra fila para
  /// borrar, sin necesidad de chequear el dueño acá también. RubrosTab valida
  /// antes de llamar acá que el rubro no tenga uso en `obra_subitems` solo
  /// para decidir qué diálogo de confirmación mostrar -- a nivel de base ya
  /// no bloquea nada (`obra_subitems.rubro_id` tiene `on delete cascade`
  /// desde 0028_obra_subitems_cascade_propio.sql). Lo que sí puede bloquear
  /// el DELETE es `importaciones_items.rubro_id` si el rubro vino del
  /// importador y esa FK no tiene cascade/set null todavía -- ver
  /// 0093_fix_delete_rubros_propios_importados.sql.
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
      obraId: row['obra_id']?.toString(),
    );
  }
}
