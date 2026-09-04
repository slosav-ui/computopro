import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/obra_config_certificacion.dart';

/// Acceso a las columnas de certificación de `obras` (`modelo_certificacion`,
/// `dias_plazo_pago_certificados`, `anticipo_pct`, `fondo_reparo_pct`,
/// `monto_total_contratado`) — ver docs/modelos_certificacion_diseno_datos.md y
/// docs/certificados_ciclo_vida_diseno_datos.md. Repositorio propio, no `ObrasRepository`
/// (Map-based, pensado para `ObrasListScreen`, no para esta pieza) — mismo criterio que
/// `ObraPresupuestoConfigRepository` para otra tabla.
///
/// El gate de quién puede escribir es de UI (`UserContext.puedeEditarConfigCertificacion`,
/// `admin_maestro`) — la base sigue aplicando la RLS de `obras` ya existente
/// (`id_admin_creador = auth.uid()`, dueño único, anterior a Etapa 3), no una verificación de rol
/// vía `obra_members`. Los dos coinciden en la práctica hoy (`0033_obra_members_bootstrap.sql`
/// sincroniza al creador como `admin_maestro` al crear la obra, cero divergencias medidas en
/// producción), pero no son el mismo mecanismo: si alguna vez se agrega un segundo
/// `admin_maestro` a una obra sin que también sea el `id_admin_creador`, ese usuario va a ver el
/// botón "Editar" (pasa el gate de rol) pero el `update` de acá le va a devolver 0 filas y
/// `.single()` va a lanzar (no pasa la RLS real). Gap conocido, heredado de
/// `cambiar_modelo_certificacion` — no se resuelve en esta pieza.
class ObraConfigCertificacionRepository {
  final SupabaseClient _client = Supabase.instance.client;

  static const _columnas = 'id, modelo_certificacion, dias_plazo_pago_certificados, '
      'anticipo_pct, fondo_reparo_pct, monto_total_contratado';

  Future<ObraConfigCertificacion> getConfig(String obraId) async {
    final row = await _client.from('obras').select(_columnas).eq('id', obraId).single();
    return _fromRow(row);
  }

  /// Los 4 campos simples juntos, un solo Guardar — mismo criterio que
  /// `ObraPresupuestoConfigRepository.actualizarCargasSociales`: se validan juntos en el panel
  /// antes de llegar acá, separarlo en 4 llamadas no gana nada. `monto_total_contratado` NO se
  /// toca acá, tiene su propia regla — ver `actualizarMontoTotalContratadoInicial`.
  Future<ObraConfigCertificacion> actualizarConfig({
    required String obraId,
    required ModeloCertificacion modeloCertificacion,
    required int diasPlazoPagoCertificados,
    required double anticipoPct,
    required double fondoReparoPct,
  }) async {
    final updated = await _client
        .from('obras')
        .update({
          'modelo_certificacion': _columnaDesdeModelo(modeloCertificacion),
          'dias_plazo_pago_certificados': diasPlazoPagoCertificados,
          'anticipo_pct': anticipoPct,
          'fondo_reparo_pct': fondoReparoPct,
        })
        .eq('id', obraId)
        .select(_columnas)
        .single();
    return _fromRow(updated);
  }

  /// Carga inicial de `monto_total_contratado` (Modelo B) — definición cerrada,
  /// docs/modelos_certificacion_diseno_datos.md §7.7-bis: editable directo SOLO mientras el valor
  /// todavía es `null`. Cualquier cambio posterior a un valor ya cargado tiene que pasar por
  /// `modificaciones_obra` con aprobación (tipo `'ajuste_contrato'`, función
  /// `aprobar_ajuste_contrato`) — sin UI todavía, fuera de esta pieza.
  ///
  /// La guarda `is('monto_total_contratado', null)` va en la propia consulta, no solo en la UI:
  /// un `update` que no matchea ninguna fila (porque el valor ya no es `null`) no lanza excepción
  /// con PostgREST, simplemente no devuelve fila — por eso se usa `maybeSingle()` y se verifica el
  /// resultado, en vez de asumir que el `update` funcionó porque no tiró error.
  Future<ObraConfigCertificacion> actualizarMontoTotalContratadoInicial({
    required String obraId,
    required double montoTotalContratado,
  }) async {
    final updated = await _client
        .from('obras')
        .update({'monto_total_contratado': montoTotalContratado})
        .eq('id', obraId)
        .isFilter('monto_total_contratado', null)
        .select(_columnas)
        .maybeSingle();
    if (updated == null) {
      throw StateError(
        'El monto total contratado ya tiene un valor cargado — cambiarlo requiere el circuito de '
        'aprobación de Modificaciones de Obra, todavía sin pantalla propia.',
      );
    }
    return _fromRow(updated);
  }

  ObraConfigCertificacion _fromRow(Map<String, dynamic> row) {
    return ObraConfigCertificacion(
      obraId: row['id'].toString(),
      modeloCertificacion: _modeloDesdeColumna(row['modelo_certificacion']?.toString()),
      diasPlazoPagoCertificados: (row['dias_plazo_pago_certificados'] as num?)?.toInt(),
      anticipoPct: (row['anticipo_pct'] as num?)?.toDouble(),
      fondoReparoPct: (row['fondo_reparo_pct'] as num?)?.toDouble(),
      montoTotalContratado: (row['monto_total_contratado'] as num?)?.toDouble(),
    );
  }

  String _columnaDesdeModelo(ModeloCertificacion modelo) {
    switch (modelo) {
      case ModeloCertificacion.avanceMedido:
        return 'avance_medido';
      case ModeloCertificacion.hitosPrecioCerrado:
        return 'hitos_precio_cerrado';
    }
  }

  ModeloCertificacion _modeloDesdeColumna(String? valor) {
    switch (valor) {
      case 'hitos_precio_cerrado':
        return ModeloCertificacion.hitosPrecioCerrado;
      case 'avance_medido':
      default:
        // Fallback más conservador ante un valor corrupto o desconocido: el default real de la
        // columna (0005_modelo_certificacion.sql).
        return ModeloCertificacion.avanceMedido;
    }
  }
}
