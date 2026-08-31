import 'package:flutter/material.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/models/rubro_catalogo.dart';
import '../../../data/models/subitem_catalogo.dart';
import '../../../data/models/obra_subitem.dart';
import '../../../services/subitems_repository.dart';
import '../../../services/obra_subitems_repository.dart';
import '../../../services/auth_service.dart';
import '../../../services/perfil_repository.dart';
import '../../shared/pro_gate_dialog.dart';

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
  final PerfilRepository _perfilRepository = PerfilRepository();

  List<SubitemCatalogo> _subitems = [];
  Map<String, ObraSubitem> _obraSubitemsPorSubitemId = {};
  bool _cargando = true;
  String? _error;
  // Mismo criterio que RubrosTab: cacheado del load inicial, gatea el botón
  // "Nuevo subítem" del AppBar. Fail-safe a false sin usuario logueado.
  bool _esPro = false;
  // subitemIds con un chequeo de uso o un DELETE en vuelo — mismo patrón que
  // RubrosTab._procesandoEliminacion.
  final Set<String> _procesandoEliminacion = {};

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

  // Precio manual — solo relevante para rubros con tipoPrecioManual ==
  // 'unitario' (1, 20, custom; ver _buildContenido), pero cacheados acá
  // igual que cantidad, con sus propios mapas para no chocar de clave.
  final Map<String, TextEditingController> _preciosControllers = {};
  final Map<String, FocusNode> _preciosFocusNodes = {};

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
    for (final controller in _preciosControllers.values) {
      controller.dispose();
    }
    for (final focusNode in _preciosFocusNodes.values) {
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
    for (final controller in _preciosControllers.values) {
      controller.dispose();
    }
    for (final focusNode in _preciosFocusNodes.values) {
      focusNode.dispose();
    }
    _preciosControllers.clear();
    _preciosFocusNodes.clear();

    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final usuarioId = _authService.usuarioActual?.id;
      final subitems = await _subitemsRepository.getSubitemsDeRubro(widget.rubro.id, usuarioId: usuarioId);
      final mapa = await _obraSubitemsRepository.getMapaDeRubro(
        obraId: widget.obraId,
        rubroId: widget.rubro.id,
      );
      final esPro = usuarioId != null ? await _perfilRepository.esPro(usuarioId) : false;
      if (!mounted) return;
      setState(() {
        _subitems = subitems;
        _obraSubitemsPorSubitemId = mapa;
        _esPro = esPro;
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

  /// Código para un subítem propio nuevo: sigue la secuencia visible de
  /// este rubro en esta obra ("{numeroPosicion}.{siguiente}"), no
  /// rubro.codigo (interno desde la etapa de reordenamiento, ver
  /// docs/rubros_orden_diseno_datos.md §3). No hace falta que sea único a
  /// nivel de base — el índice único de subitems.codigo solo cubre filas
  /// oficiales — esto es solo para que se lea bien en la lista, siguiendo
  /// el mismo patrón "N.M" que ya usa el catálogo real.
  String _siguienteCodigoPropio() {
    var maxSegundo = 0;
    for (final subitem in _subitems) {
      final partes = subitem.codigo.split('.');
      if (partes.length < 2) continue;
      final segundo = int.tryParse(partes[1]);
      if (segundo != null && segundo > maxSegundo) maxSegundo = segundo;
    }
    return '${widget.numeroPosicion}.${maxSegundo + 1}';
  }

  void _onNuevoSubitem() {
    if (_esPro) {
      _mostrarDialogoAltaSubitem();
    } else {
      mostrarDialogoFuncionPro(
        context,
        mensaje: 'Agregar tus propios subítems (para lo que el catálogo no cubre, '
            'en cualquier rubro) es una función PRO.',
      );
    }
  }

  void _mostrarDialogoAltaSubitem() {
    final descripcionCtrl = TextEditingController();
    final unidadCtrl = TextEditingController();
    // Declaradas fuera del builder: StatefulBuilder vuelve a ejecutar su
    // builder en cada setModalState, así que una variable local ahí adentro
    // se resetearía a su valor inicial en cada rebuild.
    bool guardando = false;
    String? error;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setModalState) {
          Future<void> guardar() async {
            final descripcion = descripcionCtrl.text.trim();
            final unidad = unidadCtrl.text.trim();
            if (descripcion.isEmpty) {
              setModalState(() => error = 'Completá la descripción.');
              return;
            }
            if (unidad.isEmpty) {
              setModalState(() => error = 'Completá la unidad.');
              return;
            }
            final usuarioId = _authService.usuarioActual?.id;
            if (usuarioId == null) {
              setModalState(() => error = 'No se pudo identificar al usuario.');
              return;
            }
            setModalState(() {
              guardando = true;
              error = null;
            });
            try {
              await _subitemsRepository.crearPersonalizado(
                rubroId: widget.rubro.id,
                codigo: _siguienteCodigoPropio(),
                descripcion: descripcion,
                unidad: unidad,
                creadorUsuarioId: usuarioId,
              );
              if (!dialogCtx.mounted) return;
              Navigator.of(dialogCtx).pop();
              await _cargarDatos(); // trae el subítem nuevo, no solo tildados/cantidades
            } catch (e) {
              setModalState(() {
                guardando = false;
                error = 'No se pudo crear el subítem. Probá de nuevo.';
              });
            }
          }

          return AlertDialog(
            title: const Text(
              'Nuevo Subítem',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1B365D)),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: descripcionCtrl,
                    autofocus: true,
                    maxLines: null,
                    decoration: const InputDecoration(labelText: 'Descripción', border: OutlineInputBorder(), isDense: true),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: unidadCtrl,
                    decoration: const InputDecoration(labelText: 'Unidad (ej. M2, ML, GL)', border: OutlineInputBorder(), isDense: true),
                  ),
                  // Nunca tiene composición de APU (nadie la compuso
                  // todavía) — se carga con precio manual sin importar si
                  // el resto del rubro usa APU. Ver _buildContenido: la
                  // condición de precio manual ahora también mira
                  // creadorUsuarioId, no solo tipoPrecioManual.
                  const SizedBox(height: 12),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Se carga con precio manual — no depende de una composición de '
                      'APU, que todavía nadie cargó para este subítem.',
                      style: TextStyle(fontSize: 11, color: Colors.black54),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: guardando ? null : () => Navigator.of(dialogCtx).pop(),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: guardando ? null : guardar,
                child: guardando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Crear'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Chequea uso para decidir QUÉ diálogo mostrar, ya no para bloquear — el
  /// catálogo propio es del usuario, la protección correcta es avisar qué
  /// se pierde y dejarlo decidir (ver migración
  /// 0028_obra_subitems_cascade_propio.sql para el porqué completo). Con
  /// esa migración aplicada, obra_subitems.subitem_id tiene `on delete
  /// cascade` — borrar el subítem se lleva puesto su cómputo en cualquier
  /// obra donde estuviera cargado.
  Future<void> _onEliminarSubitem(SubitemCatalogo subitem) async {
    setState(() => _procesandoEliminacion.add(subitem.id));
    List<String> obrasConUso;
    try {
      obrasConUso = await _obraSubitemsRepository.getNombresObrasConUsoDeSubitem(subitem.id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _procesandoEliminacion.remove(subitem.id));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo verificar si el subítem tiene datos cargados. Probá de nuevo.')),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _procesandoEliminacion.remove(subitem.id));

    final confirmar = obrasConUso.isEmpty
        ? await _mostrarDialogoConfirmarEliminarSubitem(subitem)
        : await _mostrarDialogoConfirmarEliminarSubitemConDatos(subitem, obrasConUso);
    if (confirmar != true) return;

    setState(() => _procesandoEliminacion.add(subitem.id));
    try {
      await _subitemsRepository.eliminar(subitem.id);
      if (!mounted) return;
      await _cargarDatos();
    } catch (e) {
      // Ya no distingue 23503 como caso especial (esa era la señal de "está
      // en uso", y ahora eso ya no bloquea) — cualquier error acá es
      // inesperado de verdad.
      if (!mounted) return;
      setState(() => _procesandoEliminacion.remove(subitem.id));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo eliminar el subítem. Probá de nuevo.')),
      );
    }
  }

  Future<bool?> _mostrarDialogoConfirmarEliminarSubitem(SubitemCatalogo subitem) {
    return showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text(
          'Eliminar subítem',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1B365D)),
        ),
        content: Text('¿Eliminar "${subitem.codigo} - ${subitem.descripcion}"? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  /// Antes bloqueaba ("No se puede eliminar"). Ahora advierte y deja
  /// decidir — mismo criterio que _mostrarDialogoConfirmarEliminarSubitem,
  /// pero con el detalle concreto de qué se pierde en vez de un genérico
  /// "no se puede deshacer".
  Future<bool?> _mostrarDialogoConfirmarEliminarSubitemConDatos(SubitemCatalogo subitem, List<String> obras) {
    return showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text(
          'Eliminar subítem con datos cargados',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1B365D)),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('"${subitem.codigo} - ${subitem.descripcion}" tiene cómputo cargado en:'),
            const SizedBox(height: 8),
            ...obras.map(
              (nombre) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text('• $nombre', style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Se va a borrar también ese cómputo (cantidad y precio cargados) en esas obras. '
              'Esta acción no se puede deshacer.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar de todos modos'),
          ),
        ],
      ),
    );
  }

  Widget _buildChipPropio() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.amber[50],
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.amber[700]!),
      ),
      child: Text(
        'Propio',
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber[900]),
      ),
    );
  }

  /// Chip "Propio" + ícono de borrar, solo para subítems del usuario — los
  /// oficiales no muestran trailing acá. El ícono queda deshabilitado y se
  /// reemplaza por un spinner chico mientras hay un chequeo/DELETE en
  /// vuelo para ese subítem puntual — mismo patrón que
  /// RubrosTab._buildTrailingPropio.
  Widget _buildTrailingPropio(SubitemCatalogo subitem) {
    final procesando = _procesandoEliminacion.contains(subitem.id);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildChipPropio(),
        const SizedBox(width: 4),
        if (procesando)
          const SizedBox(
            width: 20,
            height: 20,
            child: Padding(
              padding: EdgeInsets.all(2),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
            tooltip: 'Eliminar subítem',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => _onEliminarSubitem(subitem),
          ),
      ],
    );
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

  /// Igual que _parsearCantidad (coma o punto, rechaza vacío/no-numérico/
  /// negativo) — método propio en vez de reusar aquel para no tocar una
  /// función existente que no hace falta modificar (misma lógica, sin
  /// dependencia cruzada entre cantidad y precio).
  double? _parsearPrecio(String texto) {
    final normalizado = texto.trim().replaceAll(',', '.');
    if (normalizado.isEmpty) return null;
    final valor = double.tryParse(normalizado);
    if (valor == null || valor < 0) return null;
    return valor;
  }

  /// _parsearPrecio colapsa no-numérico/negativo en un mismo `null` para
  /// decidir si hay que persistir o no — acá se distingue cuál de los dos
  /// fue en realidad, para no mostrarle al usuario el mismo mensaje
  /// genérico ("inválido") en los dos casos (un número negativo sí es un
  /// número, el problema real es que no puede ser negativo). El caso
  /// "vacío" ya no pasa por acá — _guardarPrecio lo maneja aparte, vaciar
  /// un precio cargado es una acción válida, no un error.
  String _mensajeErrorPrecio(String texto) {
    final valor = double.tryParse(texto.replaceAll(',', '.'));
    if (valor == null) return 'Precio inválido. Ingresá solo números.';
    return 'El precio no puede ser negativo.';
  }

  /// Se dispara al perder el foco el campo de precio de un subítem (rubros
  /// con tipoPrecioManual == 'unitario' únicamente, ver _buildContenido).
  ///
  /// Vaciar un precio ya cargado es una acción válida, no un error: la
  /// columna admite `null` ("sin decidir" recién tildado, o "el usuario lo
  /// sacó a propósito" después de haber tenido uno) — si el campo queda
  /// vacío al perder el foco, se persiste `null` sin avisar ni revertir
  /// (antes se bloqueaba con un mensaje de error; el usuario puede
  /// deshacer lo que carga en su propio catálogo). Distinto de cantidad,
  /// que siempre arranca en un valor real (default 0 de la columna, no
  /// nullable) — ahí un campo vacío sigue siendo un error real, no una
  /// decisión del usuario.
  Future<void> _guardarPrecio(SubitemCatalogo subitem) async {
    final existente = _obraSubitemsPorSubitemId[subitem.id];
    if (existente == null) return;

    final controller = _preciosControllers[subitem.id];
    if (controller == null) return;

    final texto = controller.text.trim();

    if (texto.isEmpty) {
      if (existente.precioUnitarioManual == null) return; // nunca tuvo precio, nada que hacer
      await _guardarPrecioValor(subitem, existente, null);
      return;
    }

    final nuevoPrecio = _parsearPrecio(texto);
    if (nuevoPrecio == null) {
      controller.text = existente.precioUnitarioManual != null
          ? _formatearCantidad(existente.precioUnitarioManual!)
          : '';
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_mensajeErrorPrecio(texto))),
      );
      return;
    }

    if (nuevoPrecio == existente.precioUnitarioManual) return; // sin cambios
    await _guardarPrecioValor(subitem, existente, nuevoPrecio);
  }

  /// Guardado propiamente dicho, compartido entre cargar/cambiar un precio
  /// y vaciarlo (precio null) — mismo manejo de _guardando/error/revert en
  /// los dos casos, solo cambia el valor que se persiste.
  Future<void> _guardarPrecioValor(SubitemCatalogo subitem, ObraSubitem existente, double? precio) async {
    final controller = _preciosControllers[subitem.id];
    final usuarioId = _authService.usuarioActual?.id;
    if (usuarioId == null) return;

    setState(() => _guardando.add(subitem.id));
    try {
      final actualizado = await _obraSubitemsRepository.actualizarPrecioUnitarioManual(
        id: existente.id,
        precio: precio,
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
      controller?.text = existente.precioUnitarioManual != null
          ? _formatearCantidad(existente.precioUnitarioManual!)
          : '';
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(precio == null ? 'No se pudo borrar el precio. Probá de nuevo.' : 'No se pudo guardar el precio. Probá de nuevo.')),
      );
    } finally {
      if (mounted) setState(() => _guardando.remove(subitem.id));
    }
  }

  TextEditingController _controllerPrecioPara(SubitemCatalogo subitem) {
    return _preciosControllers.putIfAbsent(subitem.id, () {
      final precio = _obraSubitemsPorSubitemId[subitem.id]?.precioUnitarioManual;
      return TextEditingController(text: precio != null ? _formatearCantidad(precio) : '');
    });
  }

  FocusNode _focusNodePrecioPara(SubitemCatalogo subitem) {
    return _preciosFocusNodes.putIfAbsent(subitem.id, () {
      final focusNode = FocusNode();
      focusNode.addListener(() {
        if (!focusNode.hasFocus) _guardarPrecio(subitem);
      });
      return focusNode;
    });
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
        // Sin el número de posición del rubro (antes "3 - Nombre"): abajo
        // los subítems muestran su propio código de catálogo ("5.1", "5.2"),
        // una numeración distinta y correcta a propósito (posición del
        // rubro en esta obra vs. código de catálogo del subítem, ver
        // docs/rubros_orden_diseno_datos.md §3) — pero mezclar los dos acá
        // arriba chocaba visualmente sin aportar nada que la pantalla
        // anterior (RubrosTab) no mostrara ya.
        title: Text(
          widget.rubro.nombre,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
          // Explícito y más chico que el default del AppBar (~20-22): sin el
          // "N - " el nombre solo, a ese tamaño, se veía desproporcionado
          // respecto del resto de la pantalla. 16 en vez de 17 para dejar
          // margen real con nombres largos como "ESTRUCTURAS METALICAS
          // LIVIANAS" (30 caracteres) — no hay forma de garantizar que
          // entre sin verlo renderizado, así que conviene revisarlo
          // puntualmente con ese rubro.
          style: const TextStyle(fontSize: 16),
        ),
        backgroundColor: const Color(0xFF1B365D),
        foregroundColor: Colors.white,
        // Acción del AppBar, no una fila propia arriba de la lista — esta
        // pantalla ya viene peleando el espacio vertical (ver ajustes de
        // compactación de rubros/subítems); una fila más para "Nuevo
        // subítem" comería justo lo que se ganó. Siempre visible, para PRO
        // y para Free (mismo criterio que "Nuevo Rubro" — Free ve el
        // diálogo de función PRO al tocarlo, no se oculta la función).
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Nuevo subítem',
            onPressed: _cargando ? null : _onNuevoSubitem,
          ),
        ],
      ),
      // Sin esto, tocar fuera de un campo de texto (otra parte de la
      // pantalla que no sea otro campo/checkbox) no le saca el foco —
      // _guardarCantidad/_guardarPrecio dependen de FocusNode.hasFocus
      // pasando a false para dispararse, así que sin unfocus explícito acá
      // el campo podía quedar editado en pantalla sin guardar ni revertir
      // (causa real del bug donde borrar un precio cargado no avisaba ni
      // persistía nada).
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: RefreshIndicator(
          onRefresh: _cargarDatos,
          child: _buildContenido(),
        ),
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
        // Tildado se distingue de un vistazo: fondo apenas azulado + franja
        // de acento a la izquierda. Sin alternar fondos entre filas (cada
        // subítem ya es una tarjeta con margen propio) — la franja/fondo
        // marca el estado, no la posición en la lista.
        return Card(
          margin: const EdgeInsets.only(bottom: 4.0),
          elevation: 1,
          color: aplicable ? const Color(0xFFEAF1FB) : null,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          clipBehavior: Clip.antiAlias,
          // Franja de acento con Container/BoxDecoration, no con Row +
          // CrossAxisAlignment.stretch: ese Row rompía el render (pantalla en
          // blanco) porque dentro de un Card en un ListView.builder la altura
          // no está acotada por el padre — stretch le pedía al Container una
          // altura infinita ("BoxConstraints forces an infinite height").
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: aplicable ? const Color(0xFF1B365D) : Colors.transparent,
                  width: 4,
                ),
              ),
            ),
            child: Column(
              children: [
                ListTile(
                  // dense faltaba acá — rubros_tab.dart sí lo tenía, y reduce
                  // la altura mínima del tile por sí solo, más allá de lo
                  // que ya hacían contentPadding/minVerticalPadding.
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  minVerticalPadding: 0,
                  leading: Checkbox(
                    value: aplicable,
                    // Compacto pero no al mínimo: el tap target de 48x48
                    // default de Material era el piso real de la altura de
                    // la fila, sin importar cuánto se ajustara el resto —
                    // se achica de forma moderada, no al extremo, para no
                    // perder precisión al tocar (app pensada para usarse
                    // en obra).
                    visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
                    onChanged: puedeEditar
                        ? (val) => _toggleSubitem(subitem, val ?? false)
                        : null,
                  ),
                  // La unidad ya se ve en el suffixText del campo de cantidad —
                  // no se repite acá abajo (antes estaba en el subtitle
                  // "Unidad: X").
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
                            // Vuelta a 2 (había subido a 3): con el chevron
                            // como vía para ver el texto completo, no hace
                            // falta que el colapsado muestre todo — es la
                            // compactación pedida tras juntar varios ajustes
                            // que por separado tenían sentido pero acumulados
                            // dejaban entrar solo 4 subítems en pantalla.
                            maxLines: expandido ? null : 2,
                            overflow: expandido ? TextOverflow.visible : TextOverflow.ellipsis,
                            // 13, igual que en RubrosTab (pedido explícito
                            // para que las dos pantallas compactadas queden
                            // consistentes entre sí).
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
                  // Chip "Propio" + borrar, solo para subítems del usuario —
                  // los oficiales no muestran nada acá.
                  trailing: subitem.creadorUsuarioId != null ? _buildTrailingPropio(subitem) : null,
                ),
                // Fila propia debajo del título, ya no en el trailing del
                // ListTile: ahí el alto quedaba fijado por el título (una o dos
                // líneas) y cantidad+precio+subtotal apilados no entraban
                // (overflow de ~26px). Acá el Column de la Card crece lo que
                // haga falta. De paso el título recupera todo el ancho de la
                // Card (antes competía con los 140px del trailing).
                //
                // Rubros con tipoPrecioManual == 'unitario' (1, 20, custom —
                // ver RubrosRepository.crearPersonalizado) agrupan cantidad y
                // precio (las dos entradas) en una fila, y el subtotal (el
                // resultado) va debajo, separado y más prominente — ver
                // _buildSubtotal. Rubros con tipoPrecioManual == 'global' (18
                // Instalaciones, 19 Carpinterías) no tienen cantidad — el
                // precio tipeado ya es el monto total de la partida, sin
                // multiplicar, así que no hay subtotal aparte: mostrarlo
                // repetiría el mismo número que ya está en el campo. Un
                // subítem propio (creadorUsuarioId != null) en un rubro que
                // sí usa APU (usaApu == true, tipoPrecioManual null) también
                // agrupa cantidad+precio+subtotal, igual que 'unitario': un
                // subítem que nadie compuso no tiene de dónde derivar un
                // precio, precio manual es la única opción honesta (ver
                // diagnóstico de esta pieza). El resto (usaApu == true,
                // subítem oficial) sigue mostrando solo cantidad — ahí sí
                // el precio debería venir de APU, cuando ese motor exista.
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                  child: widget.rubro.tipoPrecioManual == 'unitario'
                      ? _buildFilaCantidadPrecioConSubtotal(subitem, aplicable, puedeEditar)
                      : widget.rubro.tipoPrecioManual == 'global'
                          ? _buildCampoPrecio(subitem, aplicable, puedeEditar, hint: 'Monto total')
                          : subitem.creadorUsuarioId != null
                              ? _buildFilaCantidadPrecioConSubtotal(subitem, aplicable, puedeEditar)
                              : Align(
                                  alignment: Alignment.centerRight,
                                  child: SizedBox(
                                    width: 140,
                                    child: _buildCampoCantidad(subitem, aplicable, puedeEditar),
                                  ),
                                ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Cantidad + precio agrupados en una fila, subtotal debajo — usado por
  /// rubros 'unitario' y por cualquier subítem propio (ver _buildContenido,
  /// tiene la misma necesidad de precio manual que 'unitario' aunque el
  /// rubro use APU). Extraído para no duplicarlo entre esos dos casos.
  Widget _buildFilaCantidadPrecioConSubtotal(SubitemCatalogo subitem, bool aplicable, bool puedeEditar) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _buildCampoCantidad(subitem, aplicable, puedeEditar)),
            const SizedBox(width: 8),
            Expanded(child: _buildCampoPrecio(subitem, aplicable, puedeEditar)),
          ],
        ),
        _buildSubtotal(subitem, aplicable),
      ],
    );
  }

  /// Extraído tal cual estaba antes (mismo comportamiento) para poder
  /// convivir con _buildCampoPrecio dentro del Column condicional de
  /// arriba, sin duplicar el TextFormField de cantidad.
  Widget _buildCampoCantidad(SubitemCatalogo subitem, bool aplicable, bool puedeEditar) {
    return TextFormField(
      controller: _controllerPara(subitem),
      focusNode: _focusNodePara(subitem),
      enabled: aplicable && puedeEditar,
      textAlign: TextAlign.right,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      // Es el dato que el usuario está cargando: más peso visual que el
      // texto descriptivo de la fila (título 13, subtítulo 11).
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 6),
        // Normalización solo visual (mayúsculas parejas) — la columna
        // subitems.unidad queda tal cual vino de la planilla original, sin
        // tocar la base. Un `suffix` con padding en vez de `suffixText` para
        // separarla un poco del número (pegada se leía como parte de él).
        suffix: Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            subitem.unidad.toUpperCase(),
            style: const TextStyle(fontSize: 12, color: Colors.black45),
          ),
        ),
      ),
    );
  }

  /// Solo se renderiza para rubros con tipoPrecioManual == 'unitario' (ver
  /// _buildContenido) — mismo campo (`precio_unitario_manual`) para los dos
  /// casos de rubro sin APU, solo cambia el hint: en 'unitario' (Rubros 1,
  /// 20, custom) es precio por unidad, se multiplica por cantidad para el
  /// subtotal (_buildSubtotal). En 'global' (Rubros 18, 19) es el monto
  /// total de la partida directamente — no hay cantidad ni subtotal
  /// aparte, por eso el hint por defecto sigue diciendo "Precio" pero
  /// _buildContenido lo pisa a "Monto total" para ese caso.
  Widget _buildCampoPrecio(
    SubitemCatalogo subitem,
    bool aplicable,
    bool puedeEditar, {
    String hint = 'Precio',
  }) {
    return TextFormField(
      controller: _controllerPrecioPara(subitem),
      focusNode: _focusNodePrecioPara(subitem),
      enabled: aplicable && puedeEditar,
      // Sin textAlign.right: con prefixText el valor se separaba del "$ "
      // (el prefijo queda pegado al borde izquierdo del campo y el número
      // se iba al borde derecho, con un hueco en el medio que lo hacía leer
      // como si el "$" fuera parte del campo de cantidad de al lado).
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 4),
        prefixText: '\$ ',
        prefixStyle: const TextStyle(fontSize: 12, color: Colors.black45),
        // labelText, no hintText: el hint desaparece apenas hay un valor
        // cargado — acá "Monto total" tiene que seguir leyéndose siempre.
        // Con labelText, Flutter lo flota arriba del campo en vez de
        // taparlo con el número.
        labelText: hint,
        labelStyle: const TextStyle(fontSize: 11, color: Colors.black38),
      ),
    );
  }

  /// Output no editable, cantidad × precio — nada nuevo en la base, se
  /// calcula acá con lo que ya está en memoria. Vacío mientras no haya
  /// precio cargado (null), no "$0" — mismo criterio que el resto de la
  /// pantalla: no mostrar un número que no refleja nada real todavía.
  /// También vacío si el subítem está destildado: el dato se preserva en la
  /// base (no se borra al destildar, ver _toggleSubitem), pero mostrar acá
  /// un subtotal con el mismo peso que los activos hace que sume visualmente
  /// como si contara en el presupuesto cuando no cuenta.
  ///
  /// Es el resultado (cantidad y precio son las entradas), así que va en su
  /// propia línea debajo de esas dos, separado con un divisor y con más
  /// peso que antes (11 → 18) para que sea el número más prominente de la
  /// fila, no el más chico.
  Widget _buildSubtotal(SubitemCatalogo subitem, bool aplicable) {
    final obraSubitem = _obraSubitemsPorSubitemId[subitem.id];
    final precio = obraSubitem?.precioUnitarioManual;
    if (precio == null || !aplicable) return const SizedBox.shrink();
    final subtotal = precio * (obraSubitem?.cantidad ?? 0);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: 1, color: Color(0x1F1B365D)),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              CurrencyFormatter.formatARS(subtotal),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1B365D)),
            ),
          ),
        ],
      ),
    );
  }
}
