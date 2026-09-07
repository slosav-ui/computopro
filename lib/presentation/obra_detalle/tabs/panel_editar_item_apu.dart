import 'package:flutter/material.dart';
import '../../../core/utils/parser_numero_ar.dart';
import '../../../data/models/apu_composicion_item_detalle.dart';
import '../../../services/apu_composiciones_repository.dart';
import '../../../services/auth_service.dart';
import '../../../services/perfil_repository.dart';
import '../../shared/pro_gate_dialog.dart';

/// Edición de una línea de la composición de APU — rendimiento y precio, los dos editables por
/// PRO en el mismo diálogo (ver `personalizar_item_apu`, reescrita en
/// `0072_edicion_apu_correcciones.sql`). Ya no ofrece cambiar qué insumo lleva la línea (eso queda
/// reemplazado por agregar/quitar material, ver `ComposicionApuScreen`) — corrección sobre la
/// primera versión de este panel, que sí tenía un selector de swap.
///
/// Gate de PRO al Guardar, no al abrir — mismo patrón que `PanelParametrosCargasSociales`: cualquiera
/// puede abrir este diálogo y ver los campos, el chequeo real de `esPro` pasa recién al tocar
/// Guardar.
///
/// Devuelve por `Navigator.pop`: `null` si se cancela, o la receta completa ya actualizada
/// (`List<ApuComposicionItemDetalle>`) si se guardó — la propia función de base la devuelve, así
/// que `ComposicionApuScreen` no necesita pedirla de nuevo.
class PanelEditarItemApu extends StatefulWidget {
  final String obraId;
  final String subitemId;
  final ApuComposicionItemDetalle item;

  const PanelEditarItemApu({
    Key? key,
    required this.obraId,
    required this.subitemId,
    required this.item,
  }) : super(key: key);

  @override
  State<PanelEditarItemApu> createState() => _PanelEditarItemApuState();
}

class _PanelEditarItemApuState extends State<PanelEditarItemApu> {
  final ApuComposicionesRepository _composicionesRepository = ApuComposicionesRepository();
  final PerfilRepository _perfilRepository = PerfilRepository();
  final AuthService _authService = AuthService();

  late final TextEditingController _rendimientoController;
  late final TextEditingController _precioController;

  String? _error;
  bool _guardando = false;
  bool _verificandoPro = false;

  @override
  void initState() {
    super.initState();
    _rendimientoController = TextEditingController(text: _formatearRendimiento(widget.item.rendimiento));
    _precioController = TextEditingController(
      text: widget.item.precioUnitario != null ? widget.item.precioUnitario!.toStringAsFixed(2) : '',
    );
    _precioController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _rendimientoController.dispose();
    _precioController.dispose();
    super.dispose();
  }

  String _formatearRendimiento(double valor) {
    return valor == valor.roundToDouble() ? valor.toInt().toString() : valor.toString();
  }

  /// El precio "cambió" si el valor tipeado difiere del original (con tolerancia) — determina si
  /// se muestra el aviso de alcance y si se manda `precioNuevo` al guardar. Dejar el campo vacío
  /// nunca cuenta como cambio (no hay forma de "borrar" el precio desde acá).
  bool get _precioCambio {
    final texto = _precioController.text.trim();
    if (texto.isEmpty) return false;
    final valor = ParserNumeroAr.parsear(texto);
    if (valor == null) return false;
    final original = widget.item.precioUnitario;
    return original == null || (valor - original).abs() > 0.001;
  }

  Future<void> _onGuardar() async {
    final rendimientoNuevo = ParserNumeroAr.parsear(_rendimientoController.text);
    if (rendimientoNuevo == null || rendimientoNuevo < 0) {
      setState(() => _error = 'Rendimiento inválido. Ingresá un número mayor o igual a 0.');
      return;
    }

    double? precioNuevo;
    if (_precioCambio) {
      precioNuevo = ParserNumeroAr.parsear(_precioController.text);
      if (precioNuevo == null || precioNuevo < 0) {
        setState(() => _error = 'Precio inválido. Ingresá un número mayor o igual a 0.');
        return;
      }
    }

    final usuarioId = _authService.usuarioActual?.id;
    setState(() {
      _error = null;
      _verificandoPro = true;
    });
    final esProAhora = usuarioId != null ? await _perfilRepository.esPro(usuarioId) : false;
    if (!mounted) return;
    setState(() => _verificandoPro = false);

    if (!esProAhora) {
      await mostrarDialogoFuncionPro(context, mensaje: 'Editar la composición de APU es una función PRO.');
      return;
    }

    setState(() => _guardando = true);
    try {
      final recetaActualizada = await _composicionesRepository.personalizarItem(
        obraId: widget.obraId,
        subitemId: widget.subitemId,
        insumoId: widget.item.insumoId,
        rendimientoNuevo: rendimientoNuevo,
        precioNuevo: precioNuevo,
      );
      if (!mounted) return;
      Navigator.pop(context, recetaActualizada);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _error = 'No se pudo guardar el cambio. Probá de nuevo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.item.insumoNombre,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1B365D)),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _rendimientoController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Rendimiento',
                suffixText: widget.item.insumoUnidad.toUpperCase(),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _precioController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Precio unitario',
                prefixText: '\$ ',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (_precioCambio) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber[50],
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.amber[200]!),
                ),
                child: Text(
                  'Este precio no se guarda solo acá: se guarda en Mat y MO y va a aplicarse a '
                  'todas las partidas de esta obra que usan ${widget.item.insumoNombre.toLowerCase()}, '
                  'no solo esta. Y es solo para esta obra — el rendimiento, en cambio, es tuyo: te '
                  'queda guardado para todas tus obras futuras.',
                  style: const TextStyle(fontSize: 11, color: Colors.black87),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: (_guardando || _verificandoPro) ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: (_guardando || _verificandoPro) ? null : _onGuardar,
          child: (_guardando || _verificandoPro)
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(_verificandoPro ? 'Verificando...' : 'Guardar'),
        ),
      ],
    );
  }
}
