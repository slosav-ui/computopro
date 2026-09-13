import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/segurity/user_context.dart';
import '../../../core/utils/conversion_dolar.dart';
import '../../../core/utils/periodo_certificacion.dart';
import '../../../data/models/certificado.dart';
import '../../../data/models/certificado_subitem_avance.dart';
import '../../../data/models/obra_config_certificacion.dart';
import '../../../data/models/rubro_catalogo.dart';
import '../../../services/auth_service.dart';
import '../../../services/certificados_repository.dart';
import '../../../services/indices_economicos_repository.dart';
import '../../../services/certificado_subitems_avance_repository.dart';
import '../../../services/obra_config_certificacion_repository.dart';
import '../../../services/rubros_repository.dart';
import '../../../services/obras_repository.dart';
import '../screens/adicionales_screen.dart';
import '../screens/carga_avance_rubros_screen.dart';
import '../screens/detalle_certificado_screen.dart';
import '../screens/quitas_demasias_screen.dart';
import 'barra_acciones_obra.dart';
import 'panel_avance_obra.dart';
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
  final CertificadosRepository _certificadosRepository =
      CertificadosRepository();
  final AuthService _authService = AuthService();
  final ObrasRepository _obrasRepository = ObrasRepository();
  final ObraConfigCertificacionRepository _configRepository =
      ObraConfigCertificacionRepository();
  final IndicesEconomicosRepository _indicesRepository =
      IndicesEconomicosRepository();
  final CertificadoSubitemsAvanceRepository _avanceRepository =
      CertificadoSubitemsAvanceRepository();
  final RubrosRepository _rubrosRepository = RubrosRepository();

  List<Certificado> _certificados = [];
  bool _cargando = true;
  String? _error;
  String _moneda = 'ARS';
  double _cotizacionHoy = 0;

  // Los anulados son información histórica, no algo que se mira todos los días -- corrección de
  // Seba (2026-09-12): antes ocupaban el mismo lugar (misma Card completa) que un certificado
  // vigente en la lista, y con más de uno o dos empezaban a dominar la solapa. Colapsados por
  // default, en su propia sección al final -- se conservan (nunca se borran, 0056) pero no compiten
  // por espacio con lo que sí hay que mirar seguido.
  bool _anuladosExpandido = false;

  // Avance certificado (auditoría §2.1: se calculaba desde la 0052 y no se mostraba en ninguna
  // pantalla). null = todavía no cargó o falló -> el panel no se dibuja, no afirma un 0% que no
  // sabe. El catálogo de rubros es solo para ponerle nombre a cada `rubro_id` que devuelve la RPC.
  double? _avancePct;
  List<AvancePonderadoRubro> _avancePorRubro = [];
  List<RubroCatalogo> _catalogoRubros = [];

  @override
  void initState() {
    super.initState();
    _cargarCertificados();
    _cargarMoneda();
    _cargarAvance();
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

  /// Avance certificado de la obra + el desglose por rubro + el catálogo para los nombres. Las tres
  /// en paralelo: ninguna depende de la otra.
  ///
  /// Silencioso ante error y fail-safe a `null`, mismo criterio que `_cargarMoneda` y que el resto
  /// de los datos secundarios de esta solapa: si falla, la solapa sigue mostrando los certificados
  /// sin el panel de avance. Nunca al revés -- el historial es lo que la gente vino a ver.
  Future<void> _cargarAvance() async {
    try {
      final usuarioId = _authService.usuarioActual?.id;
      final avanceFuture = _avanceRepository.getAvancePonderadoObra(widget.obraId);
      final rubrosFuture = _avanceRepository.getAvancePonderadoRubros(widget.obraId);
      // Mismo par de llamadas que usa CargaAvanceRubrosScreen para los nombres: el catálogo completo
      // si hay usuario (incluye sus rubros propios), el oficial si no.
      final catalogoFuture = usuarioId == null
          ? _rubrosRepository.getCatalogoOficial()
          : _rubrosRepository.getCatalogoCompleto(usuarioId);
      final avance = await avanceFuture;
      final porRubro = await rubrosFuture;
      final catalogo = await catalogoFuture;
      if (!mounted) return;
      setState(() {
        _avancePct = avance;
        _avancePorRubro = porRubro;
        _catalogoRubros = catalogo;
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
      final certs = await _certificadosRepository.getCertificadosDeObra(
        widget.obraId,
      );
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
        builder: (_) => QuitasDemasiasScreen(
          obraId: widget.obraId,
          userContext: widget.userContext,
        ),
      ),
    );
    // Aprobar una demasía/quita cambia obra_subitems.cantidad -- no afecta a esta lista de
    // certificados, así que no hace falta recargar acá (a diferencia de _abrirDetalle/
    // _abrirCargaAvance, que sí tocan certificados).
  }

  Future<void> _abrirAdicionales() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdicionalesScreen(
          obraId: widget.obraId,
          userContext: widget.userContext,
        ),
      ),
    );
    // Un adicional aprobado nunca entra al cómputo/certificación (decisión ya cerrada, §4 del
    // diagnóstico: "diluiría el % de avance") -- no afecta esta lista de certificados, no hace
    // falta recargar acá, mismo criterio que _abrirQuitasDemasias.
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
    final borradorExistente = await _certificadosRepository.getBorradorAbierto(
      widget.obraId,
    );
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

  /// Sugiere el período según la periodicidad pactada en la obra (`0123`): el mes si es mensual, la
  /// quincena si es quincenal, la semana si es semanal, y el mes actual si no se pactó ninguna --
  /// que es exactamente lo que sugería antes de la 0123. El texto se arma en `periodoSugerido`; el
  /// cierre del período lo resuelve la base (`proximo_periodo_certificacion`), acá no se recalcula
  /// el ancla. Ver docs/certificacion_acuerdo_partes_diagnostico.md §3.2.
  ///
  /// Sugerencia, no candado: el campo queda editable y `periodo` sigue siendo texto libre.
  ///
  /// Si algo de los dos datos falla (red, permisos), se sugiere igual con lo que haya -- crear un
  /// certificado no puede depender de que el sugerido se pueda calcular.
  Future<String?> _pedirPeriodo() async {
    PeriodicidadCertificacion? periodicidad;
    DateTime? cierrePeriodo;
    try {
      final config = await _configRepository.getConfig(widget.obraId);
      periodicidad = config.periodicidadCertificacion;
      if (periodicidad != null) {
        cierrePeriodo = await _configRepository.getProximoPeriodo(widget.obraId);
      }
    } catch (_) {
      // Silencioso a propósito -- ver el comentario de cabecera.
    }
    if (!mounted) return null;
    final sugerido = periodoSugerido(periodicidad: periodicidad, cierrePeriodo: cierrePeriodo);
    final controller = TextEditingController(text: sugerido);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Nuevo certificado',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Período',
            isDense: true,
          ),
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
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
        (cert.estado != EstadoCertificado.borrador &&
            cert.cotizacionDolarPromedioAlEmitir != null)
        ? cert.cotizacionDolarPromedioAlEmitir!
        : _cotizacionHoy;
    final convertido = convertirArsAMoneda(montoArs, _moneda, cotizacion);
    final valorInt = convertido.round();
    final str = valorInt.toString();
    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    final formateado = str.replaceAllMapped(reg, (Match m) => '${m[1]}.');
    return _moneda == 'USD' ? 'USD $formateado' : '\$ $formateado';
  }

  /// Como `_fmt` pero **sin certificado**: para montos que NO están congelados -- hoy, el peso de
  /// cada rubro en el panel de avance, que sale del presupuesto vigente. Va con la cotización de hoy
  /// a propósito: es un número vivo, y por la regla de la `0122` solo los montos firmados se
  /// convierten con la cotización de su momento.
  String _fmtVivo(double montoArs) {
    final convertido = convertirArsAMoneda(montoArs, _moneda, _cotizacionHoy);
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
          'Anular Certificado Nº ${cert.numeroFormateado}',
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
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
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
      await _certificadosRepository.proponerAnulacion(
        certificadoId: cert.id,
        motivo: motivo,
      );
      if (!mounted) return;
      await _cargarCertificados();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
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
          title: const Text(
            'Rechazar anulación',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Motivo (opcional)',
              isDense: true,
            ),
            style: const TextStyle(fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Volver'),
            ),
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
          title: const Text(
            'Aprobar anulación',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          content: Text(
            'El Certificado Nº ${cert.numeroFormateado} pasa a Anulado y se crea un borrador de reemplazo '
            'con el mismo número, como el ${Certificado.formatearNumero(cert.numero, cert.version + 1)}, '
            'para corregirlo. ¿Confirmás?',
            style: const TextStyle(fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Aprobar'),
            ),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
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
    final esQuienPropuso =
        cert.anulacionPropuestaPor != null &&
        cert.anulacionPropuestaPor == usuarioActualId;
    final puedeResolver =
        widget.userContext?.puedeGestionarAnulacionCertificado == true &&
        !esQuienPropuso;

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
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.red.shade900,
            ),
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
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 0),
                    ),
                    child: const Text(
                      'Aprobar',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 16),
                  TextButton(
                    onPressed: () => _resolverAnulacion(cert, false),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 0),
                    ),
                    child: Text(
                      'Rechazar',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.red.shade700,
                      ),
                    ),
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
      // Las dos: emitir un certificado cambia el avance, así que refrescar la lista sin refrescar el
      // porcentaje dejaría el panel mintiendo hasta salir y volver a entrar a la solapa.
      onRefresh: () async {
        await _cargarCertificados();
        await _cargarAvance();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Grilla de ícono + etiqueta en un solo bloque, no botones sueltos -- ver
            // BarraAccionesObra para el por qué de la forma y de las que se descartaron. Acá solo
            // vive QUÉ acciones hay y quién las ve.
            //
            // Historial de lo que ya se corrigió en esta barra, para no repetirlo: los 4 botones
            // vivían en un Wrap plano porque antes 3 de ellos estaban en un Row de ancho fijo que
            // no podía reflowar y desbordaba 69px con fuente grande (Seba, 2026-09-13). La grilla
            // hereda esa lección: ninguna altura fija, columnas calculadas del ancho real.
            BarraAccionesObra(
              acciones: [
                // Visible para admin_maestro/profesional/constructor — los 3 mismos roles que
                // certificados_insert/certificados_update (0009/0010) ya autorizan a crear o
                // seguir cargando un Borrador. Nadie más lo ve: un Cliente/Apoderado/Veedor no
                // puede iniciar esto, mostrarlo deshabilitado no aportaría nada.
                if (widget.userContext?.puedeCargarAvance == true)
                  AccionObra(
                    icono: Icons.note_add_outlined,
                    label: 'Nuevo certificado',
                    onTap: _onNuevoCertificado,
                    // La acción principal de la solapa: mismo tamaño que el resto, ícono en fondo
                    // lleno. Jerarquía sin romper la grilla.
                    destacada: true,
                  ),
                // Visible para cualquiera -- es informativo para todos (el propietario se
                // entera de una demasía/quita comentando ahí, no aprobándola, docs/
                // adicionales_quitas_demasias_diagnostico.md §6). Aprobar/rechazar/crear se
                // gatean adentro de la pantalla, no acá.
                AccionObra(
                  icono: Icons.rule_outlined,
                  label: 'Quitas y Demasías',
                  onTap: _abrirQuitasDemasias,
                ),
                // Visible para cualquiera, mismo criterio que "Quitas y Demasías" -- cualquier
                // miembro puede solicitar un adicional (ambigüedad E,
                // docs/adicionales_quitas_demasias_diagnostico.md §11.3), la barrera real es
                // la aprobación, gateada adentro de la pantalla.
                AccionObra(
                  icono: Icons.add_business_outlined,
                  label: 'Adicionales',
                  onTap: _abrirAdicionales,
                ),
                AccionObra(
                  icono: Icons.settings_outlined,
                  label: 'Configuración',
                  onTap: _abrirConfigCertificacion,
                ),
                // Acá entran las del Libro de Obra cuando se construya (Órdenes de Servicio y
                // Notas de Pedido, docs/libro_obra_horizonte.md): son dos AccionObra más, sin
                // tocar el layout.
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
            // Arriba del historial y debajo del estado del presupuesto: es el resumen de la obra, lo
            // primero que alguien quiere saber al entrar ("¿cómo va?"), y el historial es el detalle
            // que lo explica. Se dibuja solo si hay un porcentaje real que mostrar.
            PanelAvanceObra(
              avanceObraPct: _avancePct,
              porRubro: _avancePorRubro,
              catalogoRubros: _catalogoRubros,
              mostrarMontos: widget.userContext?.puedeVerMontosGestionObra == true,
              fmtMonto: _fmtVivo,
            ),
            const Text(
              'Historial de Certificados',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1B365D),
              ),
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
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54),
              ),
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
    final vigentes = _certificados
        .where((c) => c.estado != EstadoCertificado.anulado)
        .toList();
    final anulados = _certificados
        .where((c) => c.estado == EstadoCertificado.anulado)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (vigentes.isEmpty && anulados.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'No hay certificados vigentes -- todos los de esta obra fueron anulados (ver abajo).',
              style: TextStyle(color: Colors.black45, fontSize: 12),
            ),
          ),
        for (final cert in vigentes) _buildTarjetaCertificado(cert),
        if (anulados.isNotEmpty) _buildSeccionAnulados(anulados),
      ],
    );
  }

  Widget _buildTarjetaCertificado(Certificado cert) {
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
                      // "bis"/"ter" solo a partir de la 2ª versión, vía Certificado.numeroFormateado
                      // -- un certificado nunca anulado no necesita distinguirse de nada, agregarlo
                      // siempre sería ruido sin motivo.
                      'Certificado Nº ${cert.numeroFormateado} - ${cert.periodo}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Color(0xFF1B365D),
                      ),
                    ),
                  ),
                  Chip(
                    label: Text(
                      cert.estado.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    backgroundColor: _getColorEstado(cert.estado),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Gateado por rol, no solo estético: quien no ve montos según la matriz (Veedor,
              // apoderado sin delegación) no ve el monto certificado. Hasta 2026-09-12 el
              // Constructor también quedaba afuera ("vista operativa"); desde el cambio de matriz
              // los ve -- ver UserContext.puedeVerMontosGestionObra.
              if (widget.userContext?.puedeVerMontosGestionObra == true) ...[
                Text(
                  'Monto Certificado: ${_fmt(cert.monto, cert)}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
                // Desglose pactado/ajuste CAC (docs/cac_conectado_modelo_a_diseno.md §9,
                // ambigüedad B) -- solo si hay algo que explicar: montoPactado null son
                // certificados emitidos antes de esa migración (sin desglose guardado), y monto
                // == montoPactado es una obra sin CAC o sin ajuste ese mes -- en los dos casos no
                // hay nada nuevo que esta línea agregue.
                if (cert.montoPactado != null &&
                    cert.monto != cert.montoPactado)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Pactado ${_fmt(cert.montoPactado!, cert)} · Ajuste CAC '
                      '${_fmt(cert.monto - cert.montoPactado!, cert)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.blueGrey.shade600,
                      ),
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
              if (cert.estado == EstadoCertificado.anulado &&
                  cert.anulacionMotivo != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Anulado — ${cert.anulacionMotivo}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.red.shade700,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              if (cert.anulacionEstado == 'propuesta')
                _buildBloqueAnulacionPendiente(cert),
              if (widget.userContext?.puedeGestionarAnulacionCertificado ==
                      true &&
                  (cert.estado == EstadoCertificado.emitido ||
                      cert.estado == EstadoCertificado.leido) &&
                  cert.anulacionEstado != 'propuesta')
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => _proponerAnulacion(cert),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 0),
                    ),
                    child: Text(
                      'Anular',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.red.shade700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Sección colapsada al final de la lista -- anulados nunca se borran (0056), pero son
  /// información histórica, no algo que compita por espacio con los certificados vigentes. Fila
  /// chica por anulado (sin `Card` propia), tappable al detalle igual que uno vigente.
  Widget _buildSeccionAnulados(List<Certificado> anulados) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () =>
                setState(() => _anuladosExpandido = !_anuladosExpandido),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.history, size: 15, color: Colors.black45),
                  const SizedBox(width: 6),
                  Text(
                    'Anulados (${anulados.length})',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.black54,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _anuladosExpandido ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: Colors.black45,
                  ),
                ],
              ),
            ),
          ),
          if (_anuladosExpandido)
            for (final cert in anulados) _buildFilaAnulado(cert),
        ],
      ),
    );
  }

  Widget _buildFilaAnulado(Certificado cert) {
    return InkWell(
      onTap: () => _abrirDetalle(cert),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.black12)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.block, size: 13, color: Colors.red.shade300),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Certificado Nº ${cert.numeroFormateado} — ${cert.periodo}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Colors.black54,
                    ),
                  ),
                  if (cert.anulacionMotivo != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        cert.anulacionMotivo!,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: Colors.black38,
                          fontStyle: FontStyle.italic,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: Colors.black26),
          ],
        ),
      ),
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
