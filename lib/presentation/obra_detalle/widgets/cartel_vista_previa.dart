import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../services/auth_service.dart';
import '../../../services/perfil_repository.dart';

/// El cartel que explica por qué una solapa está mostrando el catálogo atenuado en vez de los datos
/// de esta obra. Se descarta y no vuelve.
///
/// ---------------------------------------------------------------- qué NO hace, y por qué importa
///
/// **No envuelve ni atenúa nada.** La versión anterior era un `VistaPreviaAtenuada` que recibía la
/// pantalla entera y le aplicaba `Opacity` + `IgnorePointer`. Seba lo probó y encontró el problema:
///
/// > *"Quedaron frías, no se pueden recorrer. El IgnorePointer bloquea todo el toque, incluido el
/// > deslizar, así que veo la primera pantalla y no puedo bajar. Y la gracia es justamente poder
/// > recorrer el catálogo para ver qué trae la app."*
///
/// **`IgnorePointer` no distingue entre editar y desplazar**: bloquea el gesto, y el scroll es un
/// gesto. Atenuar una pantalla para mostrarla y de paso impedir que se la recorra es peor que no
/// mostrarla -- se ve la primera pantalla de un catálogo de 174 insumos y ahí termina.
///
/// **La regla que queda: se bloquea la edición, no el desplazamiento.** Y la edición se bloquea
/// donde vive —el `onTap` de cada control, con el flag de vitrina de cada solapa— no con una manta
/// por encima de todo. Cada solapa atenúa con `Opacity` lo que es muestra y deja en color lo que sí
/// funciona: en Mat y MO el bloque de costo de mano de obra es dato real de la obra y se edita
/// aunque no haya un solo insumo cargado.
///
/// ---------------------------------------------------------------- descartable
///
/// Mismo mecanismo que `CartelAvisoLegalLibro` y el aviso de zona UOCRA: `SharedPreferences`, por
/// obra y por dispositivo, con el default en "visible" hasta que la lectura resuelva. `scope`
/// separa APU de Mat y MO -- son dos explicaciones distintas y cerrar una no tiene por qué cerrar
/// la otra.
class CartelVistaPrevia extends StatefulWidget {
  final String obraId;

  /// `'apu'` o `'mat_y_mo'`. Entra en la clave de SharedPreferences.
  final String scope;

  /// Qué hay debajo y qué pasa cuando el usuario tilde una partida. Dicho para esta solapa: cada una
  /// muestra su propia materia prima, no la de la de al lado.
  final String mensaje;

  /// Segunda línea: el tamaño de lo que se está mostrando. Cada solapa lo calcula con sus datos.
  final String? detalle;

  /// Línea extra, solo para un usuario Free.
  final String notaPro;

  const CartelVistaPrevia({
    Key? key,
    required this.obraId,
    required this.scope,
    required this.mensaje,
    required this.notaPro,
    this.detalle,
  }) : super(key: key);

  static String claveDescartado(String scope, String obraId) => 'vista_previa_${scope}_$obraId';

  @override
  State<CartelVistaPrevia> createState() => _CartelVistaPreviaState();
}

class _CartelVistaPreviaState extends State<CartelVistaPrevia> {
  final PerfilRepository _perfilRepository = PerfilRepository();
  final AuthService _authService = AuthService();

  bool _descartado = false;

  // Fail-safe a PRO: sin el dato no se muestra la nota. Es una etiqueta, no un gate -- el gate real
  // se verifica en vivo al guardar (ver panel_valor_hora_mano_obra.dart, donde un `esPro` viejo
  // pasado por parámetro fue un bug real). Lo peor que pasa acá si se equivoca es que falte una
  // línea informativa.
  bool _esPro = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final descartado =
          prefs.getBool(CartelVistaPrevia.claveDescartado(widget.scope, widget.obraId)) ?? false;
      final usuarioId = _authService.usuarioActual?.id;
      final esPro = usuarioId == null ? true : await _perfilRepository.esPro(usuarioId);
      if (!mounted) return;
      setState(() {
        _descartado = descartado;
        _esPro = esPro;
      });
    } catch (_) {
      // Sin rama de error: la solapa ya está mostrando lo que tiene que mostrar.
    }
  }

  Future<void> _descartar() async {
    setState(() => _descartado = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(CartelVistaPrevia.claveDescartado(widget.scope, widget.obraId), true);
    } catch (_) {
      // Si no se pudo guardar, vuelve la próxima vez. Molesta menos que un error por un cartel.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_descartado) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: Colors.amber[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber[200]!),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.auto_awesome_outlined, size: 18, color: Colors.amber[800]),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.mensaje,
                  style: const TextStyle(fontSize: 12, color: Colors.black87, height: 1.35),
                ),
                if (widget.detalle != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    widget.detalle!,
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ],
                if (!_esPro) ...[
                  const SizedBox(height: 6),
                  Text(
                    widget.notaPro,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.amber[900],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // `constraints` + `padding` en cero: el default de IconButton reserva 48x48 y en un cartel
          // de dos renglones eso lo estira de más.
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            color: Colors.amber[900],
            tooltip: 'Entendido',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            padding: EdgeInsets.zero,
            onPressed: _descartar,
          ),
        ],
      ),
    );
  }
}
