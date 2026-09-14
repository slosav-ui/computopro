import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/auth_service.dart';
import 'aceptar_invitacion_screen.dart';

/// Pantalla de Login/Registro (email + contraseña). Se muestra antes de
/// "Mis Obras" cuando no hay sesión activa de Supabase Auth (ver AuthGate).
///
/// **Tipear el mail entero cada vez, no** (pedido de Seba, 2026-09-14: *"alguien en obra con el
/// teléfono en la mano no va a querer hacer eso"*). Dos mecanismos distintos, que se suman:
///
/// 1. **El autocompletado del sistema** -- el llavero de Android/iOS o el navegador. Los
///    `autofillHints` de cada campo ya estaban puestos, pero **no alcanzan solos**: sin un
///    `AutofillGroup` que los agrupe, la plataforma no tiene a quién ofrecerle el par
///    mail+contraseña y en la práctica no ofrece nada. Ese es el arreglo real de esta tanda.
///    `TextInput.finishAutofillContext()` es la otra mitad: es lo que le avisa al administrador de
///    contraseñas que el formulario se envió bien y que puede ofrecer guardarlo.
/// 2. **El último mail usado**, que la app se guarda sola (`UltimoEmail`) y precarga al abrir. Es
///    lo que resuelve el caso del que no tiene administrador de contraseñas configurado, que en un
///    teléfono de obra es lo más común.
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
  void initState() {
    super.initState();
    _precargarUltimoEmail();
  }

  /// Si el usuario ya empezó a escribir mientras se leía la preferencia, no se le pisa lo tipeado
  /// -- la lectura es rápida, pero "rápida" no es "instantánea" y perder una tecla en el primer
  /// campo de la app sería peor que no precargar nada.
  Future<void> _precargarUltimoEmail() async {
    final ultimo = await UltimoEmail.leer();
    if (!mounted || ultimo == null || _emailCtrl.text.isNotEmpty) return;
    setState(() => _emailCtrl.text = ultimo);
  }

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
      // Recién acá, con el mail ya validado contra la base: guardar uno que no existe o está mal
      // tipeado sería precargar un error todas las próximas veces.
      await UltimoEmail.guardar(_emailCtrl.text);
      // Y esto le avisa al llavero del sistema (o al navegador) que el formulario se envió bien,
      // que es cuando ofrece guardar el par mail+contraseña. Va antes de que AuthGate desmonte
      // esta pantalla: después ya no hay contexto de autofill que cerrar.
      TextInput.finishAutofillContext();
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
              // AutofillGroup: sin esto, los `autofillHints` de los campos son decorativos --
              // la plataforma necesita saber qué campos forman UN formulario para poder ofrecer
              // el mail y la contraseña juntos, y para poder ofrecer guardarlos después.
              child: AutofillGroup(
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
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1B365D),
                        ),
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
                        // `username` además de `email`: para el llavero el usuario de una cuenta es
                        // el campo "username", y con los dos hints la sugerencia aparece igual en
                        // los administradores de contraseñas que buscan uno o el otro.
                        autofillHints: const [AutofillHints.username, AutofillHints.email],
                        textInputAction: TextInputAction.next,
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
                        // En registro el hint es `newPassword`, no `password`: es lo que hace que el
                        // llavero ofrezca generar y guardar una contraseña nueva en vez de intentar
                        // completar una vieja que no existe.
                        autofillHints: [
                          _modoRegistro ? AutofillHints.newPassword : AutofillHints.password,
                        ],
                        textInputAction: TextInputAction.done,
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
                          style: TextStyle(
                            color: Colors.red[700],
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
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
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
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
      ),
    );
  }
}
