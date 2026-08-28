import 'package:flutter/material.dart';
import '../../../data/models/rubro_catalogo.dart';
import '../../../data/models/subitem_catalogo.dart';
import '../../../services/subitems_repository.dart';

class SubitemsScreen extends StatefulWidget {
  final RubroCatalogo rubro;

  const SubitemsScreen({Key? key, required this.rubro}) : super(key: key);

  @override
  State<SubitemsScreen> createState() => _SubitemsScreenState();
}

class _SubitemsScreenState extends State<SubitemsScreen> {
  final SubitemsRepository _subitemsRepository = SubitemsRepository();

  List<SubitemCatalogo> _subitems = [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarSubitems();
  }

  Future<void> _cargarSubitems() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final subitems = await _subitemsRepository.getSubitemsDeRubro(widget.rubro.id);
      if (!mounted) return;
      setState(() {
        _subitems = subitems;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar los subitems de este rubro.';
        _cargando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.rubro.codigo} - ${widget.rubro.nombre}'),
        backgroundColor: const Color(0xFF1B365D),
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _cargarSubitems,
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
    if (_subitems.isEmpty) {
      return ListView(
        children: const [
          Padding(
            padding: EdgeInsets.all(24.0),
            child: Text(
              'No hay subitems en el catálogo para este rubro todavía.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12.0),
      itemCount: _subitems.length,
      itemBuilder: (context, index) {
        final subitem = _subitems[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8.0),
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: ListTile(
            title: Text(
              '${subitem.codigo} - ${subitem.descripcion}',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            subtitle: Text(
              'Unidad: ${subitem.unidad}',
              style: const TextStyle(color: Colors.black54, fontSize: 11),
            ),
          ),
        );
      },
    );
  }
}
