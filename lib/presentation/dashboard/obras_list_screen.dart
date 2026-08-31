import 'package:flutter/material.dart';
import '../obra_detalle/screens/presupuestos_screen.dart';
import '../../services/obras_repository.dart';
import '../../services/auth_service.dart';

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

  // --- Acceso a datos ---
  final ObrasRepository _obrasRepository = ObrasRepository();
  final AuthService _authService = AuthService();
  List<Map<String, dynamic>> _obras = [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cotizacionUsdEfectiva = _dolarOficialPromedio;
    _cargarObras();
  }

  // --- Carga de Obras desde Supabase ---
  Future<void> _cargarObras() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final obras = await _obrasRepository.getObras();
      if (!mounted) return;
      setState(() {
        _obras = obras.map(_conMontosCalculados).toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar las obras. Verificá tu conexión.';
        _cargando = false;
      });
    }
  }

  // --- Conversión de Moneda (a partir del monto base persistido) ---
  double _convertirMonto(double monto, String monedaOrigen, String monedaDestino) {
    if (monedaOrigen == monedaDestino) return monto;
    return monedaOrigen == 'ARS'
        ? monto / _cotizacionUsdEfectiva
        : monto * _cotizacionUsdEfectiva;
  }

  Map<String, dynamic> _conMontosCalculados(Map<String, dynamic> obra) {
    final double montoTotal = (obra['montoTotal'] as num?)?.toDouble() ?? 0.0;
    final String moneda = obra['moneda'] as String? ?? 'ARS';
    return {
      ...obra,
      'montoEstimadoArs': moneda == 'ARS' ? montoTotal : _convertirMonto(montoTotal, 'USD', 'ARS'),
      'montoEstimadoUsd': moneda == 'USD' ? montoTotal : _convertirMonto(montoTotal, 'ARS', 'USD'),
    };
  }

  // --- Formateador de Montos ---
  String _formatearMonto(double monto, String moneda) {
    final valorInt = monto.round();
    final str = valorInt.toString();
    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    final formateado = str.replaceAllMapped(reg, (Match m) => '${m[1]}.');
    return moneda == 'USD' ? 'USD $formateado' : '\$ $formateado';
  }

  /// Acepta coma o punto como separador decimal (mismo criterio que
  /// _parsearCantidad/_parsearPrecio de SubitemsScreen) y rechaza vacío,
  /// no numérico o <= 0 — una obra de 0 m² no tiene sentido. Antes el alta
  /// no validaba esto en absoluto: `double.tryParse(...) ?? 100.0` caía en
  /// silencio a un valor inventado si el texto no parseaba, sin avisar
  /// nada — peligroso siempre, y directamente inaceptable en edición
  /// (podía pisar la superficie real de una obra en curso sin que nadie se
  /// enterara).
  double? _parsearSuperficie(String texto) {
    final normalizado = texto.trim().replaceAll(',', '.');
    if (normalizado.isEmpty) return null;
    final valor = double.tryParse(normalizado);
    if (valor == null || valor <= 0) return null;
    return valor;
  }

  /// Para precargar el campo de superficie en el diálogo de edición sin
  /// mostrar "120.0" cuando el valor real es un entero.
  String _formatearCantidadSuperficie(double valor) {
    return valor == valor.roundToDouble() ? valor.toInt().toString() : valor.toString();
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
            // Mismo patrón que los otros 2 títulos de diálogo ya corregidos
            // en esta sesión — título de AlertDialog sin Expanded desborda
            // en pantallas angostas.
            Expanded(
              child: Text('Mapa de Obras Registradas', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
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
    bool guardando = false;

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
                // Expanded preventivo: mismo riesgo que tenía el título de
                // "Ajuste Económico & Moneda" (título de AlertDialog sin
                // Expanded desborda en pantallas angostas) — este texto es
                // más corto y no se reportó roto todavía, pero es el mismo
                // patrón sin resolver.
                Expanded(
                  child: Text('Alta de Nueva Obra', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
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
                    // labelStyle a juego con el texto tipeado (12) — el label
                    // heredaba el tamaño default del tema (~16), que no
                    // entraba entero en un campo angosto y se recortaba con
                    // "...". A 12 entra sin tocar ninguna palabra del texto.
                    decoration: const InputDecoration(
                      labelText: 'Nombre de la Obra / Proyecto',
                      labelStyle: TextStyle(fontSize: 12),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: propietarioCtrl,
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      labelText: 'Propietario / Comitente',
                      labelStyle: TextStyle(fontSize: 12),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: ubicacionCtrl,
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      labelText: 'Ubicación / Localidad',
                      labelStyle: TextStyle(fontSize: 12),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: superficieCtrl,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(fontSize: 12),
                          decoration: const InputDecoration(
                            labelText: 'Superficie (m²)',
                            labelStyle: TextStyle(fontSize: 12),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: tipoSeleccionado,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Tipo',
                            labelStyle: TextStyle(fontSize: 11),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          style: const TextStyle(fontSize: 11, color: Colors.black87),
                          items: ['Residencial', 'Comercial/Residencial', 'Industrial', 'Infraestructura']
                              .map((t) => DropdownMenuItem(
                                    value: t,
                                    child: Text(t, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis),
                                  ))
                              .toList(),
                          onChanged: (val) {
                            if (val != null) setModalState(() => tipoSeleccionado = val);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Wrap en vez de Row: acá no hay ningún widget con texto
                  // que pueda ceder ancho (los chips no truncan su label
                  // solo, y "Moneda Base:" ya es corto) — si algún día no
                  // entran los tres en una línea, el que sobra pasa a la
                  // siguiente en vez de desbordar. Robusto a cualquier
                  // ancho, no solo al de este diálogo hoy.
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      const Text('Moneda Base:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ChoiceChip(
                        label: const Text('ARS (\$)', style: TextStyle(fontSize: 11)),
                        selected: monedaSeleccionada == 'ARS',
                        onSelected: (sel) {
                          if (sel) setModalState(() => monedaSeleccionada = 'ARS');
                        },
                      ),
                      ChoiceChip(
                        label: const Text('USD', style: TextStyle(fontSize: 11)),
                        selected: monedaSeleccionada == 'USD',
                        onSelected: (sel) {
                          if (sel) setModalState(() => monedaSeleccionada = 'USD');
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Wrap, no Row: acá ambos textos son cortos y fijos (bajo
                  // riesgo por el criterio de la memoria), pero dentro de un
                  // AlertDialog el margen es chico igual — si algún día no
                  // entran los tres juntos, el badge pasa a la línea
                  // siguiente en vez de desbordar.
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      const Icon(Icons.person_pin_circle_outlined, size: 14, color: Colors.black45),
                      const Text('Creador: Vos', style: TextStyle(fontSize: 11, color: Colors.black54)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(4)),
                        child: const Text(
                          'Administrador por defecto',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black54),
                        ),
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
                onPressed: guardando
                    ? null
                    : () async {
                        if (nombreCtrl.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Por favor ingrese el nombre de la obra.')),
                          );
                          return;
                        }
                        final double? sup = _parsearSuperficie(superficieCtrl.text);
                        if (sup == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Ingresá una superficie válida, mayor a 0.')),
                          );
                          return;
                        }
                        final double montoArs = monedaSeleccionada == 'ARS' ? sup * 1000000.0 : (sup * 750.0) * _cotizacionUsdEfectiva;
                        final double montoUsd = monedaSeleccionada == 'USD' ? sup * 750.0 : (sup * 1000000.0) / _cotizacionUsdEfectiva;
                        final double montoTotal = monedaSeleccionada == 'ARS' ? montoArs : montoUsd;

                        setModalState(() => guardando = true);
                        try {
                          final creada = await _obrasRepository.crearObra({
                            'nombre': nombreCtrl.text.trim(),
                            'propietario': propietarioCtrl.text.trim().isEmpty ? 'Sin Especificar' : propietarioCtrl.text.trim(),
                            'ubicacion': ubicacionCtrl.text.trim().isEmpty ? 'Ubicación Faltante' : ubicacionCtrl.text.trim(),
                            'superficieM2': sup,
                            'tipoObra': tipoSeleccionado,
                            'estado': 'Cotización',
                            'moneda': monedaSeleccionada,
                            'aplicaCac': monedaSeleccionada == 'ARS',
                            'montoTotal': montoTotal,
                            'mesBaseCac': 'Agosto 2026',
                            'revision': 'Rev. 00',
                            'tipoRol': 'Director de Obra',
                            'estadoServicioEspecial': 'Ninguno',
                            'idAdminCreador': _authService.usuarioActual?.id,
                          });
                          if (!context.mounted) return;
                          setState(() => _obras.add(_conMontosCalculados(creada)));
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Nueva obra registrada exitosamente.')),
                          );
                        } catch (e) {
                          if (!context.mounted) return;
                          setModalState(() => guardando = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('No se pudo guardar la obra. Intente nuevamente.')),
                          );
                        }
                      },
                child: guardando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Crear Obra', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  // --- Diálogo: Editar Obra ---
  //
  // Reusa la estructura del alta, pero deliberadamente NO reusa su
  // guardado: acá no hay ningún campo de moneda (eso queda exclusivo del
  // diálogo de Ajuste Económico — mezclarlos correría el riesgo real de
  // cambiar la moneda por acá sin la lógica de default de CAC que ya tiene
  // ese diálogo), y el guardado escribe un mapa parcial con solo los 5
  // campos descriptivos — nunca montoTotal, moneda ni aplicaCac. El alta
  // recalcula montoTotal desde la superficie como estimación de arranque;
  // reusar ese cálculo acá le pisaría el monto real de una obra en curso
  // con esa fórmula cruda cada vez que alguien corrija solo el nombre.
  void _mostrarModalEditarObra(Map<String, dynamic> obra) {
    final nombreCtrl = TextEditingController(text: obra['nombre'] as String? ?? '');
    final propietarioCtrl = TextEditingController(text: obra['propietario'] as String? ?? '');
    final ubicacionCtrl = TextEditingController(text: obra['ubicacion'] as String? ?? '');
    final superficieCtrl = TextEditingController(
      text: _formatearCantidadSuperficie((obra['superficieM2'] as num?)?.toDouble() ?? 0),
    );
    String tipoSeleccionado = (obra['tipoObra'] as String?) ?? 'Residencial';
    bool guardando = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: const Row(
              children: [
                Icon(Icons.edit_outlined, color: Color(0xFF1B365D)),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Editar Obra', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
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
                            'Estos datos se consolidan en las carátulas, encabezados y legajos '
                            'exportables en PDF — el cambio se refleja en cualquier documento nuevo '
                            'que se genere de acá en más.',
                            style: TextStyle(fontSize: 10, color: Colors.amber[900], height: 1.3, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: nombreCtrl,
                    autofocus: true,
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      labelText: 'Nombre de la Obra / Proyecto',
                      labelStyle: TextStyle(fontSize: 12),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: propietarioCtrl,
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      labelText: 'Propietario / Comitente',
                      labelStyle: TextStyle(fontSize: 12),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: ubicacionCtrl,
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      labelText: 'Ubicación / Localidad',
                      labelStyle: TextStyle(fontSize: 12),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: superficieCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: const TextStyle(fontSize: 12),
                          decoration: const InputDecoration(
                            labelText: 'Superficie (m²)',
                            labelStyle: TextStyle(fontSize: 12),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: tipoSeleccionado,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Tipo',
                            labelStyle: TextStyle(fontSize: 11),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          style: const TextStyle(fontSize: 11, color: Colors.black87),
                          items: ['Residencial', 'Comercial/Residencial', 'Industrial', 'Infraestructura']
                              .map((t) => DropdownMenuItem(
                                    value: t,
                                    child: Text(t, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis),
                                  ))
                              .toList(),
                          onChanged: (val) {
                            if (val != null) setModalState(() => tipoSeleccionado = val);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: guardando ? null : () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B365D)),
                onPressed: guardando
                    ? null
                    : () async {
                        if (nombreCtrl.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Por favor ingrese el nombre de la obra.')),
                          );
                          return;
                        }
                        final double? sup = _parsearSuperficie(superficieCtrl.text);
                        if (sup == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Ingresá una superficie válida, mayor a 0.')),
                          );
                          return;
                        }

                        setModalState(() => guardando = true);
                        try {
                          final nombre = nombreCtrl.text.trim();
                          final propietario = propietarioCtrl.text.trim().isEmpty ? 'Sin Especificar' : propietarioCtrl.text.trim();
                          final ubicacion = ubicacionCtrl.text.trim().isEmpty ? 'Ubicación Faltante' : ubicacionCtrl.text.trim();
                          // Mapa parcial a propósito — sin montoTotal, moneda
                          // ni aplicaCac, ver comentario del método.
                          await _obrasRepository.actualizarObra(obra['id'] as String, {
                            'nombre': nombre,
                            'propietario': propietario,
                            'ubicacion': ubicacion,
                            'superficieM2': sup,
                            'tipoObra': tipoSeleccionado,
                          });
                          if (!context.mounted) return;
                          setState(() {
                            obra['nombre'] = nombre;
                            obra['propietario'] = propietario;
                            obra['ubicacion'] = ubicacion;
                            obra['superficieM2'] = sup;
                            obra['tipoObra'] = tipoSeleccionado;
                          });
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Obra actualizada.')),
                          );
                        } catch (e) {
                          if (!context.mounted) return;
                          setModalState(() => guardando = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('No se pudo guardar los cambios. Probá de nuevo.')),
                          );
                        }
                      },
                child: guardando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Guardar Cambios', style: TextStyle(color: Colors.white)),
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
                // Expanded: el título de un AlertDialog no está dentro del
                // SingleChildScrollView del content, así que sin esto el
                // Row desborda en vez de que el texto ajuste — mismo
                // patrón de siempre, acá con un título más largo que el
                // de "Alta de Nueva Obra" (que tiene el mismo riesgo
                // latente, corregido de paso más abajo).
                Expanded(
                  child: Text('Ajuste Económico & Moneda', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
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
                            // Expanded: mismo patrón de siempre — el badge
                            // "PRO" es corto y fijo, el label es el que
                            // tiene que ceder si no entra.
                            Expanded(
                              child: Text(
                                'Dólar Ref. Banco Nación (BNA):',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1B365D)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (_esPlanPro) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: Colors.amber[700], borderRadius: BorderRadius.circular(4)),
                                child: const Text('PRO', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                              ),
                            ],
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
                      final String nuevaMoneda = newSelection.first;
                      setDialogState(() {
                        if (nuevaMoneda == 'USD') {
                          aplicaCac = false;
                        } else if (nuevaMoneda == 'ARS' && monedaSeleccionada != 'ARS') {
                          // En pesos el CAC no es opcional por defecto — un
                          // presupuesto en ARS sin referencia de ajuste no
                          // se sostiene en el tiempo. Se activa solo al
                          // pasar A pesos (cada vez, no solo la primera
                          // vez); el usuario lo puede destildar antes de
                          // guardar, ver SwitchListTile de abajo.
                          aplicaCac = true;
                        }
                        monedaSeleccionada = nuevaMoneda;
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
                    // Fijo mientras esté apagado, no un pop-up al destildar
                    // — así queda visible cada vez que se revisa este
                    // estado, no solo en el instante de apagarlo.
                    if (!aplicaCac)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Sin el ajuste por CAC, este presupuesto en pesos queda fijo: no se '
                          'actualiza solo con el costo de la construcción. Tenelo en cuenta sobre '
                          'todo al certificar avances — un monto viejo sin ajustar termina '
                          'cobrando menos de lo que le cuesta la obra.',
                          style: TextStyle(fontSize: 10, color: Colors.orange[900]),
                        ),
                      ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B365D)),
                onPressed: () async {
                  final String monedaAnterior = obra['moneda'] as String;
                  final double montoTotalAnterior = (obra['montoTotal'] as num?)?.toDouble() ?? 0.0;
                  final double nuevoMontoTotal = monedaSeleccionada == monedaAnterior
                      ? montoTotalAnterior
                      : _convertirMonto(montoTotalAnterior, monedaAnterior, monedaSeleccionada);
                  final bool nuevoAplicaCac = (monedaSeleccionada == 'ARS') ? aplicaCac : false;

                  try {
                    await _obrasRepository.actualizarObra(obra['id'] as String, {
                      'moneda': monedaSeleccionada,
                      'aplicaCac': nuevoAplicaCac,
                      'montoTotal': nuevoMontoTotal,
                    });
                    if (!context.mounted) return;
                    setState(() {
                      obra['moneda'] = monedaSeleccionada;
                      obra['aplicaCac'] = nuevoAplicaCac;
                      obra['montoTotal'] = nuevoMontoTotal;
                      obra['montoEstimadoArs'] = monedaSeleccionada == 'ARS' ? nuevoMontoTotal : _convertirMonto(nuevoMontoTotal, monedaSeleccionada, 'ARS');
                      obra['montoEstimadoUsd'] = monedaSeleccionada == 'USD' ? nuevoMontoTotal : _convertirMonto(nuevoMontoTotal, monedaSeleccionada, 'USD');
                    });
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Configuración económica guardada.')),
                    );
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('No se pudo guardar la configuración. Intente nuevamente.')),
                    );
                  }
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
                // Expanded: mismo patrón de siempre — el ícono con badge de
                // la izquierda es de ancho fijo, el bloque de texto tiene
                // que ceder si no entra.
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Suscripción Profesional',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1B365D)),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Gestión técnica y financiera avanzada',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
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
    String? tipoComputo;
    final List<String> opcionesExtra = [
      'Acondicionamiento Térmico (Normas IRAM — Cálculo K, G, Q)',
      'Legajo de Detalles Constructivos',
      'Otro (especificar) — sujeto a evaluación',
    ];
    final List<bool> seleccionadosExtra = List<bool>.filled(opcionesExtra.length, false);
    bool archivoAdjuntado = false;
    String? nombreArchivo;
    final notasCtrl = TextEditingController();
    final otroCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final bool haySeleccion = tipoComputo != null || seleccionadosExtra.contains(true);
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: const Row(
              children: [
                Icon(Icons.assignment_outlined, color: Color(0xFF1B365D)),
                SizedBox(width: 8),
                // Mismo patrón que los otros títulos de diálogo ya
                // corregidos en esta sesión.
                Expanded(
                  child: Text('Servicios Especiales', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Obra: ${obra['nombre']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 12),
                  const Text('Solicitar presupuesto para elaboración técnica de:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87)),
                  const SizedBox(height: 4),
                  _buildRadioOption(
                    'Cómputo Métrico',
                    'Listado de cantidades y materiales — precios a cargo del usuario.',
                    'metrico',
                    tipoComputo,
                    (val) => setModalState(() => tipoComputo = val),
                  ),
                  _buildRadioOption(
                    'Cómputo y Presupuesto',
                    'Cómputo + presupuesto completo con precios incluidos.',
                    'completo',
                    tipoComputo,
                    (val) => setModalState(() => tipoComputo = val),
                  ),
                  const SizedBox(height: 6),
                  for (int i = 0; i < opcionesExtra.length; i++) ...[
                    _buildCheckOption(
                      opcionesExtra[i],
                      seleccionadosExtra[i],
                      (val) => setModalState(() => seleccionadosExtra[i] = val ?? false),
                    ),
                    if (i == 2 && seleccionadosExtra[2])
                      Padding(
                        padding: const EdgeInsets.only(left: 32, right: 4, bottom: 6),
                        child: TextField(
                          controller: otroCtrl,
                          maxLines: 2,
                          style: const TextStyle(fontSize: 12),
                          decoration: const InputDecoration(
                            hintText: 'Contame qué necesitás (render, documentación contractual, información legal, etc.)',
                            hintStyle: TextStyle(fontSize: 11),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                  ],
                  if (!haySeleccion)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, bottom: 4),
                      child: Text(
                        'Tildá al menos un servicio para solicitar la cotización.',
                        style: TextStyle(fontSize: 10, color: Colors.red[700], fontWeight: FontWeight.w600),
                      ),
                    ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 40)),
                    icon: Icon(
                      archivoAdjuntado ? Icons.check_circle : Icons.upload_file,
                      size: 18,
                      color: archivoAdjuntado ? Colors.green[700] : null,
                    ),
                    label: Text(
                      archivoAdjuntado ? (nombreArchivo ?? 'Archivo adjuntado') : 'Adjuntar Planos / Anteproyecto (PDF/DWG)',
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                    onPressed: () {
                      setModalState(() {
                        archivoAdjuntado = true;
                        nombreArchivo = 'planta_general.pdf';
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Archivo adjuntado correctamente.')),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notasCtrl,
                    maxLines: 3,
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      labelText: 'Notas / Comentario adicional (opcional)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B365D)),
                onPressed: !haySeleccion
                    ? null
                    : () {
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
          );
        },
      ),
    );
  }

  Widget _buildRadioOption(
    String label,
    String descripcion,
    String value,
    String? groupValue,
    ValueChanged<String?> onChanged,
  ) {
    return InkWell(
      onTap: () => onChanged(value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Radio<String>(
              value: value,
              groupValue: groupValue,
              onChanged: onChanged,
              activeColor: const Color(0xFF1B365D),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                    Text(descripcion, style: TextStyle(fontSize: 10, color: Colors.grey[700])),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckOption(String label, bool value, ValueChanged<bool?> onChanged) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Checkbox(
              value: value,
              onChanged: onChanged,
              activeColor: const Color(0xFF1B365D),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const SizedBox(width: 4),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 11))),
          ],
        ),
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
            onPressed: () async {
              try {
                await _obrasRepository.eliminarObra(obra['id'] as String);
                if (!mounted || !ctx.mounted) return;
                setState(() => _obras.removeWhere((i) => i['id'] == obra['id']));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Obra eliminada del registro.')),
                );
              } catch (e) {
                if (!mounted || !ctx.mounted) return;
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('No se pudo eliminar la obra. Intente nuevamente.')),
                );
              }
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // --- Menú: Imprimir / Exportar ---
  void _abrirMenuExportar(Map<String, dynamic> obra) {
    final bool tieneCertificado = obra['estado'] != 'Cotización';
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Imprimir / Exportar', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1B365D))),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.request_quote_outlined, color: Color(0xFF1B365D)),
              title: const Text('Presupuesto', style: TextStyle(fontSize: 13)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmarExportacion(obra, 'Presupuesto');
              },
            ),
            if (tieneCertificado)
              ListTile(
                leading: const Icon(Icons.verified_outlined, color: Color(0xFF1B365D)),
                title: const Text('Certificado', style: TextStyle(fontSize: 13)),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmarExportacion(obra, 'Certificado');
                },
              ),
            ListTile(
              leading: const Icon(Icons.summarize_outlined, color: Color(0xFF1B365D)),
              title: const Text('Resumen general', style: TextStyle(fontSize: 13)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmarExportacion(obra, 'Resumen general');
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // --- Diálogo: Confirmar Exportación (marca de agua Free/Pro) ---
  void _confirmarExportacion(Map<String, dynamic> obra, String tipoDocumento) {
    bool marcaAguaActiva = true;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: Row(
              children: [
                const Icon(Icons.picture_as_pdf_outlined, color: Color(0xFF1B365D)),
                const SizedBox(width: 8),
                Expanded(child: Text('Exportar $tipoDocumento', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Obra: ${obra['nombre']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 12),
                if (_esPlanPro)
                  SwitchListTile(
                    title: const Text('Incluir marca de agua', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    subtitle: const Text('Versión PRO: marca discreta y chica, opcional.', style: TextStyle(fontSize: 10, color: Colors.black54)),
                    value: marcaAguaActiva,
                    activeTrackColor: const Color(0xFF1B365D),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) => setDialogState(() => marcaAguaActiva = val),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.amber[50], borderRadius: BorderRadius.circular(6)),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.lock_outline, size: 16, color: Colors.amber),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Versión FREE: la exportación incluye marca de agua visible "ComputoPRO". La versión PRO permite una marca discreta o desactivarla.',
                            style: TextStyle(fontSize: 10, color: Colors.black87),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B365D)),
                onPressed: () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Generando $tipoDocumento...')),
                  );
                },
                child: const Text('Exportar', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
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
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            tooltip: 'Cerrar sesión',
            onPressed: () => _authService.cerrarSesion(),
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
                  // Expanded para que ceda ancho al bloque de la fecha en
                  // pantallas angostas (antes ninguno de los dos lados podía
                  // achicarse, y la suma de sus anchos naturales desbordaba
                  // en equipos más chicos que el emulador de referencia).
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'USD Ref. BNA: \$${_cotizacionUsdEfectiva.toStringAsFixed(2)}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'CAC Último Mes: +$_variacionCacUltimoMes%',
                          style: const TextStyle(color: Colors.white70, fontSize: 10),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
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
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!, style: const TextStyle(color: Colors.black54)),
                            const SizedBox(height: 8),
                            TextButton(onPressed: _cargarObras, child: const Text('Reintentar')),
                          ],
                        ),
                      )
                    : _obras.isEmpty
                ? const Center(child: Text('No hay obras registradas. Presione "+" para agregar una.'))
                : ListView.builder(
                    // Padding inferior extra para que "NUEVA OBRA" (FAB)
                    // no tape la última tarjeta — antes solo tenía el
                    // padding parejo de 12 en los 4 lados.
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
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
                                // Cabecera: Nombre + Editar + Estado
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
                                    // Lápiz acá, no un cuarto ícono en el pie
                                    // de la tarjeta (ya tiene 3, apretados
                                    // contra "Última Modif" — ver memoria de
                                    // overflow en pantalla angosta). Editar
                                    // el nombre es lo que el usuario está
                                    // mirando cuando lo quiere corregir.
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined, size: 16, color: Colors.black45),
                                      tooltip: 'Editar Obra',
                                      constraints: const BoxConstraints(),
                                      padding: const EdgeInsets.symmetric(horizontal: 6),
                                      onPressed: () => _mostrarModalEditarObra(obra),
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
                                    // Flexible (no Expanded): si el nombre entra entero, lo
                                    // muestra completo; si no hay lugar, cede en vez de
                                    // reclamar su ancho natural sin límite (eso era lo que
                                    // dejaba a ubicación sin espacio en pantallas angostas).
                                    Flexible(
                                      child: Text(
                                        obra['propietario'],
                                        style: const TextStyle(fontSize: 11, color: Colors.black54),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
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

                                // Monto Base, y debajo (línea propia, no
                                // compartiendo renglón) los chips m² / CAC.
                                // Antes competían por ancho en el mismo Row
                                // sin que ninguno pudiera ceder — al agrandar
                                // el chip de m² (pedido de otra sesión) dejó
                                // de entrar en pantallas angostas y el chip
                                // CAC se pintaba fuera del borde visible.
                                // Separarlos en líneas evita la competencia
                                // de raíz, sin achicar el chip.
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Monto Estimado Base', style: TextStyle(fontSize: 9, color: Colors.black45, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 2),
                                    Text(
                                      _formatearMonto(monto, obra['moneda']),
                                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF1B365D)),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Container(
                                          // Dato de referencia para comparar obras entre sí —
                                          // más presencia que antes (11px), sin competir con el
                                          // monto (17px).
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: Colors.grey[100],
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: Colors.black12),
                                          ),
                                          child: Text(
                                            '${obra['superficieM2']} m²',
                                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87),
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
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Última Modif: ${obra['ultimaModif']} • ${obra['revision']}',
                                        style: const TextStyle(fontSize: 10, color: Colors.black38),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
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
                                          icon: const Icon(Icons.ios_share, size: 18, color: Color(0xFF1B365D)),
                                          tooltip: 'Imprimir / Exportar',
                                          onPressed: () => _abrirMenuExportar(obra),
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
                                      // Expanded: mismo criterio que el banner superior y la
                                      // fila propietario/ubicación — el label es el texto largo
                                      // y variable, "Solicitar"/"Ver Solicitud" es corto y fijo,
                                      // así que es el label el que tiene que ceder.
                                      Expanded(
                                        child: Row(
                                          children: [
                                            Icon(
                                              estadoServicio == 'En Revision' ? Icons.hourglass_top : Icons.engineering_outlined,
                                              size: 14,
                                              color: estadoServicio == 'En Revision' ? Colors.amber[900] : const Color(0xFF1B365D),
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                estadoServicio == 'En Revision'
                                                    ? 'Estudio Técnico en Revisión'
                                                    : '¿Necesitás Cómputo / IRAM / Legajo?',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w600,
                                                  color: estadoServicio == 'En Revision' ? Colors.amber[900] : const Color(0xFF1B365D),
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                                maxLines: 1,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
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