import 'package:flutter/material.dart';
import '../obra_detalle/screens/presupuestos_screen.dart';

class ObrasListScreen extends StatefulWidget {
  const ObrasListScreen({super.key});

  @override
  State<ObrasListScreen> createState() => _ObrasListScreenState();
}

class _ObrasListScreenState extends State<ObrasListScreen> {
  // --- Estado de Suscripción ---
  bool _esPlanPro = false;

  // --- Cotización Dólar BNA & Proyección ---
  final double _dolarBnaCompra = 1340.0;
  final double _dolarBnaVenta = 1390.0;
  final String _fechaActualizacionDolar = 'Agosto 2026 (BNA)';
  double get _dolarOficialPromedio => (_dolarBnaCompra + _dolarBnaVenta) / 2;
  late double _cotizacionUsdEfectiva;

  // --- Indicadores CAC ---
  final double _variacionCacUltimoMes = 3.8;
  final String _ultimoMesPublicadoCac = 'Julio 2026';

  @override
  void initState() {
    super.initState();
    _cotizacionUsdEfectiva = _dolarOficialPromedio;
  }

  // --- Lista Unificada de Obras ---
  final List<Map<String, dynamic>> _obras = [
    {
      'id': 'obra_001',
      'nombre': 'Casa Unifamiliar Las Lomas',
      'propietario': 'Arq. Roberto Gómez',
      'ubicacion': 'San Carlos de Bariloche, B° Belgrano',
      'superficieM2': 185.0,
      'tipoObra': 'Residencial',
      'estado': 'Cotización',
      'moneda': 'ARS',
      'aplicaCac': true,
      'montoEstimadoArs': 185000000.0,
      'montoEstimadoUsd': 135500.0,
      'mesBaseCac': 'Julio 2026',
      'revision': 'Rev. 03',
      'ultimaModif': '08/Ago/2026',
      'tipoRol': 'Director de Obra',
      'estadoServicioEspecial': 'Ninguno',
    },
    {
      'id': 'obra_002',
      'nombre': 'Refacción y Ampliación Cabaña',
      'propietario': 'Inversiones del Sur S.A.',
      'ubicacion': 'Bariloche, Av. Bustillo Km 8',
      'superficieM2': 75.0,
      'tipoObra': 'Comercial/Residencial',
      'estado': 'En Ejecución',
      'moneda': 'USD',
      'aplicaCac': false,
      'montoEstimadoArs': 88725000.0,
      'montoEstimadoUsd': 65000.0,
      'mesBaseCac': 'N/A',
      'revision': 'Rev. 01',
      'ultimaModif': '02/Ago/2026',
      'tipoRol': 'Propietario / Cliente',
      'estadoServicioEspecial': 'Ninguno',
    },
  ];

  // --- Formateador de Montos ---
  String _formatearMonto(double monto, String moneda) {
    final valorInt = monto.round();
    final str = valorInt.toString();
    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    final formateado = str.replaceAllMapped(reg, (Match m) => '${m[1]}.');
    return moneda == 'USD' ? 'USD $formateado' : '\$ $formateado';
  }

  // --- Navegación a la Solapa de Presupuesto ---
  void _abrirPresupuesto(Map<String, dynamic> obra) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PresupuestosScreen(obra: obra),
      ),
    );
  }

  // --- Diálogo: Mapa de Obras Registradas ---
  void _mostrarMapaObras() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.map_outlined, color: Color(0xFF1B365D)),
            SizedBox(width: 8),
            Text('Mapa de Obras Registradas', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 180,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.blueGrey[100],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blueGrey[300]!),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(Icons.map, size: 100, color: Colors.blueGrey[300]),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B365D).withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.location_on, color: Colors.redAccent, size: 16),
                          SizedBox(width: 4),
                          Text('Vista Satelital / Ubicaciones', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text('Ubicaciones georreferenciadas en legajo:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _obras.length,
                  itemBuilder: (context, index) {
                    final item = _obras[index];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.place, color: Color(0xFF1B365D), size: 18),
                      title: Text(item['nombre'], style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      subtitle: Text(item['ubicacion'], style: const TextStyle(fontSize: 10, color: Colors.black54)),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B365D)),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // --- Diálogo: Alta de Nueva Obra ---
  void _mostrarModalNuevaObra() {
    final nombreCtrl = TextEditingController();
    final propietarioCtrl = TextEditingController();
    final ubicacionCtrl = TextEditingController();
    final superficieCtrl = TextEditingController();
    String tipoSeleccionado = 'Residencial';
    String monedaSeleccionada = 'ARS';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: const Row(
              children: [
                Icon(Icons.add_business_outlined, color: Color(0xFF1B365D)),
                SizedBox(width: 8),
                Text('Alta de Nueva Obra', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amber[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber[700]!),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.gavel_outlined, size: 18, color: Colors.amber[900]),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Los datos ingresados en este formulario (Nombre de Obra, Propietario, Ubicación, Superficie) se consolidarán de manera definitiva en las carátulas, encabezados y legajos exportables en PDF.',
                            style: TextStyle(fontSize: 10, color: Colors.amber[900], height: 1.3, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: nombreCtrl,
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(labelText: 'Nombre de la Obra / Proyecto', border: OutlineInputBorder(), isDense: true),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: propietarioCtrl,
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(labelText: 'Propietario / Comitente', border: OutlineInputBorder(), isDense: true),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: ubicacionCtrl,
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(labelText: 'Ubicación / Localidad', border: OutlineInputBorder(), isDense: true),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: superficieCtrl,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(fontSize: 12),
                          decoration: const InputDecoration(labelText: 'Superficie (m²)', border: OutlineInputBorder(), isDense: true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: tipoSeleccionado,
                          decoration: const InputDecoration(labelText: 'Tipo', border: OutlineInputBorder(), isDense: true),
                          style: const TextStyle(fontSize: 11, color: Colors.black87),
                          items: ['Residencial', 'Comercial/Residencial', 'Industrial', 'Infraestructura']
                              .map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 11))))
                              .toList(),
                          onChanged: (val) {
                            if (val != null) setModalState(() => tipoSeleccionado = val);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Text('Moneda Base:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 12),
                      ChoiceChip(
                        label: const Text('ARS (\$)', style: TextStyle(fontSize: 11)),
                        selected: monedaSeleccionada == 'ARS',
                        onSelected: (sel) {
                          if (sel) setModalState(() => monedaSeleccionada = 'ARS');
                        },
                      ),
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: const Text('USD', style: TextStyle(fontSize: 11)),
                        selected: monedaSeleccionada == 'USD',
                        onSelected: (sel) {
                          if (sel) setModalState(() => monedaSeleccionada = 'USD');
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B365D)),
                onPressed: () {
                  if (nombreCtrl.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Por favor ingrese el nombre de la obra.')),
                    );
                    return;
                  }
                  final double sup = double.tryParse(superficieCtrl.text) ?? 100.0;
                  setState(() {
                    _obras.add({
                      'id': 'obra_${DateTime.now().millisecondsSinceEpoch}',
                      'nombre': nombreCtrl.text.trim(),
                      'propietario': propietarioCtrl.text.trim().isEmpty ? 'Sin Especificar' : propietarioCtrl.text.trim(),
                      'ubicacion': ubicacionCtrl.text.trim().isEmpty ? 'Ubicación Faltante' : ubicacionCtrl.text.trim(),
                      'superficieM2': sup,
                      'tipoObra': tipoSeleccionado,
                      'estado': 'Cotización',
                      'moneda': monedaSeleccionada,
                      'aplicaCac': monedaSeleccionada == 'ARS',
                      'montoEstimadoArs': monedaSeleccionada == 'ARS' ? sup * 1000000.0 : (sup * 750.0) * _cotizacionUsdEfectiva,
                      'montoEstimadoUsd': monedaSeleccionada == 'USD' ? sup * 750.0 : (sup * 1000000.0) / _cotizacionUsdEfectiva,
                      'mesBaseCac': 'Agosto 2026',
                      'revision': 'Rev. 00',
                      'ultimaModif': 'Hoy',
                      'tipoRol': 'Director de Obra',
                      'estadoServicioEspecial': 'Ninguno',
                    });
                  });
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Nueva obra registrada exitosamente.')),
                  );
                },
                child: const Text('Crear Obra', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  // --- Diálogo: Ajuste Económico & Moneda ---
  void _configurarAjusteEconomico(Map<String, dynamic> obra) {
    String monedaSeleccionada = obra['moneda'];
    bool aplicaCac = obra['aplicaCac'] ?? false;
    final TextEditingController cotizacionCtrl = TextEditingController(
      text: _cotizacionUsdEfectiva.toStringAsFixed(0),
    );

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final bool esPersonalizada = _cotizacionUsdEfectiva != _dolarOficialPromedio;

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: const Row(
              children: [
                Icon(Icons.payments_outlined, color: Color(0xFF1B365D)),
                SizedBox(width: 8),
                Text('Ajuste Económico & Moneda', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Obra: ${obra['nombre']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blueGrey[200]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Dólar Ref. Banco Nación (BNA):', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1B365D))),
                            if (_esPlanPro)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: Colors.amber[700], borderRadius: BorderRadius.circular(4)),
                                child: const Text('PRO', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Promedio Oficial (\$${_dolarBnaCompra.toStringAsFixed(0)} / \$${_dolarBnaVenta.toStringAsFixed(0)}): \$${_dolarOficialPromedio.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 10, color: Colors.black87),
                        ),
                        Text(
                          'Fuente: Banco Nación Argentina • Fecha: $_fechaActualizacionDolar',
                          style: const TextStyle(fontSize: 9, color: Colors.black54, fontStyle: FontStyle.italic),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Valor Activo: \$ ${_cotizacionUsdEfectiva.toStringAsFixed(2)} ${esPersonalizada ? "(Proyección Personalizada)" : "(Promedio Oficial BNA)"}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: esPersonalizada ? Colors.orange[900] : const Color(0xFF2E7D32),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_esPlanPro) ...[
                    const Text('Ingresar Proyección / Dólar Libre (PRO):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 40,
                            child: TextField(
                              controller: cotizacionCtrl,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                              decoration: InputDecoration(
                                prefixText: '\$ ',
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1B365D),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                          ),
                          onPressed: () {
                            final nuevoValor = double.tryParse(cotizacionCtrl.text);
                            if (nuevoValor != null && nuevoValor > 0) {
                              setState(() => _cotizacionUsdEfectiva = nuevoValor);
                              setDialogState(() {});
                            }
                          },
                          child: const Text('Aplicar', style: TextStyle(color: Colors.white, fontSize: 11)),
                        ),
                      ],
                    ),
                    if (esPersonalizada)
                      TextButton(
                        onPressed: () {
                          setState(() => _cotizacionUsdEfectiva = _dolarOficialPromedio);
                          cotizacionCtrl.text = _dolarOficialPromedio.toStringAsFixed(0);
                          setDialogState(() {});
                        },
                        child: const Text('Restablecer a Promedio BNA', style: TextStyle(fontSize: 10, color: Colors.blue)),
                      ),
                  ] else ...[
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.amber[50], borderRadius: BorderRadius.circular(6)),
                      child: const Row(
                        children: [
                          Icon(Icons.lock_outline, size: 16, color: Colors.amber),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'En versión FREE se utiliza el dólar promedio Banco Nación. La proyección / cotización personalizada requiere versión PRO.',
                              style: TextStyle(fontSize: 10, color: Colors.black87),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const Divider(),
                  const Text('Moneda Base de Cotización:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment<String>(
                        value: 'ARS',
                        label: Text('Pesos (\$)'),
                      ),
                      ButtonSegment<String>(
                        value: 'USD',
                        label: Text('Dólares (USD)'),
                      ),
                    ],
                    selected: {monedaSeleccionada},
                    onSelectionChanged: (Set<String> newSelection) {
                      setDialogState(() {
                        monedaSeleccionada = newSelection.first;
                        if (monedaSeleccionada == 'USD') {
                          aplicaCac = false;
                        }
                      });
                    },
                  ),
                  if (monedaSeleccionada == 'ARS') ...[
                    const SizedBox(height: 10),
                    SwitchListTile(
                      title: const Text('Ajuste por Índice CAC', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        'Actualización mensual constante.\nÚltimo publicado ($_ultimoMesPublicadoCac): +$_variacionCacUltimoMes%',
                        style: const TextStyle(fontSize: 10, color: Colors.black54),
                      ),
                      value: aplicaCac,
                      activeTrackColor: const Color(0xFF1B365D),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (val) {
                        setDialogState(() => aplicaCac = val);
                      },
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B365D)),
                onPressed: () {
                  setState(() {
                    obra['moneda'] = monedaSeleccionada;
                    obra['aplicaCac'] = (monedaSeleccionada == 'ARS') ? aplicaCac : false;
                  });
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Configuración económica guardada.')),
                  );
                },
                child: const Text('Guardar', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  // --- Modal: Suscripción Plan PRO ---
  void _mostrarModalPro() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFF1B365D).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.workspace_premium, color: Color(0xFF1B365D), size: 28),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Suscripción Profesional', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1B365D))),
                    Text('Gestión técnica y financiera avanzada', style: TextStyle(fontSize: 12, color: Colors.black54)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(),
            _buildProItem(Icons.attach_money, 'Proyección y Personalización de Cotización USD'),
            _buildProItem(Icons.trending_up, 'Redeterminación de Precios y Certificación por Índice CAC'),
            _buildProItem(Icons.eco_outlined, 'Cálculos Envolvente Edilicia K, G y Q (bajo Normas IRAM)'),
            _buildProItem(Icons.picture_as_pdf_outlined, 'Exportación de Legajos limpios sin marca de agua'),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1B365D),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  setState(() => _esPlanPro = !_esPlanPro);
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(_esPlanPro ? 'Suscripción PRO Activada.' : 'Modo FREE Activado.')),
                  );
                },
                child: Text(
                  _esPlanPro ? 'DESACTIVAR PLAN PRO' : 'ACTIVAR CUENTA PRO',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF1B365D)),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  // --- Diálogo: Servicios Técnicos Especiales ---
  void _abrirModalServiciosEspeciales(Map<String, dynamic> obra) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(
          children: [
            Icon(Icons.assignment_outlined, color: Color(0xFF1B365D)),
            SizedBox(width: 8),
            Text('Servicios Especiales', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Obra: ${obra['nombre']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 12),
            const Text('Solicitar presupuesto para elaboración técnica de:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87)),
            const SizedBox(height: 8),
            _buildCheckOption('Cómputo Métrico y Listado de Materiales'),
            _buildCheckOption('Presupuesto Operativo y Cálculo Polinómico / CAC'),
            _buildCheckOption('Acondicionamiento Térmico (Normas IRAM)'),
            _buildCheckOption('Legajo de Detalles Constructivos'),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 40)),
              icon: const Icon(Icons.upload_file, size: 18),
              label: const Text('Adjuntar Planos / Anteproyecto (PDF/DWG)', style: TextStyle(fontSize: 12)),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Selección de archivos habilitada.')),
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B365D)),
            onPressed: () {
              setState(() {
                obra['estadoServicioEspecial'] = 'En Revision';
              });
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Solicitud enviada a revisión. Nos contactaremos a la brevedad.')),
              );
            },
            child: const Text('Solicitar Cotización', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckOption(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          const Icon(Icons.check_box_outline_blank, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 11))),
        ],
      ),
    );
  }

  // --- Diálogo: Confirmar Eliminación ---
  void _confirmarEliminar(Map<String, dynamic> obra) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Obra'),
        content: Text('¿Desea borrar definitivamente "${obra['nombre']}"? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700]),
            onPressed: () {
              setState(() => _obras.removeWhere((i) => i['id'] == obra['id']));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Obra eliminada del registro.')),
              );
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B365D),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'MIS OBRAS',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2, fontSize: 18, color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.map_outlined, color: Colors.white),
            tooltip: 'Ver Obras en Mapa',
            onPressed: _mostrarMapaObras,
          ),
          InkWell(
            onTap: _mostrarModalPro,
            child: Container(
              margin: const EdgeInsets.only(right: 12, top: 12, bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _esPlanPro ? Colors.amber[700] : const Color(0xFF3A5A80),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber, width: 1),
              ),
              child: Row(
                children: [
                  Icon(Icons.workspace_premium, color: _esPlanPro ? Colors.white : Colors.amber, size: 14),
                  const SizedBox(width: 4),
                  Text(_esPlanPro ? 'PRO' : 'FREE', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Banner Informativo de Indicadores Económicos
          Container(
            width: double.infinity,
            color: const Color(0xFF1B365D),
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12, top: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'USD Ref. BNA: \$${_cotizacionUsdEfectiva.toStringAsFixed(2)}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'CAC Último Mes: +$_variacionCacUltimoMes%',
                        style: const TextStyle(color: Colors.white70, fontSize: 10),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Icon(Icons.refresh, color: Colors.white70, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        _fechaActualizacionDolar,
                        style: const TextStyle(color: Colors.white70, fontSize: 10),
                      ),
                    ],
                  )
                ],
              ),
            ),
          ),

          // Lista de Tarjetas de Obra
          Expanded(
            child: _obras.isEmpty
                ? const Center(child: Text('No hay obras registradas. Presione "+" para agregar una.'))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _obras.length,
                    itemBuilder: (context, index) {
                      final obra = _obras[index];
                      final bool esCotizacion = obra['estado'] == 'Cotización';
                      final bool esArs = obra['moneda'] == 'ARS';
                      final double monto = esArs ? obra['montoEstimadoArs'] : obra['montoEstimadoUsd'];
                      final bool tieneCac = obra['aplicaCac'] ?? false;
                      final String estadoServicio = obra['estadoServicioEspecial'] ?? 'Ninguno';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                        child: InkWell(
                          onTap: () => _abrirPresupuesto(obra),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Cabecera: Nombre + Estado
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        obra['nombre'],
                                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1B365D)),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: esCotizacion ? Colors.blue[50] : Colors.green[50],
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        obra['estado'],
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: esCotizacion ? Colors.blue[800] : Colors.green[800],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),

                                // Propietario / Ubicación
                                Row(
                                  children: [
                                    const Icon(Icons.person_outline, size: 13, color: Colors.black45),
                                    const SizedBox(width: 4),
                                    Text(obra['propietario'], style: const TextStyle(fontSize: 11, color: Colors.black54)),
                                    const SizedBox(width: 10),
                                    const Icon(Icons.location_on_outlined, size: 13, color: Colors.black45),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        obra['ubicacion'],
                                        style: const TextStyle(fontSize: 11, color: Colors.black54),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),

                                // Fila Central: Monto Base + Chips (m² / CAC)
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('Monto Estimado Base', style: TextStyle(fontSize: 9, color: Colors.black45, fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 2),
                                        Text(
                                          _formatearMonto(monto, obra['moneda']),
                                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF1B365D)),
                                        ),
                                      ],
                                    ),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: Colors.grey[100],
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: Colors.black12),
                                          ),
                                          child: Text(
                                            '${obra['superficieM2']} m²',
                                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87),
                                          ),
                                        ),
                                        if (tieneCac) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF1B365D),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: const Text(
                                              'CAC',
                                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 12),
                                const Divider(height: 1),
                                const SizedBox(height: 8),

                                // Pie de Tarjeta: Info de Modificación + Botones de Acción
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Última Modif: ${obra['ultimaModif']} • ${obra['revision']}',
                                      style: const TextStyle(fontSize: 10, color: Colors.black38),
                                    ),
                                    Row(
                                      children: [
                                        IconButton(
                                          constraints: const BoxConstraints(),
                                          padding: const EdgeInsets.symmetric(horizontal: 6),
                                          icon: const Icon(Icons.tune, size: 18, color: Color(0xFF1B365D)),
                                          tooltip: 'Ajuste Económico / Moneda',
                                          onPressed: () => _configurarAjusteEconomico(obra),
                                        ),
                                        IconButton(
                                          constraints: const BoxConstraints(),
                                          padding: const EdgeInsets.symmetric(horizontal: 6),
                                          icon: const Icon(Icons.assignment_outlined, size: 18, color: Color(0xFF1B365D)),
                                          tooltip: 'Ver Presupuesto y Cómputo',
                                          onPressed: () => _abrirPresupuesto(obra),
                                        ),
                                        IconButton(
                                          constraints: const BoxConstraints(),
                                          padding: const EdgeInsets.symmetric(horizontal: 6),
                                          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                                          tooltip: 'Eliminar Obra',
                                          onPressed: () => _confirmarEliminar(obra),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 8),

                                // Banner Inferior Integrado: Solicitud de Cómputo / Legajo
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: estadoServicio == 'En Revision' ? Colors.amber[50] : const Color(0xFFEFF3F8),
                                    borderRadius: BorderRadius.circular(6),
                                    border: estadoServicio == 'En Revision' ? Border.all(color: Colors.amber[300]!) : null,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            estadoServicio == 'En Revision' ? Icons.hourglass_top : Icons.engineering_outlined,
                                            size: 14,
                                            color: estadoServicio == 'En Revision' ? Colors.amber[900] : const Color(0xFF1B365D),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            estadoServicio == 'En Revision'
                                                ? 'Estudio Técnico en Revisión'
                                                : '¿Necesitás Cómputo / IRAM / Legajo?',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: estadoServicio == 'En Revision' ? Colors.amber[900] : const Color(0xFF1B365D),
                                            ),
                                          ),
                                        ],
                                      ),
                                      InkWell(
                                        onTap: () => _abrirModalServiciosEspeciales(obra),
                                        child: Text(
                                          estadoServicio == 'En Revision' ? 'Ver Solicitud' : 'Solicitar',
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF1B365D),
                                            decoration: TextDecoration.underline,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _mostrarModalNuevaObra,
        backgroundColor: const Color(0xFF1B365D),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('NUEVA OBRA', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.8, color: Colors.white)),
      ),
    );
  }
}