import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/segurity/user_context.dart';
import '../../../core/utils/parser_numero_ar.dart';
import '../../../data/models/audit_log_entry.dart';
import '../../../data/models/modificacion_obra.dart';
import '../../../data/models/obra_subitem.dart';
import '../../../data/models/perfil_basico.dart';
import '../../../data/models/rubro_catalogo.dart';
import '../../../data/models/subitem_catalogo.dart';
import '../../../services/auth_service.dart';
import '../../../services/modificaciones_obra_repository.dart';
import '../../../services/obra_subitems_repository.dart';
import '../../../services/perfil_repository.dart';
import '../../../services/rubros_repository.dart';
import '../../../services/subitems_repository.dart';

/// Historial + aprobación de Demasías y Quitas de una obra — Gestión de Obra, circuito nuevo
/// (docs/adicionales_quitas_demasias_diagnostico.md). Deliberadamente NO incluye Adicionales
/// (tabla compartida, `tipo` distinto) — esa es una pieza de autoridad y seguimiento aparte,
/// pospuesta a propósito.
///
/// Dos caminos para llegar a registrar una: el botón "+" de acá (con selector de partida, para
/// cuando no se viene de cargar avance) y el ícono contextual por fila en
/// `CargaAvanceSubitemsScreen` (`mostrarDialogoCrearQuitaDemasia`, misma función, la partida ya
/// conocida de antemano) — los dos terminan en el mismo diálogo y el mismo
/// `ModificacionesObraRepository.crearQuitaDemasia`.
class QuitasDemasiasScreen extends StatefulWidget {
  final String obraId;
  final UserContext? userContext;

  const QuitasDemasiasScreen({Key? key, required this.obraId, required this.userContext}) : super(key: key);

  @override
  State<QuitasDemasiasScreen> createState() => _QuitasDemasiasScreenState();
}

class _QuitasDemasiasScreenState extends State<QuitasDemasiasScreen> {
  final ModificacionesObraRepository _repo = ModificacionesObraRepository();
  final ObraSubitemsRepository _obraSubitemsRepository = ObraSubitemsRepository();
  final SubitemsRepository _subitemsRepository = SubitemsRepository();
  final PerfilRepository _perfilRepository = PerfilRepository();
  final AuthService _authService = AuthService();

  bool _cargando = true;
  String? _error;
  List<ModificacionObra> _modificaciones = [];
  final Map<String, ObraSubitem> _obraSubitemPorId = {};
  final Map<String, SubitemCatalogo> _subitemCatalogoPorId = {};
  final Map<String, PerfilBasico> _perfilPorUsuarioId = {};

  final Set<String> _expandidas = {};
  final Map<String, List<AuditLogEntry>> _observacionesPorModificacion = {};
  final Set<String> _cargandoObservaciones = {};
  final Set<String> _resolviendo = {};

  bool get _puedeAprobar => widget.userContext?.puedeAprobarQuitaDemasia == true;
  bool get _puedeCrear => widget.userContext?.puedeCargarAvance == true;

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
      final modificaciones = await _repo.getQuitasDemasiasDeObra(widget.obraId);

      final obraSubitemIds = modificaciones
          .map((m) => m.obraSubitemId)
          .whereType<String>()
          .toSet()
          .toList();
      final obraSubitems = await _obraSubitemsRepository.getPorIds(obraSubitemIds);
      final subitemIds = obraSubitems.map((os) => os.subitemId).whereType<String>().toSet().toList();
      final subitemsCatalogo = await _subitemsRepository.getPorIds(subitemIds);

      final usuarioIds = <String>{
        for (final m in modificaciones) ...[m.solicitadoPor, if (m.aprobadoPor != null) m.aprobadoPor!],
      };
      // Silencioso ante error a propósito, igual que el resto de datos secundarios de Gestión de
      // Obra: si falla, la lista sigue funcionando mostrando el id crudo en vez del nombre.
      final perfiles = usuarioIds.isEmpty
          ? <PerfilBasico>[]
          : await _perfilRepository.getPerfilesDeObra(widget.obraId).catchError((_) => <PerfilBasico>[]);

      if (!mounted) return;
      setState(() {
        _modificaciones = modificaciones;
        _obraSubitemPorId
          ..clear()
          ..addEntries(obraSubitems.map((os) => MapEntry(os.id, os)));
        _subitemCatalogoPorId
          ..clear()
          ..addEntries(subitemsCatalogo.map((s) => MapEntry(s.id, s)));
        _perfilPorUsuarioId
          ..clear()
          ..addEntries(perfiles.map((p) => MapEntry(p.usuarioId, p)));
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar las demasías y quitas de esta obra.';
        _cargando = false;
      });
    }
  }

  String _descripcionPartida(ModificacionObra m) {
    final os = _obraSubitemPorId[m.obraSubitemId];
    if (os == null) return 'Partida (sin datos)';
    if (os.subitemId != null) {
      final cat = _subitemCatalogoPorId[os.subitemId];
      return cat != null ? '${cat.codigo} - ${cat.descripcion}' : 'Partida';
    }
    return os.descripcionLibre ?? 'Ítem sin descripción (OTRO)';
  }

  String _nombreUsuario(String usuarioId) => _perfilPorUsuarioId[usuarioId]?.nombre ?? usuarioId;

  String _fmtNum(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  String _fmtFecha(DateTime? f) => f == null ? '—' : '${f.day}/${f.month}/${f.year}';

  Color _colorEstado(EstadoModificacion e) {
    switch (e) {
      case EstadoModificacion.pendiente:
        return Colors.orange.shade700;
      case EstadoModificacion.devuelto:
        return Colors.amber.shade800;
      case EstadoModificacion.aprobado:
        return Colors.green.shade700;
      case EstadoModificacion.rechazado:
        return Colors.red.shade700;
    }
  }

  Future<void> _abrirCrear() async {
    final os = await _seleccionarPartida();
    if (os == null || !mounted) return;
    final creada = await mostrarDialogoCrearQuitaDemasia(
      context,
      obraId: widget.obraId,
      obraSubitem: os,
      descripcionPartida: _descripcionPartidaSuelta(os),
    );
    if (creada) await _cargarDatos();
  }

  String _descripcionPartidaSuelta(ObraSubitem os) {
    if (os.subitemId != null) {
      final cat = _subitemCatalogoPorId[os.subitemId];
      return cat != null ? '${cat.codigo} - ${cat.descripcion}' : 'Partida';
    }
    return os.descripcionLibre ?? 'Ítem sin descripción (OTRO)';
  }

  /// Selector de partida — solo para el "+" de esta pantalla, cuando no se viene ya con la
  /// partida en mano (a diferencia de `CargaAvanceSubitemsScreen`, que la conoce de entrada). Trae
  /// TODOS los tildados de la obra en una sola consulta (`getTildadosDeObra`, ya existente para la
  /// Solapa APU) y resuelve descripciones/rubros para una lista buscable.
  Future<ObraSubitem?> _seleccionarPartida() async {
    final usuarioId = _authService.usuarioActual?.id;
    List<ObraSubitem> obraSubitems;
    Map<String, RubroCatalogo> rubrosPorId = {};
    Map<String, SubitemCatalogo> subitemsPorId = {};
    try {
      obraSubitems = await _obraSubitemsRepository.getTildadosDeObra(widget.obraId);
      final subitemIds = obraSubitems.map((os) => os.subitemId).whereType<String>().toSet().toList();
      final subitemsCatalogo = await _subitemsRepository.getPorIds(subitemIds);
      subitemsPorId = {for (final s in subitemsCatalogo) s.id: s};
      if (usuarioId != null) {
        final rubros = await RubrosRepository().getCatalogoCompleto(usuarioId);
        rubrosPorId = {for (final r in rubros) r.id: r};
      }
    } catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo cargar el cómputo de la obra.')),
      );
      return null;
    }
    if (!mounted) return null;
    if (obraSubitems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Esta obra todavía no tiene partidas tildadas en el cómputo.')),
      );
      return null;
    }

    return showDialog<ObraSubitem>(
      context: context,
      builder: (ctx) => _SelectorPartidaDialog(
        obraSubitems: obraSubitems,
        rubrosPorId: rubrosPorId,
        subitemsPorId: subitemsPorId,
      ),
    );
  }

  Future<void> _resolver(ModificacionObra m, {required bool aprobar}) async {
    final usuarioId = _authService.usuarioActual?.id;
    if (usuarioId == null) return;
    final controller = TextEditingController();
    final comentario = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          aprobar ? 'Aprobar ${m.tipo.label.toLowerCase()}' : 'Rechazar ${m.tipo.label.toLowerCase()}',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 2,
          decoration: InputDecoration(labelText: aprobar ? 'Comentario (opcional)' : 'Motivo (opcional)', isDense: true),
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Volver')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(aprobar ? 'Aprobar' : 'Rechazar'),
          ),
        ],
      ),
    );
    if (comentario == null) return; // "Volver"

    setState(() => _resolviendo.add(m.id));
    try {
      if (aprobar) {
        await _repo.aprobarQuitaDemasia(modificacionId: m.id, comentario: comentario.isEmpty ? null : comentario);
      } else {
        await _repo.rechazarModificacion(
          modificacionId: m.id,
          usuarioId: usuarioId,
          motivo: comentario.isEmpty ? null : comentario,
        );
      }
      if (!mounted) return;
      setState(() => _resolviendo.remove(m.id));
      await _cargarDatos();
    } on PostgrestException catch (e) {
      debugPrint('QuitasDemasiasScreen._resolver (Postgrest) -- code=${e.code} message=${e.message}');
      if (!mounted) return;
      setState(() => _resolviendo.remove(m.id));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      debugPrint('QuitasDemasiasScreen._resolver: $e');
      if (!mounted) return;
      setState(() => _resolviendo.remove(m.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(aprobar ? 'No se pudo aprobar.' : 'No se pudo rechazar.')),
      );
    }
  }

  Future<void> _toggleObservaciones(ModificacionObra m) async {
    if (_expandidas.contains(m.id)) {
      setState(() => _expandidas.remove(m.id));
      return;
    }
    setState(() => _expandidas.add(m.id));
    if (_observacionesPorModificacion.containsKey(m.id)) return;
    setState(() => _cargandoObservaciones.add(m.id));
    try {
      final observaciones = await _repo.getObservaciones(m.id);
      if (!mounted) return;
      setState(() {
        _observacionesPorModificacion[m.id] = observaciones;
        _cargandoObservaciones.remove(m.id);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargandoObservaciones.remove(m.id));
    }
  }

  Future<void> _agregarObservacion(ModificacionObra m) async {
    final usuarioId = _authService.usuarioActual?.id;
    if (usuarioId == null) return;
    final controller = TextEditingController();
    final comentario = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Observación', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Queda registrado, no traba la aprobación.', isDense: true),
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          TextButton(
            onPressed: () {
              final texto = controller.text.trim();
              Navigator.pop(ctx, texto.isEmpty ? null : texto);
            },
            child: const Text('Comentar'),
          ),
        ],
      ),
    );
    if (comentario == null) return;
    try {
      await _repo.observar(
        obraId: widget.obraId,
        modificacionId: m.id,
        usuarioId: usuarioId,
        comentario: comentario,
      );
      final observaciones = await _repo.getObservaciones(m.id);
      if (!mounted) return;
      setState(() {
        _observacionesPorModificacion[m.id] = observaciones;
        _expandidas.add(m.id);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo guardar la observación.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quitas y Demasías', style: TextStyle(fontSize: 15)),
        backgroundColor: const Color(0xFF1B365D),
        foregroundColor: Colors.white,
      ),
      floatingActionButton: _puedeCrear
          ? FloatingActionButton(
              onPressed: _abrirCrear,
              backgroundColor: const Color(0xFF1B365D),
              child: const Icon(Icons.add),
            )
          : null,
      body: RefreshIndicator(onRefresh: _cargarDatos, child: _buildContenido()),
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
            child: Center(child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54))),
          ),
        ],
      );
    }
    if (_modificaciones.isEmpty) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.rule_outlined, color: Colors.black26, size: 32),
                  const SizedBox(height: 8),
                  const Text(
                    'Todavía no se registró ninguna demasía ni quita en esta obra.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12.0),
      itemCount: _modificaciones.length,
      itemBuilder: (context, index) => _buildFila(_modificaciones[index]),
    );
  }

  Widget _buildFila(ModificacionObra m) {
    final expandida = _expandidas.contains(m.id);
    final resolviendoEsta = _resolviendo.contains(m.id);
    final esDemasia = m.tipo == TipoModificacion.demasia;

    return Card(
      margin: const EdgeInsets.only(bottom: 10.0),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  esDemasia ? Icons.add_circle_outline : Icons.remove_circle_outline,
                  size: 18,
                  color: esDemasia ? Colors.blue.shade700 : Colors.deepOrange.shade700,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _descripcionPartida(m),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1B365D)),
                  ),
                ),
                Chip(
                  label: Text(m.estado.label, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  backgroundColor: _colorEstado(m.estado),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${m.tipo.label} de ${_fmtNum(m.cantidad)} — ${m.descripcion}',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              'Solicitado por ${_nombreUsuario(m.solicitadoPor)} el ${_fmtFecha(m.fechaSolicitud)}',
              style: const TextStyle(fontSize: 11, color: Colors.black45),
            ),
            if (m.estado != EstadoModificacion.pendiente && m.aprobadoPor != null)
              Text(
                '${m.estado == EstadoModificacion.aprobado ? "Aprobado" : "Rechazado"} por '
                '${_nombreUsuario(m.aprobadoPor!)} el ${_fmtFecha(m.fechaResolucion)}'
                '${m.comentarioResolucion != null && m.comentarioResolucion!.isNotEmpty ? " — ${m.comentarioResolucion}" : ""}',
                style: const TextStyle(fontSize: 11, color: Colors.black45, fontStyle: FontStyle.italic),
              ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                InkWell(
                  onTap: () => _toggleObservaciones(m),
                  child: Text(
                    expandida ? '▾ Observaciones' : '▸ Observaciones',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF1B365D), fontWeight: FontWeight.w600),
                  ),
                ),
                if (m.estado == EstadoModificacion.pendiente && _puedeAprobar)
                  resolviendoEsta
                      ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : Row(
                          children: [
                            TextButton(
                              onPressed: () => _resolver(m, aprobar: false),
                              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
                              child: Text('Rechazar', style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
                            ),
                            const SizedBox(width: 12),
                            TextButton(
                              onPressed: () => _resolver(m, aprobar: true),
                              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
                              child: const Text('Aprobar', style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
              ],
            ),
            if (expandida) _buildObservaciones(m),
          ],
        ),
      ),
    );
  }

  Widget _buildObservaciones(ModificacionObra m) {
    if (_cargandoObservaciones.contains(m.id)) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final observaciones = _observacionesPorModificacion[m.id] ?? [];
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (observaciones.isEmpty)
            const Text('Sin observaciones todavía.', style: TextStyle(fontSize: 11, color: Colors.black45)),
          ...observaciones.map((o) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${_nombreUsuario(o.usuarioId)}: ${o.detalle?['comentario'] ?? ''}',
                  style: const TextStyle(fontSize: 11.5),
                ),
              )),
          InkWell(
            onTap: () => _agregarObservacion(m),
            child: const Text(
              '+ Agregar observación',
              style: TextStyle(fontSize: 11, color: Color(0xFF1B365D), fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectorPartidaDialog extends StatefulWidget {
  final List<ObraSubitem> obraSubitems;
  final Map<String, RubroCatalogo> rubrosPorId;
  final Map<String, SubitemCatalogo> subitemsPorId;

  const _SelectorPartidaDialog({
    required this.obraSubitems,
    required this.rubrosPorId,
    required this.subitemsPorId,
  });

  @override
  State<_SelectorPartidaDialog> createState() => _SelectorPartidaDialogState();
}

class _SelectorPartidaDialogState extends State<_SelectorPartidaDialog> {
  String _filtro = '';

  String _label(ObraSubitem os) {
    final rubro = widget.rubrosPorId[os.rubroId]?.nombre ?? '';
    String desc;
    if (os.subitemId != null) {
      final cat = widget.subitemsPorId[os.subitemId];
      desc = cat != null ? '${cat.codigo} - ${cat.descripcion}' : 'Partida';
    } else {
      desc = os.descripcionLibre ?? 'Ítem sin descripción (OTRO)';
    }
    return rubro.isEmpty ? desc : '$rubro · $desc';
  }

  @override
  Widget build(BuildContext context) {
    final filtrados = widget.obraSubitems.where((os) {
      if (_filtro.isEmpty) return true;
      return _label(os).toLowerCase().contains(_filtro.toLowerCase());
    }).toList();

    return AlertDialog(
      title: const Text('Elegir partida', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Buscar...', isDense: true, prefixIcon: Icon(Icons.search, size: 18)),
              style: const TextStyle(fontSize: 13),
              onChanged: (v) => setState(() => _filtro = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filtrados.isEmpty
                  ? const Center(child: Text('Sin resultados.', style: TextStyle(color: Colors.black45, fontSize: 12)))
                  : ListView.builder(
                      itemCount: filtrados.length,
                      itemBuilder: (context, index) {
                        final os = filtrados[index];
                        return ListTile(
                          dense: true,
                          title: Text(_label(os), style: const TextStyle(fontSize: 13)),
                          subtitle: Text('Cantidad actual: ${os.cantidad}', style: const TextStyle(fontSize: 11)),
                          onTap: () => Navigator.pop(context, os),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
      ],
    );
  }
}

/// Diálogo de alta de una demasía/quita sobre UNA partida ya conocida — usado tanto por el "+" de
/// `QuitasDemasiasScreen` (después de elegir partida) como por el ícono contextual de
/// `CargaAvanceSubitemsScreen` (la partida es la fila que se estaba cargando). Devuelve `true` si
/// se creó, `false`/nada si se canceló.
Future<bool> mostrarDialogoCrearQuitaDemasia(
  BuildContext context, {
  required String obraId,
  required ObraSubitem obraSubitem,
  required String descripcionPartida,
}) async {
  final authService = AuthService();
  final usuarioId = authService.usuarioActual?.id;
  if (usuarioId == null) return false;

  final resultado = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (ctx) => _CrearQuitaDemasiaDialog(descripcionPartida: descripcionPartida, cantidadActual: obraSubitem.cantidad),
  );
  if (resultado == null) return false;

  try {
    await ModificacionesObraRepository().crearQuitaDemasia(
      obraId: obraId,
      obraSubitemId: obraSubitem.id,
      tipo: resultado['tipo'] as TipoModificacion,
      cantidad: resultado['cantidad'] as double,
      descripcion: resultado['descripcion'] as String,
      usuarioId: usuarioId,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registrado. Queda pendiente de aprobación.')),
      );
    }
    return true;
  } on PostgrestException catch (e) {
    debugPrint('mostrarDialogoCrearQuitaDemasia (Postgrest) -- code=${e.code} message=${e.message}');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
    return false;
  } catch (e) {
    debugPrint('mostrarDialogoCrearQuitaDemasia: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo registrar.')),
      );
    }
    return false;
  }
}

class _CrearQuitaDemasiaDialog extends StatefulWidget {
  final String descripcionPartida;
  final double cantidadActual;

  const _CrearQuitaDemasiaDialog({required this.descripcionPartida, required this.cantidadActual});

  @override
  State<_CrearQuitaDemasiaDialog> createState() => _CrearQuitaDemasiaDialogState();
}

class _CrearQuitaDemasiaDialogState extends State<_CrearQuitaDemasiaDialog> {
  TipoModificacion _tipo = TipoModificacion.demasia;
  final _cantidadController = TextEditingController();
  final _descripcionController = TextEditingController();

  @override
  void dispose() {
    _cantidadController.dispose();
    _descripcionController.dispose();
    super.dispose();
  }

  void _confirmar() {
    final cantidad = ParserNumeroAr.parsear(_cantidadController.text.trim());
    if (cantidad == null || cantidad <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La cantidad tiene que ser mayor a 0.')),
      );
      return;
    }
    if (_tipo == TipoModificacion.quita && cantidad > widget.cantidadActual) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('La quita ($cantidad) es mayor que la cantidad actual (${widget.cantidadActual}).')),
      );
      return;
    }
    final descripcion = _descripcionController.text.trim();
    if (descripcion.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Contá qué pasó -- queda como el motivo registrado.')),
      );
      return;
    }
    Navigator.pop(context, {'tipo': _tipo, 'cantidad': cantidad, 'descripcion': descripcion});
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Registrar demasía o quita', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.descripcionPartida, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            Text('Cantidad actual: ${widget.cantidadActual}', style: const TextStyle(fontSize: 11, color: Colors.black45)),
            const SizedBox(height: 12),
            SegmentedButton<TipoModificacion>(
              segments: const [
                ButtonSegment(value: TipoModificacion.demasia, label: Text('Demasía', style: TextStyle(fontSize: 12))),
                ButtonSegment(value: TipoModificacion.quita, label: Text('Quita', style: TextStyle(fontSize: 12))),
              ],
              selected: {_tipo},
              onSelectionChanged: (s) => setState(() => _tipo = s.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _cantidadController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: _tipo == TipoModificacion.demasia ? 'Cuánto se agrega' : 'Cuánto se quita',
                isDense: true,
              ),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descripcionController,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Qué pasó', isDense: true),
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        TextButton(onPressed: _confirmar, child: const Text('Registrar')),
      ],
    );
  }
}
