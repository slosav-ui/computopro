import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/invitacion.dart';
import '../data/models/obra_member.dart';

/// Acceso a la tabla `invitaciones` y sus dos funciones (ver
/// `supabase/migrations/0095_invitaciones.sql`, `docs/invitaciones_diseno_datos.md`).
///
/// Crear/listar son INSERT/SELECT directos bajo RLS (mismo criterio que
/// `ObraMembersRepository`); aceptar/revocar pasan por las funciones `SECURITY DEFINER` porque
/// ahí vive la autorización real (canjear necesita insertar en `obra_members` para alguien que
/// todavía no es miembro, algo que la RLS normal no permite).
///
/// Los errores de las funciones (código inválido/vencido, demasiados intentos, sin permiso para
/// revocar) llegan como `PostgrestException` con el mensaje ya en español, listo para mostrar —
/// mismo patrón que `apu_composiciones_repository.dart`/`gestion_obra_tab.dart`: no se envuelven
/// acá, la pantalla que llama los atrapa con `on PostgrestException catch (e)` y muestra
/// `e.message` directo.
class InvitacionesRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<Invitacion> crearInvitacion({
    required String obraId,
    required RolProyecto rol,
    required PermisosEspeciales permisos,
    required String invitadoPorUsuarioId,
  }) async {
    final row = await _client
        .from('invitaciones')
        .insert({
          'obra_id': obraId,
          'rol': columnaDesdeRol(rol),
          'puede_aprobar_certificados': permisos.puedeAprobarCertificados,
          'puede_aprobar_adicionales': permisos.puedeAprobarAdicionales,
          'tope_monto_aprobacion': permisos.topeMontoAprobacion,
          'delegacion_inicio': permisos.delegacionTemporalInicio?.toIso8601String(),
          'delegacion_fin': permisos.delegacionTemporalFin?.toIso8601String(),
          'puede_invitar_terceros': permisos.puedeInvitarTerceros,
          'puede_ver_apu_ajena': permisos.puedeVerApuAjena,
          'invitado_por_usuario_id': invitadoPorUsuarioId,
        })
        .select()
        .single();
    return Invitacion.fromRow(row);
  }

  Future<List<Invitacion>> getInvitacionesPendientes(String obraId) async {
    final data = await _client
        .from('invitaciones')
        .select()
        .eq('obra_id', obraId)
        .eq('estado', 'pendiente')
        .order('creado_at');
    return (data as List).map((row) => Invitacion.fromRow(row as Map<String, dynamic>)).toList();
  }

  Future<ResultadoInvitacionAceptada> aceptarInvitacion(String codigo) async {
    final data = await _client.rpc('aceptar_invitacion', params: {'p_codigo': codigo});
    // returns table(...) -> lista de una fila.
    final fila = (data as List).first as Map<String, dynamic>;
    return ResultadoInvitacionAceptada(
      obraId: fila['obra_id'].toString(),
      obraNombre: fila['obra_nombre']?.toString() ?? '',
      rol: rolDesdeColumna(fila['rol']?.toString()),
    );
  }

  Future<void> revocarInvitacion(String invitacionId) async {
    await _client.rpc('revocar_invitacion', params: {'p_invitacion_id': invitacionId});
  }
}

/// Persistencia del código pendiente entre "lo pega, se registra, confirma el email, vuelve" —
/// ver `docs/invitaciones_diseno_datos.md` §7. `SharedPreferences`, mismo mecanismo que ya usa el
/// proyecto para estado que cruza reinicios (`CartelCostoManoObra`, aviso de zona UOCRA), porque
/// nada en memoria (`Navigator`, estado de widget) sobrevive la confirmación de email, que puede
/// pasar con la app cerrada.
class InvitacionPendiente {
  static const _clave = 'invitaciones_codigo_pendiente';

  static Future<void> guardar(String codigo) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_clave, codigo);
  }

  static Future<String?> leer() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_clave);
  }

  static Future<void> borrar() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_clave);
  }
}
