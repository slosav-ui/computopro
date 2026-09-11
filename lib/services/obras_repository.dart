import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/certificado_subitem_avance.dart';

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
    // ascending: false explícito a propósito: obras más nuevas primero, orden
    // esperado para un dashboard de proyectos. No confundir con el default
    // engañoso de postgrest-dart (order() sin ascending es descendente salvo
    // que se pida ascending: true) — acá coincide con lo que se quiere, no es
    // el mismo bug que tenían rubros_repository.dart/certificados_repository.dart.
    final data = await _client
        .from('obras')
        .select()
        .order('created_at', ascending: false);
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

  /// Bug real encontrado por Seba (2026-09-11): cambiar la moneda de una obra a USD se veía
  /// aplicado en el dashboard (`setState` optimista) pero no sobrevivía a volver a entrar a la
  /// obra -- `_cargarObras()` releía `obras.moneda` = `'ARS'`. Causa: esta función hacía el
  /// `update` sin pedir la fila de vuelta (`.eq('id', id)` solo, sin `.select()`) -- si el `WHERE`
  /// después de aplicar RLS no matchea ninguna fila, PostgREST devuelve éxito igual (0 filas
  /// modificadas no es un error para PostgREST/RLS, mismo caso ya documentado en
  /// `actualizarMontoTotalContratadoInicial`, más abajo, que sí se armó con esta guarda desde el
  /// principio) -- el `await` nunca lanzaba, así que el catch de quien llama nunca se enteraba.
  /// Corregido con el mismo patrón: pedir la fila actualizada y lanzar si viene `null`. El
  /// `debugPrint` queda para poder ver el motivo real la próxima vez que esto (o algo parecido)
  /// vuelva a pasar, en vez de tener que adivinar entre RLS/id incorrecto/otra causa.
  Future<void> actualizarObra(String id, Map<String, dynamic> cambios) async {
    final row = _toRow(cambios);
    // updated_at lo mantiene un trigger de la base (0035_updated_at_trigger.sql),
    // no se manda desde acá.
    final Map<String, dynamic>? actualizada;
    try {
      actualizada = await _client.from('obras').update(row).eq('id', id).select().maybeSingle();
    } on PostgrestException catch (e) {
      debugPrint(
        'ObrasRepository.actualizarObra (Postgrest) -- id=$id cambios=$row code=${e.code} '
        'message=${e.message} details=${e.details} hint=${e.hint}',
      );
      rethrow;
    }
    if (actualizada == null) {
      debugPrint(
        'ObrasRepository.actualizarObra: 0 filas actualizadas para id=$id (cambios=$row) -- '
        'la obra no existe, o el usuario actual no tiene permiso de UPDATE sobre ella según RLS.',
      );
      throw StateError('No se pudo guardar -- no se encontró la obra o no tenés permiso para editarla.');
    }
  }

  Future<void> eliminarObra(String id) async {
    await _client.from('obras').delete().eq('id', id);
  }

  /// Presupuesto vivo de la obra -- suma de todas las partidas tildadas, cantidad × precio final,
  /// con la cascada de Factor K aplicada y respetando el selector de vista de esa obra (con/sin
  /// materiales). Ver `calcular_presupuesto_vivo_obra`, 0091_presupuesto_vivo_obra.sql. Siempre en
  /// ARS -- todo el sistema de precios (insumos, mano de obra) es en pesos, sin importar en qué
  /// moneda se haya dado de alta la obra; quien llama no tiene que convertir nada antes de usarlo.
  ///
  /// Sin cómputo cargado todavía (obra recién creada, o sin ninguna partida tildada), la función
  /// de base devuelve 0 -- no null, no excepción -- así que esto no necesita ningún caso especial.
  /// La moneda de la obra (`'ARS'`/`'USD'`) -- select acotado, no `getObras()`/`_fromRow()`
  /// completo. Para conversión de montos guardados en ARS, ver `core/utils/conversion_dolar.dart`.
  Future<String> getMoneda(String obraId) async {
    final row = await _client.from('obras').select('moneda').eq('id', obraId).single();
    return row['moneda']?.toString() ?? 'ARS';
  }

  Future<double> calcularPresupuestoVivo(String obraId) async {
    final data = await _client.rpc('calcular_presupuesto_vivo_obra', params: {'p_obra_id': obraId});
    return (data as num?)?.toDouble() ?? 0.0;
  }

  /// Estado del presupuesto para congelamiento/validez (Modelo A) -- ver
  /// docs/presupuesto_congelado_validez_modelo_a_diseno.md. Select acotado a estas columnas, no
  /// getObras()/_fromRow() completo -- el panel que consume esto se refresca solo después de cada
  /// acción, sin necesidad de recargar el resto de la fila de `obras`. `aplicaCac`/`cacSerie`
  /// sumados acá (no eran parte del diseño original) porque el panel los necesita para decidir si
  /// mostrar la sección de CAC ajustado -- ver docs/cac_conectado_modelo_a_diseno.md.
  Future<Map<String, dynamic>> getEstadoPresupuesto(String obraId) async {
    final row = await _client
        .from('obras')
        .select(
          'presupuesto_fecha_presentacion, presupuesto_validez_dias, presupuesto_congelado_en, '
          'aplica_cac, cac_serie',
        )
        .eq('id', obraId)
        .single();
    return {
      'fechaPresentacion': row['presupuesto_fecha_presentacion'] != null
          ? DateTime.parse(row['presupuesto_fecha_presentacion'] as String)
          : null,
      'validezDias': (row['presupuesto_validez_dias'] as num?)?.toInt() ?? 30,
      'congeladoEn': row['presupuesto_congelado_en'] != null
          ? DateTime.parse(row['presupuesto_congelado_en'] as String)
          : null,
      'aplicaCac': row['aplica_cac'] == true,
      'cacSerie': row['cac_serie']?.toString() ?? 'materiales_mano_obra',
    };
  }

  /// Arranca (o reinicia) la validez del presupuesto -- `presentar_presupuesto_obra`,
  /// `0103_presupuesto_validez_obra.sql`. Misma función para la primera presentación y para
  /// "Actualizar" uno vencido; la excepción de la base (sin autoridad, ya congelado con
  /// certificados emitidos, validez inválida) llega como `PostgrestException`, sin traducir acá --
  /// el mensaje ya viene en español, listo para mostrar.
  Future<void> presentarPresupuesto(String obraId, int validezDias) async {
    await _client.rpc('presentar_presupuesto_obra', params: {
      'p_obra_id': obraId,
      'p_validez_dias': validezDias,
    });
  }

  /// Congela cantidad y precio final de cada partida tildada -- `congelar_presupuesto_obra`,
  /// `0104_presupuesto_congelamiento_modelo_a.sql`. A partir de acá, Gestión de Obra certifica
  /// contra este número, no contra el precio en vivo. Mismas excepciones de negocio que arriba
  /// (vencido, sin presentar, recongelamiento con certificados ya emitidos) vía `PostgrestException`.
  Future<void> congelarPresupuesto(String obraId) async {
    await _client.rpc('congelar_presupuesto_obra', params: {'p_obra_id': obraId});
  }

  /// Suma de `presupuesto_subitems_congelado.monto_total` -- "lo que se firmó", sin ajuste de CAC.
  /// Consulta directa a la tabla (RLS ya acota a `is_obra_member`), no un RPC nuevo -- es una suma
  /// simple, no hace falta lógica de negocio del lado de la base para esto.
  Future<double> getMontoPactadoCongelado(String obraId) async {
    final rows = await _client
        .from('presupuesto_subitems_congelado')
        .select('monto_total')
        .eq('obra_id', obraId);
    return (rows as List).fold<double>(
      0.0,
      (suma, fila) => suma + ((fila['monto_total'] as num?)?.toDouble() ?? 0.0),
    );
  }

  /// Saldo pendiente de certificar, ya ajustado por CAC si la obra lo tiene activo --
  /// `calcular_saldo_pendiente_avance_medido`, `0104`/`0105`. `0` legítimo (obra sin congelar,
  /// o 100% ya certificado), nunca la señal de un error -- eso corta como excepción
  /// (`PostgrestException`), no devuelve `0` (`0106`).
  Future<double> calcularSaldoPendienteAvanceMedido(String obraId) async {
    final data = await _client.rpc(
      'calcular_saldo_pendiente_avance_medido',
      params: {'p_obra_id': obraId},
    );
    return (data as num?)?.toDouble() ?? 0.0;
  }

  /// Detalle por partida del ajuste de CAC -- `calcular_monto_congelado_ajustado`, `0105`/`0106`.
  /// Fuente para dos cosas distintas, en dos pantallas distintas: si alguna fila tiene
  /// `serieAplicada == 'sin_ajustar_indice_pendiente'` (el panel del presupuesto, aviso de índice
  /// base pendiente) y qué partidas tienen `fallbackGeneral == true` (carga de avance, marca de
  /// "esta partida se ajusta con el índice general"). Lista vacía para una obra sin congelar --
  /// legítimo, no un error.
  Future<List<MontoCongeladoAjustado>> getMontoCongeladoAjustado(String obraId) async {
    final data = await _client.rpc(
      'calcular_monto_congelado_ajustado',
      params: {'p_obra_id': obraId},
    );
    return (data as List).map((fila) {
      final row = fila as Map<String, dynamic>;
      return MontoCongeladoAjustado(
        obraSubitemId: row['obra_subitem_id'].toString(),
        montoTotal: (row['monto_total'] as num?)?.toDouble() ?? 0.0,
        serieAplicada: row['serie_aplicada']?.toString(),
        fallbackGeneral: row['fallback_general'] == true,
      );
    }).toList();
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
      'idAdminCreador': row['id_admin_creador']?.toString(),
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
    if (obra.containsKey('idAdminCreador')) row['id_admin_creador'] = obra['idAdminCreador'];
    return row;
  }
}
