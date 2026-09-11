import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/segurity/user_context.dart';
import '../../../data/models/invitacion.dart';
import '../../../data/models/obra_member.dart';
import '../../../data/models/perfil_basico.dart';
import '../../../services/auth_service.dart';
import '../../../services/invitaciones_repository.dart';
import '../../../services/obra_members_repository.dart';
import '../../../services/perfil_repository.dart';
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
  final _perfilRepository = PerfilRepository();

  List<ObraMember> _miembros = [];
  List<Invitacion> _invitaciones = [];
  // usuario_id -> nombre/teléfono, de get_perfiles_de_obra (0099_perfiles_nombre_telefono.sql).
  // Mapa vacío en vez de null cuando falla -- degrada a mostrar el UUID acortado (ver _idCorto),
  // nunca rompe la pantalla por un problema en un dato secundario.
  Map<String, PerfilBasico> _perfiles = {};
  bool _cargando = true;
  String? _error;

  bool get _puedeVerInvitaciones => widget.userContext?.puedeInvitarMiembros == true;
  bool get _puedeQuitar => widget.userContext?.puedeQuitarMiembros == true;
  bool get _puedeOtorgarAdmin => widget.userContext?.puedeOtorgarAdminMaestro == true;

  // Quiénes ya tienen admin_maestro activo -- un mismo usuario puede aparecer en _miembros más de
  // una vez (una fila por rol combinado, 0001_obra_members.sql), así que "hacer administrador" no
  // tiene sentido ofrecerlo en la fila de alguien que ya lo es por otra fila.
  Set<String> get _yaSonAdmin => _miembros
      .where((m) => m.rol == RolProyecto.adminMaestro)
      .map((m) => m.usuarioId)
      .toSet();

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
      // Nombre/teléfono son un dato secundario acá -- si get_perfiles_de_obra falla por lo que
      // sea, la pantalla sigue funcionando con el UUID acortado en vez de romperse entera.
      final perfilesFuture = _perfilRepository.getPerfilesDeObra(widget.obraId).catchError((_) => <PerfilBasico>[]);

      final miembros = await miembrosFuture;
      final invitaciones = await invitacionesFuture;
      final perfiles = await perfilesFuture;
      if (!mounted) return;
      setState(() {
        _miembros = miembros;
        _invitaciones = invitaciones;
        _perfiles = {for (final p in perfiles) p.usuarioId: p};
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
    // Renunciar a admin_maestro (0108) es el mismo camino que sacar a cualquier otro miembro --
    // pasa por la misma función y la misma guarda del lado del servidor ("no se puede sacar al
    // único administrador"), que ya llega tal cual al catch de abajo (PostgrestException con el
    // mensaje de quitar_miembro_obra). Solo cambia el texto del diálogo, para que quede claro que
    // es una renuncia al rol, no un abandono de la obra si todavía queda con otro rol.
    final esRenunciaAdmin = esUnoMismo && miembro.rol == RolProyecto.adminMaestro;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(esRenunciaAdmin ? 'Renunciar a administrador' : 'Sacar de la obra'),
        content: Text(
          esRenunciaAdmin
              ? '¿Renunciar a tu rol de administrador de esta obra? Si tenés otro rol acá, lo '
                  'conservás -- solo perdés los permisos de administrador.'
              : esUnoMismo
                  ? '¿Salir de esta obra como ${etiquetaRol(miembro.rol)}? Vas a perder el acceso.'
                  : '¿Sacar a ${_nombreMostrado(miembro.usuarioId)} (${etiquetaRol(miembro.rol)}) de la obra?\n\n'
                      'Se le quita el acceso. Lo que ya cargó -- avance, partidas -- no se borra: '
                      'queda igual, atribuido a esta persona.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(esRenunciaAdmin ? 'Renunciar' : 'Sacar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      await _obraMembersRepository.quitarMiembro(miembro.id);
      if (!mounted) return;
      if (esUnoMismo) {
        // Si esa era la última fila activa del usuario en esta obra, ya no es is_obra_member --
        // recargar esta pantalla rompería (la RLS ya no le deja leer nada de acá). Volver al
        // dashboard directo, no solo refrescar. `getMiembrosDeObra` (RLS: is_obra_member) da lista
        // vacía en vez de error si ya no tiene acceso -- no hace falta un caso aparte para eso.
        final sigueSiendoMiembro = await _obraMembersRepository
            .getMiembrosDeObra(widget.obraId)
            .then((miembros) => miembros.any((m) => m.usuarioId == _authService.usuarioActual?.id))
            .catchError((_) => false);
        if (!mounted) return;
        if (!sigueSiendoMiembro) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saliste de la obra.')));
          Navigator.of(context).popUntil((route) => route.isFirst);
          return;
        }
      }
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

  Future<void> _confirmarOtorgarAdmin(ObraMember miembro) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hacer administrador'),
        content: Text(
          '¿Nombrar a ${_nombreMostrado(miembro.usuarioId)} administrador de esta obra? '
          'Conserva su rol de ${etiquetaRol(miembro.rol)} además -- los dos conviven.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Nombrar')),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      await _obraMembersRepository.otorgarAdminMaestro(widget.obraId, miembro.usuarioId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Listo.')));
      await _cargar();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo nombrar administrador.')),
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

  // Nombre si `get_perfiles_de_obra` lo trajo, UUID acortado si no (todavía no lo cargó, o
  // falló la consulta) -- nunca deja la fila sin ningún identificador.
  String _nombreMostrado(String usuarioId) {
    final nombre = _perfiles[usuarioId]?.nombre;
    if (nombre != null) return nombre;
    return 'ID: ${_idCorto(usuarioId)}…';
  }

  Widget _buildMiembroCard(ObraMember miembro) {
    final esUnoMismo = miembro.usuarioId == _authService.usuarioActual?.id;
    final perfil = _perfiles[miembro.usuarioId];
    final invitadoPorId = miembro.invitadoPorUsuarioId;
    final permisos = <String>[
      if (miembro.permisosEspeciales.puedeInvitarTerceros) 'invita terceros',
      if (miembro.permisosEspeciales.puedeVerApuAjena) 've APU ajena',
      if (miembro.permisosEspeciales.puedeAprobarCertificados) 'aprueba certificados',
    ];
    final lineaSecundaria = <String>[
      etiquetaRol(miembro.rol),
      if (perfil?.matricula != null) 'mat. ${perfil!.matricula}',
      ?perfil?.telefono,
      if (permisos.isNotEmpty) permisos.join(', '),
      if (invitadoPorId != null) 'invitado por ${_nombreMostrado(invitadoPorId)}',
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.person_outline, color: Color(0xFF1B365D)),
        title: Row(
          children: [
            Flexible(
              child: Text(
                _nombreMostrado(miembro.usuarioId),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
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
        subtitle: Text(lineaSecundaria, style: const TextStyle(fontSize: 11)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // "Hacer administrador" (0108) -- solo tiene sentido en la fila de alguien que
            // TODAVÍA no es admin_maestro (por esta fila o por otra combinada, ver _yaSonAdmin).
            if (_puedeOtorgarAdmin &&
                miembro.rol != RolProyecto.adminMaestro &&
                !_yaSonAdmin.contains(miembro.usuarioId))
              IconButton(
                icon: const Icon(Icons.admin_panel_settings_outlined, size: 20, color: Color(0xFF1B365D)),
                tooltip: 'Hacer administrador',
                onPressed: () => _confirmarOtorgarAdmin(miembro),
              ),
            if (_puedeQuitar)
              IconButton(
                icon: const Icon(Icons.person_remove_outlined, size: 20, color: Colors.red),
                tooltip: esUnoMismo && miembro.rol == RolProyecto.adminMaestro
                    ? 'Renunciar a administrador'
                    : 'Sacar de la obra',
                onPressed: () => _confirmarQuitar(miembro),
              ),
          ],
        ),
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
