import 'package:flutter/material.dart';
import '../../../core/utils/parser_numero_ar.dart';
import '../../../data/models/cargas_sociales_defaults.dart';
import '../../../data/models/obra_presupuesto_config.dart';
import '../../../data/models/zona_uocra.dart';
import '../../../services/auth_service.dart';
import '../../../services/escala_salarial_uocra_repository.dart';
import '../../../services/obra_presupuesto_config_repository.dart';
import '../../../services/perfil_repository.dart';
import '../../shared/pro_gate_dialog.dart';

/// Los 7 parámetros de cargas sociales de la obra — Paso 5 (ver
/// docs/costo_mano_de_obra_decisiones.md §15/§16). Se abre desde el link "Ajustar cargas sociales"
/// de PanelValorHoraManoObra, como ventana aparte encima de esa — nunca como sección expandible del
/// mismo diálogo (ese fue el diseño original, con cuatro rondas de parches; ver §16 para el porqué
/// de la separación). El campo de valor hora de una categoría puntual no aparece acá.
///
/// Sin ambigüedad de "qué tocó el usuario": Guardar siempre guarda los 7, Cancelar nunca guarda
/// nada. La bandera de "sección abierta", la comparación de textos crudos contra un snapshot
/// inicial y el mensaje combinado de PRO del diseño de una sola ventana no se migran acá —
/// resolvían una ambigüedad que esta separación elimina.
///
/// La config se carga acá adentro (no se recibe por constructor): así nunca puede quedar vieja si
/// el usuario guarda, reabre esta ventana sin cerrar la anterior, y vuelve a guardar — mismo
/// principio que el chequeo de PRO en vivo, no confiar en una foto que alguien más te pasó (ver
/// docs §16).
///
/// Devuelve `true` por `Navigator.pop` si se guardó; `false`/`null` si no (Cancelar, o cerrar sin
/// guardar).
class PanelParametrosCargasSociales extends StatefulWidget {
  final String obraId;

  const PanelParametrosCargasSociales({
    Key? key,
    required this.obraId,
  }) : super(key: key);

  @override
  State<PanelParametrosCargasSociales> createState() => _PanelParametrosCargasSocialesState();
}

class _PanelParametrosCargasSocialesState extends State<PanelParametrosCargasSociales> {
  final ObraPresupuestoConfigRepository _configRepository = ObraPresupuestoConfigRepository();
  final EscalaSalarialUocraRepository _escalaRepository = EscalaSalarialUocraRepository();
  final PerfilRepository _perfilRepository = PerfilRepository();
  final AuthService _authService = AuthService();

  ObraPresupuestoConfig? _config;
  TextEditingController? _artController;
  TextEditingController? _fondoCeseController;
  TextEditingController? _horasMensualesController;
  TextEditingController? _horasImproductivasController;
  TextEditingController? _vacacionesController;
  bool _esMiPyme = false;
  String _zonaSeleccionada = '';

  List<ZonaUocra>? _zonasDisponibles;
  String? _errorParametros;
  bool _guardando = false;
  bool _verificandoPro = false;

  @override
  void initState() {
    super.initState();
    _cargarConfig();
    _cargarZonas();
  }

  Future<void> _cargarConfig() async {
    final config = await _configRepository.getConfig(widget.obraId);
    if (!mounted) return;
    // Defensivo: _cargarConfig hoy solo se llama una vez, desde initState. Si en el futuro se
    // agrega una forma de recargar y se llama de nuevo, esto evita que los controllers anteriores
    // queden sin dispose.
    _artController?.dispose();
    _fondoCeseController?.dispose();
    _horasMensualesController?.dispose();
    _horasImproductivasController?.dispose();
    _vacacionesController?.dispose();
    setState(() {
      _config = config;
      _artController = TextEditingController(text: _fmtEntrada(config.artPct));
      _fondoCeseController = TextEditingController(text: _fmtEntrada(config.fondoCesePct));
      _horasMensualesController = TextEditingController(text: _fmtEntrada(config.horasMensuales));
      _horasImproductivasController =
          TextEditingController(text: _fmtEntrada(config.horasImproductivasMensuales));
      _vacacionesController = TextEditingController(text: _fmtEntrada(config.vacacionesJornalesMes));
      // Cualquier valor que no sea exactamente 20,4 se trata como "con MiPyME" (18, el default de
      // 0036) — defensivo ante un valor viejo o manual que no coincida con ninguno de los dos.
      _esMiPyme = config.sussPct != 20.4;
      _zonaSeleccionada = config.zonaUocra;
    });
  }

  Future<void> _cargarZonas() async {
    final zonas = await _escalaRepository.getZonasDisponibles();
    if (!mounted) return;
    setState(() => _zonasDisponibles = zonas);
  }

  @override
  void dispose() {
    _artController?.dispose();
    _fondoCeseController?.dispose();
    _horasMensualesController?.dispose();
    _horasImproductivasController?.dispose();
    _vacacionesController?.dispose();
    super.dispose();
  }

  String _fmtEntrada(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  /// Formato de lectura para el usuario (coma decimal) — usado tanto para el valor actual del
  /// campo como para el "por defecto X" de `CargasSocialesDefaults` en los labels de más abajo.
  String _fmtComa(double v) => _fmtEntrada(v).replaceAll('.', ',');

  Map<String, double>? _validarParametros() {
    final art = ParserNumeroAr.parsear(_artController!.text);
    final fondoCese = ParserNumeroAr.parsear(_fondoCeseController!.text);
    final horasMensuales = ParserNumeroAr.parsear(_horasMensualesController!.text);
    final horasImproductivas = ParserNumeroAr.parsear(_horasImproductivasController!.text);
    final vacaciones = ParserNumeroAr.parsear(_vacacionesController!.text);

    if (art == null || art < 0) {
      setState(() => _errorParametros = 'ART inválido');
      return null;
    }
    if (fondoCese == null || fondoCese < 0) {
      setState(() => _errorParametros = 'Fondo de Cese inválido');
      return null;
    }
    if (horasMensuales == null || horasMensuales <= 0) {
      setState(() => _errorParametros = 'Horas mensuales inválidas');
      return null;
    }
    if (horasImproductivas == null || horasImproductivas < 0) {
      setState(() => _errorParametros = 'Horas improductivas inválidas');
      return null;
    }
    if (vacaciones == null || vacaciones < 0) {
      setState(() => _errorParametros = 'Vacaciones inválidas');
      return null;
    }
    // Misma regla que el check de la base (0044) — validado acá primero para un error inmediato,
    // el check queda como red de seguridad si esto se saltea por cualquier motivo.
    if (horasImproductivas >= horasMensuales) {
      setState(() => _errorParametros =
          'Las horas improductivas tienen que ser menores a las horas mensuales.');
      return null;
    }
    setState(() => _errorParametros = null);
    return {
      'sussPct': _esMiPyme ? 18 : 20.4,
      'artPct': art,
      'fondoCesePct': fondoCese,
      'horasMensuales': horasMensuales,
      'horasImproductivasMensuales': horasImproductivas,
      'vacacionesJornalesMes': vacaciones,
    };
  }

  /// Guarda siempre los 7, sin comparar contra nada — Cancelar es la salida para "no guardar". El
  /// gate de PRO se verifica en vivo, recién acá, nunca antes.
  Future<void> _onGuardar() async {
    final parametrosValidados = _validarParametros();
    if (parametrosValidados == null) return;

    final usuarioId = _authService.usuarioActual?.id;
    setState(() => _verificandoPro = true);
    final esProAhora = usuarioId != null ? await _perfilRepository.esPro(usuarioId) : false;
    if (!mounted) return;
    setState(() => _verificandoPro = false);

    if (!esProAhora) {
      await mostrarDialogoFuncionPro(context, mensaje: 'Ajustar las cargas sociales es una función PRO.');
      return;
    }

    setState(() => _guardando = true);
    try {
      await _configRepository.actualizarCargasSociales(
        obraId: widget.obraId,
        sussPct: parametrosValidados['sussPct']!,
        artPct: parametrosValidados['artPct']!,
        fondoCesePct: parametrosValidados['fondoCesePct']!,
        horasMensuales: parametrosValidados['horasMensuales']!,
        horasImproductivasMensuales: parametrosValidados['horasImproductivasMensuales']!,
        vacacionesJornalesMes: parametrosValidados['vacacionesJornalesMes']!,
        zonaUocra: _zonaSeleccionada,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _errorParametros = 'No se pudo guardar.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    if (config == null) {
      return AlertDialog(
        title: const Text('Ajustar cargas sociales', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        content: const SizedBox(height: 80, child: Center(child: CircularProgressIndicator())),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar'))],
      );
    }
    final artController = _artController!;
    final fondoCeseController = _fondoCeseController!;
    final horasMensualesController = _horasMensualesController!;
    final horasImproductivasController = _horasImproductivasController!;
    final vacacionesController = _vacacionesController!;
    final guardando = _guardando || _verificandoPro;

    return AlertDialog(
      title: const Text('Ajustar cargas sociales', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
      content: Scrollbar(
        thumbVisibility: true,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Toda la obra — afecta el valor hora de todas las categorías de mano de obra.',
                style: TextStyle(fontSize: 11, color: Colors.black54),
              ),
              const SizedBox(height: 8),
              const Text('Con certificado MiPyME vigente', style: TextStyle(fontSize: 10, color: Colors.black87)),
              RadioListTile<bool>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                title: const Text('Con certificado MiPyME — 18%', style: TextStyle(fontSize: 11)),
                value: true,
                groupValue: _esMiPyme,
                onChanged: (v) => setState(() => _esMiPyme = v!),
              ),
              RadioListTile<bool>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                title: const Text('Sin certificado MiPyME — 20,4%', style: TextStyle(fontSize: 11)),
                value: false,
                groupValue: _esMiPyme,
                onChanged: (v) => setState(() => _esMiPyme = v!),
              ),
              // "Por defecto", nunca "correcto" — el valor sale de CargasSocialesDefaults (copia a
              // mano del default real de la columna, no de la config actual de esta obra — ver el
              // comentario de esa clase), no de ninguna autoridad normativa (a diferencia del
              // "Volver" del valor hora, que sí tiene un destino con autoridad: la escala UOCRA).
              // Mismo criterio en los 5 campos de abajo y en la zona — ver
              // docs/costo_mano_de_obra_decisiones.md §15.
              Text(
                'Por defecto: ${CargasSocialesDefaults.sussPct != 20.4 ? "con certificado MiPyME (18%)" : "sin certificado MiPyME (20,4%)"}',
                style: const TextStyle(fontSize: 9, color: Colors.black45),
              ),
              const SizedBox(height: 8),
              _buildCampoParametro(
                label: 'ART (%) — por defecto ${_fmtComa(CargasSocialesDefaults.artPct)}',
                helper: 'Sacalo de tu póliza — el valor cargado es un supuesto de la liquidadora, no verificado.',
                controller: artController,
              ),
              _buildCampoParametro(
                label: 'Fondo de Cese (%) — por defecto ${_fmtComa(CargasSocialesDefaults.fondoCesePct)}',
                controller: fondoCeseController,
              ),
              _buildCampoParametro(
                label: 'Horas mensuales — por defecto ${_fmtComa(CargasSocialesDefaults.horasMensuales)}',
                controller: horasMensualesController,
              ),
              _buildCampoParametro(
                label: 'Horas improductivas mensuales — por defecto '
                    '${_fmtComa(CargasSocialesDefaults.horasImproductivasMensuales)}',
                controller: horasImproductivasController,
              ),
              _buildCampoParametro(
                label: 'Vacaciones (jornales/mes) — por defecto '
                    '${_fmtComa(CargasSocialesDefaults.vacacionesJornalesMes)}',
                controller: vacacionesController,
              ),
              const SizedBox(height: 4),
              _buildCampoZona(),
              if (_errorParametros != null) ...[
                const SizedBox(height: 4),
                Text(_errorParametros!, style: const TextStyle(fontSize: 11, color: Colors.red)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: guardando ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        TextButton(
          onPressed: guardando ? null : _onGuardar,
          child: Text(_guardando ? 'Guardando...' : _verificandoPro ? 'Verificando...' : 'Guardar'),
        ),
      ],
    );
  }

  Widget _buildCampoParametro({required String label, String? helper, required TextEditingController controller}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 11),
          helperText: helper,
          helperMaxLines: 3,
          helperStyle: const TextStyle(fontSize: 9),
          isDense: true,
        ),
        style: const TextStyle(fontSize: 12),
      ),
    );
  }

  /// Nombre de la zona por defecto (`CargasSocialesDefaults.zonaUocra`, no la seleccionada
  /// actualmente en esta obra — mismo bug que ya se arregló en los otros 6 campos, ver
  /// docs/costo_mano_de_obra_decisiones.md §15) — resuelto contra `_zonasDisponibles` cuando ya
  /// cargó; si no, el código solo, mejor que nada mientras carga.
  String _nombreZonaPorDefecto(List<ZonaUocra> zonas) {
    for (final z in zonas) {
      if (z.codigo == CargasSocialesDefaults.zonaUocra) return z.nombre;
    }
    return CargasSocialesDefaults.zonaUocra;
  }

  Widget _buildCampoZona() {
    final zonas = _zonasDisponibles;
    if (zonas == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (zonas.isEmpty) {
      // No debería pasar (la obra ya tiene una zona con escala cargada, si no calcular_valor_hora
      // ya habría fallado antes de llegar a este panel) — texto de emergencia, no un selector vacío.
      return Text('Zona UOCRA: $_zonaSeleccionada', style: const TextStyle(fontSize: 11, color: Colors.black87));
    }
    // Solo una zona cargada hoy: texto fijo con su descripción completa, no un selector con una
    // única opción sin sentido de elegir. El día que haya una segunda zona, este mismo widget se
    // convierte solo en un selector real — no hace falta tocar nada acá.
    final campo = zonas.length == 1
        ? Text(zonas.first.etiqueta, style: const TextStyle(fontSize: 11, color: Colors.black87))
        : DropdownButtonFormField<String>(
            initialValue: zonas.any((z) => z.codigo == _zonaSeleccionada) ? _zonaSeleccionada : zonas.first.codigo,
            isDense: true,
            decoration: InputDecoration(
              labelText: 'Zona UOCRA — por defecto ${_nombreZonaPorDefecto(zonas)}',
              labelStyle: const TextStyle(fontSize: 11),
              isDense: true,
            ),
            items: zonas
                .map((z) => DropdownMenuItem(value: z.codigo, child: Text(z.etiqueta, style: const TextStyle(fontSize: 12))))
                .toList(),
            onChanged: (v) => setState(() => _zonaSeleccionada = v ?? _zonaSeleccionada),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        campo,
        const SizedBox(height: 2),
        const Text(
          'La zona la determina la provincia donde se ejecuta la obra, no dónde está la sede de '
          'la empresa.',
          style: TextStyle(fontSize: 9, color: Colors.black45),
        ),
      ],
    );
  }
}
