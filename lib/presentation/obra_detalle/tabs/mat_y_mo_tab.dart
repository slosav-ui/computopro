import 'package:flutter/material.dart';
import '../../../data/models/insumo_consolidado_obra.dart';
import '../../../services/obra_insumos_repository.dart';

/// Solapa "Mat y MO" — paso 2 de la pieza (ver memoria "mat_y_mo_fuentes_precio"): consolidado
/// real de insumos de la obra, solo lectura. Reemplaza el mock que tenía
/// `presupuestos_screen.dart._buildTabMaterialesYMo()`.
class MatYMoTab extends StatefulWidget {
  final String obraId;

  const MatYMoTab({Key? key, required this.obraId}) : super(key: key);

  @override
  State<MatYMoTab> createState() => _MatYMoTabState();
}

class _MatYMoTabState extends State<MatYMoTab> {
  final ObraInsumosRepository _obraInsumosRepository = ObraInsumosRepository();

  List<InsumoConsolidadoObra> _insumos = [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarConsolidado();
  }

  Future<void> _cargarConsolidado() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final insumos = await _obraInsumosRepository.getConsolidado(widget.obraId);
      if (!mounted) return;
      setState(() {
        _insumos = insumos;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
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

    final sinPrecio = _insumos.where((i) => !i.tienePrecio).length;
    final String subtitulo = _insumos.isEmpty
        ? 'Todavía no hay insumos: tildá subítems con APU en el Cómputo para verlos acá.'
        : sinPrecio == 0
            ? '${_insumos.length} insumos, según las composiciones de APU tildadas en esta obra.'
            : '${_insumos.length} insumos — $sinPrecio sin precio cargado todavía.';

    return RefreshIndicator(
      onRefresh: _cargarConsolidado,
      child: ListView(
        padding: const EdgeInsets.all(12),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.inventory, color: Color(0xFF1B365D)),
              title: const Text('Consolidado de Insumos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              subtitle: Text(subtitulo, style: const TextStyle(fontSize: 11)),
            ),
          ),
          const SizedBox(height: 8),
          if (_insumos.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text('Sin insumos todavía.', style: TextStyle(color: Colors.black45, fontSize: 12)),
              ),
            )
          else
            ..._insumos.map(_buildInsumoCard),
        ],
      ),
    );
  }

  Widget _buildInsumoCard(InsumoConsolidadoObra insumo) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        leading: Icon(_iconoTipo(insumo.tipo), color: const Color(0xFF1B365D), size: 20),
        title: Text(insumo.nombre, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        subtitle: Text(
          'Cantidad necesaria: ${_fmtCantidad(insumo.cantidadTotal)} ${insumo.unidad}',
          style: const TextStyle(fontSize: 10),
        ),
        trailing: insumo.tienePrecio
            ? Text(
                _fmtPrecio(insumo.valorReferencial!),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF2E7D32)),
              )
            : _buildFaltaPrecio(),
      ),
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
}
