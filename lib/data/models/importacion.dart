/// Header de una importación de Excel/PDF/foto — fila de `importaciones`.
/// Ver supabase/migrations/0080_importaciones.sql y
/// docs/importador_capa1_diseno_datos.md / docs/importador_capa2_diseno_datos.md.
class Importacion {
  final String id;
  final String obraId;
  final String usuarioId;
  final String archivoNombre;
  final String archivoStoragePath;
  final String tipoArchivo; // 'excel' | 'pdf' | 'foto' — esta ronda solo produce 'excel'
  final List<String> hojasSeleccionadas;
  final String? monedaDefault; // 'ARS' | 'USD' | null
  final String estado; // 'pendiente_revision' | 'confirmado' | 'descartado'
  final double? pctAvanceManual;
  final double? montoCertificadoManual;
  final String? confianzaGeneral;
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
    required this.createdAt,
  });
}
