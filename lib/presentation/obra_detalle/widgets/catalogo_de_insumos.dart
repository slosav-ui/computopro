import 'package:flutter/material.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/models/insumo_del_catalogo.dart';
import '../../../data/models/valor_hora_categoria.dart';
import '../../../services/auth_service.dart';
import '../../../services/insumos_repository.dart';
import '../../../services/perfil_repository.dart';

/// Lo que muestra la solapa Mat y MO cuando la obra todavía no tiene insumos: **el catálogo de
/// materiales con su precio de referencia y las categorías de mano de obra con su valor hora**, en
/// gris.
///
/// ---------------------------------------------------------------- por qué insumos y no partidas
///
/// La versión anterior de este vacío mostraba las partidas del catálogo, igual que la solapa APU.
/// Seba lo corrigió el 2026-09-15:
///
/// > *"Mat y MO está mostrando las partidas de APU. Ahí no van partidas. Tienen que aparecer los
/// > materiales y la mano de obra del catálogo en gris — los 174 insumos con sus precios de los
/// > corralones, y las categorías de mano de obra con su valor hora. Eso es lo que muestra el
/// > potencial de esa solapa: el que la abre tiene que ver que la app trae precios reales de la
/// > zona."*
///
/// El criterio general —el vacío muestra lo que la pantalla puede hacer— es el mismo que en APU,
/// pero **cada solapa tiene que mostrar SU materia prima**. Mat y MO no es una lista de partidas:
/// es la lista de qué se compra y a quién se le paga. Mostrar partidas acá repetía la solapa de al
/// lado y no decía nada del valor propio de esta.
///
/// ---------------------------------------------------------------- de dónde salen los precios
///
/// De `catalogo_insumos_con_precio` (migración 0152), no de la tabla. `precios` tiene RLS por
/// corralón (`is_corralon_owner`, 0013): consultarla desde la app devuelve **cero filas, sin
/// error** -- parecería que no hay precios cargados. La función es `security definer` y devuelve
/// promedio y cantidad, nunca el precio de un corralón puntual.
///
/// El valor hora NO se pide acá: lo carga la solapa en `_cargarConsolidado` y lo pasa por
/// parámetro. Es por obra (depende de cargas sociales y de los 7 parámetros de esa obra), así que
/// la solapa ya lo tiene y pedirlo de nuevo sería traer otra cosa.
class CatalogoDeInsumos extends StatefulWidget {
  /// Qué hay acá y qué pasa al tildar una partida, dicho para esta solapa.
  final String mensaje;

  /// Se muestra solo a un usuario Free.
  final String notaPro;

  /// Mismo gate de rol que usa el resto de la solapa: sin esto, cantidad y nombre pero ningún
  /// precio. No alcanza con deshabilitar -- se oculta, igual que en SubitemsScreen.
  final bool puedeVerMontos;

  /// Valor hora por categoría UOCRA de ESTA obra, ya cargado por la solapa.
  final Map<String, ValorHoraCategoria> valorHoraPorCategoria;

  const CatalogoDeInsumos({
    Key? key,
    required this.mensaje,
    required this.notaPro,
    required this.puedeVerMontos,
    required this.valorHoraPorCategoria,
  }) : super(key: key);

  @override
  State<CatalogoDeInsumos> createState() => _CatalogoDeInsumosState();
}

class _CatalogoDeInsumosState extends State<CatalogoDeInsumos> {
  final InsumosRepository _insumosRepository = InsumosRepository();
  final PerfilRepository _perfilRepository = PerfilRepository();
  final AuthService _authService = AuthService();

  bool _cargando = true;
  bool _esPro = true; // fail-safe: sin dato, no se muestra la nota PRO
  List<InsumoDelCatalogo> _materiales = [];
  int _conPrecio = 0;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    if (mounted) setState(() => _cargando = true);
    try {
      final usuarioId = _authService.usuarioActual?.id;
      final catalogo = await _insumosRepository.getCatalogoConPrecio();
      final esPro = usuarioId == null ? true : await _perfilRepository.esPro(usuarioId);
      if (!mounted) return;
      setState(() {
        // La mano de obra del catálogo de insumos no se lista acá: para el usuario la mano de obra
        // son las categorías UOCRA con su valor hora, que es otra cosa y viene por parámetro.
        _materiales = catalogo.where((i) => !i.esManoDeObra).toList();
        _conPrecio = _materiales.where((i) => i.precioPromedio != null).length;
        _esPro = esPro;
        _cargando = false;
      });
    } catch (e) {
      // Sin rama de error propia: este widget YA es el estado de "no hay nada que mostrar". Fallar
      // al traer el catálogo no justifica pisar la pantalla con un error -- queda el cartel solo.
      if (!mounted) return;
      setState(() {
        _materiales = [];
        _cargando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Center(child: CircularProgressIndicator());

    final categorias = widget.valorHoraPorCategoria.values.toList()
      ..sort((a, b) => a.categoriaUocra.compareTo(b.categoriaUocra));

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.all(12),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _buildCartel(categorias.length),
          const SizedBox(height: 12),
          if (categorias.isNotEmpty) _buildSeccionManoDeObra(categorias),
          if (_materiales.isNotEmpty) _buildSeccionMateriales(),
        ],
      ),
    );
  }

  /// Fondo ámbar suave y no un cartel de error: no hay nada roto. Es una invitación.
  Widget _buildCartel(int categorias) {
    final partes = <String>[];
    if (widget.puedeVerMontos && _conPrecio > 0) {
      partes.add('$_conPrecio materiales con precio de corralón');
    } else if (_materiales.isNotEmpty) {
      partes.add('${_materiales.length} materiales');
    }
    if (categorias > 0) partes.add('$categorias categorías de mano de obra');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber[200]!),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.auto_awesome_outlined, size: 18, color: Colors.amber[800]),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.mensaje,
                  style: const TextStyle(fontSize: 12, color: Colors.black87, height: 1.35),
                ),
                if (partes.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${partes.join(' · ')}, cargados y listos para usar.',
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ],
                if (!_esPro) ...[
                  const SizedBox(height: 6),
                  Text(
                    widget.notaPro,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.amber[900],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Arriba de materiales: es la parte que más se mira y la que más trabajo tiene detrás (los 7
  /// parámetros, las cargas sociales, el valor hora derivado — ver
  /// docs/costo_mano_de_obra_decisiones.md). Y es específica de ESTA obra, no del catálogo global.
  Widget _buildSeccionManoDeObra(List<ValorHoraCategoria> categorias) {
    return _buildTarjeta(
      titulo: 'Mano de obra',
      icono: Icons.engineering,
      subtitulo: 'Valor hora por categoría UOCRA, calculado con los parámetros de esta obra.',
      filas: [
        for (final c in categorias)
          _buildFila(
            nombre: c.categoriaUocra,
            unidad: 'hora',
            valor: widget.puedeVerMontos ? CurrencyFormatter.formatARS(c.valorHora) : null,
            nota: null,
          ),
      ],
    );
  }

  Widget _buildSeccionMateriales() {
    return _buildTarjeta(
      titulo: 'Materiales',
      icono: Icons.inventory_2,
      subtitulo: 'Precio promedio de los corralones cargados en la zona.',
      filas: [
        for (final i in _materiales)
          _buildFila(
            nombre: i.nombre,
            unidad: i.unidad,
            valor: !widget.puedeVerMontos
                ? null
                : i.precioPromedio == null
                    ? 'sin precio'
                    : CurrencyFormatter.formatARS(i.precioPromedio!),
            // Confianza del dato: no es lo mismo un promedio de tres corralones que uno solo.
            nota: (!widget.puedeVerMontos || i.cantidadPrecios < 2)
                ? null
                : 'prom. de ${i.cantidadPrecios}',
          ),
      ],
    );
  }

  Widget _buildTarjeta({
    required String titulo,
    required IconData icono,
    required String subtitulo,
    required List<Widget> filas,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: Colors.grey[100],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey[300]!),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icono, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 6),
                Text(
                  titulo,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey[700]),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(subtitulo, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
            Divider(height: 16, color: Colors.grey[300]),
            ...filas,
          ],
        ),
      ),
    );
  }

  /// Inerte, no tocable: estos insumos no están en la obra, no hay nada que editar todavía.
  Widget _buildFila({
    required String nombre,
    required String unidad,
    required String? valor,
    required String? nota,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nombre,
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(unidad, style: TextStyle(fontSize: 10, color: Colors.grey[500])),
              ],
            ),
          ),
          if (valor != null) ...[
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  valor,
                  style: TextStyle(fontSize: 12, color: Colors.grey[700], fontWeight: FontWeight.w600),
                ),
                if (nota != null)
                  Text(nota, style: TextStyle(fontSize: 9, color: Colors.grey[500])),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
