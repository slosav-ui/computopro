import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/segurity/user_context.dart';
import '../../../data/models/certificado.dart';
import '../../../services/certificados_repository.dart';

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

  late Certificado _cert;
  bool _actualizando = false;

  bool get _puedeVerMontos => widget.userContext?.puedeVerMontosGestionObra == true;

  @override
  void initState() {
    super.initState();
    _cert = widget.certificado;
    _marcarLeidoSiCorresponde();
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
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _actualizando = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
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
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _actualizando = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _actualizando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo impactar el certificado.')),
      );
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Certificado Nº ${_cert.numero.toString().padLeft(3, '0')}',
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
