import 'package:flutter/material.dart';
import '../../../core/utils/parser_numero_ar.dart';
import '../../../data/models/insumo_consolidado_obra.dart';
import '../../../services/auth_service.dart';
import '../../../services/obra_insumos_repository.dart';

/// Una sección de la lista de insumos (título, ícono, predicado sobre `InsumoConsolidadoObra.tipo`).
/// Agregar una sección nueva (ej. "Equipos") es sumar una entrada acá — no reescribir el filtrado.
class _SeccionInsumos {
  final String titulo;
  final IconData icono;
  final bool Function(InsumoConsolidadoObra) predicado;

  const _SeccionInsumos(this.titulo, this.icono, this.predicado);
}

/// Solapa "Mat y MO" — paso 3 de la pieza (ver memoria "mat_y_mo_fuentes_precio"): consolidado
/// real de insumos de la obra, con edición manual de precio por insumo. Reemplaza el mock que
/// tenía `presupuestos_screen.dart._buildTabMaterialesYMo()`.
class MatYMoTab extends StatefulWidget {
  final String obraId;

  const MatYMoTab({Key? key, required this.obraId}) : super(key: key);

  @override
  State<MatYMoTab> createState() => _MatYMoTabState();
}

class _MatYMoTabState extends State<MatYMoTab> {
  final ObraInsumosRepository _obraInsumosRepository = ObraInsumosRepository();
  final AuthService _authService = AuthService();

  // Sin sección propia de Equipos todavía (mismo criterio que el badge de presupuesto en firme:
  // no construir el caso que no existe, pero dejar la estructura lista) — 'equipo' cae bajo
  // Materiales hasta que haga falta separarlo.
  static final List<_SeccionInsumos> _secciones = [
    _SeccionInsumos('Mano de obra', Icons.engineering, (i) => i.tipo == 'mano_obra'),
    _SeccionInsumos('Materiales', Icons.inventory_2, (i) => i.tipo != 'mano_obra'),
  ];

  List<InsumoConsolidadoObra> _insumos = [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarConsolidado();
  }

  Future<void> _cargarConsolidado() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final insumos = await _obraInsumosRepository.getConsolidado(widget.obraId);
      if (!mounted) return;
      setState(() {
        _insumos = insumos;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar el consolidado de insumos de esta obra.';
        _cargando = false;
      });
    }
  }

  String _fmtCantidad(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2);
  }

  String _fmtPrecio(double monto) {
    final valorInt = monto.round();
    final str = valorInt.toString();
    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    final formateado = str.replaceAllMapped(reg, (Match m) => '${m[1]}.');
    return '\$ $formateado';
  }

  /// A diferencia de _fmtPrecio (redondea al peso, para la card), acá se
  /// necesitan los 2 decimales visibles: es el preview de "se va a guardar
  /// esto" en el diálogo de editar precio, y su propósito es justamente
  /// mostrar el redondeo a 2 decimales que aplica ParserNumeroAr cuando se
  /// tipea un tercer decimal.
  String _fmtPrecioConDecimales(double monto) {
    final partes = monto.toStringAsFixed(2).split('.');
    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    final entero = partes[0].replaceAllMapped(reg, (Match m) => '${m[1]}.');
    return '\$ $entero,${partes[1]}';
  }

  /// Texto y estilo del helper de precio del diálogo de editar. Normal
  /// (estilo null, no cambia el look ya verificado) o reforzado en naranja +
  /// negrita con la lectura alternativa entre paréntesis, solo cuando el
  /// punto se interpretó como separador de miles (ver
  /// ParserNumeroAr.esInterpretacionDeMiles) -- es el único caso con
  /// ambigüedad real; el de doble punto queda discreto a propósito, si el
  /// aviso apareciera siempre dejaría de notarse.
  (String, TextStyle?) _previewPrecio(String texto) {
    final valor = ParserNumeroAr.parsear(texto);
    if (valor == null) return ('', null);
    final normal = 'Se guardará: ${_fmtPrecioConDecimales(valor)}';
    if (!ParserNumeroAr.esInterpretacionDeMiles(texto)) return (normal, null);
    final alterno = ParserNumeroAr.lecturaAlternativaSiEsMiles(texto);
    final reforzado = alterno != null ? '$normal (no ${_fmtPrecioConDecimales(alterno)})' : normal;
    return (reforzado, TextStyle(color: Colors.orange[800], fontWeight: FontWeight.bold));
  }

  IconData _iconoTipo(String tipo) {
    switch (tipo) {
      case 'mano_obra':
        return Icons.engineering;
      case 'equipo':
        return Icons.build;
      default:
        return Icons.inventory_2;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }

    // Separado a propósito: sin precio y con cantidad > 0 frena un cálculo real; sin precio y con
    // cantidad 0 todavía no incide en nada (subitem tildado sin cantidad cargada todavía). Ver
    // memoria "mat_y_mo_fuentes_precio" — mezclar los dos en un solo número no es una señal
    // honesta de cuánto falta de verdad.
    final sinPrecioIncide = _insumos.where((i) => !i.tienePrecio && i.cantidadTotal > 0).length;
    final sinPrecioPendiente = _insumos.where((i) => !i.tienePrecio && i.cantidadTotal == 0).length;
    final String subtitulo = _insumos.isEmpty
        ? 'Todavía no hay insumos: tildá subítems con APU en el Cómputo para verlos acá.'
        : (sinPrecioIncide == 0 && sinPrecioPendiente == 0)
            ? '${_insumos.length} insumos, según las composiciones de APU tildadas en esta obra.'
            : '${_insumos.length} insumos — $sinPrecioIncide sin precio (frenan el cálculo)'
                '${sinPrecioPendiente > 0 ? ' · $sinPrecioPendiente sin precio (cantidad en 0, todavía no cargada)' : ''}.';

    return RefreshIndicator(
      onRefresh: _cargarConsolidado,
      child: ListView(
        padding: const EdgeInsets.all(12),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.inventory, color: Color(0xFF1B365D)),
              title: const Text('Consolidado de Insumos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              subtitle: Text(subtitulo, style: const TextStyle(fontSize: 11)),
            ),
          ),
          const SizedBox(height: 8),
          if (_insumos.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text('Sin insumos todavía.', style: TextStyle(color: Colors.black45, fontSize: 12)),
              ),
            )
          else
            for (final seccion in _secciones) ..._buildSeccion(seccion),
        ],
      ),
    );
  }

  Widget _buildInsumoCard(InsumoConsolidadoObra insumo) {
    // Sin ListTile a propósito: su alto se calcula solo a partir de título/subtítulo (reglas fijas
    // de Material para tiles dense de 2 líneas) e ignora cuánto mide el trailing -- con la línea de
    // la cuenta sumada al badge "Cargado a mano", el trailing pasó a medir más que ese alto fijo y
    // desbordaba. Row/Column a mano miden lo que su contenido necesite, sin número fijo en ningún
    // lado. Mismo patrón que la card de certificados (gestion_obra_tab.dart).
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(_iconoTipo(insumo.tipo), color: const Color(0xFF1B365D), size: 20),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(insumo.nombre, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  Text(
                    'Cantidad necesaria: ${_fmtCantidad(insumo.cantidadTotal)} ${insumo.unidad}',
                    style: const TextStyle(fontSize: 10),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            _buildTrailing(insumo),
          ],
        ),
      ),
    );
  }

  /// Insumos de una sección + su encabezado — vacío (sin encabezado incluido) si el predicado no
  /// matchea ningún insumo, para no pintar un título flotando sobre una lista vacía.
  List<Widget> _buildSeccion(_SeccionInsumos seccion) {
    final insumos = _insumos.where(seccion.predicado).toList();
    if (insumos.isEmpty) return [];
    return [
      _buildEncabezadoSeccion(seccion.titulo, seccion.icono),
      ...insumos.map(_buildInsumoCard),
    ];
  }

  Widget _buildEncabezadoSeccion(String titulo, IconData icono) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4, left: 4),
      child: Row(
        children: [
          Icon(icono, size: 16, color: const Color(0xFF1B365D)),
          const SizedBox(width: 6),
          Text(
            titulo,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1B365D)),
          ),
        ],
      ),
    );
  }

  Widget _buildTrailing(InsumoConsolidadoObra insumo) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (insumo.tienePrecio)
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${_fmtPrecio(insumo.precio!)} /${insumo.unidad}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF2E7D32)),
              ),
              if (insumo.fijadoAMano) ...[
                const SizedBox(height: 4),
                _buildBadgeManual(),
              ],
            ],
          )
        else
          _buildFaltaPrecio(),
        InkWell(
          onTap: () => _mostrarDialogoEditarPrecio(insumo),
          child: const Padding(
            padding: EdgeInsets.all(6),
            child: Icon(Icons.edit, size: 16, color: Color(0xFF1B365D)),
          ),
        ),
      ],
    );
  }

  Widget _buildFaltaPrecio() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.orange[200]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.info_outline, size: 12, color: Colors.orange[800]),
          const SizedBox(width: 4),
          Text(
            'Falta cargar precio',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange[800]),
          ),
        ],
      ),
    );
  }

  Widget _buildBadgeManual() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.edit, size: 12, color: Colors.blue[800]),
          const SizedBox(width: 4),
          Text(
            'Cargado a mano',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue[800]),
          ),
        ],
      ),
    );
  }

  Future<void> _mostrarDialogoEditarPrecio(InsumoConsolidadoObra insumo) async {
    final usuarioId = _authService.usuarioActual?.id;
    if (usuarioId == null) return;

    // Bifurcación del lapicito (ver docs/costo_mano_de_obra_decisiones.md §13): mano de obra
    // escribe en obra_valor_hora_override, por categoría, no en obra_insumo_precios. Otros
    // insumos de mano de obra que comparten la misma categoría (hoy solo AYUDANTE/AYUDA DE
    // GREMIO) salen de _insumos ya cargado, sin consulta nueva ni nombre hardcodeado.
    final otrosDeLaMismaCategoria = insumo.tipo == 'mano_obra'
        ? _insumos
            .where((i) =>
                i.tipo == 'mano_obra' &&
                i.categoriaUocra == insumo.categoriaUocra &&
                i.insumoId != insumo.insumoId)
            .toList()
        : <InsumoConsolidadoObra>[];
    final textoExplicativo = insumo.tipo != 'mano_obra'
        ? 'Este precio se usa en el cálculo de todas las partidas de esta obra que llevan '
            '${insumo.nombre}. Al guardarlo se actualiza el costo de esas partidas.'
        : otrosDeLaMismaCategoria.isEmpty
            ? 'Este valor hora corresponde a la categoría UOCRA de ${insumo.nombre} — se usa en '
                'el cálculo de todas las partidas de esta obra que usan esa categoría.'
            : 'Este valor hora es compartido: también corresponde a '
                '${otrosDeLaMismaCategoria.map((o) => o.nombre).join(', ')}. Al guardarlo '
                'cambian las dos filas y todas las partidas que usan esa categoría.';

    final controller = TextEditingController(
      text: insumo.precio != null ? insumo.precio!.toStringAsFixed(2) : '',
    );
    String? error;

    final nuevoPrecio = await showDialog<double>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final preview = _previewPrecio(controller.text);
          return AlertDialog(
          title: Text(insumo.nombre, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Precio por ${insumo.unidad}', style: const TextStyle(fontSize: 11, color: Colors.black54)),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
                onChanged: (_) => setDialogState(() {}),
                decoration: InputDecoration(
                  prefixText: '\$ ',
                  isDense: true,
                  errorText: error,
                  // Helper no nulo desde el arranque (string vacío, no null) a
                  // propósito: con null, InputDecoration no reserva la línea y
                  // el diálogo salta de alto apenas aparece el primer preview.
                  helperText: preview.$1,
                  helperStyle: preview.$2,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                textoExplicativo,
                style: TextStyle(fontSize: 10, color: Colors.grey[700]),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            TextButton(
              onPressed: () {
                final valor = ParserNumeroAr.parsear(controller.text);
                if (valor == null || valor < 0) {
                  setDialogState(() => error = 'Precio inválido');
                  return;
                }
                Navigator.pop(ctx, valor);
              },
              child: const Text('Guardar'),
            ),
          ],
          );
        },
      ),
    );

    if (nuevoPrecio == null) return;

    // Caso imposible en la práctica (constraint insumos_mano_obra_requiere_categoria, 0042) pero
    // sin garantía absoluta desde Dart -- si igual llegara a pasar, tiene que fallar visible acá,
    // nunca caer en el "else" y escribir en obra_insumo_precios: esa tabla ya no se lee para mano
    // de obra (0042), así que el guardado "funcionaría" sin error y el número nunca cambiaría.
    if (insumo.tipo == 'mano_obra' && insumo.categoriaUocra == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Este insumo de mano de obra no tiene categoría UOCRA asignada — no se puede '
            'guardar. Es un dato inconsistente, avisá al soporte.',
          ),
        ),
      );
      return;
    }

    try {
      if (insumo.tipo == 'mano_obra') {
        await _obraInsumosRepository.guardarValorHoraOverride(
          obraId: widget.obraId,
          categoriaUocra: insumo.categoriaUocra!,
          valorHora: nuevoPrecio,
          usuarioId: usuarioId,
        );
      } else {
        await _obraInsumosRepository.guardarPrecioManual(
          obraId: widget.obraId,
          insumoId: insumo.insumoId,
          precio: nuevoPrecio,
          usuarioId: usuarioId,
        );
      }
      await _cargarConsolidado();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo guardar el precio.')),
      );
    }
  }
}
