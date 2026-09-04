import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/zona_uocra.dart';

/// Acceso de solo lectura a `escala_salarial_uocra` + `zonas_uocra` (ver
/// supabase/migrations/0036_escala_salarial_uocra_cargas_sociales.sql y
/// 0045_zonas_uocra_descripcion.sql). Se usa para el selector de zona del panel de mano de obra
/// (Paso 5, tanda 2 — ver docs/costo_mano_de_obra_decisiones.md §15): la app nunca deja escribir
/// una zona que no exista en `escala_salarial_uocra` — es la restricción de UI que vuelve
/// inalcanzable en uso normal el `RAISE EXCEPTION` de `calcular_valor_hora_mano_obra` (0039)
/// cuando `zona_uocra` no matchea ninguna fila.
class EscalaSalarialUocraRepository {
  final SupabaseClient _client = Supabase.instance.client;

  /// Zonas con escala realmente cargada (nunca todo `zonas_uocra` — esta lista es la que define
  /// qué puede elegir el selector, `zonas_uocra` es solo la descripción de las que ya están acá).
  Future<List<ZonaUocra>> getZonasDisponibles() async {
    final escalaData = await _client.from('escala_salarial_uocra').select('zona');
    final codigos = (escalaData as List).map((row) => row['zona'] as String).toSet();
    if (codigos.isEmpty) return [];
    final zonasData = await _client.from('zonas_uocra').select().inFilter('codigo', codigos.toList());
    final zonas = (zonasData as List).map((row) => ZonaUocra.fromMap(row as Map<String, dynamic>)).toList();
    zonas.sort((a, b) => a.codigo.compareTo(b.codigo));
    return zonas;
  }

  /// Catálogo completo de `zonas_uocra`, SIN filtrar por `escala_salarial_uocra` — a diferencia de
  /// [getZonasDisponibles], esto no sirve para poblar ningún selector (ofrecer acá una zona sin
  /// escala reabriría exactamente el bug que [getZonasDisponibles] evita). Uso único: el aviso de
  /// "hay otras zonas del convenio sin cargar" del cartel de costo de mano de obra
  /// (`CartelCostoManoObra`), que solo necesita comparar cuántas zonas hay en total contra cuántas
  /// tienen escala — nunca mostrar cuáles son.
  Future<int> getCantidadZonasEnCatalogo() async {
    final zonasData = await _client.from('zonas_uocra').select('codigo');
    return (zonasData as List).length;
  }
}
