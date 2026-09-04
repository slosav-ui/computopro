import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/certificado.dart';

/// Acceso a la tabla `certificados` de Supabase (ciclo de vida del
/// Certificado, Modelo A).
///
/// Traduce entre las columnas planas y snake_case de la tabla (ver
/// `supabase/migrations/0009_certificados.sql`) y el modelo `Certificado`.
/// Las 5 transiciones de estado (`emitir_certificado`, `marcar_certificado_leido`,
/// `marcar_certificado_pagado`, `marcar_certificado_impactado`,
/// `subir_pdf_firmado_certificado`) siguen sin conectarse desde acá — se hacen vía función RPC,
/// nunca con `update()` directo. `crearCertificadoBorrador` es la única escritura de este
/// repositorio, y es un `insert` simple porque crear el Borrador no tiene efectos secundarios que
/// coordinar (a diferencia de las transiciones, que si).
class CertificadosRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<Certificado>> getCertificadosDeObra(String obraId) async {
    final data = await _client
        .from('certificados')
        .select()
        .eq('obra_id', obraId)
        .order('numero', ascending: true);
    return (data as List)
        .map((row) => _fromRow(row as Map<String, dynamic>))
        .toList();
  }

  /// El Borrador abierto de la obra, si hay uno — `null` si no hay ninguno. `maybeSingle()` es
  /// seguro acá: el índice único parcial `certificados_un_borrador_por_obra` (0053) garantiza que
  /// nunca puede haber más de un `borrador` por obra, así que esta consulta nunca puede devolver
  /// más de una fila.
  Future<Certificado?> getBorradorAbierto(String obraId) async {
    final data = await _client
        .from('certificados')
        .select()
        .eq('obra_id', obraId)
        .eq('estado', 'borrador')
        .maybeSingle();
    return data == null ? null : _fromRow(data);
  }

  /// Crea el Borrador de un certificado nuevo — el único momento donde `numero` se calcula en
  /// Dart en vez de en la base (definición cerrada,
  /// docs/certificados_ciclo_vida_diseno_datos.md §5: sin secuencia dedicada, `unique(obra_id,
  /// numero)` como red de seguridad contra una carrera entre dos inserts simultáneos — riesgo
  /// aceptado, bajo, porque el índice de 0053 ya garantiza que solo puede haber un Borrador a la
  /// vez). `monto` y `estado` no se mandan: la tabla ya los defaultea a 0 y `'borrador'` (0052).
  Future<Certificado> crearCertificadoBorrador({
    required String obraId,
    required String periodo,
    required String usuarioId,
  }) async {
    final ultimos = await _client
        .from('certificados')
        .select('numero')
        .eq('obra_id', obraId)
        .order('numero', ascending: false)
        .limit(1);
    final ultimoNumero = ultimos.isEmpty ? 0 : (ultimos.first['numero'] as num).toInt();

    final inserted = await _client
        .from('certificados')
        .insert({
          'obra_id': obraId,
          'numero': ultimoNumero + 1,
          'periodo': periodo,
          'creado_por': usuarioId,
        })
        .select()
        .single();
    return _fromRow(inserted);
  }

  /// Certificados de la obra con firma física pendiente (`requiere_firma_fisica = true` y
  /// `pdf_firmado_subido = false`) — para el aviso persistente de `CartelFirmaPendiente`. Ya no
  /// bloquea la emisión del siguiente (0055), pero sigue siendo dato real a mostrar hasta que se
  /// resuelva. Cualquier estado del ciclo salvo `borrador` puede aparecer acá (un certificado
  /// pagado o ya impactado igual puede seguir sin su PDF firmado).
  Future<List<Certificado>> getConFirmaPendiente(String obraId) async {
    final data = await _client
        .from('certificados')
        .select()
        .eq('obra_id', obraId)
        .eq('requiere_firma_fisica', true)
        .eq('pdf_firmado_subido', false)
        .order('numero', ascending: true);
    return (data as List)
        .map((row) => _fromRow(row as Map<String, dynamic>))
        .toList();
  }

  /// Sube el/los adjunto(s) del PDF firmado — RPC a `subir_pdf_firmado_certificado`. Mismo patrón
  /// que el resto de los `*_adjuntos` de este certificado (`comprobante_pago_adjuntos`,
  /// `factura_final_adjuntos`): una lista de URLs ya hospedadas afuera (Drive, WhatsApp, etc.), la
  /// app no sube el archivo en sí — no hay ningún mecanismo de carga de binarios en todo el
  /// proyecto todavía (sin `file_picker`, sin uso de Supabase Storage desde Dart).
  Future<void> subirPdfFirmado({
    required String certificadoId,
    required List<String> adjuntos,
  }) async {
    await _client.rpc(
      'subir_pdf_firmado_certificado',
      params: {
        'p_certificado_id': certificadoId,
        'p_adjuntos': adjuntos,
      },
    );
  }

  Certificado _fromRow(Map<String, dynamic> row) {
    return Certificado(
      id: row['id'].toString(),
      obraId: row['obra_id'].toString(),
      numero: (row['numero'] as num).toInt(),
      periodo: row['periodo'].toString(),
      monto: (row['monto'] as num).toDouble(),
      estado: _estadoDesdeColumna(row['estado']?.toString()),
      creadoPor: row['creado_por'].toString(),
      fechaCreacion: DateTime.tryParse(row['fecha_creacion']?.toString() ?? '') ?? DateTime.now(),
      fechaEmision: _fecha(row['fecha_emision']),
      emitidoPor: row['emitido_por']?.toString(),
      diasPlazoPago: (row['dias_plazo_pago'] as num?)?.toInt(),
      requiereFirmaFisica: row['requiere_firma_fisica'] as bool?,
      fechaLectura: _fecha(row['fecha_lectura']),
      leidoPor: row['leido_por']?.toString(),
      fechaPago: _fecha(row['fecha_pago']),
      pagadoPor: row['pagado_por']?.toString(),
      medioPago: row['medio_pago']?.toString(),
      comprobantePagoAdjuntos: _lista(row['comprobante_pago_adjuntos']),
      anticipoPctAplicado: (row['anticipo_pct_aplicado'] as num?)?.toDouble(),
      fondoReparoPctAplicado: (row['fondo_reparo_pct_aplicado'] as num?)?.toDouble(),
      montoAnticipoDescontado: (row['monto_anticipo_descontado'] as num?)?.toDouble(),
      montoFondoReparoRetenido: (row['monto_fondo_reparo_retenido'] as num?)?.toDouble(),
      montoNetoAPagar: (row['monto_neto_a_pagar'] as num?)?.toDouble(),
      fechaImpacto: _fecha(row['fecha_impacto']),
      impactadoPor: row['impactado_por']?.toString(),
      facturaFinalAdjuntos: _lista(row['factura_final_adjuntos']),
      pdfFirmadoSubido: row['pdf_firmado_subido'] == true,
      pdfFirmadoFecha: _fecha(row['pdf_firmado_fecha']),
      pdfFirmadoAdjuntos: _lista(row['pdf_firmado_adjuntos']),
    );
  }

  DateTime? _fecha(dynamic valor) =>
      valor == null ? null : DateTime.tryParse(valor.toString());

  List<String> _lista(dynamic valor) =>
      valor == null ? const [] : List<String>.from(valor as List);

  EstadoCertificado _estadoDesdeColumna(String? valor) {
    switch (valor) {
      case 'borrador':
        return EstadoCertificado.borrador;
      case 'emitido':
        return EstadoCertificado.emitido;
      case 'leido':
        return EstadoCertificado.leido;
      case 'pagado':
        return EstadoCertificado.pagado;
      case 'impactado_cerrado':
        return EstadoCertificado.impactadoCerrado;
      default:
        // Fallback más conservador ante un valor corrupto o desconocido:
        // mostrarlo como el estado menos avanzado, nunca como pagado/cerrado
        // sin serlo.
        return EstadoCertificado.borrador;
    }
  }
}
