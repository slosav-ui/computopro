import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/segurity/user_context.dart';
import '../../core/utils/parser_numero_ar.dart';
import '../../data/models/invitacion.dart';
import '../../data/models/pendiente.dart';
import '../obra_detalle/screens/adicionales_screen.dart';
import '../obra_detalle/screens/detalle_certificado_screen.dart';
import '../obra_detalle/screens/presupuestos_screen.dart';
import '../obra_detalle/screens/quitas_demasias_screen.dart';
import 'cartel_pendientes.dart';
import '../auth/aceptar_invitacion_screen.dart';
import 'editar_perfil_screen.dart';
import '../../services/obras_repository.dart';
import '../../services/adicionales_repository.dart';
import '../../services/certificados_repository.dart';
import '../../services/pendientes_repository.dart';
import '../../services/auth_service.dart';
import '../../services/certificado_subitems_avance_repository.dart';
import '../../services/indices_economicos_repository.dart';
import '../../services/invitaciones_repository.dart';
import '../../services/obra_members_repository.dart';

/// Un adicional aprobado, listo para pintar en la card: el monto ya convertido a las dos monedas
/// (la conversión vive en un solo lugar, `_conMontosCalculados`, igual que el resto de los montos
/// de esta pantalla). Un renglón de la card por cada uno de estos -- ver §10.2 de
/// docs/adicionales_quitas_demasias_diagnostico.md.
typedef _AdicionalAprobadoCard = ({
  String id,
  String descripcion,
  double montoArs,
  double montoUsd,
  double avancePct,
});

class ObrasListScreen extends StatefulWidget {
  const ObrasListScreen({super.key});

  @override
  State<ObrasListScreen> createState() => _ObrasListScreenState();
}

class _ObrasListScreenState extends State<ObrasListScreen> {
  /// Cuántos adicionales aprobados se listan uno por uno en la card antes de agrupar el resto en un
  /// solo renglón. La portada es panorámica: con el pactado, el total y el vínculo a Resumen, tres
  /// adicionales ya son 6 renglones de números en una tarjeta de lista. Lo que queda afuera no se
  /// pierde -- se agrupa con su monto (el total siempre cierra exacto) y el detalle está en Resumen.
  static const int _maxAdicionalesEnCard = 3;

  // --- Estado de Suscripción ---
  bool _esPlanPro = false;

  // --- Cotización Dólar BNA & Proyección ---
  //
  // Ya no hardcodeado -- ver `_cargarIndicadoresEconomicos()`. Los valores de acá abajo son
  // solo el placeholder del primer frame, antes de que resuelva la consulta a
  // `cotizacion_dolar_bna` (0102_indices_cac_cotizacion_dolar.sql): mismos números que el seed
  // de esa migración, para que no haya un salto visible si la consulta tarda. Si algún día se
  // desactualiza esta constante y la de la base, no importa -- la de la base gana apenas carga.
  double _dolarBnaCompra = 1485.0;
  double _dolarBnaVenta = 1535.0;
  String _fechaActualizacionDolar = 'BNA';
  double get _dolarOficialPromedio => (_dolarBnaCompra + _dolarBnaVenta) / 2;
  late double _cotizacionUsdEfectiva;

  // --- Indicadores CAC ---
  // Idem -- placeholder hasta que `_cargarIndicadoresEconomicos()` resuelva contra `indices_cac`.
  double _variacionCacUltimoMes = 1.5;
  String _ultimoMesPublicadoCac = 'Julio 2026';

  // --- Acceso a datos ---
  final ObrasRepository _obrasRepository = ObrasRepository();
  final AuthService _authService = AuthService();
  final InvitacionesRepository _invitacionesRepository = InvitacionesRepository();
  final IndicesEconomicosRepository _indicesEconomicosRepository = IndicesEconomicosRepository();
  final ObraMembersRepository _obraMembersRepository = ObraMembersRepository();
  final AdicionalesRepository _adicionalesRepository = AdicionalesRepository();
  final CertificadoSubitemsAvanceRepository _avanceRepository =
      CertificadoSubitemsAvanceRepository();
  final PendientesRepository _pendientesRepository = PendientesRepository();
  final CertificadosRepository _certificadosRepository = CertificadosRepository();

  // Lo que espera la acción del usuario, en todas sus obras (0117) -- cartel arriba de la lista y
  // contador por card. Vacío si falla la carga: sin aviso, la lista de obras sigue igual.
  List<Pendiente> _pendientes = [];
  List<Map<String, dynamic>> _obras = [];
  bool _cargando = true;
  String? _error;

  // Obras donde el usuario actual tiene admin_maestro activo -- reemplaza el criterio viejo por
  // `obras.id_admin_creador` (0108): ese campo es inmutable y no reflejaba ni que puede haber
  // varios administradores ni que uno puede renunciar al rol. Ver `_esAdminDeObra`.
  Set<String> _obraIdsAdmin = {};

  // Aviso "qué significa el desfasaje" (chip Pactado/Hoy de una obra congelada) -- descartable,
  // por obra, mismo mecanismo que el aviso de zona UOCRA de CartelCostoManoObra: SharedPreferences,
  // por dispositivo, con ícono chico para restaurarlo. Default false (aviso visible) hasta que
  // termine de cargar -- mismo criterio "fail-closed hacia lo más seguro" que el resto del proyecto.
  Set<String> _avisoDesfasajeDescartadoObras = {};

  String _claveAvisoDesfasaje(String obraId) => 'desfasaje_congelado_aviso_descartado_$obraId';

  static const _nombresMeses = [
    'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
  ];

  /// 'YYYY-MM-01' del mes en curso -- valor de `obras.mes_base_cac` (columna `date`) para una
  /// obra que se crea hoy. `DateTime(...).toIso8601String()` da 'YYYY-MM-01T00:00:00.000', el
  /// `substring` se queda solo con la parte de fecha que espera la columna.
  String _primerDiaDelMesActual() {
    final hoy = DateTime.now();
    return DateTime(hoy.year, hoy.month, 1).toIso8601String().substring(0, 10);
  }

  @override
  void initState() {
    super.initState();
    _cotizacionUsdEfectiva = _dolarOficialPromedio;
    _cargarObras();
    _canjearInvitacionPendiente();
    _cargarIndicadoresEconomicos();
    _cargarAvisosDesfasajeDescartados();
  }

  /// Todas las obras cuyo aviso de desfasaje ya fue descartado en este dispositivo -- una sola
  /// pasada por las claves de SharedPreferences en vez de una lectura por obra (no se sabe qué
  /// obras van a existir hasta que `_cargarObras` resuelve, así que no tiene sentido pedirlas de a
  /// una).
  Future<void> _cargarAvisosDesfasajeDescartados() async {
    final prefs = await SharedPreferences.getInstance();
    const prefijo = 'desfasaje_congelado_aviso_descartado_';
    final descartados = prefs
        .getKeys()
        .where((k) => k.startsWith(prefijo) && (prefs.getBool(k) ?? false))
        .map((k) => k.substring(prefijo.length))
        .toSet();
    if (!mounted) return;
    setState(() => _avisoDesfasajeDescartadoObras = descartados);
  }

  Future<void> _descartarAvisoDesfasaje(String obraId) async {
    setState(() => _avisoDesfasajeDescartadoObras = {..._avisoDesfasajeDescartadoObras, obraId});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_claveAvisoDesfasaje(obraId), true);
  }

  Future<void> _restaurarAvisoDesfasaje(String obraId) async {
    setState(() => _avisoDesfasajeDescartadoObras = {..._avisoDesfasajeDescartadoObras}..remove(obraId));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_claveAvisoDesfasaje(obraId), false);
  }

  /// Reemplaza los placeholders de arriba por los valores reales -- `cotizacion_dolar_bna` (fila
  /// única) y el último mes de `indices_cac` (para la variación mensual que se muestra junto al
  /// interruptor de CAC al crear/editar una obra en pesos). Silencioso en el fracaso a
  /// propósito, mismo criterio que `_presupuestoVivoSeguro`: un problema puntual acá no tiene
  /// que tumbar el resto de la pantalla -- la app sigue mostrando el placeholder hasta el
  /// próximo intento.
  Future<void> _cargarIndicadoresEconomicos() async {
    try {
      final cotizacion = await _indicesEconomicosRepository.getCotizacionDolar();
      final indices = await _indicesEconomicosRepository.getIndicesCac();
      if (!mounted) return;
      // Capturado ANTES de pisar _dolarBnaCompra/_dolarBnaVenta más abajo -- comparar después de
      // pisarlos compararía contra el promedio nuevo, no contra el placeholder viejo, y la
      // detección de "el usuario no lo tocó" quedaría rota.
      final promedioPlaceholder = _dolarOficialPromedio;
      setState(() {
        if (cotizacion != null) {
          _dolarBnaCompra = cotizacion.compra;
          _dolarBnaVenta = cotizacion.venta;
          _fechaActualizacionDolar =
              '${_nombresMeses[cotizacion.actualizadoEn.month - 1]} ${cotizacion.actualizadoEn.year} (BNA)';
          // Si el usuario no personalizó la proyección (ver el diálogo "Ajuste Económico"),
          // sigue atada al promedio oficial -- se actualiza junto con él.
          if (_cotizacionUsdEfectiva == promedioPlaceholder) {
            _cotizacionUsdEfectiva = (cotizacion.compra + cotizacion.venta) / 2;
          }
        }
        if (indices.length >= 2) {
          final ultimo = indices.last;
          final anterior = indices[indices.length - 2];
          _ultimoMesPublicadoCac = '${_nombresMeses[ultimo.mes.month - 1]} ${ultimo.mes.year}';
          _variacionCacUltimoMes =
              double.parse((((ultimo.general / anterior.general) - 1) * 100).toStringAsFixed(1));
        }
      });
    } catch (_) {
      // Silencioso -- ver comentario de arriba.
    }
  }

  /// Si quedó un código guardado (pegado antes de tener sesión -- ver
  /// `AceptarInvitacionScreen`/`docs/invitaciones_diseno_datos.md` §7), lo revisa acá: es el
  /// primer momento en que hay sesión activa Y un `BuildContext` con `Scaffold` para preguntar.
  /// `initState` corre una sola vez por sesión real -- `AuthGate` reusa la misma instancia de
  /// `ObrasListScreen` (es `const`) en los rebuilds que no cambian de sesión (ej. refresh de
  /// token), así que esto no reintenta en cada uno de esos.
  ///
  /// Ajuste sobre la primera versión (feedback de Seba, 2026-09-10): antes canjeaba directo, en
  /// silencio -- si el código quedaba guardado en el dispositivo y después entraba una cuenta
  /// distinta a la que lo pegó (celular prestado, u otra persona logueándose en el mismo
  /// instalador), se sumaba a la obra a quien no correspondía, sin que nadie lo pidiera. Ahora
  /// primero previsualiza (`previsualizar_invitacion`, de solo lectura) y pide confirmación
  /// mostrando a qué obra y con qué rol -- recién ahí canjea.
  ///
  /// El código pendiente se borra apenas se resuelve la pregunta (confirme o no) -- no vuelve a
  /// preguntar en cada login siguiente. Si la previsualización ya da inválido/vencido, se borra
  /// en silencio sin diálogo: no hay nada que confirmar, y el mensaje real queda para el
  /// reintento manual desde "Ingresar código".
  Future<void> _canjearInvitacionPendiente() async {
    final codigo = await InvitacionPendiente.leer();
    if (codigo == null) return;

    VistaPreviaInvitacion? vista;
    try {
      vista = await _invitacionesRepository.previsualizarInvitacion(codigo);
    } catch (_) {
      vista = null;
    }
    if (vista == null) {
      await InvitacionPendiente.borrar();
      return;
    }

    if (!mounted) return;
    final confirmar = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Invitación pendiente'),
        content: Text('Tenés una invitación a la obra "${vista!.obraNombre}" como ${etiquetaRol(vista.rol)}. ¿Sumarte ahora?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Ahora no')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sumarme')),
        ],
      ),
    );
    await InvitacionPendiente.borrar();
    if (confirmar != true) return;

    try {
      final resultado = await _invitacionesRepository.aceptarInvitacion(codigo);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Te sumaste a la obra "${resultado.obraNombre}" como ${etiquetaRol(resultado.rol)}.')),
      );
      _cargarObras();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo sumar a la obra.')));
    }
  }

  // --- Carga de Obras desde Supabase ---
  Future<void> _cargarObras() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final obras = await _obrasRepository.getObras();
      // Presupuesto vivo por obra, en paralelo -- una RPC por obra (2 a 10 obras simultáneas es el
      // uso real del proyecto, ver CLAUDE.md, así que no hace falta una función batch todavía).
      // Resuelto acá, no dejado en manos de cada card: todas las obras necesitan el mismo dato antes
      // de poder ordenarse/mostrarse, no tiene sentido que cada una lo pida por su cuenta con un
      // FutureBuilder propio. Fail-safe a 0 por obra individual -- un fallo puntual (red, RLS) no
      // tiene que tumbar el resto de la lista, mismo criterio que el resto del proyecto.
      final presupuestos = await Future.wait([
        for (final o in obras) _presupuestoVivoSeguro(o['id'] as String),
      ]);
      // Pactado por obra congelada (Modelo A) -- solo para las que tienen `presupuestoCongeladoEn`
      // (la mayoría no, así que la mayoría de estas llamadas ni se hacen). Fail-safe a null, mismo
      // criterio que _presupuestoVivoSeguro: si falla, esa card simplemente no muestra el chip de
      // comparación, no tumba el resto de la lista.
      final pactados = await Future.wait([
        for (final o in obras)
          _montoPactadoSeguro(o['id'] as String, o['presupuestoCongeladoEn'] as DateTime?),
      ]);
      // "Hoy", con la MISMA configuración de Factor K con la que se congeló -- no
      // `calcularPresupuestoVivo` (0091), que usa los interruptores VIGENTES de la Solapa APU.
      // Comparar el pactado contra ese número mezclaba dos cosas (desfasaje de precio + desfasaje
      // de configuración) -- ver 0110. Mismo criterio fail-safe que el resto: null si falla, sin
      // chip para esa card.
      final hoyConfigCongelada = await Future.wait([
        for (final o in obras)
          _hoyConfigCongeladaSeguro(o['id'] as String, o['presupuestoCongeladoEn'] as DateTime?),
      ]);
      // Avance certificado por obra (0052, auditoría §2.1: se calculaba y no se mostraba en ningún
      // lado). Una RPC por obra, igual que el presupuesto vivo y el pactado -- 2 a 10 obras es el uso
      // real del proyecto (CLAUDE.md), no hace falta una función batch todavía. Fail-safe a null por
      // obra: sin avance, esa card simplemente no muestra la barra.
      final avances = await Future.wait([
        for (final o in obras) _avanceSeguro(o['id'] as String, o['presupuestoCongeladoEn'] as DateTime?),
      ]);
      // Adicionales aprobados (0116), una sola consulta para toda la lista. Fail-safe a vacío: si
      // falla, ninguna card muestra sus renglones de adicionales -- el resto de la card no depende de esto.
      final adicionalesAprobados = await _adicionalesAprobadosSeguro([for (final o in obras) o['id'] as String]);
      final pendientes = await _pendientesSeguro();
      // Una sola consulta para toda la lista, no una por obra -- ver _esAdminDeObra. Fail-safe a
      // vacío: si falla, ningún ícono de administrador se muestra (fallo seguro, mismo criterio
      // que el resto de esta pantalla) en vez de romper la carga de toda la lista.
      final usuarioId = _authService.usuarioActual?.id;
      final obraIdsAdmin = usuarioId == null
          ? <String>{}
          : await _obraMembersRepository
              .getObraIdsDondeSoyAdminMaestro(usuarioId)
              .catchError((_) => <String>{});
      if (!mounted) return;
      setState(() {
        _obras = [
          for (var i = 0; i < obras.length; i++)
            _conMontosCalculados(
              obras[i],
              presupuestos[i],
              pactados[i],
              hoyConfigCongelada[i],
              adicionalesAprobados[obras[i]['id']],
              avances[i],
            ),
        ];
        _obraIdsAdmin = obraIdsAdmin;
        _pendientes = pendientes;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar las obras. Verificá tu conexión.';
        _cargando = false;
      });
    }
  }

  Future<double> _presupuestoVivoSeguro(String obraId) async {
    try {
      return await _obrasRepository.calcularPresupuestoVivo(obraId);
    } catch (_) {
      return 0.0;
    }
  }

  Future<double?> _montoPactadoSeguro(String obraId, DateTime? congeladoEn) async {
    if (congeladoEn == null) return null;
    try {
      return await _obrasRepository.getMontoPactadoCongelado(obraId);
    } catch (_) {
      return null;
    }
  }

  /// Avance certificado de una obra. **Solo para obras congeladas**: en una obra en Cotización el
  /// avance es siempre 0 (no hay certificados), y una barra vacía en cada card sería ruido que no
  /// informa nada -- criterio del plan de esta pieza, confirmado por Seba. Fail-safe a null, mismo
  /// criterio que el resto: si falla, esa card no muestra la barra y nada más.
  Future<double?> _avanceSeguro(String obraId, DateTime? congeladoEn) async {
    if (congeladoEn == null) return null;
    try {
      return await _avanceRepository.getAvancePonderadoObra(obraId);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, List<({String id, String descripcion, double montoArs, double? cotizacionAlAprobar, double avancePct})>>>
      _adicionalesAprobadosSeguro(
    List<String> obraIds,
  ) async {
    try {
      return await _adicionalesRepository.getAprobadosPorObra(obraIds);
    } catch (_) {
      return {};
    }
  }

  Future<List<Pendiente>> _pendientesSeguro() async {
    try {
      return await _pendientesRepository.getMisPendientes();
    } catch (_) {
      return [];
    }
  }

  /// Lleva a donde se resuelve cada pendiente: Adicionales, Quitas y Demasías, o el detalle del
  /// certificado (ahí se marca leído -- solo con abrirlo --, pagado o cerrado, se resuelve la
  /// anulación y se sube el PDF firmado). Esas pantallas necesitan el UserContext de ESA obra, que
  /// el dashboard no tiene armado: se construye acá, igual que PresupuestosScreen. Recarga al
  /// volver, para que el cartel ya no muestre lo que se acaba de resolver.
  Future<void> _abrirPendiente(Pendiente p) async {
    final usuarioId = _authService.usuarioActual?.id;
    if (usuarioId == null) return;
    try {
      final miembros = await _obraMembersRepository.getMiembrosDeObra(p.obraId);
      final userContext = UserContext.desdeObraMembers(
        userId: usuarioId,
        obraId: p.obraId,
        todasLasMembresias: miembros,
      );
      final Widget destino;
      switch (p.tipo) {
        case TipoPendiente.adicional:
          destino = AdicionalesScreen(obraId: p.obraId, userContext: userContext);
        case TipoPendiente.quita:
        case TipoPendiente.demasia:
          destino = QuitasDemasiasScreen(obraId: p.obraId, userContext: userContext);
        case TipoPendiente.certificadoEmitido:
        case TipoPendiente.certificadoLeido:
        case TipoPendiente.certificadoPagado:
        case TipoPendiente.anulacion:
        case TipoPendiente.firmaFisica:
          // Estos tipos siempre traen el certificado en entidad_id (0117) -- el único que puede
          // venir sin entidad es certificacionPeriodo, que sale por la rama de abajo.
          final certificado = await _certificadosRepository.getPorId(p.entidadId!);
          destino = DetalleCertificadoScreen(obraId: p.obraId, certificado: certificado, userContext: userContext);
        case TipoPendiente.certificacionPeriodo:
          // No hay entidad que abrir: lo que falta es crear el borrador, y eso vive en Gestión de
          // Obra. La obra ya está cargada en la lista, no hace falta volver a pedirla.
          final obra = _obras.firstWhere(
            (o) => o['id'] == p.obraId,
            orElse: () => <String, dynamic>{},
          );
          if (obra.isEmpty) return;
          destino = PresupuestosScreen(obra: obra, solapaInicial: SolapaPresupuestos.gestionObra);
      }
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => destino));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo abrir ese pendiente.')));
    }
    if (!mounted) return;
    _cargarObras();
  }

  Future<double?> _hoyConfigCongeladaSeguro(String obraId, DateTime? congeladoEn) async {
    if (congeladoEn == null) return null;
    try {
      return await _obrasRepository.calcularPresupuestoHoyConfigCongelada(obraId);
    } catch (_) {
      return null;
    }
  }

  // --- Conversión de Moneda (a partir del monto base persistido) ---
  //
  // Guarda agregada 2026-09-10 (pedido de Seba, tras el bug real de la conversión dando 0): sin
  // una cotización válida, esto tiene que avisar, no calcular con un divisor roto en silencio.
  // `_cotizacionUsdEfectiva` en la práctica nunca debería llegar acá en 0/negativa -- arranca en
  // el placeholder de `_dolarBnaCompra`/`_dolarBnaVenta` (inicializados síncronos, antes de
  // cualquier `await`) y `_cargarIndicadoresEconomicos` solo la pisa con un valor real -- pero
  // la guarda queda igual, para no volver a depender de que esa garantía se sostenga para
  // siempre sin que nadie la verifique. El error real va a la consola antes de tirar la
  // excepción -- antes esto no decía nada, ver el comentario de más abajo sobre la causa real
  // del bug reportado.
  /// `cotizacion`: la cotización **propia de ese monto**, para los que están firmados y congelados
  /// (0122 -- el pactado usa la del congelamiento, cada adicional aprobado la de su aprobación). Sin
  /// ella se usa `_cotizacionUsdEfectiva`, que es lo correcto para todo lo vivo (presupuesto
  /// estimado, el "Hoy" del chip) e incluye la proyección personalizada PRO. Un monto ya firmado
  /// nunca se convierte con la efectiva: era justamente el problema -- el número en dólares se movía
  /// solo, y la proyección los movía todos juntos. Ver
  /// docs/cotizacion_congelada_montos_cerrados_diseno.md.
  ///
  /// Una `cotizacion` no positiva se ignora (cae a la efectiva): un snapshot roto no tiene que
  /// romper la card, y es el mismo fallback que una fila vieja sin snapshot.
  double _convertirMonto(double monto, String monedaOrigen, String monedaDestino, {double? cotizacion}) {
    if (monedaOrigen == monedaDestino) return monto;
    final double cotizacionAUsar =
        (cotizacion != null && cotizacion > 0) ? cotizacion : _cotizacionUsdEfectiva;
    if (cotizacionAUsar <= 0) {
      debugPrint(
        '_convertirMonto: cotización USD inválida ($cotizacionAUsar) -- no se puede '
        'convertir $monto de $monedaOrigen a $monedaDestino.',
      );
      throw StateError('La cotización del dólar todavía no está disponible. Probá de nuevo en un momento.');
    }
    return monedaOrigen == 'ARS' ? monto / cotizacionAUsar : monto * cotizacionAUsar;
  }

  /// `montoVivoArs`: presupuesto vivo recién calculado (ver _cargarObras) -- SIEMPRE en ARS, sin
  /// importar `obra['moneda']`. Antes (fórmula de superficie, ya sacada en 0087) el monto persistido
  /// podía estar en la moneda elegida al alta, y por eso esta función miraba `moneda` para decidir
  /// si convertir o no. Con el presupuesto vivo eso ya no aplica -- viene de calcular_precio_final_
  /// apu_subitems, que trabaja siempre en pesos (ni insumos ni mano de obra tienen precio en USD en
  /// ningún lado del sistema) -- así que acá se convierte siempre desde ARS, sin condicional.
  /// `moneda` sigue importando para otra cosa, sin cambios: qué campo de los dos (Ars/Usd) elige
  /// mostrar la card como principal (ver el uso de esRs más abajo en build()).
  Map<String, dynamic> _conMontosCalculados(
    Map<String, dynamic> obra,
    double montoVivoArs,
    double? montoPactadoArs,
    double? montoHoyConfigCongeladaArs, [
    List<({String id, String descripcion, double montoArs, double? cotizacionAlAprobar, double avancePct})>? adicionalesAprobados,
    double? avancePct,
  ]) {
    // 0122: la cotización del día en que se congeló el presupuesto. El pactado se convierte con
    // ESTA; el estimado vivo y el "Hoy" del chip, con la efectiva de hoy (son números vivos).
    final double? cotizacionAlCongelar = (obra['cotizacionDolarAlCongelar'] as num?)?.toDouble();
    return {
      ...obra,
      'montoEstimadoArs': montoVivoArs,
      'montoEstimadoUsd': _convertirMonto(montoVivoArs, 'ARS', 'USD'),
      'montoPactadoArs': montoPactadoArs,
      'montoPactadoUsd': montoPactadoArs == null
          ? null
          : _convertirMonto(montoPactadoArs, 'ARS', 'USD', cotizacion: cotizacionAlCongelar),
      'montoHoyConfigCongeladaArs': montoHoyConfigCongeladaArs,
      'montoHoyConfigCongeladaUsd': montoHoyConfigCongeladaArs == null
          ? null
          : _convertirMonto(montoHoyConfigCongeladaArs, 'ARS', 'USD'),
      // Avance certificado (0052). null = obra sin congelar, o falló la consulta -> sin barra.
      'avancePct': avancePct,
      // Uno por adicional, no un total -- la card pinta un renglón por cada uno. La conversión a
      // USD se hace acá, de una vez, para que la card no tenga que saber nada de cotizaciones: cada
      // adicional aprobado con la cotización de SU aprobación (0122), no con la de hoy.
      'adicionalesAprobados': <_AdicionalAprobadoCard>[
        for (final a in adicionalesAprobados ?? const [])
          (
            id: a.id,
            descripcion: a.descripcion,
            montoArs: a.montoArs,
            montoUsd: _convertirMonto(a.montoArs, 'ARS', 'USD', cotizacion: a.cotizacionAlAprobar),
            avancePct: a.avancePct,
          ),
      ],
    };
  }

  // --- Formateador de Montos ---
  String _formatearMonto(double monto, String moneda) {
    final valorInt = monto.round();
    final str = valorInt.toString();
    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    final formateado = str.replaceAllMapped(reg, (Match m) => '${m[1]}.');
    return moneda == 'USD' ? 'USD $formateado' : '\$ $formateado';
  }

  /// Un dato de identificación de la card: ícono + texto, en el renglón de arriba. `destacado` es
  /// para los m², que son identidad pero también la referencia con la que se comparan obras entre sí
  /// -- un peso más que el resto, sin volver a ser el chip que eran.
  ///
  /// Sin `Expanded` ni `Flexible` acá: cada dato pide su ancho natural y el `Wrap` que los contiene
  /// baja de línea cuando no entran. Eso es lo que hace que no desborde nunca, y por qué el texto no
  /// necesita `ellipsis`: si es largo, ocupa su renglón completo.
  Widget _buildDatoIdentidad(IconData icono, String texto, {bool destacado = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icono, size: 13, color: Colors.black45),
        const SizedBox(width: 4),
        Text(
          texto,
          style: TextStyle(
            fontSize: destacado ? 12 : 11,
            fontWeight: destacado ? FontWeight.bold : FontWeight.normal,
            color: destacado ? Colors.black87 : Colors.black54,
          ),
        ),
      ],
    );
  }

  /// La barra de avance de un monto de la card: va **pegada abajo del renglón del monto al que
  /// pertenece** -- el pactado tiene la del contrato y cada adicional aprobado la suya (pedido de
  /// Seba, 2026-09-13: *"hoy ve cómo va el contrato pero no la obra completa"*). Un profesional
  /// tiene que ver de un vistazo cómo corren todas sus obras, y una obra con adicionales en
  /// ejecución no se resume en el avance del contrato.
  ///
  /// Deliberadamente chica y sin detalle: el porcentaje a la derecha, alineado con la cifra de
  /// arriba, y nada más. El desglose por rubro vive en Gestión de Obra (`PanelAvanceObra`) y el del
  /// adicional en Resumen, por el criterio de la portada -- acá va el dato, no el análisis.
  ///
  /// `LinearProgressIndicator` con `value` explícito (nunca indeterminado) y alto fijo: el mismo
  /// aspecto en las dos pantallas sin que el tema del Material lo cambie. El clamp es defensivo: el
  /// acumulado no debería pasar de 100 (lo impide el candado de excesos de la 0054, y el de
  /// `certificar_avance_adicional` para los adicionales), pero una barra pintada fuera de su caja
  /// sería un bug visual por un dato de más.
  ///
  /// `sangria`: el hueco del candado, para que la barra arranque alineada con el rótulo del monto y
  /// no con el borde de la card.
  Widget _buildBarraAvance(double pct, {double sangria = 13}) {
    final fraccion = (pct / 100).clamp(0.0, 1.0);
    final entero = pct == pct.roundToDouble();
    return Padding(
      padding: EdgeInsets.only(left: sangria, top: 3),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: fraccion,
                minHeight: 5,
                backgroundColor: Colors.black12,
                valueColor: AlwaysStoppedAnimation<Color>(
                  fraccion >= 1 ? Colors.green.shade600 : const Color(0xFF1B365D),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${entero ? pct.toStringAsFixed(0) : pct.toStringAsFixed(1)}%',
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  /// Rótulo del renglón de un adicional aprobado: su descripción, que es lo que lo identifica para
  /// quien lo firmó, con el prefijo "Adicional" para que el renglón se lea solo y no dependa de
  /// estar debajo del pactado. Descripción vacía (no debería pasar, es obligatoria al cargarlo):
  /// queda solo el prefijo, nunca un renglón sin nombre.
  String _rotuloAdicional(_AdicionalAprobadoCard a) =>
      a.descripcion.isEmpty ? 'Adicional' : 'Adicional · ${a.descripcion}';

  /// El "ver más" de los adicionales: lleva a la solapa Resumen de la obra, que es donde vive el
  /// detalle técnico (qué incluye cada adicional, cuánto se certificó, qué saldo queda). La portada
  /// se queda con los montos cerrados y nada más -- ver docs/criterio_pantalla_principal_vs_
  /// resumen.md. Tocar cualquier otra parte de la card sigue abriendo la obra en Cómputo, como
  /// siempre.
  Widget _buildVinculoResumen(Map<String, dynamic> obra) {
    return InkWell(
      onTap: () => _abrirPresupuesto(obra, solapa: SolapaPresupuestos.resumen),
      borderRadius: BorderRadius.circular(4),
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Ver el detalle en Resumen',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF1B365D)),
            ),
            SizedBox(width: 3),
            Icon(Icons.arrow_forward, size: 12, color: Color(0xFF1B365D)),
          ],
        ),
      ),
    );
  }

  /// Un monto cerrado de la card de obra: rótulo a la izquierda, cifra a la derecha, mismo tamaño
  /// y mismo peso para todos los que la usan (pactado, adicional aprobado, total). Los dos
  /// primeros están firmados y congelados, así que van iguales -- darle al adicional un
  /// tratamiento menor lo hacía leer como un detalle de la suma del pactado, no como un monto
  /// aprobado por sí mismo (pedido de Seba, 2026-09-13).
  ///
  /// El rótulo es el que cede ancho (Expanded + ellipsis): en una card angosta lo que no puede
  /// recortarse es la cifra (memoria de overflow en pantalla angosta).
  Widget _buildMontoCerrado(String rotulo, double monto, String moneda, {bool conCandado = true}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Candado en los montos firmados; el total es derivado, no se firma aparte -- pero deja el
        // mismo hueco para que los tres rótulos arranquen alineados.
        if (conCandado)
          const Padding(
            padding: EdgeInsets.only(bottom: 3),
            child: Icon(Icons.lock_outline, size: 10, color: Colors.black45),
          )
        else
          const SizedBox(width: 10),
        const SizedBox(width: 3),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(
              rotulo,
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.black54),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _formatearMonto(monto, moneda),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF1B365D)),
        ),
      ],
    );
  }

  /// Referencia "Hoy · Desfasaje" para obra congelada -- el pactado ya es el número grande de la
  /// card (criterio de Seba, 2026-09-12: "el precio de la obra debe ser en grande el que se
  /// pactó"), así que acá no se repite, solo el dato de comparación.
  ///
  /// `montoHoy` viene de `calcularPresupuestoHoyConfigCongelada` (0110) -- recalculado con la
  /// MISMA configuración de Factor K con la que se congeló (`presupuesto_config_congelado`), no
  /// con los interruptores vigentes de la Solapa APU. Antes de esta corrección el chip comparaba
  /// contra `calcular_presupuesto_vivo_obra` (config vigente) y podía mostrar un desfasaje que en
  /// realidad era un cambio de configuración, no de costos -- caso real: obra congelada con
  /// impuestos aplicados, interruptor de impuestos apagado después, "desfasaje" de 20% que no
  /// `montoHoyMostrar` llega en la moneda de visualización (es lo único que se imprime); el
  /// **porcentaje se calcula siempre en pesos**, con `montoHoyArs`/`montoPactadoArs`. Antes los dos
  /// llegaban convertidos y daba igual, porque compartían cotización y esta se cancelaba en la
  /// división. Desde la 0122 no la comparten -- el pactado usa la del congelamiento y "Hoy" la de
  /// hoy -- así que calcularlo sobre los convertidos le sumaría al desfasaje la variación del dólar,
  /// justo la mezcla que la 0110 vino a sacar (desfasaje de costos vs. de configuración). El
  /// desfasaje mide costos: se calcula en pesos y vale igual en cualquier moneda.
  ///
  /// `Wrap`, no `Row` -- incluso con textos cortos, varias piezas de texto en una card angosta
  /// (memoria de overflow en pantalla angosta) tienen que poder pasar a una segunda línea.
  Widget _buildComparacionCongelada(
    String obraId,
    double montoHoyMostrar,
    double montoHoyArs,
    double montoPactadoArs,
    String moneda,
  ) {
    final double? desfasajePct =
        montoPactadoArs != 0 ? ((montoHoyArs - montoPactadoArs) / montoPactadoArs) * 100 : null;
    final bool subio = (desfasajePct ?? 0) >= 0;
    final bool avisoDescartado = _avisoDesfasajeDescartadoObras.contains(obraId);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.indigo.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 10,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Hoy ${_formatearMonto(montoHoyMostrar, moneda)}',
                      style: TextStyle(fontSize: 10.5, color: Colors.indigo.shade900),
                    ),
                    if (desfasajePct != null)
                      Text(
                        'Desfasaje ${subio ? '+' : ''}${desfasajePct.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: subio ? Colors.red.shade700 : Colors.green.shade700,
                        ),
                      ),
                  ],
                ),
              ),
              if (avisoDescartado)
                IconButton(
                  icon: Icon(Icons.info_outline, size: 13, color: Colors.indigo.shade300),
                  tooltip: 'Qué significa el desfasaje',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _restaurarAvisoDesfasaje(obraId),
                ),
            ],
          ),
          if (!avisoDescartado) ...[
            const SizedBox(height: 4),
            _buildAvisoDesfasaje(obraId),
          ],
        ],
      ),
    );
  }

  /// Aviso descartable, primera vez -- explica qué es "Hoy" y el desfasaje sin invadir al que ya
  /// lo sabe. Mismo mecanismo que el aviso de zona UOCRA (CartelCostoManoObra): SharedPreferences
  /// por obra, ícono chico para restaurarlo.
  Widget _buildAvisoDesfasaje(String obraId) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(color: Colors.indigo.shade100.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(4)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Expanded(
            child: Text(
              'El desfasaje mide cuánto se corrió el costo de los materiales/mano de obra desde que '
              'se firmó, con la misma configuración pactada. No cambia el precio contratado.',
              style: TextStyle(fontSize: 9.5, color: Colors.black87),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 13, color: Colors.indigo.shade700),
            tooltip: 'Cerrar aviso',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => _descartarAvisoDesfasaje(obraId),
          ),
        ],
      ),
    );
  }

  /// Acepta coma o punto como separador decimal (mismo criterio que
  /// _parsearCantidad/_parsearPrecio de SubitemsScreen) y rechaza vacío,
  /// no numérico o <= 0 — una obra de 0 m² no tiene sentido. Antes el alta
  /// no validaba esto en absoluto: `double.tryParse(...) ?? 100.0` caía en
  /// silencio a un valor inventado si el texto no parseaba, sin avisar
  /// nada — peligroso siempre, y directamente inaceptable en edición
  /// (podía pisar la superficie real de una obra en curso sin que nadie se
  /// enterara).
  double? _parsearSuperficie(String texto) {
    final valor = ParserNumeroAr.parsear(texto);
    if (valor == null || valor <= 0) return null;
    return valor;
  }

  /// Para precargar el campo de superficie en el diálogo de edición sin
  /// mostrar "120.0" cuando el valor real es un entero.
  String _formatearCantidadSuperficie(double valor) {
    return valor == valor.roundToDouble() ? valor.toInt().toString() : valor.toString();
  }

  /// Texto y estilo del helper de superficie. Normal (fontSize 10, sin más)
  /// o reforzado en naranja + negrita con la lectura alternativa entre
  /// paréntesis, solo cuando el punto se interpretó como separador de miles
  /// (ver ParserNumeroAr.esInterpretacionDeMiles) -- el de doble punto queda
  /// discreto a propósito, si el aviso apareciera siempre dejaría de
  /// notarse. Usado en los dos diálogos (alta y edición).
  (String, TextStyle) _previewSuperficie(String texto) {
    const estiloNormal = TextStyle(fontSize: 10);
    final valor = ParserNumeroAr.parsear(texto);
    if (valor == null) return ('', estiloNormal);
    final normal = 'Se guardará: ${_formatearCantidadSuperficie(valor)} m²';
    if (!ParserNumeroAr.esInterpretacionDeMiles(texto)) return (normal, estiloNormal);
    final alterno = ParserNumeroAr.lecturaAlternativaSiEsMiles(texto);
    final reforzado =
        alterno != null ? '$normal (no ${_formatearCantidadSuperficie(alterno)} m²)' : normal;
    return (reforzado, TextStyle(fontSize: 10, color: Colors.orange[800], fontWeight: FontWeight.bold));
  }

  // --- Navegación a la Solapa de Presupuesto ---
  //
  // Bug real corregido acá (Seba, 2026-09-08): el push no esperaba el pop ni refrescaba nada al
  // volver -- el dashboard es la ruta raíz, su State nunca se destruye mientras PresupuestosScreen
  // está encima, así que sin este await+recarga el presupuesto vivo de la card quedaba con el valor
  // de cuando se entró a la obra, sin importar cuánto cómputo se cargara adentro. No hay
  // RefreshIndicator en esta pantalla como alternativa manual -- hacía falta esto sí o sí.
  /// `solapa`: en qué solapa abre la obra. El default es Cómputo (tocar la card). El vínculo de la
  /// card va a Resumen -- la portada es panorámica y el análisis vive ahí
  /// (docs/criterio_pantalla_principal_vs_resumen.md) -- y el aviso de "ya se puede certificar" va a
  /// Gestión de Obra, que es donde se crea el borrador. En los dos casos el "ver más" tiene que caer
  /// en la solapa correcta, sin obligar a buscarla a mano.
  Future<void> _abrirPresupuesto(
    Map<String, dynamic> obra, {
    SolapaPresupuestos solapa = SolapaPresupuestos.computo,
  }) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PresupuestosScreen(obra: obra, solapaInicial: solapa),
      ),
    );
    if (!mounted) return;
    _cargarObras();
  }

  // --- Diálogo: Mapa de Obras Registradas ---
  void _mostrarMapaObras() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.map_outlined, color: Color(0xFF1B365D)),
            SizedBox(width: 8),
            // Mismo patrón que los otros 2 títulos de diálogo ya corregidos
            // en esta sesión — título de AlertDialog sin Expanded desborda
            // en pantallas angostas.
            Expanded(
              child: Text('Mapa de Obras Registradas', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 180,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.blueGrey[100],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blueGrey[300]!),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(Icons.map, size: 100, color: Colors.blueGrey[300]),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B365D).withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.location_on, color: Colors.redAccent, size: 16),
                          SizedBox(width: 4),
                          Text('Vista Satelital / Ubicaciones', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text('Ubicaciones georreferenciadas en legajo:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _obras.length,
                  itemBuilder: (context, index) {
                    final item = _obras[index];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.place, color: Color(0xFF1B365D), size: 18),
                      title: Text(item['nombre'], style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      subtitle: Text(item['ubicacion'], style: const TextStyle(fontSize: 10, color: Colors.black54)),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B365D)),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // --- Diálogo: Alta de Nueva Obra ---
  void _mostrarModalNuevaObra() {
    final nombreCtrl = TextEditingController();
    final propietarioCtrl = TextEditingController();
    final ubicacionCtrl = TextEditingController();
    final superficieCtrl = TextEditingController();
    String tipoSeleccionado = 'Residencial';
    String monedaSeleccionada = 'ARS';
    bool guardando = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final previewSuperficie = _previewSuperficie(superficieCtrl.text);
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: const Row(
              children: [
                Icon(Icons.add_business_outlined, color: Color(0xFF1B365D)),
                SizedBox(width: 8),
                // Expanded preventivo: mismo riesgo que tenía el título de
                // "Ajuste Económico & Moneda" (título de AlertDialog sin
                // Expanded desborda en pantallas angostas) — este texto es
                // más corto y no se reportó roto todavía, pero es el mismo
                // patrón sin resolver.
                Expanded(
                  child: Text('Alta de Nueva Obra', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amber[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber[700]!),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.gavel_outlined, size: 18, color: Colors.amber[900]),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Los datos ingresados en este formulario (Nombre de Obra, Propietario, Ubicación, Superficie) se consolidarán de manera definitiva en las carátulas, encabezados y legajos exportables en PDF.',
                            style: TextStyle(fontSize: 10, color: Colors.amber[900], height: 1.3, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: nombreCtrl,
                    style: const TextStyle(fontSize: 12),
                    // labelStyle a juego con el texto tipeado (12) — el label
                    // heredaba el tamaño default del tema (~16), que no
                    // entraba entero en un campo angosto y se recortaba con
                    // "...". A 12 entra sin tocar ninguna palabra del texto.
                    decoration: const InputDecoration(
                      labelText: 'Nombre de la Obra / Proyecto',
                      labelStyle: TextStyle(fontSize: 12),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: propietarioCtrl,
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      labelText: 'Propietario / Comitente',
                      labelStyle: TextStyle(fontSize: 12),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: ubicacionCtrl,
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      labelText: 'Ubicación / Localidad',
                      labelStyle: TextStyle(fontSize: 12),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: superficieCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 12),
                    onChanged: (_) => setModalState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Superficie (m²)',
                      labelStyle: const TextStyle(fontSize: 12),
                      border: const OutlineInputBorder(),
                      isDense: true,
                      // helperText no nulo desde el arranque (string
                      // vacío, no null): con null el campo no reserva
                      // la línea y salta de alto al aparecer el primer
                      // preview.
                      helperText: previewSuperficie.$1,
                      helperStyle: previewSuperficie.$2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Fuera de la fila de Superficie a propósito (antes
                  // compartía Row 50/50 con este campo): con el preview
                  // reforzado de miles ("Se guardará: X (no Y)") el campo de
                  // superficie no entraba en la mitad del ancho del diálogo
                  // y el texto se cortaba (ver diagnóstico de esta pieza).
                  // Cada uno en su propia fila le da a los dos el ancho
                  // completo, sin negociar con el largo del mensaje.
                  DropdownButtonFormField<String>(
                    initialValue: tipoSeleccionado,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Tipo',
                      labelStyle: TextStyle(fontSize: 11),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 11, color: Colors.black87),
                    items: ['Residencial', 'Comercial/Residencial', 'Industrial', 'Infraestructura']
                        .map((t) => DropdownMenuItem(
                              value: t,
                              child: Text(t, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setModalState(() => tipoSeleccionado = val);
                    },
                  ),
                  const SizedBox(height: 10),
                  // Wrap en vez de Row: acá no hay ningún widget con texto
                  // que pueda ceder ancho (los chips no truncan su label
                  // solo, y "Moneda Base:" ya es corto) — si algún día no
                  // entran los tres en una línea, el que sobra pasa a la
                  // siguiente en vez de desbordar. Robusto a cualquier
                  // ancho, no solo al de este diálogo hoy.
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      const Text('Moneda Base:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ChoiceChip(
                        label: const Text('ARS (\$)', style: TextStyle(fontSize: 11)),
                        selected: monedaSeleccionada == 'ARS',
                        onSelected: (sel) {
                          if (sel) setModalState(() => monedaSeleccionada = 'ARS');
                        },
                      ),
                      ChoiceChip(
                        label: const Text('USD', style: TextStyle(fontSize: 11)),
                        selected: monedaSeleccionada == 'USD',
                        onSelected: (sel) {
                          if (sel) setModalState(() => monedaSeleccionada = 'USD');
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Wrap, no Row: acá ambos textos son cortos y fijos (bajo
                  // riesgo por el criterio de la memoria), pero dentro de un
                  // AlertDialog el margen es chico igual — si algún día no
                  // entran los tres juntos, el badge pasa a la línea
                  // siguiente en vez de desbordar.
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      const Icon(Icons.person_pin_circle_outlined, size: 14, color: Colors.black45),
                      const Text('Creador: Vos', style: TextStyle(fontSize: 11, color: Colors.black54)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(4)),
                        child: const Text(
                          'Administrador por defecto',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black54),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B365D)),
                onPressed: guardando
                    ? null
                    : () async {
                        if (nombreCtrl.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Por favor ingrese el nombre de la obra.')),
                          );
                          return;
                        }
                        final double? sup = _parsearSuperficie(superficieCtrl.text);
                        if (sup == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Ingresá una superficie válida, mayor a 0.')),
                          );
                          return;
                        }
                        setModalState(() => guardando = true);
                        try {
                          final creada = await _obrasRepository.crearObra({
                            'nombre': nombreCtrl.text.trim(),
                            'propietario': propietarioCtrl.text.trim().isEmpty ? 'Sin Especificar' : propietarioCtrl.text.trim(),
                            'ubicacion': ubicacionCtrl.text.trim().isEmpty ? 'Ubicación Faltante' : ubicacionCtrl.text.trim(),
                            'superficieM2': sup,
                            'tipoObra': tipoSeleccionado,
                            'estado': 'Cotización',
                            'moneda': monedaSeleccionada,
                            'aplicaCac': monedaSeleccionada == 'ARS',
                            // Una obra nueva arranca sin cómputo -- el monto tiene que ser 0, nunca
                            // una estimación derivada de la superficie. Bug real (Seba, 2026-09-08):
                            // acá había una fórmula "sup * 1.000.000 ARS/m² (o sup * 750 USD/m²)
                            // como estimación de arranque" que terminaba guardando la superficie
                            // como si fuera un monto real -- una obra de 200m² quedaba con
                            // monto_total = 200.000.000. El monto real se carga solo cuando hay
                            // cómputo cargado (calcular_presupuesto_vivo_obra, 0091), nunca acá.
                            'montoTotal': 0.0,
                            // Bug real encontrado 2026-09-10: acá había el string literal
                            // 'Agosto 2026', escrito igual en toda obra nueva sin importar la
                            // fecha real de creación -- obras.mes_base_cac es `date` desde
                            // 0102_indices_cac_cotizacion_dolar.sql, primer día del mes en curso.
                            'mesBaseCac': _primerDiaDelMesActual(),
                            'revision': 'Rev. 00',
                            'tipoRol': 'Director de Obra',
                            'estadoServicioEspecial': 'Ninguno',
                            'idAdminCreador': _authService.usuarioActual?.id,
                          });
                          if (!context.mounted) return;
                          // 0.0 directo, no una llamada a calcularPresupuestoVivo: una obra recién
                          // creada no tiene ningún obra_subitems todavía, la función de base daría
                          // 0 igual -- ahorra el viaje de red.
                          setState(() => _obras.add(_conMontosCalculados(creada, 0.0, null, null)));
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Nueva obra registrada exitosamente.')),
                          );
                        } catch (e) {
                          if (!context.mounted) return;
                          setModalState(() => guardando = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('No se pudo guardar la obra. Intente nuevamente.')),
                          );
                        }
                      },
                child: guardando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Crear Obra', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  // --- Diálogo: Editar Obra ---
  //
  // Reusa la estructura del alta, pero deliberadamente NO reusa su
  // guardado: acá no hay ningún campo de moneda (eso queda exclusivo del
  // diálogo de Ajuste Económico — mezclarlos correría el riesgo real de
  // cambiar la moneda por acá sin la lógica de default de CAC que ya tiene
  // ese diálogo), y el guardado escribe un mapa parcial con solo los 5
  // campos descriptivos — nunca montoTotal, moneda ni aplicaCac. El alta
  // recalcula montoTotal desde la superficie como estimación de arranque;
  // reusar ese cálculo acá le pisaría el monto real de una obra en curso
  // con esa fórmula cruda cada vez que alguien corrija solo el nombre.
  void _mostrarModalEditarObra(Map<String, dynamic> obra) {
    final nombreCtrl = TextEditingController(text: obra['nombre'] as String? ?? '');
    final propietarioCtrl = TextEditingController(text: obra['propietario'] as String? ?? '');
    final ubicacionCtrl = TextEditingController(text: obra['ubicacion'] as String? ?? '');
    final superficieCtrl = TextEditingController(
      text: _formatearCantidadSuperficie((obra['superficieM2'] as num?)?.toDouble() ?? 0),
    );
    String tipoSeleccionado = (obra['tipoObra'] as String?) ?? 'Residencial';
    bool guardando = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final previewSuperficie = _previewSuperficie(superficieCtrl.text);
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: const Row(
              children: [
                Icon(Icons.edit_outlined, color: Color(0xFF1B365D)),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Editar Obra', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amber[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber[700]!),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.gavel_outlined, size: 18, color: Colors.amber[900]),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Estos datos se consolidan en las carátulas, encabezados y legajos '
                            'exportables en PDF — el cambio se refleja en cualquier documento nuevo '
                            'que se genere de acá en más.',
                            style: TextStyle(fontSize: 10, color: Colors.amber[900], height: 1.3, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: nombreCtrl,
                    autofocus: true,
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      labelText: 'Nombre de la Obra / Proyecto',
                      labelStyle: TextStyle(fontSize: 12),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: propietarioCtrl,
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      labelText: 'Propietario / Comitente',
                      labelStyle: TextStyle(fontSize: 12),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: ubicacionCtrl,
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      labelText: 'Ubicación / Localidad',
                      labelStyle: TextStyle(fontSize: 12),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: superficieCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(fontSize: 12),
                    onChanged: (_) => setModalState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Superficie (m²)',
                      labelStyle: const TextStyle(fontSize: 12),
                      border: const OutlineInputBorder(),
                      isDense: true,
                      // helperText no nulo desde el arranque, mismo
                      // motivo que en el diálogo de alta: evitar el
                      // salto de alto al primer preview.
                      helperText: previewSuperficie.$1,
                      helperStyle: previewSuperficie.$2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Fuera de la fila de Superficie a propósito, mismo motivo
                  // que en el diálogo de alta: con el preview reforzado de
                  // miles el campo no entraba en la mitad del ancho del
                  // diálogo y el texto se cortaba.
                  DropdownButtonFormField<String>(
                    initialValue: tipoSeleccionado,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Tipo',
                      labelStyle: TextStyle(fontSize: 11),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 11, color: Colors.black87),
                    items: ['Residencial', 'Comercial/Residencial', 'Industrial', 'Infraestructura']
                        .map((t) => DropdownMenuItem(
                              value: t,
                              child: Text(t, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setModalState(() => tipoSeleccionado = val);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: guardando ? null : () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B365D)),
                onPressed: guardando
                    ? null
                    : () async {
                        if (nombreCtrl.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Por favor ingrese el nombre de la obra.')),
                          );
                          return;
                        }
                        final double? sup = _parsearSuperficie(superficieCtrl.text);
                        if (sup == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Ingresá una superficie válida, mayor a 0.')),
                          );
                          return;
                        }

                        setModalState(() => guardando = true);
                        try {
                          final nombre = nombreCtrl.text.trim();
                          final propietario = propietarioCtrl.text.trim().isEmpty ? 'Sin Especificar' : propietarioCtrl.text.trim();
                          final ubicacion = ubicacionCtrl.text.trim().isEmpty ? 'Ubicación Faltante' : ubicacionCtrl.text.trim();
                          // Mapa parcial a propósito — sin montoTotal, moneda
                          // ni aplicaCac, ver comentario del método.
                          await _obrasRepository.actualizarObra(obra['id'] as String, {
                            'nombre': nombre,
                            'propietario': propietario,
                            'ubicacion': ubicacion,
                            'superficieM2': sup,
                            'tipoObra': tipoSeleccionado,
                          });
                          if (!context.mounted) return;
                          setState(() {
                            obra['nombre'] = nombre;
                            obra['propietario'] = propietario;
                            obra['ubicacion'] = ubicacion;
                            obra['superficieM2'] = sup;
                            obra['tipoObra'] = tipoSeleccionado;
                          });
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Obra actualizada.')),
                          );
                        } catch (e, st) {
                          // El error real a la consola -- mismo criterio que _configurarAjusteEconomico
                          // (más abajo): antes esto no decía nada, ni siquiera cuando actualizarObra
                          // empezó a poder lanzar StateError (0 filas actualizadas, ver ese método).
                          debugPrint('_abrirEditarObra: guardar falló: $e\n$st');
                          if (!context.mounted) return;
                          setModalState(() => guardando = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                e is StateError ? e.message : 'No se pudo guardar los cambios. Probá de nuevo.',
                              ),
                            ),
                          );
                        }
                      },
                child: guardando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Guardar Cambios', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  /// ¿Puede este usuario editar la configuración económica/eliminar/editar esta obra? Corregido
  /// (2026-09-11, decisión de Seba): ya NO mira `idAdminCreador` -- ese campo es inmutable y hacía
  /// al creador "dueño para siempre", sin reflejar que puede haber varios `admin_maestro` (`0108`,
  /// el dueño le puede dar el rol a otro) ni que alguien puede renunciar a ese rol (`MiembrosObraScreen`,
  /// vía `quitar_miembro_obra` sobre su propia fila) -- con el criterio viejo, renunciar no sacaba
  /// estos íconos porque `idAdminCreador` seguía siendo suyo para siempre. Ahora mira `_obraIdsAdmin`
  /// (cargado una sola vez para toda la lista en `_cargarObras`, ver ese comentario), que sale de
  /// `obra_members` -- la fuente de verdad real del rol, no un campo histórico de quién la creó.
  bool _esAdminDeObra(Map<String, dynamic> obra) => _obraIdsAdmin.contains(obra['id']);

  // --- Diálogo: Ajuste Económico & Moneda ---
  void _configurarAjusteEconomico(Map<String, dynamic> obra) {
    String monedaSeleccionada = obra['moneda'];
    bool aplicaCac = obra['aplicaCac'] ?? false;
    final TextEditingController cotizacionCtrl = TextEditingController(
      text: _cotizacionUsdEfectiva.toStringAsFixed(0),
    );

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final bool esPersonalizada = _cotizacionUsdEfectiva != _dolarOficialPromedio;

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: const Row(
              children: [
                Icon(Icons.payments_outlined, color: Color(0xFF1B365D)),
                SizedBox(width: 8),
                // Expanded: el título de un AlertDialog no está dentro del
                // SingleChildScrollView del content, así que sin esto el
                // Row desborda en vez de que el texto ajuste — mismo
                // patrón de siempre, acá con un título más largo que el
                // de "Alta de Nueva Obra" (que tiene el mismo riesgo
                // latente, corregido de paso más abajo).
                Expanded(
                  child: Text('Ajuste Económico & Moneda', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Obra: ${obra['nombre']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blueGrey[200]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Expanded: mismo patrón de siempre — el badge
                            // "PRO" es corto y fijo, el label es el que
                            // tiene que ceder si no entra.
                            Expanded(
                              child: Text(
                                'Dólar Ref. Banco Nación (BNA):',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1B365D)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (_esPlanPro) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: Colors.amber[700], borderRadius: BorderRadius.circular(4)),
                                child: const Text('PRO', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Promedio Oficial (\$${_dolarBnaCompra.toStringAsFixed(0)} / \$${_dolarBnaVenta.toStringAsFixed(0)}): \$${_dolarOficialPromedio.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 10, color: Colors.black87),
                        ),
                        Text(
                          'Fuente: Banco Nación Argentina • Fecha: $_fechaActualizacionDolar',
                          style: const TextStyle(fontSize: 9, color: Colors.black54, fontStyle: FontStyle.italic),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Valor Activo: \$ ${_cotizacionUsdEfectiva.toStringAsFixed(2)} ${esPersonalizada ? "(Proyección Personalizada)" : "(Promedio Oficial BNA)"}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: esPersonalizada ? Colors.orange[900] : const Color(0xFF2E7D32),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_esPlanPro) ...[
                    const Text('Ingresar Proyección / Dólar Libre (PRO):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 40,
                            child: TextField(
                              controller: cotizacionCtrl,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                              decoration: InputDecoration(
                                prefixText: '\$ ',
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1B365D),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                          ),
                          onPressed: () {
                            final nuevoValor = double.tryParse(cotizacionCtrl.text);
                            if (nuevoValor != null && nuevoValor > 0) {
                              setState(() => _cotizacionUsdEfectiva = nuevoValor);
                              setDialogState(() {});
                            }
                          },
                          child: const Text('Aplicar', style: TextStyle(color: Colors.white, fontSize: 11)),
                        ),
                      ],
                    ),
                    if (esPersonalizada)
                      TextButton(
                        onPressed: () {
                          setState(() => _cotizacionUsdEfectiva = _dolarOficialPromedio);
                          cotizacionCtrl.text = _dolarOficialPromedio.toStringAsFixed(0);
                          setDialogState(() {});
                        },
                        child: const Text('Restablecer a Promedio BNA', style: TextStyle(fontSize: 10, color: Colors.blue)),
                      ),
                  ] else ...[
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.amber[50], borderRadius: BorderRadius.circular(6)),
                      child: const Row(
                        children: [
                          Icon(Icons.lock_outline, size: 16, color: Colors.amber),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'En versión FREE se utiliza el dólar promedio Banco Nación. La proyección / cotización personalizada requiere versión PRO.',
                              style: TextStyle(fontSize: 10, color: Colors.black87),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const Divider(),
                  const Text('Moneda Base de Cotización:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment<String>(
                        value: 'ARS',
                        label: Text('Pesos (\$)'),
                      ),
                      ButtonSegment<String>(
                        value: 'USD',
                        label: Text('Dólares (USD)'),
                      ),
                    ],
                    selected: {monedaSeleccionada},
                    onSelectionChanged: (Set<String> newSelection) {
                      final String nuevaMoneda = newSelection.first;
                      setDialogState(() {
                        if (nuevaMoneda == 'USD') {
                          aplicaCac = false;
                        } else if (nuevaMoneda == 'ARS' && monedaSeleccionada != 'ARS') {
                          // En pesos el CAC no es opcional por defecto — un
                          // presupuesto en ARS sin referencia de ajuste no
                          // se sostiene en el tiempo. Se activa solo al
                          // pasar A pesos (cada vez, no solo la primera
                          // vez); el usuario lo puede destildar antes de
                          // guardar, ver SwitchListTile de abajo.
                          aplicaCac = true;
                        }
                        monedaSeleccionada = nuevaMoneda;
                      });
                    },
                  ),
                  if (monedaSeleccionada == 'ARS') ...[
                    const SizedBox(height: 10),
                    SwitchListTile(
                      title: const Text('Ajuste por Índice CAC', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        'Actualización mensual constante.\nÚltimo publicado ($_ultimoMesPublicadoCac): +$_variacionCacUltimoMes%',
                        style: const TextStyle(fontSize: 10, color: Colors.black54),
                      ),
                      value: aplicaCac,
                      activeTrackColor: const Color(0xFF1B365D),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (val) {
                        setDialogState(() => aplicaCac = val);
                      },
                    ),
                    // Fijo mientras esté apagado, no un pop-up al destildar
                    // — así queda visible cada vez que se revisa este
                    // estado, no solo en el instante de apagarlo.
                    if (!aplicaCac)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Sin el ajuste por CAC, este presupuesto en pesos queda fijo: no se '
                          'actualiza solo con el costo de la construcción. Tenelo en cuenta sobre '
                          'todo al certificar avances — un monto viejo sin ajustar termina '
                          'cobrando menos de lo que le cuesta la obra.',
                          style: TextStyle(fontSize: 10, color: Colors.orange[900]),
                        ),
                      ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B365D)),
                onPressed: () async {
                  final String monedaAnterior = obra['moneda'] as String;
                  // Bug real encontrado 2026-09-10 (Seba, al verificar la carga de la
                  // cotización): esto leía `obra['montoTotal']`, la columna `obras.monto_total`
                  // -- que ninguna otra parte de la app mantiene al día desde que existe el
                  // presupuesto vivo (`calcular_presupuesto_vivo_obra`, 0091). Se escribe en 0.0
                  // al crear la obra y nunca más, salvo acá mismo -- así que para cualquier obra
                  // con cómputo real cargado, `montoTotalAnterior` daba 0 siempre, sin importar
                  // la cotización. No era una carrera contra `_cargarIndicadoresEconomicos` (la
                  // cotización ya está disponible en un valor no nulo desde el primer frame, ver
                  // `_convertirMonto`) -- el dato de origen estaba mal, no el momento en que se
                  // usaba. El monto vivo real ya está en `montoEstimadoArs`/`montoEstimadoUsd`
                  // (`_conMontosCalculados`, recalculado en cada carga) -- es la fuente correcta.
                  final double montoTotalAnterior = monedaAnterior == 'ARS'
                      ? (obra['montoEstimadoArs'] as num?)?.toDouble() ?? 0.0
                      : (obra['montoEstimadoUsd'] as num?)?.toDouble() ?? 0.0;
                  final double nuevoMontoTotal = monedaSeleccionada == monedaAnterior
                      ? montoTotalAnterior
                      : _convertirMonto(montoTotalAnterior, monedaAnterior, monedaSeleccionada);
                  final bool nuevoAplicaCac = (monedaSeleccionada == 'ARS') ? aplicaCac : false;

                  try {
                    await _obrasRepository.actualizarObra(obra['id'] as String, {
                      'moneda': monedaSeleccionada,
                      'aplicaCac': nuevoAplicaCac,
                      'montoTotal': nuevoMontoTotal,
                    });
                    if (!context.mounted) return;
                    setState(() {
                      obra['moneda'] = monedaSeleccionada;
                      obra['aplicaCac'] = nuevoAplicaCac;
                      obra['montoTotal'] = nuevoMontoTotal;
                      obra['montoEstimadoArs'] = monedaSeleccionada == 'ARS' ? nuevoMontoTotal : _convertirMonto(nuevoMontoTotal, monedaSeleccionada, 'ARS');
                      obra['montoEstimadoUsd'] = monedaSeleccionada == 'USD' ? nuevoMontoTotal : _convertirMonto(nuevoMontoTotal, monedaSeleccionada, 'USD');
                    });
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Configuración económica guardada.')),
                    );
                  } catch (e, st) {
                    // El error real a la consola -- antes esto no decía nada, y un StateError de
                    // _convertirMonto (cotización inválida) se mostraba igual que cualquier otro
                    // fallo de guardado, sin poder distinguir la causa.
                    debugPrint('_configurarAjusteEconomico: guardar falló: $e\n$st');
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          e is StateError
                              ? e.message
                              : 'No se pudo guardar la configuración. Intente nuevamente.',
                        ),
                      ),
                    );
                  }
                },
                child: const Text('Guardar', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  // --- Modal: Suscripción Plan PRO ---
  void _mostrarModalPro() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFF1B365D).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.workspace_premium, color: Color(0xFF1B365D), size: 28),
                ),
                const SizedBox(width: 12),
                // Expanded: mismo patrón de siempre — el ícono con badge de
                // la izquierda es de ancho fijo, el bloque de texto tiene
                // que ceder si no entra.
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Suscripción Profesional',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1B365D)),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Gestión técnica y financiera avanzada',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(),
            _buildProItem(Icons.attach_money, 'Proyección y Personalización de Cotización USD'),
            _buildProItem(Icons.trending_up, 'Redeterminación de Precios y Certificación por Índice CAC'),
            _buildProItem(Icons.eco_outlined, 'Cálculos Envolvente Edilicia K, G y Q (bajo Normas IRAM)'),
            _buildProItem(Icons.picture_as_pdf_outlined, 'Exportación de Legajos limpios sin marca de agua'),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1B365D),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  setState(() => _esPlanPro = !_esPlanPro);
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(_esPlanPro ? 'Suscripción PRO Activada.' : 'Modo FREE Activado.')),
                  );
                },
                child: Text(
                  _esPlanPro ? 'DESACTIVAR PLAN PRO' : 'ACTIVAR CUENTA PRO',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF1B365D)),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  // --- Diálogo: Servicios Técnicos Especiales ---
  void _abrirModalServiciosEspeciales(Map<String, dynamic> obra) {
    String? tipoComputo;
    final List<String> opcionesExtra = [
      'Acondicionamiento Térmico (Normas IRAM — Cálculo K, G, Q)',
      'Legajo de Detalles Constructivos',
      'Otro (especificar) — sujeto a evaluación',
    ];
    final List<bool> seleccionadosExtra = List<bool>.filled(opcionesExtra.length, false);
    bool archivoAdjuntado = false;
    String? nombreArchivo;
    final notasCtrl = TextEditingController();
    final otroCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final bool haySeleccion = tipoComputo != null || seleccionadosExtra.contains(true);
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: const Row(
              children: [
                Icon(Icons.assignment_outlined, color: Color(0xFF1B365D)),
                SizedBox(width: 8),
                // Mismo patrón que los otros títulos de diálogo ya
                // corregidos en esta sesión.
                Expanded(
                  child: Text('Servicios Especiales', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Obra: ${obra['nombre']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 12),
                  const Text('Solicitar presupuesto para elaboración técnica de:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87)),
                  const SizedBox(height: 4),
                  _buildRadioOption(
                    'Cómputo Métrico',
                    'Listado de cantidades y materiales — precios a cargo del usuario.',
                    'metrico',
                    tipoComputo,
                    (val) => setModalState(() => tipoComputo = val),
                  ),
                  _buildRadioOption(
                    'Cómputo y Presupuesto',
                    'Cómputo + presupuesto completo con precios incluidos.',
                    'completo',
                    tipoComputo,
                    (val) => setModalState(() => tipoComputo = val),
                  ),
                  const SizedBox(height: 6),
                  for (int i = 0; i < opcionesExtra.length; i++) ...[
                    _buildCheckOption(
                      opcionesExtra[i],
                      seleccionadosExtra[i],
                      (val) => setModalState(() => seleccionadosExtra[i] = val ?? false),
                    ),
                    if (i == 2 && seleccionadosExtra[2])
                      Padding(
                        padding: const EdgeInsets.only(left: 32, right: 4, bottom: 6),
                        child: TextField(
                          controller: otroCtrl,
                          maxLines: 2,
                          style: const TextStyle(fontSize: 12),
                          decoration: const InputDecoration(
                            hintText: 'Contame qué necesitás (render, documentación contractual, información legal, etc.)',
                            hintStyle: TextStyle(fontSize: 11),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                  ],
                  if (!haySeleccion)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, bottom: 4),
                      child: Text(
                        'Tildá al menos un servicio para solicitar la cotización.',
                        style: TextStyle(fontSize: 10, color: Colors.red[700], fontWeight: FontWeight.w600),
                      ),
                    ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 40)),
                    icon: Icon(
                      archivoAdjuntado ? Icons.check_circle : Icons.upload_file,
                      size: 18,
                      color: archivoAdjuntado ? Colors.green[700] : null,
                    ),
                    label: Text(
                      archivoAdjuntado ? (nombreArchivo ?? 'Archivo adjuntado') : 'Adjuntar Planos / Anteproyecto (PDF/DWG)',
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                    onPressed: () {
                      setModalState(() {
                        archivoAdjuntado = true;
                        nombreArchivo = 'planta_general.pdf';
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Archivo adjuntado correctamente.')),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notasCtrl,
                    maxLines: 3,
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      labelText: 'Notas / Comentario adicional (opcional)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B365D)),
                onPressed: !haySeleccion
                    ? null
                    : () {
                        setState(() {
                          obra['estadoServicioEspecial'] = 'En Revision';
                        });
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Solicitud enviada a revisión. Nos contactaremos a la brevedad.')),
                        );
                      },
                child: const Text('Solicitar Cotización', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRadioOption(
    String label,
    String descripcion,
    String value,
    String? groupValue,
    ValueChanged<String?> onChanged,
  ) {
    return InkWell(
      onTap: () => onChanged(value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Radio<String>(
              value: value,
              groupValue: groupValue,
              onChanged: onChanged,
              activeColor: const Color(0xFF1B365D),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                    Text(descripcion, style: TextStyle(fontSize: 10, color: Colors.grey[700])),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckOption(String label, bool value, ValueChanged<bool?> onChanged) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Checkbox(
              value: value,
              onChanged: onChanged,
              activeColor: const Color(0xFF1B365D),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const SizedBox(width: 4),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 11))),
          ],
        ),
      ),
    );
  }

  // --- Diálogo: Confirmar Eliminación ---
  void _confirmarEliminar(Map<String, dynamic> obra) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Obra'),
        content: Text('¿Desea borrar definitivamente "${obra['nombre']}"? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700]),
            onPressed: () async {
              try {
                await _obrasRepository.eliminarObra(obra['id'] as String);
                if (!mounted || !ctx.mounted) return;
                setState(() => _obras.removeWhere((i) => i['id'] == obra['id']));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Obra eliminada del registro.')),
                );
              } catch (e, st) {
                // El error real a la consola, mismo criterio que el resto de las acciones de esta
                // pantalla -- acá importa más que en ninguna otra: antes de este fix, un borrado
                // sin permiso ni siquiera caía en este catch (eliminarObra no lo detectaba),
                // mostraba éxito falso y sacaba la obra de la lista igual. Ver
                // ObrasRepository.eliminarObra.
                debugPrint('_confirmarEliminar: falló: $e\n$st');
                if (!mounted || !ctx.mounted) return;
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      e is StateError ? e.message : 'No se pudo eliminar la obra. Intente nuevamente.',
                    ),
                  ),
                );
              }
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // --- Menú: Imprimir / Exportar ---
  void _abrirMenuExportar(Map<String, dynamic> obra) {
    final bool tieneCertificado = obra['estado'] != 'Cotización';
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Imprimir / Exportar', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1B365D))),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.request_quote_outlined, color: Color(0xFF1B365D)),
              title: const Text('Presupuesto', style: TextStyle(fontSize: 13)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmarExportacion(obra, 'Presupuesto');
              },
            ),
            if (tieneCertificado)
              ListTile(
                leading: const Icon(Icons.verified_outlined, color: Color(0xFF1B365D)),
                title: const Text('Certificado', style: TextStyle(fontSize: 13)),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmarExportacion(obra, 'Certificado');
                },
              ),
            ListTile(
              leading: const Icon(Icons.summarize_outlined, color: Color(0xFF1B365D)),
              title: const Text('Resumen general', style: TextStyle(fontSize: 13)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmarExportacion(obra, 'Resumen general');
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // --- Diálogo: Confirmar Exportación (marca de agua Free/Pro) ---
  void _confirmarExportacion(Map<String, dynamic> obra, String tipoDocumento) {
    bool marcaAguaActiva = true;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: Row(
              children: [
                const Icon(Icons.picture_as_pdf_outlined, color: Color(0xFF1B365D)),
                const SizedBox(width: 8),
                Expanded(child: Text('Exportar $tipoDocumento', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Obra: ${obra['nombre']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 12),
                if (_esPlanPro)
                  SwitchListTile(
                    title: const Text('Incluir marca de agua', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    subtitle: const Text('Versión PRO: marca discreta y chica, opcional.', style: TextStyle(fontSize: 10, color: Colors.black54)),
                    value: marcaAguaActiva,
                    activeTrackColor: const Color(0xFF1B365D),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) => setDialogState(() => marcaAguaActiva = val),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.amber[50], borderRadius: BorderRadius.circular(6)),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.lock_outline, size: 16, color: Colors.amber),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Versión FREE: la exportación incluye marca de agua visible "ComputoPRO". La versión PRO permite una marca discreta o desactivarla.',
                            style: TextStyle(fontSize: 10, color: Colors.black87),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B365D)),
                onPressed: () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Generando $tipoDocumento...')),
                  );
                },
                child: const Text('Exportar', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Fondo del listado, en dos pasos y los dos mirados en el emulador por Seba: `F4F6F9` original
      // -> `E9EDF2` (todavía justo) -> `E2E7EE`. Contra un gris casi blanco, una tarjeta blanca no se
      // distingue y toda la lista se lee como una sola superficie; con este gris el blanco de la
      // tarjeta se lee como blanco y el límite entre obras aparece solo.
      //
      // Es el tope de lo que conviene oscurecer por acá: más abajo (D8DEE7 y siguientes) la pantalla
      // empieza a verse gris y pesada, y el contraste hay que buscarlo en el canto de la tarjeta, no
      // en el fondo -- ver el criterio de docs/criterio_pantalla_principal_vs_resumen.md §5.4.
      backgroundColor: const Color(0xFFE2E7EE),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B365D),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'MIS OBRAS',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2, fontSize: 18, color: Colors.white),
        ),
        actions: [
          // Un solo ícono para las dos acciones secundarias (mapa, ingresar código) -- ajuste de
          // interfaz sobre la primera versión (feedback de Seba, 2026-09-10): el ícono de
          // invitación como botón propio dejaba 4 acciones en la fila y tapaba el indicador
          // Free/PRO, que tiene que quedar siempre visible. Con esto la fila vuelve a las 3
          // acciones de antes (menú, indicador, cerrar sesión).
          PopupMenuButton<VoidCallback>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            tooltip: 'Más opciones',
            onSelected: (accion) => accion(),
            itemBuilder: (context) => [
              PopupMenuItem<VoidCallback>(
                value: _mostrarMapaObras,
                child: const Row(
                  children: [
                    Icon(Icons.map_outlined, size: 18, color: Color(0xFF1B365D)),
                    SizedBox(width: 10),
                    Text('Ver obras en mapa'),
                  ],
                ),
              ),
              PopupMenuItem<VoidCallback>(
                value: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AceptarInvitacionScreen()),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.key_outlined, size: 18, color: Color(0xFF1B365D)),
                    SizedBox(width: 10),
                    Text('Ingresar código de invitación'),
                  ],
                ),
              ),
              PopupMenuItem<VoidCallback>(
                value: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const EditarPerfilScreen()),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.person_outline, size: 18, color: Color(0xFF1B365D)),
                    SizedBox(width: 10),
                    Text('Mi perfil'),
                  ],
                ),
              ),
            ],
          ),
          InkWell(
            onTap: _mostrarModalPro,
            child: Container(
              margin: const EdgeInsets.only(right: 12, top: 12, bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _esPlanPro ? Colors.amber[700] : const Color(0xFF3A5A80),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber, width: 1),
              ),
              child: Row(
                children: [
                  Icon(Icons.workspace_premium, color: _esPlanPro ? Colors.white : Colors.amber, size: 14),
                  const SizedBox(width: 4),
                  Text(_esPlanPro ? 'PRO' : 'FREE', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            tooltip: 'Cerrar sesión',
            onPressed: () => _authService.cerrarSesion(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Banner Informativo de Indicadores Económicos
          Container(
            width: double.infinity,
            color: const Color(0xFF1B365D),
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12, top: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Expanded para que ceda ancho al bloque de la fecha en
                  // pantallas angostas (antes ninguno de los dos lados podía
                  // achicarse, y la suma de sus anchos naturales desbordaba
                  // en equipos más chicos que el emulador de referencia).
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'USD Ref. BNA: \$${_cotizacionUsdEfectiva.toStringAsFixed(2)}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'CAC Último Mes: +$_variacionCacUltimoMes%',
                          style: const TextStyle(color: Colors.white70, fontSize: 10),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Row(
                    children: [
                      const Icon(Icons.refresh, color: Colors.white70, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        _fechaActualizacionDolar,
                        style: const TextStyle(color: Colors.white70, fontSize: 10),
                      ),
                    ],
                  )
                ],
              ),
            ),
          ),

          // Lo que espera la acción del usuario (0117) -- al abrir la app, sin tener que entrar a
          // cada obra (docs/avisos_pendientes_diseno.md). Nada si no hay pendientes.
          if (!_cargando && _pendientes.isNotEmpty)
            CartelPendientes(pendientes: _pendientes, onAbrir: _abrirPendiente),

          // Lista de Tarjetas de Obra
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!, style: const TextStyle(color: Colors.black54)),
                            const SizedBox(height: 8),
                            TextButton(onPressed: _cargarObras, child: const Text('Reintentar')),
                          ],
                        ),
                      )
                    : _obras.isEmpty
                ? const Center(child: Text('No hay obras registradas. Presione "+" para agregar una.'))
                : ListView.builder(
                    // Padding inferior extra para que "NUEVA OBRA" (FAB)
                    // no tape la última tarjeta — antes solo tenía el
                    // padding parejo de 12 en los 4 lados.
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                    itemCount: _obras.length,
                    itemBuilder: (context, index) {
                      final obra = _obras[index];
                      final bool esCotizacion = obra['estado'] == 'Cotización';
                      final bool esArs = obra['moneda'] == 'ARS';
                      final double montoVivo = esArs ? obra['montoEstimadoArs'] : obra['montoEstimadoUsd'];
                      final bool esCongelada = obra['presupuestoCongeladoEn'] != null;
                      final double? montoPactado =
                          esArs ? obra['montoPactadoArs'] as double? : obra['montoPactadoUsd'] as double?;
                      final double? montoHoyConfigCongelada = esArs
                          ? obra['montoHoyConfigCongeladaArs'] as double?
                          : obra['montoHoyConfigCongeladaUsd'] as double?;
                      // Una vez pactado, el número de la obra ES el pactado -- criterio de Seba
                      // (2026-09-12): los interruptores de la Solapa APU no pueden seguir moviendo
                      // el precio de una obra ya firmada. Si el pactado no pudo cargarse (fallo de
                      // red puntual), cae al vivo con su aclaración de siempre -- fallback, no el
                      // caso normal.
                      final bool mostrarPactado = esCongelada && montoPactado != null;
                      final double monto = (esCongelada && montoPactado != null) ? montoPactado : montoVivo;
                      final bool tieneCac = obra['aplicaCac'] ?? false;
                      // Un renglón por adicional aprobado (§10.2): la card los lista, no los agrupa.
                      final List<_AdicionalAprobadoCard> adicionales =
                          (obra['adicionalesAprobados'] as List<_AdicionalAprobadoCard>?) ?? const [];
                      final int pendientesDeObra = _pendientes.where((p) => p.obraId == obra['id']).length;
                      // Los montos ya vienen convertidos a las dos monedas (_conMontosCalculados);
                      // acá solo se elige cuál mostrar, igual que con el pactado y el estimado.
                      double montoAdicional(_AdicionalAprobadoCard a) => esArs ? a.montoArs : a.montoUsd;
                      final double montoAdicionales = adicionales.fold(0.0, (t, a) => t + montoAdicional(a));
                      // Si hay más de los que entran en una portada, los primeros van uno por uno y el
                      // resto se agrupa en un solo renglón -- ver _maxAdicionalesEnCard.
                      final List<_AdicionalAprobadoCard> adicionalesVisibles =
                          adicionales.take(_maxAdicionalesEnCard).toList();
                      final List<_AdicionalAprobadoCard> adicionalesAgrupados =
                          adicionales.skip(_maxAdicionalesEnCard).toList();
                      final double montoAgrupados =
                          adicionalesAgrupados.fold(0.0, (t, a) => t + montoAdicional(a));
                      final String estadoServicio = obra['estadoServicioEspecial'] ?? 'Ninguno';

                      // Separación entre tarjetas (Seba, 2026-09-13): con los renglones de montos y
                      // las barras, la lista se leía como un bloque continuo y no se veía dónde
                      // terminaba una obra y empezaba la otra. Cuatro cambios chicos, ningún elemento
                      // nuevo -- la portada tiene que seguir limpia:
                      //
                      //   1. `margin` de 12 a 18: el aire es lo que agrupa. Una tarjeta alta con poco
                      //      espacio alrededor se pega a la de al lado por más borde que tenga.
                      //   2. Borde de 1px (`side`): un canto definido que no depende de la sombra.
                      //      Es lo que hace que el límite se vea también en pantallas con poco
                      //      contraste o con brillo alto al sol, que es donde se usa esta app.
                      //   3. Sombra más marcada (`elevation` 3 + `shadowColor`), para que la tarjeta
                      //      se despegue del fondo en vez de ser un rectángulo dibujado sobre él.
                      //   4. `surfaceTintColor` transparente: Material 3 tiñe de color primario las
                      //      superficies elevadas, y ese tinte acercaba el blanco de la tarjeta al
                      //      gris del fondo -- justo al revés de lo que hace falta acá.
                      //
                      // El fondo de la pantalla también se oscureció un punto (ver el `Scaffold`).
                      return Card(
                        margin: const EdgeInsets.only(bottom: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Colors.black12),
                        ),
                        elevation: 3,
                        shadowColor: Colors.black.withValues(alpha: 0.28),
                        surfaceTintColor: Colors.transparent,
                        child: InkWell(
                          onTap: () => _abrirPresupuesto(obra),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Cabecera: Nombre + Editar + Estado
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        obra['nombre'],
                                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1B365D)),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    // Lápiz acá, no un cuarto ícono en el pie
                                    // de la tarjeta (ya tiene 3, apretados
                                    // contra "Última Modif" — ver memoria de
                                    // overflow en pantalla angosta). Editar
                                    // el nombre es lo que el usuario está
                                    // mirando cuando lo quiere corregir.
                                    //
                                    // Gateado por dueño, mismo criterio que "Ajuste Económico" y
                                    // "Eliminar" (2026-09-11): la RLS de UPDATE sobre `obras` es
                                    // la misma para los 3 -- si no puede, que no aparezca.
                                    if (_esAdminDeObra(obra))
                                      IconButton(
                                        icon: const Icon(Icons.edit_outlined, size: 16, color: Colors.black45),
                                        tooltip: 'Editar Obra',
                                        constraints: const BoxConstraints(),
                                        padding: const EdgeInsets.symmetric(horizontal: 6),
                                        onPressed: () => _mostrarModalEditarObra(obra),
                                      ),
                                    // Cuántas cosas de esta obra esperan al usuario (0117) -- para
                                    // ubicar dónde está lo que anuncia el cartel de arriba. El nombre
                                    // es el que cede ancho (Expanded + ellipsis), esto es chico y fijo.
                                    if (pendientesDeObra > 0) ...[
                                      Tooltip(
                                        // Mismo criterio de tono que el cartel (ver `Pendiente`).
                                        message: pendientesDeObra == 1
                                            ? '1 acción requerida'
                                            : '$pendientesDeObra acciones requeridas',
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: Colors.amber.shade100,
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.notifications_active_outlined, size: 12, color: Colors.amber.shade900),
                                              const SizedBox(width: 2),
                                              Text(
                                                '$pendientesDeObra',
                                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                    ],
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: esCotizacion ? Colors.blue[50] : Colors.green[50],
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        obra['estado'],
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: esCotizacion ? Colors.blue[800] : Colors.green[800],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),

                                // Identificación de la obra: propietario, ubicación y **m²**.
                                //
                                // Los m² entraron acá el 2026-09-13 (pedido de Seba): antes eran un
                                // chip grande abajo, entre los montos, y son un dato de identidad
                                // como el nombre -- "no un número más entre los montos". Pierden la
                                // presencia de los 15px que tenían como chip, a cambio de leerse
                                // junto con lo que identifica la obra.
                                //
                                // `Wrap` y no `Row`: con tres datos de ancho variable, un `Row` no
                                // baja de línea y desborda con fuente grande o pantalla angosta --
                                // la misma lección que ya dejó la barra de acciones de Gestión de
                                // Obra y el chip de m² cuando compartía renglón con el de CAC.
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 2,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    _buildDatoIdentidad(Icons.person_outline, obra['propietario']),
                                    _buildDatoIdentidad(Icons.location_on_outlined, obra['ubicacion']),
                                    _buildDatoIdentidad(
                                      Icons.square_foot_outlined,
                                      '${obra['superficieM2']} m²',
                                      destacado: true,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),

                                // Monto Base, y debajo (línea propia, no
                                // compartiendo renglón) los chips m² / CAC.
                                // Antes competían por ancho en el mismo Row
                                // sin que ninguno pudiera ceder — al agrandar
                                // el chip de m² (pedido de otra sesión) dejó
                                // de entrar en pantallas angostas y el chip
                                // CAC se pintaba fuera del borde visible.
                                // Separarlos en líneas evita la competencia
                                // de raíz, sin achicar el chip.
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Los montos cerrados de una obra firmada -- el pactado y CADA
                                    // adicional aprobado -- van con el MISMO tratamiento visual
                                    // (criterio de Seba, 2026-09-13): todos están congelados y
                                    // firmados, ninguno es una estimación, así que ninguno puede
                                    // aparecer agrupado ni escondido dentro de una suma. Debajo, el
                                    // total, y un vínculo a Resumen para el detalle.
                                    //
                                    // Nada de certificados ni avance acá: la portada es panorámica,
                                    // el análisis es de Resumen (docs/criterio_pantalla_principal_vs_
                                    // resumen.md).
                                    if (mostrarPactado && adicionales.isNotEmpty) ...[
                                      _buildMontoCerrado('Presupuesto Pactado', monto, obra['moneda']),
                                      // Cada monto con su propio avance debajo: el del contrato acá, y
                                      // el de cada adicional pegado al suyo. Así la card muestra cómo
                                      // corre la obra completa, no solo el contrato.
                                      if (obra['avancePct'] != null)
                                        _buildBarraAvance(obra['avancePct'] as double),
                                      for (final a in adicionalesVisibles) ...[
                                        const SizedBox(height: 4),
                                        _buildMontoCerrado(_rotuloAdicional(a), montoAdicional(a), obra['moneda']),
                                        // Seguimiento propio del adicional (0120). Siempre, incluso en
                                        // 0: un aprobado sin certificar es información, no un hueco.
                                        _buildBarraAvance(a.avancePct),
                                      ],
                                      // El resto, en un solo renglón: la portada no crece sin límite,
                                      // pero el total sigue cerrando exacto y nada queda sin sumar.
                                      // El renglón agrupado NO lleva barra: son varios adicionales con
                                      // avances distintos y una barra promedio sería un número que no
                                      // le corresponde a ninguno. El detalle de esos está en Resumen.
                                      if (adicionalesAgrupados.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        _buildMontoCerrado(
                                          'Otros ${adicionalesAgrupados.length} adicionales aprobados',
                                          montoAgrupados,
                                          obra['moneda'],
                                        ),
                                      ],
                                      const Padding(
                                        padding: EdgeInsets.symmetric(vertical: 4),
                                        child: Divider(height: 1, thickness: 1, color: Colors.black12),
                                      ),
                                      _buildMontoCerrado(
                                        'Total',
                                        monto + montoAdicionales,
                                        obra['moneda'],
                                        conCandado: false,
                                      ),
                                    ] else ...[
                                      // Un solo número grande (sin adicionales aprobados, u obra sin
                                      // congelar): el de siempre, con el rótulo arriba. El pactado se
                                      // muestra SIN aclaración que lo relativice -- una vez firmado,
                                      // ese es el precio de la obra, no una estimación (criterio de
                                      // Seba, 2026-09-12). Solo si el pactado no pudo cargarse
                                      // (fallback) se avisa que lo que se ve es el vivo, no el firmado.
                                      Row(
                                        children: [
                                          if (mostrarPactado) ...[
                                            const Icon(Icons.lock_outline, size: 10, color: Colors.black45),
                                            const SizedBox(width: 3),
                                          ],
                                          Text(
                                            mostrarPactado
                                                ? 'Presupuesto Pactado'
                                                : (esCongelada
                                                    ? 'Valor de HOY (pactado no disponible)'
                                                    : 'Monto Estimado Base'),
                                            style: const TextStyle(fontSize: 9, color: Colors.black45, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _formatearMonto(monto, obra['moneda']),
                                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF1B365D)),
                                      ),
                                      // Sin candado en este renglón, así que la barra tampoco lleva
                                      // sangría: arranca alineada con el número.
                                      if (obra['avancePct'] != null)
                                        _buildBarraAvance(obra['avancePct'] as double, sangria: 0),
                                      // Obra sin congelar: los adicionales aprobados se listan igual,
                                      // uno por uno y con su candado (están firmados), pero SIN total
                                      // -- no se suman a un estimado que todavía se mueve.
                                      for (final a in adicionalesVisibles) ...[
                                        const SizedBox(height: 4),
                                        _buildMontoCerrado(_rotuloAdicional(a), montoAdicional(a), obra['moneda']),
                                        _buildBarraAvance(a.avancePct),
                                      ],
                                      if (adicionalesAgrupados.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        _buildMontoCerrado(
                                          'Otros ${adicionalesAgrupados.length} adicionales aprobados',
                                          montoAgrupados,
                                          obra['moneda'],
                                        ),
                                      ],
                                    ],
                                    // "Ver más" de esta pieza: el detalle de cada adicional (qué
                                    // incluye, certificado, saldo) vive en Resumen, no en la portada.
                                    if (adicionales.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      _buildVinculoResumen(obra),
                                    ],
                                    if (mostrarPactado && montoHoyConfigCongelada != null) ...[
                                      const SizedBox(height: 6),
                                      _buildComparacionCongelada(
                                        obra['id'] as String,
                                        montoHoyConfigCongelada,
                                        obra['montoHoyConfigCongeladaArs'] as double,
                                        obra['montoPactadoArs'] as double,
                                        obra['moneda'],
                                      ),
                                    ],
                                    // Los m² se fueron al renglón de identificación de arriba; acá
                                    // queda solo el CAC, que no es identidad de la obra sino una
                                    // condición del contrato, y por eso vive con los montos.
                                    if (tieneCac) ...[
                                      const SizedBox(height: 8),
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF1B365D),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: const Text(
                                            'CAC',
                                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),

                                const SizedBox(height: 12),
                                const Divider(height: 1),
                                const SizedBox(height: 8),

                                // Pie de Tarjeta: Info de Modificación + Botones de Acción
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Última Modif: ${obra['ultimaModif']} • ${obra['revision']}',
                                        style: const TextStyle(fontSize: 10, color: Colors.black38),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        // Gateado por dueño -- confirmado por Seba (2026-09-11):
                                        // un invitado profesional (no admin_maestro, no el
                                        // creador) que intenta esto choca con la RLS de `obras`
                                        // (`0051`) y es correcto que choque. Antes se mostraba
                                        // igual y fallaba al guardar -- "mejor que no aparezca a
                                        // que aparezca y falle". `idAdminCreador == auth.uid()` es
                                        // una aproximación, no la regla exacta de la RLS (que
                                        // también deja pasar a un `admin_maestro` que no sea el
                                        // creador original) -- mismo criterio ya aceptado en
                                        // otras partes del proyecto (obra_config_certificacion_repository.dart):
                                        // subestimar quién puede editar es un fallo seguro, nunca
                                        // al revés.
                                        if (_esAdminDeObra(obra))
                                          IconButton(
                                            constraints: const BoxConstraints(),
                                            padding: const EdgeInsets.symmetric(horizontal: 6),
                                            icon: const Icon(Icons.tune, size: 18, color: Color(0xFF1B365D)),
                                            tooltip: 'Ajuste Económico / Moneda',
                                            onPressed: () => _configurarAjusteEconomico(obra),
                                          ),
                                        IconButton(
                                          constraints: const BoxConstraints(),
                                          padding: const EdgeInsets.symmetric(horizontal: 6),
                                          icon: const Icon(Icons.ios_share, size: 18, color: Color(0xFF1B365D)),
                                          tooltip: 'Imprimir / Exportar',
                                          onPressed: () => _abrirMenuExportar(obra),
                                        ),
                                        // Gateado por dueño (2026-09-11) -- el más importante de
                                        // los 3: sin esto, alguien sin permiso podía confirmar el
                                        // borrado y ver "Obra eliminada del registro" (éxito
                                        // falso, ObrasRepository.eliminarObra no detectaba el
                                        // rechazo de RLS) sin saber si de verdad se borró o no.
                                        if (_esAdminDeObra(obra))
                                          IconButton(
                                            constraints: const BoxConstraints(),
                                            padding: const EdgeInsets.symmetric(horizontal: 6),
                                            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                                            tooltip: 'Eliminar Obra',
                                            onPressed: () => _confirmarEliminar(obra),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 8),

                                // Banner Inferior Integrado: Solicitud de Cómputo / Legajo
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: estadoServicio == 'En Revision' ? Colors.amber[50] : const Color(0xFFEFF3F8),
                                    borderRadius: BorderRadius.circular(6),
                                    border: estadoServicio == 'En Revision' ? Border.all(color: Colors.amber[300]!) : null,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      // Expanded: mismo criterio que el banner superior y la
                                      // fila propietario/ubicación — el label es el texto largo
                                      // y variable, "Solicitar"/"Ver Solicitud" es corto y fijo,
                                      // así que es el label el que tiene que ceder.
                                      Expanded(
                                        child: Row(
                                          children: [
                                            Icon(
                                              estadoServicio == 'En Revision' ? Icons.hourglass_top : Icons.engineering_outlined,
                                              size: 14,
                                              color: estadoServicio == 'En Revision' ? Colors.amber[900] : const Color(0xFF1B365D),
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                estadoServicio == 'En Revision'
                                                    ? 'Estudio Técnico en Revisión'
                                                    : '¿Necesitás Cómputo / IRAM / Legajo?',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w600,
                                                  color: estadoServicio == 'En Revision' ? Colors.amber[900] : const Color(0xFF1B365D),
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                                maxLines: 1,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      InkWell(
                                        onTap: () => _abrirModalServiciosEspeciales(obra),
                                        child: Text(
                                          estadoServicio == 'En Revision' ? 'Ver Solicitud' : 'Solicitar',
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF1B365D),
                                            decoration: TextDecoration.underline,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _mostrarModalNuevaObra,
        backgroundColor: const Color(0xFF1B365D),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('NUEVA OBRA', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.8, color: Colors.white)),
      ),
    );
  }
}