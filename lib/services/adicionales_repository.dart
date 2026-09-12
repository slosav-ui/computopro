import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/modificacion_obra.dart';

/// Acceso al circuito de Adicionales de `modificaciones_obra` (Tanda 1,
/// docs/adicionales_quitas_demasias_diagnostico.md §11) -- repositorio propio, no una extensión de
/// `ModificacionesObraRepository` (que su propio comentario de cabecera ya deja acotado a
/// demasia/quita): la autoridad de aprobación (cliente_principal/apoderado, Tanda 2) y el shape de
/// datos (costo manual + cascada, sin `obra_subitem_id`) son suficientemente distintos como para
/// no compartir métodos.
///
/// Creación, listado y, desde la Tanda 2 (0116), enviar/aprobar/rechazar -- todas las transiciones
/// por RPC: la 0116 cerró cualquier `UPDATE` directo sobre una fila de adicional. Certificar avance
/// sigue pendiente (Tanda 2, después).
class AdicionalesRepository {
  final SupabaseClient _client = Supabase.instance.client;

  /// Mismo criterio que `InvitacionesRepository._conLog`: el error real (code/message/details/hint
  /// de Postgres, o la excepción cruda) va a la consola antes de relanzarlo -- la pantalla que llama
  /// sigue decidiendo qué mensaje ve el usuario.
  Future<T> _conLog<T>(String etiqueta, Future<T> Function() accion) async {
    try {
      return await accion();
    } on PostgrestException catch (e) {
      debugPrint(
        'AdicionalesRepository.$etiqueta falló (Postgrest) -- code=${e.code} message=${e.message} '
        'details=${e.details} hint=${e.hint}',
      );
      rethrow;
    } catch (e, st) {
      debugPrint('AdicionalesRepository.$etiqueta falló: $e\n$st');
      rethrow;
    }
  }

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
  }) {
    return _conLog('crearAdicionalPresupuestado', () async {
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
    });
  }

  /// El adicional que corresponde a una obra hija -- para el aviso de `PresupuestosScreen` cuando se
  /// abre la hija (enviado/aprobado/rechazado). `null` si no hay (o si la RLS no lo deja ver: la
  /// fila vive en la madre, `is_obra_member(madre)`), sin error -- el aviso es informativo.
  Future<ModificacionObra?> getAdicionalDeObraHija(String obraHijaId) async {
    final row = await _client
        .from('modificaciones_obra')
        .select()
        .eq('obra_hija_id', obraHijaId)
        .maybeSingle();
    return row == null ? null : ModificacionObra.fromRow(row);
  }

  /// Quien cotiza congela la obra hija y la manda a aprobar (0116, `enviar_adicional_a_aprobacion`
  /// -- docs/adicionales_quitas_demasias_diagnostico.md §13.6-A). Sirve igual para reenviar mientras
  /// siga pendiente. Devuelve el monto enviado (la suma congelada).
  Future<double> enviarAAprobacion(String modificacionId) {
    return _conLog('enviarAAprobacion', () async {
      final monto = await _client.rpc('enviar_adicional_a_aprobacion', params: {
        'p_modificacion_id': modificacionId,
      });
      return _aDouble(monto);
    });
  }

  /// `montoVisto`: el `montoTotal` crudo (en pesos, sin redondear ni convertir) de la fila que el
  /// aprobador tenía en pantalla -- `aprobar_adicional` rechaza si no coincide con el monto real que
  /// va a quedar (reenvío o cambio de config en el medio), y recién con ese monto valida el tope.
  /// Devuelve el monto aprobado.
  Future<double> aprobarAdicional({
    required String modificacionId,
    required double montoVisto,
    String? comentario,
  }) {
    return _conLog('aprobarAdicional', () async {
      final monto = await _client.rpc('aprobar_adicional', params: {
        'p_modificacion_id': modificacionId,
        'p_monto_visto': montoVisto,
        'p_comentario': comentario,
      });
      return _aDouble(monto);
    });
  }

  Future<void> rechazarAdicional({required String modificacionId, String? comentario}) {
    return _conLog('rechazarAdicional', () async {
      await _client.rpc('rechazar_adicional', params: {
        'p_modificacion_id': modificacionId,
        'p_comentario': comentario,
      });
    });
  }

  // `numeric` de Postgres puede llegar como número o como texto según su tamaño -- mismo resguardo
  // en los dos casos, nunca un cast directo.
  double _aDouble(dynamic valor) =>
      valor is num ? valor.toDouble() : double.tryParse(valor?.toString() ?? '') ?? 0.0;

  // Sin "corregir mientras pendiente" a propósito: desde la 0116 ninguna escritura directa sobre una
  // fila de adicional pasa la RLS, ni siquiera para quien la subió. Para el camino obra hija, corregir
  // es editar el cómputo de la hija y reenviar; para el monto fijo, rechazar y volver a cargarlo.
}
