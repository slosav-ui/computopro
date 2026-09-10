import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/segurity/user_context.dart';
import '../../../data/models/invitacion.dart';
import '../../../data/models/obra_member.dart';
import '../../../services/auth_service.dart';
import '../../../services/invitaciones_repository.dart';
import '../../../services/obra_members_repository.dart';
import 'invitar_miembro_screen.dart';

/// Invitaciones, Tanda 2 — ver `docs/invitaciones_diseno_datos.md`. Miembros activos de la obra,
/// invitaciones pendientes (con copiar/revocar) e histórico (vencidas/revocadas/aceptadas).
/// Punto de entrada único para gestión de gente en la obra: "Invitar" vive adentro de esta
/// pantalla (antes era un ícono aparte en `PresupuestosScreen`), gateado por
/// `puedeInvitarMiembros` -- la pantalla en sí la ve cualquier miembro, ver `userContext` más
/// abajo.
class MiembrosObraScreen extends StatefulWidget {
  final String obraId;
  final UserContext? userContext;

  const MiembrosObraScreen({super.key, required this.obraId, required this.userContext});

  @override
  State<MiembrosObraScreen> createState() => _MiembrosObraScreenState();
}

class _MiembrosObraScreenState extends State<MiembrosObraScreen> {
  final _authService = AuthService();
  final _obraMembersRepository = ObraMembersRepository();
  final _invitacionesRepository = InvitacionesRepository();

  List<ObraMember> _miembros = [];
  List<Invitacion> _invitaciones = [];
  bool _cargando = true;
  String? _error;

  bool get _puedeVerInvitaciones => widget.userContext?.puedeInvitarMiembros == true;
  bool get _puedeQuitar => widget.userContext?.puedeQuitarMiembros == true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final miembrosFuture = _obraMembersRepository.getMiembrosDeObra(widget.obraId);
      // RLS ya filtra a quien no tiene por qué ver invitaciones -- pedirla igual para todos
      // simplifica el código, y en el peor caso vuelve una lista vacía, no un error. Igual se
      // evita el viaje de red de más: si el getter ya dice que no, ni se pide.
      final invitacionesFuture = _puedeVerInvitaciones
          ? _invitacionesRepository.getTodasLasInvitaciones(widget.obraId)
          : Future.value(<Invitacion>[]);

      final miembros = await miembrosFuture;
      final invitaciones = await invitacionesFuture;
      if (!mounted) return;
      setState(() {
        _miembros = miembros;
        _invitaciones = invitaciones;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar la lista de miembros.';
        _cargando = false;
      });
    }
  }

  Future<void> _irAInvitar() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => InvitarMiembroScreen(obraId: widget.obraId)),
    );
    await _cargar();
  }

  Future<void> _confirmarQuitar(ObraMember miembro) async {
    final esUnoMismo = miembro.usuarioId == _authService.usuarioActual?.id;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sacar de la obra'),
        content: Text(
          esUnoMismo
              ? '¿Salir de esta obra como ${etiquetaRol(miembro.rol)}? Vas a perder el acceso.'
              : '¿Sacar a este integrante (${etiquetaRol(miembro.rol)}) de la obra?\n\n'
                  'Se le quita el acceso. Lo que ya cargó -- avance, partidas -- no se borra: '
                  'queda igual, atribuido a esta persona.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sacar')),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      await _obraMembersRepository.quitarMiembro(miembro.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Listo.')));
      await _cargar();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo sacar al miembro.')),
      );
    }
  }

  Future<void> _confirmarRevocar(Invitacion invitacion) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Revocar invitación'),
        content: Text('¿Revocar el código ${invitacion.codigo}? Ya no se va a poder usar.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Revocar')),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      await _invitacionesRepository.revocarInvitacion(invitacion.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invitación revocada.')));
      await _cargar();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo revocar la invitación.')),
      );
    }
  }

  void _copiarCodigo(String codigo) {
    Clipboard.setData(ClipboardData(text: codigo));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Código copiado.')));
  }

  String _fmtFecha(DateTime f) =>
      '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}/${f.year}';

  // UUID crudo, acortado -- no hay nombre ni email visible en ningún lado del proyecto todavía
  // (`perfiles` solo tiene `usuario_id`/`es_pro`, ver `supabase/migrations/0014_perfiles.sql`, y
  // el cliente no puede leer `auth.users.email` de otra persona). Gap real, no resuelto acá --
  // ver docs/invitaciones_diseno_datos.md.
  String _idCorto(String usuarioId) => usuarioId.length > 8 ? usuarioId.substring(0, 8) : usuarioId;

  String _estadoLabel(Invitacion inv) {
    if (inv.estado == EstadoInvitacion.aceptada) return 'Aceptada';
    if (inv.estado == EstadoInvitacion.revocada) return 'Revocada';
    return 'Vencida'; // pendiente pero expiraEn ya pasó
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B365D),
        title: const Text('Miembros de la obra', style: TextStyle(color: Colors.white, fontSize: 15)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (widget.userContext?.puedeInvitarMiembros == true)
            IconButton(
              icon: const Icon(Icons.person_add_alt, color: Colors.white),
              tooltip: 'Invitar',
              onPressed: _irAInvitar,
            ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
              : RefreshIndicator(onRefresh: _cargar, child: _buildContenido()),
    );
  }

  Widget _buildContenido() {
    final vigentes = _invitaciones.where((i) => i.vigente).toList();
    final historico = _invitaciones.where((i) => !i.vigente).toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        _buildEncabezado('Miembros (${_miembros.length})', Icons.groups),
        if (_miembros.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('Sin miembros todavía.', style: TextStyle(color: Colors.black45, fontSize: 12)),
          )
        else
          ..._miembros.map(_buildMiembroCard),
        if (_puedeVerInvitaciones) ...[
          const SizedBox(height: 16),
          _buildEncabezado('Invitaciones pendientes (${vigentes.length})', Icons.mail_outline),
          if (vigentes.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('Sin invitaciones pendientes.', style: TextStyle(color: Colors.black45, fontSize: 12)),
            )
          else
            ...vigentes.map(_buildInvitacionPendienteCard),
          if (historico.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildEncabezado('Histórico (${historico.length})', Icons.history),
            ...historico.map(_buildInvitacionHistoricoTile),
          ],
        ],
      ],
    );
  }

  Widget _buildEncabezado(String titulo, IconData icono) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icono, size: 16, color: const Color(0xFF1B365D)),
          const SizedBox(width: 6),
          Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1B365D))),
        ],
      ),
    );
  }

  Widget _buildMiembroCard(ObraMember miembro) {
    final esUnoMismo = miembro.usuarioId == _authService.usuarioActual?.id;
    final permisos = <String>[
      if (miembro.permisosEspeciales.puedeInvitarTerceros) 'invita terceros',
      if (miembro.permisosEspeciales.puedeVerApuAjena) 've APU ajena',
      if (miembro.permisosEspeciales.puedeAprobarCertificados) 'aprueba certificados',
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.person_outline, color: Color(0xFF1B365D)),
        title: Row(
          children: [
            Text(etiquetaRol(miembro.rol), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            if (esUnoMismo) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(4)),
                child: const Text('Vos', style: TextStyle(fontSize: 10, color: Colors.blue)),
              ),
            ],
          ],
        ),
        subtitle: Text(
          'ID: ${_idCorto(miembro.usuarioId)}…'
          '${permisos.isNotEmpty ? ' · ${permisos.join(', ')}' : ''}',
          style: const TextStyle(fontSize: 11),
        ),
        trailing: _puedeQuitar
            ? IconButton(
                icon: const Icon(Icons.person_remove_outlined, size: 20, color: Colors.red),
                tooltip: 'Sacar de la obra',
                onPressed: () => _confirmarQuitar(miembro),
              )
            : null,
      ),
    );
  }

  Widget _buildInvitacionPendienteCard(Invitacion inv) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.mail_outline, color: Color(0xFF1B365D)),
        title: Text(
          inv.codigo,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 1),
        ),
        subtitle: Text(
          '${etiquetaRol(inv.rol)} · vence el ${_fmtFecha(inv.expiraEn)}',
          style: const TextStyle(fontSize: 11),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.copy, size: 18),
              tooltip: 'Copiar código',
              onPressed: () => _copiarCodigo(inv.codigo),
            ),
            IconButton(
              icon: const Icon(Icons.cancel_outlined, size: 18, color: Colors.red),
              tooltip: 'Revocar',
              onPressed: () => _confirmarRevocar(inv),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInvitacionHistoricoTile(Invitacion inv) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${etiquetaRol(inv.rol)} · ${inv.codigo}',
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ),
          Text(_estadoLabel(inv), style: const TextStyle(fontSize: 11, color: Colors.black38)),
        ],
      ),
    );
  }
}
