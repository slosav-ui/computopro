import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/certificado.dart';

/// Acceso a la tabla `certificados` de Supabase (ciclo de vida del
/// Certificado, Modelo A).
///
/// Traduce entre las columnas planas y snake_case de la tabla (ver
/// `supabase/migrations/0009_certificados.sql`) y el modelo `Certificado`.
/// Solo lectura por ahora — las 5 transiciones de estado se hacen vía
/// funciones RPC (`emitir_certificado`, `marcar_certificado_leido`,
/// `marcar_certificado_pagado`, `marcar_certificado_impactado`,
/// `subir_pdf_firmado_certificado`), no con `update()` directo, y todavía no
/// están conectadas desde acá.
class CertificadosRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<Certificado>> getCertificadosDeObra(String obraId) async {
    final data = await _client
        .from('certificados')
        .select()
        .eq('obra_id', obraId)
        .order('numero');
    return (data as List)
        .map((row) => _fromRow(row as Map<String, dynamic>))
        .toList();
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
