import 'package:flutter/material.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/models/apu_composicion_item_detalle.dart';
import '../../../data/models/apu_precio_subitem.dart';
import '../../../services/apu_composiciones_repository.dart';
import '../../../services/auth_service.dart';
import '../../../services/insumos_repository.dart';
import '../../../services/perfil_repository.dart';
import '../../shared/pro_gate_dialog.dart';
import '../tabs/panel_agregar_item_apu.dart';
import '../tabs/panel_crear_equipo_apu.dart';
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
  final InsumosRepository _insumosRepository = InsumosRepository();
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
        _buildSeccion(
          'MATERIALES',
          materiales,
          accionAgregar: () => _abrirAgregarItem('material'),
          conAccionQuitar: true,
          textoVacio: 'Sin materiales cargados.',
        ),
        _buildSeccion(
          'EQUIPOS',
          equipos,
          accionAgregar: () => _abrirAgregarItem('equipo'),
          conAccionQuitar: true,
          textoVacio: 'Sin equipos cargados.',
          atenuarSiVacio: true,
        ),
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
              'Este es tu APU personalizado de esta partida.',
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
          'Volver al APU oficial',
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
        const SnackBar(content: Text('No se pudo restaurar el APU oficial. Probá de nuevo.')),
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

  /// `tipoComponente`: 'material' o 'equipo' -- mismo mecanismo de clonado para los dos, solo
  /// cambia a qué RPC de base termina llamando. Para equipo, antes de cualquier otra cosa se
  /// muestra un aviso aparte (`_confirmarAgregarEquipo`) -- tiene que verse ANTES de cargar nada,
  /// no adentro del diálogo de carga (ver conversación: si aparece después, el usuario ya cargó
  /// mal). Después el camino se bifurca según si el catálogo de equipos ya tiene algo: vacío (hoy,
  /// siempre) va directo al formulario de alta (`PanelCrearEquipoApu`); con al menos un equipo va
  /// al buscador (`PanelAgregarItemApu`, mismo que materiales, con su propia salida a
  /// `PanelCrearEquipoApu` si no encuentra lo que busca).
  Future<void> _abrirAgregarItem(String tipoComponente) async {
    if (tipoComponente == 'equipo') {
      final continuar = await _confirmarAgregarEquipo();
      if (continuar != true || !mounted) return;

      final hayCatalogo = await _insumosRepository.hayInsumosDeTipo('equipo');
      if (!mounted) return;
      if (!hayCatalogo) {
        final resultado = await showDialog<List<ApuComposicionItemDetalle>>(
          context: context,
          builder: (_) => PanelCrearEquipoApu(obraId: widget.obraId, subitemId: widget.subitemId),
        );
        if (resultado == null || !mounted) return;
        setState(() => _items = resultado);
        return;
      }
    }

    final idsExistentes = _items.where((i) => i.tipoComponente == tipoComponente).map((i) => i.insumoId).toSet();
    final resultado = await showDialog<List<ApuComposicionItemDetalle>>(
      context: context,
      builder: (_) => PanelAgregarItemApu(
        obraId: widget.obraId,
        subitemId: widget.subitemId,
        insumoIdsExistentes: idsExistentes,
        tipoComponente: tipoComponente,
      ),
    );
    if (resultado == null || !mounted) return;
    setState(() => _items = resultado);
  }

  /// Aviso obligatorio antes de abrir el buscador de equipos -- ejemplo concreto, sin
  /// "amortización"/"prorrateo" (PRO es un plan, no un rol de caja blanca: un constructor sin
  /// formación contable también puede ser PRO y tocar este botón). `true` = el usuario tocó
  /// Continuar, `null`/`false` = canceló y no se abre nada.
  Future<bool?> _confirmarAgregarEquipo() {
    return showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text(
          'Antes de agregar un equipo',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1B365D)),
        ),
        content: const Text(
          'Ojo cómo cargás el precio: si alquilás la hormigonera por día y la usás 4 horas para '
          '10 m² de mampostería, no cargues el alquiler del día ni del mes — cargá el precio de '
          'esa hora, y como rendimiento las horas que lleva cada m². Cargado mal (el precio del '
          'día entero, por ejemplo), el precio por unidad sale disparatado.\n\n'
          'Y si el costo de este equipo ya está contemplado en los Gastos Generales del Factor K '
          'de esta obra, no lo agregues acá de nuevo: lo estarías contando dos veces.',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
  }

  /// Quita una línea de material o equipo -- misma confirmación y gate para las dos, solo cambia
  /// qué RPC de base termina llamando (`quitarMaterial`/`quitarEquipo`, ver
  /// `ApuComposicionesRepository`).
  Future<void> _onQuitarItem(ApuComposicionItemDetalle item) async {
    final esEquipo = item.tipoComponente == 'equipo';
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(
          esEquipo ? 'Quitar equipo' : 'Quitar material',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1B365D)),
        ),
        content: Text('Vas a quitar "${item.insumoNombre}" de tu APU de esta partida.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    final usuarioId = _authService.usuarioActual?.id;
    final esProAhora = usuarioId != null ? await _perfilRepository.esPro(usuarioId) : false;
    if (!mounted) return;
    if (!esProAhora) {
      await mostrarDialogoFuncionPro(context, mensaje: 'Editar la composición de APU es una función PRO.');
      return;
    }

    try {
      final resultado = esEquipo
          ? await _repository.quitarEquipo(
              obraId: widget.obraId,
              subitemId: widget.subitemId,
              insumoId: item.insumoId,
            )
          : await _repository.quitarMaterial(
              obraId: widget.obraId,
              subitemId: widget.subitemId,
              insumoId: item.insumoId,
            );
      if (!mounted) return;
      setState(() => _items = resultado);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo quitar el ${esEquipo ? 'equipo' : 'material'}. Probá de nuevo.')),
      );
    }
  }

  // Anchos fijos de las 3 columnas numéricas, compartidos entre el encabezado y cada fila para que
  // queden alineadas entre sí (y las cifras en la misma vertical) -- ver conversación: probado que
  // el emulador angosto no alcanza para confiar en que "se acomoda solo", hay que fijarlos.
  static const double _colUnidad = 32;
  static const double _colRendimiento = 46;
  static const double _colPrecio = 64;
  static const double _colSubtotal = 72;
  static const double _colAccion = 26;

  /// `atenuarSiVacio`: la sección nunca se oculta (existe igual, con su título y su botón de
  /// agregar), pero si no tiene líneas cargadas se ve apagada -- se entiende que la opción existe
  /// sin que compita visualmente con las secciones que sí están en uso. El estado "apagada" no se
  /// guarda en ningún lado: se deriva de `items.isEmpty`, no es una preferencia del usuario.
  Widget _buildSeccion(
    String titulo,
    List<ApuComposicionItemDetalle> items, {
    VoidCallback? accionAgregar,
    bool conAccionQuitar = false,
    String textoVacio = 'Sin líneas cargadas.',
    bool atenuarSiVacio = false,
  }) {
    final apagada = atenuarSiVacio && items.isEmpty;
    final tarjeta = Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1B365D)),
                ),
                // Visible para cualquiera (Free incluido) -- mismo criterio que el precio: el gate
                // de PRO es al Guardar, adentro del diálogo, no acá.
                if (accionAgregar != null)
                  TextButton.icon(
                    onPressed: accionAgregar,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Agregar', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
                  ),
              ],
            ),
            const Divider(height: 16),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  textoVacio,
                  style: const TextStyle(fontSize: 12, color: Colors.black45, fontStyle: FontStyle.italic),
                ),
              )
            else ...[
              _buildEncabezadoColumnas(conAccionQuitar: conAccionQuitar),
              for (final item in items) _buildFilaItem(item, conAccionQuitar: conAccionQuitar),
            ],
          ],
        ),
      ),
    );
    // Opacity, no un color gris propio -- el botón "Agregar" tiene que seguir siendo tocable
    // (Opacity no bloquea hit-testing), a diferencia de deshabilitarlo.
    return apagada ? Opacity(opacity: 0.45, child: tarjeta) : tarjeta;
  }

  /// Encabezados de columna -- sin esto, las 3 cifras seguidas de cada línea (rendimiento, precio
  /// unitario, subtotal) no dicen cuál es cuál. Letra chica y atenuada a propósito, para que no
  /// compita con los datos de abajo.
  Widget _buildEncabezadoColumnas({required bool conAccionQuitar}) {
    const estilo = TextStyle(
      fontSize: 9,
      fontWeight: FontWeight.w600,
      color: Colors.black38,
      letterSpacing: 0.3,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Expanded(child: Text('INSUMO', style: estilo)),
          const SizedBox(width: _colUnidad, child: Text('UNID.', style: estilo, textAlign: TextAlign.right)),
          const SizedBox(width: _colRendimiento, child: Text('REND.', style: estilo, textAlign: TextAlign.right)),
          const SizedBox(width: _colPrecio, child: Text('P. UNIT.', style: estilo, textAlign: TextAlign.right)),
          const SizedBox(width: _colSubtotal, child: Text('SUBTOTAL', style: estilo, textAlign: TextAlign.right)),
          if (conAccionQuitar) SizedBox(width: _colAccion),
        ],
      ),
    );
  }

  /// Una fila por línea, alineada a `_buildEncabezadoColumnas`: insumo (ocupa lo que sobra, se
  /// corta con puntos suspensivos antes que apretar las columnas numéricas -- el nombre completo
  /// se ve en el diálogo que abre el precio), unidad, rendimiento, precio unitario (el toque para
  /// editar, ver `PanelEditarItemApu`) y subtotal (texto plano, resultado calculado). Vale igual
  /// para material, mano de obra (el precio unitario ahí es el valor hora de la categoría) y
  /// equipos.
  Widget _buildFilaItem(ApuComposicionItemDetalle item, {required bool conAccionQuitar}) {
    final sinPrecio = item.precioUnitario == null;
    // Categoría de mano de obra sin rendimiento cargado (fila real en 0, o virtual todavía --
    // corrección #1: las 5 categorías siempre visibles, atenuadas mientras estén en 0).
    final atenuado = item.tipoComponente == 'mano_obra' && item.rendimiento == 0;
    final fila = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              item.insumoNombre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          SizedBox(
            width: _colUnidad,
            child: Text(
              item.insumoUnidad.toUpperCase(),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 11, color: Colors.black45),
            ),
          ),
          SizedBox(
            width: _colRendimiento,
            child: Text(
              _fmtRendimiento(item.rendimiento),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 11, color: Colors.black45),
            ),
          ),
          SizedBox(
            width: _colPrecio,
            // Único toque para editar rendimiento y precio (ver PanelEditarItemApu) -- visible
            // para cualquiera (Free incluido), el gate de PRO es al Guardar, adentro del diálogo.
            child: InkWell(
              onTap: () => _abrirEdicion(item),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  sinPrecio ? 'Cargar precio' : CurrencyFormatter.formatARS(item.precioUnitario!),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: sinPrecio ? Colors.orange[800] : const Color(0xFF1B365D),
                    decoration: TextDecoration.underline,
                    decorationColor: Colors.black26,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: _colSubtotal,
            child: Text(
              sinPrecio ? '—' : CurrencyFormatter.formatARS(item.subtotal!),
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1B365D)),
            ),
          ),
          if (conAccionQuitar)
            SizedBox(
              width: _colAccion,
              // La sección que pasa conAccionQuitar:true es homogénea (solo materiales o solo
              // equipos, ver los dos call sites de _buildSeccion) -- alcanza con mostrar el ícono
              // siempre acá, _onQuitarItem ya distingue a qué RPC llamar según item.tipoComponente.
              child: IconButton(
                icon: const Icon(Icons.delete_outline, size: 15, color: Colors.black45),
                tooltip: 'Quitar',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                onPressed: () => _onQuitarItem(item),
              ),
            ),
        ],
      ),
    );
    return atenuado ? Opacity(opacity: 0.5, child: fila) : fila;
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
          // Expanded -- con letra grande (accesibilidad) esta etiqueta más el precio de al lado no
          // entran en una sola línea sin desbordar; acá puede ajustarse o pasar a una segunda línea.
          const Expanded(
            child: Text('Precio unitario de la partida', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
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
