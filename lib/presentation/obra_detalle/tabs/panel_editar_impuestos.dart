import 'package:flutter/material.dart';
import '../../../core/utils/parser_numero_ar.dart';
import '../../../data/models/obra_impuesto.dart';
import '../../../services/auth_service.dart';
import '../../../services/obra_impuestos_repository.dart';
import '../../../services/perfil_repository.dart';
import '../../shared/pro_gate_dialog.dart';

/// Edición de los 4 impuestos de la obra (última pieza del Factor K, ver conversación -- sin doc
/// nuevo en docs/ todavía para esta pieza puntual, se suma cuando se cierre). Panel aparte de
/// `PanelEditarFactorK` a propósito: tablas distintas (`obra_impuestos`, no
/// `obra_presupuesto_config`), conceptos distintos (obligación fiscal externa, no estructura de
/// costos del contratista) -- mismo motivo que ya separó el costo de mano de obra en dos ventanas
/// (`docs/costo_mano_de_obra_decisiones.md` §16), no repetir esa lección.
///
/// Gate de PRO al Guardar, no al abrir -- a diferencia de `PanelEditarFactorK`/`BloqueFactorK`
/// (gate en el botón "Editar", antes de abrir, ver §4 de `docs/factor_k_apu_decisiones.md`). Ahí la
/// excepción se justificaba porque el bloque de cabecera ya le mostraba a Free los conceptos
/// completos sin necesitar el panel -- esa justificación ya no aplica desde que Free dejó de ver
/// los conceptos/bases (ver `docs/monetizacion.md` §9), pero no se tocó el gate de ese botón acá
/// (no fue lo que se pidió esta vez). Este panel nuevo sigue el patrón general del resto de la app:
/// se abre para cualquiera, el chequeo real es en vivo recién al tocar "Guardar".
///
/// Carga los 4 `ObraImpuesto` al abrirse (no los recibe por constructor) -- mismo principio que
/// `PanelEditarFactorK`/`PanelParametrosCargasSociales`: no confiar en una foto vieja.
///
/// "Uno solo, no se borra" (ver diagnóstico): el cuarto impuesto es la fila `tipo = 'otro'` que ya
/// existe en la obra, nunca una fila nueva. Vaciar su nombre y dejar el porcentaje en 0 es la forma
/// de "sacarlo" -- no hay ningún botón de eliminar, ni falta.
class PanelEditarImpuestos extends StatefulWidget {
  final String obraId;

  const PanelEditarImpuestos({Key? key, required this.obraId}) : super(key: key);

  @override
  State<PanelEditarImpuestos> createState() => _PanelEditarImpuestosState();
}

class _PanelEditarImpuestosState extends State<PanelEditarImpuestos> {
  final ObraImpuestosRepository _impuestosRepository = ObraImpuestosRepository();
  final PerfilRepository _perfilRepository = PerfilRepository();
  final AuthService _authService = AuthService();

  // Límite de sanidad, no un valor legal exacto -- ver diagnóstico: no se ata a la lista cerrada de
  // alícuotas reales (que se desactualiza), es un techo generoso que nunca debería tocar un caso
  // legítimo (IVA reducido de construcción de vivienda es 10,5%) pero atrapa el error de tipeo
  // típico (210 en vez de 21).
  static const double _pctMaximo = 50;

  List<ObraImpuesto>? _impuestos;
  TextEditingController? _ivaController;
  TextEditingController? _iibbController;
  TextEditingController? _tasasController;
  TextEditingController? _otroNombreController;
  TextEditingController? _otroPctController;

  String? _error;
  bool _guardando = false;
  bool _verificandoPro = false;

  @override
  void initState() {
    super.initState();
    _cargarImpuestos();
  }

  Future<void> _cargarImpuestos() async {
    final impuestos = await _impuestosRepository.getImpuestos(widget.obraId);
    if (!mounted) return;
    ObraImpuesto porTipo(TipoImpuesto tipo) => impuestos.firstWhere((i) => i.tipo == tipo);
    setState(() {
      _impuestos = impuestos;
      _ivaController = TextEditingController(text: _fmtEntrada(porTipo(TipoImpuesto.iva).porcentaje));
      _iibbController = TextEditingController(text: _fmtEntrada(porTipo(TipoImpuesto.iibb).porcentaje));
      _tasasController =
          TextEditingController(text: _fmtEntrada(porTipo(TipoImpuesto.tasasMunicipales).porcentaje));
      final otro = porTipo(TipoImpuesto.otro);
      _otroNombreController = TextEditingController(text: otro.nombreOtro ?? '');
      _otroPctController = TextEditingController(text: _fmtEntrada(otro.porcentaje));
    });
  }

  @override
  void dispose() {
    _ivaController?.dispose();
    _iibbController?.dispose();
    _tasasController?.dispose();
    _otroNombreController?.dispose();
    _otroPctController?.dispose();
    super.dispose();
  }

  String _fmtEntrada(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  /// `null` si algo no valida -- ya dejó el mensaje en `_error` antes de retornar.
  ({double iva, double iibb, double tasas, double otroPct, String? otroNombre})? _validar() {
    final iva = ParserNumeroAr.parsear(_ivaController!.text);
    final iibb = ParserNumeroAr.parsear(_iibbController!.text);
    final tasas = ParserNumeroAr.parsear(_tasasController!.text);
    final otroPct = ParserNumeroAr.parsear(_otroPctController!.text);
    final otroNombre = _otroNombreController!.text.trim();

    if (iva == null || iva < 0 || iva > _pctMaximo) {
      setState(() => _error = 'IVA inválido (0 a $_pctMaximo%).');
      return null;
    }
    if (iibb == null || iibb < 0 || iibb > _pctMaximo) {
      setState(() => _error = 'Ingresos Brutos inválido (0 a $_pctMaximo%).');
      return null;
    }
    if (tasas == null || tasas < 0 || tasas > _pctMaximo) {
      setState(() => _error = 'Tasas Municipales inválido (0 a $_pctMaximo%).');
      return null;
    }
    if (otroPct == null || otroPct < 0 || otroPct > _pctMaximo) {
      setState(() => _error = 'El cuarto impuesto tiene un porcentaje inválido (0 a $_pctMaximo%).');
      return null;
    }
    // Un porcentaje > 0 sin nombre es exactamente el problema que esta pieza vino a resolver (la
    // línea "Otro" que no explicaba nada en el presupuesto) -- no se guarda así.
    if (otroPct > 0 && otroNombre.isEmpty) {
      setState(() => _error = 'Si cargás un porcentaje para el cuarto impuesto, ponele un nombre.');
      return null;
    }
    setState(() => _error = null);
    return (iva: iva, iibb: iibb, tasas: tasas, otroPct: otroPct, otroNombre: otroNombre);
  }

  Future<void> _onGuardar() async {
    final valores = _validar();
    if (valores == null) return;

    final usuarioId = _authService.usuarioActual?.id;
    setState(() => _verificandoPro = true);
    final esProAhora = usuarioId != null ? await _perfilRepository.esPro(usuarioId) : false;
    if (!mounted) return;
    setState(() => _verificandoPro = false);

    if (!esProAhora) {
      await mostrarDialogoFuncionPro(context, mensaje: 'Editar los porcentajes de impuestos es una función PRO.');
      return;
    }

    final impuestos = _impuestos!;
    ObraImpuesto porTipo(TipoImpuesto tipo) => impuestos.firstWhere((i) => i.tipo == tipo);

    setState(() => _guardando = true);
    try {
      await Future.wait([
        _impuestosRepository.actualizarPorcentaje(id: porTipo(TipoImpuesto.iva).id, porcentaje: valores.iva),
        _impuestosRepository.actualizarPorcentaje(id: porTipo(TipoImpuesto.iibb).id, porcentaje: valores.iibb),
        _impuestosRepository.actualizarPorcentaje(
          id: porTipo(TipoImpuesto.tasasMunicipales).id,
          porcentaje: valores.tasas,
        ),
        _impuestosRepository.actualizarOtro(
          id: porTipo(TipoImpuesto.otro).id,
          porcentaje: valores.otroPct,
          nombreOtro: valores.otroNombre,
        ),
      ]);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _error = 'No se pudo guardar. Probá de nuevo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_impuestos == null) {
      return AlertDialog(
        title: const Text('Editar impuestos', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        content: const SizedBox(height: 80, child: Center(child: CircularProgressIndicator())),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar'))],
      );
    }

    final ocupado = _guardando || _verificandoPro;
    return AlertDialog(
      title: const Text('Editar impuestos', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Toda la obra — cada uno se aplica sobre el Costo Total del Trabajo de cada partida.',
              style: TextStyle(fontSize: 11, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            _buildCampoPct('IVA (%)', _ivaController!),
            _buildCampoPct('Ingresos Brutos (%)', _iibbController!),
            _buildCampoPct('Tasas Municipales (%)', _tasasController!),
            const Divider(height: 20),
            const Text(
              'Cuarto impuesto (opcional) — nombralo para que se entienda en el presupuesto.',
              style: TextStyle(fontSize: 11, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _otroNombreController,
              maxLength: 40,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                labelStyle: TextStyle(fontSize: 11),
                isDense: true,
                counterText: '',
              ),
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            _buildCampoPct('Porcentaje (%)', _otroPctController!),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(fontSize: 11, color: Colors.red)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: ocupado ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        TextButton(
          onPressed: ocupado ? null : _onGuardar,
          child: Text(_verificandoPro ? 'Verificando...' : (_guardando ? 'Guardando...' : 'Guardar')),
        ),
      ],
    );
  }

  Widget _buildCampoPct(String label, TextEditingController controller) {
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
