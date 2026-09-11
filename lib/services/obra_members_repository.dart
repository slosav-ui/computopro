import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/obra_member.dart';

/// Acceso a la tabla `obra_members` de Supabase (Etapa 3, paso 1).
///
/// Traduce entre las columnas planas y snake_case de la tabla
/// (ver `supabase/migrations/0001_obra_members.sql`) y el modelo `ObraMember`.
/// No reutiliza `ObraMember.fromMap()` porque ese método espera la forma
/// serializada de la app (camelCase, `permisosEspeciales` anidado), no la
/// fila cruda de la tabla.
class ObraMembersRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<T> _conLog<T>(String etiqueta, Future<T> Function() accion) async {
    try {
      return await accion();
    } on PostgrestException catch (e) {
      debugPrint(
        'ObraMembersRepository.$etiqueta falló (Postgrest) -- code=${e.code} message=${e.message} '
        'details=${e.details} hint=${e.hint}',
      );
      rethrow;
    } catch (e, st) {
      debugPrint('ObraMembersRepository.$etiqueta falló: $e\n$st');
      rethrow;
    }
  }

  Future<List<ObraMember>> getMiembrosDeObra(String obraId) {
    return _conLog('getMiembrosDeObra', () async {
      final data = await _client
          .from('obra_members')
          .select()
          .eq('obra_id', obraId)
          .eq('activo', true);
      return (data as List)
          .map((row) => _fromRow(row as Map<String, dynamic>))
          .toList();
    });
  }

  /// Ver `supabase/migrations/0098_quitar_miembro_obra.sql` -- pone `activo = false` (nunca
  /// borra la fila) con la guarda de "no dejar la obra sin ningún admin_maestro activo" resuelta
  /// del lado del servidor, no acá. Mismo camino para que un `admin_maestro` renuncie a su propio
  /// rol -- pasarle el `id` de su propia fila; la guarda de "no puede irse el único administrador"
  /// aplica igual (`0108`).
  Future<void> quitarMiembro(String obraMemberId) {
    return _conLog('quitarMiembro', () async {
      await _client.rpc('quitar_miembro_obra', params: {'p_obra_member_id': obraMemberId});
    });
  }

  /// Nombra a otro miembro ya existente como `admin_maestro`, además de su(s) rol(es) actual(es)
  /// -- roles combinables, no un reemplazo. `0108`. Solo puede llamarla quien ya es
  /// `admin_maestro` de esa obra (verificado del lado del servidor).
  Future<void> otorgarAdminMaestro(String obraId, String usuarioId) {
    return _conLog('otorgarAdminMaestro', () async {
      await _client.rpc('otorgar_admin_maestro', params: {
        'p_obra_id': obraId,
        'p_usuario_id': usuarioId,
      });
    });
  }

  /// Los `obra_id` donde el usuario actual tiene `admin_maestro` activo -- `0108`, reemplaza el
  /// criterio viejo de `ObrasListScreen` (`obras.id_admin_creador == auth.uid()`, que no reflejaba
  /// ni la posibilidad de varios administradores ni la renuncia al rol). Una sola consulta para
  /// toda la lista del dashboard, no una por obra.
  Future<Set<String>> getObraIdsDondeSoyAdminMaestro(String usuarioId) {
    return _conLog('getObraIdsDondeSoyAdminMaestro', () async {
      final data = await _client
          .from('obra_members')
          .select('obra_id')
          .eq('usuario_id', usuarioId)
          .eq('rol', 'admin_maestro')
          .eq('activo', true);
      return (data as List).map((row) => (row as Map<String, dynamic>)['obra_id'].toString()).toSet();
    });
  }

  ObraMember _fromRow(Map<String, dynamic> row) {
    return ObraMember(
      id: row['id'].toString(),
      obraId: row['obra_id'].toString(),
      usuarioId: row['usuario_id'].toString(),
      rol: _rolDesdeColumna(row['rol']?.toString()),
      invitadoPorUsuarioId: row['invitado_por_usuario_id']?.toString(),
      activo: row['activo'] == true,
      fechaAlta: DateTime.tryParse(row['created_at']?.toString() ?? '') ?? DateTime.now(),
      permisosEspeciales: PermisosEspeciales(
        puedeAprobarCertificados: row['puede_aprobar_certificados'] == true,
        puedeAprobarAdicionales: row['puede_aprobar_adicionales'] == true,
        topeMontoAprobacion: (row['tope_monto_aprobacion'] as num?)?.toDouble(),
        delegacionTemporalInicio: row['delegacion_inicio'] != null
            ? DateTime.tryParse(row['delegacion_inicio'].toString())
            : null,
        delegacionTemporalFin: row['delegacion_fin'] != null
            ? DateTime.tryParse(row['delegacion_fin'].toString())
            : null,
        puedeInvitarTerceros: row['puede_invitar_terceros'] == true,
        puedeVerApuAjena: row['puede_ver_apu_ajena'] == true,
      ),
    );
  }

  RolProyecto _rolDesdeColumna(String? valor) {
    switch (valor) {
      case 'admin_maestro':
        return RolProyecto.adminMaestro;
      case 'profesional':
        return RolProyecto.profesional;
      case 'constructor':
        return RolProyecto.constructor;
      case 'cliente_principal':
        return RolProyecto.clientePrincipal;
      case 'invitado_veedor':
        return RolProyecto.invitadoVeedor;
      case 'invitado_apoderado':
        return RolProyecto.invitadoApoderado;
      default:
        // Fallback más restrictivo posible ante un valor corrupto o desconocido:
        // nunca asumir un rol con más acceso del que corresponde.
        return RolProyecto.invitadoVeedor;
    }
  }
}
