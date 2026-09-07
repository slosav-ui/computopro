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
  /// 0060_calcular_composicion_detalle_subitem.sql, ampliada en 0071 con los ids/`es_personal` que
  /// necesita la edición). Un solo subitemId, no batch: a diferencia de `calcularPreciosSubitems`
  /// (que arma el chip agregado de toda la lista de SubitemsScreen de una sola vez), esto lo pide
  /// ComposicionApuScreen para una partida puntual.
  ///
  /// Sin el mecanismo de `_rpcCalcularPreciosDisponible`: para cuando esto se llama, 0034/0059 ya
  /// se probaron al abrir SubitemsScreen (si no existieran, no habría llegado a mostrarse el chip
  /// "APU" que lleva a esta pantalla) — no hace falta repetir el cortocircuito acá.
  Future<List<ApuComposicionItemDetalle>> getComposicionDetalle(String obraId, String subitemId) async {
    final data = await _client.rpc('calcular_composicion_detalle_subitem', params: {
      'p_obra_id': obraId,
      'p_subitem_id': subitemId,
    });
    return [for (final row in data as List) _itemDetalleDesdeFila(row as Map<String, dynamic>)];
  }

  /// Clona (si hace falta) y edita rendimiento y/o precio de una línea, en una sola llamada (ver
  /// `personalizar_item_apu`, reescrita en 0072_edicion_apu_correcciones.sql). Ubica la línea por
  /// `insumoId`, no por el id de la fila -- una fila virtual de mano de obra (una de las 5
  /// categorías que la receta todavía no tiene, ver `ApuComposicionItemDetalle.itemId`) no tiene
  /// id hasta que se edita. Devuelve la receta completa ya actualizada, para no tener que pedirla
  /// de nuevo con un segundo viaje de red.
  ///
  /// `precioNuevo` null = no toca el precio -- la función de base decide sola, según
  /// `insumos.tipo`, si el precio va a `obra_valor_hora_override` (mano de obra, por categoría
  /// UOCRA) o a `obra_insumo_precios` (material/equipo); acá no hace falta distinguirlo. Clonar la
  /// receta personal solo pasa si el rendimiento cambió de verdad -- editar solo el precio no
  /// fuerza un fork, porque el precio no vive en la receta (ver comentario de la migración).
  ///
  /// Gate de PRO: NO se chequea acá — responsabilidad de quien llama (mismo patrón que
  /// `PanelParametrosCargasSociales._onGuardar`, verificar `esPro` en vivo antes de llamar a esto).
  Future<List<ApuComposicionItemDetalle>> personalizarItem({
    required String obraId,
    required String subitemId,
    required String insumoId,
    required double rendimientoNuevo,
    double? precioNuevo,
  }) async {
    final data = await _client.rpc('personalizar_item_apu', params: {
      'p_obra_id': obraId,
      'p_subitem_id': subitemId,
      'p_insumo_id': insumoId,
      'p_rendimiento_nuevo': rendimientoNuevo,
      'p_precio_nuevo': precioNuevo,
    });
    return [for (final row in data as List) _itemDetalleDesdeFila(row as Map<String, dynamic>)];
  }

  /// Agrega un material nuevo a la receta personal del usuario (clona primero si hace falta, ver
  /// `agregar_material_apu`, 0072_edicion_apu_correcciones.sql). El catálogo oficial no se toca.
  ///
  /// Gate de PRO: NO se chequea acá, mismo criterio que `personalizarItem`.
  Future<List<ApuComposicionItemDetalle>> agregarMaterial({
    required String obraId,
    required String subitemId,
    required String insumoId,
    required double rendimiento,
  }) async {
    final data = await _client.rpc('agregar_material_apu', params: {
      'p_obra_id': obraId,
      'p_subitem_id': subitemId,
      'p_insumo_id': insumoId,
      'p_rendimiento': rendimiento,
    });
    return [for (final row in data as List) _itemDetalleDesdeFila(row as Map<String, dynamic>)];
  }

  /// Quita un material de la receta personal del usuario (clona primero si hace falta, ver
  /// `quitar_material_apu`, 0072_edicion_apu_correcciones.sql). El catálogo oficial no se toca.
  ///
  /// Gate de PRO: NO se chequea acá, mismo criterio que `personalizarItem`.
  Future<List<ApuComposicionItemDetalle>> quitarMaterial({
    required String obraId,
    required String subitemId,
    required String insumoId,
  }) async {
    final data = await _client.rpc('quitar_material_apu', params: {
      'p_obra_id': obraId,
      'p_subitem_id': subitemId,
      'p_insumo_id': insumoId,
    });
    return [for (final row in data as List) _itemDetalleDesdeFila(row as Map<String, dynamic>)];
  }

  /// Agrega un equipo nuevo a la receta personal del usuario -- mismo mecanismo que
  /// `agregarMaterial`, funciones de base separadas (`agregar_equipo_apu`,
  /// `0074_catalogo_colaborativo_equipos.sql`) para no cambiarle la firma a las que ya estaban en
  /// producción. `precioInicial` es para el formulario de alta directa (`PanelCrearEquipoApu`,
  /// catálogo de equipos vacío) que pide rendimiento y precio en un solo paso -- va a
  /// `obra_insumo_precios` en la misma llamada, mismo criterio que `personalizarItem`. Al agregar
  /// un equipo que ya existía en el catálogo (buscador, no formulario de alta) queda `null` -- el
  /// precio se carga después igual que el de un material, tocando el precio unitario de la línea.
  ///
  /// Gate de PRO: NO se chequea acá, mismo criterio que `personalizarItem`.
  Future<List<ApuComposicionItemDetalle>> agregarEquipo({
    required String obraId,
    required String subitemId,
    required String insumoId,
    required double rendimiento,
    double? precioInicial,
  }) async {
    final data = await _client.rpc('agregar_equipo_apu', params: {
      'p_obra_id': obraId,
      'p_subitem_id': subitemId,
      'p_insumo_id': insumoId,
      'p_rendimiento': rendimiento,
      'p_precio_inicial': precioInicial,
    });
    return [for (final row in data as List) _itemDetalleDesdeFila(row as Map<String, dynamic>)];
  }

  /// Quita un equipo de la receta personal del usuario (ver `quitar_equipo_apu`,
  /// `0073_agregar_quitar_equipo_apu.sql`). El catálogo oficial no se toca.
  ///
  /// Gate de PRO: NO se chequea acá, mismo criterio que `personalizarItem`.
  Future<List<ApuComposicionItemDetalle>> quitarEquipo({
    required String obraId,
    required String subitemId,
    required String insumoId,
  }) async {
    final data = await _client.rpc('quitar_equipo_apu', params: {
      'p_obra_id': obraId,
      'p_subitem_id': subitemId,
      'p_insumo_id': insumoId,
    });
    return [for (final row in data as List) _itemDetalleDesdeFila(row as Map<String, dynamic>)];
  }

  /// Borra la receta personal del usuario para este subítem (ver `restaurar_receta_oficial_apu`) —
  /// vuelve a mostrar la oficial. `true` si había algo para borrar, `false` si no tenía ninguna
  /// personalización todavía. El aviso de "vas a perder tu personalización" es responsabilidad de
  /// quien llama, esta función no confirma nada por su cuenta.
  Future<bool> restaurarRecetaOficial(String subitemId) async {
    final resultado = await _client.rpc('restaurar_receta_oficial_apu', params: {
      'p_subitem_id': subitemId,
    });
    return resultado as bool;
  }

  /// Mapeo fila->modelo compartido por las 4 RPC de arriba -- todas devuelven exactamente la misma
  /// forma (las 3 de escritura literalmente llaman a `calcular_composicion_detalle_subitem` al
  /// final). `item_id` puede venir null (fila virtual de mano de obra, ver 0072).
  ApuComposicionItemDetalle _itemDetalleDesdeFila(Map<String, dynamic> row) {
    return ApuComposicionItemDetalle(
      itemId: row['item_id']?.toString(),
      apuComposicionId: row['apu_composicion_id'].toString(),
      esPersonal: row['es_personal'] as bool,
      tipoComponente: row['tipo_componente'] as String,
      insumoId: row['insumo_id'].toString(),
      insumoNombre: row['insumo_nombre'] as String,
      insumoUnidad: row['insumo_unidad'] as String,
      rendimiento: (row['rendimiento'] as num).toDouble(),
      precioUnitario: (row['precio_unitario'] as num?)?.toDouble(),
    );
  }
}
