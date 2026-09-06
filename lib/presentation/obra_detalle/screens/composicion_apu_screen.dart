import 'package:flutter/material.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/models/apu_composicion_item_detalle.dart';
import '../../../data/models/apu_precio_subitem.dart';
import '../../../services/apu_composiciones_repository.dart';
import '../../../services/auth_service.dart';
import '../../../services/perfil_repository.dart';
import '../../shared/pro_gate_dialog.dart';
import '../tabs/panel_editar_item_apu.dart';

/// Composición completa de una partida — mano de obra, materiales y equipos, cada uno con su
/// rendimiento, precio unitario y subtotal (ver `calcular_composicion_detalle_subitem`,
/// 0060_calcular_composicion_detalle_subitem.sql). Free lee, PRO edita (ver
/// `PanelEditarItemApu` y `personalizar_item_apu`, 0071_personalizacion_apu_pro.sql) — primera
/// pieza de "edición de APU en la Solapa APU".
///
/// Se llega acá desde SubitemsScreen, tocando el precio APU de un subítem con composición cargada
/// (chip "APU") — no hay un listado propio para esto, reusa la navegación de Rubros/Cómputo que
/// ya existe; la edición vive en esta misma pantalla, no en una aparte (mismo criterio ya escrito
/// en `_buildTabApu()` de no duplicar navegación entre Cómputo y la Solapa APU).
class ComposicionApuScreen extends StatefulWidget {
  final String obraId;
  final String subitemId;
  final String subitemCodigo;
  final String subitemDescripcion;
  // Ya no se usa para el total mostrado (ver _resultadoActual, recalculado desde _items siempre
  // que cambian: editar o restaurar una línea invalidaría este valor si se lo siguiera usando
  // tal cual). Se mantiene como parámetro para no tocar el call site de SubitemsScreen — sigue
  // siendo el número correcto para el primer render de la lista de partidas allá, solo que
  // dejó de ser la fuente de verdad de esta pantalla.
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
  final PerfilRepository _perfilRepository = PerfilRepository();
  final AuthService _authService = AuthService();

  List<ApuComposicionItemDetalle> _items = [];
  bool _cargando = true;
  String? _error;
  // Solo para el botón "Volver a la receta oficial" -- el resto de la pantalla no necesita saber
  // esto mientras carga.
  bool _verificandoProRestaurar = false;

  /// Recalculado siempre desde `_items`, nunca desde `widget.precioAgregado` (ver comentario del
  /// campo en el widget) -- mismo COALESCE que ya hace `calcular_precio_apu_subitems`/
  /// `calcular_composicion_detalle_subitem`, solo que sumado acá porque `_items` puede cambiar
  /// (editar una línea, o restaurar la oficial) sin que valga la pena pedir un nuevo agregado a la
  /// base cuando ya tenemos el detalle completo en memoria.
  ApuPrecioSubitem get _resultadoActual {
    final conPrecio = _items.where((i) => i.precioUnitario != null).toList();
    final total = conPrecio.fold<double>(0, (acc, i) => acc + i.subtotal!);
    return ApuPrecioSubitem(
      precioTotal: total,
      insumosConPrecio: conPrecio.length,
      insumosTotal: _items.length,
    );
  }

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
        // Todas las líneas comparten la misma composición (oficial o personal) -- alcanza con
        // mirar la primera para saber cuál se está mostrando.
        if (_items.first.esPersonal) _buildBannerPersonalizado(),
        if (manoDeObra.isNotEmpty) _buildSeccion('MANO DE OBRA', manoDeObra),
        if (materiales.isNotEmpty) _buildSeccion('MATERIALES', materiales),
        if (equipos.isNotEmpty) _buildSeccion('EQUIPOS', equipos),
        const SizedBox(height: 8),
        _buildTotal(),
      ],
    );
  }

  /// Aviso + acción cuando la receta que se está mostrando es la personal del usuario, no la
  /// oficial (ver `es_personal`, 0071). Solo informa/ofrece volver -- no dice qué se editó línea
  /// por línea, ese detalle ya se ve en las secciones de abajo.
  Widget _buildBannerPersonalizado() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.amber[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber[200]!),
      ),
      child: Row(
        children: [
          Icon(Icons.edit_note, size: 16, color: Colors.amber[900]),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Esta es tu receta personalizada de esta partida.',
              style: TextStyle(fontSize: 11, color: Colors.black87),
            ),
          ),
          TextButton(
            onPressed: _verificandoProRestaurar ? null : _onRestaurarOficial,
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            child: Text(_verificandoProRestaurar ? 'Verificando...' : 'Volver a la oficial'),
          ),
        ],
      ),
    );
  }

  Future<void> _onRestaurarOficial() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text(
          'Volver a la receta oficial',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1B365D)),
        ),
        content: const Text(
          'Vas a perder tu personalización de esta partida (rendimientos e insumos que hayas '
          'cambiado). No se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Volver a la oficial'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    final usuarioId = _authService.usuarioActual?.id;
    setState(() => _verificandoProRestaurar = true);
    final esProAhora = usuarioId != null ? await _perfilRepository.esPro(usuarioId) : false;
    if (!mounted) return;
    setState(() => _verificandoProRestaurar = false);

    if (!esProAhora) {
      await mostrarDialogoFuncionPro(context, mensaje: 'Editar la composición de APU es una función PRO.');
      return;
    }

    try {
      await _repository.restaurarRecetaOficial(widget.subitemId);
      if (!mounted) return;
      await _cargarDetalle(); // los ids cambian al volver a la oficial, recarga completa
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo restaurar la receta oficial. Probá de nuevo.')),
      );
    }
  }

  Future<void> _abrirEdicion(ApuComposicionItemDetalle item) async {
    final resultado = await showDialog<List<ApuComposicionItemDetalle>>(
      context: context,
      builder: (_) => PanelEditarItemApu(
        obraId: widget.obraId,
        subitemId: widget.subitemId,
        item: item,
      ),
    );
    if (resultado == null || !mounted) return;
    setState(() => _items = resultado);
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
          // Visible para cualquiera (Free incluido) -- el gate de PRO es al Guardar, adentro del
          // diálogo, no acá (mismo criterio "no ocultar la función, gatear la acción").
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 16, color: Colors.black45),
            tooltip: 'Editar',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: () => _abrirEdicion(item),
          ),
        ],
      ),
    );
  }

  /// Mismo semáforo que `_buildPrecioApuDerivado` de SubitemsScreen, pero recalculado desde
  /// `_items` (`_resultadoActual`), no desde `widget.precioAgregado` -- ese valor queda desactualizado
  /// apenas se edita una línea o se restaura la oficial, ver el comentario del campo en el widget.
  Widget _buildTotal() {
    final resultado = _resultadoActual;
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
