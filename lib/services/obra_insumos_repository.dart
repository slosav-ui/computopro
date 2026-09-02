import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/insumo_consolidado_obra.dart';

/// Acceso a `obra_insumo_precios` (precio editado/en firme por obra, ver
/// `supabase/migrations/0030_obra_insumo_precios.sql`) y al consolidado real de insumos de una
/// obra (`consolidado_insumos_obra`, `0032_consolidado_lee_precio_manual.sql`).
class ObraInsumosRepository {
  final SupabaseClient _client = Supabase.instance.client;

  /// Insumos reales que consume la obra según sus composiciones de APU tildadas, con el precio
  /// efectivo (carga manual si existe, si no el promedio automático de corralones — ver 0032) y
  /// su `origen`.
  Future<List<InsumoConsolidadoObra>> getConsolidado(String obraId) async {
    final data = await _client.rpc('consolidado_insumos_obra', params: {'p_obra_id': obraId});
    return (data as List)
        .map((row) => InsumoConsolidadoObra.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Paso 3 de Mat y MO: guarda (o actualiza) el precio cargado a mano para un insumo de esta
  /// obra, en la unidad que pide la APU. Origen siempre 'manual' acá.
  ///
  /// Sin guard de precedencia contra origen='presupuesto_firme' (ver comentario de 0030): ese
  /// origen no puede existir todavía en ninguna fila porque el paso 4 (presupuesto en firme) no
  /// está construido, así que esa validación queda pendiente para cuando exista algo real que
  /// probar contra ella.
  Future<void> guardarPrecioManual({
    required String obraId,
    required String insumoId,
    required double precio,
    required String usuarioId,
  }) async {
    // updated_at lo mantiene un trigger de la base (0035_updated_at_trigger.sql),
    // no se manda desde acá.
    await _client.from('obra_insumo_precios').upsert(
      {
        'obra_id': obraId,
        'insumo_id': insumoId,
        'precio': precio,
        'origen': 'manual',
        'usuario_id': usuarioId,
      },
      onConflict: 'obra_id,insumo_id',
    );
  }

  /// Bifurcación del lapicito para mano de obra (ver docs/costo_mano_de_obra_decisiones.md §13):
  /// guarda el valor hora fijado a mano para una categoría UOCRA completa, en
  /// obra_valor_hora_override (0036) — no en obra_insumo_precios. El override es por categoría, no
  /// por insumo suelto, para que AYUDANTE/AYUDA DE GREMIO (misma categoría) no queden con valores
  /// distintos. updated_at lo mantiene el trigger de la base (0036), no se manda desde acá.
  Future<void> guardarValorHoraOverride({
    required String obraId,
    required String categoriaUocra,
    required double valorHora,
    required String usuarioId,
  }) async {
    await _client.from('obra_valor_hora_override').upsert(
      {
        'obra_id': obraId,
        'categoria_uocra': categoriaUocra,
        'valor_hora': valorHora,
        'usuario_id': usuarioId,
      },
      onConflict: 'obra_id,categoria_uocra',
    );
  }
}
