import 'package:supabase_flutter/supabase_flutter.dart';

/// Acceso a la tabla `obras` de Supabase.
///
/// Traduce entre las columnas snake_case de la tabla y las claves
/// camelCase del `Map<String, dynamic>` que ya consume `ObrasListScreen`.
/// No incluye `montoEstimadoArs`/`montoEstimadoUsd`: esos son valores de
/// visualización que calcula la pantalla a partir de `montoTotal` + la
/// cotización activa, no se persisten.
class ObrasRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> getObras() async {
    final data = await _client.from('obras').select().order('created_at');
    return (data as List)
        .map((row) => _fromRow(row as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> crearObra(Map<String, dynamic> obra) async {
    final inserted = await _client
        .from('obras')
        .insert(_toRow(obra))
        .select()
        .single();
    return _fromRow(inserted);
  }

  Future<void> actualizarObra(String id, Map<String, dynamic> cambios) async {
    final row = _toRow(cambios);
    row['updated_at'] = DateTime.now().toIso8601String();
    await _client.from('obras').update(row).eq('id', id);
  }

  Future<void> eliminarObra(String id) async {
    await _client.from('obras').delete().eq('id', id);
  }

  Map<String, dynamic> _fromRow(Map<String, dynamic> row) {
    return {
      'id': row['id']?.toString() ?? '',
      'nombre': row['nombre']?.toString() ?? '',
      'propietario': row['propietario']?.toString() ?? '',
      'ubicacion': row['ubicacion']?.toString() ?? '',
      'tipoObra': row['tipo_obra']?.toString() ?? '',
      'tipoRol': row['perfil_creador']?.toString() ?? '',
      'montoTotal': (row['monto_total'] as num?)?.toDouble() ?? 0.0,
      'superficieM2': (row['superficie_m2'] as num?)?.toDouble() ?? 0.0,
      'estado': row['estado']?.toString() ?? 'Cotización',
      'moneda': row['moneda']?.toString() ?? 'ARS',
      'aplicaCac': row['aplica_cac'] == true,
      'mesBaseCac': row['mes_base_cac']?.toString() ?? 'N/A',
      'revision': row['revision']?.toString() ?? 'Rev. 00',
      'ultimaModif': row['updated_at'] ?? row['created_at'],
      'estadoServicioEspecial': row['estado_servicio_especial']?.toString() ?? 'Ninguno',
    };
  }

  Map<String, dynamic> _toRow(Map<String, dynamic> obra) {
    final row = <String, dynamic>{};
    if (obra.containsKey('nombre')) row['nombre'] = obra['nombre'];
    if (obra.containsKey('propietario')) row['propietario'] = obra['propietario'];
    if (obra.containsKey('ubicacion')) row['ubicacion'] = obra['ubicacion'];
    if (obra.containsKey('tipoObra')) row['tipo_obra'] = obra['tipoObra'];
    if (obra.containsKey('tipoRol')) row['perfil_creador'] = obra['tipoRol'];
    if (obra.containsKey('montoTotal')) row['monto_total'] = obra['montoTotal'];
    if (obra.containsKey('superficieM2')) row['superficie_m2'] = obra['superficieM2'];
    if (obra.containsKey('estado')) row['estado'] = obra['estado'];
    if (obra.containsKey('moneda')) row['moneda'] = obra['moneda'];
    if (obra.containsKey('aplicaCac')) row['aplica_cac'] = obra['aplicaCac'];
    if (obra.containsKey('mesBaseCac')) row['mes_base_cac'] = obra['mesBaseCac'];
    if (obra.containsKey('revision')) row['revision'] = obra['revision'];
    if (obra.containsKey('estadoServicioEspecial')) {
      row['estado_servicio_especial'] = obra['estadoServicioEspecial'];
    }
    return row;
  }
}
