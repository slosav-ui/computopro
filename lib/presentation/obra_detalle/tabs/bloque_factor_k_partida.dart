import 'package:flutter/material.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/models/factor_k_linea_subitem.dart';
import '../../../data/models/obra_presupuesto_config.dart';
import '../../../services/auth_service.dart';
import '../../../services/factor_k_subitem_repository.dart';
import '../../../services/obra_presupuesto_config_repository.dart';
import '../../../services/perfil_repository.dart';

/// Factor K de una partida puntual — Paso B (ver `docs/factor_k_apu_decisiones.md` §1, "Paso B,
/// más grande, sin empezar" -- ya empezó). Va debajo de la composición en `ComposicionApuScreen`,
/// después del total: primero qué lleva la partida, después los coeficientes hasta el precio final.
///
/// Función PRO, corrección de negocio sobre el criterio original del Paso A (ver
/// `docs/monetizacion.md`, punto "Desglose de Factor K es exclusivo de PRO"): Free ve la
/// composición (mano de obra, materiales, subtotal) pero NO el desglose de cómo se llega al precio
/// final -- si viera la cascada completa (porcentajes, bases, impuestos línea por línea) podría
/// armarse su propia planilla con esa estructura y nunca pagar. Corrige el criterio de
/// `docs/factor_k_apu_decisiones.md` §4 ("Free ve todo, el panel no agrega información nueva") --
/// ese criterio queda descartado, no vale más ni acá ni en `BloqueFactorK` (Paso A), que tuvo el
/// mismo ajuste. A diferencia del resto de la app ("no ocultar la función, gatear la acción"), acá
/// se oculta la información en sí -- es la excepción deliberada, no un descuido.
///
/// Muestra solo la vista elegida en `SelectorTipoPresupuesto` (`obra_presupuesto_config.
/// tipoPresupuesto`, ya existe y ya persiste) -- a propósito no se ven las dos juntas, para que la
/// comparación entre "con materiales" y "sin materiales" no quede servida en la misma pantalla. La
/// función de base (`calcular_factor_k_subitem`) sigue devolviendo las dos -- sin materiales
/// necesita los montos de la vista completa para copiar GG/EPP/Costo Financiero -- lo que cambia
/// acá es solo qué se renderiza.
class BloqueFactorKPartida extends StatefulWidget {
  final String obraId;
  final String subitemId;

  const BloqueFactorKPartida({Key? key, required this.obraId, required this.subitemId}) : super(key: key);

  @override
  State<BloqueFactorKPartida> createState() => _BloqueFactorKPartidaState();
}

class _BloqueFactorKPartidaState extends State<BloqueFactorKPartida> {
  final FactorKSubitemRepository _factorKRepository = FactorKSubitemRepository();
  final ObraPresupuestoConfigRepository _configRepository = ObraPresupuestoConfigRepository();
  final PerfilRepository _perfilRepository = PerfilRepository();
  final AuthService _authService = AuthService();

  bool _cargando = true;
  String? _error;
  PrecioFinalSubitem? _precioFinal;
  ObraPresupuestoConfig? _config;
  bool _esPro = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final usuarioId = _authService.usuarioActual?.id;
      final esProFuture = usuarioId != null ? _perfilRepository.esPro(usuarioId) : Future.value(false);
      final esPro = await esProFuture;

      // Free no llega a pedir el desglose -- es la información que esta pieza no le muestra (ver
      // comentario de cabecera), no hace falta gastar la llamada a calcular_factor_k_subitem.
      if (!esPro) {
        if (!mounted) return;
        setState(() {
          _esPro = false;
          _cargando = false;
        });
        return;
      }

      final precioFinalFuture = _factorKRepository.getPrecioFinal(widget.obraId, widget.subitemId);
      final configFuture = _configRepository.getConfig(widget.obraId);
      final precioFinal = await precioFinalFuture;
      final config = await configFuture;
      if (!mounted) return;
      setState(() {
        _esPro = true;
        _precioFinal = precioFinal;
        _config = config;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo calcular el Factor K de esta partida.';
        _cargando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Factor K de esta partida',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1B365D)),
          ),
          const Divider(height: 16),
          _buildContenido(),
        ],
      ),
    );
  }

  Widget _buildContenido() {
    if (_cargando) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
      );
    }

    if (!_esPro) {
      return Row(
        children: [
          Icon(Icons.workspace_premium, size: 14, color: Colors.amber[800]),
          const SizedBox(width: 6),
          const Expanded(
            child: Text(
              'Cómo se forma el precio final (porcentajes, impuestos) es una función PRO.',
              style: TextStyle(fontSize: 11, color: Colors.black54, fontStyle: FontStyle.italic),
            ),
          ),
        ],
      );
    }

    final precioFinal = _precioFinal!;
    final config = _config!;

    if (!precioFinal.completo) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          'Cargá el precio de todos los insumos de esta partida para ver el Factor K '
          '(${precioFinal.insumosConPrecio}/${precioFinal.insumosTotal}).',
          style: const TextStyle(fontSize: 12, color: Colors.black45, fontStyle: FontStyle.italic),
        ),
      );
    }

    // No es algo que la pantalla deba tolerar (ver conversación) -- si esto pasa es un bug de
    // calcular_factor_k_subitem, no un problema de datos de esta partida.
    if (!precioFinal.cierraOkConMateriales || !precioFinal.cierraOkSinMateriales) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Text(
          'Error de cálculo del Factor K en esta partida. No se muestra ningún monto -- avisá a '
          'soporte.',
          style: TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.bold),
        ),
      );
    }

    final sinMateriales = config.tipoPresupuesto == TipoPresupuesto.manoObraSola;
    return sinMateriales
        ? _buildVista(
            'SIN MATERIALES (Comp. Solo MO)',
            precioFinal.lineasSinMateriales,
            precioFinal.costoCostoSinMateriales,
            precioFinal.costoTotalTrabajoSinMateriales,
            precioFinal.precioFinalSinMateriales,
            config.aplicaImpuestos,
          )
        : _buildVista(
            'CON MATERIALES',
            precioFinal.lineasConMateriales,
            precioFinal.costoCostoConMateriales,
            precioFinal.costoTotalTrabajoConMateriales,
            precioFinal.precioFinalConMateriales,
            config.aplicaImpuestos,
          );
  }

  /// Una línea de concepto (Gastos Generales, Imprevistos, ...) siempre tiene un `baseTexto`
  /// propio de esa línea ("Costo-Costo", "Costo-Costo + GG", ...); las 4 líneas de impuesto
  /// comparten el mismo `baseTexto` fijo ("Costo Total del Trabajo") -- ese es el discriminador
  /// para separarlas acá, en vez de asumir una cantidad fija de líneas por vista.
  Widget _buildVista(
    String titulo,
    List<FactorKLineaSubitem> lineas,
    double costoCosto,
    double costoTotalTrabajo,
    double precioFinal,
    bool aplicaImpuestos,
  ) {
    final conceptos = lineas.where((l) => l.baseTexto != 'Costo Total del Trabajo').toList();
    final impuestos = lineas.where((l) => l.baseTexto == 'Costo Total del Trabajo').toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF1B365D))),
        const SizedBox(height: 4),
        _buildLineaMonto('Costo-Costo', null, null, costoCosto, destacado: false),
        for (final linea in conceptos) _buildLineaMonto(linea.concepto, linea.pct, linea.baseTexto, linea.monto),
        _buildLineaMonto('Costo Total del Trabajo', null, null, costoTotalTrabajo, destacado: true),
        if (aplicaImpuestos) ...[
          for (final linea in impuestos) _buildLineaMonto(linea.concepto, linea.pct, linea.baseTexto, linea.monto),
          _buildLineaMonto('Precio Final', null, null, precioFinal, destacado: true, grande: true),
        ],
      ],
    );
  }

  Widget _buildLineaMonto(
    String concepto,
    double? pct,
    String? baseTexto,
    double monto, {
    bool destacado = false,
    bool grande = false,
  }) {
    final etiqueta = pct != null && baseTexto != null
        ? '$concepto — ${_fmtPct(pct)}% sobre $baseTexto'
        : concepto;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              etiqueta,
              style: TextStyle(
                fontSize: grande ? 12 : 11,
                fontWeight: destacado ? FontWeight.bold : FontWeight.normal,
                color: destacado ? const Color(0xFF1B365D) : Colors.black87,
              ),
            ),
          ),
          Text(
            CurrencyFormatter.formatARS(monto),
            style: TextStyle(
              fontSize: grande ? 16 : 12,
              fontWeight: destacado ? FontWeight.bold : FontWeight.w600,
              color: const Color(0xFF1B365D),
            ),
          ),
        ],
      ),
    );
  }

  String _fmtPct(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2).replaceAll('.', ',');
}
