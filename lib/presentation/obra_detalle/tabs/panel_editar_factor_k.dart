import 'package:flutter/material.dart';
import '../../../core/utils/parser_numero_ar.dart';
import '../../../data/models/obra_presupuesto_config.dart';
import '../../../services/obra_presupuesto_config_repository.dart';

/// Edición del Factor K (Paso A — ver docs/factor_k_apu_decisiones.md §5). Se abre ya con el gate
/// de PRO resuelto por `BloqueFactorK._onEditar` — este panel no vuelve a chequearlo, asume que
/// quien lo abrió ya tiene permiso.
///
/// Carga su propia config al abrirse (no la recibe por constructor) — mismo principio que
/// `PanelParametrosCargasSociales`: no confiar en una foto que otro widget ya tenía, pedir el dato
/// en el momento en que importa.
///
/// Carga los 6 valores siempre, aunque solo muestre 5 en modo "Materiales + Mano de obra" — el 6to
/// (Gestión de materiales de terceros) viaja igual en el Guardar, con el valor que ya tenía, para
/// no pisarlo con un default por no haberse mostrado en pantalla (ver §5 del doc).
class PanelEditarFactorK extends StatefulWidget {
  final String obraId;

  const PanelEditarFactorK({Key? key, required this.obraId}) : super(key: key);

  @override
  State<PanelEditarFactorK> createState() => _PanelEditarFactorKState();
}

class _PanelEditarFactorKState extends State<PanelEditarFactorK> {
  final ObraPresupuestoConfigRepository _configRepository = ObraPresupuestoConfigRepository();

  ObraPresupuestoConfig? _config;
  TextEditingController? _ggController;
  TextEditingController? _imprevistosController;
  TextEditingController? _eppController;
  TextEditingController? _costoFinancieroController;
  TextEditingController? _beneficioController;
  TextEditingController? _gestionController;

  String? _error;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargarConfig();
  }

  Future<void> _cargarConfig() async {
    final config = await _configRepository.getConfig(widget.obraId);
    if (!mounted) return;
    setState(() {
      _config = config;
      _ggController = TextEditingController(text: _fmtEntrada(config.ggPct));
      _imprevistosController = TextEditingController(text: _fmtEntrada(config.imprevistosPct));
      _eppController = TextEditingController(text: _fmtEntrada(config.eppPct));
      _costoFinancieroController = TextEditingController(text: _fmtEntrada(config.costoFinancieroPct));
      _beneficioController = TextEditingController(text: _fmtEntrada(config.beneficioPct));
      _gestionController = TextEditingController(text: _fmtEntrada(config.gestionMaterialesTercerosPct));
    });
  }

  @override
  void dispose() {
    _ggController?.dispose();
    _imprevistosController?.dispose();
    _eppController?.dispose();
    _costoFinancieroController?.dispose();
    _beneficioController?.dispose();
    _gestionController?.dispose();
    super.dispose();
  }

  String _fmtEntrada(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  Map<String, double>? _validar() {
    final gg = ParserNumeroAr.parsear(_ggController!.text);
    final imprevistos = ParserNumeroAr.parsear(_imprevistosController!.text);
    final epp = ParserNumeroAr.parsear(_eppController!.text);
    final costoFinanciero = ParserNumeroAr.parsear(_costoFinancieroController!.text);
    final beneficio = ParserNumeroAr.parsear(_beneficioController!.text);
    final gestion = ParserNumeroAr.parsear(_gestionController!.text);

    if (gg == null || gg < 0) {
      setState(() => _error = 'Gastos Generales inválido');
      return null;
    }
    if (imprevistos == null || imprevistos < 0) {
      setState(() => _error = 'Imprevistos inválido');
      return null;
    }
    if (epp == null || epp < 0) {
      setState(() => _error = 'EPP-Seguridad inválido');
      return null;
    }
    if (costoFinanciero == null || costoFinanciero < 0) {
      setState(() => _error = 'Costo Financiero inválido');
      return null;
    }
    if (beneficio == null || beneficio < 0) {
      setState(() => _error = 'Beneficio inválido');
      return null;
    }
    if (gestion == null || gestion < 0) {
      setState(() => _error = 'Gestión de materiales de terceros inválida');
      return null;
    }
    setState(() => _error = null);
    return {
      'gg': gg,
      'imprevistos': imprevistos,
      'epp': epp,
      'costoFinanciero': costoFinanciero,
      'beneficio': beneficio,
      'gestion': gestion,
    };
  }

  Future<void> _onGuardar() async {
    final valores = _validar();
    if (valores == null) return;

    setState(() => _guardando = true);
    try {
      await _configRepository.actualizarFactorK(
        obraId: widget.obraId,
        ggPct: valores['gg']!,
        imprevistosPct: valores['imprevistos']!,
        eppPct: valores['epp']!,
        costoFinancieroPct: valores['costoFinanciero']!,
        beneficioPct: valores['beneficio']!,
        gestionMaterialesTercerosPct: valores['gestion']!,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _error = 'No se pudo guardar.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    if (config == null) {
      return AlertDialog(
        title: const Text('Editar Factor K', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        content: const SizedBox(height: 80, child: Center(child: CircularProgressIndicator())),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar'))],
      );
    }
    final sinMateriales = config.tipoPresupuesto == TipoPresupuesto.manoObraSola;

    return AlertDialog(
      title: const Text('Editar Factor K', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Toda la obra — afecta el cálculo de todas las partidas.',
              style: TextStyle(fontSize: 11, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            _buildCampo('Gastos Generales (%)', _ggController!),
            _buildCampo('Imprevistos (%)', _imprevistosController!),
            _buildCampo('EPP-Seguridad (%)', _eppController!),
            _buildCampo('Costo Financiero (%)', _costoFinancieroController!),
            _buildCampo('Beneficio (%)', _beneficioController!),
            if (sinMateriales)
              _buildCampo('Gestión de materiales de terceros (%)', _gestionController!),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(_error!, style: const TextStyle(fontSize: 11, color: Colors.red)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _guardando ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        TextButton(
          onPressed: _guardando ? null : _onGuardar,
          child: Text(_guardando ? 'Guardando...' : 'Guardar'),
        ),
      ],
    );
  }

  Widget _buildCampo(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, labelStyle: const TextStyle(fontSize: 11), isDense: true),
        style: const TextStyle(fontSize: 12),
      ),
    );
  }
}
