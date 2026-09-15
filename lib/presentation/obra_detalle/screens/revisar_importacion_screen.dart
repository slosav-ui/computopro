import 'package:flutter/material.dart';
import '../../../data/models/importacion.dart';
import '../../../data/models/importacion_item.dart';
import '../../../data/models/rubro_catalogo.dart';
import '../../../data/models/subitem_catalogo.dart';
import '../../../services/auth_service.dart';
import '../../../services/importaciones_repository.dart';
import '../../../core/utils/parser_numero_ar.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../services/rubros_repository.dart';
import '../../../services/subitems_repository.dart';

/// Revisión de una importación ya procesada (docs/importador_capa2_diseno_datos.md §3): una fila
/// por cada `importaciones_items` extraída, con 3 acciones -- elegir del catálogo, crear como
/// propia, o descartar -- y "Confirmar importación" al final, que vuelca todo lo resuelto en
/// `obra_subitems` de una sola vez (`confirmar_importacion`, atómica).
///
/// Sin fuzzy-matching automático en esta ronda (§3): el usuario busca y elige a mano. "Descartar"
/// no tiene columna propia -- una fila sin `rubro_id`/`subitem_id` ya cuenta como descartada para
/// `confirmar_importacion`; el chip "Descartada" de acá es puramente de esta pantalla, para
/// distinguir "ya la miré y no va" de "todavía no la miré" mientras se revisa. Se pierde si se sale
/// y se vuelve a entrar -- aceptado, mismo criterio "no hace falta columna nueva" del diseño.
class RevisarImportacionScreen extends StatefulWidget {
  final String obraId;
  final String importacionId;

  const RevisarImportacionScreen({
    Key? key,
    required this.obraId,
    required this.importacionId,
  }) : super(key: key);

  @override
  State<RevisarImportacionScreen> createState() =>
      _RevisarImportacionScreenState();
}

class _RevisarImportacionScreenState extends State<RevisarImportacionScreen> {
  final ImportacionesRepository _importacionesRepository =
      ImportacionesRepository();
  final RubrosRepository _rubrosRepository = RubrosRepository();
  final SubitemsRepository _subitemsRepository = SubitemsRepository();
  final AuthService _authService = AuthService();

  bool _cargando = true;
  String? _error;
  Importacion? _importacion;
  List<ImportacionItem> _items = [];
  List<RubroCatalogo> _rubros = [];
  List<SubitemCatalogo> _subitems = [];
  final Set<String> _descartados = {};
  bool _confirmando = false;

  String? get _usuarioId => _authService.usuarioActual?.id;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final importacion = await _importacionesRepository.getImportacion(
        widget.importacionId,
      );
      final items = await _importacionesRepository.getItems(
        widget.importacionId,
      );
      // `obraId` (tanda 5): el buscador de "elegir del catálogo" también tiene que ofrecer lo que
      // ya está en la carpeta de esta obra -- si no, reimportar no encontraría nunca las partidas
      // de la importación anterior y crearía todo de nuevo.
      final rubros = await _rubrosRepository.getCatalogoCompleto(
        _usuarioId ?? '',
        obraId: widget.obraId,
      );
      final subitems = await _subitemsRepository.getTodos(
        usuarioId: _usuarioId,
        obraId: widget.obraId,
      );
      if (!mounted) return;
      setState(() {
        _importacion = importacion;
        _items = _ordenadas(items);
        _rubros = rubros;
        _subitems = subitems;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar la importación. Probá de nuevo.';
      });
    }
  }

  /// Lo dudoso primero.
  ///
  /// Con 97 partidas, una fila que el modelo marcó "baja" en el puesto 60 no la ve nadie. El orden
  /// del documento deja de ser el mejor orden apenas hay filas de distinta calidad -- y el orden
  /// original no se pierde, sigue escrito en `orden` y se muestra como desempate.
  ///
  /// Para una importación de Excel esto no cambia nada: sin confianza, todas las filas empatan en
  /// el mismo grupo y quedan en el orden del archivo.
  List<ImportacionItem> _ordenadas(List<ImportacionItem> items) {
    final copia = [...items];
    copia.sort((a, b) {
      final porConfianza = a.ordenDeRevision.compareTo(b.ordenDeRevision);
      return porConfianza != 0 ? porConfianza : a.orden.compareTo(b.orden);
    });
    return copia;
  }

  Future<void> _recargarItems() async {
    final items = await _importacionesRepository.getItems(widget.importacionId);
    if (!mounted) return;
    setState(() => _items = _ordenadas(items));
  }

  RubroCatalogo? _rubroDe(ImportacionItem item) {
    if (item.rubroId == null) return null;
    for (final r in _rubros) {
      if (r.id == item.rubroId) return r;
    }
    return null;
  }

  SubitemCatalogo? _subitemDe(ImportacionItem item) {
    if (item.subitemId == null) return null;
    for (final s in _subitems) {
      if (s.id == item.subitemId) return s;
    }
    return null;
  }

  /// Aviso antes de pisar una fila que ya estaba resuelta (por cualquiera de las dos acciones) --
  /// sin esto, tocar una acción sobre una fila ya resuelta la reemplazaba en silencio, sin decir
  /// qué tenía antes. `true` = seguir adelante, `false`/cancelado = no tocar nada.
  Future<bool> _confirmarSiYaResuelta(ImportacionItem item) async {
    if (!item.resuelta) return true;
    final rubro = _rubroDe(item);
    final subitem = _subitemDe(item);
    final actual = rubro != null && subitem != null
        ? '${rubro.nombre} · ${subitem.descripcion}'
        : 'otra partida';
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text(
          '¿Reemplazar la elección?',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Esta fila ya está resuelta contra "$actual". ¿La reemplazás?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Reemplazar'),
          ),
        ],
      ),
    );
    return confirmar == true;
  }

  Future<void> _elegirDelCatalogo(ImportacionItem item) async {
    if (!await _confirmarSiYaResuelta(item)) return;
    if (!mounted) return;
    final elegido = await showDialog<SubitemCatalogo>(
      context: context,
      builder: (_) =>
          _DialogoBuscarSubitem(subitems: _subitems, rubros: _rubros),
    );
    if (elegido == null) return;
    try {
      await _importacionesRepository
          .resolverItem(
            item.id,
            rubroId: elegido.rubroId,
            subitemId: elegido.id,
          )
          .timeout(const Duration(seconds: 20));
      setState(() => _descartados.remove(item.id));
      await _recargarItems();
    } catch (e, st) {
      debugPrint('_elegirDelCatalogo falló: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar la elección: $e')),
      );
    }
  }

  Future<void> _crearComoPropia(ImportacionItem item) async {
    debugPrint(
      '_crearComoPropia: tap en item ${item.id} (descripcion=${item.descripcionTexto})',
    );
    if (!await _confirmarSiYaResuelta(item)) return;
    final usuarioId = _usuarioId;
    if (usuarioId == null) {
      debugPrint('_crearComoPropia: usuarioId null, no se abre el diálogo');
      return;
    }
    if (!mounted) return;
    final resultado = await showDialog<bool>(
      context: context,
      builder: (_) => _DialogoCrearPropia(
        item: item,
        obraId: widget.obraId,
        rubros: _rubros,
        subitems: _subitems,
        usuarioId: usuarioId,
        rubrosRepository: _rubrosRepository,
        subitemsRepository: _subitemsRepository,
        importacionesRepository: _importacionesRepository,
      ),
    );
    if (resultado != true) return;
    setState(() => _descartados.remove(item.id));
    // El diálogo ya creó/actualizó todo en el servidor -- se recarga catálogo completo (puede
    // haber un rubro o subítem nuevo) además de los items.
    await _cargar();
  }

  Future<void> _descartar(ImportacionItem item) async {
    if (item.resuelta) {
      try {
        await _importacionesRepository
            .desresolverItem(item.id)
            .timeout(const Duration(seconds: 20));
        await _recargarItems();
      } catch (e, st) {
        debugPrint('_descartar falló: $e\n$st');
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('No se pudo descartar: $e')));
        return;
      }
    }
    setState(() => _descartados.add(item.id));
  }

  Future<void> _confirmar() async {
    final resueltos = _items.where((i) => i.resuelta).length;
    if (resueltos == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No hay ninguna fila resuelta todavía -- elegí del catálogo o creá al menos una.',
          ),
        ),
      );
      return;
    }
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text(
          'Confirmar importación',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        content: Text(
          '$resueltos de ${_items.length} filas se van a cargar en el cómputo de esta obra. '
          'Las que quedaron sin resolver o descartadas no se cargan. Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    setState(() => _confirmando = true);
    try {
      await _importacionesRepository
          .confirmarImportacion(widget.importacionId)
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e, st) {
      debugPrint('_confirmar falló: $e\n$st');
      if (!mounted) return;
      setState(() => _confirmando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo confirmar la importación: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Revisar importación${_importacion != null ? ' (${_items.length})' : ''}',
        ),
        backgroundColor: const Color(0xFF1B365D),
        foregroundColor: Colors.white,
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            )
          : _items.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No se encontraron filas en las hojas elegidas.',
                  style: TextStyle(color: Colors.black54),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                // +1: la verificación de la suma va arriba de todo, no al pie. Es lo primero que
                // hay que mirar, porque decide si vale la pena revisar fila por fila o si conviene
                // volver a leer el documento.
                itemCount: _items.length + 1,
                itemBuilder: (context, index) => index == 0
                    ? _buildControlDeTotal()
                    : _buildFila(_items[index - 1]),
              ),
            ),
      bottomNavigationBar: _cargando || _error != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: ElevatedButton(
                  onPressed: _confirmando ? null : _confirmar,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                  ),
                  child: _confirmando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Confirmar importación'),
                ),
              ),
            ),
    );
  }

  /// La suma de lo interpretado contra el total impreso en el documento.
  ///
  /// **Es la única verificación de esta pantalla que no se apoya en la misma lectura que está bajo
  /// sospecha.** Todo lo demás (la confianza, el texto original, hasta la descripción) sale del
  /// modelo; esto sale de comparar dos números que tienen que dar igual. Si una cantidad se leyó
  /// 41096 donde decía 410,96, acá se nota aunque la fila parezca perfecta.
  ///
  /// Solo aparece en importaciones que leyó un modelo: para el Excel determinístico no hay un total
  /// impreso que contrastar, y un cartel que no puede decir nada es ruido.
  Widget _buildControlDeTotal() {
    final leyoUnModelo = _items.any((i) => i.confianza != null);
    if (!leyoUnModelo) return const SizedBox.shrink();

    final moneda = _importacion?.monedaDefault ?? 'ARS';
    final suma = _items
        .where((i) => !_descartados.contains(i.id))
        .fold<double>(0, (acc, i) => acc + (i.cantidad ?? 0) * (i.precioUnitario ?? 0));
    final declarado = _importacion?.totalDeclarado;

    if (declarado == null) {
      // Decirlo es mejor que callarlo: el usuario tiene que saber que este control no corrió, para
      // no confundir "no hay aviso" con "está todo bien".
      return _cartel(
        icono: Icons.info_outline,
        color: Colors.grey.shade700,
        fondo: Colors.grey.shade100,
        borde: Colors.grey.shade300,
        titulo: 'El documento no traía un total al pie',
        detalle: 'Lo importado suma ${CurrencyFormatter.formatByCurrency(suma, moneda)}. No hay con '
            'qué contrastarlo, así que conviene revisar las filas con atención.',
      );
    }

    final diferencia = suma - declarado;
    // Tolerancia: los redondeos por partida se acumulan, y un presupuesto de 97 filas nunca cierra
    // al centavo. Medio por ciento del total, con un piso de un peso para montos chicos.
    final tolerancia = (declarado.abs() * 0.005).clamp(1.0, double.infinity);

    if (diferencia.abs() <= tolerancia) {
      return _cartel(
        icono: Icons.check_circle_outline,
        color: Colors.green.shade800,
        fondo: Colors.green.shade50,
        borde: Colors.green.shade200,
        titulo: 'La suma coincide con el total del documento',
        detalle: '${CurrencyFormatter.formatByCurrency(suma, moneda)}. Es buena señal, pero no '
            'garantiza que cada partida esté bien: revisá igual las marcadas para revisar.',
      );
    }

    final pct = declarado == 0 ? 0.0 : (diferencia / declarado) * 100;
    return _cartel(
      icono: Icons.error_outline,
      color: Colors.red.shade800,
      fondo: Colors.red.shade50,
      borde: Colors.red.shade200,
      titulo: 'La suma no coincide con el total del documento',
      detalle: 'Lo importado suma ${CurrencyFormatter.formatByCurrency(suma, moneda)} y el '
          'documento dice ${CurrencyFormatter.formatByCurrency(declarado, moneda)}: '
          '${diferencia > 0 ? "sobran" : "faltan"} '
          '${CurrencyFormatter.formatByCurrency(diferencia.abs(), moneda)} '
          '(${pct.abs().toStringAsFixed(1)}%). Casi siempre es una cantidad o un precio leído mal, '
          'o una partida que no se leyó.',
    );
  }

  Widget _cartel({
    required IconData icono,
    required Color color,
    required Color fondo,
    required Color borde,
    required String titulo,
    required String detalle,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borde),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo,
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color)),
                const SizedBox(height: 3),
                Text(detalle,
                    style: TextStyle(fontSize: 11.5, height: 1.45, color: Colors.grey.shade800)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Corregir lo que el modelo leyó mal.
  ///
  /// **Esta acción faltaba, y era el agujero grande del importador**: la pantalla sabía mapear una
  /// fila al catálogo o descartarla, pero no arreglar un número. Con el parser de Excel se podía
  /// vivir sin esto; con un modelo de por medio no, porque el error típico es justamente un número
  /// mal leído que llega con toda la cara de estar bien.
  Future<void> _corregirValores(ImportacionItem item) async {
    final cambios = await showDialog<_ValoresCorregidos>(
      context: context,
      builder: (_) => _DialogoCorregirValores(item: item),
    );
    if (cambios == null) return;
    try {
      await _importacionesRepository.actualizarItem(
        item.id,
        descripcionTexto: cambios.descripcion,
        unidadTexto: cambios.unidad,
        cantidad: cambios.cantidad,
        precioUnitario: cambios.precioUnitario,
        limpiarCantidad: cambios.limpiarCantidad,
        limpiarPrecio: cambios.limpiarPrecio,
      );
      await _recargarItems();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo guardar la corrección: $e')));
    }
  }

  /// El aviso de que esta fila conviene mirarla, con el texto original al lado.
  ///
  /// El texto original es la mitad que hace útil a la otra: "cant. 41096" sola parece un dato;
  /// "cant. 41096" junto a la línea que decía "410,96" es un error evidente.
  Widget _buildConfianza(ImportacionItem item) {
    if (item.confianza == null || item.confianza == 'alta') {
      if (item.textoOriginal == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text('En el documento: ${item.textoOriginal}',
            style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600, height: 1.3)),
      );
    }

    final baja = item.confianza == 'baja';
    final color = baja ? Colors.red.shade700 : Colors.orange.shade800;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.priority_high, size: 13, color: color),
              const SizedBox(width: 3),
              Text(
                baja ? 'Revisar: la lectura es dudosa' : 'Revisar: hubo que interpretar',
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color),
              ),
            ],
          ),
          if (item.textoOriginal != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('En el documento: ${item.textoOriginal}',
                  style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700, height: 1.3)),
            ),
        ],
      ),
    );
  }

  Widget _buildFila(ImportacionItem item) {
    final descartada = _descartados.contains(item.id);
    final rubro = _rubroDe(item);
    final subitem = _subitemDe(item);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: descartada ? Colors.black.withValues(alpha: 0.03) : null,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    item.descripcionTexto ?? '(sin descripción)',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      decoration: descartada
                          ? TextDecoration.lineThrough
                          : null,
                      color: descartada ? Colors.black38 : Colors.black87,
                    ),
                  ),
                ),
                _buildEstado(item, descartada),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              [
                if (item.rubroTexto != null) item.rubroTexto!,
                if (item.unidadTexto != null) item.unidadTexto!,
                if (item.cantidad != null) 'cant. ${item.cantidad}',
                if (item.precioUnitario != null)
                  'p.unit. ${item.precioUnitario} ${item.moneda ?? _importacion?.monedaDefault ?? ''}',
              ].join(' · '),
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
            _buildConfianza(item),
            if (rubro != null && subitem != null) ...[
              const SizedBox(height: 4),
              Text(
                '-> ${rubro.nombre} · ${subitem.descripcion}',
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF1B365D),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                OutlinedButton(
                  onPressed: () => _elegirDelCatalogo(item),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                  child: const Text('Elegir del catálogo'),
                ),
                OutlinedButton(
                  onPressed: () => _crearComoPropia(item),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                  child: const Text('Crear como propia'),
                ),
                OutlinedButton(
                  onPressed: () => _corregirValores(item),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                  child: const Text('Corregir valores'),
                ),
                TextButton(
                  onPressed: () => _descartar(item),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(fontSize: 11),
                    foregroundColor: Colors.red,
                  ),
                  child: const Text('Descartar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEstado(ImportacionItem item, bool descartada) {
    if (descartada) {
      return const Icon(
        Icons.remove_circle_outline,
        size: 18,
        color: Colors.black38,
      );
    }
    if (item.resuelta) {
      return const Icon(Icons.check_circle, size: 18, color: Colors.green);
    }
    return const Icon(Icons.help_outline, size: 18, color: Colors.orange);
  }
}

/// Buscador de subítem existente (acción "elegir del catálogo") -- catálogo ya cargado por
/// RevisarImportacionScreen, filtro local, sin ida al servidor por cada letra tipeada.
class _DialogoBuscarSubitem extends StatefulWidget {
  final List<SubitemCatalogo> subitems;
  final List<RubroCatalogo> rubros;

  const _DialogoBuscarSubitem({required this.subitems, required this.rubros});

  @override
  State<_DialogoBuscarSubitem> createState() => _DialogoBuscarSubitemState();
}

class _DialogoBuscarSubitemState extends State<_DialogoBuscarSubitem> {
  final TextEditingController _controller = TextEditingController();
  List<SubitemCatalogo> _resultados = [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _nombreRubro(String rubroId) {
    for (final r in widget.rubros) {
      if (r.id == rubroId) return r.nombre;
    }
    return '?';
  }

  void _buscar(String texto) {
    final termino = texto.trim().toLowerCase();
    if (termino.isEmpty) {
      setState(() => _resultados = []);
      return;
    }
    setState(() {
      _resultados = widget.subitems
          .where(
            (s) =>
                s.descripcion.toLowerCase().contains(termino) ||
                _nombreRubro(s.rubroId).toLowerCase().contains(termino),
          )
          .take(30)
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'Elegir del catálogo',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.bold,
          color: Color(0xFF1B365D),
        ),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              onChanged: _buscar,
              decoration: const InputDecoration(
                hintText: 'Buscar por descripción o rubro...',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: _resultados.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Sin resultados.',
                        style: TextStyle(fontSize: 12, color: Colors.black45),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _resultados.length,
                      itemBuilder: (context, index) {
                        final s = _resultados[index];
                        return ListTile(
                          dense: true,
                          title: Text(
                            s.descripcion,
                            style: const TextStyle(fontSize: 12),
                          ),
                          subtitle: Text(
                            _nombreRubro(s.rubroId),
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.black45,
                            ),
                          ),
                          trailing: Text(
                            s.unidad,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.black45,
                            ),
                          ),
                          onTap: () => Navigator.pop(context, s),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}

/// Alta de rubro (si hace falta) + subítem propio a partir de lo extraído de una fila, y vínculo
/// de esa fila con lo recién creado -- acción "crear como propia" (§3 del diseño). Devuelve `true`
/// por Navigator.pop si guardó, `null`/`false` si se canceló.
class _DialogoCrearPropia extends StatefulWidget {
  final ImportacionItem item;
  /// La obra en cuya carpeta cae todo lo que este diálogo crea. **No es opcional y no tiene
  /// default**: que lo importado vaya a la carpeta y no al catálogo personal es la mitad de la
  /// pieza que evita que las obras se mezclen (§2 del doc). Un `null` acá reintroduce el bug de
  /// las partidas duplicadas.
  final String obraId;
  final List<RubroCatalogo> rubros;
  final List<SubitemCatalogo> subitems;
  final String usuarioId;
  final RubrosRepository rubrosRepository;
  final SubitemsRepository subitemsRepository;
  final ImportacionesRepository importacionesRepository;

  const _DialogoCrearPropia({
    required this.item,
    required this.obraId,
    required this.rubros,
    required this.subitems,
    required this.usuarioId,
    required this.rubrosRepository,
    required this.subitemsRepository,
    required this.importacionesRepository,
  });

  @override
  State<_DialogoCrearPropia> createState() => _DialogoCrearPropiaState();
}

class _DialogoCrearPropiaState extends State<_DialogoCrearPropia> {
  late final TextEditingController _rubroController;
  late final TextEditingController _descripcionController;
  late final TextEditingController _unidadController;

  RubroCatalogo? _rubroElegido;
  List<RubroCatalogo> _resultadosRubro = [];
  String? _error;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    debugPrint(
      '_DialogoCrearPropiaState.initState: abriendo para item ${widget.item.id}',
    );
    _rubroController = TextEditingController(
      text: widget.item.rubroTexto ?? '',
    );
    _descripcionController = TextEditingController(
      text: widget.item.descripcionTexto ?? '',
    );
    _unidadController = TextEditingController(
      text: widget.item.unidadTexto ?? '',
    );
    if (_rubroController.text.trim().isNotEmpty)
      _buscarRubro(_rubroController.text);
  }

  @override
  void dispose() {
    _rubroController.dispose();
    _descripcionController.dispose();
    _unidadController.dispose();
    super.dispose();
  }

  void _buscarRubro(String texto) {
    final termino = texto.trim().toLowerCase();
    setState(() {
      _rubroElegido = null;
      _resultadosRubro = termino.isEmpty
          ? []
          : widget.rubros
                .where((r) => r.nombre.toLowerCase().contains(termino))
                .take(15)
                .toList();
      // Bug real encontrado 2026-09-07: si el texto matchea EXACTO (sin mayúsculas) el nombre de
      // un rubro real, se autoselecciona -- antes había que tocar a mano una sugerencia de la
      // lista, y si no se hacía (típico: el texto ya viene prellenado con rubro_texto de la fila
      // importada, y ya es el nombre correcto, así que no parece hacer falta tocar nada más),
      // _guardar() creaba un rubro DUPLICADO en vez de reusar el real. Un rubro recién creado
      // siempre nace con orden=0 y sin subítems, así que _siguienteCodigo no tenía de dónde sacar
      // un prefijo real y siempre daba "0.1" -- exactamente lo que apareció con las 7 partidas de
      // la prueba real.
      for (final r in widget.rubros) {
        if (r.nombre.toLowerCase() == termino) {
          _rubroElegido = r;
          _resultadosRubro = [];
          break;
        }
      }
    });
  }

  /// Código para el subítem propio nuevo, mismo espíritu que
  /// SubitemsScreen._siguienteCodigoPropio pero sin la numeración posicional real de la obra (no
  /// está disponible acá) -- se usa el prefijo que ya usan los subítems existentes de este rubro
  /// (típico en los oficiales, ej. "8.1"..."8.9"), o el `orden` del rubro si todavía no tiene
  /// ninguno. Es solo para que se lea bien en la lista -- no hace falta que sea único ni exacto
  /// (ver SubitemsRepository.crearPersonalizado).
  ///
  /// Bug real encontrado 2026-09-07: antes miraba `widget.subitems`, una foto de TODO el catálogo
  /// tomada una sola vez al abrir la revisión -- a diferencia de SubitemsScreen (que siempre mira
  /// un solo rubro en vivo), acá esa foto podía quedar corta o desactualizada, así que el máximo
  /// no siempre reflejaba la última partida real del rubro y la numeración no quedaba correlativa
  /// ("1.9" existente -> tendría que dar "1.10", no reiniciar). Ahora relee ese rubro puntual en
  /// vivo justo antes de crear, con `SubitemsRepository.getSubitemsDeRubro` -- la misma consulta
  /// que ya usa SubitemsScreen, siempre al día, y de paso también correcta si en la misma revisión
  /// se crean dos propios seguidos para el mismo rubro (el segundo ya ve al primero).
  Future<String> _siguienteCodigo(RubroCatalogo rubro) async {
    final delRubro = await widget.subitemsRepository.getSubitemsDeRubro(
      rubro.id,
      usuarioId: widget.usuarioId,
      obraId: widget.obraId,
    );
    String primerSegmento = rubro.orden.toString();
    var maxSegundo = 0;
    for (final s in delRubro) {
      final partes = s.codigo.split('.');
      if (partes.isEmpty) continue;
      final primero = int.tryParse(partes.first);
      if (primero != null) primerSegmento = partes.first;
      if (partes.length < 2) continue;
      final segundo = int.tryParse(partes[1]);
      if (segundo != null && segundo > maxSegundo) maxSegundo = segundo;
    }

    // Desde la 0151 el código tiene que ser único en TODA la carpeta de la obra
    // (`subitems_codigo_obra_unique`), no solo dentro del rubro. Dos rubros distintos de la misma
    // carpeta pueden derivar el mismo `primerSegmento` -- por ejemplo si los dos arrancan sin
    // partidas y caen en el `rubro.orden` -- y el segundo en llegar reventaría con un error sin
    // explicación. Se avanza hasta el primero libre; un hueco en la secuencia no significa nada.
    final ocupados = await widget.subitemsRepository.getCodigosDeObra(widget.obraId);
    var siguiente = maxSegundo + 1;
    while (ocupados.contains('$primerSegmento.$siguiente')) {
      siguiente++;
    }
    return '$primerSegmento.$siguiente';
  }

  Future<void> _guardar() async {
    debugPrint(
      '_DialogoCrearPropiaState._guardar: entrando, antes de cualquier await',
    );
    final nombreRubro = _rubroController.text.trim();
    final descripcion = _descripcionController.text.trim();
    final unidad = _unidadController.text.trim();
    if (nombreRubro.isEmpty) {
      setState(() => _error = 'Completá el rubro.');
      return;
    }
    if (descripcion.isEmpty) {
      setState(() => _error = 'Completá la descripción.');
      return;
    }
    if (unidad.isEmpty) {
      setState(() => _error = 'Completá la unidad.');
      return;
    }

    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      // Timeout explícito: sin esto, un llamado que se cuelga (red, RLS, lo que sea) deja el
      // diálogo con el spinner girando para siempre, sin error y sin forma de salir -- exactamente
      // el síntoma reportado ("no da error ni completa la acción"). Con el timeout, al menos hay
      // una excepción que cae en el catch de abajo.
      await (() async {
        var rubro = _rubroElegido;
        // **El cambio de fondo de la tanda 5**: lo que crea el importador va a la carpeta de la
        // obra, no al catálogo personal. Antes iba al catálogo, y por eso una planilla importada
        // aparecía en el Cómputo de todas las obras del usuario -- el origen de las partidas
        // duplicadas que Seba vio en el teléfono.
        rubro ??= await widget.rubrosRepository.crearPersonalizado(
          nombre: nombreRubro,
          creadorUsuarioId: widget.usuarioId,
          obraId: widget.obraId,
        );

        // `obraId` solo si el rubro es de la carpeta: si el usuario eligió un rubro del catálogo en
        // el buscador, la partida cuelga de ahí y va como "solo en esta obra" igual -- que es el
        // caso que la 0151 habilita a propósito (§4.2). Mandar la carpeta con un rubro del catálogo
        // sería coherente; al revés no, y el trigger lo rechazaría.
        final subitem = await widget.subitemsRepository.crearPersonalizado(
          rubroId: rubro.id,
          codigo: await _siguienteCodigo(rubro),
          obraId: widget.obraId,
          descripcion: descripcion,
          unidad: unidad,
          creadorUsuarioId: widget.usuarioId,
        );

        await widget.importacionesRepository.resolverItem(
          widget.item.id,
          rubroId: rubro.id,
          subitemId: subitem.id,
        );
      })().timeout(const Duration(seconds: 20));
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e, st) {
      // El mensaje en pantalla queda genérico, pero el real (y de qué llamada vino, con el stack)
      // va a la consola -- mismo criterio que ya se aplicó para el selector de archivo del
      // importador y para el bug de la fila de equipo en blanco.
      debugPrint('_DialogoCrearPropia._guardar falló: $e\n$st');
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _error = 'No se pudo crear. Detalle en consola: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'Crear como propia',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.bold,
          color: Color(0xFF1B365D),
        ),
      ),
      // SizedBox con ancho explícito, mismo motivo que ya resuelve _DialogoBuscarSubitem más abajo:
      // AlertDialog mide el ancho intrínseco de su content, y el ListView.builder de resultados de
      // rubro (más abajo, un viewport) no puede responder esa pregunta -- sin este SizedBox tira
      // "RenderShrinkWrappingViewport does not support returning intrinsic dimensions" apenas se
      // abre el diálogo, antes de que el usuario llegue a tocar nada.
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _rubroController,
                onChanged: _buscarRubro,
                decoration: const InputDecoration(
                  labelText: 'Rubro',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(fontSize: 13),
              ),
              if (_rubroElegido != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Rubro existente: ${_rubroElegido!.nombre}',
                    style: const TextStyle(fontSize: 11, color: Colors.green),
                  ),
                )
              else if (_resultadosRubro.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  constraints: const BoxConstraints(maxHeight: 140),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.black12),
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _resultadosRubro.length,
                    itemBuilder: (context, index) {
                      final r = _resultadosRubro[index];
                      return ListTile(
                        dense: true,
                        title: Text(
                          r.nombre,
                          style: const TextStyle(fontSize: 12),
                        ),
                        onTap: () => setState(() {
                          _rubroElegido = r;
                          _rubroController.text = r.nombre;
                          _resultadosRubro = [];
                        }),
                      );
                    },
                  ),
                )
              else if (_rubroController.text.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Se crea un rubro propio nuevo: "${_rubroController.text.trim()}"',
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _descripcionController,
                decoration: const InputDecoration(
                  labelText: 'Descripción',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _unidadController,
                decoration: const InputDecoration(
                  labelText: 'Unidad',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(fontSize: 13),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _guardando ? null : _guardar,
          child: _guardando
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Crear y usar'),
        ),
      ],
    );
  }
}


/// Lo que devuelve el diálogo de corrección. Los dos `limpiar*` distinguen "no lo toqué" de
/// "quiero que quede vacío", que con un `double?` solo no se puede decir.
class _ValoresCorregidos {
  final String? descripcion;
  final String? unidad;
  final double? cantidad;
  final double? precioUnitario;
  final bool limpiarCantidad;
  final bool limpiarPrecio;

  const _ValoresCorregidos({
    this.descripcion,
    this.unidad,
    this.cantidad,
    this.precioUnitario,
    this.limpiarCantidad = false,
    this.limpiarPrecio = false,
  });
}

/// Corregir los valores de una fila importada.
///
/// Los números se leen con [ParserNumeroAr], que es la única lógica de coma/punto del proyecto
/// (ver la memoria "bug_separador_miles_mat_y_mo" para el diagnóstico que la motivó). Acá importa
/// más que en ningún otro lado: el usuario está corrigiendo justamente un número que se leyó mal, y
/// sería absurdo que la corrección se guardara mal por la misma clase de error.
///
/// Y se muestra el valor interpretado debajo de cada campo mientras se escribe, con un aviso
/// reforzado en el caso genuinamente ambiguo ("1.500" puede ser mil quinientos o uno con medio).
class _DialogoCorregirValores extends StatefulWidget {
  final ImportacionItem item;

  const _DialogoCorregirValores({required this.item});

  @override
  State<_DialogoCorregirValores> createState() => _DialogoCorregirValoresState();
}

class _DialogoCorregirValoresState extends State<_DialogoCorregirValores> {
  late final TextEditingController _descripcion;
  late final TextEditingController _unidad;
  late final TextEditingController _cantidad;
  late final TextEditingController _precio;

  @override
  void initState() {
    super.initState();
    _descripcion = TextEditingController(text: widget.item.descripcionTexto ?? '');
    _unidad = TextEditingController(text: widget.item.unidadTexto ?? '');
    _cantidad = TextEditingController(text: _aTexto(widget.item.cantidad));
    _precio = TextEditingController(text: _aTexto(widget.item.precioUnitario));
  }

  @override
  void dispose() {
    _descripcion.dispose();
    _unidad.dispose();
    _cantidad.dispose();
    _precio.dispose();
    super.dispose();
  }

  /// Se muestra con coma decimal porque es como se escribe acá, y porque el campo se vuelve a leer
  /// con ParserNumeroAr: si se mostrara con punto, reabrir y guardar sin tocar nada podría cambiar
  /// el valor.
  String _aTexto(double? valor) {
    if (valor == null) return '';
    final texto = valor == valor.roundToDouble()
        ? valor.toStringAsFixed(0)
        : valor.toStringAsFixed(2);
    return texto.replaceAll('.', ',');
  }

  void _guardar() {
    final cantidadTexto = _cantidad.text.trim();
    final precioTexto = _precio.text.trim();
    Navigator.pop(
      context,
      _ValoresCorregidos(
        descripcion: _descripcion.text.trim().isEmpty ? null : _descripcion.text.trim(),
        unidad: _unidad.text.trim().isEmpty ? null : _unidad.text.trim(),
        cantidad: ParserNumeroAr.parsear(cantidadTexto),
        precioUnitario: ParserNumeroAr.parsear(precioTexto),
        limpiarCantidad: cantidadTexto.isEmpty,
        limpiarPrecio: precioTexto.isEmpty,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final original = widget.item.textoOriginal;
    return AlertDialog(
      title: const Text('Corregir valores', style: TextStyle(fontSize: 16)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (original != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('En el documento dice',
                        style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
                    const SizedBox(height: 3),
                    Text(original,
                        style: const TextStyle(fontSize: 12, height: 1.35, color: Colors.black87)),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],
            TextField(
              controller: _descripcion,
              decoration: const InputDecoration(labelText: 'Descripción', isDense: true),
              style: const TextStyle(fontSize: 13),
              maxLines: null,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _unidad,
              decoration: const InputDecoration(labelText: 'Unidad', isDense: true),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            _campoNumero(_cantidad, 'Cantidad'),
            const SizedBox(height: 12),
            _campoNumero(_precio, 'Precio unitario'),
            const SizedBox(height: 10),
            Text(
              'Dejar un número vacío lo borra: una partida sin precio es una partida sin precio, y '
              'es mejor que un número inventado.',
              style: TextStyle(fontSize: 10.5, height: 1.35, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(onPressed: _guardar, child: const Text('Guardar')),
      ],
    );
  }

  Widget _campoNumero(TextEditingController ctrl, String etiqueta) {
    final texto = ctrl.text.trim();
    final valor = ParserNumeroAr.parsear(texto);
    final ambiguo = ParserNumeroAr.esInterpretacionDeMiles(texto);
    final alternativa = ambiguo ? ParserNumeroAr.lecturaAlternativaSiEsMiles(texto) : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: etiqueta, isDense: true),
          style: const TextStyle(fontSize: 13),
          onChanged: (_) => setState(() {}),
        ),
        if (texto.isNotEmpty) ...[
          const SizedBox(height: 4),
          if (valor == null)
            Text('No se entiende como número',
                style: TextStyle(fontSize: 10.5, color: Colors.red.shade700))
          else if (ambiguo)
            Text(
              'Se va a guardar ${valor.toStringAsFixed(2).replaceAll('.', ',')} '
              '(si querías ${alternativa?.toStringAsFixed(2).replaceAll('.', ',')}, '
              'escribilo con coma)',
              style: TextStyle(fontSize: 10.5, color: Colors.orange.shade800, height: 1.3),
            )
          else
            Text('Se va a guardar ${valor.toStringAsFixed(2).replaceAll('.', ',')}',
                style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
        ],
      ],
    );
  }
}
