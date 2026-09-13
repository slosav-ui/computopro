import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/segurity/user_context.dart';
import '../../../core/utils/conversion_dolar.dart';
import '../../../data/models/certificado.dart';
import '../../../services/certificados_repository.dart';
import '../../../services/indices_economicos_repository.dart';
import '../../../services/obras_repository.dart';

/// Detalle de un certificado YA EMITIDO -- cierra el ciclo de 5 estados que hasta ahora quedaba
/// atascado en "Emitido" (Gestión de Obra, auditoría 2026-09-11,
/// docs/gestion_obra_estado_real_auditoria.md §2): `marcar_certificado_leido`/`pagado`/`impactado`
/// existían y funcionaban en Supabase, pero ninguna pantalla las llamaba.
///
/// Distinta de `VistaPreviaCertificadoScreen` (esa es ANTES de emitir, con el botón "Emitir" y el
/// cálculo en vivo de `calcular_totales_certificado`) -- acá todo sale de las columnas ya
/// congeladas en `certificados` al emitir, sin volver a calcular nada.
///
/// "Leído" se marca sola al abrir esta pantalla, sin botón -- literal de la spec fundacional
/// (`docs/especificacion_funcional_parte2_fundacional.md` §2: "al abrir el certificado, se
/// notifica automáticamente a la obra que fue visto"), y así lo dejó diseñado
/// `marcar_certificado_leido` desde el arranque (idempotente, pensada para esto).
class DetalleCertificadoScreen extends StatefulWidget {
  final String obraId;
  final Certificado certificado;
  final UserContext? userContext;

  const DetalleCertificadoScreen({
    Key? key,
    required this.obraId,
    required this.certificado,
    required this.userContext,
  }) : super(key: key);

  @override
  State<DetalleCertificadoScreen> createState() => _DetalleCertificadoScreenState();
}

class _DetalleCertificadoScreenState extends State<DetalleCertificadoScreen> {
  final CertificadosRepository _certificadosRepository = CertificadosRepository();
  final ObrasRepository _obrasRepository = ObrasRepository();
  final IndicesEconomicosRepository _indicesRepository = IndicesEconomicosRepository();

  late Certificado _cert;
  bool _actualizando = false;

  /// Solo tiene sentido en un certificado anulado: ¿quedó sin reemplazo? (0126). Sale de
  /// `falta_reemplazo_certificado`, la misma función que valida la creación, así que el botón no
  /// puede ofrecer algo que la base después rechace.
  bool _faltaReemplazo = false;
  String _moneda = 'ARS';
  double _cotizacionHoy = 0;

  bool get _puedeVerMontos => widget.userContext?.puedeVerMontosGestionObra == true;

  /// La cotización con la que se convierten los montos de este certificado -- ver
  /// `docs/gestion_obra_estado_real_auditoria.md` y el intercambio del 2026-09-11: un certificado
  /// YA EMITIDO usa la cotización congelada al emitir (`0107`), nunca la de hoy -- el monto en
  /// pesos ya está fijo, así que el número en dólares que se mostró en su momento tampoco se
  /// mueve. Un Borrador (no debería llegar a esta pantalla, pero por las dudas) o un certificado
  /// emitido antes de esa migración (sin snapshot guardado) cae a la cotización de hoy -- la mejor
  /// aproximación disponible en esos dos casos, marcada como tal en pantalla (ver
  /// `_avisoConversionAproximada`).
  double get _cotizacionAUsar =>
      (_cert.estado != EstadoCertificado.borrador && _cert.cotizacionDolarPromedioAlEmitir != null)
          ? _cert.cotizacionDolarPromedioAlEmitir!
          : _cotizacionHoy;

  bool get _avisoConversionAproximada =>
      _moneda == 'USD' &&
      _cert.estado != EstadoCertificado.borrador &&
      _cert.cotizacionDolarPromedioAlEmitir == null;

  @override
  void initState() {
    super.initState();
    _cert = widget.certificado;
    _abrirConEstadoReal();
    _cargarMoneda();
  }

  /// El certificado que llega por parámetro es una FOTO del momento en que la pantalla anterior
  /// cargó su lista, y este circuito tiene dos lados que marcan desde dispositivos distintos (el
  /// Cliente marca Leído y Pagado; el que ejecuta impacta y cierra). Confiar en esa foto es lo que
  /// hacía que la pantalla ofreciera "Impactar y cerrar" sobre un certificado que la base ya tenía
  /// cerrado, y que al tocarlo contestara "no está pagado" (encontrado por Seba, 2026-09-13,
  /// probando con dos usuarios reales). Por eso lo primero que hace la pantalla es releerlo, y
  /// recién ahí decide si corresponde marcarlo como leído.
  ///
  /// Si la relectura falla se sigue con la foto: es mejor mostrar lo último que se sabía que no
  /// abrir la pantalla. Los botones que queden de más igual los rechaza la base, y ahora ese
  /// rechazo refresca la pantalla (ver `_avisarDeAccionFallida`).
  Future<void> _abrirConEstadoReal() async {
    await _recargar();
    await _marcarLeidoSiCorresponde();
  }

  /// Relee el certificado de la base. Devuelve `true` si el estado que tenía la pantalla ya no era
  /// el real -- lo usa el manejo de error de las acciones para explicar qué pasó.
  Future<bool> _recargar() async {
    final estadoAnterior = _cert.estado;
    try {
      final fresco = await _certificadosRepository.getPorId(_cert.id);
      final falta = fresco.estado == EstadoCertificado.anulado &&
          await _certificadosRepository.faltaReemplazo(fresco.id);
      if (!mounted) return false;
      setState(() {
        _cert = fresco;
        _faltaReemplazo = falta;
      });
      return fresco.estado != estadoAnterior;
    } catch (_) {
      return false;
    }
  }

  /// Recrea el reemplazo que falta. Al volver, la pantalla se cierra devolviendo `true`: el
  /// historial recarga y el borrador nuevo aparece ahí, que es donde se sigue trabajando.
  Future<void> _crearReemplazo() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _actualizando = true);
    try {
      await _certificadosRepository.crearReemplazo(_cert.id);
      if (!mounted) return;
      Navigator.pop(context, true);
      messenger.showSnackBar(SnackBar(
        content: Text('Se creó el reemplazo del certificado N° ${_cert.numeroFormateado}, '
            'en borrador, con las partidas del anulado.'),
      ));
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _actualizando = false);
      // El mensaje de la base ya explica el caso frecuente: "ya hay un borrador en curso...".
      await _recargar();
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _actualizando = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo crear el reemplazo del certificado.')),
      );
    }
  }

  /// Una acción rechazada acá casi siempre significa lo mismo: otra persona movió el certificado
  /// mientras esta pantalla mostraba el estado anterior. Se relee, y si efectivamente cambió se lo
  /// dice con el estado real -- en vez de repetir el mensaje crudo de Postgres, que trae el uuid y
  /// el nombre interno del estado ("certificado 5c5f... no está pagado (estado actual:
  /// impactado_cerrado)"). Al volver de acá los botones ya son los que correspondan al estado real.
  Future<void> _avisarDeAccionFallida(String mensajeSiSigueIgual) async {
    final cambio = await _recargar();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(cambio
          ? 'Este certificado ya fue actualizado por otra persona: ahora figura como '
              '${_cert.estado.label}.'
          : mensajeSiSigueIgual),
    ));
  }

  /// Silencioso ante error -- si falla, la pantalla sigue mostrando los montos en ARS (moneda
  /// nace en 'ARS', `convertirArsAMoneda` no convierte para esa moneda), nunca rompe la pantalla
  /// por un dato secundario de visualización.
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

  /// Automático, sin botón -- ver el comentario de cabecera. Silencioso ante error (no es una
  /// acción que el usuario pidió, no hay nada que mostrarle si falla) y sin efecto si ya está
  /// leído o si el certificado sigue en borrador (`marcar_certificado_leido` rechaza ese caso, y
  /// acá ni siquiera debería poder abrirse un borrador desde este detalle).
  Future<void> _marcarLeidoSiCorresponde() async {
    if (_cert.estado == EstadoCertificado.borrador) return;
    if (_cert.fechaLectura != null) return;
    if (widget.userContext?.puedeMarcarCertificadoLeido != true) return;
    try {
      await _certificadosRepository.marcarLeido(_cert.id);
      if (!mounted) return;
      setState(() {
        _cert = _copiarComoLeido(_cert);
      });
    } catch (_) {
      // Silencioso a propósito -- ver comentario del método.
    }
  }

  Certificado _copiarComoLeido(Certificado c) {
    // Certificado no tiene copyWith -- reconstruir a mano es más simple que sumarlo para un solo
    // uso. fechaLectura/estado son los únicos campos que cambian acá.
    return Certificado(
      id: c.id,
      obraId: c.obraId,
      numero: c.numero,
      version: c.version,
      periodo: c.periodo,
      monto: c.monto,
      montoPactado: c.montoPactado,
      cotizacionDolarPromedioAlEmitir: c.cotizacionDolarPromedioAlEmitir,
      estado: c.estado == EstadoCertificado.emitido ? EstadoCertificado.leido : c.estado,
      creadoPor: c.creadoPor,
      fechaCreacion: c.fechaCreacion,
      fechaEmision: c.fechaEmision,
      emitidoPor: c.emitidoPor,
      diasPlazoPago: c.diasPlazoPago,
      requiereFirmaFisica: c.requiereFirmaFisica,
      fechaLectura: DateTime.now(),
      leidoPor: c.leidoPor,
      fechaPago: c.fechaPago,
      pagadoPor: c.pagadoPor,
      medioPago: c.medioPago,
      comprobantePagoAdjuntos: c.comprobantePagoAdjuntos,
      anticipoPctAplicado: c.anticipoPctAplicado,
      fondoReparoPctAplicado: c.fondoReparoPctAplicado,
      montoAnticipoDescontado: c.montoAnticipoDescontado,
      montoFondoReparoRetenido: c.montoFondoReparoRetenido,
      montoNetoAPagar: c.montoNetoAPagar,
      fechaImpacto: c.fechaImpacto,
      impactadoPor: c.impactadoPor,
      facturaFinalAdjuntos: c.facturaFinalAdjuntos,
      pdfFirmadoSubido: c.pdfFirmadoSubido,
      pdfFirmadoFecha: c.pdfFirmadoFecha,
      pdfFirmadoAdjuntos: c.pdfFirmadoAdjuntos,
      anulacionEstado: c.anulacionEstado,
      anulacionMotivo: c.anulacionMotivo,
      anulacionPropuestaPor: c.anulacionPropuestaPor,
      anulacionPropuestaFecha: c.anulacionPropuestaFecha,
      anulacionResueltaPor: c.anulacionResueltaPor,
      anulacionResueltaFecha: c.anulacionResueltaFecha,
      anulacionMotivoRechazo: c.anulacionMotivoRechazo,
      // Acuerdo entre partes (0124). Se copian aunque en un certificado ya emitido no cambien
      // nada: este constructor a mano es el único lugar del proyecto donde un campo nuevo del
      // modelo se pierde en silencio si alguien se olvida de agregarlo.
      acuerdoEstado: c.acuerdoEstado,
      propuestoPor: c.propuestoPor,
      propuestaFecha: c.propuestaFecha,
      conformePor: c.conformePor,
      conformeFecha: c.conformeFecha,
      comentarioDevolucion: c.comentarioDevolucion,
    );
  }

  Future<void> _marcarPagado() async {
    final resultado = await _pedirDatosPago();
    if (resultado == null) return;

    setState(() => _actualizando = true);
    try {
      await _certificadosRepository.marcarPagado(
        certificadoId: _cert.id,
        medioPago: resultado.$1,
        comprobanteAdjuntos: resultado.$2 == null ? const [] : [resultado.$2!],
      );
      if (!mounted) return;
      Navigator.pop(context, true); // recarga la lista del historial al volver
    } on PostgrestException catch (_) {
      if (!mounted) return;
      setState(() => _actualizando = false);
      await _avisarDeAccionFallida('No se pudo marcar el certificado como pagado.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _actualizando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo marcar el certificado como pagado.')),
      );
    }
  }

  static const _mediosPago = {
    'transferencia': 'Transferencia',
    'efectivo': 'Efectivo',
    'cheque': 'Cheque',
    'otro': 'Otro',
  };

  Future<(String, String?)?> _pedirDatosPago() {
    String medioSeleccionado = 'transferencia';
    final comprobanteController = TextEditingController();
    return showDialog<(String, String?)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Marcar como pagado', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Medio de pago', style: TextStyle(fontSize: 12, color: Colors.black54)),
              DropdownButton<String>(
                value: medioSeleccionado,
                isExpanded: true,
                items: _mediosPago.entries
                    .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 13))))
                    .toList(),
                onChanged: (v) => setDialogState(() => medioSeleccionado = v!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: comprobanteController,
                decoration: const InputDecoration(
                  labelText: 'Link al comprobante (opcional)',
                  hintText: 'Drive, WhatsApp, etc.',
                  isDense: true,
                ),
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            TextButton(
              onPressed: () {
                final comprobante = comprobanteController.text.trim();
                Navigator.pop(ctx, (medioSeleccionado, comprobante.isEmpty ? null : comprobante));
              },
              child: const Text('Confirmar pago'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _marcarImpactado() async {
    final controller = TextEditingController();
    final factura = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Impactar y cerrar', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Confirma que se verificó el cobro. Cierra el ciclo de este certificado.',
              style: TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Link a factura/recibo final (opcional)',
                isDense: true,
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Impactar y cerrar'),
          ),
        ],
      ),
    );
    if (factura == null) return; // canceló

    setState(() => _actualizando = true);
    try {
      await _certificadosRepository.marcarImpactado(
        certificadoId: _cert.id,
        facturaAdjuntos: factura.isEmpty ? const [] : [factura],
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on PostgrestException catch (_) {
      if (!mounted) return;
      setState(() => _actualizando = false);
      await _avisarDeAccionFallida('No se pudo impactar el certificado.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _actualizando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo impactar el certificado.')),
      );
    }
  }

  /// `montoArs`: el valor tal cual sale de `certificados` -- siempre en pesos. Convierte a la
  /// moneda de la obra antes de formatear, ver `_cotizacionAUsar`.
  String _fmt(double montoArs) {
    final convertido = convertirArsAMoneda(montoArs, _moneda, _cotizacionAUsar);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Certificado Nº ${_cert.numeroFormateado}',
          style: const TextStyle(fontSize: 15),
        ),
        backgroundColor: const Color(0xFF1B365D),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Text(_cert.estado.label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade700)),
          Text('Período: ${_cert.periodo}', style: const TextStyle(fontSize: 13, color: Colors.black54)),
          const SizedBox(height: 16),
          if (_puedeVerMontos) _buildMontos(),
          const SizedBox(height: 16),
          _buildLineaTiempo(),
          const SizedBox(height: 24),
          if (_cert.estado == EstadoCertificado.pagado || _cert.estado == EstadoCertificado.impactadoCerrado)
            _buildDatoPago(),
          if (_cert.estado == EstadoCertificado.impactadoCerrado) _buildDatoImpacto(),
          if (_faltaReemplazo) _buildAvisoSinReemplazo(),
          const SizedBox(height: 24),
          _buildAcciones(),
        ],
      ),
    );
  }

  Widget _buildMontos() {
    final tieneDesglose = _cert.montoPactado != null && _cert.monto != _cert.montoPactado;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (tieneDesglose) ...[
            _buildFila('Precio pactado', _fmt(_cert.montoPactado!)),
            _buildFila('Ajuste CAC', _fmt(_cert.monto - _cert.montoPactado!)),
          ],
          _buildFila('Monto certificado', _fmt(_cert.monto), destacado: true),
          if ((_cert.anticipoPctAplicado ?? 0) > 0)
            _buildFila('Anticipo (${_cert.anticipoPctAplicado!.toStringAsFixed(1)}%)', '-${_fmt(_cert.montoAnticipoDescontado ?? 0)}'),
          if ((_cert.fondoReparoPctAplicado ?? 0) > 0)
            _buildFila('Fondo de reparo (${_cert.fondoReparoPctAplicado!.toStringAsFixed(1)}%)', '-${_fmt(_cert.montoFondoReparoRetenido ?? 0)}'),
          const Divider(),
          _buildFila('Neto a pagar', _fmt(_cert.montoNetoAPagar ?? _cert.monto), destacado: true),
          if (_avisoConversionAproximada)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Convertido a la cotización de hoy -- este certificado se emitió antes de que se '
                'empezara a guardar la cotización del momento de emisión.',
                style: TextStyle(fontSize: 10, color: Colors.blueGrey.shade400, fontStyle: FontStyle.italic),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFila(String etiqueta, String valor, {bool destacado = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(etiqueta, style: TextStyle(fontSize: destacado ? 13 : 12, fontWeight: destacado ? FontWeight.bold : FontWeight.normal)),
          Text(valor, style: TextStyle(fontSize: destacado ? 13 : 12, fontWeight: destacado ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
    );
  }

  Widget _buildLineaTiempo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Línea de tiempo', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1B365D))),
        const SizedBox(height: 6),
        _buildPaso('Emitido', _cert.fechaEmision),
        _buildPaso('Leído por Propietario', _cert.fechaLectura),
        _buildPaso('Pagado', _cert.fechaPago),
        _buildPaso('Impactado y Cerrado', _cert.fechaImpacto),
      ],
    );
  }

  Widget _buildPaso(String etiqueta, DateTime? fecha) {
    final ocurrido = fecha != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(ocurrido ? Icons.check_circle : Icons.radio_button_unchecked, size: 14, color: ocurrido ? Colors.green.shade700 : Colors.black26),
          const SizedBox(width: 6),
          Text(etiqueta, style: TextStyle(fontSize: 12.5, color: ocurrido ? Colors.black87 : Colors.black38)),
          const Spacer(),
          Text(_fmtFecha(fecha), style: TextStyle(fontSize: 11.5, color: ocurrido ? Colors.black54 : Colors.black26)),
        ],
      ),
    );
  }

  Widget _buildDatoPago() {
    final medio = _mediosPago[_cert.medioPago] ?? _cert.medioPago ?? '—';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text('Medio de pago: $medio', style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
    );
  }

  /// Un anulado siempre debería tener su reemplazo: nace solo al aprobarse la anulación. Si no está,
  /// lo que este certificado media quedó sin certificar por ningún documento vigente, y eso hay que
  /// decirlo -- sin el cartel, el botón de abajo no se entiende.
  Widget _buildAvisoSinReemplazo() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Text(
        'Este certificado no tiene reemplazo. Lo que medía no está certificado por ningún '
        'certificado vigente. Al recrearlo nace un borrador con las partidas de este, para '
        'corregirlo y volver a emitir.',
        style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
      ),
    );
  }

  Widget _buildDatoImpacto() {
    if (_cert.facturaFinalAdjuntos.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text('Factura final: ${_cert.facturaFinalAdjuntos.first}', style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
    );
  }

  Widget _buildAcciones() {
    final botones = <Widget>[];

    if ((_cert.estado == EstadoCertificado.emitido || _cert.estado == EstadoCertificado.leido) &&
        widget.userContext?.puedeMarcarCertificadoPagado(_cert.monto) == true) {
      botones.add(ElevatedButton(
        onPressed: _actualizando ? null : _marcarPagado,
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B365D), foregroundColor: Colors.white),
        child: const Text('Marcar como pagado'),
      ));
    }

    // Red de seguridad (0126): un anulado sin reemplazo. Los tres roles técnicos, que es la misma
    // autoridad que ya crea un borrador -- recrear el reemplazo es crear un borrador, no un acto
    // formal: no emite, no compromete plata. Los actos formales siguen pidiendo lo suyo después.
    if (_faltaReemplazo && widget.userContext?.puedeCargarAvance == true) {
      botones.add(ElevatedButton(
        onPressed: _actualizando ? null : _crearReemplazo,
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B365D), foregroundColor: Colors.white),
        child: const Text('Crear el reemplazo'),
      ));
    }

    if (_cert.estado == EstadoCertificado.pagado && widget.userContext?.puedeMarcarCertificadoImpactado == true) {
      botones.add(ElevatedButton(
        onPressed: _actualizando ? null : _marcarImpactado,
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B365D), foregroundColor: Colors.white),
        child: const Text('Impactar y cerrar'),
      ));
    }

    if (botones.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final b in botones) Padding(padding: const EdgeInsets.only(bottom: 8), child: b),
        if (_actualizando) const Center(child: Padding(padding: EdgeInsets.only(top: 4), child: CircularProgressIndicator())),
      ],
    );
  }
}
