import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/utils/parser_numero_ar.dart';
import '../../../data/models/apu_composicion_item_detalle.dart';
import '../../../data/models/insumo_busqueda.dart';
import '../../../services/apu_composiciones_repository.dart';
import '../../../services/auth_service.dart';
import '../../../services/insumos_repository.dart';
import '../../../services/perfil_repository.dart';
import '../../shared/pro_gate_dialog.dart';

/// Edición de una línea de la composición de APU (ver `personalizar_item_apu`,
/// 0071_personalizacion_apu_pro.sql) — primera pieza de "edición de APU en la Solapa APU".
/// Siempre edita el rendimiento; si la línea es un material, además permite reemplazar qué
/// insumo lleva esa línea (el caso "ladrillo común -> ladrillón" de Seba). Mano de obra y equipos
/// solo editan rendimiento, sin selector de insumo — decisión explícita, no una limitación
/// técnica (la función de base admite cualquier tipo_componente).
///
/// Gate de PRO al Guardar, no al abrir — mismo patrón que `PanelParametrosCargasSociales`, no el
/// de `BloqueFactorK` (que gatea antes de abrir): cualquiera puede abrir este diálogo y ver el
/// campo, el chequeo real de `esPro` pasa recién al tocar Guardar.
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
  final InsumosRepository _insumosRepository = InsumosRepository();
  final PerfilRepository _perfilRepository = PerfilRepository();
  final AuthService _authService = AuthService();

  late final TextEditingController _rendimientoController;
  final TextEditingController _busquedaController = TextEditingController();
  Timer? _debounceBusqueda;

  bool get _esMaterial => widget.item.tipoComponente == 'material';

  // Insumo elegido para reemplazar al actual -- null mientras no se cambió nada (se guarda solo
  // el rendimiento, mismo insumo de siempre).
  InsumoBusqueda? _insumoSeleccionado;
  bool _buscando = false;
  bool _cargandoBusqueda = false;
  List<InsumoBusqueda> _resultados = [];

  String? _error;
  bool _guardando = false;
  bool _verificandoPro = false;

  @override
  void initState() {
    super.initState();
    _rendimientoController = TextEditingController(text: _formatearRendimiento(widget.item.rendimiento));
  }

  @override
  void dispose() {
    _rendimientoController.dispose();
    _busquedaController.dispose();
    _debounceBusqueda?.cancel();
    super.dispose();
  }

  String _formatearRendimiento(double valor) {
    return valor == valor.roundToDouble() ? valor.toInt().toString() : valor.toString();
  }

  void _onBuscarCambiado(String texto) {
    _debounceBusqueda?.cancel();
    if (texto.trim().isEmpty) {
      setState(() => _resultados = []);
      return;
    }
    _debounceBusqueda = Timer(const Duration(milliseconds: 300), () async {
      setState(() => _cargandoBusqueda = true);
      try {
        final resultados = await _insumosRepository.buscarMateriales(texto);
        if (!mounted) return;
        setState(() {
          _resultados = resultados;
          _cargandoBusqueda = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() => _cargandoBusqueda = false);
      }
    });
  }

  void _elegirInsumo(InsumoBusqueda insumo) {
    setState(() {
      _insumoSeleccionado = insumo;
      _buscando = false;
      _resultados = [];
      _busquedaController.clear();
    });
  }

  Future<void> _onGuardar() async {
    final rendimientoNuevo = ParserNumeroAr.parsear(_rendimientoController.text);
    if (rendimientoNuevo == null || rendimientoNuevo < 0) {
      setState(() => _error = 'Rendimiento inválido. Ingresá un número mayor o igual a 0.');
      return;
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
        itemId: widget.item.itemId,
        rendimientoNuevo: rendimientoNuevo,
        insumoIdNuevo: _insumoSeleccionado?.id,
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
      title: const Text(
        'Editar línea de la receta',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1B365D)),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildBloqueInsumo(),
            const SizedBox(height: 14),
            TextField(
              controller: _rendimientoController,
              autofocus: !_esMaterial,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Rendimiento',
                suffixText: (_insumoSeleccionado?.unidad ?? widget.item.insumoUnidad).toUpperCase(),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
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

  Widget _buildBloqueInsumo() {
    final nombreActual = _insumoSeleccionado?.nombre ?? widget.item.insumoNombre;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                nombreActual,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            // Solo materiales pueden cambiar de insumo -- mano de obra y equipos solo editan
            // rendimiento (decisión explícita, no limitación de la función de base).
            if (_esMaterial && !_buscando)
              TextButton(
                onPressed: () => setState(() => _buscando = true),
                child: const Text('Cambiar', style: TextStyle(fontSize: 12)),
              ),
          ],
        ),
        if (_insumoSeleccionado != null && !_buscando)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'Reemplaza a "${widget.item.insumoNombre}"',
              style: const TextStyle(fontSize: 11, color: Colors.black45),
            ),
          ),
        if (_buscando) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _busquedaController,
            autofocus: true,
            onChanged: _onBuscarCambiado,
            decoration: InputDecoration(
              hintText: 'Buscar material...',
              isDense: true,
              border: const OutlineInputBorder(),
              suffixIcon: _cargandoBusqueda
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() {
                        _buscando = false;
                        _resultados = [];
                        _busquedaController.clear();
                      }),
                    ),
            ),
          ),
          if (_resultados.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 4),
              constraints: const BoxConstraints(maxHeight: 160),
              decoration: BoxDecoration(border: Border.all(color: Colors.black12)),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _resultados.length,
                itemBuilder: (context, index) {
                  final insumo = _resultados[index];
                  return ListTile(
                    dense: true,
                    title: Text(insumo.nombre, style: const TextStyle(fontSize: 13)),
                    trailing: Text(insumo.unidad, style: const TextStyle(fontSize: 11, color: Colors.black45)),
                    onTap: () => _elegirInsumo(insumo),
                  );
                },
              ),
            ),
        ],
      ],
    );
  }
}
