import 'package:flutter/material.dart';
import '../../../data/models/rubro_catalogo.dart';
import '../../../data/models/subitem_catalogo.dart';
import '../../../data/models/obra_subitem.dart';
import '../../../services/subitems_repository.dart';
import '../../../services/obra_subitems_repository.dart';
import '../../../services/auth_service.dart';

class SubitemsScreen extends StatefulWidget {
  final RubroCatalogo rubro;
  final String obraId;
  final bool puedeEditarComputo;

  const SubitemsScreen({
    Key? key,
    required this.rubro,
    required this.obraId,
    required this.puedeEditarComputo,
  }) : super(key: key);

  @override
  State<SubitemsScreen> createState() => _SubitemsScreenState();
}

class _SubitemsScreenState extends State<SubitemsScreen> {
  final SubitemsRepository _subitemsRepository = SubitemsRepository();
  final ObraSubitemsRepository _obraSubitemsRepository = ObraSubitemsRepository();
  final AuthService _authService = AuthService();

  List<SubitemCatalogo> _subitems = [];
  Map<String, ObraSubitem> _obraSubitemsPorSubitemId = {};
  bool _cargando = true;
  String? _error;

  // subitemIds con un toggle en vuelo, para deshabilitar su checkbox mientras
  // se guarda y evitar doble tap.
  final Set<String> _guardando = {};

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final subitems = await _subitemsRepository.getSubitemsDeRubro(widget.rubro.id);
      final mapa = await _obraSubitemsRepository.getMapaDeRubro(
        obraId: widget.obraId,
        rubroId: widget.rubro.id,
      );
      if (!mounted) return;
      setState(() {
        _subitems = subitems;
        _obraSubitemsPorSubitemId = mapa;
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

  Future<void> _toggleSubitem(SubitemCatalogo subitem, bool nuevoValor) async {
    final usuarioId = _authService.usuarioActual?.id;
    if (usuarioId == null) return;

    setState(() => _guardando.add(subitem.id));
    try {
      final existente = _obraSubitemsPorSubitemId[subitem.id];
      final ObraSubitem actualizado;
      if (existente == null) {
        // Primera vez que aparece en la obra: siempre insert con
        // es_aplicable = true (a este punto solo se llega tildando).
        actualizado = await _obraSubitemsRepository.crear(
          obraId: widget.obraId,
          rubroId: widget.rubro.id,
          subitemId: subitem.id,
          agregadoPorUsuarioId: usuarioId,
        );
      } else {
        // Ya tenía fila: nunca se borra, solo cambia es_aplicable —
        // preserva cantidad para si se vuelve a tildar.
        actualizado = await _obraSubitemsRepository.actualizarEsAplicable(
          id: existente.id,
          esAplicable: nuevoValor,
          usuarioId: usuarioId,
        );
      }
      if (!mounted) return;
      setState(() {
        _obraSubitemsPorSubitemId = {
          ..._obraSubitemsPorSubitemId,
          subitem.id: actualizado,
        };
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo guardar el cambio. Probá de nuevo.')),
      );
    } finally {
      if (mounted) setState(() => _guardando.remove(subitem.id));
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
        onRefresh: _cargarDatos,
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
        final aplicable = _obraSubitemsPorSubitemId[subitem.id]?.esAplicable ?? false;
        final guardandoEste = _guardando.contains(subitem.id);
        final puedeEditar = widget.puedeEditarComputo && !guardandoEste;
        return Card(
          margin: const EdgeInsets.only(bottom: 8.0),
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: ListTile(
            leading: Checkbox(
              value: aplicable,
              onChanged: puedeEditar
                  ? (val) => _toggleSubitem(subitem, val ?? false)
                  : null,
            ),
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
