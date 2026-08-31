import 'package:flutter/material.dart';
import '../../../data/models/rubro_catalogo.dart';
import '../../../data/models/subitem_catalogo.dart';
import '../../../data/models/obra_subitem.dart';
import '../../../services/subitems_repository.dart';
import '../../../services/obra_subitems_repository.dart';
import '../../../services/auth_service.dart';

class SubitemsScreen extends StatefulWidget {
  final RubroCatalogo rubro;
  final String obraId;
  final bool puedeEditarComputo;
  // Posición del rubro en la lista ya mezclada/ordenada de esa obra (ver
  // RubrosTab._mezclarOrden) — no rubro.codigo, que queda interno desde esta
  // etapa (docs/rubros_orden_diseno_datos.md §3).
  final int numeroPosicion;

  const SubitemsScreen({
    Key? key,
    required this.rubro,
    required this.obraId,
    required this.puedeEditarComputo,
    required this.numeroPosicion,
  }) : super(key: key);

  @override
  State<SubitemsScreen> createState() => _SubitemsScreenState();
}

class _SubitemsScreenState extends State<SubitemsScreen> {
  final SubitemsRepository _subitemsRepository = SubitemsRepository();
  final ObraSubitemsRepository _obraSubitemsRepository = ObraSubitemsRepository();
  final AuthService _authService = AuthService();

  List<SubitemCatalogo> _subitems = [];
  Map<String, ObraSubitem> _obraSubitemsPorSubitemId = {};
  bool _cargando = true;
  String? _error;

  // subitemIds con un toggle o un guardado de cantidad en vuelo: deshabilita
  // esa fila entera (checkbox + campo de cantidad) mientras se persiste, para
  // no disparar dos escrituras concurrentes sobre la misma fila de
  // obra_subitems.
  final Set<String> _guardando = {};

  // Un TextEditingController y un FocusNode por subítem, cacheados acá (no
  // creados en itemBuilder) para no perder lo que el usuario está tipeando en
  // cada rebuild del ListView. Se descartan y se recrean solo cuando
  // _cargarDatos() vuelve a pedir todo (carga inicial o pull-to-refresh), así
  // un refresh manual sí trae valores frescos del servidor.
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, FocusNode> _focusNodes = {};

  // subitemIds con la descripción expandida (más de 2 líneas). Colapsada por
  // default para que entren más fichas en pantalla.
  final Set<String> _expandidos = {};

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes.values) {
      focusNode.dispose();
    }
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes.values) {
      focusNode.dispose();
    }
    _controllers.clear();
    _focusNodes.clear();

    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final subitems = await _subitemsRepository.getSubitemsDeRubro(widget.rubro.id);
      final mapa = await _obraSubitemsRepository.getMapaDeRubro(
        obraId: widget.obraId,
        rubroId: widget.rubro.id,
      );
      if (!mounted) return;
      setState(() {
        _subitems = subitems;
        _obraSubitemsPorSubitemId = mapa;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar los subitems de este rubro.';
        _cargando = false;
      });
    }
  }

  Future<void> _toggleSubitem(SubitemCatalogo subitem, bool nuevoValor) async {
    final usuarioId = _authService.usuarioActual?.id;
    if (usuarioId == null) return;

    setState(() => _guardando.add(subitem.id));
    try {
      final existente = _obraSubitemsPorSubitemId[subitem.id];
      final ObraSubitem actualizado;
      if (existente == null) {
        // Primera vez que aparece en la obra: siempre insert con
        // es_aplicable = true (a este punto solo se llega tildando).
        actualizado = await _obraSubitemsRepository.crear(
          obraId: widget.obraId,
          rubroId: widget.rubro.id,
          subitemId: subitem.id,
          agregadoPorUsuarioId: usuarioId,
        );
      } else {
        // Ya tenía fila: nunca se borra, solo cambia es_aplicable —
        // preserva cantidad para si se vuelve a tildar.
        actualizado = await _obraSubitemsRepository.actualizarEsAplicable(
          id: existente.id,
          esAplicable: nuevoValor,
          usuarioId: usuarioId,
        );
      }
      if (!mounted) return;
      setState(() {
        _obraSubitemsPorSubitemId = {
          ..._obraSubitemsPorSubitemId,
          subitem.id: actualizado,
        };
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo guardar el cambio. Probá de nuevo.')),
      );
    } finally {
      if (mounted) setState(() => _guardando.remove(subitem.id));
    }
  }

  /// Acepta coma o punto como separador decimal (el teclado numérico de un
  /// dispositivo en es-AR pone coma) y rechaza vacío, no numérico o negativo.
  double? _parsearCantidad(String texto) {
    final normalizado = texto.trim().replaceAll(',', '.');
    if (normalizado.isEmpty) return null;
    final valor = double.tryParse(normalizado);
    if (valor == null || valor < 0) return null;
    return valor;
  }

  String _formatearCantidad(double valor) {
    return valor == valor.roundToDouble() ? valor.toInt().toString() : valor.toString();
  }

  /// Se dispara al perder el foco el campo de cantidad de un subítem.
  Future<void> _guardarCantidad(SubitemCatalogo subitem) async {
    final existente = _obraSubitemsPorSubitemId[subitem.id];
    // El campo solo está habilitado con el subítem tildado (ver
    // _buildContenido), así que a esta altura siempre hay fila.
    if (existente == null) return;

    final controller = _controllers[subitem.id];
    if (controller == null) return;

    final nuevaCantidad = _parsearCantidad(controller.text);
    if (nuevaCantidad == null) {
      // Nada de fallback silencioso a 0: acá el dato es plata real de la
      // obra (a diferencia de un campo de un diálogo de catálogo). Se
      // revierte el texto al último valor válido y se avisa.
      controller.text = _formatearCantidad(existente.cantidad);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cantidad inválida. Ingresá un número mayor o igual a 0.')),
      );
      return;
    }

    if (nuevaCantidad == existente.cantidad) return; // sin cambios, nada que persistir

    final usuarioId = _authService.usuarioActual?.id;
    if (usuarioId == null) return;

    setState(() => _guardando.add(subitem.id));
    try {
      final actualizado = await _obraSubitemsRepository.actualizarCantidad(
        id: existente.id,
        cantidad: nuevaCantidad,
        usuarioId: usuarioId,
      );
      if (!mounted) return;
      setState(() {
        _obraSubitemsPorSubitemId = {
          ..._obraSubitemsPorSubitemId,
          subitem.id: actualizado,
        };
      });
    } catch (e) {
      controller.text = _formatearCantidad(existente.cantidad);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo guardar la cantidad. Probá de nuevo.')),
      );
    } finally {
      if (mounted) setState(() => _guardando.remove(subitem.id));
    }
  }

  TextEditingController _controllerPara(SubitemCatalogo subitem) {
    return _controllers.putIfAbsent(subitem.id, () {
      final existente = _obraSubitemsPorSubitemId[subitem.id];
      return TextEditingController(text: _formatearCantidad(existente?.cantidad ?? 0));
    });
  }

  FocusNode _focusNodePara(SubitemCatalogo subitem) {
    return _focusNodes.putIfAbsent(subitem.id, () {
      final focusNode = FocusNode();
      focusNode.addListener(() {
        if (!focusNode.hasFocus) _guardarCantidad(subitem);
      });
      return focusNode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.numeroPosicion} - ${widget.rubro.nombre}'),
        backgroundColor: const Color(0xFF1B365D),
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _cargarDatos,
        child: _buildContenido(),
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
            child: Column(
              children: [
                Icon(Icons.error_outline, color: Colors.red.shade400, size: 32),
                const SizedBox(height: 8),
                Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
              ],
            ),
          ),
        ],
      );
    }
    if (_subitems.isEmpty) {
      return ListView(
        children: const [
          Padding(
            padding: EdgeInsets.all(24.0),
            child: Text(
              'No hay subitems en el catálogo para este rubro todavía.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12.0),
      itemCount: _subitems.length,
      itemBuilder: (context, index) {
        final subitem = _subitems[index];
        final aplicable = _obraSubitemsPorSubitemId[subitem.id]?.esAplicable ?? false;
        final guardandoEste = _guardando.contains(subitem.id);
        final puedeEditar = widget.puedeEditarComputo && !guardandoEste;
        final expandido = _expandidos.contains(subitem.id);
        return Card(
          margin: const EdgeInsets.only(bottom: 6.0),
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            leading: Checkbox(
              value: aplicable,
              onChanged: puedeEditar
                  ? (val) => _toggleSubitem(subitem, val ?? false)
                  : null,
            ),
            // La unidad ya se ve en el suffixText del campo de cantidad — no
            // se repite acá abajo (antes estaba en el subtitle "Unidad: X").
            title: InkWell(
              onTap: () => setState(() {
                if (expandido) {
                  _expandidos.remove(subitem.id);
                } else {
                  _expandidos.add(subitem.id);
                }
              }),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      '${subitem.codigo} - ${subitem.descripcion}',
                      maxLines: expandido ? null : 2,
                      overflow: expandido ? TextOverflow.visible : TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                  Icon(
                    expandido ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    size: 18,
                    color: Colors.black45,
                  ),
                ],
              ),
            ),
            trailing: SizedBox(
              // Ancho suficiente para el número en fuente grande + el sufijo
              // de unidad más largo del catálogo ("M2 O GL.", "UND O M2").
              width: 140,
              child: TextFormField(
                controller: _controllerPara(subitem),
                focusNode: _focusNodePara(subitem),
                enabled: aplicable && puedeEditar,
                textAlign: TextAlign.right,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                // Es el dato que el usuario está cargando: más peso visual
                // que el texto descriptivo de la fila (título 13, subtítulo
                // 11).
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  // Normalización solo visual (mayúsculas parejas) — la
                  // columna subitems.unidad queda tal cual vino de la
                  // planilla original, sin tocar la base.
                  suffixText: subitem.unidad.toUpperCase(),
                  suffixStyle: const TextStyle(fontSize: 12, color: Colors.black45),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
