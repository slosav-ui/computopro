import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/audit_log_entry.dart';
import '../data/models/modificacion_obra.dart';

/// Acceso a `modificaciones_obra` (circuito de Quitas/Demasías, docs/adicionales_quitas_demasias_
/// diagnostico.md) y a las observaciones que se cuelgan de una modificación puntual en
/// `audit_log`. Primer repositorio de esta tabla — no existía ninguno antes de esta pieza (el
/// modelo `ModificacionObra` tampoco estaba conectado a Supabase, quedó en camelCase pre-Supabase
/// sin un solo caller real).
///
/// Acotado a `demasia`/`quita`: `crear`/`aprobar`/`rechazar` de acá asumen esos dos tipos (mismos
/// que `0109` autoriza vía `puede_aprobar_quita_demasia`). Adicionales, cuando se construyan, son
/// una pieza de autoridad distinta (`cliente_principal`/apoderado, nunca profesional/constructor)
/// y probablemente necesiten sus propios métodos, no una extensión de estos.
class ModificacionesObraRepository {
  final SupabaseClient _client = Supabase.instance.client;

  /// Todas las demasías/quitas de una obra (cualquier estado), más recientes primero — para el
  /// historial completo de `QuitasDemasiasScreen`. `adicional`/`ajuste_contrato` quedan afuera a
  /// propósito, son de otro circuito.
  Future<List<ModificacionObra>> getQuitasDemasiasDeObra(String obraId) async {
    final data = await _client
        .from('modificaciones_obra')
        .select()
        .eq('obra_id', obraId)
        .inFilter('tipo', ['demasia', 'quita'])
        .order('fecha_solicitud', ascending: false);
    return (data as List)
        .map((row) => ModificacionObra.fromRow(row as Map<String, dynamic>))
        .toList();
  }

  /// Registra una demasía/quita como `pendiente` — RLS (`modificaciones_obra_insert`, 0004) exige
  /// `solicitado_por = subido_por = auth.uid()`, así que quien detecta y quien la eleva son la
  /// misma persona en este circuito (misma limitación conocida y aceptada que ya documenta esa
  /// política). `montoTotal` se inserta en 0: sin significado propio para estos dos tipos, ver
  /// comentario en el modelo.
  Future<ModificacionObra> crearQuitaDemasia({
    required String obraId,
    required String obraSubitemId,
    required TipoModificacion tipo,
    required double cantidad,
    required String descripcion,
    required String usuarioId,
  }) async {
    assert(tipo == TipoModificacion.demasia || tipo == TipoModificacion.quita);
    final inserted = await _client
        .from('modificaciones_obra')
        .insert({
          'obra_id': obraId,
          'obra_subitem_id': obraSubitemId,
          'tipo': tipo.columna,
          'cantidad': cantidad,
          'descripcion': descripcion,
          'monto_total': 0,
          'solicitado_por': usuarioId,
          'subido_por': usuarioId,
        })
        .select()
        .single();
    return ModificacionObra.fromRow(inserted);
  }

  /// Aprueba — RPC a `aprobar_quita_demasia` (0109): aplica el delta a `obra_subitems.cantidad`,
  /// corrige `presupuesto_subitems_congelado` si la obra ya está congelada, y deja `audit_log`.
  /// Autoridad real (profesional o constructor) la verifica la función del lado del servidor.
  Future<void> aprobarQuitaDemasia({
    required String modificacionId,
    String? comentario,
  }) async {
    await _client.rpc('aprobar_quita_demasia', params: {
      'p_modificacion_id': modificacionId,
      'p_comentario': comentario,
    });
  }

  /// Rechaza — `update` directo, no RPC: a diferencia de aprobar, rechazar no tiene efecto
  /// colateral que coordinar (no toca `obra_subitems` ni el congelamiento), así que no hace falta
  /// una función dedicada. Pasa por la misma RLS (`modificaciones_obra_update`, rama demasia/quita
  /// de `puede_aprobar_quita_demasia`) que ya rige la aprobación — quien no tiene autoridad recibe
  /// el rechazo de PostgREST, no un éxito silencioso.
  Future<void> rechazarModificacion({
    required String modificacionId,
    required String usuarioId,
    String? motivo,
  }) async {
    await _client.from('modificaciones_obra').update({
      'estado': 'rechazado',
      'aprobado_por': usuarioId,
      'fecha_resolucion': DateTime.now().toUtc().toIso8601String(),
      'comentario_resolucion': motivo,
    }).eq('id', modificacionId);
  }

  /// Observación del propietario (o cualquier miembro) sobre una modificación puntual — `insert`
  /// directo a `audit_log`, sin RPC nueva: la política `audit_log_insert` (0004) ya deja que
  /// cualquier miembro de la obra inserte su propia fila, y al no haber política de UPDATE/DELETE
  /// (append-only) la observación no puede trabar ni cambiar el `estado` de la modificación que
  /// comenta (docs/adicionales_quitas_demasias_diagnostico.md §6).
  Future<void> observar({
    required String obraId,
    required String modificacionId,
    required String usuarioId,
    required String comentario,
  }) async {
    await _client.from('audit_log').insert({
      'obra_id': obraId,
      'usuario_id': usuarioId,
      'accion': 'observar_modificacion',
      'entidad': 'modificacion_obra',
      'entidad_id': modificacionId,
      'detalle': {'comentario': comentario},
    });
  }

  /// Observaciones de una modificación puntual, más antiguas primero (orden de conversación) —
  /// filtra por `accion` además de `entidad`/`entidad_id`: la misma fila de `modificacion_obra`
  /// también acumula la entrada que deja `aprobar_quita_demasia` (`accion='aprobar_quita_demasia'`,
  /// 0109) en el mismo `audit_log`, que no es una observación y no corresponde mostrar acá.
  Future<List<AuditLogEntry>> getObservaciones(String modificacionId) async {
    final data = await _client
        .from('audit_log')
        .select()
        .eq('entidad', 'modificacion_obra')
        .eq('entidad_id', modificacionId)
        .eq('accion', 'observar_modificacion')
        .order('created_at', ascending: true);
    return (data as List)
        .map((row) => AuditLogEntry.fromRow(row as Map<String, dynamic>))
        .toList();
  }
}
