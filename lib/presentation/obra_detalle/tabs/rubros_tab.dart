import 'package:flutter/material.dart';
import '../../../../models/rubro.dart';
import '../../../../models/subitem.dart';
import '../../../../models/obra_model.dart';
import 'agregar_subitem_dialog.dart';

class RubrosTab extends StatefulWidget {
  final List<Rubro>? rubros;
  final Function(List<Rubro>)? onRubrosChanged;
  final ObraModel? obra;

  const RubrosTab({
    Key? key,
    this.rubros,
    this.onRubrosChanged,
    this.obra,
  }) : super(key: key);

  @override
  State<RubrosTab> createState() => _RubrosTabState();
}

class _RubrosTabState extends State<RubrosTab> {
  late List<Rubro> _listaRubros;

  @override
  void initState() {
    super.initState();
    _listaRubros = widget.rubros != null ? List<Rubro>.from(widget.rubros!) : [];
  }

  @override
  void didUpdateWidget(covariant RubrosTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.rubros != null && widget.rubros != oldWidget.rubros) {
      setState(() {
        _listaRubros = List<Rubro>.from(widget.rubros!);
      });
    }
  }

  void _notificarCambio() {
    if (widget.onRubrosChanged != null) {
      widget.onRubrosChanged!(_listaRubros);
    }
  }

  String _fmt(double monto) {
    final valorInt = monto.round();
    final str = valorInt.toString();
    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    final formateado = str.replaceAllMapped(reg, (Match m) => '${m[1]}.');
    return '\$ $formateado';
  }

  double get _totalGeneralDirecto {
    double total = 0.0;
    for (var r in _listaRubros) {
      total += r.totalRubro;
    }
    return total;
  }

  int get _cantidadSubitemsTotales {
    int count = 0;
    for (var r in _listaRubros) {
      count += r.subitems.length;
    }
    return count;
  }

  void _agregarNuevoRubro() {
    final itemController = TextEditingController();
    final nombreController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          title: const Text(
            'Agregar Nuevo Rubro',
            style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1B365D), fontSize: 16),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: itemController,
                decoration: const InputDecoration(
                  labelText: 'Ítem (ej: 03.00)',
                  hintText: 'Autogenerado si se deja vacío',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: nombreController,
                decoration: const InputDecoration(
                  labelText: 'Nombre del Rubro (ej: Mampostería)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B365D)),
              onPressed: () {
                if (nombreController.text.isNotEmpty) {
                  setState(() {
                    _listaRubros.add(
                      Rubro(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        item: itemController.text.isEmpty
                            ? '${(_listaRubros.length + 1).toString().padLeft(2, '0')}.00'
                            : itemController.text,
                        nombre: nombreController.text,
                        subitems: [],
                      ),
                    );
                  });
                  _notificarCambio();
                  Navigator.pop(dialogContext);
                }
              },
              child: const Text('Agregar', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _eliminarRubro(int rubroIndex) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Eliminar Rubro?'),
        content: Text('Se eliminará "${_listaRubros[rubroIndex].nombre}" con todos sus ítems asociados.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              setState(() {
                _listaRubros.removeAt(rubroIndex);
              });
              _notificarCambio();
              Navigator.pop(context);
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _abrirDialogoSubitem(int rubroIndex, {Subitem? subitemExistente, int? subitemIndex}) async {
    final resultado = await showDialog<Subitem>(
      context: context,
      builder: (context) => AgregarSubitemDialog(subitemExistente: subitemExistente),
    );

    if (resultado != null) {
      setState(() {
        final rubroActual = _listaRubros[rubroIndex];
        final nuevosSubitems = List<Subitem>.from(rubroActual.subitems);

        if (subitemIndex != null) {
          nuevosSubitems[subitemIndex] = resultado;
        } else {
          nuevosSubitems.add(resultado);
        }

        _listaRubros[rubroIndex] = rubroActual.copyWith(subitems: nuevosSubitems);
      });
      _notificarCambio();
    }
  }

  void _eliminarSubitem(int rubroIndex, int subitemIndex) {
    setState(() {
      final rubroActual = _listaRubros[rubroIndex];
      final nuevosSubitems = List<Subitem>.from(rubroActual.subitems);

      nuevosSubitems.removeAt(subitemIndex);
      _listaRubros[rubroIndex] = rubroActual.copyWith(subitems: nuevosSubitems);
    });
    _notificarCambio();
  }

  @override
  Widget build(BuildContext context) {
    final ObraModel? obra = widget.obra;

    return Scaffold(
      body: Column(
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

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF1B365D),
              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('SUBTOTAL CÓMPUTO DIRECTO', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(_fmt(_totalGeneralDirecto), style: const TextStyle(color: Colors.amber, fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${_listaRubros.length} Rubros • $_cantidadSubitemsTotales Ítems',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: _listaRubros.isEmpty
                ? const Center(
                    child: Text(
                      'No hay rubros agregados al presupuesto.\nUsá el botón inferior para agregar uno.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black54, fontSize: 13),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12.0),
                    itemCount: _listaRubros.length,
                    itemBuilder: (context, rubroIdx) {
                      final rubro = _listaRubros[rubroIdx];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12.0),
                        elevation: 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        child: ExpansionTile(
                          initiallyExpanded: true,
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${rubro.item} - ${rubro.nombre}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1B365D), fontSize: 14),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.black38),
                                onPressed: () => _eliminarRubro(rubroIdx),
                                tooltip: 'Eliminar Rubro',
                              ),
                            ],
                          ),
                          subtitle: Text(
                            'Subtotal Rubro: ${_fmt(rubro.totalRubro)}',
                            style: const TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.w600, fontSize: 12),
                          ),
                          children: [
                            const Divider(height: 1),
                            if (rubro.subitems.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(12.0),
                                child: Text('Sin ítems en este rubro. Hacé clic en "Agregar Ítem".', style: TextStyle(fontSize: 11, color: Colors.black38)),
                              )
                            else
                              ...rubro.subitems.asMap().entries.map((entry) {
                                final subIdx = entry.key;
                                final sub = entry.value;
                                return ListTile(
                                  dense: true,
                                  title: Text('${sub.codigo} - ${sub.descripcion}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                                  subtitle: Text(
                                    '${sub.cantidad} ${sub.unidad}  x  ${_fmt(sub.precioUnitario)}',
                                    style: const TextStyle(color: Colors.black54, fontSize: 11),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _fmt(sub.total),
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1B365D)),
                                      ),
                                      const SizedBox(width: 4),
                                      IconButton(
                                        icon: const Icon(Icons.edit, size: 18, color: Colors.blue),
                                        onPressed: () => _abrirDialogoSubitem(
                                          rubroIdx,
                                          subitemExistente: sub,
                                          subitemIndex: subIdx,
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                                        onPressed: () => _eliminarSubitem(rubroIdx, subIdx),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  icon: const Icon(Icons.add, size: 18),
                                  label: const Text('Agregar Ítem'),
                                  onPressed: () => _abrirDialogoSubitem(rubroIdx),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _agregarNuevoRubro,
        backgroundColor: const Color(0xFF1B365D),
        tooltip: 'Nuevo Rubro',
        child: const Icon(Icons.create_new_folder, color: Colors.white),
      ),
    );
  }
}