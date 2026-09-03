import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../data/models/obra_presupuesto_config.dart';
import '../../../services/auth_service.dart';
import '../../../services/obra_presupuesto_config_repository.dart';
import '../../../services/perfil_repository.dart';
import '../../shared/pro_gate_dialog.dart';
import 'panel_editar_factor_k.dart';

/// Bloque de cabecera de la Solapa APU (Paso A — ver docs/factor_k_apu_decisiones.md) — plegable,
/// primer elemento debajo del selector de tipo de presupuesto. Muestra los 6 conceptos del Factor
/// K con su % y su base explicada en texto, **nunca un monto**: no existe un Costo-Costo único de
/// la obra (cada partida tiene el suyo), así que un monto acá sería inventado — ver §1 del doc.
///
/// Plegable con persistencia por obra en SharedPreferences, mismo mecanismo que el aviso de orden
/// de `rubros_tab.dart` — no un mecanismo nuevo. Empieza desplegado (fail-closed hacia mostrar la
/// información, no hacia ocultarla).
class BloqueFactorK extends StatefulWidget {
  final String obraId;

  const BloqueFactorK({Key? key, required this.obraId}) : super(key: key);

  @override
  State<BloqueFactorK> createState() => _BloqueFactorKState();
}

class _BloqueFactorKState extends State<BloqueFactorK> {
  final ObraPresupuestoConfigRepository _configRepository = ObraPresupuestoConfigRepository();
  final PerfilRepository _perfilRepository = PerfilRepository();
  final AuthService _authService = AuthService();

  bool _cargando = true;
  ObraPresupuestoConfig? _config;
  // Cargado junto con la config, solo para pintar el ícono PRO del botón "Editar" — la decisión
  // real de si se puede guardar se vuelve a verificar en vivo en _onEditar, nunca contra esto.
  bool _esPro = false;
  bool _plegado = false;
  bool _verificandoPro = false;

  String get _clavePlegado => 'factor_k_bloque_plegado_${widget.obraId}';

  @override
  void initState() {
    super.initState();
    _cargar();
    _cargarPlegado();
  }

  Future<void> _cargar() async {
    final usuarioId = _authService.usuarioActual?.id;
    final configFuture = _configRepository.getConfig(widget.obraId);
    final esProFuture = usuarioId != null ? _perfilRepository.esPro(usuarioId) : Future.value(false);

    final config = await configFuture;
    final esPro = await esProFuture;
    if (!mounted) return;
    setState(() {
      _config = config;
      _esPro = esPro;
      _cargando = false;
    });
  }

  Future<void> _cargarPlegado() async {
    final prefs = await SharedPreferences.getInstance();
    final plegado = prefs.getBool(_clavePlegado) ?? false;
    if (!mounted) return;
    setState(() => _plegado = plegado);
  }

  Future<void> _alternarPlegado() async {
    final nuevo = !_plegado;
    setState(() => _plegado = nuevo);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_clavePlegado, nuevo);
  }

  /// Gate en el botón, antes de abrir — no al abrir el panel, a diferencia del de cargas sociales
  /// de mano de obra. Ahí el panel es la única forma de que Free vea los parámetros; acá Free ya
  /// ve todo en este mismo bloque, el panel no agrega información, solo la capacidad de editar.
  /// Ver docs/factor_k_apu_decisiones.md §4 para el razonamiento completo.
  Future<void> _onEditar() async {
    final usuarioId = _authService.usuarioActual?.id;
    setState(() => _verificandoPro = true);
    final esProAhora = usuarioId != null ? await _perfilRepository.esPro(usuarioId) : false;
    if (!mounted) return;
    setState(() => _verificandoPro = false);

    if (!esProAhora) {
      await mostrarDialogoFuncionPro(context, mensaje: 'Editar el Factor K es una función PRO.');
      return;
    }

    final guardado = await showDialog<bool>(
      context: context,
      builder: (_) => PanelEditarFactorK(obraId: widget.obraId),
    );
    if (guardado == true) await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando || _config == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final config = _config!;
    final sinMateriales = config.tipoPresupuesto == TipoPresupuesto.manoObraSola;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: _alternarPlegado,
            child: Row(
              children: [
                const Icon(Icons.percent, size: 16, color: Color(0xFF1B365D)),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Factor K y estructura de costos',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1B365D)),
                  ),
                ),
                Icon(_plegado ? Icons.expand_more : Icons.expand_less, size: 18, color: Colors.black45),
              ],
            ),
          ),
          if (!_plegado) ...[
            const SizedBox(height: 8),
            _buildLinea('Gastos Generales', config.ggPct, 'Costo-Costo'),
            _buildLinea('Imprevistos', config.imprevistosPct, 'Costo-Costo + GG'),
            _buildLinea('EPP-Seguridad', config.eppPct, 'Costo-Costo + GG + Imprevistos'),
            _buildLinea('Costo Financiero', config.costoFinancieroPct, 'Costo-Costo + GG + Imprevistos + EPP'),
            _buildLinea('Beneficio', config.beneficioPct, 'todo lo anterior'),
            if (sinMateriales) ...[
              _buildLinea(
                'Gestión de materiales de terceros',
                config.gestionMaterialesTercerosPct,
                'Materiales de la vista con materiales',
              ),
              const SizedBox(height: 4),
              const Text(
                'Gastos Generales, EPP-Seguridad y Costo Financiero se aplican igual que en '
                'Materiales + Mano de obra — no dependen de quién compra los materiales.',
                style: TextStyle(fontSize: 9, color: Colors.black45),
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _verificandoPro ? null : _onEditar,
                icon: !_esPro
                    ? const Icon(Icons.workspace_premium, size: 14, color: Colors.amber)
                    : const SizedBox.shrink(),
                label: Text(_verificandoPro ? 'Verificando...' : 'Editar'),
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLinea(String concepto, double pct, String base) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$concepto — ${_fmtPct(pct)}% ',
              style: const TextStyle(fontSize: 11, color: Colors.black87),
            ),
            TextSpan(
              text: 'sobre $base',
              style: const TextStyle(fontSize: 10, color: Colors.black45),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtPct(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2).replaceAll('.', ',');
}
