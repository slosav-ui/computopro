/// Fila de la tabla `modificaciones_obra` (Supabase) — dos circuitos distintos comparten esta
/// tabla, discriminados por `tipo` (ver docs/adicionales_quitas_demasias_diagnostico.md §1):
/// Demasía/Quita corrige la `cantidad` de una partida YA EN el cómputo (`obraSubitemId` no nulo,
/// aprobada por profesional o constructor, informada al propietario); Adicional es scope nuevo,
/// corre aparte del cómputo (sin construir todavía, pospuesto a propósito, §8). `ajusteContrato`
/// (0008, Modelo B) también vive en esta tabla — se modela acá solo para no perder filas al leer,
/// esta pieza no construye nada sobre ese tipo.
/// Ver supabase/migrations/0002_modificaciones_obra_audit_log.sql,
/// supabase/migrations/0109_quitas_demasias.sql.
enum TipoModificacion { adicional, demasia, quita, ajusteContrato }

extension TipoModificacionColumna on TipoModificacion {
  String get columna {
    switch (this) {
      case TipoModificacion.adicional:
        return 'adicional';
      case TipoModificacion.demasia:
        return 'demasia';
      case TipoModificacion.quita:
        return 'quita';
      case TipoModificacion.ajusteContrato:
        return 'ajuste_contrato';
    }
  }

  String get label {
    switch (this) {
      case TipoModificacion.adicional:
        return 'Adicional';
      case TipoModificacion.demasia:
        return 'Demasía';
      case TipoModificacion.quita:
        return 'Quita';
      case TipoModificacion.ajusteContrato:
        return 'Ajuste de contrato';
    }
  }
}

/// `devuelto` no es terminal: se corrige el mismo registro y vuelve a `pendiente` (definición
/// cerrada, docs/etapa3_roles_permisos_diseno_datos.md §6.5) — no se usa en el circuito de
/// Quitas/Demasías de esta pieza (sin flujo de corrección todavía, se puede rechazar y volver a
/// solicitar), se modela igual para no perder filas al leer.
enum EstadoModificacion { pendiente, devuelto, aprobado, rechazado }

extension EstadoModificacionColumna on EstadoModificacion {
  String get columna => name;

  String get label {
    switch (this) {
      case EstadoModificacion.pendiente:
        return 'Pendiente';
      case EstadoModificacion.devuelto:
        return 'Devuelto';
      case EstadoModificacion.aprobado:
        return 'Aprobado';
      case EstadoModificacion.rechazado:
        return 'Rechazado';
    }
  }
}

class ModificacionObra {
  final String id;
  final String obraId;
  final TipoModificacion tipo;

  /// Catálogo compartido (`subitems`, sin FK real) — dejado de lado por el circuito de Quitas/
  /// Demasías desde la 0109 (ver `obraSubitemId`), sin uso práctico hoy. Se conserva por fidelidad
  /// de fila, no se escribe desde ningún método nuevo de este repositorio.
  final String? subitemId;

  /// La partida real de ESTA obra cuya `cantidad` se está corrigiendo — `0109`, obligatorio para
  /// `demasia`/`quita`, nulo para el resto. Es la corrección del hueco de FK que tenía `subitemId`
  /// (apuntaba al catálogo, no a "esta partida, en esta obra puntual").
  final String? obraSubitemId;

  final String descripcion;

  /// Demasía: cuánto se agrega a la cantidad existente. Quita: cuánto se resta. Siempre positivo —
  /// el signo de la operación lo da `tipo`, no `cantidad` (ver `aprobar_quita_demasia`, 0109).
  final double cantidad;

  final double? precioUnitarioHeredado;

  /// Sin significado propio para `demasia`/`quita` (0109 nunca la lee ni la usa para autoridad,
  /// que corre por `puede_aprobar_quita_demasia`, ajena a montos) — la tabla la exige NOT NULL,
  /// se inserta en 0 para esos dos tipos. Sí es el campo central de `adicional` (pieza aparte).
  final double montoTotal;

  final String? apuPrivadoId;

  final String solicitadoPor;
  final String subidoPor;

  final EstadoModificacion estado;
  final String? aprobadoPor;

  final DateTime fechaSolicitud;
  final DateTime? fechaResolucion;
  final String? comentarioResolucion;

  const ModificacionObra({
    required this.id,
    required this.obraId,
    required this.tipo,
    this.subitemId,
    this.obraSubitemId,
    required this.descripcion,
    required this.cantidad,
    this.precioUnitarioHeredado,
    required this.montoTotal,
    this.apuPrivadoId,
    required this.solicitadoPor,
    required this.subidoPor,
    this.estado = EstadoModificacion.pendiente,
    this.aprobadoPor,
    required this.fechaSolicitud,
    this.fechaResolucion,
    this.comentarioResolucion,
  });

  factory ModificacionObra.fromRow(Map<String, dynamic> row) {
    return ModificacionObra(
      id: row['id'].toString(),
      obraId: row['obra_id'].toString(),
      tipo: _tipoDesdeColumna(row['tipo']?.toString()),
      subitemId: row['subitem_id']?.toString(),
      obraSubitemId: row['obra_subitem_id']?.toString(),
      descripcion: row['descripcion']?.toString() ?? '',
      cantidad: (row['cantidad'] as num?)?.toDouble() ?? 0.0,
      precioUnitarioHeredado: (row['precio_unitario_heredado'] as num?)?.toDouble(),
      montoTotal: (row['monto_total'] as num?)?.toDouble() ?? 0.0,
      apuPrivadoId: row['apu_privado_id']?.toString(),
      solicitadoPor: row['solicitado_por'].toString(),
      subidoPor: row['subido_por'].toString(),
      estado: _estadoDesdeColumna(row['estado']?.toString()),
      aprobadoPor: row['aprobado_por']?.toString(),
      fechaSolicitud: DateTime.tryParse(row['fecha_solicitud']?.toString() ?? '') ?? DateTime.now(),
      fechaResolucion: row['fecha_resolucion'] != null
          ? DateTime.tryParse(row['fecha_resolucion'].toString())
          : null,
      comentarioResolucion: row['comentario_resolucion']?.toString(),
    );
  }

  static TipoModificacion _tipoDesdeColumna(String? valor) {
    switch (valor) {
      case 'demasia':
        return TipoModificacion.demasia;
      case 'quita':
        return TipoModificacion.quita;
      case 'ajuste_contrato':
        return TipoModificacion.ajusteContrato;
      case 'adicional':
      default:
        return TipoModificacion.adicional;
    }
  }

  static EstadoModificacion _estadoDesdeColumna(String? valor) {
    switch (valor) {
      case 'devuelto':
        return EstadoModificacion.devuelto;
      case 'aprobado':
        return EstadoModificacion.aprobado;
      case 'rechazado':
        return EstadoModificacion.rechazado;
      case 'pendiente':
      default:
        // Fallback más conservador ante un valor corrupto o desconocido: pendiente de revisión,
        // nunca aprobado sin serlo.
        return EstadoModificacion.pendiente;
    }
  }
}
