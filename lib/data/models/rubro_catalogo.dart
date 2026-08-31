/// Fila de catálogo de la tabla `rubros` (Supabase) — no confundir con `Rubro`
/// (instancia editable con subitems en memoria, sin persistencia real, que
/// sigue existiendo tal cual para cuando se diseñe el alta real).
/// Ver supabase/migrations/0015_rubros.sql.
class RubroCatalogo {
  final String id;
  final String codigo;
  final String nombre;
  final int orden;
  final bool usaApu;
  final String? tipoPrecioManual; // 'unitario' | 'global' | null (cuando usaApu == true)
  final String? creadorUsuarioId; // null = catálogo oficial
  final DateTime createdAt; // desempate de orden default para propios sin override en una obra,
                             // ver docs/rubros_orden_diseno_datos.md §3 (reemplaza a codigo).

  const RubroCatalogo({
    required this.id,
    required this.codigo,
    required this.nombre,
    required this.orden,
    required this.usaApu,
    required this.createdAt,
    this.tipoPrecioManual,
    this.creadorUsuarioId,
  });
}
