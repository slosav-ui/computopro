import 'package:flutter/material.dart';
import '../../../data/models/obra_model.dart';
import '../../../data/models/rubro_catalogo.dart';
import '../../../services/rubros_repository.dart';

class RubrosTab extends StatefulWidget {
  final ObraModel? obra;

  const RubrosTab({Key? key, this.obra}) : super(key: key);

  @override
  State<RubrosTab> createState() => _RubrosTabState();
}

class _RubrosTabState extends State<RubrosTab> {
  final RubrosRepository _rubrosRepository = RubrosRepository();

  List<RubroCatalogo> _catalogo = [];
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
      if (!mounted) return;
      setState(() {
        _catalogo = rubros;
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
          ),
        );
      },
    );
  }
}
