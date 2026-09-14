import 'certificado.dart';
import 'obra_config_certificacion.dart';

/// Una acción requerida del usuario logueado -- fila de `mis_pendientes()` (0117,
/// docs/avisos_pendientes_diseno.md). Quién ve cada una lo decide la base con la misma autoridad que
/// usa la transición que la resuelve; la app solo la muestra y lleva a donde se resuelve.
///
/// **Criterio de tono, fijado por Seba el 2026-09-13** (antes los textos eran coloquiales -- "tenés
/// 1 cosa esperándote", "falta registrar el pago"):
///
/// - `titulo`: **qué hay que hacer**, en la forma "&lt;qué&gt; para &lt;acción&gt;". Sin "falta" ni
///   "sin": nombran lo que no se hizo y suenan a reproche, cuando el que mira recién se está
///   enterando.
/// - `detalle`: **el dato concreto y cuándo**, para que el ítem se explique solo sin abrirlo.
/// - Nada de "vencido" ni de lenguaje que dé a entender que algo se hizo mal: un período de
///   certificación que llegó es una **habilitación que se abre**, no un problema.
enum TipoPendiente {
  adicional,
  quita,
  demasia,
  certificadoEmitido,
  certificadoLeido,
  certificadoPagado,
  anulacion,
  firmaFisica,

  /// "Ya se puede certificar": venció el período de la periodicidad pactada y no hay borrador en
  /// curso (`0123`). El único tipo que NO es una fila de ninguna entidad -- ver `entidadId`.
  certificacionPeriodo,

  /// "Te proponen un avance para revisar": el borrador tiene una propuesta esperando la conformidad
  /// de la contraparte (`0124`). Va solo a quien puede conformarla, nunca a quien propuso -- lo
  /// decide `puede_dar_conformidad_certificado`, la misma función que ejecuta la acción.
  certificadoPropuesto,

  /// Un certificado anulado que quedó **sin reemplazo** (`0126`). Red de reparación: bajo uso normal
  /// de la app no se puede producir, así que si aparece, falta algo de verdad -- por eso no se
  /// descarta, se resuelve creando el reemplazo.
  certificadoSinReemplazo,

  /// "Te objetaron un certificado" (`0129`): el cliente planteó una duda y todavía nadie la
  /// respondió. Va al lado técnico, que es el que sabe qué se midió.
  certificadoObjetado,

  /// La vuelta de lo anterior: al cliente le respondieron la objeción y sigue abierta. Le toca leer
  /// la aclaración y levantarla, o dejarla planteada.
  objecionRespondida,

  /// El borrador ya conformado que todavía nadie emitió (`0130`). Va a quien emite en esa obra según
  /// la escalera de la `0125` — que puede no haber participado ni de la propuesta ni de la
  /// conformidad, y por eso el aviso hace falta: hasta la `0130` este certificado **no le aparecía a
  /// nadie** y podía quedar esperando para siempre, con las dos partes técnicas creyendo que ya
  /// estaba.
  certificadoConforme,

  /// El borrador que la contraparte devolvió con un comentario y todavía nadie volvió a proponer
  /// (`0131`). Va solo a quien propuso: un borrador que te devolvieron no es trabajo que elegiste
  /// tener abierto, es una respuesta que te esperan.
  certificadoDevuelto,


}

class Pendiente {
  final String obraId;
  final String obraNombre;
  final TipoPendiente tipo;

  /// `modificaciones_obra.id` (adicional/quita/demasía) o `certificados.id` (casi todo el resto).
  /// **`null` en `certificacionPeriodo`**: ahí el pendiente no es una fila, es un período que
  /// venció, y lo que hay que abrir es Gestión de Obra de la obra.
  final String? entidadId;

  /// Descripción del adicional/quita/demasía, período del certificado, o la periodicidad pactada
  /// (`mensual`/`quincenal`/`semanal`) en `certificacionPeriodo`.
  final String descripcion;

  final int? certificadoNumero;
  final int? certificadoVersion;

  /// Desde cuándo espera -- envío/solicitud, emisión, lectura, pago o propuesta, según el tipo.
  final DateTime? desde;

  /// Cuándo esto se resuelve **solo**, si tiene plazo (`0131`). Hoy lo llena una sola rama, la
  /// objeción respondida, y recién pasados los 2 días en que corresponde avisar: la base manda la
  /// fecha cuando hay que decirla y null antes. Por eso acá no hay ningún número de días -- ni el 2
  /// ni el 5 viven en Dart, y no se pueden desincronizar con los que aplica la función.
  final DateTime? vence;

  const Pendiente({
    required this.obraId,
    required this.obraNombre,
    required this.tipo,
    this.entidadId,
    required this.descripcion,
    this.certificadoNumero,
    this.certificadoVersion,
    this.desde,
    this.vence,
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
        return 'Certificado N° $_numero para leer';
      case TipoPendiente.certificadoLeido:
        return 'Certificado N° $_numero para registrar el pago';
      case TipoPendiente.certificadoPagado:
        return 'Certificado N° $_numero para cerrar';
      case TipoPendiente.anulacion:
        return 'Anulación del certificado N° $_numero para resolver';
      case TipoPendiente.firmaFisica:
        return 'Certificado N° $_numero para subir el PDF firmado';
      case TipoPendiente.certificacionPeriodo:
        return 'Ya se puede certificar';
      case TipoPendiente.certificadoPropuesto:
        return 'Certificado N° $_numero para revisar y conformar';
      case TipoPendiente.certificadoSinReemplazo:
        return 'Certificado N° $_numero para recrear su reemplazo';
      case TipoPendiente.certificadoObjetado:
        return 'Certificado N° $_numero para responder una objeción';
      case TipoPendiente.objecionRespondida:
        return 'Certificado N° $_numero para revisar la respuesta a tu objeción';
      case TipoPendiente.certificadoConforme:
        return 'Certificado N° $_numero para emitir';
      case TipoPendiente.certificadoDevuelto:
        return 'Certificado N° $_numero para corregir y volver a proponer';
    }
  }

  /// El dato concreto de este pendiente y desde cuándo, para que el ítem se explique solo. El verbo
  /// es el del hecho que lo abrió (emitido, leído, pagado, propuesta, solicitado), no una carencia.
  String get detalle {
    final cuando = _fechaCorta(desde);
    switch (tipo) {
      case TipoPendiente.certificacionPeriodo:
        // "habilitado", nunca "vencido": el período que llega ABRE la posibilidad de certificar,
        // no denuncia un atraso (criterio de Seba, 2026-09-13).
        final periodicidad = periodicidadDesdeColumna(descripcion);
        final base = periodicidad == null
            ? 'Período de certificación pactado'
            : 'Período ${periodicidad.labelMinuscula}';
        return cuando == null ? base : '$base, habilitado desde el $cuando';
      case TipoPendiente.adicional:
        return _conFecha(descripcion, 'presentado el', cuando);
      case TipoPendiente.quita:
      case TipoPendiente.demasia:
        return _conFecha(descripcion, 'solicitada el', cuando);
      case TipoPendiente.certificadoEmitido:
      case TipoPendiente.firmaFisica:
        return _conFecha('Período $descripcion', 'emitido el', cuando);
      case TipoPendiente.certificadoLeido:
        return _conFecha('Período $descripcion', 'leído el', cuando);
      case TipoPendiente.certificadoPagado:
        return _conFecha('Período $descripcion', 'pagado el', cuando);
      case TipoPendiente.anulacion:
        return _conFecha('Período $descripcion', 'propuesta el', cuando);
      case TipoPendiente.certificadoPropuesto:
        return _conFecha('Período $descripcion', 'propuesto el', cuando);
      case TipoPendiente.certificadoSinReemplazo:
        return _conFecha('Período $descripcion', 'anulado el', cuando);
      case TipoPendiente.certificadoObjetado:
        return _conFecha('Período $descripcion', 'objetado el', cuando);
      case TipoPendiente.objecionRespondida:
        final base = _conFecha('Período $descripcion', 'respondida el', cuando);
        // El aviso de los 2 días (0131). Lo decide la base: manda `vence` recién cuando hay que
        // avisar. "Se resuelve sola" y no "vence" ni "se pierde": lo que llega no es un castigo por
        // no contestar, es el plazo que se pactó para sostener una objeción.
        final seResuelve = _fechaCorta(vence);
        return seResuelve == null ? base : '$base · se resuelve sola el $seResuelve';
      case TipoPendiente.certificadoConforme:
        // "conformado", el hecho que abrió la espera, y no "sin emitir": el que mira recién se está
        // enterando de que le toca.
        return _conFecha('Período $descripcion', 'conformado el', cuando);
      case TipoPendiente.certificadoDevuelto:
        // La fecha es la de la propuesta que devolvieron: la devolución no guarda fecha propia
        // (0124 guardó el comentario y no el momento), y decir "propuesto el" es lo cierto.
        return _conFecha('Período $descripcion', 'propuesto el', cuando);
    }
  }

  static String _conFecha(String base, String verbo, String? cuando) =>
      cuando == null ? base : '$base, $verbo $cuando';

  /// Día y mes, sin año: el pendiente es de ahora, el año no aporta y alarga el renglón.
  static String? _fechaCorta(DateTime? f) {
    if (f == null) return null;
    final l = f.toLocal();
    return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}';
  }

  /// `null` si la base devuelve un tipo que esta versión de la app no conoce -- se saltea esa fila
  /// en vez de romper el dashboard entero.
  static Pendiente? desdeRow(Map<String, dynamic> row) {
    final tipo = _tipoDesdeColumna(row['tipo']?.toString());
    if (tipo == null) return null;
    return Pendiente(
      obraId: row['obra_id'].toString(),
      obraNombre: row['obra_nombre']?.toString() ?? '',
      tipo: tipo,
      // null en certificacionPeriodo -- ver el campo.
      entidadId: row['entidad_id']?.toString(),
      descripcion: row['descripcion']?.toString() ?? '',
      certificadoNumero: (row['certificado_numero'] as num?)?.toInt(),
      certificadoVersion: (row['certificado_version'] as num?)?.toInt(),
      desde: row['desde'] != null ? DateTime.tryParse(row['desde'].toString()) : null,
      vence: row['vence'] != null ? DateTime.tryParse(row['vence'].toString()) : null,
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
      case 'certificacion_periodo':
        return TipoPendiente.certificacionPeriodo;
      case 'certificado_propuesto':
        return TipoPendiente.certificadoPropuesto;
      case 'certificado_sin_reemplazo':
        return TipoPendiente.certificadoSinReemplazo;
      case 'certificado_objetado':
        return TipoPendiente.certificadoObjetado;
      case 'objecion_respondida':
        return TipoPendiente.objecionRespondida;
      case 'certificado_conforme':
        return TipoPendiente.certificadoConforme;
      case 'certificado_devuelto':
        return TipoPendiente.certificadoDevuelto;
      default:
        return null;
    }
  }
}
