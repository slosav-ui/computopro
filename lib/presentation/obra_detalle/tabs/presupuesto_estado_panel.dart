import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../services/obras_repository.dart';

/// Presentar el presupuesto (con su validez), avisar cuando venció y ofrecer actualizarlo, y
/// congelarlo al firmar -- Modelo A. Ver
/// docs/presupuesto_congelado_validez_modelo_a_diseno.md para el diseño completo;
/// `presentar_presupuesto_obra`/`congelar_presupuesto_obra` (`0103`/`0104`) para las reglas reales,
/// que este panel no duplica -- cualquier excepción de negocio (vencido, sin presentar, ya
/// congelado con certificados emitidos) llega como `PostgrestException` con el mensaje ya en
/// español, se muestra tal cual.
///
/// Siempre visible (a diferencia de `CartelFirmaPendiente`, que no muestra nada si no hay ningún
/// pendiente) -- toda obra tiene un estado de presupuesto, aunque sea "todavía sin presentar", así
/// que acá sí hay algo que mostrar siempre.
///
/// Los botones de acción quedan visibles incluso con la obra ya congelada -- a propósito, no un
/// descuido: `presentar_presupuesto_obra`/`congelar_presupuesto_obra` ya permiten volver a
/// presentar/congelar mientras ningún certificado dejó de ser borrador (ambigüedad C del diseño,
/// "mientras no se certificó nada, no hay nada que proteger"). Filtrar esto del lado del cliente
/// duplicaría una regla que el servidor ya aplica y que puede cambiar con el tiempo -- si ya no se
/// puede, el intento simplemente vuelve con el mensaje de la excepción.
class PresupuestoEstadoPanel extends StatefulWidget {
  final String obraId;
  final bool puedeGestionar;

  const PresupuestoEstadoPanel({
    Key? key,
    required this.obraId,
    required this.puedeGestionar,
  }) : super(key: key);

  @override
  State<PresupuestoEstadoPanel> createState() => _PresupuestoEstadoPanelState();
}

class _PresupuestoEstadoPanelState extends State<PresupuestoEstadoPanel> {
  final ObrasRepository _obrasRepository = ObrasRepository();

  bool _cargando = true;
  DateTime? _fechaPresentacion;
  int _validezDias = 30;
  DateTime? _congeladoEn;
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    if (mounted) setState(() => _cargando = true);
    try {
      final estado = await _obrasRepository.getEstadoPresupuesto(widget.obraId);
      if (!mounted) return;
      setState(() {
        _fechaPresentacion = estado['fechaPresentacion'] as DateTime?;
        _validezDias = estado['validezDias'] as int;
        _congeladoEn = estado['congeladoEn'] as DateTime?;
        _cargando = false;
      });
    } catch (_) {
      // Silencioso a propósito, mismo criterio que CartelFirmaPendiente: si falla la consulta, el
      // panel no se muestra en vez de tapar la solapa con un error -- no es una acción bloqueante.
      if (!mounted) return;
      setState(() => _cargando = false);
    }
  }

  DateTime? get _vencimiento =>
      _fechaPresentacion?.add(Duration(days: _validezDias));

  bool get _vencido =>
      _congeladoEn == null &&
      _vencimiento != null &&
      DateTime.now().isAfter(_vencimiento!);

  String _fmtFecha(DateTime fecha) => '${fecha.day}/${fecha.month}/${fecha.year}';

  Future<void> _presentar() async {
    final validez = await _pedirValidez(_validezDias);
    if (validez == null) return; // canceló

    setState(() => _enviando = true);
    try {
      await _obrasRepository.presentarPresupuesto(widget.obraId, validez);
      if (!mounted) return;
      await _cargar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Presupuesto presentado -- válido hasta ${_fmtFecha(_vencimiento!)}.'),
      ));
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo presentar el presupuesto.')),
      );
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  /// Cartel de validez ANTES de confirmar -- nunca un valor por defecto que nadie miró. 30 días
  /// sugerido, editable; si ya había una validez cargada (caso "Actualizar"), se prefiere esa como
  /// punto de partida en vez de resetear siempre a 30.
  Future<int?> _pedirValidez(int sugerido) async {
    final controller = TextEditingController(text: sugerido.toString());
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Validez del presupuesto', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Días que el presupuesto queda vigente desde hoy. Pasado ese plazo, va a avisar que '
              'venció antes de dejar firmarlo.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Días de validez', isDense: true),
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          TextButton(
            onPressed: () {
              final valor = int.tryParse(controller.text.trim());
              if (valor == null || valor <= 0) return;
              Navigator.pop(ctx, valor);
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
  }

  Future<void> _congelar() async {
    double? presupuestoVivo;
    try {
      presupuestoVivo = await _obrasRepository.calcularPresupuestoVivo(widget.obraId);
    } catch (_) {
      presupuestoVivo = null; // informativo -- si falla, el diálogo sigue sin ese dato
    }

    if (!mounted) return;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Congelar presupuesto', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'A partir de ahora, la cantidad y el precio final de cada partida tildada quedan '
              'fijos -- Gestión de Obra va a certificar contra este número, no contra lo que cueste '
              'más adelante. Usalo cuando se firme el contrato, o se dé el anticipo si no hay '
              'contrato.',
              style: TextStyle(fontSize: 12.5),
            ),
            if (presupuestoVivo != null) ...[
              const SizedBox(height: 12),
              Text(
                'Presupuesto actual: ${_fmtMonto(presupuestoVivo)}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1B365D)),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B365D)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Congelar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    setState(() => _enviando = true);
    try {
      await _obrasRepository.congelarPresupuesto(widget.obraId);
      if (!mounted) return;
      await _cargar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Presupuesto congelado.')),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo congelar el presupuesto.')),
      );
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  String _fmtMonto(double monto) {
    final valorInt = monto.round();
    final str = valorInt.toString();
    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    final formateado = str.replaceAllMapped(reg, (Match m) => '${m[1]}.');
    return '\$ $formateado';
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const SizedBox.shrink();

    if (_congeladoEn != null) {
      return _buildCard(
        color: Colors.green.shade50,
        borderColor: Colors.green.shade300,
        icon: Icons.lock_outline,
        iconColor: Colors.green.shade800,
        titulo: 'Presupuesto congelado el ${_fmtFecha(_congeladoEn!)}',
        subtitulo: 'La cantidad y el precio de cada partida quedaron fijos. Gestión de Obra '
            'certifica contra este número.',
        tituloColor: Colors.green.shade900,
      );
    }

    if (_vencido) {
      final diasVencido = DateTime.now().difference(_vencimiento!).inDays;
      return _buildCard(
        color: Colors.amber.shade50,
        borderColor: Colors.amber.shade300,
        icon: Icons.warning_amber_rounded,
        iconColor: Colors.amber.shade800,
        titulo: 'Presupuesto vencido hace ${diasVencido <= 0 ? 'menos de 1' : diasVencido} '
            '${diasVencido == 1 ? 'día' : 'días'}',
        subtitulo: 'Venció el ${_fmtFecha(_vencimiento!)}. Actualizalo para poder congelarlo.',
        tituloColor: Colors.amber.shade900,
        boton: widget.puedeGestionar
            ? _buildBoton('Actualizar', _presentar)
            : null,
      );
    }

    if (_fechaPresentacion != null) {
      return _buildCard(
        color: Colors.blue.shade50,
        borderColor: Colors.blue.shade200,
        icon: Icons.description_outlined,
        iconColor: Colors.blue.shade800,
        titulo: 'Presentado el ${_fmtFecha(_fechaPresentacion!)}',
        subtitulo: 'Válido hasta ${_fmtFecha(_vencimiento!)}.',
        tituloColor: Colors.blue.shade900,
        boton: widget.puedeGestionar
            ? Row(
                children: [
                  _buildBoton('Volver a presentar', _presentar, primario: false),
                  const SizedBox(width: 12),
                  _buildBoton('Firmar (congelar)', _congelar),
                ],
              )
            : null,
      );
    }

    return _buildCard(
      color: Colors.grey.shade100,
      borderColor: Colors.grey.shade300,
      icon: Icons.description_outlined,
      iconColor: Colors.black54,
      titulo: 'Presupuesto sin presentar',
      subtitulo: 'Presentalo para que arranque a correr su validez.',
      tituloColor: Colors.black87,
      boton: widget.puedeGestionar
          ? _buildBoton('Presentar presupuesto', _presentar)
          : null,
    );
  }

  Widget _buildBoton(String texto, VoidCallback onPressed, {bool primario = true}) {
    final Widget child = _enviando
        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
        : Text(texto, style: TextStyle(fontSize: 12, color: primario ? Colors.white : null));
    return primario
        ? ElevatedButton(
            onPressed: _enviando ? null : onPressed,
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B365D)),
            child: child,
          )
        : OutlinedButton(
            onPressed: _enviando ? null : onPressed,
            style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1B365D)),
            child: child,
          );
  }

  Widget _buildCard({
    required Color color,
    required Color borderColor,
    required IconData icon,
    required Color iconColor,
    required String titulo,
    required String subtitulo,
    required Color tituloColor,
    Widget? boton,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: tituloColor)),
                    const SizedBox(height: 2),
                    Text(subtitulo, style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
                  ],
                ),
              ),
            ],
          ),
          if (boton != null) ...[
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerRight, child: boton),
          ],
        ],
      ),
    );
  }
}
