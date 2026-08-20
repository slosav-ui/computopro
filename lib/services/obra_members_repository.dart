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

  Future<List<ObraMember>> getMiembrosDeObra(String obraId) async {
    final data = await _client
        .from('obra_members')
        .select()
        .eq('obra_id', obraId)
        .eq('activo', true);
    return (data as List)
        .map((row) => _fromRow(row as Map<String, dynamic>))
        .toList();
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
