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
import 'panel_crear_equipo_apu.dart';

/// Agregar una línea nueva a la receta de una partida — material o equipo, mismo mecanismo para
/// los dos: clona la receta oficial al fork del usuario si hace falta y agrega la línea ahí (ver
/// `agregar_material_apu`/`agregar_equipo_apu`, `0072_edicion_apu_correcciones.sql` /
/// `0073_agregar_quitar_equipo_apu.sql`). El catálogo oficial nunca se toca. Mano de obra queda
/// afuera a propósito -- ya tiene sus 5 categorías siempre visibles (ver `ComposicionApuScreen`),
/// no se agregan/quitan líneas ahí.
///
/// Para equipo, `ComposicionApuScreen` muestra un diálogo de advertencia ANTES de abrir este --
/// acá adentro no hay ningún aviso, este panel es igual para los dos tipos.
///
/// Dos pasos en un mismo diálogo: buscar y elegir el insumo, después cargarle un rendimiento.
/// `insumoIdsExistentes` filtra del buscador lo que la receta ya tiene, para no ofrecer un
/// duplicado que la función de base va a rechazar de todos modos.
///
/// Gate de PRO al Guardar, no al abrir — mismo criterio que `PanelEditarItemApu`.
///
/// Devuelve por `Navigator.pop`: `null` si se cancela, o la receta completa ya actualizada.
class PanelAgregarItemApu extends StatefulWidget {
  final String obraId;
  final String subitemId;
  final Set<String> insumoIdsExistentes;
  final String tipoComponente; // 'material' | 'equipo'

  const PanelAgregarItemApu({
    Key? key,
    required this.obraId,
    required this.subitemId,
    required this.insumoIdsExistentes,
    required this.tipoComponente,
  }) : super(key: key);

  @override
  State<PanelAgregarItemApu> createState() => _PanelAgregarItemApuState();
}

class _PanelAgregarItemApuState extends State<PanelAgregarItemApu> {
  final ApuComposicionesRepository _composicionesRepository = ApuComposicionesRepository();
  final InsumosRepository _insumosRepository = InsumosRepository();
  final PerfilRepository _perfilRepository = PerfilRepository();
  final AuthService _authService = AuthService();

  final TextEditingController _busquedaController = TextEditingController();
  final TextEditingController _rendimientoController = TextEditingController();
  Timer? _debounceBusqueda;

  bool get _esEquipo => widget.tipoComponente == 'equipo';
  String get _etiqueta => _esEquipo ? 'equipo' : 'material';

  InsumoBusqueda? _insumoSeleccionado;
  bool _cargandoBusqueda = false;
  List<InsumoBusqueda> _resultados = [];

  String? _error;
  bool _guardando = false;
  bool _verificandoPro = false;

  @override
  void dispose() {
    _busquedaController.dispose();
    _rendimientoController.dispose();
    _debounceBusqueda?.cancel();
    super.dispose();
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
        final resultados = await _insumosRepository.buscarPorTipo(texto, widget.tipoComponente);
        if (!mounted) return;
        setState(() {
          _resultados = resultados.where((r) => !widget.insumoIdsExistentes.contains(r.id)).toList();
          _cargandoBusqueda = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() => _cargandoBusqueda = false);
      }
    });
  }

  /// Abre el formulario de alta directa (`PanelCrearEquipoApu`) desde adentro del buscador -- si
  /// se crea algo, cierra este diálogo también, devolviendo el resultado hacia `ComposicionApuScreen`
  /// (mismo contrato de `Navigator.pop` que ya usa `_onGuardar`).
  Future<void> _abrirCrearEquipo() async {
    final resultado = await showDialog<List<ApuComposicionItemDetalle>>(
      context: context,
      builder: (_) => PanelCrearEquipoApu(obraId: widget.obraId, subitemId: widget.subitemId),
    );
    if (resultado == null || !mounted) return;
    Navigator.pop(context, resultado);
  }

  Future<void> _onGuardar() async {
    final insumo = _insumoSeleccionado;
    if (insumo == null) {
      setState(() => _error = 'Elegí un $_etiqueta.');
      return;
    }
    final rendimiento = ParserNumeroAr.parsear(_rendimientoController.text);
    if (rendimiento == null || rendimiento < 0) {
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
      final recetaActualizada = _esEquipo
          ? await _composicionesRepository.agregarEquipo(
              obraId: widget.obraId,
              subitemId: widget.subitemId,
              insumoId: insumo.id,
              rendimiento: rendimiento,
            )
          : await _composicionesRepository.agregarMaterial(
              obraId: widget.obraId,
              subitemId: widget.subitemId,
              insumoId: insumo.id,
              rendimiento: rendimiento,
            );
      if (!mounted) return;
      Navigator.pop(context, recetaActualizada);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _error = 'No se pudo agregar el $_etiqueta. Probá de nuevo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final insumo = _insumoSeleccionado;
    return AlertDialog(
      title: Text(
        _esEquipo ? 'Agregar equipo' : 'Agregar material',
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1B365D)),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (insumo == null) ...[
              TextField(
                controller: _busquedaController,
                autofocus: true,
                onChanged: _onBuscarCambiado,
                decoration: InputDecoration(
                  hintText: 'Buscar $_etiqueta...',
                  isDense: true,
                  border: const OutlineInputBorder(),
                  suffixIcon: _cargandoBusqueda
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : null,
                ),
              ),
              if (_resultados.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  constraints: const BoxConstraints(maxHeight: 200),
                  decoration: BoxDecoration(border: Border.all(color: Colors.black12)),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _resultados.length,
                    itemBuilder: (context, index) {
                      final r = _resultados[index];
                      return ListTile(
                        dense: true,
                        title: Text(r.nombre, style: const TextStyle(fontSize: 13)),
                        trailing: Text(r.unidad, style: const TextStyle(fontSize: 11, color: Colors.black45)),
                        onTap: () => setState(() {
                          _insumoSeleccionado = r;
                          _resultados = [];
                          _busquedaController.clear();
                        }),
                      );
                    },
                  ),
                ),
              // Solo equipo -- el catálogo de materiales es curado, sin alta desde acá (ver
              // InsumosRepository). El catálogo de equipos se arma con lo que carga cada usuario.
              if (_esEquipo) ...[
                const SizedBox(height: 8),
                InkWell(
                  onTap: _abrirCrearEquipo,
                  child: const Text(
                    '¿No lo encontrás? Crear equipo nuevo',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF1B365D),
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      insumo.nombre,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _insumoSeleccionado = null),
                    child: const Text('Cambiar', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _rendimientoController,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Rendimiento',
                  suffixText: insumo.unidad.toUpperCase(),
                  border: const OutlineInputBorder(),
                  isDense: true,
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
        if (insumo != null)
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
