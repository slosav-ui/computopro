import 'package:flutter/material.dart';
import '../../../data/models/obra_model.dart';
import '../../../data/models/rubro_catalogo.dart';
import '../../../services/rubros_repository.dart';
import '../../../services/subitems_repository.dart';
import '../../../services/obra_subitems_repository.dart';
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

  List<RubroCatalogo> _catalogo = [];
  // Indicador "N de M tildados" por rubro (ver diagnóstico: sin monto real
  // todavía, unit-agnostic, no depende de APU/precio_unitario_manual).
  Map<String, int> _totalPorRubro = {};
  Map<String, int> _tildadosPorRubro = {};
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarCatalogo();
  }

  Future<void> _cargarCatalogo() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final rubros = await _rubrosRepository.getCatalogoOficial();
      final totales = await _subitemsRepository.getConteoOficialPorRubro();
      final tildados = await _obraSubitemsRepository.getConteoTildadosPorObra(widget.obraId);
      if (!mounted) return;
      setState(() {
        _catalogo = rubros;
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
        Expanded(
          child: RefreshIndicator(
            onRefresh: _cargarCatalogo,
            child: _buildContenido(),
          ),
        ),
      ],
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
    return ListView.builder(
      padding: const EdgeInsets.all(12.0),
      itemCount: _catalogo.length,
      itemBuilder: (context, index) {
        final rubro = _catalogo[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8.0),
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: ListTile(
            title: Text(
              '${rubro.codigo} - ${rubro.nombre}',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1B365D), fontSize: 14),
            ),
            subtitle: rubro.usaApu
                ? null
                : Text(
                    'Precio manual (${rubro.tipoPrecioManual})',
                    style: const TextStyle(color: Colors.black54, fontSize: 11),
                  ),
            trailing: _buildConteoBadge(rubro),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SubitemsScreen(
                    rubro: rubro,
                    obraId: widget.obraId,
                    puedeEditarComputo: widget.puedeEditarComputo,
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
}
