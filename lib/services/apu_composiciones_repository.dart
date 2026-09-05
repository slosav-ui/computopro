import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/apu_precio_subitem.dart';
import '../data/models/apu_composicion_item_detalle.dart';

/// Acceso a `apu_composiciones`/`apu_composicion_items` de Supabase (receta
/// de un subítem — materiales/mano de obra/equipos, ver
/// `supabase/migrations/0018_apu_composiciones.sql`).
///
/// 97 partidas / 770 ítems de rubros 2-17 ya están cargados (migraciones
/// 0022-0024), pero ningún archivo de `lib/` los leía hasta el paso 1 de la
/// vinculación con APU.
class ApuComposicionesRepository {
  final SupabaseClient _client = Supabase.instance.client;

  /// Descubre sola, en vivo, si `calcular_precio_apu_subitems` (migración
  /// 0034, reemplaza a la 0029 original que nunca se aplicó) ya está
  /// aplicada -- no una bandera fija que alguien tendría que acordarse de
  /// sacar. `null` = todavía no se intentó en esta sesión de la app; se
  /// prueba normalmente. `false` = ya se confirmó con el código de error
  /// específico de Postgrest para "función no encontrada" (PGRST202) que
  /// la RPC no existe -- se saltea la llamada mientras dure la sesión, sin
  /// gastar red en algo que sabemos que va a fallar. `true` = ya se
  /// confirmó que funciona.
  ///
  /// static, no de instancia: SubitemsScreen crea un repositorio nuevo por
  /// cada rubro que se abre, así que una bandera de instancia se perdería
  /// entre pantallas. Arranca en `null` en cada arranque en frío de la
  /// app -- con 0034 ya aplicada, el primer intento de cada sesión la
  /// encuentra funcionando y queda en `true`, sin que nadie edite este
  /// archivo.
  static bool? _rpcCalcularPreciosDisponible;

  /// Paso 1: de la lista de subitemIds dada, cuáles ya tienen al menos una
  /// composición cargada (oficial o propia, lo que la RLS de
  /// `apu_composiciones` deje ver) — sin distinguir cuál ni traer sus
  /// ítems, es solo para el chip "APU" de SubitemsScreen.
  Future<Set<String>> getSubitemIdsConComposicion(List<String> subitemIds) async {
    if (subitemIds.isEmpty) return {};
    final data = await _client
        .from('apu_composiciones')
        .select('subitem_id')
        .inFilter('subitem_id', subitemIds);
    return {
      for (final row in data as List) (row as Map<String, dynamic>)['subitem_id'].toString(),
    };
  }

  /// Paso 3: precio derivado de la composición, batch (una sola llamada
  /// para todos los subitemIds de la pantalla, ver
  /// `calcular_precio_apu_subitems` en
  /// 0034_calcular_precio_apu_subitem.sql). Solo tiene sentido llamarlo con
  /// subitemIds que ya se sabe que tienen composición (ver
  /// getSubitemIdsConComposicion) — para el resto, sin filas en el
  /// resultado, no se muestra nada.
  ///
  /// `obraId` (agregado en 0034): la función usa el precio cargado a mano
  /// para esa obra en `obra_insumo_precios` antes que el promedio de
  /// corralón -- sin esto no tiene forma de saber qué obra está pidiendo el
  /// cálculo, y siempre caería al promedio (siempre null para mano de obra,
  /// ver el comentario de la migración).
  ///
  /// Mismo contrato de siempre para quien llama (SubitemsScreen no cambia
  /// nada de su try/catch): mientras la RPC no exista, esto sigue tirando
  /// una excepción -- solo que, a partir de la primera vez que se confirma
  /// el motivo específico (PGRST202, "función no encontrada"), las
  /// llamadas siguientes de la sesión tiran esa misma excepción sin gastar
  /// el viaje de red que ya sabemos que va a fallar. Ver
  /// _rpcCalcularPreciosDisponible.
  Future<Map<String, ApuPrecioSubitem>> calcularPreciosSubitems(String obraId, List<String> subitemIds) async {
    if (subitemIds.isEmpty) return {};
    if (_rpcCalcularPreciosDisponible == false) {
      throw const PostgrestException(
        message: 'calcular_precio_apu_subitems no disponible (confirmado antes en esta sesión)',
        code: 'PGRST202',
      );
    }
    try {
      final data = await _client.rpc('calcular_precio_apu_subitems', params: {
        'p_obra_id': obraId,
        'p_subitem_ids': subitemIds,
      });
      _rpcCalcularPreciosDisponible = true;
      final resultado = <String, ApuPrecioSubitem>{};
      for (final row in data as List) {
        final map = row as Map<String, dynamic>;
        resultado[map['subitem_id'].toString()] = ApuPrecioSubitem(
          precioTotal: (map['precio_total'] as num?)?.toDouble() ?? 0,
          insumosConPrecio: (map['insumos_con_precio'] as num?)?.toInt() ?? 0,
          insumosTotal: (map['insumos_total'] as num?)?.toInt() ?? 0,
        );
      }
      return resultado;
    } on PostgrestException catch (e) {
      // Solo el código específico de "función no encontrada" marca la
      // bandera -- cualquier otro error (red, RLS, lo que sea) deja el
      // comportamiento de siempre sin tocarla, para no apagar la
      // funcionalidad toda la sesión por un problema pasajero.
      if (e.code == 'PGRST202') {
        _rpcCalcularPreciosDisponible = false;
      }
      rethrow;
    }
  }

  /// Detalle línea por línea de la composición de un subítem — mano de obra, materiales y equipos
  /// con rendimiento y precio unitario ya resuelto (ver `calcular_composicion_detalle_subitem`,
  /// 0060_calcular_composicion_detalle_subitem.sql). Un solo subitemId, no batch: a diferencia de
  /// `calcularPreciosSubitems` (que arma el chip agregado de toda la lista de SubitemsScreen de
  /// una sola vez), esto lo pide ComposicionApuScreen para una partida puntual.
  ///
  /// Sin el mecanismo de `_rpcCalcularPreciosDisponible`: para cuando esto se llama, 0034/0059 ya
  /// se probaron al abrir SubitemsScreen (si no existieran, no habría llegado a mostrarse el chip
  /// "APU" que lleva a esta pantalla) — no hace falta repetir el cortocircuito acá.
  Future<List<ApuComposicionItemDetalle>> getComposicionDetalle(String obraId, String subitemId) async {
    final data = await _client.rpc('calcular_composicion_detalle_subitem', params: {
      'p_obra_id': obraId,
      'p_subitem_id': subitemId,
    });
    return [
      for (final row in data as List)
        ApuComposicionItemDetalle(
          tipoComponente: (row as Map<String, dynamic>)['tipo_componente'] as String,
          insumoNombre: row['insumo_nombre'] as String,
          insumoUnidad: row['insumo_unidad'] as String,
          rendimiento: (row['rendimiento'] as num).toDouble(),
          precioUnitario: (row['precio_unitario'] as num?)?.toDouble(),
        ),
    ];
  }
}
