import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/segurity/user_context.dart';
import '../../../core/utils/conversion_dolar.dart';
import '../../../data/models/certificado.dart';
import '../../../services/auth_service.dart';
import '../../../services/certificados_repository.dart';
import '../../../services/indices_economicos_repository.dart';
import '../../../services/obras_repository.dart';
import '../screens/carga_avance_rubros_screen.dart';
import '../screens/detalle_certificado_screen.dart';
import '../screens/quitas_demasias_screen.dart';
import 'cartel_firma_pendiente.dart';
import 'panel_config_certificacion.dart';
import 'presupuesto_estado_panel.dart';

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
  final ObrasRepository _obrasRepository = ObrasRepository();
  final IndicesEconomicosRepository _indicesRepository = IndicesEconomicosRepository();

  List<Certificado> _certificados = [];
  bool _cargando = true;
  String? _error;
  String _moneda = 'ARS';
  double _cotizacionHoy = 0;

  @override
  void initState() {
    super.initState();
    _cargarCertificados();
    _cargarMoneda();
  }

  /// Silencioso ante error, mismo criterio que el resto de los datos secundarios de esta solapa
  /// (`PresupuestoEstadoPanel`, `CartelFirmaPendiente`): si falla, los montos siguen mostrándose
  /// en ARS (moneda nace en 'ARS'), nunca rompe la lista de certificados por esto.
  Future<void> _cargarMoneda() async {
    try {
      final monedaFuture = _obrasRepository.getMoneda(widget.obraId);
      final cotizacionFuture = _indicesRepository.getCotizacionDolar();
      final moneda = await monedaFuture;
      final cotizacion = await cotizacionFuture;
      if (!mounted) return;
      setState(() {
        _moneda = moneda;
        _cotizacionHoy = cotizacion?.promedio ?? 0;
      });
    } catch (_) {
      // Silencioso -- ver comentario del método.
    }
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

  Future<void> _abrirQuitasDemasias() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QuitasDemasiasScreen(obraId: widget.obraId, userContext: widget.userContext),
      ),
    );
    // Aprobar una demasía/quita cambia obra_subitems.cantidad -- no afecta a esta lista de
    // certificados, así que no hace falta recargar acá (a diferencia de _abrirDetalle/
    // _abrirCargaAvance, que sí tocan certificados).
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

  /// `montoArs`: el valor tal cual sale de `certificados` -- siempre en pesos. Convierte a la
  /// moneda de la obra antes de formatear -- un certificado YA EMITIDO usa su propia cotización
  /// congelada al emitir (`0107`), no la de hoy (mismo criterio que `DetalleCertificadoScreen`,
  /// docs/gestion_obra_estado_real_auditoria.md, intercambio del 2026-09-11); un Borrador (monto
  /// en 0, sin nada congelado todavía) cae a la cotización de hoy.
  String _fmt(double montoArs, Certificado cert) {
    final cotizacion =
        (cert.estado != EstadoCertificado.borrador && cert.cotizacionDolarPromedioAlEmitir != null)
            ? cert.cotizacionDolarPromedioAlEmitir!
            : _cotizacionHoy;
    final convertido = convertirArsAMoneda(montoArs, _moneda, cotizacion);
    final valorInt = convertido.round();
    final str = valorInt.toString();
    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    final formateado = str.replaceAllMapped(reg, (Match m) => '${m[1]}.');
    return _moneda == 'USD' ? 'USD $formateado' : '\$ $formateado';
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
      case EstadoCertificado.anulado:
        return Colors.red.shade700;
    }
  }

  /// Propone anular un certificado emitido/leído — botón visible solo para profesional/constructor
  /// (0056: la dupla que arma el borrador, nunca el cliente). El motivo es obligatorio del lado del
  /// servidor; acá solo se evita el viaje si viene vacío.
  Future<void> _proponerAnulacion(Certificado cert) async {
    final controller = TextEditingController();
    final motivo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Anular Certificado Nº ${cert.numero}',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Motivo', isDense: true),
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          TextButton(
            onPressed: () {
              final texto = controller.text.trim();
              Navigator.pop(ctx, texto.isEmpty ? null : texto);
            },
            child: const Text('Proponer'),
          ),
        ],
      ),
    );
    if (motivo == null) return;

    try {
      await _certificadosRepository.proponerAnulacion(certificadoId: cert.id, motivo: motivo);
      if (!mounted) return;
      await _cargarCertificados();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo proponer la anulación.')),
      );
    }
  }

  /// Aprueba o rechaza una anulación propuesta — visible solo para quien puede resolverla (el otro
  /// lado de la dupla, nunca quien propuso; ese chequeo final lo hace la función del lado del
  /// servidor, acá solo se oculta el botón para no ofrecer una acción que va a fallar seguro).
  Future<void> _resolverAnulacion(Certificado cert, bool aprobar) async {
    String? motivoRechazo;
    if (!aprobar) {
      final controller = TextEditingController();
      final resultado = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Rechazar anulación', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Motivo (opcional)', isDense: true),
            style: const TextStyle(fontSize: 13),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Volver')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Rechazar'),
            ),
          ],
        ),
      );
      if (resultado == null) return; // "Volver" — no confundir con motivo vacío
      motivoRechazo = resultado.isEmpty ? null : resultado;
    } else {
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Aprobar anulación', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          content: Text(
            'El Certificado Nº ${cert.numero} pasa a Anulado y se crea un borrador de reemplazo '
            'con el mismo número para corregirlo. ¿Confirmás?',
            style: const TextStyle(fontSize: 13),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Aprobar')),
          ],
        ),
      );
      if (confirmar != true) return;
    }

    try {
      await _certificadosRepository.resolverAnulacion(
        certificadoId: cert.id,
        aprobar: aprobar,
        motivoRechazo: motivoRechazo,
      );
      if (!mounted) return;
      await _cargarCertificados();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo resolver la anulación.')),
      );
    }
  }

  /// Bloque de la anulación propuesta y pendiente — quien propuso ve un aviso de espera, el otro
  /// lado de la dupla (si tiene el rol y no es quien propuso) ve los botones de Aprobar/Rechazar.
  /// Un tercero (Cliente, Veedor, Admin Maestro) no ve ninguna acción, solo lo que ya muestra el
  /// chip de estado — el circuito de anulación es exclusivamente entre profesional y constructor.
  Widget _buildBloqueAnulacionPendiente(Certificado cert) {
    final usuarioActualId = _authService.usuarioActual?.id;
    final esQuienPropuso = cert.anulacionPropuestaPor != null && cert.anulacionPropuestaPor == usuarioActualId;
    final puedeResolver = widget.userContext?.puedeGestionarAnulacionCertificado == true && !esQuienPropuso;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Anulación propuesta: ${cert.anulacionMotivo ?? ''}',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.red.shade900),
          ),
          if (esQuienPropuso)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Esperando que la otra parte apruebe o rechace.',
                style: TextStyle(fontSize: 11, color: Colors.red.shade700),
              ),
            )
          else if (puedeResolver)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => _resolverAnulacion(cert, true),
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
                    child: const Text('Aprobar', style: TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(width: 16),
                  TextButton(
                    onPressed: () => _resolverAnulacion(cert, false),
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
                    child: Text('Rechazar', style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
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
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              runSpacing: 6,
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
                  ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Visible para cualquiera -- es informativo para todos (el propietario se
                    // entera de una demasía/quita comentando ahí, no aprobándola, docs/
                    // adicionales_quitas_demasias_diagnostico.md §6). Aprobar/rechazar/crear se
                    // gatean adentro de la pantalla, no acá.
                    OutlinedButton.icon(
                      onPressed: () => _abrirQuitasDemasias(),
                      icon: const Icon(Icons.rule_outlined, size: 16),
                      label: const Text('Quitas y Demasías', style: TextStyle(fontSize: 11)),
                      style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1B365D)),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _abrirConfigCertificacion,
                      icon: const Icon(Icons.settings_outlined, size: 16),
                      label: const Text('Configuración', style: TextStyle(fontSize: 11)),
                      style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1B365D)),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Presentar (con validez), aviso de vencido + actualizar, y congelar al firmar --
            // docs/presupuesto_congelado_validez_modelo_a_diseno.md. Visible para cualquiera (el
            // estado es informativo para todos); los botones de acción se ocultan solos adentro
            // del panel para quien no tiene puedeEditarComputo — mismo par (admin_maestro/
            // profesional) que ya edita obra_subitems y que cerró la ambigüedad B del diseño.
            PresupuestoEstadoPanel(
              obraId: widget.obraId,
              puedeGestionar: widget.userContext?.puedeEditarComputo == true,
            ),
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
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            // Corregido (Seba, al probar): un Borrador tiene que poder tocarse siempre -- es lo
            // que permite corregir antes de emitir. Antes de esta pieza tocar la tarjeta no hacía
            // nada (el único camino era el botón "Nuevo certificado" de arriba); ahora que el
            // resto de la lista SÍ responde al toque, un Borrador que no responde se siente
            // bloqueado, no "sin cambios". Borrador -> misma pantalla de carga de avance que ya
            // usa "Nuevo certificado" para reabrirlo; cualquier otro estado -> el detalle nuevo
            // (Leído/Pagado/Impactado).
            onTap: cert.estado == EstadoCertificado.borrador
                ? () => _abrirCargaAvance(cert)
                : () => _abrirDetalle(cert),
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
                        // (vN) solo a partir de la 2ª versión — un certificado nunca anulado no
                        // necesita distinguirse de nada, agregarlo siempre sería ruido sin motivo.
                        'Certificado Nº ${cert.numero.toString().padLeft(3, '0')}'
                        '${cert.version > 1 ? ' (v${cert.version})' : ''} - ${cert.periodo}',
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
                if (widget.userContext?.puedeVerMontosGestionObra == true) ...[
                  Text(
                    'Monto Certificado: ${_fmt(cert.monto, cert)}',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black54),
                  ),
                  // Desglose pactado/ajuste CAC (docs/cac_conectado_modelo_a_diseno.md §9,
                  // ambigüedad B) -- solo si hay algo que explicar: montoPactado null son
                  // certificados emitidos antes de esa migración (sin desglose guardado), y monto
                  // == montoPactado es una obra sin CAC o sin ajuste ese mes -- en los dos casos no
                  // hay nada nuevo que esta línea agregue.
                  if (cert.montoPactado != null && cert.monto != cert.montoPactado)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'Pactado ${_fmt(cert.montoPactado!, cert)} · Ajuste CAC '
                        '${_fmt(cert.monto - cert.montoPactado!, cert)}',
                        style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade600),
                      ),
                    ),
                ],
                Text(
                  'Emisión: ${_fmtFecha(cert.fechaEmision)}${cert.diasPlazoPago != null ? ' | Plazo: ${cert.diasPlazoPago} días' : ''}',
                  style: const TextStyle(fontSize: 11, color: Colors.black45),
                ),
                // Visible para cualquiera que ya vea el certificado (no gateado por rol): la
                // anulación queda en el historial con motivo, nunca se borra (0056) — es
                // información pública del certificado, no parte del circuito de propuesta/
                // resolución en sí (eso sí está gateado, ver más abajo).
                if (cert.estado == EstadoCertificado.anulado && cert.anulacionMotivo != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Anulado — ${cert.anulacionMotivo}',
                      style: TextStyle(fontSize: 11, color: Colors.red.shade700, fontStyle: FontStyle.italic),
                    ),
                  ),
                if (cert.anulacionEstado == 'propuesta') _buildBloqueAnulacionPendiente(cert),
                if (widget.userContext?.puedeGestionarAnulacionCertificado == true &&
                    (cert.estado == EstadoCertificado.emitido || cert.estado == EstadoCertificado.leido) &&
                    cert.anulacionEstado != 'propuesta')
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => _proponerAnulacion(cert),
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
                      child: Text('Anular', style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
                    ),
                  ),
              ],
            ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _abrirDetalle(Certificado cert) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DetalleCertificadoScreen(
          obraId: widget.obraId,
          certificado: cert,
          userContext: widget.userContext,
        ),
      ),
    );
    // Recarga siempre al volver, no solo si se marcó algo explícito: "Leído" pasa solo al abrir
    // el detalle, sin que el usuario haga nada -- el historial tiene que reflejar eso también si
    // el usuario solo miró y volvió sin marcar nada más.
    await _cargarCertificados();
  }
}
