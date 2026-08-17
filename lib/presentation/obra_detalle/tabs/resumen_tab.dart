import 'package:flutter/material.dart';

class ResumenTab extends StatefulWidget {
  final String obraId;

  const ResumenTab({super.key, required this.obraId});

  @override
  State<ResumenTab> createState() => _ResumenTabState();
}

class _ResumenTabState extends State<ResumenTab> {
  // Valores base de Costos Directos
  double _costoMateriales = 18500000.0;
  double _costoManoObra = 12400000.0;
  double _costoEquipos = 2100000.0;

  // Porcentajes de Costos Indirectos / Coeficiente de Pase
  double _gastosGeneralesPct = 10.0; // %
  double _imprevistosPct = 5.0;       // %
  double _beneficioPct = 15.0;        // %
  double _ivaPct = 21.0;              // %

  String _fmt(double monto) {
    final valorInt = monto.round();
    final str = valorInt.toString();
    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    final formateado = str.replaceAllMapped(reg, (Match m) => '${m[1]}.');
    return '\$ $formateado';
  }

  // Cálculos consolidados
  double get _costoDirectoTotal => _costoMateriales + _costoManoObra + _costoEquipos;
  double get _gastosGeneralesMonto => _costoDirectoTotal * (_gastosGeneralesPct / 100);
  double get _imprevistosMonto => _costoDirectoTotal * (_imprevistosPct / 100);
  double get _costoTotalObra => _costoDirectoTotal + _gastosGeneralesMonto + _imprevistosMonto;
  double get _beneficioMonto => _costoTotalObra * (_beneficioPct / 100);
  double get _subtotalNeto => _costoTotalObra + _beneficioMonto;
  double get _ivaMonto => _subtotalNeto * (_ivaPct / 100);
  double get _totalPresupuestoFinal => _subtotalNeto + _ivaMonto;

  double get _coeficientePase => _costoDirectoTotal > 0 ? (_subtotalNeto / _costoDirectoTotal) : 1.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // TARJETA PRINCIPAL - TOTAL PRESUPUESTO
            Card(
              color: const Color(0xFF1B365D),
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              child: Padding(
                padding: const EdgeInsets.all(18.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'PRESUPUESTO TOTAL CONSOLIDADO',
                      style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _fmt(_totalPresupuestoFinal),
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    const Divider(color: Colors.white24, height: 1),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _metricaHeader('Subtotal Neto', _fmt(_subtotalNeto)),
                        _metricaHeader('Coeficiente Pase', _coeficientePase.toStringAsFixed(3)),
                        _metricaHeader('IVA (${_ivaPct.toStringAsFixed(0)}%)', _fmt(_ivaMonto)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // DESGLOSE COSTOS DIRECTOS
            const Text(
              '1. Costos Directos',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1B365D)),
            ),
            const SizedBox(height: 10),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              child: Column(
                children: [
                  _itemFilaResumen('Materiales', _fmt(_costoMateriales), _costoDirectoTotal > 0 ? (_costoMateriales / _costoDirectoTotal * 100) : 0),
                  const Divider(height: 1),
                  _itemFilaResumen('Mano de Obra', _fmt(_costoManoObra), _costoDirectoTotal > 0 ? (_costoManoObra / _costoDirectoTotal * 100) : 0),
                  const Divider(height: 1),
                  _itemFilaResumen('Equipos y Herramientas', _fmt(_costoEquipos), _costoDirectoTotal > 0 ? (_costoEquipos / _costoDirectoTotal * 100) : 0),
                  Container(
                    color: Colors.grey.shade100,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Costo Directo', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1B365D))),
                        Text(_fmt(_costoDirectoTotal), style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1B365D), fontSize: 15)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // COSTOS INDIRECTOS Y BENEFICIO
            const Text(
              '2. Costos Indirectos y Margen',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1B365D)),
            ),
            const SizedBox(height: 10),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              child: Column(
                children: [
                  _itemFilaPorcentaje('Gastos Generales', _gastosGeneralesPct, _gastosGeneralesMonto, (val) => setState(() => _gastosGeneralesPct = val)),
                  const Divider(height: 1),
                  _itemFilaPorcentaje('Imprevistos / Contingencia', _imprevistosPct, _imprevistosMonto, (val) => setState(() => _imprevistosPct = val)),
                  const Divider(height: 1),
                  _itemFilaPorcentaje('Beneficio / Honorarios', _beneficioPct, _beneficioMonto, (val) => setState(() => _beneficioPct = val)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricaHeader(String titulo, String valor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo, style: const TextStyle(color: Colors.white60, fontSize: 11)),
        const SizedBox(height: 2),
        Text(valor, style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13)),
      ],
    );
  }

  Widget _itemFilaResumen(String concepto, String montoStr, double porcentaje) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(concepto, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${porcentaje.toStringAsFixed(1)}%',
                  style: TextStyle(fontSize: 10, color: Colors.blue.shade900, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          Text(montoStr, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _itemFilaPorcentaje(String concepto, double pct, double monto, Function(double) onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(concepto, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ),
          SizedBox(
            width: 70,
            child: TextFormField(
              initialValue: pct.toStringAsFixed(1),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                suffixText: '%',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                border: OutlineInputBorder(),
              ),
              onChanged: (val) {
                final parsed = double.tryParse(val);
                if (parsed != null) onChanged(parsed);
              },
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 110,
            child: Text(
              _fmt(monto),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}