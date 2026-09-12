import 'certificado.dart';

/// Una cosa que espera la acción del usuario logueado -- fila de `mis_pendientes()` (0117,
/// docs/avisos_pendientes_diseno.md). Quién ve cada una lo decide la base con la misma autoridad que
/// usa la transición que la resuelve; la app solo la muestra y lleva a donde se resuelve.
enum TipoPendiente {
  adicional,
  quita,
  demasia,
  certificadoEmitido,
  certificadoLeido,
  certificadoPagado,
  anulacion,
  firmaFisica,
}

class Pendiente {
  final String obraId;
  final String obraNombre;
  final TipoPendiente tipo;

  /// `modificaciones_obra.id` (adicional/quita/demasía) o `certificados.id` (el resto).
  final String entidadId;

  /// Descripción del adicional/quita/demasía, o período del certificado.
  final String descripcion;

  final int? certificadoNumero;
  final int? certificadoVersion;

  /// Desde cuándo espera -- envío/solicitud, emisión, lectura, pago o propuesta, según el tipo.
  final DateTime? desde;

  const Pendiente({
    required this.obraId,
    required this.obraNombre,
    required this.tipo,
    required this.entidadId,
    required this.descripcion,
    this.certificadoNumero,
    this.certificadoVersion,
    this.desde,
  });

  bool get esDeCertificado => certificadoNumero != null;

  String get _numero => Certificado.formatearNumero(certificadoNumero ?? 0, certificadoVersion ?? 1);

  String get titulo {
    switch (tipo) {
      case TipoPendiente.adicional:
        return 'Adicional para aprobar';
      case TipoPendiente.quita:
        return 'Quita para aprobar';
      case TipoPendiente.demasia:
        return 'Demasía para aprobar';
      case TipoPendiente.certificadoEmitido:
        return 'Certificado N° $_numero emitido, sin leer';
      case TipoPendiente.certificadoLeido:
        return 'Certificado N° $_numero: falta registrar el pago';
      case TipoPendiente.certificadoPagado:
        return 'Certificado N° $_numero pagado: falta cerrarlo';
      case TipoPendiente.anulacion:
        return 'Anulación propuesta del certificado N° $_numero';
      case TipoPendiente.firmaFisica:
        return 'Certificado N° $_numero: falta subir el PDF firmado';
    }
  }

  String get detalle => esDeCertificado ? 'Período $descripcion' : descripcion;

  /// `null` si la base devuelve un tipo que esta versión de la app no conoce -- se saltea esa fila
  /// en vez de romper el dashboard entero.
  static Pendiente? desdeRow(Map<String, dynamic> row) {
    final tipo = _tipoDesdeColumna(row['tipo']?.toString());
    if (tipo == null) return null;
    return Pendiente(
      obraId: row['obra_id'].toString(),
      obraNombre: row['obra_nombre']?.toString() ?? '',
      tipo: tipo,
      entidadId: row['entidad_id'].toString(),
      descripcion: row['descripcion']?.toString() ?? '',
      certificadoNumero: (row['certificado_numero'] as num?)?.toInt(),
      certificadoVersion: (row['certificado_version'] as num?)?.toInt(),
      desde: row['desde'] != null ? DateTime.tryParse(row['desde'].toString()) : null,
    );
  }

  static TipoPendiente? _tipoDesdeColumna(String? valor) {
    switch (valor) {
      case 'adicional':
        return TipoPendiente.adicional;
      case 'quita':
        return TipoPendiente.quita;
      case 'demasia':
        return TipoPendiente.demasia;
      case 'certificado_emitido':
        return TipoPendiente.certificadoEmitido;
      case 'certificado_leido':
        return TipoPendiente.certificadoLeido;
      case 'certificado_pagado':
        return TipoPendiente.certificadoPagado;
      case 'anulacion':
        return TipoPendiente.anulacion;
      case 'firma_fisica':
        return TipoPendiente.firmaFisica;
      default:
        return null;
    }
  }
}
