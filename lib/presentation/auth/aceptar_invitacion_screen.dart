import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/models/invitacion.dart';
import '../../services/auth_service.dart';
import '../../services/invitaciones_repository.dart';

/// Pegar/tipear el código de invitación de 8 caracteres — ver
/// `docs/invitaciones_diseno_datos.md` §5/§7. Reachable desde `LoginScreen` (sin sesión) y desde
/// `ObrasListScreen` (ya logueado, invitado a la obra de otra persona).
///
/// Sin sesión: guarda el código en `SharedPreferences` (`InvitacionPendiente`) y explica que se
/// aplica solo al iniciar sesión -- no puede canjearlo acá porque `aceptar_invitacion` necesita
/// `auth.uid()`. Con sesión: canjea directo.
class AceptarInvitacionScreen extends StatefulWidget {
  const AceptarInvitacionScreen({super.key});

  @override
  State<AceptarInvitacionScreen> createState() => _AceptarInvitacionScreenState();
}

class _AceptarInvitacionScreenState extends State<AceptarInvitacionScreen> {
  final _authService = AuthService();
  final _repositorio = InvitacionesRepository();
  final _codigoCtrl = TextEditingController();

  bool _cargando = false;
  String? _error;

  @override
  void dispose() {
    _codigoCtrl.dispose();
    super.dispose();
  }

  Future<void> _continuar() async {
    // Sin espacios ni minúsculas -- el alfabeto de generar_codigo_invitacion es todo mayúsculas,
    // pero quien pega desde WhatsApp puede traer espacios alrededor sin darse cuenta.
    final codigo = _codigoCtrl.text.trim().toUpperCase().replaceAll(' ', '');
    if (codigo.length != 8) {
      setState(() => _error = 'El código tiene 8 caracteres.');
      return;
    }

    setState(() {
      _cargando = true;
      _error = null;
    });

    if (_authService.usuarioActual == null) {
      await InvitacionPendiente.guardar(codigo);
      if (!mounted) return;
      setState(() => _cargando = false);
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Código guardado'),
          content: const Text(
            'Iniciá sesión o registrate para sumarte a la obra. En cuanto entres, se aplica solo.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido')),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      return;
    }

    try {
      final resultado = await _repositorio.aceptarInvitacion(codigo);
      if (!mounted) return;
      setState(() => _cargando = false);
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Listo'),
          content: Text('Te sumaste a la obra "${resultado.obraNombre}" como ${etiquetaRol(resultado.rol)}.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido')),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo canjear el código. Intentá de nuevo.';
        _cargando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B365D),
        title: const Text('Ingresar código de invitación', style: TextStyle(color: Colors.white, fontSize: 15)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Pegá el código que te compartieron por WhatsApp.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _codigoCtrl,
                  textAlign: TextAlign.center,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [LengthLimitingTextInputFormatter(8)],
                  style: const TextStyle(fontSize: 22, letterSpacing: 3, fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    hintText: 'QJWNR74V',
                  ),
                  onSubmitted: (_) => _continuar(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Colors.red[700], fontSize: 12, fontWeight: FontWeight.w600)),
                ],
                const SizedBox(height: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1B365D),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _cargando ? null : _continuar,
                  child: _cargando
                      ? const SizedBox(
                          width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Continuar', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
