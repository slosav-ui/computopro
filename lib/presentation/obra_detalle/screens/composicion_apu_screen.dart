import 'package:flutter/material.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/models/apu_composicion_item_detalle.dart';
import '../../../data/models/apu_precio_subitem.dart';
import '../../../services/apu_composiciones_repository.dart';

/// Composición completa de una partida — mano de obra, materiales y equipos, cada uno con su
/// rendimiento, precio unitario y subtotal (ver `calcular_composicion_detalle_subitem`,
/// 0060_calcular_composicion_detalle_subitem.sql). Solo lectura: edición es PRO, va después.
///
/// Se llega acá desde SubitemsScreen, tocando el precio APU de un subítem con composición cargada
/// (chip "APU") — no hay un listado propio para esto, reusa la navegación de Rubros/Cómputo que
/// ya existe. `precioAgregado` viene ya calculado por SubitemsScreen (mismo resultado de
/// `calcular_precio_apu_subitems` que arma el chip de la lista) — no se vuelve a pedir acá, evita
/// una segunda llamada para el mismo número.
class ComposicionApuScreen extends StatefulWidget {
  final String obraId;
  final String subitemId;
  final String subitemCodigo;
  final String subitemDescripcion;
  final ApuPrecioSubitem precioAgregado;

  const ComposicionApuScreen({
    Key? key,
    required this.obraId,
    required this.subitemId,
    required this.subitemCodigo,
    required this.subitemDescripcion,
    required this.precioAgregado,
  }) : super(key: key);

  @override
  State<ComposicionApuScreen> createState() => _ComposicionApuScreenState();
}

class _ComposicionApuScreenState extends State<ComposicionApuScreen> {
  final ApuComposicionesRepository _repository = ApuComposicionesRepository();

  List<ApuComposicionItemDetalle> _items = [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarDetalle();
  }

  Future<void> _cargarDetalle() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final items = await _repository.getComposicionDetalle(widget.obraId, widget.subitemId);
      if (!mounted) return;
      setState(() {
        _items = items;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar la composición de esta partida.';
        _cargando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.subitemCodigo} - ${widget.subitemDescripcion}',
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
          style: const TextStyle(fontSize: 16),
        ),
        backgroundColor: const Color(0xFF1B365D),
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _cargarDetalle,
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
    if (_items.isEmpty) {
      return ListView(
        children: const [
          Padding(
            padding: EdgeInsets.all(24.0),
            child: Text(
              'Esta partida no tiene ítems cargados en su composición.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ),
        ],
      );
    }

    // El SQL ya devuelve mano_obra, material, equipo en ese orden -- agrupar acá es solo separar
    // en secciones consecutivas, sin volver a ordenar.
    final manoDeObra = _items.where((i) => i.tipoComponente == 'mano_obra').toList();
    final materiales = _items.where((i) => i.tipoComponente == 'material').toList();
    final equipos = _items.where((i) => i.tipoComponente == 'equipo').toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (manoDeObra.isNotEmpty) _buildSeccion('MANO DE OBRA', manoDeObra),
        if (materiales.isNotEmpty) _buildSeccion('MATERIALES', materiales),
        if (equipos.isNotEmpty) _buildSeccion('EQUIPOS', equipos),
        const SizedBox(height: 8),
        _buildTotal(),
      ],
    );
  }

  Widget _buildSeccion(String titulo, List<ApuComposicionItemDetalle> items) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titulo,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1B365D)),
            ),
            const Divider(height: 16),
            for (final item in items) _buildFilaItem(item),
          ],
        ),
      ),
    );
  }

  Widget _buildFilaItem(ApuComposicionItemDetalle item) {
    final sinPrecio = item.precioUnitario == null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.insumoNombre,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                Text(
                  '${_fmtRendimiento(item.rendimiento)} ${item.insumoUnidad.toUpperCase()}',
                  style: const TextStyle(fontSize: 11, color: Colors.black45),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: sinPrecio
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Icon(Icons.info_outline, size: 12, color: Colors.orange[800]),
                      const SizedBox(width: 4),
                      Text(
                        'sin precio',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange[800]),
                      ),
                    ],
                  )
                : Text(
                    CurrencyFormatter.formatARS(item.subtotal!),
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1B365D)),
                  ),
          ),
        ],
      ),
    );
  }

  /// Mismo semáforo que `_buildPrecioApuDerivado` de SubitemsScreen — no un total nuevo, el mismo
  /// resultado que ya arma el chip de la lista, mostrado más grande acá.
  Widget _buildTotal() {
    final resultado = widget.precioAgregado;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: resultado.completo ? Colors.grey[100] : Colors.orange[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: resultado.completo ? Colors.black12 : Colors.orange[200]!),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Precio unitario de la partida', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          resultado.completo
              ? Text(
                  CurrencyFormatter.formatARS(resultado.precioTotal),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1B365D)),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.info_outline, size: 14, color: Colors.orange[800]),
                    const SizedBox(width: 4),
                    Text(
                      'Incompleto (${resultado.insumosConPrecio}/${resultado.insumosTotal})',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange[800]),
                    ),
                  ],
                ),
        ],
      ),
    );
  }

  String _fmtRendimiento(double valor) {
    return valor == valor.roundToDouble() ? valor.toInt().toString() : valor.toString();
  }
}
