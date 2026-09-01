import 'package:flutter/material.dart';
import '../../../data/models/obra_presupuesto_config.dart';
import '../../../services/auth_service.dart';
import '../../../services/obra_presupuesto_config_repository.dart';
import '../../../services/perfil_repository.dart';
import '../../shared/pro_gate_dialog.dart';

/// Header de la Solapa APU: selector de tipo de presupuesto (Materiales +
/// Mano de Obra / Mano de Obra Sola) y toggle de impuestos. Vive arriba de
/// la solapa, no detrás de un ícono de configuración aparte — es algo que
/// se toca mientras se trabaja para comparar vistas, no un ajuste de alta
/// que se configura una sola vez. `SegmentedButton` en vez de `ChoiceChip`
/// sueltos a propósito: mismo control que ya usa el toggle ARS/USD de
/// "Ajuste Económico & Moneda" (`obras_list_screen.dart`), y mantiene los
/// dos segmentos en una sola fila sin depender de que el ancho alcance
/// (`ChoiceChip` + `Wrap` se apilaba en pantalla angosta con estas
/// etiquetas). Deliberadamente chico — es un control que se toca cada
/// tanto, no debe competir con el contenido de la solapa.
///
/// Solo lee y guarda la elección en `obra_presupuesto_config` — no dispara
/// ningún recálculo todavía. Esa lógica es la pieza siguiente (conectar la
/// Solapa APU de verdad), que va a leer esta misma configuración.
///
/// Mano de Obra Sola es función PRO (Free queda fijo en Materiales + Mano
/// de Obra); impuestos lo usan Free y PRO por igual. El gate reusa
/// `mostrarDialogoFuncionPro` — mismo patrón que `RubrosTab`/`SubitemsScreen`
/// para "función PRO": el control queda visible y tocable, no oculto ni
/// grisado, y al tocarlo Free ve el diálogo en vez de que el cambio se
/// aplique.
class SelectorTipoPresupuesto extends StatefulWidget {
  final String obraId;

  const SelectorTipoPresupuesto({Key? key, required this.obraId}) : super(key: key);

  @override
  State<SelectorTipoPresupuesto> createState() => _SelectorTipoPresupuestoState();
}

class _SelectorTipoPresupuestoState extends State<SelectorTipoPresupuesto> {
  final AuthService _authService = AuthService();
  final ObraPresupuestoConfigRepository _configRepository = ObraPresupuestoConfigRepository();
  final PerfilRepository _perfilRepository = PerfilRepository();

  bool _cargando = true;
  bool _esPro = false;
  ObraPresupuestoConfig? _config;

  @override
  void initState() {
    super.initState();
    _cargar();
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

  Future<void> _onCambiarTipo(TipoPresupuesto tipo) async {
    final actual = _config;
    if (actual == null || actual.tipoPresupuesto == tipo) return;

    if (tipo == TipoPresupuesto.manoObraSola && !_esPro) {
      mostrarDialogoFuncionPro(
        context,
        mensaje: 'Ver el presupuesto sin materiales (Mano de Obra Sola) es una función PRO.',
      );
      return;
    }

    final actualizado = await _configRepository.actualizarTipoPresupuesto(
      obraId: widget.obraId,
      tipo: tipo,
    );
    if (!mounted) return;
    setState(() => _config = actualizado);
  }

  Future<void> _onCambiarImpuestos(bool aplicaImpuestos) async {
    final actual = _config;
    if (actual == null || actual.aplicaImpuestos == aplicaImpuestos) return;

    final actualizado = await _configRepository.actualizarAplicaImpuestos(
      obraId: widget.obraId,
      aplicaImpuestos: aplicaImpuestos,
    );
    if (!mounted) return;
    setState(() => _config = actualizado);
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando || _config == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: SizedBox(
          height: 16,
          width: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final config = _config!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SegmentedButton<TipoPresupuesto>(
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(fontSize: 11),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
            ),
            segments: [
              const ButtonSegment(
                value: TipoPresupuesto.materialesManoObra,
                label: Text('Comp. Mat y MO'),
              ),
              ButtonSegment(
                value: TipoPresupuesto.manoObraSola,
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Comp. Solo MO'),
                    if (!_esPro) ...[
                      const SizedBox(width: 3),
                      const Icon(Icons.workspace_premium, size: 12, color: Colors.amber),
                    ],
                  ],
                ),
              ),
            ],
            selected: {config.tipoPresupuesto},
            onSelectionChanged: (nuevaSeleccion) => _onCambiarTipo(nuevaSeleccion.first),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Impuestos', style: TextStyle(fontSize: 11, color: Colors.black54)),
              Transform.scale(
                scale: 0.75,
                child: Switch(
                  value: config.aplicaImpuestos,
                  onChanged: _onCambiarImpuestos,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
