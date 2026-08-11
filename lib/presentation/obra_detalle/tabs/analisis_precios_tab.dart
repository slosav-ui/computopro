import 'package:flutter/material.dart';
import '../../../../models/obra_model.dart';
import '../../../../models/componente_apu.dart';
import '../../../../models/insumo_apu.dart';
import '../../../../models/insumo.dart';
import '../../../../models/rubro.dart';
import '../../../../models/subitem.dart';

class AnalisisPreciosTab extends StatefulWidget {
  final ObraModel obra;
  final List<Rubro>? rubros;

  const AnalisisPreciosTab({
    Key? key,
    required this.obra,
    this.rubros,
  }) : super(key: key);

  @override
  State<AnalisisPreciosTab> createState() => _AnalisisPreciosTabState();
}

class _AnalisisPreciosTabState extends State<AnalisisPreciosTab> {
  // Subítem seleccionado para analizar
  Subitem? _subitemSeleccionado;

  // Estructura APU editable
  late ComponenteApu _apuActual;

  @override
  void initState() {
    super.initState();
    _cargarApuPorDefecto();
  }

  void _cargarApuPorDefecto() {
    // Si hay rubros y subítems, se selecciona el primero por defecto
    if (widget.rubros != null && widget.rubros!.isNotEmpty) {
      for (var r in widget.rubros!) {
        if (r.subitems.isNotEmpty) {
          _subitemSeleccionado = r.subitems.first;
          break;
        }
      }
    }

    // Inicialización con la estructura base de análisis
    _apuActual = ComponenteApu(
      materiales: [
        InsumoApu(
          insumo: Insumo(id: 'm1', nombre: 'Cemento CPN40 (Bolsa 50kg)', unidad: 'bolsa', precio: 8500.0, tipo: 'material'),
          rendimiento: 7.0,
        ),
        InsumoApu(
          insumo: Insumo(id: 'm2', nombre: 'Arena Mediana', unidad: 'm³', precio: 18000.0, tipo: 'material'),
          rendimiento: 0.65,
        ),
        InsumoApu(
          insumo: Insumo(id: 'm3', nombre: 'Piedra Partida 6-20', unidad: 'm³', precio: 24000.0, tipo: 'material'),
          rendimiento: 0.85,
        ),
        InsumoApu(
          insumo: Insumo(id: 'm4', nombre: 'Acero A420 en Barras', unidad: 'kg', precio: 1450.0, tipo: 'material'),
          rendimiento: 95.0,
        ),
      ],
      manoDeObra: [
        InsumoApu(
          insumo: Insumo(id: 'mo1', nombre: 'Oficial Especializado', unidad: 'hs', precio: 4200.0, tipo: 'mano_obra'),
          rendimiento: 12.0,
        ),
        InsumoApu(
          insumo: Insumo(id: 'mo2', nombre: 'Ayudante', unidad: 'hs', precio: 3400.0, tipo: 'mano_obra'),
          rendimiento: 14.0,
        ),
      ],
      equipos: [
        InsumoApu(
          insumo: Insumo(id: 'e1', nombre: 'Hormigonera y Vibrador de Inmersión', unidad: 'hs', precio: 2500.0, tipo: 'equipo'),
          rendimiento: 3.5,
        ),
      ],
    );
  }

  String _fmt(double monto) {
    final valorInt = monto.round();
    final str = valorInt.toString();
    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    final formateado = str.replaceAllMapped(reg, (Match m) => '${m[1]}.');
    return '\$ $formateado';
  }

  void _agregarInsumo(String tipo) {
    final nombreCtrl = TextEditingController();
    final unidadCtrl = TextEditingController(text: tipo == 'mano_obra' || tipo == 'equipo' ? 'hs' : 'u');
    final rendimientoCtrl = TextEditingController();
    final precioCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Agregar Insumo a $tipo', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1B365D))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nombreCtrl, decoration: const InputDecoration(labelText: 'Descripción / Insumo')),
            TextField(controller: unidadCtrl, decoration: const InputDecoration(labelText: 'Unidad de Medida')),
            TextField(controller: rendimientoCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Rendimiento')),
            TextField(controller: precioCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Precio Unitario (\$)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B365D)),
            onPressed: () {
              if (nombreCtrl.text.isNotEmpty && rendimientoCtrl.text.isNotEmpty && precioCtrl.text.isNotEmpty) {
                final nuevoInsumo = InsumoApu(
                  insumo: Insumo(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    nombre: nombreCtrl.text,
                    unidad: unidadCtrl.text,
                    precio: double.tryParse(precioCtrl.text) ?? 0.0,
                    tipo: tipo,
                  ),
                  rendimiento: double.tryParse(rendimientoCtrl.text) ?? 0.0,
                );

                setState(() {
                  if (tipo == 'material') {
                    _apuActual.materiales.add(nuevoInsumo);
                  } else if (tipo == 'mano_obra') {
                    _apuActual.manoDeObra.add(nuevoInsumo);
                  } else {
                    _apuActual.equipos.add(nuevoInsumo);
                  }
                });
                Navigator.pop(dialogCtx);
              }
            },
            child: const Text('Guardar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _eliminarInsumo(List<InsumoApu> lista, int index) {
    setState(() {
      lista.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final rubrosDisponibles = widget.rubros ?? [];

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Selección del Subítem a Analizar
            if (rubrosDisponibles.isNotEmpty)
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<Subitem>(
                      isExpanded: true,
                      hint: const Text('Seleccionar Ítem a analizar'),
                      value: _subitemSeleccionado,
                      items: rubrosDisponibles.expand((r) => r.subitems).map((sub) {
                        return DropdownMenuItem<Subitem>(
                          value: sub,
                          child: Text('${sub.codigo} - ${sub.descripcion}', overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setState(() {
                          _subitemSeleccionado = val;
                        });
                      },
                    ),
                  ),
                ),
              ),

            // Cabecera del APU
            Card(
              color: const Color(0xFF1B365D),
              elevation: 3,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Análisis de Precio Unitario (APU)',
                      style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _subitemSeleccionado?.descripcion ?? 'Hormigón Armado para Columnas y Vigas',
                      style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Unidad: ${_subitemSeleccionado?.unidad ?? "m³"}',
                          style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        Text(
                          'Costo Directo Unitario: ${_fmt(_apuActual.costoDirectoTotal)}',
                          style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Tablas desglosadas por componente
            _buildSeccionApu('1. Materiales', _apuActual.materiales, _apuActual.totalMateriales, Colors.blue.shade800, 'material'),
            const SizedBox(height: 12),
            _buildSeccionApu('2. Mano de Obra', _apuActual.manoDeObra, _apuActual.totalManoDeObra, Colors.orange.shade800, 'mano_obra'),
            const SizedBox(height: 12),
            _buildSeccionApu('3. Equipos y Herramientas', _apuActual.equipos, _apuActual.totalEquipos, Colors.purple.shade800, 'equipo'),
          ],
        ),
      ),
    );
  }

  Widget _buildSeccionApu(String titulo, List<InsumoApu> lista, double subtotal, Color colorHeader, String tipoInsumo) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
            decoration: BoxDecoration(
              color: colorHeader.withOpacity(0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              border: Border(left: BorderSide(color: colorHeader, width: 4)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(titulo, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: colorHeader)),
                Row(
                  children: [
                    Text('Subtotal: ${_fmt(subtotal)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    IconButton(
                      icon: Icon(Icons.add_circle, color: colorHeader, size: 20),
                      tooltip: 'Agregar Insumo',
                      onPressed: () => _agregarInsumo(tipoInsumo),
                    ),
                  ],
                ),
              ],
            ),
          ),
          lista.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(12.0),
                  child: Text('Sin insumos asignados en esta categoría.', style: TextStyle(fontSize: 11, color: Colors.black38)),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: lista.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = lista[index];
                    return ListTile(
                      dense: true,
                      title: Text(item.insumo.nombre, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                      subtitle: Text(
                        'Rendimiento: ${item.rendimiento} ${item.insumo.unidad}  x  ${_fmt(item.insumo.precio)}',
                        style: const TextStyle(fontSize: 11, color: Colors.black54),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_fmt(item.costoParcial), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                            onPressed: () => _eliminarInsumo(lista, index),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ],
      ),
    );
  }
}