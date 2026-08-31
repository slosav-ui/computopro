import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../../../data/models/obra_model.dart';
import '../../../data/models/rubro_catalogo.dart';
import '../../../services/rubros_repository.dart';
import '../../../services/subitems_repository.dart';
import '../../../services/obra_subitems_repository.dart';
import '../../../services/obra_rubros_orden_repository.dart';
import '../../../services/perfil_repository.dart';
import '../../../services/auth_service.dart';
import '../../shared/pro_gate_dialog.dart';
import '../screens/subitems_screen.dart';

class RubrosTab extends StatefulWidget {
  final ObraModel? obra;
  final String obraId;
  final bool puedeEditarComputo;

  const RubrosTab({
    Key? key,
    this.obra,
    required this.obraId,
    required this.puedeEditarComputo,
  }) : super(key: key);

  @override
  State<RubrosTab> createState() => _RubrosTabState();
}

class _RubrosTabState extends State<RubrosTab> {
  final RubrosRepository _rubrosRepository = RubrosRepository();
  final SubitemsRepository _subitemsRepository = SubitemsRepository();
  final ObraSubitemsRepository _obraSubitemsRepository = ObraSubitemsRepository();
  final ObraRubrosOrdenRepository _obraRubrosOrdenRepository = ObraRubrosOrdenRepository();
  final PerfilRepository _perfilRepository = PerfilRepository();
  final AuthService _authService = AuthService();

  // Ya mezclado con los overrides de obra_rubros_orden y ordenado — el
  // número mostrado en cada fila es directamente su índice+1 acá adentro
  // (ver _mezclarOrden), no un campo aparte que haya que mantener en
  // sincronía.
  List<RubroCatalogo> _catalogo = [];
  // Posición efectiva (real, no un índice sintético) de cada rubro en
  // _catalogo, mismo orden — necesaria para calcular el punto medio correcto
  // al arrastrar (ver _onReorder). No alcanza con recalcular a partir del
  // índice en cada drag: un vecino puede ya tener un override persistido con
  // una magnitud real distinta a la que le daría su posición en la lista.
  List<double> _posicionesCatalogo = [];
  // Indicador "N de M tildados" por rubro (ver diagnóstico: sin monto real
  // todavía, unit-agnostic, no depende de APU/precio_unitario_manual).
  Map<String, int> _totalPorRubro = {};
  Map<String, int> _tildadosPorRubro = {};
  bool _cargando = true;
  String? _error;

  // Ids de rubros con un borrado en curso (chequeo de uso o DELETE en
  // vuelo) — deshabilita el ícono de esa fila puntual y lo reemplaza por un
  // spinner chico, sin bloquear el resto de la lista.
  final Set<String> _procesandoEliminacion = {};

  // Fail-closed a Free hasta que se resuelva la consulta real (ver
  // PerfilRepository.esPro) — el botón "Nuevo Rubro" queda deshabilitado
  // mientras _cargando es true, así que no llega a mostrarse con este
  // default incorrecto.
  bool _esPro = false;

  // Default false (aviso visible) hasta que se resuelva la lectura real de
  // SharedPreferences — mismo criterio "fail-closed hacia lo más seguro" que
  // _esPro, pero acá lo seguro es mostrar el aviso, no ocultarlo.
  bool _avisoOrdenDescartado = false;

  String get _claveAvisoOrden => 'orden_rubros_aviso_descartado_${widget.obraId}';

  @override
  void initState() {
    super.initState();
    _cargarCatalogo();
    _cargarAvisoDescartado();
  }

  Future<void> _cargarAvisoDescartado() async {
    final prefs = await SharedPreferences.getInstance();
    final descartado = prefs.getBool(_claveAvisoOrden) ?? false;
    if (!mounted) return;
    setState(() => _avisoOrdenDescartado = descartado);
  }

  /// Descarta el aviso solo para esta obra — guardado en SharedPreferences
  /// (por dispositivo, no sincronizado entre dispositivos ni usuarios), así
  /// que vuelve a aparecer al abrir otra obra o en otro dispositivo/usuario
  /// que no lo haya descartado ahí. No reaparece solo en esta obra — para
  /// eso está el ícono chico de _buildAvisoOrden que lo trae de vuelta.
  Future<void> _descartarAviso() async {
    setState(() => _avisoOrdenDescartado = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_claveAvisoOrden, true);
  }

  Future<void> _restaurarAviso() async {
    setState(() => _avisoOrdenDescartado = false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_claveAvisoOrden, false);
  }

  Future<void> _cargarCatalogo() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final usuarioId = _authService.usuarioActual?.id;
      final rubros = usuarioId != null
          ? await _rubrosRepository.getCatalogoCompleto(usuarioId)
          : await _rubrosRepository.getCatalogoOficial();
      final esPro = usuarioId != null ? await _perfilRepository.esPro(usuarioId) : false;
      final totales = await _subitemsRepository.getConteoOficialPorRubro();
      final tildados = await _obraSubitemsRepository.getConteoTildadosPorObra(widget.obraId);
      final overrides = await _obraRubrosOrdenRepository.getOverridesDeObra(widget.obraId);
      if (!mounted) return;
      final (catalogoOrdenado, posiciones) = _mezclarOrden(rubros, overrides);
      setState(() {
        _catalogo = catalogoOrdenado;
        _posicionesCatalogo = posiciones;
        _esPro = esPro;
        _totalPorRubro = totales;
        _tildadosPorRubro = tildados;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar el catálogo de rubros.';
        _cargando = false;
      });
    }
  }

  /// Combina el orden default (`catalogoDefault`, ya viene ordenado:
  /// oficiales por `orden`, propios por `createdAt` — ver
  /// RubrosRepository.getCatalogoCompleto) con los overrides explícitos de
  /// esta obra (`obra_rubros_orden`, indexación fraccionaria — ver
  /// docs/rubros_orden_diseno_datos.md §2.2). Sin overrides, el resultado es
  /// exactamente `catalogoDefault` sin cambios, con posiciones sintéticas.
  ///
  /// La posición default de un rubro sin override es (índice en la lista ya
  /// ordenada + 1) * 1000 — no rubros.orden * 1000 directamente, porque así
  /// también les da un lugar coherente a los propios (que no tienen
  /// `orden`), reutilizando el orden que getCatalogoCompleto ya calculó bien
  /// en vez de reimplementarlo acá.
  ///
  /// Devuelve también las posiciones (mismo orden que la lista) porque
  /// _onReorder las necesita como valores reales al calcular el punto medio
  /// entre vecinos — no alcanza con la lista de rubros sola.
  (List<RubroCatalogo>, List<double>) _mezclarOrden(
    List<RubroCatalogo> catalogoDefault,
    Map<String, double> overrides,
  ) {
    final conPosicion = <MapEntry<RubroCatalogo, double>>[
      for (var i = 0; i < catalogoDefault.length; i++)
        MapEntry(
          catalogoDefault[i],
          overrides[catalogoDefault[i].id] ?? (i + 1) * 1000.0,
        ),
    ];
    conPosicion.sort((a, b) => a.value.compareTo(b.value));
    return (
      conPosicion.map((e) => e.key).toList(),
      conPosicion.map((e) => e.value).toList(),
    );
  }

  /// Se dispara al soltar un rubro en una posición nueva. Calcula la nueva
  /// posición como el punto medio entre los dos vecinos que le quedan en la
  /// lista sin el rubro movido (`newIndex`, con `onReorderItem`, ya viene
  /// ajustado para indexar esa lista sin el ítem removido — no hace falta el
  /// `if (oldIndex < newIndex) newIndex -= 1` manual que pedía el `onReorder`
  /// viejo, deprecado). Actualización optimista: la lista local cambia antes
  /// del request; si el upsert falla, se revierte al snapshot previo.
  Future<void> _onReorder(int oldIndex, int newIndex) async {
    // Red de seguridad: el handle de arrastre no debería estar visible sin
    // este permiso (ver _buildContenido), así que esto no debería disparar
    // en la práctica.
    if (!widget.puedeEditarComputo) return;
    if (oldIndex == newIndex) return;

    final usuarioId = _authService.usuarioActual?.id;
    if (usuarioId == null) return;

    final rubro = _catalogo[oldIndex];
    final catalogoPrevio = List<RubroCatalogo>.from(_catalogo);
    final posicionesPrevias = List<double>.from(_posicionesCatalogo);

    final catalogoSinMovido = List<RubroCatalogo>.from(_catalogo)..removeAt(oldIndex);
    final posicionesSinMovido = List<double>.from(_posicionesCatalogo)..removeAt(oldIndex);

    final anterior = newIndex > 0 ? posicionesSinMovido[newIndex - 1] : null;
    final siguiente = newIndex < posicionesSinMovido.length ? posicionesSinMovido[newIndex] : null;

    final double nuevaPosicion;
    if (anterior != null && siguiente != null) {
      nuevaPosicion = (anterior + siguiente) / 2;
    } else if (anterior != null) {
      nuevaPosicion = anterior + 1000; // fue al final, sin cota superior
    } else if (siguiente != null) {
      nuevaPosicion = siguiente / 2; // fue al principio, sin cota inferior
    } else {
      nuevaPosicion = 1000; // único rubro en la lista (no debería pasar)
    }

    setState(() {
      _catalogo = List<RubroCatalogo>.from(catalogoSinMovido)..insert(newIndex, rubro);
      _posicionesCatalogo = List<double>.from(posicionesSinMovido)..insert(newIndex, nuevaPosicion);
    });

    try {
      await _obraRubrosOrdenRepository.moverRubro(
        obraId: widget.obraId,
        rubroId: rubro.id,
        posicion: nuevaPosicion,
        usuarioId: usuarioId,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _catalogo = catalogoPrevio;
        _posicionesCatalogo = posicionesPrevias;
      });
      _mostrarSnackError('No se pudo guardar el nuevo orden. Probá de nuevo.');
    }
  }

  /// Refresca solo los dos mapas de conteo (no el catálogo entero) al volver
  /// de SubitemsScreen — tildar/destildar ahí deja el "N de M" desactualizado
  /// si no se refresca. Falla en silencio: un conteo desactualizado no
  /// amerita interrumpir con un SnackBar, se corrige solo en el próximo
  /// pull-to-refresh o reingreso a la pantalla.
  Future<void> _cargarConteos() async {
    try {
      final totales = await _subitemsRepository.getConteoOficialPorRubro();
      final tildados = await _obraSubitemsRepository.getConteoTildadosPorObra(widget.obraId);
      if (!mounted) return;
      setState(() {
        _totalPorRubro = totales;
        _tildadosPorRubro = tildados;
      });
    } catch (e) {
      // silencioso, ver doc del método.
    }
  }

  @override
  Widget build(BuildContext context) {
    final ObraModel? obra = widget.obra;

    return Column(
      children: [
        if (obra != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.blueGrey[50],
            child: Row(
              children: [
                const Icon(Icons.architecture, size: 18, color: Color(0xFF1B365D)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${obra.nombre} • ${obra.propietario} (${obra.tipoObra})',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1B365D)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        // Independiente del rol: la sorpresa de "veo otro número acá" le
        // puede pasar a cualquiera que mire la obra, no solo a quien puede
        // arrastrar — así que no se gatea por puedeEditarComputo.
        //
        // Cuando el aviso está descartado (caso común, es lo que se ve la
        // gran mayoría del tiempo) el ícono chico que lo restaura y el botón
        // "Nuevo Rubro" comparten la misma fila — antes cada uno ocupaba su
        // propia fila completa, y esa altura duplicada era justamente lo que
        // le robaba lugar a la lista en pantallas donde ya el alto escasea.
        // Con el banner completo visible (sin descartar) sí van apilados,
        // porque el banner ya ocupa todo el ancho con su propio texto.
        if (_avisoOrdenDescartado)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 16, 0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.info_outline, size: 16, color: Colors.black38),
                  tooltip: 'Sobre la numeración de rubros',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: _restaurarAviso,
                ),
                const Spacer(),
                _buildBotonNuevoRubro(),
              ],
            ),
          )
        else ...[
          _buildAvisoOrden(),
          // Siempre visible, para PRO y para Free (Free ve el diálogo de
          // función PRO al tocarlo, ver _onNuevoRubro — no se oculta la
          // función, mismo criterio que el resto del spec Free/PRO).
          // RubrosTab no es un Scaffold (vive dentro del TabBarView de
          // PresupuestosScreen), así que va como fila propia en vez de un
          // floatingActionButton.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Align(
              alignment: Alignment.centerRight,
              child: _buildBotonNuevoRubro(),
            ),
          ),
        ],
        Expanded(
          child: RefreshIndicator(
            onRefresh: _cargarCatalogo,
            child: _buildContenido(),
          ),
        ),
      ],
    );
  }

  /// Botón "Nuevo Rubro" — extraído para no duplicarlo entre la fila
  /// combinada con el ícono de aviso (descartado) y la fila propia debajo
  /// del banner completo (sin descartar), ver build().
  Widget _buildBotonNuevoRubro() {
    return OutlinedButton.icon(
      onPressed: _cargando ? null : _onNuevoRubro,
      icon: const Icon(Icons.add, size: 18),
      label: const Text('Nuevo Rubro'),
      style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1B365D)),
    );
  }

  /// Badge del número de posición del rubro, en el leading del ListTile —
  /// reemplaza al prefijo "N - " que antes formaba parte del título (ver
  /// _buildContenido).
  Widget _buildBadgeNumero(int numero) {
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF1B365D).withValues(alpha: 0.08),
        shape: BoxShape.circle,
      ),
      child: Text(
        '$numero',
        style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1B365D), fontSize: 12),
      ),
    );
  }

  /// Banner completo del aviso de que la numeración es posicional y de esta
  /// obra puntual — descartable, guardado por obra en SharedPreferences (ver
  /// _descartarAviso). Solo se llama cuando NO está descartado — el estado
  /// descartado (ícono chico que lo restaura, _restaurarAviso) se arma en
  /// build() compartiendo fila con "Nuevo Rubro", no acá.
  Widget _buildAvisoOrden() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.blueGrey[50],
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16, color: Color(0xFF1B365D)),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Los números se ajustan al orden que le des a esta obra. En otras obras la '
              'numeración puede ser distinta.',
              style: TextStyle(fontSize: 11, color: Color(0xFF1B365D)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16, color: Color(0xFF1B365D)),
            tooltip: 'Cerrar aviso',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: _descartarAviso,
          ),
        ],
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
    if (_catalogo.isEmpty) {
      return ListView(
        children: const [
          Padding(
            padding: EdgeInsets.all(24.0),
            child: Text(
              'No hay rubros en el catálogo todavía.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ),
        ],
      );
    }
    return ReorderableListView.builder(
      padding: const EdgeInsets.all(12.0),
      // Sin esto, Flutter arma un drag handle automático (long-press en
      // toda la fila en mobile) — lo desactivamos para que el ÚNICO gesto de
      // arrastre válido sea el ícono dedicado de abajo, sin pisar el onTap
      // que abre SubitemsScreen ni el ícono de borrar.
      buildDefaultDragHandles: false,
      itemCount: _catalogo.length,
      onReorderItem: _onReorder,
      itemBuilder: (context, index) {
        final rubro = _catalogo[index];
        // Número mostrado = posición en _catalogo, que ya viene mezclado y
        // ordenado (ver _mezclarOrden) — nunca rubro.codigo, que queda
        // interno desde esta etapa (docs/rubros_orden_diseno_datos.md §3).
        final numeroMostrado = index + 1;
        return Card(
          // ReorderableListView exige una Key única y estable por ítem.
          key: ValueKey(rubro.id),
          margin: const EdgeInsets.only(bottom: 6.0),
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            // El número pasa del prefijo del título ("N - Nombre") a un
            // badge acá, junto al drag handle — el nombre completo del
            // rubro sigue mostrándose entero (nada se recorta), pero ya no
            // compite por ancho contra el "N - " y el título envuelve menos
            // seguido en pantallas angostas.
            leading: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.puedeEditarComputo) ...[
                  // Oculto (no solo deshabilitado) para quien no puede editar
                  // el cómputo — mismo criterio que el checkbox de
                  // SubitemsScreen, pero acá "no debería aparecer" en vez de
                  // "deshabilitado".
                  ReorderableDragStartListener(
                    index: index,
                    child: const Icon(Icons.drag_handle, color: Colors.black38, size: 20),
                  ),
                  const SizedBox(width: 4),
                ],
                _buildBadgeNumero(numeroMostrado),
              ],
            ),
            title: Text(
              rubro.nombre,
              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1B365D), fontSize: 14),
            ),
            subtitle: rubro.usaApu
                ? null
                : Text(
                    'Precio manual (${rubro.tipoPrecioManual})',
                    style: const TextStyle(color: Colors.black54, fontSize: 11),
                  ),
            // Un rubro propio hoy siempre tiene 0 subitems en catálogo (no
            // existe todavía UI para agregarle subitems custom), así que
            // _buildConteoBadge devolvería null de cualquier forma — el
            // chip "Propio" ocupa ese lugar en vez de convivir con el N/M.
            // Revisar cuando exista esa UI y un rubro propio sí tenga
            // subitems.
            trailing: rubro.creadorUsuarioId != null
                ? _buildTrailingPropio(rubro, numeroMostrado)
                : _buildConteoBadge(rubro),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SubitemsScreen(
                    rubro: rubro,
                    obraId: widget.obraId,
                    puedeEditarComputo: widget.puedeEditarComputo,
                    numeroPosicion: numeroMostrado,
                  ),
                ),
              );
              await _cargarConteos();
            },
          ),
        );
      },
    );
  }

  /// "N de M" tildados en esta obra, para ese rubro. `null` (sin badge) si
  /// el rubro todavía no tiene subitems en el catálogo — evita mostrar un
  /// confuso "0/0" en un rubro custom recién creado (ver Etapa A).
  Widget? _buildConteoBadge(RubroCatalogo rubro) {
    final total = _totalPorRubro[rubro.id] ?? 0;
    if (total == 0) return null;
    final tildados = _tildadosPorRubro[rubro.id] ?? 0;
    final trabajado = tildados > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: trabajado ? Colors.green[50] : Colors.grey[200],
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$tildados/$total',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: trabajado ? Colors.green[800] : Colors.black45,
        ),
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
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber[900]),
      ),
    );
  }

  /// Chip "Propio" + ícono de borrar, solo para rubros del usuario — los
  /// oficiales nunca lo muestran (`_buildConteoBadge` sigue siendo su
  /// trailing). El ícono queda deshabilitado y se reemplaza por un spinner
  /// chico mientras hay un chequeo/DELETE en vuelo para ese rubro puntual.
  Widget _buildTrailingPropio(RubroCatalogo rubro, int numeroMostrado) {
    final procesando = _procesandoEliminacion.contains(rubro.id);
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
            tooltip: 'Eliminar rubro',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => _onEliminarRubro(rubro, numeroMostrado),
          ),
      ],
    );
  }

  /// Chequea uso antes de ofrecer confirmar, y solo confirma si no hay
  /// ninguna fila de `obra_subitems` apuntando a este rubro (ver
  /// ObraSubitemsRepository.getNombresObrasConUso para el criterio exacto).
  /// El catch de `PostgrestException` código 23503 es una red de seguridad
  /// por si algo se cargó entre el chequeo y el DELETE (otro dispositivo,
  /// otra pestaña) — vuelve a consultar para mostrar el mismo diálogo con
  /// nombres reales en vez de un mensaje genérico.
  Future<void> _onEliminarRubro(RubroCatalogo rubro, int numeroMostrado) async {
    setState(() => _procesandoEliminacion.add(rubro.id));
    List<String> obrasConUso;
    try {
      obrasConUso = await _obraSubitemsRepository.getNombresObrasConUso(rubro.id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _procesandoEliminacion.remove(rubro.id));
      _mostrarSnackError('No se pudo verificar si el rubro está en uso. Probá de nuevo.');
      return;
    }
    if (!mounted) return;
    setState(() => _procesandoEliminacion.remove(rubro.id));

    if (obrasConUso.isNotEmpty) {
      _mostrarDialogoBloqueadoPorUso(rubro, numeroMostrado, obrasConUso);
      return;
    }

    final confirmar = await _mostrarDialogoConfirmarEliminar(rubro, numeroMostrado);
    if (confirmar != true) return;

    setState(() => _procesandoEliminacion.add(rubro.id));
    try {
      await _rubrosRepository.eliminar(rubro.id);
      if (!mounted) return;
      await _cargarCatalogo();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _procesandoEliminacion.remove(rubro.id));
      if (e.code == '23503') {
        final obrasActualizadas = await _obraSubitemsRepository.getNombresObrasConUso(rubro.id);
        if (!mounted) return;
        _mostrarDialogoBloqueadoPorUso(rubro, numeroMostrado, obrasActualizadas);
      } else {
        _mostrarSnackError('No se pudo eliminar el rubro. Probá de nuevo.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _procesandoEliminacion.remove(rubro.id));
      _mostrarSnackError('No se pudo eliminar el rubro. Probá de nuevo.');
    }
  }

  Future<bool?> _mostrarDialogoConfirmarEliminar(RubroCatalogo rubro, int numeroMostrado) {
    return showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text(
          'Eliminar rubro',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1B365D)),
        ),
        content: Text('¿Eliminar "$numeroMostrado - ${rubro.nombre}"? Esta acción no se puede deshacer.'),
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

  void _mostrarDialogoBloqueadoPorUso(RubroCatalogo rubro, int numeroMostrado, List<String> obras) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text(
          'No se puede eliminar',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1B365D)),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('"$numeroMostrado - ${rubro.nombre}" tiene datos cargados en:'),
            const SizedBox(height: 8),
            ...obras.map(
              (nombre) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text('• $nombre', style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Sacá esas filas primero desde esas obras para poder eliminarlo.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  void _mostrarSnackError(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  void _onNuevoRubro() {
    if (_esPro) {
      _mostrarDialogoAltaRubro();
    } else {
      mostrarDialogoFuncionPro(
        context,
        mensaje: 'Crear tus propios rubros (para lo que el catálogo no cubre — '
            'piscina, ascensor, paisajismo, etc.) es una función PRO.',
      );
    }
  }

  void _mostrarDialogoAltaRubro() {
    final nombreCtrl = TextEditingController();
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
            final nombre = nombreCtrl.text.trim();
            if (nombre.isEmpty) {
              setModalState(() => error = 'Completá el nombre.');
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
              await _rubrosRepository.crearPersonalizado(
                nombre: nombre,
                creadorUsuarioId: usuarioId,
              );
              if (!dialogCtx.mounted) return;
              Navigator.of(dialogCtx).pop();
              await _cargarCatalogo(); // trae el rubro nuevo, no solo los conteos
            } catch (e) {
              // Ya no hay un código elegido a mano que pueda chocar (Etapa D
              // de docs/rubros_orden_diseno_datos.md — se genera solo del
              // lado de la base, migración 0027) — sin distinción de causa
              // que el usuario pueda accionar, un solo mensaje genérico.
              setModalState(() {
                guardando = false;
                error = 'No se pudo crear el rubro. Probá de nuevo.';
              });
            }
          }

          return AlertDialog(
            title: const Text(
              'Nuevo Rubro',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1B365D)),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nombreCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Nombre', border: OutlineInputBorder(), isDense: true),
                ),
                // Precio manual por subítem, sin selector — 'global' queda
                // reservado a Instalaciones/Carpinterías (decisión de negocio,
                // ver RubrosRepository.crearPersonalizado).
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Se carga con precio manual por subítem, igual que Tareas '
                    'Preliminares y Varios.',
                    style: TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                ],
              ],
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
}
