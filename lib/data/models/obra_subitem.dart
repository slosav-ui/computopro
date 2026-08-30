/// Fila de la tabla `obra_subitems` (Supabase) — el cómputo métrico real de
/// una obra: qué subítem del catálogo está tildado, con qué cantidad.
/// Ver supabase/migrations/0019_obra_subitems.sql.
class ObraSubitem {
  final String id;
  final String obraId;
  final String rubroId;
  final String? subitemId; // null = fila OTRO (usa descripcionLibre en su lugar)
  final String? descripcionLibre;
  final String? sector;
  final double cantidad;
  final double? precioUnitarioManual; // null = deriva de APU
  final bool esAplicable; // destildar = false, nunca se borra la fila
  final String agregadoPorUsuarioId;
  final String? ultimaModificacionUsuarioId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ObraSubitem({
    required this.id,
    required this.obraId,
    required this.rubroId,
    this.subitemId,
    this.descripcionLibre,
    this.sector,
    required this.cantidad,
    this.precioUnitarioManual,
    required this.esAplicable,
    required this.agregadoPorUsuarioId,
    this.ultimaModificacionUsuarioId,
    required this.createdAt,
    required this.updatedAt,
  });
}
