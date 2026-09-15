import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/insumo_busqueda.dart';
import '../data/models/insumo_del_catalogo.dart';

/// Acceso a `insumos` para el selector de "agregar material"/"agregar equipo" de la edición de APU
/// (ver `PanelAgregarItemApu`, `PanelCrearEquipoApu`). Para material sigue siendo de solo lectura
/// -- ese catálogo es curado, sin alta desde la app. Para equipo sí puede crear (ver
/// `buscarOCrearEquipo`, `0074_catalogo_colaborativo_equipos.sql`): el catálogo de equipos está
/// vacío hoy y se arma con lo que cada usuario va cargando -- distinto del mecanismo colaborativo
/// de precios de `docs/confianza_precios_diseno.md` (ese sigue sin implementar), acá lo que se
/// comparte es la existencia/nombre del equipo, visible para cualquiera apenas se crea (SELECT de
/// `insumos` ya es abierto, sin distinguir dueño).
class InsumosRepository {
  final SupabaseClient _client = Supabase.instance.client;

  /// El catálogo entero con su precio de referencia -- RPC a `catalogo_insumos_con_precio`
  /// (migración 0152).
  ///
  /// **No se puede consultar `precios` directamente desde la app**: su RLS (0013) es
  /// `is_corralon_owner(corralon_id)`, o sea que cada corralón ve solo los suyos y un PRO recibe
  /// cero filas -- sin error, que es el modo de falla peor. La función es `security definer` y
  /// devuelve promedio y cantidad, nunca el precio de un corralón puntual.
  Future<List<InsumoDelCatalogo>> getCatalogoConPrecio() async {
    final data = await _client.rpc('catalogo_insumos_con_precio');
    return [
      for (final row in (data as List).cast<Map<String, dynamic>>())
        InsumoDelCatalogo(
          id: row['insumo_id'].toString(),
          nombre: row['nombre']?.toString() ?? '',
          unidad: row['unidad']?.toString() ?? '',
          tipo: row['tipo']?.toString() ?? '',
          precioPromedio: (row['precio_promedio'] as num?)?.toDouble(),
          cantidadPrecios: (row['cantidad_precios'] as num?)?.toInt() ?? 0,
        ),
    ];
  }

  /// Busca un insumo del catálogo por nombre — RPC a `buscar_insumos_por_tipo` (migración 0153).
  ///
  /// `tipo`: `'material'` o `'equipo'` — agregar/quitar de esta pieza está acotado a esos dos, no a
  /// mano de obra (decisión explícita de Seba; mano de obra ya tiene sus 5 categorías siempre
  /// visibles, no se agregan/quitan líneas ahí). `texto` vacío no dispara ninguna consulta, devuelve
  /// lista vacía directo -- evita pedir "todo el catálogo de ese tipo" por accidente.
  ///
  /// **Era un `ilike '%texto%'` armado acá y ese fue el origen de las tres grúas duplicadas**: no
  /// ignoraba acentos, así que escribir "grua" no encontraba "GRÚA" y el usuario terminaba creando
  /// un equipo nuevo. La función compara con `insumo_nombre_normalizado` -- la misma definición de
  /// "el mismo nombre" que usa el alta y el índice único -- y además busca la subcadena en los dos
  /// sentidos, así que "grúas" encuentra "grúa".
  ///
  /// El filtro y el orden quedan del lado de la base a propósito: si vivieran acá volverían a
  /// divergir del criterio del alta, que es exactamente lo que pasó.
  Future<List<InsumoBusqueda>> buscarPorTipo(String texto, String tipo) async {
    final termino = texto.trim();
    if (termino.isEmpty) return [];
    final data = await _client.rpc('buscar_insumos_por_tipo', params: {
      'p_texto': termino,
      'p_tipo': tipo,
    });
    return [
      for (final row in (data as List).cast<Map<String, dynamic>>())
        InsumoBusqueda(
          id: row['id'].toString(),
          nombre: row['nombre']?.toString() ?? '',
          unidad: row['unidad']?.toString() ?? '',
        ),
    ];
  }

  /// `true` si ya existe al menos un insumo de este tipo en el catálogo -- decide si "Agregar
  /// equipo" abre el buscador o va directo al formulario de alta (ver `ComposicionApuScreen`,
  /// hoy solo se usa con `'equipo'`, que arranca en 0).
  Future<bool> hayInsumosDeTipo(String tipo) async {
    final data = await _client.from('insumos').select('id').eq('tipo', tipo).limit(1);
    return (data as List).isNotEmpty;
  }

  /// Encuentra un equipo existente por nombre (case-insensitive, sin espacios de borde) o lo crea
  /// si no hay ninguno todavía -- ver `buscar_o_crear_equipo_apu`,
  /// `0074_catalogo_colaborativo_equipos.sql`. La identidad de un equipo es el nombre, no el
  /// precio -- el precio queda aparte, por obra (`obra_insumo_precios`, ver
  /// `ApuComposicionesRepository.agregarEquipo`).
  Future<InsumoBusqueda> buscarOCrearEquipo({required String nombre, required String unidad}) async {
    final data = await _client.rpc('buscar_o_crear_equipo_apu', params: {
      'p_nombre': nombre,
      'p_unidad': unidad,
    });
    final row = (data as List).first as Map<String, dynamic>;
    return InsumoBusqueda(
      id: row['id'].toString(),
      nombre: row['nombre'] as String,
      unidad: row['unidad'] as String,
    );
  }
}
