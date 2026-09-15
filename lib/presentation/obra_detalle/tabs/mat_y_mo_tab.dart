import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/utils/parser_numero_ar.dart';
import '../../../data/models/insumo_consolidado_obra.dart';
import '../../../data/models/insumo_del_catalogo.dart';
import '../../../data/models/obra_presupuesto_config.dart';
import '../../../data/models/valor_hora_categoria.dart';
import '../../../services/auth_service.dart';
import '../../../services/obra_insumos_repository.dart';
import '../../../services/obra_presupuesto_config_repository.dart';
import '../../../services/valor_hora_mano_obra_repository.dart';
import '../../../services/insumos_repository.dart';
import '../widgets/cartel_vista_previa.dart';
import 'cartel_costo_mano_obra.dart';
import 'panel_valor_hora_mano_obra.dart';

/// Una sección de la lista de insumos (título, ícono, predicado sobre `InsumoConsolidadoObra.tipo`).
/// Agregar una sección nueva (ej. "Equipos") es sumar una entrada acá — no reescribir el filtrado.
class _SeccionInsumos {
  final String titulo;
  final IconData icono;
  final bool Function(InsumoConsolidadoObra) predicado;

  const _SeccionInsumos(this.titulo, this.icono, this.predicado);
}

/// Solapa "Mat y MO" — consolidado real de insumos de la obra, con edición manual de precio por
/// insumo (materiales) y por categoría UOCRA (mano de obra, ver
/// docs/costo_mano_de_obra_decisiones.md). Reemplaza el mock que tenía
/// `presupuestos_screen.dart._buildTabMaterialesYMo()`.
class MatYMoTab extends StatefulWidget {
  final String obraId;

  // Regla de visibilidad 1 de UserContext (Caja Blanca: admin_maestro/profesional/constructor
  // desde el cambio de matriz de 2026-09-12 -- el constructor es quien cotiza y compra, necesita los
  // precios) — mismo gate que ya usan RubrosTab/SubitemsScreen para precio/subtotal. Cliente
  // Principal (Caja Negra Comercial, ve montos de certificados pero no la estructura de costo
  // interna) queda afuera: acá no hay un permiso aparte para "ve montos de obra pero no de insumos"
  // — es la misma pregunta que ya resuelve este getter en el resto de la app.
  //
  // Sin puedeVerMontosYAPU: cantidad sola por insumo, sin precio/valor hora/cartel de costo de
  // mano de obra ni lápiz de edición — oculto, no deshabilitado (mismo criterio que
  // SubitemsScreen). RLS no filtra columnas, solo filas: el consolidado sigue viajando completo
  // al cliente para estos roles, esto es exclusivamente el gate de la capa de app.
  final bool puedeVerMontosYAPU;

  // `UserContext.puedeEditarPreciosObra` -- lápiz de precio/valor hora, "Volver" del override y el
  // tilde de cargas sociales. Separado de ver desde 2026-09-12: el constructor ve los precios pero
  // no los cambia (RLS de obra_insumo_precios/obra_valor_hora_override/obra_presupuesto_config).
  final bool puedeEditarPrecios;

  const MatYMoTab({
    Key? key,
    required this.obraId,
    required this.puedeVerMontosYAPU,
    required this.puedeEditarPrecios,
  }) : super(key: key);

  @override
  State<MatYMoTab> createState() => _MatYMoTabState();
}

class _MatYMoTabState extends State<MatYMoTab> {
  final ObraInsumosRepository _obraInsumosRepository = ObraInsumosRepository();
  final ObraPresupuestoConfigRepository _configRepository = ObraPresupuestoConfigRepository();
  final ValorHoraManoObraRepository _valorHoraRepository = ValorHoraManoObraRepository();
  final InsumosRepository _insumosRepository = InsumosRepository();
  final AuthService _authService = AuthService();

  // Sin sección propia de Equipos todavía (mismo criterio que el badge de presupuesto en firme:
  // no construir el caso que no existe, pero dejar la estructura lista) — 'equipo' cae bajo
  // Materiales hasta que haga falta separarlo.
  static final List<_SeccionInsumos> _secciones = [
    _SeccionInsumos('Mano de obra', Icons.engineering, (i) => i.tipo == 'mano_obra'),
    _SeccionInsumos('Materiales', Icons.inventory_2, (i) => i.tipo != 'mano_obra'),
  ];

  List<InsumoConsolidadoObra> _insumos = [];

  /// `true` cuando lo que se está listando NO son los insumos de esta obra sino el catálogo, para
  /// atenuarlo y explicar por qué (ver `cartel_vista_previa.dart`). Las secciones y las tarjetas
  /// son las mismas -- lo único que cambia es de dónde salieron los insumos y que la tarjeta no
  /// muestra la cantidad, porque una obra sin nada tildado no necesita ninguna.
  bool _vitrina = false;
  ObraPresupuestoConfig? _config;
  // Paso 5, tanda 2: valor hora por categoría UOCRA, para la línea "Volver" de cada fila con
  // override — ver docs/costo_mano_de_obra_decisiones.md §15. Independiente de la carga que hace
  // CartelCostoManoObra (a propósito, no se toca ese widget en esta tanda).
  Map<String, ValorHoraCategoria> _valorHoraPorCategoria = {};
  bool _cargando = true;
  String? _error;

  // Sincronización en tiempo real, primer corte — una sola tabla (ver diagnóstico de la pieza).
  RealtimeChannel? _obraInsumoPreciosChannel;

  @override
  void initState() {
    super.initState();
    _cargarConsolidado();
    _suscribirCambiosPrecios();
  }

  @override
  void dispose() {
    // Preferido, según la propia documentación de Flutter para este caso (cancelar la
    // suscripción en dispose, no solo confiar en el guard de `mounted` de más abajo): sin esto,
    // cada entrada/salida de esta solapa deja un canal más abierto, y eso sí puede llegar al
    // límite de conexiones concurrentes del plan gratuito de Supabase. `removeChannel` devuelve
    // un Future que a propósito no se espera acá — dispose() de Flutter tiene que ser sincrónico.
    final channel = _obraInsumoPreciosChannel;
    if (channel != null) {
      Supabase.instance.client.removeChannel(channel);
    }
    super.dispose();
  }

  /// Suscribe a cambios de `obra_insumo_precios` de esta obra — dispara `_cargarConsolidado`
  /// en modo silencioso cuando otro dispositivo edita un precio. Filtrado por obra_id del lado
  /// del servidor: la RLS de la tabla (0030) ya garantiza que nunca llega un evento de una obra
  /// ajena aunque este filtro fallara, pero filtrar acá evita procesar de más los eventos de las
  /// otras obras propias del usuario.
  void _suscribirCambiosPrecios() {
    _obraInsumoPreciosChannel = Supabase.instance.client
        .channel('obra_insumo_precios_${widget.obraId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'obra_insumo_precios',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'obra_id',
            value: widget.obraId,
          ),
          callback: (payload) => _cargarConsolidado(silencioso: true),
        )
        .subscribe();
  }

  /// Carga las tres cosas que la solapa necesita en conjunto — consolidado, config de la obra y
  /// valor hora por categoría. Se recarga entera tanto al abrir la solapa como después de
  /// cualquier cambio (editar precio, tildar cargas sociales desde el cartel, guardar o borrar un
  /// override, guardar los 7 parámetros) para que nada quede desincronizado — ver
  /// docs/costo_mano_de_obra_decisiones.md §15 sobre por qué las tres fuentes tienen que recargar
  /// juntas.
  ///
  /// El estado PRO NO se carga acá — el panel de mano de obra lo verifica en vivo en el momento
  /// de guardar (ver panel_valor_hora_mano_obra.dart), no contra una foto vieja: un `esPro`
  /// cargado acá y pasado por parámetro fue exactamente el bug real que dejaba pasar un guardado
  /// de Free sin mostrar el diálogo de función PRO.
  ///
  /// [silencioso]: true cuando dispara un evento de Realtime en segundo plano (ver
  /// _suscribirCambiosPrecios) — no pone `_cargando` (no reemplaza la lista por un spinner por un
  /// cambio ajeno) y, si falla, no toca `_error` (se queda mostrando lo último que cargó bien en
  /// vez de romper la pantalla por algo que pasó en segundo plano). false para la carga inicial y
  /// el pull-to-refresh manual, donde sí corresponde mostrar spinner/error.
  Future<void> _cargarConsolidado({bool silencioso = false}) async {
    if (!silencioso) {
      setState(() {
        _cargando = true;
        _error = null;
      });
    }
    try {
      final insumosFuture = _obraInsumosRepository.getConsolidado(widget.obraId);
      final configFuture = _configRepository.getConfig(widget.obraId);
      final valorHoraFuture = _valorHoraRepository.getValorHoraPorCategoria(widget.obraId);

      final insumos = await insumosFuture;
      final config = await configFuture;
      final valorHora = await valorHoraFuture;
      // Sin insumos propios se lista el catálogo, con la pantalla atenuada. Se resuelve acá y no en
      // un widget aparte para que lo que se muestra sea ESTA pantalla, con las mismas secciones y
      // las mismas tarjetas.
      final vitrina = insumos.isEmpty;
      final insumosFinales = vitrina ? await _insumosDelCatalogo(valorHora) : insumos;

      if (!mounted) return;
      setState(() {
        _insumos = insumosFinales;
        _vitrina = vitrina;
        _config = config;
        _valorHoraPorCategoria = {for (final v in valorHora) v.categoriaUocra: v};
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (silencioso) return;
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
    // En vitrina el subtítulo no puede hablar de "las composiciones tildadas en esta obra": no hay
    // ninguna, y los contadores de "sin precio" medirían el catálogo en vez de la obra.
    final String subtitulo = _vitrina
        ? 'Catálogo disponible: materiales con precio de corralón y mano de obra por convenio.'
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
          _atenuar(
            Card(
              child: ListTile(
                leading: const Icon(Icons.inventory, color: Color(0xFF1B365D)),
                title: const Text('Consolidado de Insumos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                subtitle: Text(subtitulo, style: const TextStyle(fontSize: 11)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (final seccion in _secciones) ...[
            // Cartel de costo de mano de obra + tilde de cargas sociales (Paso 5, tanda 1) —
            // arriba de la sección, solo cuando esa sección va a tener filas (mismo criterio
            // que _buildSeccion: sin banner sobre una lista vacía). onCambio sigue apuntando a
            // _cargarConsolidado, que ahora también recarga config y valor hora por categoría —
            // el cartel no se tocó, solo lo que ese callback hace por dentro.
            //
            // **NO se atenúa ni en vitrina**, y es la corrección de Seba: el costo de mano de obra
            // es dato real de ESTA obra (cargas sociales, valor hora, los 7 parámetros) y se edita
            // aunque no haya un solo insumo cargado. Atenuarlo lo haría parecer inactivo cuando es
            // lo único que sí funciona en esta pantalla.
            if (seccion.titulo == 'Mano de obra' &&
                _insumos.any(seccion.predicado) &&
                widget.puedeVerMontosYAPU)
              CartelCostoManoObra(
                obraId: widget.obraId,
                onCambio: _cargarConsolidado,
                puedeEditar: widget.puedeEditarPrecios,
              ),
            ..._buildSeccion(seccion).map(_atenuar),
            // El cartel va DEBAJO del bloque de mano de obra, no arriba de todo: arriba tapaba
            // justamente lo único editable de la pantalla (Seba). Acá explica lo que sigue -- el
            // catálogo de materiales -- que es lo que efectivamente es una muestra.
            if (_vitrina && seccion.titulo == 'Mano de obra')
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: CartelVistaPrevia(
                  obraId: widget.obraId,
                  scope: 'mat_y_mo',
                  mensaje: 'Así se va a ver esta solapa. Los materiales y la mano de obra salen del '
                      'análisis de cada partida: tildá una del catálogo en la solapa Cómputo y sus '
                      'insumos aparecen acá, con cantidades y precios.',
                  detalle: _detalleVitrina(),
                  notaPro: 'Editar el análisis de una partida y crear los tuyos es una función PRO.',
                ),
              ),
          ],
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
                  // En vitrina no se muestra la cantidad: esta obra no necesita nada de
                  // esto todavía, y 174 renglones diciendo "Cantidad necesaria: 0" es ruido, no
                  // información. Lo demás de la tarjeta queda igual.
                  if (!_vitrina)
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
  /// El catálogo de insumos, mapeado a la misma forma que usa la grilla real.
  ///
  /// **Materiales** con su precio promedio de corralón, que viene de `catalogo_insumos_con_precio`
  /// (migración 0152) y no de la tabla: `precios` tiene RLS por corralón, así que consultarla desde
  /// la app devuelve cero filas **sin error** -- parecería que no hay precios cargados.
  ///
  /// **Mano de obra** de `valorHora` y no del catálogo de insumos: para el usuario la mano de obra
  /// son las 5 categorías UOCRA con su valor hora, que sale del convenio con las cargas sociales
  /// (docs/costo_mano_de_obra_decisiones.md) y no de ningún corralón. Es el mismo dato que la
  /// solapa ya tiene cargado para esta obra.
  ///
  /// `cantidadTotal` en 0 es correcto y honesto: esta obra todavía no necesita nada de esto. La
  /// tarjeta no la muestra en vitrina (ver `_buildInsumoCard`) justamente para no llenar la pantalla
  /// de ceros.
  Future<List<InsumoConsolidadoObra>> _insumosDelCatalogo(
    List<ValorHoraCategoria> valorHora,
  ) async {
    // Try propio: si falla traer el catálogo, la solapa NO tiene que mostrar "no se pudo cargar el
    // consolidado de esta obra". Es una obra vacía, no una obra rota -- se muestra lo que haya
    // (las categorías de mano de obra, que ya están cargadas) y listo.
    List<InsumoDelCatalogo> catalogo = [];
    try {
      catalogo = await _insumosRepository.getCatalogoConPrecio();
    } catch (_) {
      // Caso típico: la 0152 todavía no está aplicada.
    }
    return [
      for (final v in valorHora)
        InsumoConsolidadoObra(
          insumoId: 'vitrina-mo-${v.categoriaUocra}',
          nombre: v.categoriaUocra,
          unidad: 'hs',
          tipo: 'mano_obra',
          categoriaUocra: v.categoriaUocra,
          cantidadTotal: 0,
          precio: v.valorHora,
          tienePrecio: true,
          origen: 'automatico',
        ),
      for (final i in catalogo.where((i) => !i.esManoDeObra))
        InsumoConsolidadoObra(
          insumoId: i.id,
          nombre: i.nombre,
          unidad: i.unidad,
          tipo: i.tipo,
          categoriaUocra: null,
          cantidadTotal: 0,
          precio: i.precioPromedio,
          tienePrecio: i.precioPromedio != null,
          origen: 'automatico',
        ),
    ];
  }

  /// `Opacity` sin `IgnorePointer`: atenúa sin bloquear el gesto de desplazar. Lo que no se puede
  /// tocar se apaga en cada control (el lápiz, el "Volver"), no con una manta por encima -- un
  /// `IgnorePointer` sobre la lista se come el scroll y deja el catálogo imposible de recorrer.
  Widget _atenuar(Widget hijo) => _vitrina ? Opacity(opacity: 0.55, child: hijo) : hijo;

  String _detalleVitrina() {
    final materiales = _insumos.where((i) => i.tipo != 'mano_obra').length;
    final conPrecio = _insumos.where((i) => i.tipo != 'mano_obra' && i.tienePrecio).length;
    final categorias = _insumos.length - materiales;
    return widget.puedeVerMontosYAPU
        ? '$conPrecio de $materiales materiales con precio de corralón · $categorias categorías de '
            'mano de obra por convenio.'
        : '$materiales materiales · $categorias categorías de mano de obra.';
  }

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
    // Gate de privacidad primero, antes de cualquier otro caso — mismo criterio que
    // SubitemsScreen._buildContenido: sin puedeVerMontosYAPU, nada de precio/valor hora/edición
    // para esta fila, sin importar si tiene precio cargado o no.
    if (!widget.puedeVerMontosYAPU) return const SizedBox.shrink();

    // "Volver" a la vista, en la propia fila (Paso 5, tanda 2 — ver
    // docs/costo_mano_de_obra_decisiones.md §15): el camino principal para deshacer un override no
    // es el panel del lápiz, es esto — el usuario que fijó un valor hace dos meses no va a abrir
    // el panel para encontrarlo. Solo aparece con datos completos (categoría + config cargados);
    // si por lo que sea faltara alguno, no se muestra nada en vez de arriesgar un null.
    final categoria = insumo.categoriaUocra != null ? _valorHoraPorCategoria[insumo.categoriaUocra] : null;
    final config = _config;
    final muestraVolver =
        insumo.tipo == 'mano_obra' && insumo.origen == 'override' && categoria != null && config != null;

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
              if (muestraVolver && widget.puedeEditarPrecios && !_vitrina) ...[
                const SizedBox(height: 2),
                InkWell(
                  onTap: () => _onVolverDesdeFila(insumo),
                  child: Text(
                    // El valor al que volvería es el que tomaría hoy sin override: con cargas o
                    // sin cargas según el tilde actual de la obra — mismo criterio que el panel.
                    'Valor UOCRA: ${_fmtPrecio(config.aplicaCargasSociales ? categoria.valorHoraConCargas : categoria.valorHoraSinCargas)} — Volver',
                    style: const TextStyle(fontSize: 9, color: Color(0xFF1B365D), decoration: TextDecoration.underline),
                  ),
                ),
              ],
            ],
          )
        else
          _buildFaltaPrecio(),
        // En vitrina no hay lápiz: el insumo no está en la obra, no hay precio de obra que fijar.
        if (widget.puedeEditarPrecios && !_vitrina)
          InkWell(
            onTap: () => _onTocarLapiz(insumo),
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

  /// "Volver" desde la fila (no desde el panel) — borra el override y recarga todo. Sin diálogo de
  /// confirmación a propósito: el valor de destino ya se muestra en el propio link antes de
  /// tocarlo, esa es la decisión informada que pedía el diseño — un diálogo encima sería fricción
  /// redundante.
  Future<void> _onVolverDesdeFila(InsumoConsolidadoObra insumo) async {
    final categoria = insumo.categoriaUocra;
    if (categoria == null) return;
    try {
      await _obraInsumosRepository.borrarValorHoraOverride(obraId: widget.obraId, categoriaUocra: categoria);
      await _cargarConsolidado();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo volver al valor calculado.')),
      );
    }
  }

  /// Dispatch del lápiz: mano de obra abre el panel dedicado (categoría, no insumo suelto — ver
  /// docs/costo_mano_de_obra_decisiones.md §13/§15); materiales siguen con el diálogo genérico de
  /// siempre, sin cambios de comportamiento.
  Future<void> _onTocarLapiz(InsumoConsolidadoObra insumo) async {
    if (insumo.tipo == 'mano_obra') {
      final categoria = insumo.categoriaUocra != null ? _valorHoraPorCategoria[insumo.categoriaUocra] : null;
      final config = _config;
      // Caso imposible en la práctica (constraint insumos_mano_obra_requiere_categoria, 0042) pero
      // sin garantía absoluta desde Dart — si igual llegara a pasar, frena visible acá.
      if (categoria == null || config == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Este insumo de mano de obra no tiene categoría UOCRA asignada — no se puede '
              'editar. Es un dato inconsistente, avisá al soporte.',
            ),
          ),
        );
        return;
      }
      final cambio = await showDialog<bool>(
        context: context,
        builder: (_) => PanelValorHoraManoObra(
          obraId: widget.obraId,
          insumo: insumo,
          todosLosInsumos: _insumos,
          valorHoraCategoria: categoria,
        ),
      );
      if (cambio == true) await _cargarConsolidado();
    } else {
      await _mostrarDialogoEditarPrecio(insumo);
    }
  }

  Future<void> _mostrarDialogoEditarPrecio(InsumoConsolidadoObra insumo) async {
    final usuarioId = _authService.usuarioActual?.id;
    if (usuarioId == null) return;

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
                'Este precio se usa en el cálculo de todas las partidas de esta obra que llevan '
                '${insumo.nombre}. Al guardarlo se actualiza el costo de esas partidas.',
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

    try {
      await _obraInsumosRepository.guardarPrecioManual(
        obraId: widget.obraId,
        insumoId: insumo.insumoId,
        precio: nuevoPrecio,
        usuarioId: usuarioId,
      );
      await _cargarConsolidado();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo guardar el precio.')),
      );
    }
  }
}
