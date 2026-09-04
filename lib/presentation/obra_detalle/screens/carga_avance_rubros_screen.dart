import 'package:flutter/material.dart';
import '../../../core/segurity/user_context.dart';
import '../../../data/models/certificado.dart';
import '../../../data/models/certificado_subitem_avance.dart';
import '../../../data/models/rubro_catalogo.dart';
import '../../../services/auth_service.dart';
import '../../../services/certificado_subitems_avance_repository.dart';
import '../../../services/obra_subitems_repository.dart';
import '../../../services/rubros_repository.dart';
import 'carga_avance_subitems_screen.dart';

/// Pantalla de carga de avance por partida (Modelo A) — Gestión de Obra, pieza 3. Lista de
/// rubros con subítems tildados en esta obra, mismo patrón de navegación que `RubrosTab`: se
/// toca un rubro, se empuja una pantalla nueva con sus subítems (`CargaAvanceSubitemsScreen`),
/// nunca un acordeón inline — un rubro abierto por vez sale solo, porque solo hay una pantalla en
/// la pila a la vez.
///
/// Ver supabase/migrations/0052_certificado_subitems_avance.sql para el diseño completo de datos.
class CargaAvanceRubrosScreen extends StatefulWidget {
  final String obraId;
  final Certificado certificado;
  final UserContext? userContext;

  const CargaAvanceRubrosScreen({
    Key? key,
    required this.obraId,
    required this.certificado,
    required this.userContext,
  }) : super(key: key);

  @override
  State<CargaAvanceRubrosScreen> createState() => _CargaAvanceRubrosScreenState();
}

class _CargaAvanceRubrosScreenState extends State<CargaAvanceRubrosScreen> {
  final ObraSubitemsRepository _obraSubitemsRepository = ObraSubitemsRepository();
  final RubrosRepository _rubrosRepository = RubrosRepository();
  final CertificadoSubitemsAvanceRepository _avanceRepository = CertificadoSubitemsAvanceRepository();
  final AuthService _authService = AuthService();

  bool _cargando = true;
  String? _error;
  List<RubroCatalogo> _rubrosConTildados = [];
  ResumenCertificadoObra? _resumen;
  double _montoEnCurso = 0;

  bool get _puedeVerMontos => widget.userContext?.puedeVerMontosGestionObra == true;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final usuarioId = _authService.usuarioActual?.id;
      final conteoFuture = _obraSubitemsRepository.getConteoTildadosPorObra(widget.obraId);
      final rubrosFuture = usuarioId == null
          ? _rubrosRepository.getCatalogoOficial()
          : _rubrosRepository.getCatalogoCompleto(usuarioId);
      final avancesFuture = _avanceRepository.getAvancesDeCertificado(widget.certificado.id);
      // El resumen es puro monto — no tiene sentido pedirlo si el usuario no lo puede ver.
      final resumenFuture = _puedeVerMontos ? _avanceRepository.getResumen(widget.obraId) : null;

      final conteo = await conteoFuture;
      final rubros = await rubrosFuture;
      final avances = await avancesFuture;
      final resumen = resumenFuture == null ? null : await resumenFuture;

      if (!mounted) return;
      setState(() {
        _rubrosConTildados = rubros.where((r) => (conteo[r.id] ?? 0) > 0).toList();
        _montoEnCurso = avances.fold(0.0, (sum, a) => sum + a.montoPeriodo);
        _resumen = resumen;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar el certificado.';
        _cargando = false;
      });
    }
  }

  String _fmt(double monto) {
    final valorInt = monto.round();
    final str = valorInt.toString();
    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    final formateado = str.replaceAllMapped(reg, (Match m) => '${m[1]}.');
    return '\$ $formateado';
  }

  /// No hay todavía un mecanismo de saltar de una pantalla empujada a una solapa puntual de
  /// `PresupuestosScreen` (nada en el proyecto lo necesitó hasta ahora) — cierra esta pantalla y
  /// vuelve a Gestión de Obra, con el aviso de adónde ir. Marcado para revisar si en algún
  /// momento hace falta un salto directo de verdad.
  void _irAResumen() {
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Abrí la solapa Resumen para ver el detalle completo.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Certificado Nº ${widget.certificado.numero.toString().padLeft(3, '0')} — ${widget.certificado.periodo}',
          style: const TextStyle(fontSize: 15),
        ),
        backgroundColor: const Color(0xFF1B365D),
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _cargarDatos,
        child: _buildContenido(),
      ),
    );
  }

  Widget _buildContenido() {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                Icon(Icons.error_outline, color: Colors.red.shade400, size: 32),
                const SizedBox(height: 8),
                Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
              ],
            ),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.all(12.0),
      children: [
        _buildResumenChico(),
        if (_rubrosConTildados.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Text(
                'Esta obra todavía no tiene subítems tildados en la Solapa 1 — no hay nada que certificar todavía.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54, fontSize: 13),
              ),
            ),
          )
        else
          ..._rubrosConTildados.map(_buildFilaRubro),
      ],
    );
  }

  /// "Certificado y pagado a la fecha" (histórico de la obra, solo lectura acá — el detalle
  /// completo vive en Resumen) + el monto de ESTE certificado, actualizándose mientras se carga.
  /// Ninguno de los dos aparece si el usuario no ve montos (Constructor/Veedor) — no hay versión
  /// "sin plata" de un resumen que es, de punta a punta, sobre plata.
  Widget _buildResumenChico() {
    if (!_puedeVerMontos) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          'Certificado Nº ${widget.certificado.numero} — en borrador',
          style: const TextStyle(fontSize: 12, color: Colors.black54, fontStyle: FontStyle.italic),
        ),
      );
    }
    final resumen = _resumen;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: const Color(0xFFEAF1FB),
      child: InkWell(
        onTap: _irAResumen,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Certificado y pagado a la fecha',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1B365D))),
                  const Icon(Icons.chevron_right, size: 16, color: Color(0xFF1B365D)),
                ],
              ),
              if (resumen != null) ...[
                const SizedBox(height: 4),
                Text('Certificado: ${_fmt(resumen.totalCertificado)}  ·  Pagado: ${_fmt(resumen.totalPagado)}',
                    style: const TextStyle(fontSize: 11, color: Colors.black87)),
              ],
              const Divider(height: 16),
              Text(
                'Este certificado (en carga): ${_fmt(_montoEnCurso)}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1B365D)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilaRubro(RubroCatalogo rubro) {
    return Card(
      margin: const EdgeInsets.only(bottom: 4.0),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        title: Text(
          rubro.nombre,
          style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1B365D), fontSize: 13),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.black38),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CargaAvanceSubitemsScreen(
                obraId: widget.obraId,
                rubro: rubro,
                certificado: widget.certificado,
                userContext: widget.userContext,
              ),
            ),
          );
          await _cargarDatos(); // el monto en curso pudo cambiar mientras se cargaba avance
        },
      ),
    );
  }
}
