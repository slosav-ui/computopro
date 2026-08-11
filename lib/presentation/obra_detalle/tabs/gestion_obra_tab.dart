import 'package:flutter/material.dart';

class GestionObraTab extends StatefulWidget {
  final String obraId;

  const GestionObraTab({Key? key, required this.obraId}) : super(key: key);

  @override
  State<GestionObraTab> createState() => _GestionObraTabState();
}

class _GestionObraTabState extends State<GestionObraTab> {
  int _diasPlazoPago = 10;
  String _rolActual = 'Profesional / Empresa';

  final List<Map<String, dynamic>> _certificados = [
    {
      'numero': 1,
      'periodo': 'Julio 2026',
      'monto': 1250000.00,
      'estado': 'Borrador',
      'diasPactados': 10,
      'fechaEmision': '01/08/2026',
      'leido': false,
      'pagado': false,
      'pdfFirmadoSubido': false,
    },
  ];

  String _fmt(double monto) {
    final valorInt = monto.round();
    final str = valorInt.toString();
    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    final formateado = str.replaceAllMapped(reg, (Match m) => '${m[1]}.');
    return '\$ $formateado';
  }

  void _cambiarEstado(int index, String nuevoEstado) {
    setState(() {
      _certificados[index]['estado'] = nuevoEstado;
      if (nuevoEstado == 'Pagado') {
        _certificados[index]['pagado'] = true;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Estado actualizado: $nuevoEstado'),
        backgroundColor: const Color(0xFF1B365D),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _agregarCertificadoModal() {
    final periodoCtrl = TextEditingController();
    final montoCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Nuevo Certificado de Obra', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1B365D))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: periodoCtrl,
              decoration: const InputDecoration(labelText: 'Período (ej: Agosto 2026)', hintText: 'Mes Año'),
            ),
            TextField(
              controller: montoCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Monto a Certificar (\$)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B365D)),
            onPressed: () {
              if (periodoCtrl.text.isNotEmpty && montoCtrl.text.isNotEmpty) {
                final nuevoNumero = _certificados.length + 1;
                final nuevoMonto = double.tryParse(montoCtrl.text) ?? 0.0;

                setState(() {
                  _certificados.add({
                    'numero': nuevoNumero,
                    'periodo': periodoCtrl.text,
                    'monto': nuevoMonto,
                    'estado': 'Borrador',
                    'diasPactados': _diasPlazoPago,
                    'fechaEmision': '${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
                    'leido': false,
                    'pagado': false,
                    'pdfFirmadoSubido': false,
                  });
                });
                Navigator.pop(dialogCtx);
              }
            },
            child: const Text('Crear Certificado', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Color _getColorEstado(String estado) {
    switch (estado) {
      case 'Borrador':
        return Colors.orange.shade700;
      case 'Emitido (Esperando Pago)':
        return Colors.blue.shade700;
      case 'Pagado':
        return Colors.green.shade700;
      default:
        return Colors.grey.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // PANEL SUPERIOR DE ROL Y CONFIGURACIÓN
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
                      const Flexible(
                        child: Text(
                          'GESTIÓN Y CERTIFICACIÓN',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DropdownButton<String>(
                        dropdownColor: const Color(0xFF1B365D),
                        underline: const SizedBox(),
                        value: _rolActual,
                        style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13),
                        items: const [
                          DropdownMenuItem(value: 'Profesional / Empresa', child: Text('Rol: Profesional / Empresa')),
                          DropdownMenuItem(value: 'Propietario / Cliente', child: Text('Rol: Propietario / Cliente')),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _rolActual = val);
                        },
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white30, height: 16),
                  Row(
                    children: [
                      const Icon(Icons.timer_outlined, color: Colors.amber, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Plazo de Pago Pactado: $_diasPlazoPago días hábiles',
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  )
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // CABECERA HISTORIAL
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Historial de Certificados',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1B365D)),
              ),
              if (_rolActual == 'Profesional / Empresa')
                ElevatedButton.icon(
                  onPressed: _agregarCertificadoModal,
                  icon: const Icon(Icons.add, size: 16, color: Colors.white),
                  label: const Text('Nuevo Certificado', style: TextStyle(color: Colors.white, fontSize: 12)),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B365D)),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // LISTADO DE CERTIFICADOS
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _certificados.length,
            itemBuilder: (context, index) {
              final cert = _certificados[index];
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
                            'Certificado Nº 0${cert['numero']} - ${cert['periodo']}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1B365D)),
                          ),
                          Chip(
                            label: Text(
                              cert['estado'],
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                            backgroundColor: _getColorEstado(cert['estado']),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Monto Certificado: ${_fmt(cert['monto'])}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black54),
                      ),
                      Text(
                        'Emisión: ${cert['fechaEmision']} | Plazo: ${cert['diasPactados']} días',
                        style: const TextStyle(fontSize: 11, color: Colors.black45),
                      ),
                      const Divider(height: 16),
                      
                      // ACCIONES SEGÚN EL ROL
                      if (_rolActual == 'Profesional / Empresa') ...[
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            if (cert['estado'] == 'Borrador')
                              ElevatedButton.icon(
                                onPressed: () => _cambiarEstado(index, 'Emitido (Esperando Pago)'),
                                icon: const Icon(Icons.send, size: 14, color: Colors.white),
                                label: const Text('Aprobar y Emitir', style: TextStyle(color: Colors.white, fontSize: 12)),
                                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B365D)),
                              ),
                            OutlinedButton.icon(
                              onPressed: () {
                                setState(() {
                                  cert['pdfFirmadoSubido'] = true;
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Documento PDF adjuntado correctamente.')),
                                );
                              },
                              icon: Icon(
                                cert['pdfFirmadoSubido'] ? Icons.check_circle : Icons.upload_file,
                                size: 14,
                                color: cert['pdfFirmadoSubido'] ? Colors.green : const Color(0xFF1B365D),
                              ),
                              label: Text(
                                cert['pdfFirmadoSubido'] ? 'PDF Subido' : 'Subir PDF Firmado',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        // Vista Propietario / Cliente
                        Wrap(
                          spacing: 8,
                          children: [
                            if (cert['estado'] == 'Emitido (Esperando Pago)')
                              ElevatedButton.icon(
                                onPressed: () => _cambiarEstado(index, 'Pagado'),
                                icon: const Icon(Icons.payment, size: 14, color: Colors.white),
                                label: const Text('Registrar Pago', style: TextStyle(color: Colors.white, fontSize: 12)),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700),
                              ),
                          ],
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
    );
  }
}