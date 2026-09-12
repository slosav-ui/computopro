import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/segurity/user_context.dart';
import '../../../core/utils/conversion_dolar.dart';
import '../../../core/utils/parser_numero_ar.dart';
import '../../../data/models/modificacion_obra.dart';
import '../../../data/models/perfil_basico.dart';
import '../../../services/adicionales_repository.dart';
import '../../../services/auth_service.dart';
import '../../../services/indices_economicos_repository.dart';
import '../../../services/obras_repository.dart';
import '../../../services/perfil_repository.dart';
import 'presupuestos_screen.dart';

/// Historial, creación y aprobación de Adicionales de una obra (docs/adicionales_quitas_demasias_
/// diagnostico.md §11/§12/§13). Todavía SIN seguimiento de avance certificado (Tanda 2, después).
///
/// Circuito de aprobación (0116, §13.6): un adicional presupuestado con la app lo **envía** quien lo
/// cotiza (congela la obra hija con sus recetas y precios -- "te mandan un presupuesto cerrado, no
/// una hoja de cálculo abierta") y recién ahí se puede aprobar; uno de monto fijo se aprueba
/// directo. Aprobar/rechazar: solo cliente_principal o apoderado habilitado (§7-B) -- el tope del
/// apoderado lo valida la base contra el monto real, este tile solo lo anticipa.
///
/// El "+" ofrece las 3 vías de carga (§12.6): **Monto fijo** (Tanda 1, un precio cerrado, cascada
/// de Factor K aplicada sobre un costo tipeado a mano), **Presupuestar con la app** (la principal
/// -- crea una obra hija con Factor K propio y precios de hoy, con las mismas solapas de Rubros/
/// APU/Materiales que una obra real, "obra dentro de obra") y **Importar de Excel/PDF** (todavía
/// sin conectar, mismo importador de la Solapa Cómputo).
///
/// Mismo criterio de creación que Quitas/Demasías (ambigüedad E, cerrada por Seba): cualquier
/// miembro de la obra puede solicitar uno, sin gate de rol -- "la barrera real es la aprobación".
class AdicionalesScreen extends StatefulWidget {
  final String obraId;
  final UserContext? userContext;

  const AdicionalesScreen({Key? key, required this.obraId, required this.userContext}) : super(key: key);

  @override
  State<AdicionalesScreen> createState() => _AdicionalesScreenState();
}

class _AdicionalesScreenState extends State<AdicionalesScreen> {
  final AdicionalesRepository _repo = AdicionalesRepository();
  final ObrasRepository _obrasRepository = ObrasRepository();
  final IndicesEconomicosRepository _indicesRepository = IndicesEconomicosRepository();
  final PerfilRepository _perfilRepository = PerfilRepository();
  final AuthService _authService = AuthService();

  bool _cargando = true;
  String? _error;
  List<ModificacionObra> _adicionales = [];
  final Map<String, PerfilBasico> _perfilPorUsuarioId = {};

  String _moneda = 'ARS';
  double _cotizacionHoy = 0;

  // Adicionales con una transición en curso (enviar/aprobar/rechazar) -- spinner en su tile en vez
  // de los botones, mismo patrón que QuitasDemasiasScreen.
  final Set<String> _resolviendo = {};

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
      final adicionalesFuture = _repo.getAdicionalesDeObra(widget.obraId);
      final monedaFuture = _obrasRepository.getMoneda(widget.obraId);
      final cotizacionFuture = _indicesRepository.getCotizacionDolar();

      final adicionales = await adicionalesFuture;
      final moneda = await monedaFuture;
      final cotizacion = await cotizacionFuture;

      final usuarioIds = <String>{for (final a in adicionales) a.solicitadoPor};
      // Silencioso ante error a propósito, mismo criterio que QuitasDemasiasScreen: sin nombres,
      // la lista sigue funcionando mostrando el id crudo.
      final perfiles = usuarioIds.isEmpty
          ? <PerfilBasico>[]
          : await _perfilRepository.getPerfilesDeObra(widget.obraId).catchError((_) => <PerfilBasico>[]);

      if (!mounted) return;
      setState(() {
        _adicionales = adicionales;
        _moneda = moneda;
        _cotizacionHoy = cotizacion?.promedio ?? 0;
        _perfilPorUsuarioId
          ..clear()
          ..addEntries(perfiles.map((p) => MapEntry(p.usuarioId, p)));
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar los adicionales de esta obra.';
        _cargando = false;
      });
    }
  }

  String _nombreUsuario(String usuarioId) => _perfilPorUsuarioId[usuarioId]?.nombre ?? usuarioId;

  String _fmtFecha(DateTime? f) => f == null ? '—' : '${f.day}/${f.month}/${f.year}';

  /// `montoArs`: siempre en pesos (el sistema de precios entero trabaja en ARS) -- convierte a la
  /// moneda de la obra antes de formatear, mismo patrón que el resto de Gestión de Obra.
  String _fmtMonto(double montoArs) {
    final convertido = convertirArsAMoneda(montoArs, _moneda, _cotizacionHoy);
    final valorInt = convertido.round();
    final str = valorInt.toString();
    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    final formateado = str.replaceAllMapped(reg, (Match m) => '${m[1]}.');
    return _moneda == 'USD' ? 'USD $formateado' : '\$ $formateado';
  }

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

  /// Tres vías de carga (docs/adicionales_quitas_demasias_diagnostico.md §12.6) -- el "+" elige
  /// primero cuál, después dispara el flujo que corresponda. "Monto fijo" es la Tanda 1 tal cual
  /// ya estaba; las otras dos son la corrección de alcance de §12 ("una obra dentro de una obra").
  Future<void> _abrirCrear() async {
    final via = await showDialog<_ViaCargaAdicional>(
      context: context,
      builder: (ctx) => const _SelectorViaAdicionalDialog(),
    );
    if (via == null || !mounted) return;
    switch (via) {
      case _ViaCargaAdicional.montoFijo:
        await _crearMontoFijo();
      case _ViaCargaAdicional.presupuestar:
        await _crearPresupuestado();
      case _ViaCargaAdicional.importar:
        await _mostrarImportarProximamente();
    }
  }

  Future<void> _crearMontoFijo() async {
    final usuarioId = _authService.usuarioActual?.id;
    if (usuarioId == null) return;
    final creado = await showDialog<bool>(
      context: context,
      builder: (ctx) => _CrearAdicionalDialog(
        obraId: widget.obraId,
        usuarioId: usuarioId,
        moneda: _moneda,
        cotizacionHoy: _cotizacionHoy,
      ),
    );
    if (creado == true) await _cargarDatos();
  }

  /// "Presupuestar con la app" (§12.6) -- pide solo la descripción (el costo sale de tildar
  /// partidas en la obra hija, no se tipea acá), crea la obra hija + el adicional ya vinculado en
  /// una sola llamada (`crear_adicional_presupuestado`, 0113), y navega directo a sus solapas.
  Future<void> _crearPresupuestado() async {
    final controller = TextEditingController();
    final descripcion = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Presupuestar adicional', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Descripción', isDense: true),
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
    if (descripcion == null || !mounted) return;

    try {
      final adicional = await _repo.crearAdicionalPresupuestado(
        obraId: widget.obraId,
        descripcion: descripcion,
      );
      if (!mounted) return;
      await _cargarDatos();
      if (!mounted || adicional.obraHijaId == null) return;
      await _abrirObraHija(adicional.obraHijaId!);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo crear el adicional.')),
      );
    }
  }

  /// Navega a las solapas de la obra hija (Rubros/APU/Mat y MO/Resumen/Proveedores -- sin Gestión
  /// de Obra, ver `PresupuestosScreen`) para seguir presupuestando un adicional ya creado por esta
  /// vía. Trae la fila completa porque `PresupuestosScreen` espera el mapa de la obra, no solo el
  /// id.
  Future<void> _abrirObraHija(String obraHijaId) async {
    try {
      final obraHija = await _obrasRepository.getObraPorId(obraHijaId);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PresupuestosScreen(obra: obraHija)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el presupuesto de este adicional.')),
      );
    }
  }

  Future<void> _mostrarImportarProximamente() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Importar de Excel/PDF', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        content: const Text(
          'Todavía no está conectado para adicionales. Mientras tanto, usá "Presupuestar con la '
          'app" y cargá el cómputo desde ahí.',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido')),
        ],
      ),
    );
  }

  /// Corre una transición con el spinner del tile y recarga SIEMPRE al terminar -- también ante
  /// error: si `aprobar_adicional` rechaza porque el monto cambió desde que se abrió la lista, la
  /// lista tiene que mostrar el monto nuevo antes de volver a intentar. El error real ya queda en
  /// consola (`AdicionalesRepository._conLog`); acá solo se muestra el mensaje.
  Future<void> _transicion(
    ModificacionObra m,
    Future<String> Function() accion,
    String errorGenerico,
  ) async {
    setState(() => _resolviendo.add(m.id));
    String mensaje;
    try {
      mensaje = await accion();
    } on PostgrestException catch (e) {
      mensaje = e.message;
    } catch (_) {
      mensaje = errorGenerico;
    }
    if (!mounted) return;
    setState(() => _resolviendo.remove(m.id));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
    await _cargarDatos();
  }

  Future<void> _enviar(ModificacionObra m) async {
    final reenvio = m.enviadoAAprobacionEn != null;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          reenvio ? 'Reenviar para aprobación' : 'Enviar para aprobación',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        content: Text(
          '${reenvio ? "Se vuelve a congelar" : "Se congela"} el presupuesto de este adicional con las '
          'cantidades y los precios de hoy, y el cliente va a aprobar ese número. Si después cambiás '
          'algo del cómputo, lo tenés que reenviar.',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Volver')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(reenvio ? 'Reenviar' : 'Enviar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;
    await _transicion(m, () async {
      final monto = await _repo.enviarAAprobacion(m.id);
      return 'Enviado para aprobación: ${_fmtMonto(monto)}';
    }, 'No se pudo enviar el adicional.');
  }

  Future<void> _aprobar(ModificacionObra m) async {
    final comentario = await _pedirComentario(
      titulo: 'Aprobar adicional',
      detalle: 'Vas a aprobar ${_fmtMonto(m.montoTotal)} por "${m.descripcion}". Queda fijo: no se '
          'vuelve a recalcular.',
      etiqueta: 'Comentario (opcional)',
      accion: 'Aprobar',
    );
    if (comentario == null || !mounted) return;
    await _transicion(m, () async {
      // El monto crudo de la fila (pesos, sin redondear ni convertir) -- el mismo contra el que la
      // base compara, no el texto formateado de arriba.
      final monto = await _repo.aprobarAdicional(
        modificacionId: m.id,
        montoVisto: m.montoTotal,
        comentario: comentario.isEmpty ? null : comentario,
      );
      return 'Adicional aprobado: ${_fmtMonto(monto)}';
    }, 'No se pudo aprobar el adicional.');
  }

  Future<void> _rechazar(ModificacionObra m) async {
    final motivo = await _pedirComentario(
      titulo: 'Rechazar adicional',
      detalle: '"${m.descripcion}" queda rechazado y no se puede volver a enviar.',
      etiqueta: 'Motivo (opcional)',
      accion: 'Rechazar',
    );
    if (motivo == null || !mounted) return;
    await _transicion(m, () async {
      await _repo.rechazarAdicional(modificacionId: m.id, comentario: motivo.isEmpty ? null : motivo);
      return 'Adicional rechazado.';
    }, 'No se pudo rechazar el adicional.');
  }

  /// `null` = "Volver"; texto vacío = confirmó sin comentario.
  Future<String?> _pedirComentario({
    required String titulo,
    required String detalle,
    required String etiqueta,
    required String accion,
  }) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(detalle, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              maxLines: 2,
              decoration: InputDecoration(labelText: etiqueta, isDense: true),
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Volver')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(accion),
          ),
        ],
      ),
    );
  }

  Widget _buildAdicional(ModificacionObra m) {
    final esPendiente = m.estado == EstadoModificacion.pendiente;
    final esPresupuestado = m.obraHijaId != null;
    final enviado = m.enviadoAAprobacionEn != null;
    // En preparación: presupuestado con la app y todavía sin enviar -- monto_total sigue en 0 hasta
    // que quien lo cotiza lo envía (0116); mostrar "$ 0" ahí sería mentir por omisión, mismo
    // criterio que el chip de desfasaje del dashboard.
    final enPreparacion = esPresupuestado && esPendiente && !enviado;

    final ctx = widget.userContext;
    final puedeEnviar =
        esPresupuestado && esPendiente && ctx?.puedeEnviarAdicional(solicitadoPor: m.solicitadoPor) == true;
    final puedeRechazar = esPendiente && ctx?.puedeRechazarAdicional == true;
    // Un presupuestado solo se aprueba una vez enviado -- antes no hay número que aprobar.
    final aprobable = esPendiente && (!esPresupuestado || enviado);
    final puedeAprobar = aprobable && ctx?.puedeAprobarAdicional(m.montoTotal) == true;
    final superaTope = aprobable && puedeRechazar && !puedeAprobar;
    final resolviendoEste = _resolviendo.contains(m.id);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: esPresupuestado ? () => _abrirObraHija(m.obraHijaId!) : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      m.descripcion,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                    ),
                  ),
                  Chip(
                    label: Text(
                      m.estado.label,
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                    backgroundColor: _colorEstado(m.estado),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              if (enPreparacion)
                const Text(
                  'Presupuestándose con la app -- tocá para seguir cargando el cómputo.',
                  style: TextStyle(fontSize: 12.5, color: Colors.black54, fontStyle: FontStyle.italic),
                )
              else
                Text(
                  _fmtMonto(m.montoTotal),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1B365D)),
                ),
              const SizedBox(height: 2),
              Wrap(
                spacing: 8,
                children: [
                  if (!m.incluyeImpuestos)
                    const Text('Sin impuestos', style: TextStyle(fontSize: 10.5, color: Colors.black45)),
                  if (!m.incluyeMateriales)
                    const Text('Sin materiales', style: TextStyle(fontSize: 10.5, color: Colors.black45)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Solicitado por ${_nombreUsuario(m.solicitadoPor)} — ${_fmtFecha(m.fechaSolicitud)}',
                style: const TextStyle(fontSize: 10.5, color: Colors.black38),
              ),
              if (esPendiente && !esPresupuestado)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'Todavía es una propuesta, pendiente de aprobación.',
                    style: TextStyle(fontSize: 10, color: Colors.black38, fontStyle: FontStyle.italic),
                  ),
                ),
              if (esPendiente && esPresupuestado && enviado)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Enviado para aprobación el ${_fmtFecha(m.enviadoAAprobacionEn)}. Si se cambia el '
                    'cómputo, hay que reenviarlo.',
                    style: const TextStyle(fontSize: 10, color: Colors.black38, fontStyle: FontStyle.italic),
                  ),
                ),
              if (!esPendiente && m.aprobadoPor != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${m.estado.label} por ${_nombreUsuario(m.aprobadoPor!)} el ${_fmtFecha(m.fechaResolucion)}'
                    '${m.comentarioResolucion != null && m.comentarioResolucion!.isNotEmpty ? " — ${m.comentarioResolucion}" : ""}',
                    style: const TextStyle(fontSize: 11, color: Colors.black45, fontStyle: FontStyle.italic),
                  ),
                ),
              if (superaTope)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Supera tu tope de aprobación -- lo tiene que aprobar el cliente principal.',
                    style: TextStyle(fontSize: 10.5, color: Colors.red.shade700),
                  ),
                ),
              if (puedeEnviar || puedeRechazar || puedeAprobar)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: resolviendoEste
                        ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        // Wrap, no Row: en pantalla angosta los tres botones pasan de renglón en
                        // vez de desbordar.
                        : Wrap(
                            spacing: 12,
                            runSpacing: 4,
                            alignment: WrapAlignment.end,
                            children: [
                              if (puedeEnviar)
                                TextButton(
                                  onPressed: () => _enviar(m),
                                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
                                  child: Text(
                                    enviado ? 'Reenviar' : 'Enviar para aprobación',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              if (puedeRechazar)
                                TextButton(
                                  onPressed: () => _rechazar(m),
                                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
                                  child: Text('Rechazar', style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
                                ),
                              if (puedeAprobar)
                                TextButton(
                                  onPressed: () => _aprobar(m),
                                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
                                  child: const Text('Aprobar', style: TextStyle(fontSize: 12)),
                                ),
                            ],
                          ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Adicionales', style: TextStyle(fontSize: 15)),
        backgroundColor: const Color(0xFF1B365D),
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.add), tooltip: 'Nuevo adicional', onPressed: _abrirCrear),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.black54)))
              : _adicionales.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Todavía no hay adicionales cargados para esta obra.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.black54),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _adicionales.length,
                      itemBuilder: (context, index) => _buildAdicional(_adicionales[index]),
                    ),
    );
  }
}

enum _ViaCargaAdicional { montoFijo, presupuestar, importar }

/// Las tres vías de carga (§12.6) -- se muestra antes de cualquier diálogo de datos, para que el
/// usuario elija con qué mecanismo va a cotizar el adicional. "Monto fijo" es la Tanda 1 (un
/// precio cerrado, ya negociado); "Presupuestar con la app" es la principal (cómputo real, precios
/// de hoy, Factor K propio); "Importar" reusa el importador de la Solapa Cómputo, todavía sin
/// conectar para adicionales.
class _SelectorViaAdicionalDialog extends StatelessWidget {
  const _SelectorViaAdicionalDialog();

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text('¿Cómo cargás este adicional?', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
      children: [
        _buildOpcion(
          context,
          via: _ViaCargaAdicional.presupuestar,
          icono: Icons.calculate_outlined,
          titulo: 'Presupuestar con la app',
          subtitulo: 'Cómputo, APU y materiales, a los precios de hoy -- la vía principal.',
        ),
        _buildOpcion(
          context,
          via: _ViaCargaAdicional.montoFijo,
          icono: Icons.attach_money,
          titulo: 'Monto fijo',
          subtitulo: 'Ya tenés un precio cerrado, sin nada que computar.',
        ),
        _buildOpcion(
          context,
          via: _ViaCargaAdicional.importar,
          icono: Icons.upload_file_outlined,
          titulo: 'Importar de Excel/PDF',
          subtitulo: 'Igual que el importador de la Solapa Cómputo.',
        ),
      ],
    );
  }

  Widget _buildOpcion(
    BuildContext context, {
    required _ViaCargaAdicional via,
    required IconData icono,
    required String titulo,
    required String subtitulo,
  }) {
    return SimpleDialogOption(
      onPressed: () => Navigator.pop(context, via),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 20, color: const Color(0xFF1B365D)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                const SizedBox(height: 2),
                Text(subtitulo, style: const TextStyle(fontSize: 11, color: Colors.black54)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Crear un adicional nuevo -- sin modo edición: `modificaciones_obra_update` (0109) solo deja
/// tocar una fila `pendiente` a quien puede aprobarla, no a quien la subió (esa rama de la
/// política solo aplica con `estado = 'devuelto'`) -- mismo límite que ya tiene Quitas/Demasías
/// (sin edición, solo aprobar/rechazar). Vista previa del monto recalculada en cada cambio de
/// costo o del toggle de impuestos, contra `calcular_precio_adicional` -- el mismo cálculo que el
/// trigger de la base va a aplicar al guardar, para que no haya sorpresa entre lo que se ve acá y
/// lo que queda guardado.
class _CrearAdicionalDialog extends StatefulWidget {
  final String obraId;
  final String usuarioId;
  final String moneda;
  final double cotizacionHoy;

  const _CrearAdicionalDialog({
    required this.obraId,
    required this.usuarioId,
    required this.moneda,
    required this.cotizacionHoy,
  });

  @override
  State<_CrearAdicionalDialog> createState() => _CrearAdicionalDialogState();
}

class _CrearAdicionalDialogState extends State<_CrearAdicionalDialog> {
  final AdicionalesRepository _repo = AdicionalesRepository();
  final TextEditingController _descripcionController = TextEditingController();
  final TextEditingController _costoController = TextEditingController();
  bool _incluyeMateriales = true;
  bool _incluyeImpuestos = true;

  double? _previa;
  bool _calculando = false;
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _descripcionController.dispose();
    _costoController.dispose();
    super.dispose();
  }

  String _fmtMonto(double montoArs) {
    final convertido = convertirArsAMoneda(montoArs, widget.moneda, widget.cotizacionHoy);
    final valorInt = convertido.round();
    final str = valorInt.toString();
    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    final formateado = str.replaceAllMapped(reg, (Match m) => '${m[1]}.');
    return widget.moneda == 'USD' ? 'USD $formateado' : '\$ $formateado';
  }

  Future<void> _recalcular() async {
    final costo = ParserNumeroAr.parsear(_costoController.text.trim());
    if (costo == null || costo < 0) {
      setState(() => _previa = null);
      return;
    }
    setState(() => _calculando = true);
    try {
      final previa = await _repo.previsualizarPrecioAdicional(
        obraId: widget.obraId,
        costoCostoBase: costo,
        incluyeImpuestos: _incluyeImpuestos,
      );
      if (!mounted) return;
      setState(() {
        _previa = previa;
        _calculando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _calculando = false);
    }
  }

  Future<void> _guardar() async {
    final descripcion = _descripcionController.text.trim();
    if (descripcion.isEmpty) {
      setState(() => _error = 'Describí de qué se trata el adicional.');
      return;
    }
    final costo = ParserNumeroAr.parsear(_costoController.text.trim());
    if (costo == null || costo < 0) {
      setState(() => _error = 'Ingresá un costo válido, mayor o igual a 0.');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await _repo.crearAdicional(
        obraId: widget.obraId,
        descripcion: descripcion,
        costoCostoBase: costo,
        incluyeMateriales: _incluyeMateriales,
        incluyeImpuestos: _incluyeImpuestos,
        usuarioId: widget.usuarioId,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _error = 'No se pudo crear el adicional.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nuevo adicional', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _descripcionController,
              autofocus: true,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Descripción', isDense: true),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _costoController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Costo (antes de Gastos Generales, Beneficio, etc.)',
                isDense: true,
              ),
              style: const TextStyle(fontSize: 13),
              onChanged: (_) => _recalcular(),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Incluye materiales', style: TextStyle(fontSize: 12.5)),
              value: _incluyeMateriales,
              onChanged: (v) => setState(() => _incluyeMateriales = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Lleva impuestos', style: TextStyle(fontSize: 12.5)),
              value: _incluyeImpuestos,
              onChanged: (v) {
                setState(() => _incluyeImpuestos = v);
                _recalcular();
              },
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6)),
              child: Row(
                children: [
                  const Text('Precio final: ', style: TextStyle(fontSize: 12.5, color: Colors.black54)),
                  if (_calculando)
                    const SizedBox(height: 12, width: 12, child: CircularProgressIndicator(strokeWidth: 2))
                  else
                    Text(
                      _previa != null ? _fmtMonto(_previa!) : '—',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1B365D)),
                    ),
                ],
              ),
            ),
            // Ya aplica la cascada de Factor K del contrato (GG, Imprevistos, EPP, Costo
            // Financiero, Beneficio) + impuestos si el toggle está activo -- los 6 conceptos NO se
            // eligen acá, se heredan tal cual (decisión de Seba, 2026-09-13: "son la estructura de
            // costos del contratista, no algo que el cliente elija").
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Ya incluye Gastos Generales, Imprevistos, EPP, Costo Financiero y Beneficio del '
                'contrato -- esos no se eligen por adicional.',
                style: TextStyle(fontSize: 10, color: Colors.black45, fontStyle: FontStyle.italic),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(fontSize: 11.5, color: Colors.red.shade700)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: _guardando ? null : _guardar,
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B365D)),
          child: _guardando
              ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Crear', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
