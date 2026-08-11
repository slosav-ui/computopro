import 'package:flutter/material.dart';

class Operario {
  final String id;
  final String nombre;
  final String categoria; // ej: Oficial Especializado, Oficial, Ayudante
  final double valorHora;
  double horasTrabajadas;

  Operario({
    required this.id,
    required this.nombre,
    required this.categoria,
    required this.valorHora,
    this.horasTrabajadas = 0.0,
  });

  double get costoTotal => valorHora * horasTrabajadas;
}

class ManoObraTab extends StatefulWidget {
  final int obraId;

  const ManoObraTab({super.key, required this.obraId});

  @override
  State<ManoObraTab> createState() => _ManoObraTabState();
}

class _ManoObraTabState extends State<ManoObraTab> {
  final List<Operario> _personal = [
    Operario(id: 'op1', nombre: 'Carlos Gómez', categoria: 'Oficial Especializado', valorHora: 4200.0, horasTrabajadas: 160),
    Operario(id: 'op2', nombre: 'Juan Pérez', categoria: 'Oficial Armador', valorHora: 3800.0, horasTrabajadas: 160),
    Operario(id: 'op3', nombre: 'Lucas Rodríguez', categoria: 'Ayudante', valorHora: 3400.0, horasTrabajadas: 140),
  ];

  String _fmt(double monto) {
    final valorInt = monto.round();
    final str = valorInt.toString();
    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    final formateado = str.replaceAllMapped(reg, (Match m) => '${m[1]}.');
    return '\$ $formateado';
  }

  double get _totalManoObra => _personal.fold(0.0, (sum, op) => sum + op.costoTotal);
  double get _totalHoras => _personal.fold(0.0, (sum, op) => sum + op.horasTrabajadas);

  void _agregarOperarioModal() {
    final nombreCtrl = TextEditingController();
    final valorHoraCtrl = TextEditingController();
    String categoriaSel = 'Oficial';

    final categorias = ['Oficial Especializado', 'Oficial', 'Medio Oficial', 'Ayudante'];

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: const Text('Registrar Nuevo Operario', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1B365D))),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nombreCtrl,
                decoration: const InputDecoration(labelText: 'Nombre y Apellido'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: categoriaSel,
                decoration: const InputDecoration(labelText: 'Categoría'),
                items: categorias.map((cat) => DropdownMenuItem(value: cat, child: Text(cat))).toList(),
                onChanged: (val) {
                  if (val != null) setModalState(() => categoriaSel = val);
                },
              ),
              TextField(
                controller: valorHoraCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Valor Hora (\$)'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B365D)),
              onPressed: () {
                if (nombreCtrl.text.isNotEmpty && valorHoraCtrl.text.isNotEmpty) {
                  setState(() {
                    _personal.add(Operario(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      nombre: nombreCtrl.text,
                      categoria: categoriaSel,
                      valorHora: double.tryParse(valorHoraCtrl.text) ?? 0.0,
                    ));
                  });
                  Navigator.pop(dialogCtx);
                }
              },
              child: const Text('Guardar', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _editarHorasModal(Operario operario) {
    final horasCtrl = TextEditingController(text: operario.horasTrabajadas.toString());

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Cargar Horas - ${operario.nombre}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1B365D))),
        content: TextField(
          controller: horasCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Horas Acumuladas'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B365D)),
            onPressed: () {
              setState(() {
                operario.horasTrabajadas = double.tryParse(horasCtrl.text) ?? operario.horasTrabajadas;
              });
              Navigator.pop(dialogCtx);
            },
            child: const Text('Actualizar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // TARJETA DE RESUMEN
            Card(
              color: const Color(0xFF1B365D),
              elevation: 3,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'CONTROL DE MANO DE OBRA',
                      style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Total Liquidación: ${_fmt(_totalManoObra)}',
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Operarios: ${_personal.length}', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13)),
                        Text('Total Horas: ${_totalHoras.toStringAsFixed(1)} hs', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // CABECERA LISTA Y BOTÓN AGREGAR
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Nómina de Personal',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1B365D)),
                ),
                ElevatedButton.icon(
                  onPressed: _agregarOperarioModal,
                  icon: const Icon(Icons.person_add, size: 16, color: Colors.white),
                  label: const Text('Nuevo Operario', style: TextStyle(color: Colors.white, fontSize: 12)),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B365D)),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // LISTADO DE OPERARIOS
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _personal.length,
              itemBuilder: (context, index) {
                final op = _personal[index];
                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.only(bottom: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFF1B365D).withOpacity(0.1),
                      child: const Icon(Icons.engineering, color: Color(0xFF1B365D)),
                    ),
                    title: Text(op.nombre, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${op.categoria} | ${_fmt(op.valorHora)}/hs', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                        Text('Horas cargadas: ${op.horasTrabajadas} hs', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(_fmt(op.costoTotal), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1B365D))),
                          ],
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.access_time, color: Colors.orange, size: 20),
                          tooltip: 'Cargar Horas',
                          onPressed: () => _editarHorasModal(op),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                          onPressed: () {
                            setState(() {
                              _personal.removeAt(index);
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}