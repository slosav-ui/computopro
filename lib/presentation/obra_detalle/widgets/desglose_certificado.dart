import 'package:flutter/material.dart';
import '../../../data/models/certificado_subitem_avance.dart';
import '../../../services/certificado_subitems_avance_repository.dart';
import '../../../services/obra_subitems_repository.dart';
import '../../../services/rubros_repository.dart';
import '../../../services/subitems_repository.dart';
import '../../../services/auth_service.dart';

/// Qué se certificó, partida por partida: agrupado por rubro, con el porcentaje del período y el
/// monto de cada renglón.
///
/// ================== POR QUÉ ES UN WIDGET Y NO CÓDIGO EN UNA PANTALLA ==================
///
/// Esto existía solo dentro de `VistaPreviaCertificadoScreen`, o sea **únicamente mientras el
/// certificado era un borrador**. Emitido, la pantalla de detalle mostraba el monto total y nada
/// más. Seba lo encontró probando la obra real (2026-09-14): *"sin eso el certificado no sirve como
/// documento, y tampoco tengo referencia para cargar el siguiente"*.
///
/// Las dos mitades de esa frase son dos problemas distintos y los dos importan:
///
///   - **como documento**: el certificado en papel tiene una fila por partida con su porcentaje y su
///     monto. Un total suelto no es un certificado, es un número;
///   - **como referencia**: para cargar el certificado siguiente hay que saber qué se certificó en el
///     anterior. Sin el desglose hay que reconstruirlo de memoria.
///
/// Se extrajo a un widget en vez de copiarse para que las dos pantallas no se desincronicen: es
/// exactamente el mismo desglose antes y después de emitir, y tiene que seguir siéndolo.
///
/// Carga sola a partir del `certificadoId` -- no recibe los avances ya cargados a propósito, para
/// que agregarlo a una pantalla sea una línea y no un capítulo de `initState`.
class DesgloseCertificado extends StatefulWidget {
  final String certificadoId;

  /// Cómo formatear cada monto. Lo pone quien lo usa porque la conversión a la moneda de la obra
  /// (y con qué cotización) es decisión de la pantalla, no de este widget -- el certificado emitido
  /// usa la cotización congelada al emitir y la vista previa la de hoy.
  final String Function(double montoArs) formatearMonto;

  /// `false` esconde los montos y deja solo los porcentajes, para quien no ve plata en esta obra
  /// (constructor sin permiso, según la matriz de roles).
  final bool mostrarMontos;

  const DesgloseCertificado({
    super.key,
    required this.certificadoId,
    required this.formatearMonto,
    this.mostrarMontos = true,
  });

  @override
  State<DesgloseCertificado> createState() => _DesgloseCertificadoState();
}

class _DesgloseCertificadoState extends State<DesgloseCertificado> {
  static const _azul = Color(0xFF1B365D);

  final CertificadoSubitemsAvanceRepository _avanceRepository = CertificadoSubitemsAvanceRepository();
  final ObraSubitemsRepository _obraSubitemsRepository = ObraSubitemsRepository();
  final SubitemsRepository _subitemsRepository = SubitemsRepository();
  final RubrosRepository _rubrosRepository = RubrosRepository();
  final AuthService _authService = AuthService();

  List<CertificadoSubitemAvance> _avances = [];
  final Map<String, String> _descripcionPorObraSubitem = {};
  final Map<String, String> _rubroPorObraSubitem = {};
  bool _cargando = true;
  bool _fallo = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final avances = await _avanceRepository.getAvancesDeCertificado(widget.certificadoId);
      if (avances.isEmpty) {
        if (!mounted) return;
        setState(() => _cargando = false);
        return;
      }

      final obraSubitems =
          await _obraSubitemsRepository.getPorIds(avances.map((a) => a.obraSubitemId).toList());
      final subitemsCatalogo = await _subitemsRepository.getPorIds(
        obraSubitems.where((os) => os.subitemId != null).map((os) => os.subitemId!).toList(),
      );
      final usuarioId = _authService.usuarioActual?.id;
      final rubros = usuarioId == null
          ? await _rubrosRepository.getCatalogoOficial()
          : await _rubrosRepository.getCatalogoCompleto(usuarioId);

      final descripcionPorCatalogo = {
        for (final s in subitemsCatalogo) s.id: '${s.codigo} - ${s.descripcion}',
      };
      final nombrePorRubro = {for (final r in rubros) r.id: r.nombre};

      if (!mounted) return;
      setState(() {
        _avances = avances;
        _descripcionPorObraSubitem
          ..clear()
          ..addEntries(obraSubitems.map((os) => MapEntry(
                os.id,
                os.subitemId != null
                    ? (descripcionPorCatalogo[os.subitemId] ?? 'partida sin descripción')
                    : (os.descripcionLibre ?? 'partida sin descripción'),
              )));
        _rubroPorObraSubitem
          ..clear()
          ..addEntries(obraSubitems
              .map((os) => MapEntry(os.id, nombrePorRubro[os.rubroId] ?? 'Rubro')));
        _cargando = false;
      });
    } catch (_) {
      // El desglose es información, no una acción: si falla, la pantalla que lo contiene tiene que
      // seguir sirviendo. Se avisa en vez de desaparecer, para que nadie lea "este certificado no
      // tiene detalle" cuando lo que pasó es que no se pudo traer.
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _fallo = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    if (_fallo) {
      return Text(
        'No se pudo cargar el detalle por partida. Probá de nuevo más tarde.',
        style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
      );
    }
    if (_avances.isEmpty) {
      return Text(
        'Este certificado no tiene avance cargado por partida.',
        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
      );
    }

    // Agrupado por rubro, respetando el orden en que vienen los avances -- que es el orden de carga,
    // el mismo que tiene el papel.
    final porRubro = <String, List<CertificadoSubitemAvance>>{};
    for (final a in _avances) {
      porRubro.putIfAbsent(_rubroPorObraSubitem[a.obraSubitemId] ?? 'Rubro', () => []).add(a);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.list_alt_outlined, size: 16, color: _azul),
            const SizedBox(width: 6),
            const Text('Detalle por partida',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _azul)),
            const Spacer(),
            Text('${_avances.length} ${_avances.length == 1 ? "partida" : "partidas"}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ],
        ),
        const SizedBox(height: 10),
        for (final entry in porRubro.entries) _buildRubro(entry.key, entry.value),
      ],
    );
  }

  Widget _buildRubro(String rubro, List<CertificadoSubitemAvance> avances) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(rubro,
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: _azul)),
          const SizedBox(height: 5),
          for (final a in avances) _buildFila(a),
        ],
      ),
    );
  }

  /// Una partida. Apilada y no en columnas de ancho fijo, por lo que enseñó la tabla de materiales
  /// de APU: una caja de ancho fijo con texto que escala se cruza con la de al lado apenas el
  /// usuario agranda la fuente del sistema. Acá la descripción ocupa su renglón y los dos números
  /// van abajo, alineados a la derecha -- entra en cualquier ancho y a cualquier escala.
  Widget _buildFila(CertificadoSubitemAvance a) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _descripcionPorObraSubitem[a.obraSubitemId] ?? 'partida sin descripción',
            style: const TextStyle(fontSize: 12.5, height: 1.3),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${_fmtPct(a.porcentajePeriodo)}% del período',
                  style: TextStyle(
                      fontSize: 10.5, fontWeight: FontWeight.w600, color: Colors.blueGrey.shade800),
                ),
              ),
              const Spacer(),
              if (widget.mostrarMontos)
                Flexible(
                  child: Text(
                    widget.formatearMonto(a.montoPeriodo),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600, color: _azul),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _fmtPct(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}
