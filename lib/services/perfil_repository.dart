import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/perfil_basico.dart';

/// Acceso a la tabla `perfiles` de Supabase (flag Free/PRO `es_pro`, y desde
/// `0099_perfiles_nombre_telefono.sql`, nombre/teléfono).
///
/// Ver `supabase/migrations/0014_perfiles.sql`: RLS solo `SELECT`, cada usuario ve únicamente su
/// propia fila -- eso no cambió. `es_pro` sigue sin ningún camino de escritura del lado del
/// usuario (cambia a mano vía SQL Editor hasta que exista un sistema de pagos real). Lo que sí
/// cambió: `nombre`/`telefono` tienen un camino de escritura acotado
/// (`actualizar_mi_perfil`, `SECURITY DEFINER`, solo esas dos columnas, nunca `es_pro`) y un
/// camino de lectura de OTRAS personas acotado a compañeros de obra (`get_perfiles_de_obra`,
/// nunca expone `es_pro`) -- ver el comentario de esa migración para el razonamiento completo.
class PerfilRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<T> _conLog<T>(String etiqueta, Future<T> Function() accion) async {
    try {
      return await accion();
    } on PostgrestException catch (e) {
      debugPrint(
        'PerfilRepository.$etiqueta falló (Postgrest) -- code=${e.code} message=${e.message} '
        'details=${e.details} hint=${e.hint}',
      );
      rethrow;
    } catch (e, st) {
      debugPrint('PerfilRepository.$etiqueta falló: $e\n$st');
      rethrow;
    }
  }

  /// Fail-closed a Free (`false`): si no hay fila (no debería pasar, hay
  /// trigger + backfill, pero por las dudas) o si la consulta falla por
  /// cualquier motivo, nunca se asume PRO ante una duda. Sin `_conLog` a propósito -- este
  /// método ya se llama en el camino caliente de cada pantalla que gatea PRO (ver
  /// `bloque_factor_k.dart`/`rubros_tab.dart`) y silenciar el error es la conducta deseada, no
  /// un descuido.
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

  /// Nombre propio (obligatorio en el formulario) y teléfono (opcional). Nunca toca `es_pro` --
  /// la función del lado del servidor ni lo acepta como parámetro.
  Future<void> actualizarMiPerfil({required String nombre, String? telefono}) {
    return _conLog('actualizarMiPerfil', () async {
      await _client.rpc('actualizar_mi_perfil', params: {
        'p_nombre': nombre,
        'p_telefono': telefono,
      });
    });
  }

  /// Mi propia fila completa (incluye `nombre`/`telefono` para precargar "Editar mi perfil") --
  /// a diferencia de `esPro`, sin fail-closed silencioso: quien llama a esto ya sabe que hay
  /// sesión activa y necesita el error real si algo falla.
  Future<PerfilBasico?> getMiPerfil(String usuarioId) {
    return _conLog('getMiPerfil', () async {
      final row = await _client
          .from('perfiles')
          .select('usuario_id, nombre, telefono')
          .eq('usuario_id', usuarioId)
          .maybeSingle();
      return row == null ? null : PerfilBasico.fromRow(row);
    });
  }

  /// Nombre/teléfono de los compañeros activos de una obra -- ver `get_perfiles_de_obra`
  /// (nunca expone `es_pro`, y falla si quien pregunta no es miembro de esa obra).
  Future<List<PerfilBasico>> getPerfilesDeObra(String obraId) {
    return _conLog('getPerfilesDeObra', () async {
      final data = await _client.rpc('get_perfiles_de_obra', params: {'p_obra_id': obraId});
      return (data as List).map((row) => PerfilBasico.fromRow(row as Map<String, dynamic>)).toList();
    });
  }
}
