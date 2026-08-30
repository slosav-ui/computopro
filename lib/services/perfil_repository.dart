import 'package:supabase_flutter/supabase_flutter.dart';

/// Acceso a la tabla `perfiles` de Supabase (flag Free/PRO, `es_pro`).
///
/// Ver `supabase/migrations/0014_perfiles.sql`: RLS solo `SELECT`, cada
/// usuario ve únicamente su propia fila. Sin política de escritura para el
/// usuario — `es_pro` cambia a mano vía SQL Editor hasta que exista un
/// sistema de pagos real, así que este repositorio es deliberadamente
/// solo-lectura.
class PerfilRepository {
  final SupabaseClient _client = Supabase.instance.client;

  /// Fail-closed a Free (`false`): si no hay fila (no debería pasar, hay
  /// trigger + backfill, pero por las dudas) o si la consulta falla por
  /// cualquier motivo, nunca se asume PRO ante una duda.
  Future<bool> esPro(String usuarioId) async {
    try {
      final row = await _client
          .from('perfiles')
          .select('es_pro')
          .eq('usuario_id', usuarioId)
          .maybeSingle();
      return row?['es_pro'] == true;
    } catch (e) {
      return false;
    }
  }
}
