/// Header de una importación de Excel/PDF/foto — fila de `importaciones`.
/// Ver supabase/migrations/0080_importaciones.sql y
/// docs/importador_capa1_diseno_datos.md / docs/importador_capa2_diseno_datos.md.
class Importacion {
  final String id;
  final String obraId;
  final String usuarioId;
  final String archivoNombre;
  final String archivoStoragePath;
  final String tipoArchivo; // 'excel' | 'pdf' | 'foto'
  final List<String> hojasSeleccionadas;
  final String? monedaDefault; // 'ARS' | 'USD' | null
  final String estado; // 'pendiente_revision' | 'confirmado' | 'descartado'
  final double? pctAvanceManual;
  final double? montoCertificadoManual;
  final String? confianzaGeneral;

  /// El total tal como figura IMPRESO en el documento (0146), no la suma de los ítems.
  ///
  /// Existe para contrastarlo contra esa suma. Es la única verificación del importador que **no se
  /// apoya en la misma lectura que está bajo sospecha**: si el modelo leyó mal una cantidad, la
  /// suma no va a dar el número del papel. null = el documento no traía total, y entonces esta
  /// verificación no está disponible (y la pantalla lo dice, en vez de callarse).
  final double? totalDeclarado;
  final DateTime createdAt;

  const Importacion({
    required this.id,
    required this.obraId,
    required this.usuarioId,
    required this.archivoNombre,
    required this.archivoStoragePath,
    required this.tipoArchivo,
    required this.hojasSeleccionadas,
    this.monedaDefault,
    required this.estado,
    this.pctAvanceManual,
    this.montoCertificadoManual,
    this.confianzaGeneral,
    this.totalDeclarado,
    required this.createdAt,
  });
}
