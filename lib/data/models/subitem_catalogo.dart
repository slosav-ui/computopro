/// Fila de catálogo de la tabla `subitems` (Supabase) — sin cantidad/precio,
/// esos viven en `obra_subitems` (pieza siguiente a esta).
/// Ver supabase/migrations/0016_subitems.sql.
class SubitemCatalogo {
  final String id;
  final String rubroId;
  final String codigo;
  final String descripcion;
  final String unidad;
  final String? creadorUsuarioId; // null = catálogo oficial
  /// null = catálogo. No nulo = partida de esa obra. Puede colgar de un rubro
  /// del catálogo (partida suelta agregada solo para esta obra) pero nunca de
  /// un rubro de otra obra — ver el trigger de la migración 0151.
  final String? obraId;

  const SubitemCatalogo({
    required this.id,
    required this.rubroId,
    required this.codigo,
    required this.descripcion,
    required this.unidad,
    this.creadorUsuarioId,
    this.obraId,
  });

  bool get esDeCarpetaDeObra => obraId != null;
}
