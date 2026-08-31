import 'package:flutter/material.dart';
import '../../../core/utils/currency_formatter.dart';
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

  /// _parsearPrecio colapsa vacío/no-numérico/negativo en un mismo `null`
  /// para decidir si hay que persistir o no — acá se distingue cuál de los
  /// tres fue en realidad, para no mostrarle al usuario el mismo mensaje
  /// genérico ("inválido") en los tres casos (un número negativo sí es un
  /// número, el problema real es que no puede ser negativo).
  String _mensajeErrorPrecio(String texto) {
    if (texto.isEmpty) {
      return 'El precio no puede quedar vacío una vez cargado. Se restauró el valor anterior.';
    }
    final valor = double.tryParse(texto.replaceAll(',', '.'));
    if (valor == null) return 'Precio inválido. Ingresá solo números.';
    return 'El precio no puede ser negativo.';
  }

  /// Se dispara al perder el foco el campo de precio de un subítem (rubros
  /// con tipoPrecioManual == 'unitario' únicamente, ver _buildContenido).
  ///
  /// Una diferencia real con _guardarCantidad: cantidad siempre arranca en
  /// un valor real (default 0 de la columna), así que un campo vacío
  /// siempre es un error. precio_unitario_manual arranca en `null` recién
  /// tildado — vacío ahí es un estado válido ("todavía no decidido"), no un
  /// error, así que tocar el campo y salir sin tipear nada no dispara
  /// ningún aviso. Si ya había un precio cargado y el campo quedó vacío, sí
  /// es un intento de edición inválido — mismo criterio que cantidad desde
  /// ahí en más.
  Future<void> _guardarPrecio(SubitemCatalogo subitem) async {
    final existente = _obraSubitemsPorSubitemId[subitem.id];
    if (existente == null) return;

    final controller = _preciosControllers[subitem.id];
    if (controller == null) return;

    final texto = controller.text.trim();
    if (texto.isEmpty && existente.precioUnitarioManual == null) return;

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

    final usuarioId = _authService.usuarioActual?.id;
    if (usuarioId == null) return;

    setState(() => _guardando.add(subitem.id));
    try {
      final actualizado = await _obraSubitemsRepository.actualizarPrecioUnitarioManual(
        id: existente.id,
        precio: nuevoPrecio,
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
      controller.text = existente.precioUnitarioManual != null
          ? _formatearCantidad(existente.precioUnitarioManual!)
          : '';
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo guardar el precio. Probá de nuevo.')),
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
        title: Text('${widget.numeroPosicion} - ${widget.rubro.nombre}'),
        backgroundColor: const Color(0xFF1B365D),
        foregroundColor: Colors.white,
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
          margin: const EdgeInsets.only(bottom: 6.0),
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
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  leading: Checkbox(
                    value: aplicable,
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
                            // 3 en vez de 2: no hace falta que entre
                            // completo (para eso está el chevron, que
                            // expande a null/sin límite), pero con 2 cortaba
                            // demasiado pronto en pantallas angostas —
                            // sobre todo tras subir la fuente de 13 a 15.
                            // Una línea más escala con cualquier ancho, a
                            // diferencia de pelear por los pocos px fijos
                            // del checkbox o el chevron.
                            maxLines: expandido ? null : 3,
                            overflow: expandido ? TextOverflow.visible : TextOverflow.ellipsis,
                            // Es lo que el usuario lee para saber qué está
                            // tildando — más peso que antes (13), para que no
                            // quede por debajo de los números que carga al lado.
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
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
                // repetiría el mismo número que ya está en el campo. El
                // resto (usaApu == true) sigue mostrando solo cantidad.
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: widget.rubro.tipoPrecioManual == 'unitario'
                      ? Column(
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
                        )
                      : widget.rubro.tipoPrecioManual == 'global'
                          ? _buildCampoPrecio(subitem, aplicable, puedeEditar, hint: 'Monto total')
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
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
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
        contentPadding: const EdgeInsets.symmetric(vertical: 6),
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
