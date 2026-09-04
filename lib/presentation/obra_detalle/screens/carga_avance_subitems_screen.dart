import 'package:flutter/material.dart';
import '../../../core/segurity/user_context.dart';
import '../../../core/utils/parser_numero_ar.dart';
import '../../../data/models/certificado.dart';
import '../../../data/models/certificado_subitem_avance.dart';
import '../../../data/models/obra_subitem.dart';
import '../../../data/models/rubro_catalogo.dart';
import '../../../services/auth_service.dart';
import '../../../services/certificado_subitems_avance_repository.dart';
import '../../../services/obra_subitems_repository.dart';
import '../../../services/subitems_repository.dart';

/// Carga de avance de los subítems tildados de UN rubro, para el Borrador en curso — Gestión de
/// Obra, pieza 3. Empujada desde `CargaAvanceRubrosScreen`, mismo patrón de navegación que
/// `SubitemsScreen` (empujada desde `RubrosTab`): esta pantalla, no un acordeón, es "el rubro
/// abierto".
///
/// Cada fila muestra 3 cosas (definido por Seba, sin reinterpretar): el historial de avances
/// anteriores certificado por certificado (plegado, para no saturar una fila de teléfono), el
/// acumulado (siempre visible), y el campo editable del período. El candado real del 100% vive en
/// `emitir_certificado` (0052) — acá solo hay avisos, nunca un rechazo silencioso ni un recorte
/// automático.
class CargaAvanceSubitemsScreen extends StatefulWidget {
  final String obraId;
  final RubroCatalogo rubro;
  final Certificado certificado;
  final UserContext? userContext;

  const CargaAvanceSubitemsScreen({
    Key? key,
    required this.obraId,
    required this.rubro,
    required this.certificado,
    required this.userContext,
  }) : super(key: key);

  @override
  State<CargaAvanceSubitemsScreen> createState() => _CargaAvanceSubitemsScreenState();
}

class _CargaAvanceSubitemsScreenState extends State<CargaAvanceSubitemsScreen> {
  final ObraSubitemsRepository _obraSubitemsRepository = ObraSubitemsRepository();
  final SubitemsRepository _subitemsRepository = SubitemsRepository();
  final CertificadoSubitemsAvanceRepository _avanceRepository = CertificadoSubitemsAvanceRepository();
  final AuthService _authService = AuthService();

  bool _cargando = true;
  String? _error;
  List<ObraSubitem> _obraSubitems = [];
  final Map<String, String> _descripcionPorSubitemCatalogo = {};
  final Map<String, MontoObraSubitem> _montoPorObraSubitem = {};
  final Map<String, double> _acumuladoPorObraSubitem = {};
  final Map<String, CertificadoSubitemAvance> _avanceActualPorObraSubitem = {};

  // Historial: cargado a demanda (lazy) recién cuando el usuario despliega esa fila puntual, no
  // de arriba para todas — evita N llamadas de más para algo que casi siempre queda plegado.
  final Map<String, List<AvanceHistorialItem>> _historialPorObraSubitem = {};
  final Set<String> _historialExpandido = {};
  final Set<String> _cargandoHistorial = {};

  // TextEditingController/FocusNode por fila, cacheados acá (no creados en itemBuilder) — mismo
  // motivo que subitems_screen.dart: no perder lo que el usuario está tipeando en cada rebuild.
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, FocusNode> _focusNodes = {};
  final Set<String> _guardando = {};

  bool get _puedeCargar => widget.userContext?.puedeCargarAvance == true;
  bool get _puedeVerMontos => widget.userContext?.puedeVerMontosGestionObra == true;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final f in _focusNodes.values) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final usuarioId = _authService.usuarioActual?.id;

      final obraSubitemsFuture = _obraSubitemsRepository.getTildadosDeRubro(
        obraId: widget.obraId,
        rubroId: widget.rubro.id,
      );
      final subitemsCatalogoFuture = _subitemsRepository.getSubitemsDeRubro(widget.rubro.id, usuarioId: usuarioId);
      final montosFuture = _avanceRepository.getMontoObraSubitems(widget.obraId);
      final avancesFuture = _avanceRepository.getAvancesDeCertificado(widget.certificado.id);

      final obraSubitems = await obraSubitemsFuture;
      final subitemsCatalogo = await subitemsCatalogoFuture;
      final montos = await montosFuture;
      final avances = await avancesFuture;

      // Acumulado: una llamada por subítem tildado de este rubro, en paralelo — no hay (todavía)
      // una versión batch de calcular_avance_acumulado_subitem, y un rubro tiene pocos subítems
      // como para que N llamadas paralelas sean un problema real.
      final acumulados = await Future.wait(
        obraSubitems.map((os) => _avanceRepository.getAcumuladoSubitem(os.id)),
      );

      if (!mounted) return;
      setState(() {
        _obraSubitems = obraSubitems;
        _descripcionPorSubitemCatalogo
          ..clear()
          ..addEntries(subitemsCatalogo.map((s) => MapEntry(s.id, '${s.codigo} - ${s.descripcion}')));
        _montoPorObraSubitem
          ..clear()
          ..addAll(montos);
        _avanceActualPorObraSubitem
          ..clear()
          ..addEntries(avances.map((a) => MapEntry(a.obraSubitemId, a)));
        for (var i = 0; i < obraSubitems.length; i++) {
          _acumuladoPorObraSubitem[obraSubitems[i].id] = acumulados[i];
        }
        for (final c in _controllers.values) {
          c.dispose();
        }
        _controllers.clear();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar el avance de este rubro.';
        _cargando = false;
      });
    }
  }

  TextEditingController _controllerPara(ObraSubitem os) {
    return _controllers.putIfAbsent(
      os.id,
      () => TextEditingController(
        text: _avanceActualPorObraSubitem[os.id] != null
            ? _fmtEntrada(_avanceActualPorObraSubitem[os.id]!.porcentajePeriodo)
            : '',
      ),
    );
  }

  FocusNode _focusNodePara(ObraSubitem os) {
    return _focusNodes.putIfAbsent(os.id, () {
      final node = FocusNode();
      node.addListener(() {
        if (!node.hasFocus) _onPerderFoco(os);
      });
      return node;
    });
  }

  String _fmtEntrada(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  String _descripcionDe(ObraSubitem os) {
    if (os.subitemId != null) {
      return _descripcionPorSubitemCatalogo[os.subitemId] ?? 'Subítem';
    }
    return os.descripcionLibre ?? 'Ítem sin descripción (OTRO)';
  }

  Future<void> _toggleHistorial(ObraSubitem os) async {
    if (_historialExpandido.contains(os.id)) {
      setState(() => _historialExpandido.remove(os.id));
      return;
    }
    setState(() => _historialExpandido.add(os.id));
    if (_historialPorObraSubitem.containsKey(os.id)) return; // ya cargado antes
    setState(() => _cargandoHistorial.add(os.id));
    try {
      final historial = await _avanceRepository.getHistorialPorSubitem(os.id);
      if (!mounted) return;
      setState(() {
        _historialPorObraSubitem[os.id] = historial;
        _cargandoHistorial.remove(os.id);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargandoHistorial.remove(os.id));
    }
  }

  Future<void> _onPerderFoco(ObraSubitem os) async {
    final controller = _controllers[os.id];
    if (controller == null || !_puedeCargar) return;
    final texto = controller.text.trim();
    if (texto.isEmpty) return; // no borra un avance ya cargado por dejar el campo vacío sin querer

    final valor = ParserNumeroAr.parsear(texto);
    if (valor == null || valor <= 0 || valor > 100) {
      _mostrarError('El porcentaje tiene que ser mayor a 0 y hasta 100.');
      // revierte al último valor guardado, no deja un número inválido a medio camino
      controller.text = _avanceActualPorObraSubitem[os.id] != null
          ? _fmtEntrada(_avanceActualPorObraSubitem[os.id]!.porcentajePeriodo)
          : '';
      return;
    }

    final acumulado = _acumuladoPorObraSubitem[os.id] ?? 0;
    final disponible = double.parse((100 - acumulado).toStringAsFixed(2));

    if (valor > disponible) {
      // Textual de Seba: avisa cuánto queda de verdad y deja elegir — nunca rechaza en silencio
      // ni recorta solo.
      final decision = await _confirmarExceso(disponible, valor);
      if (decision == null) {
        // "Revisar": no guarda nada, el campo queda como está para que el usuario lo corrija.
        return;
      }
      controller.text = _fmtEntrada(decision);
      await _guardar(os, decision);
      return;
    }

    await _guardar(os, valor);
  }

  Future<double?> _confirmarExceso(double disponible, double intentado) {
    return showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excede lo disponible', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        content: Text(
          'Para llegar al 100% le queda solamente un ${_fmtEntrada(disponible)}% disponible. '
          '¿Querés certificar ese ${_fmtEntrada(disponible)}% o preferís revisar el número?',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Revisar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, disponible),
            child: Text('Certificar ${_fmtEntrada(disponible)}%'),
          ),
        ],
      ),
    );
  }

  Future<void> _guardar(ObraSubitem os, double porcentaje) async {
    final usuarioId = _authService.usuarioActual?.id;
    if (usuarioId == null) return;
    setState(() => _guardando.add(os.id));
    try {
      final avance = await _avanceRepository.guardarAvance(
        certificadoId: widget.certificado.id,
        obraSubitemId: os.id,
        porcentajePeriodo: porcentaje,
        usuarioId: usuarioId,
      );
      if (!mounted) return;
      setState(() {
        _avanceActualPorObraSubitem[os.id] = avance;
        _guardando.remove(os.id);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando.remove(os.id));
      _mostrarError('No se pudo guardar el avance de este subítem.');
    }
  }

  void _mostrarError(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.rubro.nombre, style: const TextStyle(fontSize: 15), overflow: TextOverflow.ellipsis),
        backgroundColor: const Color(0xFF1B365D),
        foregroundColor: Colors.white,
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: RefreshIndicator(onRefresh: _cargarDatos, child: _buildContenido()),
      ),
    );
  }

  Widget _buildContenido() {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Center(
              child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
            ),
          ),
        ],
      );
    }
    if (_obraSubitems.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Text(
            'Este rubro no tiene subítems tildados en esta obra.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54, fontSize: 13),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12.0),
      itemCount: _obraSubitems.length,
      itemBuilder: (context, index) => _buildFila(_obraSubitems[index]),
    );
  }

  Widget _buildFila(ObraSubitem os) {
    final acumulado = _acumuladoPorObraSubitem[os.id] ?? 0;
    final alCien = acumulado >= 100;
    final expandido = _historialExpandido.contains(os.id);
    final guardandoEsta = _guardando.contains(os.id);

    return Card(
      margin: const EdgeInsets.only(bottom: 4.0),
      elevation: 1,
      color: alCien ? const Color(0xFFF1F1F1) : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _descripcionDe(os),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Acumulado, siempre visible — es el dato que más importa de un vistazo.
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        'Acumulado: ${_fmtEntrada(acumulado)}%',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: alCien ? Colors.green.shade700 : const Color(0xFF1B365D),
                        ),
                      ),
                      if (alCien) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.check_circle, size: 14, color: Colors.green.shade700),
                      ],
                    ],
                  ),
                ),
                if (alCien)
                  const Text('Certificado al 100%', style: TextStyle(fontSize: 11, color: Colors.black45))
                else
                  SizedBox(
                    width: 90,
                    child: TextField(
                      controller: _controllerPara(os),
                      focusNode: _focusNodePara(os),
                      enabled: _puedeCargar && !guardandoEsta,
                      textAlign: TextAlign.right,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        isDense: true,
                        suffixText: '%',
                        hintText: '0',
                        hintStyle: TextStyle(color: Colors.grey[350]),
                      ),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
            if (guardandoEsta)
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Text('Guardando...', style: TextStyle(fontSize: 10, color: Colors.black45)),
              ),
            const SizedBox(height: 2),
            InkWell(
              onTap: () => _toggleHistorial(os),
              child: Text(
                expandido ? '▾ Ocultar historial' : '▸ Ver historial de avances',
                style: const TextStyle(fontSize: 11, color: Color(0xFF1B365D), fontWeight: FontWeight.w600),
              ),
            ),
            if (expandido) _buildHistorial(os),
          ],
        ),
      ),
    );
  }

  Widget _buildHistorial(ObraSubitem os) {
    if (_cargandoHistorial.contains(os.id)) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final historial = _historialPorObraSubitem[os.id] ?? [];
    if (historial.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 4),
        child: Text('Todavía no tiene avance certificado.', style: TextStyle(fontSize: 11, color: Colors.black45)),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: historial.map((item) {
          final esEsteBorrador = item.estadoCertificado == 'borrador';
          final texto = _puedeVerMontos
              ? 'Certificado N°${item.numeroCertificado}: ${_fmtEntrada(item.porcentajePeriodo)}% — ${_fmtMonto(item.montoPeriodo)}'
              : 'Certificado N°${item.numeroCertificado}: ${_fmtEntrada(item.porcentajePeriodo)}%';
          return Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              esEsteBorrador ? '$texto (en carga, sin emitir)' : texto,
              style: TextStyle(
                fontSize: 10.5,
                color: esEsteBorrador ? Colors.orange.shade800 : Colors.black54,
                fontStyle: esEsteBorrador ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  String _fmtMonto(double monto) {
    final valorInt = monto.round();
    final str = valorInt.toString();
    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    final formateado = str.replaceAllMapped(reg, (Match m) => '${m[1]}.');
    return '\$ $formateado';
  }
}
