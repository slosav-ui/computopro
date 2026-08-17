import 'package:flutter/material.dart';

class Proveedor {
  final String id;
  final String nombre;
  final String rubro; // ej: Corralón, Electricidad, Sanitaria, Alquiler de Equipos
  final String telefono;
  final String direccion;
  final List<String> insumosPrincipales;

  Proveedor({
    required this.id,
    required this.nombre,
    required this.rubro,
    required this.telefono,
    required this.direccion,
    required this.insumosPrincipales,
  });
}

class ProveedoresTab extends StatefulWidget {
  final String obraId;

  const ProveedoresTab({super.key, required this.obraId});

  @override
  State<ProveedoresTab> createState() => _ProveedoresTabState();
}

class _ProveedoresTabState extends State<ProveedoresTab> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _filtroTexto = '';

  final List<Proveedor> _proveedores = [
    Proveedor(
      id: 'p1',
      nombre: 'Corralón El Valle',
      rubro: 'Materiales Gruesos',
      telefono: '0299-4481234',
      direccion: 'Ruta 22 Km 1200',
      insumosPrincipales: ['Cemento', 'Arena gruesa', 'Hierro ø12', 'Ladrillo del 18'],
    ),
    Proveedor(
      id: 'p2',
      nombre: 'Electrostock S.A.',
      rubro: 'Electricidad e Iluminación',
      telefono: '0299-4428899',
      direccion: 'Av. Argentina 450',
      insumosPrincipales: ['Cable 2.5 mm2', 'Térmica 20A', 'Caño corrugado 3/4'],
    ),
    Proveedor(
      id: 'p3',
      nombre: 'Sanitarios Neuquén',
      rubro: 'Sanitaria y Gas',
      telefono: '0299-4431122',
      direccion: 'Perticone 890',
      insumosPrincipales: ['Caño PVC ø110', 'Caño Termofusión ø25', 'Llave de paso 3/4'],
    ),
  ];

  List<Proveedor> get _proveedoresFiltrados {
    if (_filtroTexto.isEmpty) return _proveedores;
    return _proveedores.where((p) {
      final query = _filtroTexto.toLowerCase();
      final nom = p.nombre.toLowerCase();
      final rub = p.rubro.toLowerCase();
      final ins = p.insumosPrincipales.join(' ').toLowerCase();
      return nom.contains(query) || rub.contains(query) || ins.contains(query);
    }).toList();
  }

  void _agregarProveedorModal() {
    final nombreCtrl = TextEditingController();
    final rubroCtrl = TextEditingController();
    final telCtrl = TextEditingController();
    final dirCtrl = TextEditingController();
    final insumosCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text(
          'Registrar Nuevo Proveedor',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1B365D)),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nombreCtrl,
                decoration: const InputDecoration(labelText: 'Nombre o Razón Social'),
              ),
              TextField(
                controller: rubroCtrl,
                decoration: const InputDecoration(labelText: 'Rubro (ej: Corralón, Sanitaria)'),
              ),
              TextField(
                controller: telCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Teléfono de Contacto'),
              ),
              TextField(
                controller: dirCtrl,
                decoration: const InputDecoration(labelText: 'Dirección / Depósito'),
              ),
              TextField(
                controller: insumosCtrl,
                decoration: const InputDecoration(
                  labelText: 'Insumos (separados por coma)',
                  hintText: 'ej: Cemento, Cal, Arena',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B365D)),
            onPressed: () {
              if (nombreCtrl.text.isNotEmpty) {
                final insumosList = insumosCtrl.text
                    .split(',')
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList();

                setState(() {
                  _proveedores.add(Proveedor(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    nombre: nombreCtrl.text,
                    rubro: rubroCtrl.text.isEmpty ? 'General' : rubroCtrl.text,
                    telefono: telCtrl.text,
                    direccion: dirCtrl.text,
                    insumosPrincipales: insumosList,
                  ));
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // PANEL BUSCADOR Y RESUMEN
            Card(
              color: const Color(0xFF1B365D),
              elevation: 3,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'DIRECTORIO DE PROVEEDORES',
                          style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          'Registrados: ${_proveedores.length}',
                          style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _searchCtrl,
                      onChanged: (val) => setState(() => _filtroTexto = val),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Buscar por nombre, rubro o material...',
                        hintStyle: const TextStyle(color: Colors.white54, fontSize: 13),
                        prefixIcon: const Icon(Icons.search, color: Colors.amber, size: 20),
                        suffixIcon: _filtroTexto.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, color: Colors.white54, size: 18),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() => _filtroTexto = '');
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.12),
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // CABECERA
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Listado de Proveedores',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1B365D)),
                ),
                ElevatedButton.icon(
                  onPressed: _agregarProveedorModal,
                  icon: const Icon(Icons.add_business, size: 16, color: Colors.white),
                  label: const Text('Nuevo Proveedor', style: TextStyle(color: Colors.white, fontSize: 12)),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B365D)),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // LISTA DE PROVEEDORES
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _proveedoresFiltrados.length,
              itemBuilder: (context, index) {
                final prov = _proveedoresFiltrados[index];
                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  child: Padding(
                    padding: const EdgeInsets.all(14.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              prov.nombre,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1B365D)),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1B365D).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                prov.rubro,
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1B365D)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.phone_outlined, size: 14, color: Colors.black54),
                            const SizedBox(width: 4),
                            Text(prov.telefono.isEmpty ? 'Sin teléfono' : prov.telefono, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                            const SizedBox(width: 16),
                            const Icon(Icons.location_on_outlined, size: 14, color: Colors.black54),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                prov.direccion.isEmpty ? 'Sin dirección' : prov.direccion,
                                style: const TextStyle(fontSize: 12, color: Colors.black54),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        if (prov.insumosPrincipales.isNotEmpty) ...[
                          const Divider(height: 16),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: prov.insumosPrincipales.map((insumo) {
                              return Chip(
                                label: Text(insumo, style: const TextStyle(fontSize: 10, color: Colors.black54)),
                                backgroundColor: Colors.grey.shade200,
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                              );
                            }).toList(),
                          ),
                        ],
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