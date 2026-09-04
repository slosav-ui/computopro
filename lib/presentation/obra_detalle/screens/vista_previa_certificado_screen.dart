import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/segurity/user_context.dart';
import '../../../data/models/certificado.dart';
import '../../../data/models/certificado_subitem_avance.dart';
import '../../../services/auth_service.dart';
import '../../../services/certificado_subitems_avance_repository.dart';
import '../../../services/obra_subitems_repository.dart';
import '../../../services/rubros_repository.dart';
import '../../../services/subitems_repository.dart';

/// Vista previa del certificado antes de emitir — Gestión de Obra, pieza 4, tanda 1. Muestra el
/// detalle por rubro/subítem (de `certificado_subitems_avance`, ya snapshoteado) y el desglose de
/// totales que devuelve `calcular_totales_certificado` (0054) — la misma función que
/// `emitir_certificado` usa para congelar, así que el número que se ve acá es el mismo que se va a
/// guardar, no un cálculo aparte en Dart.
///
/// Acá vive también el botón "Emitir": la firma física se pregunta en este momento, no antes (es
/// una decisión por certificado, no de la obra), y el botón queda deshabilitado mientras haya
/// algún subítem por encima del 100% acumulado (`calcular_excesos_certificado`, misma cuenta que
/// bloquea `emitir_certificado` del lado de la base).
class VistaPreviaCertificadoScreen extends StatefulWidget {
  final String obraId;
  final Certificado certificado;
  final UserContext? userContext;

  const VistaPreviaCertificadoScreen({
    Key? key,
    required this.obraId,
    required this.certificado,
    required this.userContext,
  }) : super(key: key);

  @override
  State<VistaPreviaCertificadoScreen> createState() => _VistaPreviaCertificadoScreenState();
}

class _VistaPreviaCertificadoScreenState extends State<VistaPreviaCertificadoScreen> {
  final CertificadoSubitemsAvanceRepository _avanceRepository = CertificadoSubitemsAvanceRepository();
  final ObraSubitemsRepository _obraSubitemsRepository = ObraSubitemsRepository();
  final SubitemsRepository _subitemsRepository = SubitemsRepository();
  final RubrosRepository _rubrosRepository = RubrosRepository();
  final AuthService _authService = AuthService();

  bool _cargando = true;
  bool _emitiendo = false;
  String? _error;

  List<CertificadoSubitemAvance> _avances = [];
  final Map<String, String> _descripcionPorObraSubitem = {};
  final Map<String, String> _rubroNombrePorObraSubitem = {};
  TotalesCertificado? _totales;
  List<ExcesoCertificado> _excesos = [];

  bool get _puedeEmitir => widget.userContext?.puedeEmitirCertificado == true;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final usuarioId = _authService.usuarioActual?.id;

      final avances = await _avanceRepository.getAvancesDeCertificado(widget.certificado.id);
      final obraSubitemIds = avances.map((a) => a.obraSubitemId).toList();

      final obraSubitemsFuture = _obraSubitemsRepository.getPorIds(obraSubitemIds);
      final totalesFuture = _avanceRepository.getTotalesCertificado(widget.certificado.id);
      final excesosFuture = _avanceRepository.getExcesosCertificado(widget.certificado.id);
      final rubrosFuture = usuarioId == null
          ? _rubrosRepository.getCatalogoOficial()
          : _rubrosRepository.getCatalogoCompleto(usuarioId);

      final obraSubitems = await obraSubitemsFuture;
      final subitemIds = obraSubitems
          .where((os) => os.subitemId != null)
          .map((os) => os.subitemId!)
          .toList();
      final subitemsCatalogo = await _subitemsRepository.getPorIds(subitemIds);
      final rubros = await rubrosFuture;
      final totales = await totalesFuture;
      final excesos = await excesosFuture;

      final descripcionPorSubitemCatalogo = {
        for (final s in subitemsCatalogo) s.id: '${s.codigo} - ${s.descripcion}',
      };
      final nombrePorRubro = {for (final r in rubros) r.id: r.nombre};
      final obraSubitemPorId = {for (final os in obraSubitems) os.id: os};

      if (!mounted) return;
      setState(() {
        _avances = avances;
        _descripcionPorObraSubitem
          ..clear()
          ..addEntries(obraSubitemPorId.entries.map((entry) {
            final os = entry.value;
            final descripcion = os.subitemId != null
                ? (descripcionPorSubitemCatalogo[os.subitemId] ?? 'subítem sin descripción')
                : (os.descripcionLibre ?? 'subítem sin descripción');
            return MapEntry(entry.key, descripcion);
          }));
        _rubroNombrePorObraSubitem
          ..clear()
          ..addEntries(obraSubitemPorId.entries.map(
            (entry) => MapEntry(entry.key, nombrePorRubro[entry.value.rubroId] ?? 'Rubro'),
          ));
        _totales = totales;
        _excesos = excesos;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar la vista previa del certificado.';
        _cargando = false;
      });
    }
  }

  Map<String, List<CertificadoSubitemAvance>> get _avancesPorRubro {
    final mapa = <String, List<CertificadoSubitemAvance>>{};
    for (final a in _avances) {
      final rubro = _rubroNombrePorObraSubitem[a.obraSubitemId] ?? 'Rubro';
      mapa.putIfAbsent(rubro, () => []).add(a);
    }
    return mapa;
  }

  Future<void> _onEmitir() async {
    final requiereFirma = await _preguntarFirmaFisica();
    if (requiereFirma == null) return; // canceló el diálogo
    setState(() => _emitiendo = true);
    try {
      await _avanceRepository.emitirCertificado(
        certificadoId: widget.certificado.id,
        requiereFirmaFisica: requiereFirma,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _emitiendo = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _emitiendo = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo emitir el certificado.')),
      );
    }
  }

  Future<bool?> _preguntarFirmaFisica() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Emitir certificado', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        content: const Text(
          '¿Este certificado requiere firma física? Si la requiere, no se va a poder emitir el '
          'siguiente certificado hasta subir el PDF firmado de este.',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No requiere')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sí, requiere')),
        ],
      ),
    );
  }

  String _fmt(double monto) {
    final valorInt = monto.round();
    final str = valorInt.toString();
    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    final formateado = str.replaceAllMapped(reg, (Match m) => '${m[1]}.');
    return '\$ $formateado';
  }

  String _fmtPct(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Certificado Nº ${widget.certificado.numero.toString().padLeft(3, '0')} — vista previa',
          style: const TextStyle(fontSize: 15),
        ),
        backgroundColor: const Color(0xFF1B365D),
        foregroundColor: Colors.white,
      ),
      body: _buildContenido(),
      bottomNavigationBar: (_cargando || _error != null || !_puedeEmitir) ? null : _buildBarraEmitir(),
    );
  }

  Widget _buildContenido() {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
        ),
      );
    }
    final totales = _totales!;
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        Text('Período: ${widget.certificado.periodo}',
            style: const TextStyle(fontSize: 13, color: Colors.black54)),
        const SizedBox(height: 12),
        if (_excesos.isNotEmpty) _buildAvisoExcesos(),
        if (_avances.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'Este certificado todavía no tiene ningún avance cargado.',
              style: TextStyle(color: Colors.black54, fontSize: 13),
            ),
          )
        else
          ..._avancesPorRubro.entries.map(_buildBloqueRubro),
        const Divider(height: 32),
        _buildFilaTotal('Subtotal certificado', totales.monto),
        if ((totales.anticipoPct ?? 0) > 0)
          _buildFilaTotal(
              'Anticipo descontado (${_fmtPct(totales.anticipoPct!)}%)', -totales.montoAnticipo),
        if ((totales.fondoReparoPct ?? 0) > 0)
          _buildFilaTotal(
              'Fondo de reparo retenido (${_fmtPct(totales.fondoReparoPct!)}%)', -totales.montoFondoReparo),
        const Divider(),
        _buildFilaTotal('Neto a pagar', totales.montoNeto, destacado: true),
        const SizedBox(height: 80), // espacio para no quedar tapado por la barra de Emitir
      ],
    );
  }

  Widget _buildAvisoExcesos() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        border: Border.all(color: Colors.red.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No se puede emitir todavía — hay subítems que exceden el 100% acumulado:',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red.shade800),
          ),
          const SizedBox(height: 4),
          ..._excesos.map((e) => Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '"${e.descripcion}": ya tiene ${_fmtPct(e.acumuladoPrevio)}% certificado, quedan '
                  '${_fmtPct(e.disponible)}% disponibles y se cargó ${_fmtPct(e.intentado)}%. '
                  'Volvé a la carga de avance para corregirlo.',
                  style: TextStyle(fontSize: 11.5, color: Colors.red.shade700),
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildBloqueRubro(MapEntry<String, List<CertificadoSubitemAvance>> entry) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(entry.key,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1B365D))),
          const SizedBox(height: 4),
          ...entry.value.map((a) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _descripcionPorObraSubitem[a.obraSubitemId] ?? 'subítem sin descripción',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                    Text('${_fmtPct(a.porcentajePeriodo)}%',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 90,
                      child: Text(_fmt(a.montoPeriodo),
                          textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5)),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildFilaTotal(String etiqueta, double monto, {bool destacado = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(etiqueta,
              style: TextStyle(
                  fontSize: destacado ? 14 : 13, fontWeight: destacado ? FontWeight.bold : FontWeight.normal)),
          Text(
            _fmt(monto),
            style: TextStyle(
              fontSize: destacado ? 15 : 13,
              fontWeight: destacado ? FontWeight.bold : FontWeight.normal,
              color: destacado ? const Color(0xFF1B365D) : (monto < 0 ? Colors.red.shade700 : Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarraEmitir() {
    final habilitado = _excesos.isEmpty && !_emitiendo;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: ElevatedButton(
          onPressed: habilitado ? _onEmitir : null,
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B365D), foregroundColor: Colors.white),
          child: _emitiendo
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Emitir certificado'),
        ),
      ),
    );
  }
}
