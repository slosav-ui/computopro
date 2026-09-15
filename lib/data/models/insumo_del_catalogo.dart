/// Una fila del catálogo de insumos con su precio de referencia — salida de
/// `catalogo_insumos_con_precio` (migración 0152).
///
/// Separado de `InsumoConsolidadoObra` a propósito: ese trae la cantidad que la obra necesita y el
/// precio que rige para esa obra (que puede ser uno cargado a mano). Este no sabe de ninguna obra —
/// es el catálogo tal como viene, para mostrar de qué dispone la app antes de que la obra tenga
/// nada cargado.
class InsumoDelCatalogo {
  final String id;
  final String nombre;
  final String unidad;
  final String tipo; // 'mano_obra' o material/equipo

  /// Promedio de lo que cotizan los corralones. `null` = todavía sin ningún precio cargado, que es
  /// distinto de cero y se muestra distinto.
  final double? precioPromedio;

  /// Cuántos precios promedia. Es la señal de confianza del dato: no es lo mismo un promedio de
  /// tres corralones que uno solo.
  final int cantidadPrecios;

  const InsumoDelCatalogo({
    required this.id,
    required this.nombre,
    required this.unidad,
    required this.tipo,
    required this.precioPromedio,
    required this.cantidadPrecios,
  });

  bool get esManoDeObra => tipo == 'mano_obra';
}
