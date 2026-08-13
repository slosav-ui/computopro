import 'package:flutter/material.dart';
import '../../../data/models/obra_model.dart';
import '../tabs/rubros_tab.dart';

class PresupuestosScreen extends StatefulWidget {
  final dynamic obra;

  const PresupuestosScreen({Key? key, this.obra}) : super(key: key);

  @override
  _PresupuestosScreenState createState() => _PresupuestosScreenState();
}

class _PresupuestosScreenState extends State<PresupuestosScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late Map<String, dynamic> _obraDatos;

  // Coeficientes dinámicos para Resumen Final
  double _gastosGeneralesPorcentaje = 15.0;
  double _beneficioPorcentaje = 10.0;
  double _ivaPorcentaje = 21.0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);

    String nombreObra = 'Proyecto Genérico';
    String propietario = 'Comitente Genérico';
    String ubicacion = 'Ubicación no especificada';
    double sup = 100.0;
    double monto = 100000000.0;

    if (widget.obra != null) {
      if (widget.obra is Map<String, dynamic>) {
        final map = widget.obra as Map<String, dynamic>;
        nombreObra = map['nombre']?.toString() ?? nombreObra;
        propietario = map['propietario']?.toString() ?? map['comitente']?.toString() ?? propietario;
        ubicacion = map['ubicacion']?.toString() ?? ubicacion;
        sup = (map['superficieM2'] as num?)?.toDouble() ?? (map['superficie'] as num?)?.toDouble() ?? sup;
        monto = (map['montoEstimadoArs'] as num?)?.toDouble() ?? (map['montoTotal'] as num?)?.toDouble() ?? monto;
      } else {
        // Acceso seguro por casting dinámico para evitar errores de getters/métodos faltantes en ObraModel
        final dynamic o = widget.obra;
        try { if (o.nombre != null) nombreObra = o.nombre.toString(); } catch (_) {}
        try { 
          final prop = o.propietario ?? o.comitente;
          if (prop != null) propietario = prop.toString(); 
        } catch (_) {}
        try { if (o.ubicacion != null) ubicacion = o.ubicacion.toString(); } catch (_) {}
        try { 
          final valSup = o.superficieM2 ?? o.superficie;
          if (valSup != null && valSup is num) sup = valSup.toDouble(); 
        } catch (_) {}
        try { 
          final valMonto = o.montoEstimadoArs ?? o.montoTotal;
          if (valMonto != null && valMonto is num) monto = valMonto.toDouble(); 
        } catch (_) {}
      }
    }

    _obraDatos = {
      'nombre': nombreObra,
      'propietario': propietario,
      'ubicacion': ubicacion,
      'superficieM2': sup,
      'moneda': 'ARS',
      'montoEstimadoArs': monto,
      'revision': 'Rev. 01',
    };
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _fmt(double monto) {
    final valorInt = monto.round();
    final str = valorInt.toString();
    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    final formateado = str.replaceAllMapped(reg, (Match m) => '${m[1]}.');
    final String moneda = _obraDatos['moneda'] ?? 'ARS';
    return moneda == 'USD' ? 'USD $formateado' : '\$ $formateado';
  }

  @override
  Widget build(BuildContext context) {
    final String moneda = _obraDatos['moneda'] ?? 'ARS';
    final ObraModel? obraModelParaTab = widget.obra is ObraModel ? widget.obra as ObraModel : null;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B365D),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _obraDatos['nombre'] ?? 'Presupuesto de Obra',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            Text(
              '${_obraDatos['propietario']} • ${_obraDatos['superficieM2']} m² • ${moneda == 'USD' ? 'USD' : 'ARS (\$)'}',
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: Colors.amber,
          indicatorWeight: 3,
          labelColor: Colors.amber,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          tabs: const [
            Tab(icon: Icon(Icons.calculate_outlined, size: 18), text: '1. Cómputo y Pres.'),
            Tab(icon: Icon(Icons.analytics_outlined, size: 18), text: '2. APU'),
            Tab(icon: Icon(Icons.inventory_2_outlined, size: 18), text: '3. Materiales y MO'),
            Tab(icon: Icon(Icons.storefront_outlined, size: 18), text: '4. Proveedores'),
            Tab(icon: Icon(Icons.show_chart_outlined, size: 18), text: '5. Certificación'),
            Tab(icon: Icon(Icons.receipt_long_outlined, size: 18), text: '6. Resumen Final'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          RubrosTab(obra: obraModelParaTab),
          _buildTabApu(),
          _buildTabMaterialesYMo(),
          _buildTabProveedores(),
          _buildTabCertificaciones(),
          _buildTabResumenFinal(),
        ],
      ),
    );
  }

  // 2. APU
  Widget _buildTabApu() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.black12)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Item APU Seleccionado:', style: TextStyle(fontSize: 10, color: Colors.black54)),
                    Text('02.01 Hormigón armado en fundaciones', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1B365D))),
                  ],
                ),
                Text(_fmt(320000.0), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF2E7D32))),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                _buildApuSection('MATERIALES', [
                  _buildApuDetailRow('Hormigón Elaborado H-21', 'm³', 1.05, 180000.0),
                  _buildApuDetailRow('Acero ADN 420 en barras', 'kg', 65.0, 1850.0),
                  _buildApuDetailRow('Alambre negro de atar N°16', 'kg', 1.2, 2400.0),
                ]),
                _buildApuSection('MANO DE OBRA', [
                  _buildApuDetailRow('Oficial Especializado (Estructura)', 'hs', 4.5, 4800.0),
                  _buildApuDetailRow('Ayudante', 'hs', 6.0, 3900.0),
                ]),
                _buildApuSection('EQUIPOS Y HERRAMIENTAS', [
                  _buildApuDetailRow('Vibrador de Inmersión naftero', 'hs', 0.5, 8500.0),
                  _buildApuDetailRow('Herramientas menores y encofrado', 'gl', 1.0, 12000.0),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApuSection(String titulo, List<Widget> filas) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF1B365D))),
            const Divider(),
            ...filas,
          ],
        ),
      ),
    );
  }

  Widget _buildApuDetailRow(String concepto, String unidad, double consumo, double unitario) {
    final subtotal = consumo * unitario;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(concepto, style: const TextStyle(fontSize: 11))),
          SizedBox(width: 50, child: Text('$consumo $unidad', style: const TextStyle(fontSize: 11, color: Colors.black54))),
          SizedBox(width: 80, child: Text(_fmt(unitario), style: const TextStyle(fontSize: 11, color: Colors.black54), textAlign: TextAlign.right)),
          SizedBox(width: 90, child: Text(_fmt(subtotal), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
        ],
      ),
    );
  }

  // 3. MATERIALES Y MO
  Widget _buildTabMaterialesYMo() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.inventory, color: Color(0xFF1B365D)),
            title: const Text('Consolidado Total de Insumos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            subtitle: const Text('Listado general de insumos requeridos para el total de la obra', style: TextStyle(fontSize: 11)),
          ),
        ),
        const SizedBox(height: 8),
        _buildInsumoCard('Cemento Portland (Bolsa 50kg)', '650 Bolsas', 12500.0, 8125000.0),
        _buildInsumoCard('Arena Medida Fina/Gruesa', '45 m³', 28000.0, 1260000.0),
        _buildInsumoCard('Hierro Aletado 10mm (Barra 12m)', '180 Unidades', 22500.0, 4050000.0),
        _buildInsumoCard('Oficial Albañil (Horas Totales)', '1200 Horas', 4800.0, 5760000.0),
        _buildInsumoCard('Ayudante (Horas Totales)', '1600 Horas', 3900.0, 6240000.0),
      ],
    );
  }

  Widget _buildInsumoCard(String nombre, String cantidad, double unitario, double total) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        title: Text(nombre, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        subtitle: Text('Cantidad necesaria: $cantidad  •  Unitario: ${_fmt(unitario)}', style: const TextStyle(fontSize: 10)),
        trailing: Text(_fmt(total), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF2E7D32))),
      ),
    );
  }

  // 4. PROVEEDORES
  Widget _buildTabProveedores() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          color: Colors.blueGrey[50],
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.compare_arrows, color: Color(0xFF1B365D)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Comparativo y Cotización de Proveedores Directos por Insumo.',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1B365D)),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        _buildProveedorCard('Corralón San Martín', 'Hierro / Cementos', 'Descuento 5% pago contado', '\$ 12.450.000'),
        _buildProveedorCard('Hormigonera del Sur', 'Hormigón Elaborado', 'Incluye bomba pluma', '\$ 8.900.000'),
        _buildProveedorCard('Distribuidora Eléctrica Central', 'Materiales Eléctricos', 'Presupuesto válido por 10 días', '\$ 4.320.000'),
      ],
    );
  }

  Widget _buildProveedorCard(String nombre, String rubro, String condicion, String total) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.store, color: Color(0xFF1B365D)),
        title: Text(nombre, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        subtitle: Text('$rubro\n$condicion', style: const TextStyle(fontSize: 11)),
        isThreeLine: true,
        trailing: Text(total, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF2E7D32))),
      ),
    );
  }

  // 5. CERTIFICACIONES
  Widget _buildTabCertificaciones() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Avance y Curva de Certificación de Obra', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1B365D))),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              children: [
                _buildCertRow('Certificado N° 1 - Anticipo / T. Preliminares', '100%', _fmt(850000.0), Colors.green),
                _buildCertRow('Certificado N° 2 - Fundaciones y Estructura', '65%', _fmt(5400000.0), Colors.orange),
                _buildCertRow('Certificado N° 3 - Muros y Cubierta', '0%', _fmt(0.0), Colors.grey),
                _buildCertRow('Certificado N° 4 - Instalaciones y Terminaciones', '0%', _fmt(0.0), Colors.grey),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCertRow(String titulo, String porcentaje, String monto, Color color) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.2),
          child: Text(porcentaje, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
        ),
        title: Text(titulo, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        trailing: Text(monto, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      ),
    );
  }

  // 6. RESUMEN FINAL DINÁMICO
  Widget _buildTabResumenFinal() {
    final double costoDirectoTotal = 85000000.0;
    final double gastosGenerales = costoDirectoTotal * (_gastosGeneralesPorcentaje / 100);
    final double costoSubtotal = costoDirectoTotal + gastosGenerales;
    final double beneficio = costoSubtotal * (_beneficioPorcentaje / 100);
    final double subtotalNeto = costoSubtotal + beneficio;
    final double iva = subtotalNeto * (_ivaPorcentaje / 100);
    final double precioTotalFinal = subtotalNeto + iva;

    final double superficie = (_obraDatos['superficieM2'] as num).toDouble();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            color: const Color(0xFF1B365D),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('PRECIO TOTAL DE OBRA', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(_fmt(precioTotalFinal), style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('Incidencia por m²: ${_fmt(precioTotalFinal / (superficie > 0 ? superficie : 1))}/m²', style: const TextStyle(color: Colors.amber, fontSize: 12)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Ajuste de Coeficientes Indirectos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1B365D))),
                  const SizedBox(height: 8),
                  _buildSliderCoeficiente('Gastos Generales / Indirectos', _gastosGeneralesPorcentaje, 0, 30, (val) {
                    setState(() => _gastosGeneralesPorcentaje = val);
                  }),
                  _buildSliderCoeficiente('Beneficio Empresarial', _beneficioPorcentaje, 0, 30, (val) {
                    setState(() => _beneficioPorcentaje = val);
                  }),
                  _buildSliderCoeficiente('IVA', _ivaPorcentaje, 0, 27, (val) {
                    setState(() => _ivaPorcentaje = val);
                  }),
                  const Divider(),
                  _buildResumenRow('Costo Directo Total (CD)', _fmt(costoDirectoTotal), isBold: true),
                  _buildResumenRow('Gastos Generales (${_gastosGeneralesPorcentaje.toStringAsFixed(1)}%)', _fmt(gastosGenerales)),
                  _buildResumenRow('Beneficio (${_beneficioPorcentaje.toStringAsFixed(1)}%)', _fmt(beneficio)),
                  const Divider(),
                  _buildResumenRow('Subtotal Neto', _fmt(subtotalNeto), isBold: true),
                  _buildResumenRow('IVA (${_ivaPorcentaje.toStringAsFixed(1)}%)', _fmt(iva)),
                  const Divider(),
                  _buildResumenRow('TOTAL GENERAL', _fmt(precioTotalFinal), isBold: true, color: const Color(0xFF2E7D32)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliderCoeficiente(String etiqueta, double valorActual, double min, double max, ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(etiqueta, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
            Text('${valorActual.toStringAsFixed(1)} %', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1B365D))),
          ],
        ),
        Slider(
          value: valorActual,
          min: min,
          max: max,
          divisions: (max - min).toInt() * 2,
          activeColor: const Color(0xFF1B365D),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildResumenRow(String etiqueta, String valor, {bool isBold = false, Color color = Colors.black87}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(etiqueta, style: TextStyle(fontSize: 12, fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: color)),
          Text(valor, style: TextStyle(fontSize: 12, fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: color)),
        ],
      ),
    );
  }
}