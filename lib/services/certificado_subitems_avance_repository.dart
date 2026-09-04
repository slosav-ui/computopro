import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/certificado_subitem_avance.dart';

/// Acceso a `certificado_subitems_avance` + las funciones de la
/// supabase/migrations/0052_certificado_subitems_avance.sql (monto por subítem, acumulado,
/// agregación ponderada). Ver esa migración para el diseño completo.
class CertificadoSubitemsAvanceRepository {
  final SupabaseClient _client = Supabase.instance.client;

  /// El avance ya cargado en ESTE certificado (para prellenar los campos al reabrir un borrador
  /// en curso). Nunca el histórico completo de un subítem — para eso, `getHistorialPorSubitem`.
  Future<List<CertificadoSubitemAvance>> getAvancesDeCertificado(String certificadoId) async {
    final data = await _client
        .from('certificado_subitems_avance')
        .select()
        .eq('certificado_id', certificadoId);
    return (data as List)
        .map((row) => _fromRow(row as Map<String, dynamic>))
        .toList();
  }

  /// Guarda (o corrige, mientras el certificado siga en borrador) el % de este período para un
  /// subítem — upsert sobre el `unique(certificado_id, obra_subitem_id)` de la 0052.
  /// `monto_periodo` no se manda: lo calcula y lo pisa el trigger de la tabla, server-side.
  Future<CertificadoSubitemAvance> guardarAvance({
    required String certificadoId,
    required String obraSubitemId,
    required double porcentajePeriodo,
    required String usuarioId,
  }) async {
    final updated = await _client
        .from('certificado_subitems_avance')
        .upsert(
          {
            'certificado_id': certificadoId,
            'obra_subitem_id': obraSubitemId,
            'porcentaje_periodo': porcentajePeriodo,
            'creado_por': usuarioId,
          },
          onConflict: 'certificado_id,obra_subitem_id',
        )
        .select()
        .single();
    return _fromRow(updated);
  }

  /// Historial completo de un subítem, certificado por certificado — no solo el acumulado.
  /// Dos consultas, no un select con recurso embebido: mismo patrón que el resto del proyecto
  /// (ObraSubitemsRepository.getNombresObrasConUso), nada acá usa la sintaxis de join embebido de
  /// PostgREST todavía.
  Future<List<AvanceHistorialItem>> getHistorialPorSubitem(String obraSubitemId) async {
    final avances = await _client
        .from('certificado_subitems_avance')
        .select('certificado_id, porcentaje_periodo, monto_periodo')
        .eq('obra_subitem_id', obraSubitemId);
    final filas = avances as List;
    if (filas.isEmpty) return [];

    final certificadoIds = filas.map((f) => (f as Map<String, dynamic>)['certificado_id'].toString()).toSet();
    final certificadosData = await _client
        .from('certificados')
        .select('id, numero, estado')
        .inFilter('id', certificadoIds.toList());
    final certificadosPorId = <String, Map<String, dynamic>>{
      for (final c in certificadosData as List)
        (c as Map<String, dynamic>)['id'].toString(): c,
    };

    final items = filas.map((f) {
      final fila = f as Map<String, dynamic>;
      final cert = certificadosPorId[fila['certificado_id'].toString()];
      return AvanceHistorialItem(
        numeroCertificado: (cert?['numero'] as num?)?.toInt() ?? 0,
        estadoCertificado: cert?['estado']?.toString() ?? '',
        porcentajePeriodo: (fila['porcentaje_periodo'] as num).toDouble(),
        montoPeriodo: (fila['monto_periodo'] as num).toDouble(),
      );
    }).toList();
    items.sort((a, b) => a.numeroCertificado.compareTo(b.numeroCertificado));
    return items;
  }

  /// Monto real de cada subítem tildado de la obra, las 3 ramas de precio ya resueltas del lado
  /// del servidor — RPC a `calcular_monto_obra_subitems` (0052).
  Future<Map<String, MontoObraSubitem>> getMontoObraSubitems(String obraId) async {
    final data = await _client.rpc('calcular_monto_obra_subitems', params: {'p_obra_id': obraId});
    final mapa = <String, MontoObraSubitem>{};
    for (final row in data as List) {
      final fila = row as Map<String, dynamic>;
      final id = fila['obra_subitem_id'].toString();
      mapa[id] = MontoObraSubitem(
        obraSubitemId: id,
        montoTotal: (fila['monto_total'] as num?)?.toDouble() ?? 0,
        tienePrecioCompleto: fila['tiene_precio_completo'] == true,
      );
    }
    return mapa;
  }

  /// Acumulado real de un subítem — solo certificados que ya dejaron de ser borrador (0052:
  /// "es un certificado por vez", el propio borrador en curso queda afuera solo por el filtro de
  /// estado, sin necesitar exclusión explícita). RPC escalar: `calcular_avance_acumulado_subitem`.
  Future<double> getAcumuladoSubitem(String obraSubitemId) async {
    final data = await _client.rpc(
      'calcular_avance_acumulado_subitem',
      params: {'p_obra_subitem_id': obraSubitemId},
    );
    return (data as num?)?.toDouble() ?? 0;
  }

  /// Avance ponderado por rubro — RPC a `calcular_avance_ponderado_rubros` (0052).
  Future<List<AvancePonderadoRubro>> getAvancePonderadoRubros(String obraId) async {
    final data = await _client.rpc('calcular_avance_ponderado_rubros', params: {'p_obra_id': obraId});
    return (data as List).map((row) {
      final fila = row as Map<String, dynamic>;
      return AvancePonderadoRubro(
        rubroId: fila['rubro_id'].toString(),
        avancePct: (fila['avance_pct'] as num?)?.toDouble(),
        montoPonderado: (fila['monto_ponderado'] as num?)?.toDouble() ?? 0,
      );
    }).toList();
  }

  /// Avance ponderado de la obra completa — RPC escalar a `calcular_avance_ponderado_obra`.
  Future<double?> getAvancePonderadoObra(String obraId) async {
    final data = await _client.rpc('calcular_avance_ponderado_obra', params: {'p_obra_id': obraId});
    return (data as num?)?.toDouble();
  }

  /// "Certificado y pagado a la fecha" — para el resumen chico de la pantalla de carga. Suma
  /// simple sobre `certificados`, no hace falta ninguna función SQL nueva para esto.
  Future<ResumenCertificadoObra> getResumen(String obraId) async {
    final data = await _client
        .from('certificados')
        .select('estado, monto, monto_neto_a_pagar')
        .eq('obra_id', obraId)
        .neq('estado', 'borrador');
    double totalCertificado = 0;
    double totalPagado = 0;
    for (final row in data as List) {
      final fila = row as Map<String, dynamic>;
      totalCertificado += (fila['monto'] as num?)?.toDouble() ?? 0;
      final estado = fila['estado']?.toString();
      if (estado == 'pagado' || estado == 'impactado_cerrado') {
        totalPagado += (fila['monto_neto_a_pagar'] as num?)?.toDouble() ?? 0;
      }
    }
    return ResumenCertificadoObra(totalCertificado: totalCertificado, totalPagado: totalPagado);
  }

  /// El desglose completo de un certificado (subtotal, anticipo, fondo de reparo, neto) — RPC a
  /// `calcular_totales_certificado` (0054). Misma función que `emitir_certificado` usa para
  /// congelar, llamada acá de solo lectura para la vista previa — nunca recalculada en Dart.
  Future<TotalesCertificado> getTotalesCertificado(String certificadoId) async {
    final data = await _client.rpc(
      'calcular_totales_certificado',
      params: {'p_certificado_id': certificadoId},
    );
    final fila = (data as List).first as Map<String, dynamic>;
    return TotalesCertificado(
      monto: (fila['monto'] as num?)?.toDouble() ?? 0,
      anticipoPct: (fila['anticipo_pct'] as num?)?.toDouble(),
      fondoReparoPct: (fila['fondo_reparo_pct'] as num?)?.toDouble(),
      montoAnticipo: (fila['monto_anticipo'] as num?)?.toDouble() ?? 0,
      montoFondoReparo: (fila['monto_fondo_reparo'] as num?)?.toDouble() ?? 0,
      montoNeto: (fila['monto_neto'] as num?)?.toDouble() ?? 0,
      diasPlazoPago: (fila['dias_plazo_pago'] as num?)?.toInt(),
    );
  }

  /// Subítems de este borrador que exceden el 100% acumulado — RPC a
  /// `calcular_excesos_certificado` (0054). Lista vacía si no hay ningún exceso: la vista previa
  /// habilita "Emitir" solo cuando esto vuelve vacío.
  Future<List<ExcesoCertificado>> getExcesosCertificado(String certificadoId) async {
    final data = await _client.rpc(
      'calcular_excesos_certificado',
      params: {'p_certificado_id': certificadoId},
    );
    return (data as List).map((row) {
      final fila = row as Map<String, dynamic>;
      return ExcesoCertificado(
        obraSubitemId: fila['obra_subitem_id'].toString(),
        descripcion: fila['descripcion']?.toString() ?? '',
        acumuladoPrevio: (fila['acumulado_previo'] as num?)?.toDouble() ?? 0,
        disponible: (fila['disponible'] as num?)?.toDouble() ?? 0,
        intentado: (fila['intentado'] as num?)?.toDouble() ?? 0,
      );
    }).toList();
  }

  /// Borrador -> Emitido — RPC a `emitir_certificado`. `requiereFirmaFisica` se pregunta recién acá,
  /// al emitir, nunca antes (es una decisión por certificado, no de la obra).
  Future<void> emitirCertificado({
    required String certificadoId,
    required bool requiereFirmaFisica,
  }) async {
    await _client.rpc(
      'emitir_certificado',
      params: {
        'p_certificado_id': certificadoId,
        'p_requiere_firma_fisica': requiereFirmaFisica,
      },
    );
  }

  CertificadoSubitemAvance _fromRow(Map<String, dynamic> row) {
    return CertificadoSubitemAvance(
      id: row['id'].toString(),
      certificadoId: row['certificado_id'].toString(),
      obraSubitemId: row['obra_subitem_id'].toString(),
      porcentajePeriodo: (row['porcentaje_periodo'] as num).toDouble(),
      montoPeriodo: (row['monto_periodo'] as num).toDouble(),
      creadoPor: row['creado_por'].toString(),
      createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(row['updated_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}
