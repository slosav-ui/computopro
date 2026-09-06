/// Resultado de buscar un insumo existente en el catálogo (`InsumosRepository.buscarMateriales`) —
/// para el selector de "cambiar material" de la edición de APU. Deliberadamente separado del
/// `Insumo` viejo de `data/models/insumo.dart` (modelo en memoria pre-Supabase, con campos que no
/// coinciden con las columnas reales de `insumos` hoy) — este es chico a propósito, solo lo que el
/// selector necesita para mostrar y elegir.
class InsumoBusqueda {
  final String id;
  final String nombre;
  final String unidad;

  const InsumoBusqueda({
    required this.id,
    required this.nombre,
    required this.unidad,
  });
}
