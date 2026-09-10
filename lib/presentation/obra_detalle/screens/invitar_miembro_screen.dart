import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/utils/parser_numero_ar.dart';
import '../../../data/models/invitacion.dart';
import '../../../data/models/obra_member.dart';
import '../../../services/auth_service.dart';
import '../../../services/invitaciones_repository.dart';

/// Invitar a alguien a la obra: elegir rol + permisos, generar un código de 8 caracteres para
/// pegar a mano (WhatsApp) — ver `docs/invitaciones_diseno_datos.md`. Tanda 1: sin enlace real
/// todavía, sin panel de miembros (eso es Tanda 2).
class InvitarMiembroScreen extends StatefulWidget {
  final String obraId;

  const InvitarMiembroScreen({super.key, required this.obraId});

  @override
  State<InvitarMiembroScreen> createState() => _InvitarMiembroScreenState();
}

class _InvitarMiembroScreenState extends State<InvitarMiembroScreen> {
  final _authService = AuthService();
  final _repositorio = InvitacionesRepository();
  final _topeMontoCtrl = TextEditingController();

  // Sin admin_maestro a propósito (decisión cerrada, docs/invitaciones_diseno_datos.md §3) --
  // no es un rol económico invitable, está ligado a quien crea la obra.
  static const _rolesInvitables = [
    RolProyecto.profesional,
    RolProyecto.constructor,
    RolProyecto.clientePrincipal,
    RolProyecto.invitadoVeedor,
    RolProyecto.invitadoApoderado,
  ];

  RolProyecto _rol = RolProyecto.constructor;
  bool _puedeAprobarCertificados = false;
  bool _puedeAprobarAdicionales = false;
  bool _puedeInvitarTerceros = false;
  bool _puedeVerApuAjena = false;
  DateTime? _delegacionInicio;
  DateTime? _delegacionFin;

  bool _generando = false;
  String? _error;
  Invitacion? _invitacionGenerada;

  @override
  void dispose() {
    _topeMontoCtrl.dispose();
    super.dispose();
  }

  Future<void> _elegirFecha({required bool esInicio}) async {
    final ahora = DateTime.now();
    final fecha = await showDatePicker(
      context: context,
      initialDate: esInicio ? (_delegacionInicio ?? ahora) : (_delegacionFin ?? ahora),
      firstDate: ahora.subtract(const Duration(days: 1)),
      lastDate: ahora.add(const Duration(days: 365 * 2)),
    );
    if (fecha == null) return;
    setState(() {
      if (esInicio) {
        _delegacionInicio = fecha;
      } else {
        _delegacionFin = fecha;
      }
    });
  }

  Future<void> _generarCodigo() async {
    final usuarioId = _authService.usuarioActual?.id;
    if (usuarioId == null) return;

    setState(() {
      _generando = true;
      _error = null;
    });

    // ParserNumeroAr, no double.tryParse a secas -- un monto tipeado con coma decimal
    // ("1.200,50") se guardaba en 0 en silencio con el parser ingenuo (ver memoria de diseño
    // "bug_coma_decimal_analisis_precios").
    final tope = ParserNumeroAr.parsear(_topeMontoCtrl.text);

    try {
      final invitacion = await _repositorio.crearInvitacion(
        obraId: widget.obraId,
        rol: _rol,
        invitadoPorUsuarioId: usuarioId,
        permisos: PermisosEspeciales(
          puedeAprobarCertificados: _puedeAprobarCertificados,
          puedeAprobarAdicionales: _puedeAprobarAdicionales,
          topeMontoAprobacion: _puedeAprobarAdicionales ? tope : null,
          delegacionTemporalInicio: _rol == RolProyecto.invitadoApoderado ? _delegacionInicio : null,
          delegacionTemporalFin: _rol == RolProyecto.invitadoApoderado ? _delegacionFin : null,
          puedeInvitarTerceros: _puedeInvitarTerceros,
          puedeVerApuAjena: _puedeVerApuAjena,
        ),
      );
      if (!mounted) return;
      setState(() {
        _invitacionGenerada = invitacion;
        _generando = false;
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _generando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo generar el código. Intentá de nuevo.';
        _generando = false;
      });
    }
  }

  void _copiarCodigo(String codigo) {
    Clipboard.setData(ClipboardData(text: codigo));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Código copiado.')),
    );
  }

  String _fmtFecha(DateTime f) => '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}/${f.year}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B365D),
        title: const Text('Invitar a la obra', style: TextStyle(color: Colors.white, fontSize: 15)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: _invitacionGenerada != null ? _buildResultado(_invitacionGenerada!) : _buildFormulario(),
      ),
    );
  }

  Widget _buildFormulario() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Rol', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 6),
        DropdownButtonFormField<RolProyecto>(
          initialValue: _rol,
          decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
          items: [
            for (final rol in _rolesInvitables) DropdownMenuItem(value: rol, child: Text(etiquetaRol(rol))),
          ],
          onChanged: (v) => setState(() => _rol = v ?? _rol),
        ),
        const SizedBox(height: 20),
        const Text('Permisos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Puede aprobar certificados', style: TextStyle(fontSize: 13)),
          value: _puedeAprobarCertificados,
          onChanged: (v) => setState(() => _puedeAprobarCertificados = v ?? false),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Puede aprobar adicionales', style: TextStyle(fontSize: 13)),
          value: _puedeAprobarAdicionales,
          onChanged: (v) => setState(() => _puedeAprobarAdicionales = v ?? false),
        ),
        if (_puedeAprobarAdicionales)
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 8),
            child: TextField(
              controller: _topeMontoCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Tope de monto (vacío = sin límite)',
                border: OutlineInputBorder(),
                isDense: true,
                prefixText: '\$ ',
              ),
            ),
          ),
        if (_rol == RolProyecto.invitadoApoderado) ...[
          const SizedBox(height: 8),
          const Text('Delegación (opcional — vacío = permanente)', style: TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _elegirFecha(esInicio: true),
                  child: Text(_delegacionInicio == null ? 'Desde' : _fmtFecha(_delegacionInicio!)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _elegirFecha(esInicio: false),
                  child: Text(_delegacionFin == null ? 'Hasta' : _fmtFecha(_delegacionFin!)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Puede invitar a terceros', style: TextStyle(fontSize: 13)),
          value: _puedeInvitarTerceros,
          onChanged: (v) => setState(() => _puedeInvitarTerceros = v ?? false),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Puede ver el APU de otros', style: TextStyle(fontSize: 13)),
          value: _puedeVerApuAjena,
          onChanged: (v) => setState(() => _puedeVerApuAjena = v ?? false),
        ),
        // Aviso genérico, no una verificación real: al invitar no se sabe si la persona invitada
        // es PRO -- puede ni tener cuenta todavía. La verificación real es esPro(auth.uid()) en
        // vivo, en el momento de uso (docs/invitaciones_diseno_datos.md §4).
        if (_puedeVerApuAjena)
          Container(
            margin: const EdgeInsets.only(left: 12, bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.amber[50],
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.amber[200]!),
            ),
            child: Row(
              children: [
                Icon(Icons.workspace_premium, size: 14, color: Colors.amber[800]),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Requiere PRO: si la persona invitada es Free, no va a poder ver el APU hasta que actualice su plan.',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: Colors.red[700], fontSize: 12, fontWeight: FontWeight.w600)),
        ],
        const SizedBox(height: 20),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1B365D),
            padding: const EdgeInsets.symmetric(vertical: 14),
            minimumSize: const Size.fromHeight(0),
          ),
          onPressed: _generando ? null : _generarCodigo,
          child: _generando
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Generar código', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  Widget _buildResultado(Invitacion invitacion) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text(
                  'Código para ${etiquetaRol(invitacion.rol)}',
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                Text(
                  invitacion.codigo,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 4, color: Color(0xFF1B365D)),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => _copiarCodigo(invitacion.codigo),
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copiar código'),
                ),
                const SizedBox(height: 12),
                Text(
                  'Compartilo por WhatsApp. Vence el ${_fmtFecha(invitacion.expiraEn)}, o cuando lo revoques.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Listo'),
        ),
      ],
    );
  }
}
