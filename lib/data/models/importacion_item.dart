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
  });

  bool get resuelta => rubroId != null && subitemId != null;
}
