import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/auth_service.dart';
import '../../services/perfil_repository.dart';

/// Cargar/corregir el propio nombre, teléfono y matrícula profesional -- ver
/// `supabase/migrations/0099_perfiles_nombre_telefono.sql`/`0100_perfiles_matricula.sql`. Cubre
/// el caso que el registro no resuelve: usuarios que ya existían antes de esta pieza (sin nombre,
/// sin forma de inferirlo) y cualquiera que se haya equivocado al tipear la primera vez.
/// Reachable desde el menú de `ObrasListScreen`.
class EditarPerfilScreen extends StatefulWidget {
  const EditarPerfilScreen({super.key});

  @override
  State<EditarPerfilScreen> createState() => _EditarPerfilScreenState();
}

class _EditarPerfilScreenState extends State<EditarPerfilScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();
  final _perfilRepository = PerfilRepository();
  final _nombreCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _matriculaCtrl = TextEditingController();

  bool _cargando = true;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _telefonoCtrl.dispose();
    _matriculaCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final usuarioId = _authService.usuarioActual?.id;
    if (usuarioId == null) {
      setState(() => _cargando = false);
      return;
    }
    try {
      final perfil = await _perfilRepository.getMiPerfil(usuarioId);
      if (!mounted) return;
      setState(() {
        _nombreCtrl.text = perfil?.nombre ?? '';
        _telefonoCtrl.text = perfil?.telefono ?? '';
        _matriculaCtrl.text = perfil?.matricula ?? '';
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar tu perfil.';
        _cargando = false;
      });
    }
  }

  String? _validarNombre(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Ingresá tu nombre.';
    return null;
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await _perfilRepository.actualizarMiPerfil(
        nombre: _nombreCtrl.text.trim(),
        telefono: _telefonoCtrl.text.trim(),
        matricula: _matriculaCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Perfil actualizado.')));
      Navigator.of(context).pop();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _guardando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo guardar. Intentá de nuevo.';
        _guardando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B365D),
        title: const Text('Mi perfil', style: TextStyle(color: Colors.white, fontSize: 15)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Así te ven tus compañeros de obra en la lista de miembros.',
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _nombreCtrl,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Nombre',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          validator: _validarNombre,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _telefonoCtrl,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Teléfono (opcional)',
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
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(_error!, style: TextStyle(color: Colors.red[700], fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                        const SizedBox(height: 20),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1B365D),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: _guardando ? null : _guardar,
                          child: _guardando
                              ? const SizedBox(
                                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Text('Guardar', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
