/// Los 4 impuestos de una obra — ver `supabase/migrations/0020_obra_presupuesto_config.sql`
/// (tabla `obra_impuestos`) y `0079_obra_impuestos_nombre_otro_longitud.sql`. Siempre 4 filas por
/// obra, sembradas por trigger al crear la obra — este modelo nunca representa un alta ni una baja
/// de fila, solo lectura/edición de las 4 que ya existen (ver `PanelEditarImpuestos`: "uno solo, no
/// se borra" — el cuarto impuesto es la fila `otro`, reusada, nunca una fila nueva).
enum TipoImpuesto { iva, iibb, tasasMunicipales, otro }

extension TipoImpuestoDb on TipoImpuesto {
  String get valorDb {
    switch (this) {
      case TipoImpuesto.iva:
        return 'iva';
      case TipoImpuesto.iibb:
        return 'iibb';
      case TipoImpuesto.tasasMunicipales:
        return 'tasas_municipales';
      case TipoImpuesto.otro:
        return 'otro';
    }
  }
}

TipoImpuesto tipoImpuestoDesdeDb(String valor) {
  switch (valor) {
    case 'iva':
      return TipoImpuesto.iva;
    case 'iibb':
      return TipoImpuesto.iibb;
    case 'tasas_municipales':
      return TipoImpuesto.tasasMunicipales;
    case 'otro':
      return TipoImpuesto.otro;
    default:
      throw ArgumentError('Tipo de impuesto desconocido: $valor');
  }
}

class ObraImpuesto {
  final String id;
  final String obraId;
  final TipoImpuesto tipo;
  final String? nombreOtro; // solo tiene valor real cuando tipo == otro
  final double porcentaje;
  final int orden;

  const ObraImpuesto({
    required this.id,
    required this.obraId,
    required this.tipo,
    required this.porcentaje,
    required this.orden,
    this.nombreOtro,
  });

  /// Nombre para mostrar -- fijo para los 3 oficiales (mismo texto que ya usa el `case` de
  /// `calcular_factor_k_subitem` del lado SQL, no se repite un tercer lugar con estos nombres:
  /// acá y ahí, nada más), libre para el cuarto.
  String get nombre {
    switch (tipo) {
      case TipoImpuesto.iva:
        return 'IVA';
      case TipoImpuesto.iibb:
        return 'Ingresos Brutos';
      case TipoImpuesto.tasasMunicipales:
        return 'Tasas Municipales';
      case TipoImpuesto.otro:
        return nombreOtro ?? '';
    }
  }
}
