import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/segurity/user_context.dart';
import '../../../data/models/certificado.dart';
import '../../../data/models/certificado_subitem_avance.dart';
import '../../../data/models/rubro_catalogo.dart';
import '../../../services/auth_service.dart';
import '../../../services/certificado_subitems_avance_repository.dart';
import '../../../services/certificados_repository.dart';
import '../../../services/obra_subitems_repository.dart';
import '../../../services/rubros_repository.dart';
import 'carga_avance_subitems_screen.dart';
import 'vista_previa_certificado_screen.dart';

/// Pantalla de carga de avance por partida (Modelo A) — Gestión de Obra, pieza 3. Lista de
/// rubros con subítems tildados en esta obra, mismo patrón de navegación que `RubrosTab`: se
/// toca un rubro, se empuja una pantalla nueva con sus subítems (`CargaAvanceSubitemsScreen`),
/// nunca un acordeón inline — un rubro abierto por vez sale solo, porque solo hay una pantalla en
/// la pila a la vez.
///
/// Acá vive también el ida y vuelta del acuerdo entre partes (`0124`): proponer el avance cargado,
/// darle conformidad o devolverlo con un comentario. Va en esta pantalla y no en el detalle a
/// propósito -- se conforma al lado de los números que se están conformando.
///
/// Ver supabase/migrations/0052_certificado_subitems_avance.sql para el diseño completo de datos, y
/// docs/certificacion_acuerdo_partes_diagnostico.md §2.1 para el acuerdo.
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
  final CertificadosRepository _certificadosRepository = CertificadosRepository();
  final AuthService _authService = AuthService();

  bool _cargando = true;
  String? _error;
  List<RubroCatalogo> _rubrosConTildados = [];
  ResumenCertificadoObra? _resumen;
  double _montoEnCurso = 0;

  /// El certificado se relee de la base en cada carga, en vez de confiar en el que llegó por
  /// parámetro: el acuerdo lo mueve la OTRA parte desde otro dispositivo, así que la foto que trajo
  /// la pantalla anterior envejece sola (mismo criterio que ya se aplicó en
  /// `DetalleCertificadoScreen`, 2026-09-13). Si la relectura falla se sigue con la foto.
  late Certificado _cert;

  /// Si la obra no tiene contraparte, el circuito del acuerdo no se muestra y emitir funciona como
  /// antes de la 0124 -- una obra de una sola persona no cambia en nada.
  bool _hayContraparte = false;
  bool _puedeConformar = false;
  bool _accionando = false;

  bool get _puedeVerMontos => widget.userContext?.puedeVerMontosGestionObra == true;
  bool get _puedeCargarAvance => widget.userContext?.puedeCargarAvance == true;
  bool get _esQuienPropuso =>
      _cert.propuestoPor != null && _cert.propuestoPor == _authService.usuarioActual?.id;

  @override
  void initState() {
    super.initState();
    _cert = widget.certificado;
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
      final avancesFuture = _avanceRepository.getAvancesDeCertificado(_cert.id);
      // El resumen es puro monto — no tiene sentido pedirlo si el usuario no lo puede ver.
      final resumenFuture = _puedeVerMontos ? _avanceRepository.getResumen(widget.obraId) : null;

      final conteo = await conteoFuture;
      final rubros = await rubrosFuture;
      final avances = await avancesFuture;
      final resumen = resumenFuture == null ? null : await resumenFuture;
      final cert = await _certificadoFresco();
      final acuerdo = await _estadoDelAcuerdo(cert);

      if (!mounted) return;
      setState(() {
        _rubrosConTildados = rubros.where((r) => (conteo[r.id] ?? 0) > 0).toList();
        _montoEnCurso = avances.fold(0.0, (sum, a) => sum + a.montoPeriodo);
        _resumen = resumen;
        _cert = cert;
        _hayContraparte = acuerdo.$1;
        _puedeConformar = acuerdo.$2;
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

  /// Silencioso ante error: si la relectura falla se sigue con lo último que se sabía. No abrir la
  /// pantalla porque no se pudo refrescar el encabezado sería peor que mostrarlo un poco viejo.
  Future<Certificado> _certificadoFresco() async {
    try {
      return await _certificadosRepository.getPorId(_cert.id);
    } catch (_) {
      return _cert;
    }
  }

  /// (¿hay contraparte?, ¿el que mira puede conformar?). Las dos las contesta la base: dependen de
  /// si la obra tiene profesional activo y de quién propuso, que no es algo que `UserContext` sepa.
  /// Ante un error las dos dan false -- se esconde el circuito, nunca se ofrece un botón de más.
  Future<(bool, bool)> _estadoDelAcuerdo(Certificado cert) async {
    if (cert.estado != EstadoCertificado.borrador) return (false, false);
    try {
      final hay = await _certificadosRepository.hayContraparte(
        obraId: widget.obraId,
        propuestoPor: cert.propuestoPor,
      );
      final puede = cert.acuerdoEstado == AcuerdoCertificado.propuesto &&
          await _certificadosRepository.puedeDarConformidad(cert.id);
      return (hay, puede);
    } catch (_) {
      return (false, false);
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
          'Certificado Nº ${_cert.numeroFormateado} — ${_cert.periodo}',
          style: const TextStyle(fontSize: 15),
        ),
        backgroundColor: const Color(0xFF1B365D),
        foregroundColor: Colors.white,
        // Vista previa + Emitir viven en su propia pantalla — mismos 2 roles que exige
        // emitir_certificado (admin_maestro/profesional), no los mismos que pueden cargar avance
        // (que suma constructor): cargar es de posta entre los 3, emitir es autoridad propia.
        actions: [
          if (widget.userContext?.puedeEmitirCertificado == true)
            TextButton.icon(
              onPressed: _abrirVistaPrevia,
              icon: const Icon(Icons.visibility_outlined, size: 18, color: Colors.white),
              label: const Text('Vista previa', style: TextStyle(fontSize: 12, color: Colors.white)),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _cargarDatos,
        child: _buildContenido(),
      ),
    );
  }

  Future<void> _abrirVistaPrevia() async {
    final emitido = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => VistaPreviaCertificadoScreen(
          obraId: widget.obraId,
          certificado: _cert,
          userContext: widget.userContext,
        ),
      ),
    );
    // Solo si se emitió de verdad: el certificado pasa de estado y esta pantalla ya no tiene
    // sentido seguir mostrándola como "Borrador en curso" — se vuelve a Gestión de Obra, que
    // recarga la lista. Si el usuario solo miró la vista previa y volvió (sin emitir), se queda acá.
    if (emitido != true || !mounted) return;
    Navigator.pop(context);
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
        _buildBloqueAcuerdo(),
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
  /// Ninguno de los dos aparece si el usuario no ve montos (Veedor; el Constructor los ve desde el
  /// cambio de matriz de 2026-09-12) — no hay versión
  /// "sin plata" de un resumen que es, de punta a punta, sobre plata.
  Widget _buildResumenChico() {
    if (!_puedeVerMontos) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          'Certificado Nº ${_cert.numeroFormateado} — en borrador',
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

  // ===========================================================================
  // Acuerdo entre partes (0124)
  // ===========================================================================

  /// Corre una de las tres acciones del circuito y recarga. El mensaje de error se muestra tal cual
  /// viene de la base: los `raise exception` de estas tres funciones están escritos en español y
  /// dicen qué hacer ("la conformidad la da la otra parte", "la devolución necesita un comentario").
  Future<void> _accionDeAcuerdo(Future<void> Function() accion, String fallback) async {
    setState(() => _accionando = true);
    try {
      await accion();
      if (!mounted) return;
      await _cargarDatos();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      await _cargarDatos(); // el estado real pudo haber cambiado desde el otro lado
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(fallback)));
    } finally {
      if (mounted) setState(() => _accionando = false);
    }
  }

  Future<void> _proponer() => _accionDeAcuerdo(
        () => _certificadosRepository.proponerAvance(_cert.id),
        'No se pudo proponer el avance.',
      );

  Future<void> _darConformidad() => _accionDeAcuerdo(
        () => _certificadosRepository.darConformidad(_cert.id),
        'No se pudo registrar la conformidad.',
      );

  /// El comentario es obligatorio del lado del servidor; acá solo se evita el viaje si viene vacío,
  /// mismo patrón que el motivo de la anulación en `GestionObraTab`.
  Future<void> _devolver() async {
    final controller = TextEditingController();
    final comentario = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Devolver para corregir',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Qué hay que revisar. Lo va a ver quien propuso el avance, junto al borrador.',
              style: TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Comentario', isDense: true),
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          TextButton(
            onPressed: () {
              final texto = controller.text.trim();
              Navigator.pop(ctx, texto.isEmpty ? null : texto);
            },
            child: const Text('Devolver'),
          ),
        ],
      ),
    );
    if (comentario == null) return;
    await _accionDeAcuerdo(
      () => _certificadosRepository.devolverAvance(
        certificadoId: _cert.id,
        comentario: comentario,
      ),
      'No se pudo devolver la propuesta.',
    );
  }

  /// El estado del acuerdo y lo que se puede hacer con él. No aparece si la obra no tiene
  /// contraparte: ahí no hay acuerdo que registrar, y un bloque explicando que no hay nadie del otro
  /// lado sería ruido en el caso más común.
  Widget _buildBloqueAcuerdo() {
    if (!_hayContraparte || _cert.estado != EstadoCertificado.borrador) {
      return const SizedBox.shrink();
    }

    final String texto;
    final List<Widget> botones;
    switch (_cert.acuerdoEstado) {
      case AcuerdoCertificado.propuesto:
        if (_puedeConformar) {
          texto = 'Te proponen este avance para revisar${_fechaCorta(_cert.propuestaFecha)}.';
          botones = [
            _botonAcuerdo('Conforme', _darConformidad, principal: true),
            _botonAcuerdo('Devolver con comentario', _devolver),
          ];
        } else {
          texto = 'Propuesto para revisión${_fechaCorta(_cert.propuestaFecha)}. '
              'Esperando la conformidad de la otra parte.';
          botones = const [];
        }
      case AcuerdoCertificado.conforme:
        texto = _esQuienPropuso
            ? 'Conforme${_fechaCorta(_cert.conformeFecha)}. Lo emite la otra parte: el que propone '
                'el avance no lo emite.'
            : 'Conforme${_fechaCorta(_cert.conformeFecha)}. Ya se puede emitir.';
        botones = const [];
      case AcuerdoCertificado.enCarga:
        texto = _cert.fueDevuelto
            ? 'Devuelto para corregir: ${_cert.comentarioDevolucion}'
            : 'Este avance todavía no se propuso para revisión. Se emite después de que la otra '
                'parte lo conforme.';
        botones = [
          if (_puedeCargarAvance)
            _botonAcuerdo('Proponer para revisión', _proponer, principal: true),
        ];
    }

    final devuelto = _cert.fueDevuelto;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: devuelto ? const Color(0xFFFFF4E5) : const Color(0xFFEDF3EC),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  devuelto ? Icons.undo : Icons.handshake_outlined,
                  size: 15,
                  color: devuelto ? Colors.orange.shade800 : const Color(0xFF1B365D),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _cert.acuerdoEstado.label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: devuelto ? Colors.orange.shade900 : const Color(0xFF1B365D),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(texto, style: const TextStyle(fontSize: 12.5, color: Colors.black87)),
            if (botones.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 4, children: botones),
            ],
          ],
        ),
      ),
    );
  }

  Widget _botonAcuerdo(String texto, Future<void> Function() alTocar, {bool principal = false}) {
    final onPressed = _accionando ? null : () => alTocar();
    if (!principal) {
      return TextButton(
        onPressed: onPressed,
        child: Text(texto, style: const TextStyle(fontSize: 12)),
      );
    }
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF1B365D),
        foregroundColor: Colors.white,
        visualDensity: VisualDensity.compact,
      ),
      child: Text(texto, style: const TextStyle(fontSize: 12)),
    );
  }

  /// " el 13/09" o vacío -- el texto tiene que leerse igual cuando la fecha no está.
  String _fechaCorta(DateTime? f) {
    if (f == null) return '';
    final l = f.toLocal();
    return ' el ${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}';
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
                certificado: _cert,
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
