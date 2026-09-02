import 'package:flutter/material.dart';
import '../../../core/utils/parser_numero_ar.dart';
import '../../../data/models/insumo_consolidado_obra.dart';
import '../../../data/models/valor_hora_categoria.dart';
import '../../../services/auth_service.dart';
import '../../../services/obra_insumos_repository.dart';
import 'panel_parametros_cargas_sociales.dart';

/// El lapicito de mano de obra — Paso 5 (ver docs/costo_mano_de_obra_decisiones.md §15/§16). Solo
/// el valor hora de ESTA categoría: el campo, el link a "Ajustar cargas sociales" (abre
/// PanelParametrosCargasSociales en una ventana aparte, nunca una sección expandible acá),
/// Cancelar y Guardar. Los 7 parámetros de la obra no viven en este archivo — separarlos fue la
/// corrección que cerró la tanda 2 después de cuatro rondas de parches sobre el diseño de "una
/// sola ventana" (ver §16 para el porqué completo).
///
/// Devuelve `true` por `Navigator.pop` si se guardó algo de verdad — el valor hora de acá, o los
/// parámetros en la ventana que abre el link (viaja para arriba en `_huboGuardadoDeParametros`
/// aunque el usuario después cancele esta ventana). Quien abre este panel recarga el consolidado
/// si el resultado es `true`.
class PanelValorHoraManoObra extends StatefulWidget {
  final String obraId;
  final InsumoConsolidadoObra insumo;
  final List<InsumoConsolidadoObra> todosLosInsumos;
  final ValorHoraCategoria valorHoraCategoria;

  const PanelValorHoraManoObra({
    Key? key,
    required this.obraId,
    required this.insumo,
    required this.todosLosInsumos,
    required this.valorHoraCategoria,
  }) : super(key: key);

  @override
  State<PanelValorHoraManoObra> createState() => _PanelValorHoraManoObraState();
}

class _PanelValorHoraManoObraState extends State<PanelValorHoraManoObra> {
  final ObraInsumosRepository _obraInsumosRepository = ObraInsumosRepository();
  final AuthService _authService = AuthService();

  late final TextEditingController _valorHoraController;
  String? _errorValorHora;
  bool _guardando = false;

  // true si la ventana de parámetros guardó algo durante esta visita. No se refresca el campo de
  // arriba ni se cierra este panel solo — el nuevo valor hora depende de los 7 parámetros y no es
  // una cuenta que este panel pueda rehacer sin otra consulta a la base, y cerrar solo tiraría un
  // valor hora sin guardar que el usuario haya tipeado. En cambio se avisa con una nota (ver
  // build()) y se deja que el propio Guardar/Cancelar de acá recargue el consolidado al cerrar. El
  // texto tipeado en el campo, tocado o no, sigue intacto de por sí: abrir la ventana de parámetros
  // no desmonta este panel, solo lo tapa (`showDialog` anidado). Ver docs §16.
  bool _huboGuardadoDeParametros = false;

  /// Otros insumos de mano de obra que comparten categoría UOCRA con éste (hoy solo AYUDANTE/
  /// AYUDA DE GREMIO) — sale del dato real ya cargado, nunca de un nombre hardcodeado.
  List<InsumoConsolidadoObra> get _otrosDeLaMismaCategoria => widget.todosLosInsumos
      .where((i) =>
          i.tipo == 'mano_obra' &&
          i.categoriaUocra == widget.insumo.categoriaUocra &&
          i.insumoId != widget.insumo.insumoId)
      .toList();

  @override
  void initState() {
    super.initState();
    _valorHoraController = TextEditingController(
      text: widget.insumo.precio != null ? widget.insumo.precio!.toStringAsFixed(2) : '',
    );
  }

  @override
  void dispose() {
    _valorHoraController.dispose();
    super.dispose();
  }

  Future<void> _abrirParametros() async {
    final guardado = await showDialog<bool>(
      context: context,
      builder: (_) => PanelParametrosCargasSociales(obraId: widget.obraId),
    );
    if (guardado == true && mounted) {
      setState(() => _huboGuardadoDeParametros = true);
    }
  }

  /// Se guarda solo si cambió de verdad contra lo precargado (comparación numérica con tolerancia)
  /// — guardar sin cambios crearía un override donde no lo había, a traición. Vaciar el campo no se
  /// interpreta como "volver al calculado" (para eso está el link "Volver" de la fila del
  /// consolidado, no de acá) — muestra un aviso inline y no guarda nada.
  Future<void> _onGuardar() async {
    final textoValorHora = _valorHoraController.text.trim();
    final valorHoraVacio = textoValorHora.isEmpty;
    final valorParseado = ParserNumeroAr.parsear(textoValorHora);
    final valorHoraCambio = !valorHoraVacio &&
        (widget.insumo.precio == null ||
            valorParseado == null ||
            (valorParseado - widget.insumo.precio!).abs() > 0.001);

    if (valorHoraVacio && widget.insumo.precio != null) {
      setState(() => _errorValorHora =
          'Vacío no se guarda — para volver al valor calculado usá "Volver" arriba.');
      return;
    }
    if (valorHoraCambio && (valorParseado == null || valorParseado < 0)) {
      setState(() => _errorValorHora = 'Valor inválido');
      return;
    }
    setState(() => _errorValorHora = null);

    if (!valorHoraCambio) {
      Navigator.pop(context, _huboGuardadoDeParametros ? true : null);
      return;
    }

    final usuarioId = _authService.usuarioActual?.id;
    if (usuarioId == null) return;
    setState(() => _guardando = true);
    try {
      await _obraInsumosRepository.guardarValorHoraOverride(
        obraId: widget.obraId,
        categoriaUocra: widget.insumo.categoriaUocra!,
        valorHora: valorParseado!,
        usuarioId: usuarioId,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _errorValorHora = 'No se pudo guardar.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final insumo = widget.insumo;
    final otros = _otrosDeLaMismaCategoria;

    return AlertDialog(
      title: Text(insumo.nombre, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Valor hora — solo esta categoría',
            style: TextStyle(fontSize: 11, color: Colors.black54),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _valorHoraController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            decoration: InputDecoration(
              prefixText: '\$ ',
              isDense: true,
              errorText: _errorValorHora,
            ),
          ),
          if (otros.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Este valor hora es compartido: también corresponde a '
              '${otros.map((o) => o.nombre).join(', ')}. Al guardarlo cambian las dos filas.',
              style: TextStyle(fontSize: 10, color: Colors.grey[700]),
            ),
          ],
          const SizedBox(height: 12),
          InkWell(
            onTap: _guardando ? null : _abrirParametros,
            child: const Text(
              '▸ Ajustar cargas sociales',
              style: TextStyle(fontSize: 11, color: Color(0xFF1B365D), fontWeight: FontWeight.w600),
            ),
          ),
          if (_huboGuardadoDeParametros) ...[
            const SizedBox(height: 6),
            const Text(
              'Los parámetros de cargas cambiaron. Cerrá y volvé a abrir para ver el valor '
              'recalculado.',
              style: TextStyle(fontSize: 10, color: Colors.black54, fontStyle: FontStyle.italic),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _guardando
              ? null
              : () => Navigator.pop(context, _huboGuardadoDeParametros ? true : null),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: _guardando ? null : _onGuardar,
          child: Text(_guardando ? 'Guardando...' : 'Guardar'),
        ),
      ],
    );
  }
}
