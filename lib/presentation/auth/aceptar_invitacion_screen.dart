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
/// Dos pasos, no uno: primero se previsualiza el código (`previsualizar_invitacion`, de solo
/// lectura, funciona sin sesión) para mostrar a qué obra y con qué rol se va a sumar la persona
/// ANTES de guardar nada o canjear -- ajuste sobre la primera versión, que guardaba el código
/// pendiente a ciegas y dejaba una pantalla neutra sin explicar qué seguía (feedback de Seba al
/// probar el circuito).
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

  // No nulo == ya se encontró un código válido y se está mostrando el paso de confirmación.
  String? _codigoConfirmado;
  VistaPreviaInvitacion? _vistaPrevia;

  @override
  void dispose() {
    _codigoCtrl.dispose();
    super.dispose();
  }

  String _normalizarCodigo() =>
      _codigoCtrl.text.trim().toUpperCase().replaceAll(' ', '');

  Future<void> _buscarCodigo() async {
    final codigo = _normalizarCodigo();
    if (codigo.length != 8) {
      setState(() => _error = 'El código tiene 8 caracteres.');
      return;
    }

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final vista = await _repositorio.previsualizarInvitacion(codigo);
      if (!mounted) return;
      if (vista == null) {
        setState(() {
          _error = 'Código inválido o vencido.';
          _cargando = false;
        });
        return;
      }
      setState(() {
        _vistaPrevia = vista;
        _codigoConfirmado = codigo;
        _cargando = false;
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo buscar el código. Intentá de nuevo.';
        _cargando = false;
      });
    }
  }

  void _cancelarConfirmacion() {
    setState(() {
      _codigoConfirmado = null;
      _vistaPrevia = null;
      _error = null;
    });
  }

  Future<void> _confirmar() async {
    final codigo = _codigoConfirmado;
    if (codigo == null) return;

    setState(() {
      _cargando = true;
      _error = null;
    });

    if (_authService.usuarioActual == null) {
      // Recién acá se guarda -- ya se sabe que el código es válido, no se guarda a ciegas como en
      // la primera versión. AceptarInvitacionScreen se abrió desde LoginScreen en este caso, así
      // que un pop simple alcanza para volver ahí (no hace falta pushear una LoginScreen nueva).
      await InvitacionPendiente.guardar(codigo);
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
            child: _vistaPrevia != null ? _buildConfirmacion(_vistaPrevia!) : _buildIngresarCodigo(),
          ),
        ),
      ),
    );
  }

  Widget _buildIngresarCodigo() {
    return Column(
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
          onSubmitted: (_) => _buscarCodigo(),
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
          onPressed: _cargando ? null : _buscarCodigo,
          child: _cargando
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Continuar', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  Widget _buildConfirmacion(VistaPreviaInvitacion vista) {
    final logueado = _authService.usuarioActual != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Icon(Icons.domain, size: 32, color: Color(0xFF1B365D)),
                const SizedBox(height: 12),
                Text(
                  logueado
                      ? 'Te vas a sumar a la obra "${vista.obraNombre}" como ${etiquetaRol(vista.rol)}.'
                      : 'Te invitaron a la obra "${vista.obraNombre}" como ${etiquetaRol(vista.rol)}.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  logueado
                      ? 'Confirmá para sumarte ahora.'
                      : 'Iniciá sesión o registrate para sumarte — en cuanto entres, te agregamos automáticamente, sin otro paso.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
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
          onPressed: _cargando ? null : _confirmar,
          child: _cargando
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(
                  logueado ? 'Confirmar' : 'Ir a iniciar sesión / registrarme',
                  style: const TextStyle(color: Colors.white),
                ),
        ),
        TextButton(
          onPressed: _cargando ? null : _cancelarConfirmacion,
          child: const Text('No es esta, ingresar otro código'),
        ),
      ],
    );
  }
}
