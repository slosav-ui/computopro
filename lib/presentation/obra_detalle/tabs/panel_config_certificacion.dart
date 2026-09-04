import 'package:flutter/material.dart';
import '../../../core/utils/parser_numero_ar.dart';
import '../../../data/models/obra_config_certificacion.dart';
import '../../../services/obra_config_certificacion_repository.dart';

/// Configuración de certificación de la obra — Modelo A/B, plazo de pago, anticipo, fondo de
/// reparo y la carga inicial de monto total contratado (Modelo B). Ver
/// docs/modelos_certificacion_diseno_datos.md y docs/certificados_ciclo_vida_diseno_datos.md.
///
/// Gratis para todos — Gestión de Obra no tiene gate de PRO, decisión de negocio (si un actor de
/// la cadena no puede usarla por no pagar, se rompe para todos). El gate acá es de ROL: solo
/// `admin_maestro` edita. [puedeEditar] lo decide quien abre este panel (`GestionObraTab`, contra
/// `UserContext.puedeEditarConfigCertificacion`) — este widget no vuelve a chequearlo, confía en
/// el valor recibido. Todos los miembros de la obra pueden abrir el panel y ver la config igual;
/// quien no es `admin_maestro` la ve de solo lectura — mismo criterio de "gatear la acción, no
/// ocultar la función" que ya usa el resto del proyecto, aplicado acá a rol en vez de a plan.
class PanelConfigCertificacion extends StatefulWidget {
  final String obraId;
  final bool puedeEditar;

  const PanelConfigCertificacion({
    Key? key,
    required this.obraId,
    required this.puedeEditar,
  }) : super(key: key);

  @override
  State<PanelConfigCertificacion> createState() => _PanelConfigCertificacionState();
}

class _PanelConfigCertificacionState extends State<PanelConfigCertificacion> {
  final ObraConfigCertificacionRepository _repository = ObraConfigCertificacionRepository();

  ObraConfigCertificacion? _config;
  ModeloCertificacion _modeloSeleccionado = ModeloCertificacion.avanceMedido;
  TextEditingController? _diasPlazoPagoController;
  TextEditingController? _anticipoController;
  TextEditingController? _fondoReparoController;
  TextEditingController? _montoTotalContratadoController;

  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarConfig();
  }

  Future<void> _cargarConfig() async {
    final config = await _repository.getConfig(widget.obraId);
    if (!mounted) return;
    setState(() {
      _config = config;
      _modeloSeleccionado = config.modeloCertificacion;
      _diasPlazoPagoController =
          TextEditingController(text: config.diasPlazoPagoCertificados?.toString() ?? '');
      _anticipoController = TextEditingController(text: _fmtEntrada(config.anticipoPct));
      _fondoReparoController = TextEditingController(text: _fmtEntrada(config.fondoReparoPct));
      _montoTotalContratadoController =
          TextEditingController(text: _fmtEntrada(config.montoTotalContratado));
    });
  }

  @override
  void dispose() {
    _diasPlazoPagoController?.dispose();
    _anticipoController?.dispose();
    _fondoReparoController?.dispose();
    _montoTotalContratadoController?.dispose();
    super.dispose();
  }

  String _fmtEntrada(double? v) {
    if (v == null) return '';
    return v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
  }

  /// Devuelve los valores validados, o `null` si hay un error (ya seteado en `_error`).
  /// `montoTotalContratado` viene `null` en el resultado si no correspondía cargarlo (ya tenía
  /// valor) o si el campo quedó vacío — en ninguno de los dos casos se intenta guardar.
  Map<String, dynamic>? _validar() {
    final dias = ParserNumeroAr.parsear(_diasPlazoPagoController!.text);
    final anticipo = ParserNumeroAr.parsear(_anticipoController!.text);
    final fondoReparo = ParserNumeroAr.parsear(_fondoReparoController!.text);

    if (dias == null || dias <= 0) {
      setState(() => _error = 'Plazo de pago inválido.');
      return null;
    }
    if (anticipo == null || anticipo < 0 || anticipo > 100) {
      setState(() => _error = 'Anticipo inválido — tiene que ser un porcentaje entre 0 y 100.');
      return null;
    }
    if (fondoReparo == null || fondoReparo < 0 || fondoReparo > 100) {
      setState(() => _error = 'Fondo de reparo inválido — tiene que ser un porcentaje entre 0 y 100.');
      return null;
    }

    double? montoTotalContratado;
    if (_config!.montoTotalContratado == null) {
      final montoTexto = _montoTotalContratadoController!.text.trim();
      if (montoTexto.isNotEmpty) {
        final monto = ParserNumeroAr.parsear(montoTexto);
        if (monto == null || monto <= 0) {
          setState(() => _error = 'Monto total contratado inválido.');
          return null;
        }
        montoTotalContratado = monto;
      }
    }

    setState(() => _error = null);
    return {
      'dias': dias.toInt(),
      'anticipo': anticipo,
      'fondoReparo': fondoReparo,
      'montoTotalContratado': montoTotalContratado,
    };
  }

  Future<void> _onGuardar() async {
    final validado = _validar();
    if (validado == null) return;

    setState(() => _guardando = true);
    try {
      await _repository.actualizarConfig(
        obraId: widget.obraId,
        modeloCertificacion: _modeloSeleccionado,
        diasPlazoPagoCertificados: validado['dias'] as int,
        anticipoPct: validado['anticipo'] as double,
        fondoReparoPct: validado['fondoReparo'] as double,
      );
      final montoTotalContratado = validado['montoTotalContratado'] as double?;
      if (montoTotalContratado != null) {
        await _repository.actualizarMontoTotalContratadoInicial(
          obraId: widget.obraId,
          montoTotalContratado: montoTotalContratado,
        );
      }
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
        title: const Text('Configuración de certificación', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        content: const SizedBox(height: 80, child: Center(child: CircularProgressIndicator())),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
      );
    }

    final soloLectura = !widget.puedeEditar;
    final diasController = _diasPlazoPagoController!;
    final anticipoController = _anticipoController!;
    final fondoReparoController = _fondoReparoController!;

    return AlertDialog(
      title: const Text('Configuración de certificación', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (soloLectura)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Solo el administrador de la obra puede editar esta configuración.',
                  style: TextStyle(fontSize: 11, color: Colors.black54),
                ),
              ),
            const Text('Modelo de certificación', style: TextStyle(fontSize: 11, color: Colors.black87)),
            RadioListTile<ModeloCertificacion>(
              dense: true,
              contentPadding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              title: const Text('Avance Medido', style: TextStyle(fontSize: 11)),
              value: ModeloCertificacion.avanceMedido,
              groupValue: _modeloSeleccionado,
              onChanged: soloLectura ? null : (v) => setState(() => _modeloSeleccionado = v!),
            ),
            RadioListTile<ModeloCertificacion>(
              dense: true,
              contentPadding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              title: const Text('Hitos de Precio Cerrado', style: TextStyle(fontSize: 11)),
              value: ModeloCertificacion.hitosPrecioCerrado,
              groupValue: _modeloSeleccionado,
              onChanged: soloLectura ? null : (v) => setState(() => _modeloSeleccionado = v!),
            ),
            const SizedBox(height: 8),
            _buildCampo(label: 'Plazo de pago (días)', controller: diasController, habilitado: !soloLectura),
            _buildCampo(label: 'Anticipo (%)', controller: anticipoController, habilitado: !soloLectura),
            _buildCampo(label: 'Fondo de reparo (%)', controller: fondoReparoController, habilitado: !soloLectura),
            const SizedBox(height: 4),
            _buildCampoMontoTotalContratado(config, soloLectura),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(_error!, style: const TextStyle(fontSize: 11, color: Colors.red)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
        if (!soloLectura)
          TextButton(
            onPressed: _guardando ? null : _onGuardar,
            child: Text(_guardando ? 'Guardando...' : 'Guardar'),
          ),
      ],
    );
  }

  Widget _buildCampo({required String label, required TextEditingController controller, required bool habilitado}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        enabled: habilitado,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, labelStyle: const TextStyle(fontSize: 11), isDense: true),
        style: const TextStyle(fontSize: 12),
      ),
    );
  }

  /// Editable solo mientras `montoTotalContratado` todavía es `null` — una vez cargado, de solo
  /// lectura acá: el cambio pasa por Modificaciones de Obra con aprobación (§7.7-bis), sin UI
  /// todavía. La guarda real está en la consulta del repositorio; acá solo se refleja para no
  /// ofrecer un campo editable que después la base va a rechazar.
  Widget _buildCampoMontoTotalContratado(ObraConfigCertificacion config, bool soloLectura) {
    if (config.montoTotalContratado != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          'Monto total contratado: ${_montoTotalContratadoController!.text} — ya cargado, el '
          'cambio requiere el circuito de Modificaciones de Obra (todavía sin pantalla propia).',
          style: const TextStyle(fontSize: 11, color: Colors.black54),
        ),
      );
    }
    return _buildCampo(
      label: 'Monto total contratado (Hitos de Precio Cerrado) — opcional',
      controller: _montoTotalContratadoController!,
      habilitado: !soloLectura,
    );
  }
}
