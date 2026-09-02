/// Fila de `zonas_uocra` (ver supabase/migrations/0045_zonas_uocra_descripcion.sql) — catálogo
/// descriptivo de las zonas del CCT 76/75, separado de `escala_salarial_uocra` porque la
/// descripción es un dato por zona, no por fila de escala (que acumula una fila nueva por
/// categoría en cada paritaria — repetirla ahí la duplicaría 5 veces cada vez).
class ZonaUocra {
  final String codigo;
  final String nombre;
  final String descripcion;

  const ZonaUocra({required this.codigo, required this.nombre, required this.descripcion});

  /// "Zona B — Neuquén, Río Negro y Chubut" — lo que se muestra en pantalla, nunca el código solo.
  String get etiqueta => '$nombre — $descripcion';

  factory ZonaUocra.fromMap(Map<String, dynamic> map) {
    return ZonaUocra(
      codigo: map['codigo'] as String,
      nombre: map['nombre'] as String,
      descripcion: map['descripcion'] as String,
    );
  }
}
