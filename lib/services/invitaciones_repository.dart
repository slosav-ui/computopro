import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/invitacion.dart';
import '../data/models/obra_member.dart';

/// Acceso a la tabla `invitaciones` y sus tres funciones (ver
/// `supabase/migrations/0095_invitaciones.sql`/`0096_invitaciones_previsualizar.sql`,
/// `docs/invitaciones_diseno_datos.md`).
///
/// Crear/listar son INSERT/SELECT directos bajo RLS (mismo criterio que
/// `ObraMembersRepository`); previsualizar/aceptar/revocar pasan por funciones `SECURITY DEFINER`
/// (canjear necesita insertar en `obra_members` para alguien que todavía no es miembro, algo que
/// la RLS normal no permite).
///
/// Los errores de las funciones (código inválido/vencido, demasiados intentos, sin permiso para
/// revocar) llegan como `PostgrestException` con el mensaje ya en español, listo para mostrar —
/// mismo patrón que `apu_composiciones_repository.dart`/`gestion_obra_tab.dart`: no se envuelven
/// acá, la pantalla que llama los atrapa con `on PostgrestException catch (e)` y muestra
/// `e.message` directo.
///
/// Cada método pasa por `_conLog` -- mismo criterio que `panel_crear_equipo_apu.dart`: el mensaje
/// que ve el usuario queda genérico a propósito (lo decide la pantalla que llama), pero el error
/// real (code/message/details/hint de Postgres, o la excepción cruda si no es `PostgrestException`)
/// siempre va a la consola antes de relanzarlo -- sin esto, un error de RLS/constraint/columna se
/// perdía detrás de "no se pudo generar el código" sin forma de diagnosticarlo.
class InvitacionesRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<T> _conLog<T>(String etiqueta, Future<T> Function() accion) async {
    try {
      return await accion();
    } on PostgrestException catch (e) {
      debugPrint(
        'InvitacionesRepository.$etiqueta falló (Postgrest) -- code=${e.code} message=${e.message} '
        'details=${e.details} hint=${e.hint}',
      );
      rethrow;
    } catch (e, st) {
      debugPrint('InvitacionesRepository.$etiqueta falló: $e\n$st');
      rethrow;
    }
  }

  Future<Invitacion> crearInvitacion({
    required String obraId,
    required RolProyecto rol,
    required PermisosEspeciales permisos,
    required String invitadoPorUsuarioId,
  }) {
    return _conLog('crearInvitacion', () async {
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
    });
  }

  Future<List<Invitacion>> getInvitacionesPendientes(String obraId) {
    return _conLog('getInvitacionesPendientes', () async {
      final data = await _client
          .from('invitaciones')
          .select()
          .eq('obra_id', obraId)
          .eq('estado', 'pendiente')
          .order('creado_at');
      return (data as List).map((row) => Invitacion.fromRow(row as Map<String, dynamic>)).toList();
    });
  }

  /// De solo lectura, sin efecto — funciona sin sesión activa (ver el grant a `anon` en
  /// `0096_invitaciones_previsualizar.sql`). `null` significa código inexistente, vencido, o ya
  /// usado — mismo criterio de mensaje único que `aceptar_invitacion`, no se distingue el motivo.
  Future<VistaPreviaInvitacion?> previsualizarInvitacion(String codigo) {
    return _conLog('previsualizarInvitacion', () async {
      final data = await _client.rpc('previsualizar_invitacion', params: {'p_codigo': codigo});
      final filas = data as List;
      if (filas.isEmpty) return null;
      final fila = filas.first as Map<String, dynamic>;
      return VistaPreviaInvitacion(
        obraNombre: fila['obra_nombre']?.toString() ?? '',
        rol: rolDesdeColumna(fila['rol']?.toString()),
      );
    });
  }

  Future<ResultadoInvitacionAceptada> aceptarInvitacion(String codigo) {
    return _conLog('aceptarInvitacion', () async {
      final data = await _client.rpc('aceptar_invitacion', params: {'p_codigo': codigo});
      // returns table(...) -> lista de una fila.
      final fila = (data as List).first as Map<String, dynamic>;
      return ResultadoInvitacionAceptada(
        obraId: fila['obra_id'].toString(),
        obraNombre: fila['obra_nombre']?.toString() ?? '',
        rol: rolDesdeColumna(fila['rol']?.toString()),
      );
    });
  }

  Future<void> revocarInvitacion(String invitacionId) {
    return _conLog('revocarInvitacion', () async {
      await _client.rpc('revocar_invitacion', params: {'p_invitacion_id': invitacionId});
    });
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
