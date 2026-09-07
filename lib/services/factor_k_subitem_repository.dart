import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/factor_k_linea_subitem.dart';

/// Acceso a `calcular_factor_k_subitem` (ver `supabase/migrations/0077_calcular_factor_k_subitem.sql`,
/// redondeo en `0078`) -- el Factor K de una partida puntual, cascada completa de 6 conceptos +
/// impuestos, con las dos vistas (con/sin materiales) juntas. Archivo propio, no una extensión de
/// `ApuComposicionesRepository` -- el Factor K es su propia pieza (Paso B, ver
/// `docs/factor_k_apu_decisiones.md`), con su propia función de base, aunque las dos lean la misma
/// composición de la partida.
class FactorKSubitemRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<PrecioFinalSubitem> getPrecioFinal(String obraId, String subitemId) async {
    final data = await _client.rpc('calcular_factor_k_subitem', params: {
      'p_obra_id': obraId,
      'p_subitem_id': subitemId,
    });
    final filas = (data as List).cast<Map<String, dynamic>>();

    // Sin filas = sin fila de obra_presupuesto_config para esta obra (no debería pasar en uso
    // normal, la pantalla ya verificó acceso antes de llegar acá) -- mismo fail-closed silencioso
    // que ya usa calcular_valor_hora_mano_obra para el mismo caso, pero acá no hay ningún número
    // razonable que mostrar ni siquiera vacío, así que se corta con una excepción en vez de devolver
    // un objeto con todo en cero que se vería como un cálculo real.
    if (filas.isEmpty) {
      throw StateError('No se pudo calcular el Factor K de esta partida.');
    }

    final conMateriales = filas.where((f) => f['vista'] == 'con_materiales').toList()
      ..sort((a, b) => (a['orden'] as int).compareTo(b['orden'] as int));
    final sinMateriales = filas.where((f) => f['vista'] == 'sin_materiales').toList()
      ..sort((a, b) => (a['orden'] as int).compareTo(b['orden'] as int));

    final primeraCm = conMateriales.first;
    final primeraSm = sinMateriales.first;
    // insumos_con_precio/insumos_total no dependen de la vista -- se leen de cualquier fila.
    final primera = filas.first;

    return PrecioFinalSubitem(
      lineasConMateriales: conMateriales.map(_lineaDesdeFila).toList(),
      costoCostoConMateriales: (primeraCm['costo_costo'] as num).toDouble(),
      costoTotalTrabajoConMateriales: (primeraCm['costo_total_trabajo'] as num).toDouble(),
      precioFinalConMateriales: (primeraCm['precio_final'] as num).toDouble(),
      cierraOkConMateriales: primeraCm['cierra_ok'] as bool,
      lineasSinMateriales: sinMateriales.map(_lineaDesdeFila).toList(),
      costoCostoSinMateriales: (primeraSm['costo_costo'] as num).toDouble(),
      costoTotalTrabajoSinMateriales: (primeraSm['costo_total_trabajo'] as num).toDouble(),
      precioFinalSinMateriales: (primeraSm['precio_final'] as num).toDouble(),
      cierraOkSinMateriales: primeraSm['cierra_ok'] as bool,
      insumosConPrecio: primera['insumos_con_precio'] as int,
      insumosTotal: primera['insumos_total'] as int,
    );
  }

  FactorKLineaSubitem _lineaDesdeFila(Map<String, dynamic> f) {
    return FactorKLineaSubitem(
      orden: f['orden'] as int,
      concepto: f['concepto'] as String,
      pct: (f['pct'] as num).toDouble(),
      baseTexto: f['base_texto'] as String,
      baseMonto: (f['base_monto'] as num).toDouble(),
      monto: (f['monto'] as num).toDouble(),
    );
  }
}
