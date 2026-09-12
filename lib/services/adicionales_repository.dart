import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/modificacion_obra.dart';

/// Acceso al circuito de Adicionales de `modificaciones_obra` (Tanda 1,
/// docs/adicionales_quitas_demasias_diagnostico.md §11) -- repositorio propio, no una extensión de
/// `ModificacionesObraRepository` (que su propio comentario de cabecera ya deja acotado a
/// demasia/quita): la autoridad de aprobación (cliente_principal/apoderado, Tanda 2) y el shape de
/// datos (costo manual + cascada, sin `obra_subitem_id`) son suficientemente distintos como para
/// no compartir métodos.
///
/// Solo creación y listado en esta tanda -- aprobar/rechazar/certificar avance son Tanda 2, una vez
/// aplicada y verificada la `0112`.
class AdicionalesRepository {
  final SupabaseClient _client = Supabase.instance.client;

  /// Todos los adicionales de una obra (cualquier estado), más recientes primero -- mismo criterio
  /// que `getQuitasDemasiasDeObra`.
  Future<List<ModificacionObra>> getAdicionalesDeObra(String obraId) async {
    final data = await _client
        .from('modificaciones_obra')
        .select()
        .eq('obra_id', obraId)
        .eq('tipo', 'adicional')
        .order('fecha_solicitud', ascending: false);
    return (data as List)
        .map((row) => ModificacionObra.fromRow(row as Map<String, dynamic>))
        .toList();
  }

  /// Vista previa del monto -- misma cuenta que el trigger de la base
  /// (`calcular_monto_total_adicional`, 0112) va a aplicar al guardar, para que quien está
  /// cargando el adicional vea el resultado ANTES de confirmar, no recién después de crearlo.
  /// `null` (obra sin membresía, o la RPC falla) se resuelve a 0 -- valor informativo, no bloquea
  /// nada si no se puede calcular.
  Future<double> previsualizarPrecioAdicional({
    required String obraId,
    required double costoCostoBase,
    required bool incluyeImpuestos,
  }) async {
    final data = await _client.rpc('calcular_precio_adicional', params: {
      'p_obra_id': obraId,
      'p_costo_costo_base': costoCostoBase,
      'p_incluye_impuestos': incluyeImpuestos,
    });
    return (data as num?)?.toDouble() ?? 0.0;
  }

  /// Registra un adicional como `pendiente` -- RLS (`modificaciones_obra_insert`, 0004) exige
  /// `solicitado_por = subido_por = auth.uid()`, sin restricción de rol (ambigüedad E, cerrada por
  /// Seba: "que lo pueda crear cualquier miembro está bien, la barrera real es la aprobación").
  /// `cantidad` fija en 1 (0112: un adicional es un monto de una sola vez, no cantidad × precio
  /// unitario) y `monto_total` no se manda -- lo calcula el trigger antes de guardar, mismo
  /// criterio que `guardarAvance` con `monto_periodo`.
  Future<ModificacionObra> crearAdicional({
    required String obraId,
    required String descripcion,
    required double costoCostoBase,
    required bool incluyeMateriales,
    required bool incluyeImpuestos,
    required String usuarioId,
  }) async {
    final inserted = await _client
        .from('modificaciones_obra')
        .insert({
          'obra_id': obraId,
          'tipo': 'adicional',
          'descripcion': descripcion,
          'cantidad': 1,
          'costo_costo_base': costoCostoBase,
          'incluye_materiales': incluyeMateriales,
          'incluye_impuestos': incluyeImpuestos,
          'solicitado_por': usuarioId,
          'subido_por': usuarioId,
        })
        .select()
        .single();
    return ModificacionObra.fromRow(inserted);
  }

  /// Segunda vía de carga: "presupuestar con la app" (0113, "obra dentro de obra" -- docs/
  /// adicionales_quitas_demasias_diagnostico.md §12). RPC a `crear_adicional_presupuestado`, que en
  /// una sola transacción crea la obra hija, le copia el Factor K/impuestos vigentes de la madre
  /// (no el default genérico de una obra nueva) y el equipo activo (foto, no en vivo), y crea el
  /// adicional ya vinculado (`obra_hija_id`, `costo_costo_base` queda null -- mutuamente
  /// excluyentes). Sin autoridad de rol -- mismo criterio que `crearAdicional`, cualquier miembro
  /// puede presupuestar uno.
  ///
  /// Devuelve el `ModificacionObra` completo (un segundo viaje, `getPorId`) en vez de solo el id
  /// que da la RPC -- quien llama necesita `obraHijaId` para poder navegar directo a las solapas de
  /// la obra recién creada.
  Future<ModificacionObra> crearAdicionalPresupuestado({
    required String obraId,
    required String descripcion,
  }) async {
    final modificacionId = await _client.rpc('crear_adicional_presupuestado', params: {
      'p_obra_id': obraId,
      'p_descripcion': descripcion,
    }) as String;
    final row = await _client
        .from('modificaciones_obra')
        .select()
        .eq('id', modificacionId)
        .single();
    return ModificacionObra.fromRow(row);
  }

  // Sin "corregir mientras pendiente" a propósito -- verificado contra `modificaciones_obra_update`
  // (0109): esa política solo deja tocar una fila `pendiente` a quien puede aprobarla
  // (`puede_aprobar_monto` para todo lo que no es demasia/quita), no a `subido_por` en general --
  // la rama `subido_por = auth.uid()` de esa política solo aplica con `estado = 'devuelto'`. Quien
  // creó un adicional pendiente no puede autoeditarlo hoy, mismo límite que ya tiene Quitas/
  // Demasías (sin edición, solo aprobar/rechazar). Si hace falta poder corregir un pendiente antes
  // de que se resuelva, es un cambio de RLS a proponer en la Tanda 2, no algo que se pueda ofrecer
  // en la UI sin esa base.
}
