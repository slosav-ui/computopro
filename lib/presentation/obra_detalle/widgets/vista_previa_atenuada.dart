import 'package:flutter/material.dart';
import '../../../services/auth_service.dart';
import '../../../services/perfil_repository.dart';

/// Un cartel arriba y **la pantalla real atenuada** debajo: lo que muestran APU y Mat y MO cuando
/// esta obra todavía no tiene nada propio que mostrar.
///
/// ---------------------------------------------------------------- por qué no es una vitrina aparte
///
/// La versión anterior dibujaba tarjetas grises propias, con su layout, su tipografía y su forma de
/// listar. Seba lo corrigió el 2026-09-15: *"la pantalla real atenuada, no una vitrina aparte"*.
///
/// La diferencia importa por dos motivos, y ninguno es estético:
///
///  1. **Lo que se ve es lo que va a haber.** Una vitrina con diseño propio muestra una aproximación
///     de la pantalla; la pantalla atenuada muestra la pantalla. Cuando el usuario tilda su primera
///     partida, lo que aparece es exactamente lo que estaba viendo, ahora en color y tocable.
///  2. **No hay un segundo layout que mantener.** Un diseño paralelo se desactualiza solo: el día
///     que la fila real gana una columna, la vitrina se queda vieja y nadie se entera hasta que
///     alguien mira la pantalla vacía, que es justamente la que nadie mira.
///
/// Por eso este widget **no dibuja contenido**: recibe el árbol real de la solapa como `child` y
/// solo lo envuelve.
///
/// ---------------------------------------------------------------- las dos capas del envoltorio
///
/// `Opacity` para que se lea como inactivo, e `IgnorePointer` para que no responda. Las dos, no una:
/// atenuar sin bloquear deja botones grises que se pueden tocar y no hacen nada, y bloquear sin
/// atenuar deja una pantalla que parece activa y no responde. Cualquiera de las dos sola se lee como
/// una pantalla rota, que es de lo que veníamos escapando.
class VistaPreviaAtenuada extends StatefulWidget {
  /// Qué hay debajo y qué pasa cuando el usuario tilde una partida. Dicho para esta solapa: cada una
  /// muestra su propia materia prima, no la de la de al lado.
  final String mensaje;

  /// Línea extra, solo para un usuario Free. A un PRO decirle que algo es PRO es ruido.
  final String notaPro;

  /// Segunda línea del cartel, opcional: el tamaño de lo que se está mostrando ("174 materiales con
  /// precio de corralón"). Va aparte del mensaje porque cada solapa lo calcula con sus propios datos.
  final String? detalle;

  /// **El árbol real de la solapa**, con datos del catálogo en vez de los de la obra.
  final Widget child;

  const VistaPreviaAtenuada({
    Key? key,
    required this.mensaje,
    required this.notaPro,
    required this.child,
    this.detalle,
  }) : super(key: key);

  @override
  State<VistaPreviaAtenuada> createState() => _VistaPreviaAtenuadaState();
}

class _VistaPreviaAtenuadaState extends State<VistaPreviaAtenuada> {
  final PerfilRepository _perfilRepository = PerfilRepository();
  final AuthService _authService = AuthService();

  // Fail-safe a PRO: sin el dato no se muestra la nota. Es una etiqueta, no un gate -- el gate real
  // de PRO se verifica en vivo en el momento de guardar (ver panel_valor_hora_mano_obra.dart, donde
  // un `esPro` viejo pasado por parámetro fue un bug real). Acá lo peor que pasa si se equivoca es
  // que falte una línea informativa.
  bool _esPro = true;

  @override
  void initState() {
    super.initState();
    _cargarEsPro();
  }

  Future<void> _cargarEsPro() async {
    final usuarioId = _authService.usuarioActual?.id;
    if (usuarioId == null) return;
    try {
      final esPro = await _perfilRepository.esPro(usuarioId);
      if (mounted) setState(() => _esPro = esPro);
    } catch (_) {
      // Sin rama de error: la pantalla ya está mostrando lo que tiene que mostrar.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: _buildCartel(),
        ),
        Expanded(
          child: Opacity(
            opacity: 0.55,
            child: IgnorePointer(child: widget.child),
          ),
        ),
      ],
    );
  }

  /// Ámbar suave y no un cartel de error: no hay nada roto ni nada que corregir. Es una invitación,
  /// y el tono de la UI es informativo, nunca de reproche.
  Widget _buildCartel() {
    return Container(
      padding: const EdgeInsets.all(12),
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
        ],
      ),
    );
  }
}
