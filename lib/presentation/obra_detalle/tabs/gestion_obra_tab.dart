import 'package:flutter/material.dart';
import '../../../core/segurity/user_context.dart';
import '../../../data/models/certificado.dart';
import '../../../services/auth_service.dart';
import '../../../services/certificados_repository.dart';
import '../screens/carga_avance_rubros_screen.dart';
import 'cartel_firma_pendiente.dart';
import 'panel_config_certificacion.dart';

class GestionObraTab extends StatefulWidget {
  final String obraId;

  /// El contexto de permisos completo, no un booleano derivado — a diferencia de otras solapas
  /// más simples (RubrosTab recibe un solo `puedeEditarComputo`), Gestión de Obra ya necesita más
  /// de un chequeo de rol acá (config de certificación, cargar avance, ver montos) y va a seguir
  /// creciendo (libros, adicionales, curva de avance) — pasar el contexto entero evita agregar un
  /// booleano nuevo en `PresupuestosScreen` cada vez. Gestión de Obra no tiene gate de PRO
  /// (decisión de negocio: es gratuita para todos), así que todo lo de acá es puramente de rol.
  final UserContext? userContext;

  const GestionObraTab({
    Key? key,
    required this.obraId,
    required this.userContext,
  }) : super(key: key);

  @override
  State<GestionObraTab> createState() => _GestionObraTabState();
}

class _GestionObraTabState extends State<GestionObraTab> {
  final CertificadosRepository _certificadosRepository = CertificadosRepository();
  final AuthService _authService = AuthService();

  List<Certificado> _certificados = [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarCertificados();
  }

  Future<void> _cargarCertificados() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final certs = await _certificadosRepository.getCertificadosDeObra(widget.obraId);
      if (!mounted) return;
      setState(() {
        _certificados = certs;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar los certificados de esta obra.';
        _cargando = false;
      });
    }
  }

  Future<void> _abrirConfigCertificacion() async {
    await showDialog<bool>(
      context: context,
      builder: (_) => PanelConfigCertificacion(
        obraId: widget.obraId,
        puedeEditar: widget.userContext?.puedeEditarConfigCertificacion == true,
      ),
    );
    // No hace falta recargar _certificados: la config de certificación (modelo, plazo, anticipo,
    // fondo de reparo, monto total contratado) no aparece en ninguna tarjeta de esta lista.
  }

  /// "Nuevo certificado" — si ya hay un Borrador abierto, lleva a ese en vez de crear otro (es un
  /// certificado por vez, ahora también forzado por el índice único parcial de la 0053: un
  /// segundo intento de crear fallaría en la base igual, pero chequear acá primero evita ese viaje
  /// al servidor y, sobre todo, evita perderle el período recién tipeado al usuario por un error
  /// que se podía anticipar).
  Future<void> _onNuevoCertificado() async {
    final borradorExistente = await _certificadosRepository.getBorradorAbierto(widget.obraId);
    if (borradorExistente != null) {
      if (!mounted) return;
      await _abrirCargaAvance(borradorExistente);
      return;
    }

    final periodo = await _pedirPeriodo();
    if (periodo == null) return; // canceló

    final usuarioId = _authService.usuarioActual?.id;
    if (usuarioId == null) return;

    try {
      final nuevo = await _certificadosRepository.crearCertificadoBorrador(
        obraId: widget.obraId,
        periodo: periodo,
        usuarioId: usuarioId,
      );
      if (!mounted) return;
      await _abrirCargaAvance(nuevo);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo crear el certificado.')),
      );
    }
  }

  /// Sugiere el mes/año actual como período — sin `package:intl` (no es una dependencia limpia de
  /// este proyecto, ver CLAUDE.md), doce nombres a mano alcanzan. El usuario puede cambiarlo antes
  /// de crear.
  Future<String?> _pedirPeriodo() async {
    const meses = [
      'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
      'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
    ];
    final ahora = DateTime.now();
    final mes = meses[ahora.month - 1];
    final sugerido = '${mes[0].toUpperCase()}${mes.substring(1)} ${ahora.year}';
    final controller = TextEditingController(text: sugerido);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nuevo certificado', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Período', isDense: true),
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          TextButton(
            onPressed: () {
              final texto = controller.text.trim();
              Navigator.pop(ctx, texto.isEmpty ? null : texto);
            },
            child: const Text('Crear'),
          ),
        ],
      ),
    );
  }

  Future<void> _abrirCargaAvance(Certificado certificado) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CargaAvanceRubrosScreen(
          obraId: widget.obraId,
          certificado: certificado,
          userContext: widget.userContext,
        ),
      ),
    );
    // Por si el certificado se emitió (piezas futuras) o cambió algo mientras se cargaba avance.
    await _cargarCertificados();
  }

  String _fmt(double monto) {
    final valorInt = monto.round();
    final str = valorInt.toString();
    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    final formateado = str.replaceAllMapped(reg, (Match m) => '${m[1]}.');
    return '\$ $formateado';
  }

  String _fmtFecha(DateTime? fecha) {
    if (fecha == null) return '—';
    return '${fecha.day}/${fecha.month}/${fecha.year}';
  }

  Color _getColorEstado(EstadoCertificado estado) {
    switch (estado) {
      case EstadoCertificado.borrador:
        return Colors.orange.shade700;
      case EstadoCertificado.emitido:
        return Colors.blue.shade700;
      case EstadoCertificado.leido:
        return Colors.indigo.shade700;
      case EstadoCertificado.pagado:
        return Colors.green.shade700;
      case EstadoCertificado.impactadoCerrado:
        return Colors.grey.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _cargarCertificados,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Visible para admin_maestro/profesional/constructor — los 3 mismos roles que
                // certificados_insert/certificados_update (0009/0010) ya autorizan a crear o
                // seguir cargando un Borrador. Nadie más lo ve: un Cliente/Apoderado/Veedor no
                // puede iniciar esto, mostrarlo deshabilitado no aportaría nada.
                if (widget.userContext?.puedeCargarAvance == true)
                  OutlinedButton.icon(
                    onPressed: _onNuevoCertificado,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Nuevo certificado', style: TextStyle(fontSize: 11)),
                    style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1B365D)),
                  )
                else
                  const SizedBox.shrink(),
                OutlinedButton.icon(
                  onPressed: _abrirConfigCertificacion,
                  icon: const Icon(Icons.settings_outlined, size: 16),
                  label: const Text('Configuración', style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1B365D)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Solo quien tiene autoridad para subir el PDF (subir_pdf_firmado_certificado, 0011:
            // admin_maestro/profesional) — mostrárselo al Constructor sería un botón que le falla
            // siempre, no una información útil para él.
            if (widget.userContext?.puedeEmitirCertificado == true)
              CartelFirmaPendiente(obraId: widget.obraId),
            const Text(
              'Historial de Certificados',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1B365D)),
            ),
            const SizedBox(height: 12),
            _buildContenido(),
          ],
        ),
      ),
    );
  }

  Widget _buildContenido() {
    if (_cargando) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.error_outline, color: Colors.red.shade400, size: 32),
              const SizedBox(height: 8),
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
            ],
          ),
        ),
      );
    }
    if (_certificados.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.description_outlined, color: Colors.black26, size: 32),
              SizedBox(height: 8),
              Text(
                'Todavía no hay certificados cargados para esta obra.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
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
                    Expanded(
                      child: Text(
                        'Certificado Nº ${cert.numero.toString().padLeft(3, '0')} - ${cert.periodo}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1B365D)),
                      ),
                    ),
                    Chip(
                      label: Text(
                        cert.estado.label,
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                      backgroundColor: _getColorEstado(cert.estado),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // Gateado por rol, no solo estético: el Constructor "vista operativa" no ve
                // montos según la matriz de permisos — encontrado como agujero real al construir
                // la pieza 3 (esta pantalla no tenía ningún UserContext hasta ahora), cerrado acá
                // de una vez ya que se está conectando UserContext a este archivo por primera vez.
                if (widget.userContext?.puedeVerMontosGestionObra == true)
                  Text(
                    'Monto Certificado: ${_fmt(cert.monto)}',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black54),
                  ),
                Text(
                  'Emisión: ${_fmtFecha(cert.fechaEmision)}${cert.diasPlazoPago != null ? ' | Plazo: ${cert.diasPlazoPago} días' : ''}',
                  style: const TextStyle(fontSize: 11, color: Colors.black45),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
