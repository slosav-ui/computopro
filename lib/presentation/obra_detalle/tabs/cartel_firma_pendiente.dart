import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../data/models/certificado.dart';
import '../../../services/certificados_repository.dart';

/// Aviso persistente de certificados con firma física pendiente — Gestión de Obra, pieza 4.
/// Ya no bloquea la emisión del siguiente certificado (0055): la firma física puede tardar días
/// por depender de terceros, así que en vez de frenar la certificación de la obra, esto se
/// muestra cada vez que se abre la solapa hasta que se sube el PDF de cada uno. Textual de Seba:
/// que el aviso "gane por cansancio" antes que trabar el flujo entero.
///
/// A propósito no es plegable ni recuerda si se cerró (a diferencia de `BloqueFactorK`/el aviso de
/// orden de `rubros_tab.dart`, que sí persisten su estado colapsado en SharedPreferences) — ese
/// mecanismo serviría exactamente para lo contrario de lo que se pidió acá: si el usuario lo
/// colapsara una vez, quedaría silenciado para siempre y el aviso dejaría de cumplir su función.
///
/// Nada si no hay ninguno pendiente — no hay motivo para mostrar una tarjeta vacía.
class CartelFirmaPendiente extends StatefulWidget {
  final String obraId;

  const CartelFirmaPendiente({Key? key, required this.obraId}) : super(key: key);

  @override
  State<CartelFirmaPendiente> createState() => _CartelFirmaPendienteState();
}

class _CartelFirmaPendienteState extends State<CartelFirmaPendiente> {
  final CertificadosRepository _certificadosRepository = CertificadosRepository();

  List<Certificado> _pendientes = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final pendientes = await _certificadosRepository.getConFirmaPendiente(widget.obraId);
      if (!mounted) return;
      setState(() {
        _pendientes = pendientes;
        _cargando = false;
      });
    } catch (e) {
      // Silencioso a propósito: es un aviso informativo, no una funcionalidad crítica — si falla
      // la consulta, simplemente no se muestra nada en vez de tapar la solapa con un error.
      if (!mounted) return;
      setState(() => _cargando = false);
    }
  }

  Future<void> _subirPdf(Certificado certificado) async {
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        return AlertDialog(
          title: Text('Certificado Nº ${certificado.numero} — PDF firmado',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Link al PDF firmado (Drive, WhatsApp, etc.)',
              isDense: true,
            ),
            style: const TextStyle(fontSize: 13),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            TextButton(
              onPressed: () {
                final texto = controller.text.trim();
                Navigator.pop(ctx, texto.isEmpty ? null : texto);
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );
    if (url == null) return;

    try {
      await _certificadosRepository.subirPdfFirmado(
        certificadoId: certificado.id,
        adjuntos: [url],
      );
      if (!mounted) return;
      await _cargar();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo guardar el PDF firmado.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando || _pendientes.isEmpty) return const SizedBox.shrink();

    final plural = _pendientes.length == 1 ? 'certificado' : 'certificados';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.amber.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.amber.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 18, color: Colors.amber.shade800),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Tenés ${_pendientes.length} $plural con firma física pendiente',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ..._pendientes.map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Certificado Nº ${c.numero} — ${c.periodo}',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                      TextButton(
                        onPressed: () => _subirPdf(c),
                        style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
                        child: const Text('Subir PDF', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
