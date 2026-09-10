import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import 'aceptar_invitacion_screen.dart';

/// Pantalla de Login/Registro (email + contraseña). Se muestra antes de
/// "Mis Obras" cuando no hay sesión activa de Supabase Auth (ver AuthGate).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nombreCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _matriculaCtrl = TextEditingController();

  bool _modoRegistro = false;
  bool _cargando = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _nombreCtrl.dispose();
    _telefonoCtrl.dispose();
    _matriculaCtrl.dispose();
    super.dispose();
  }

  String? _validarEmail(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Ingresá tu email.';
    final regex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!regex.hasMatch(v)) return 'Ingresá un email válido.';
    return null;
  }

  // Solo se valida en modo registro (ver el TextFormField más abajo, validator condicional) --
  // en modo login el campo ni se muestra.
  String? _validarNombre(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Ingresá tu nombre.';
    return null;
  }

  String? _validarPassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Ingresá tu contraseña.';
    if (v.length < 6) return 'La contraseña debe tener al menos 6 caracteres.';
    return null;
  }

  Future<void> _enviar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      if (_modoRegistro) {
        await _authService.registrarse(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
          nombre: _nombreCtrl.text.trim(),
          telefono: _telefonoCtrl.text.trim(),
          matricula: _matriculaCtrl.text.trim(),
        );
      } else {
        await _authService.iniciarSesion(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
        );
      }
      // Si el login/registro fue exitoso, AuthGate reacciona solo al cambio
      // de estado de auth y muestra Mis Obras; no hace falta navegar acá.
    } on AuthFriendlyException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Ocurrió un error inesperado. Intentá de nuevo.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.construction, size: 48, color: Color(0xFF1B365D)),
                    const SizedBox(height: 12),
                    const Text(
                      'ComputoPRO',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1B365D)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _modoRegistro ? 'Creá tu cuenta' : 'Iniciá sesión para continuar',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, color: Colors.black54),
                    ),
                    const SizedBox(height: 24),
                    // Nombre/teléfono/matrícula solo en modo registro -- ver
                    // AuthService.registrarse: se guardan en auth.users como metadata del signup,
                    // y el trigger de perfiles los lee de ahí (0099_perfiles_nombre_telefono.sql/
                    // 0100_perfiles_matricula.sql). Es el único momento en que la app puede
                    // capturarlos sin una pantalla de edición aparte -- por eso nombre es
                    // obligatorio acá, no opcional para completar después (teléfono y matrícula
                    // sí quedan opcionales, se pueden cargar después desde "Mi perfil").
                    if (_modoRegistro) ...[
                      TextFormField(
                        controller: _nombreCtrl,
                        textCapitalization: TextCapitalization.words,
                        autofillHints: const [AutofillHints.name],
                        decoration: const InputDecoration(
                          labelText: 'Nombre',
                          helperText: 'Así te van a ver tus compañeros de obra.',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        validator: _validarNombre,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _telefonoCtrl,
                        keyboardType: TextInputType.phone,
                        autofillHints: const [AutofillHints.telephoneNumber],
                        decoration: const InputDecoration(
                          labelText: 'Teléfono (opcional)',
                          helperText: 'En obra se llama por teléfono, no se manda mail.',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _matriculaCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Matrícula profesional (opcional)',
                          helperText: 'Va en los presupuestos y certificados que emitas.',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      validator: _validarEmail,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passwordCtrl,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      decoration: const InputDecoration(
                        labelText: 'Contraseña',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      validator: _validarPassword,
                      onFieldSubmitted: (_) => _enviar(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: TextStyle(color: Colors.red[700], fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                    const SizedBox(height: 20),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1B365D),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: _cargando ? null : _enviar,
                      child: _cargando
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text(
                              _modoRegistro ? 'Registrarme' : 'Ingresar',
                              style: const TextStyle(color: Colors.white),
                            ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _cargando
                          ? null
                          : () => setState(() {
                                _modoRegistro = !_modoRegistro;
                                _error = null;
                              }),
                      child: Text(
                        _modoRegistro
                            ? '¿Ya tenés cuenta? Iniciá sesión'
                            : '¿No tenés cuenta? Registrate',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    TextButton(
                      onPressed: _cargando
                          ? null
                          : () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const AceptarInvitacionScreen()),
                              ),
                      child: const Text(
                        '¿Tenés un código de invitación?',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
