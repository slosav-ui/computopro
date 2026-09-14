/// Una fila extraída de una importación — fila de `importaciones_items`. Ver
/// supabase/migrations/0080_importaciones.sql / 0081_confirmar_importacion.sql y
/// docs/importador_capa2_diseno_datos.md §3.
///
/// `rubroId`/`subitemId` cargados = fila resuelta (acción "elegir del catálogo" o "crear como
/// propia"); ambos `null` = sin resolver o descartada — el diseño no distingue las dos a nivel de
/// base a propósito (docs/importador_capa2_diseno_datos.md §3), "descartar" no escribe nada, solo
/// decide no completarla nunca.
class ImportacionItem {
  final String id;
  final String importacionId;
  final int orden;
  final String? rubroTexto;
  final String? descripcionTexto;
  final String? unidadTexto;
  final double? cantidad;
  final double? precioUnitario;
  final String? moneda; // null = hereda importacion.monedaDefault
  final String? rubroId;
  final String? subitemId;

  /// 'alta' | 'media' | 'baja', o null.
  ///
  /// **null no quiere decir "no sé": quiere decir que nadie interpretó nada.** Es el camino del
  /// parser determinístico de Excel, donde una celda es una celda. Solo las filas que leyó un
  /// modelo traen confianza, porque solo esas pudieron leerse mal de forma plausible (0146).
  final String? confianza;

  /// La línea del documento tal como aparecía, cuando la leyó un modelo. Vive dentro de
  /// `datos_originales`, que existe desde la 0080 como respaldo de la fila cruda.
  ///
  /// Es lo que permite que la revisión compare lo interpretado contra el original sin volver al
  /// PDF: sin esto, "410,96" y "41096" se ven igual de creíbles en pantalla.
  final String? textoOriginal;

  const ImportacionItem({
    required this.id,
    required this.importacionId,
    required this.orden,
    this.rubroTexto,
    this.descripcionTexto,
    this.unidadTexto,
    this.cantidad,
    this.precioUnitario,
    this.moneda,
    this.rubroId,
    this.subitemId,
    this.confianza,
    this.textoOriginal,
  });

  bool get resuelta => rubroId != null && subitemId != null;

  /// Para ordenar la revisión: lo dudoso primero. Las filas sin confianza (Excel determinístico)
  /// van con las de confianza alta -- no son sospechosas, simplemente nadie las interpretó.
  int get ordenDeRevision {
    switch (confianza) {
      case 'baja':
        return 0;
      case 'media':
        return 1;
      default:
        return 2;
    }
  }

  ImportacionItem copyWith({
    String? descripcionTexto,
    String? unidadTexto,
    double? cantidad,
    double? precioUnitario,
  }) {
    return ImportacionItem(
      id: id,
      importacionId: importacionId,
      orden: orden,
      rubroTexto: rubroTexto,
      descripcionTexto: descripcionTexto ?? this.descripcionTexto,
      unidadTexto: unidadTexto ?? this.unidadTexto,
      cantidad: cantidad ?? this.cantidad,
      precioUnitario: precioUnitario ?? this.precioUnitario,
      moneda: moneda,
      rubroId: rubroId,
      subitemId: subitemId,
      confianza: confianza,
      textoOriginal: textoOriginal,
    );
  }
}
