import 'obra_member.dart';

/// Los libros de `libro_entradas.libro` (0003). **La app usa uno solo: `obra`**, el libro de
/// comunicaciones de obra (cambio de alcance de Seba, 2026-09-14).
///
/// `ordenServicio` y `notaPedido` siguen existiendo en el check de la columna porque hay filas de
/// prueba con esos valores, pero **ninguna pantalla los escribe ni los muestra**. En obra la empresa
/// no responde adentro de la orden: contesta con una nota de pedido, que es otro libro — reproducir
/// ese ida y vuelta complicaba sin aportar, y el respaldo legal sigue siendo el libro rubricado en
/// papel. Ver docs/libro_obra_horizonte.md.
enum TipoLibro { obra, ordenServicio, notaPedido }

extension TipoLibroColumna on TipoLibro {
  /// El valor de la columna. **`name` no sirve**: da `ordenServicio` y la columna dice
  /// `orden_servicio` — el check constraint de la 0003 rechaza cualquier otra cosa.
  String get columna => switch (this) {
        TipoLibro.obra => 'obra',
        TipoLibro.ordenServicio => 'orden_servicio',
        TipoLibro.notaPedido => 'nota_pedido',
      };

  String get titulo => switch (this) {
        TipoLibro.obra => 'Libro de obra',
        TipoLibro.ordenServicio => 'Órdenes de Servicio',
        TipoLibro.notaPedido => 'Notas de Pedido',
      };
}

TipoLibro tipoLibroDesdeColumna(String? valor) => switch (valor) {
      'orden_servicio' => TipoLibro.ordenServicio,
      'nota_pedido' => TipoLibro.notaPedido,
      _ => TipoLibro.obra,
    };

/// Una entrada del libro de comunicaciones de obra.
///
/// **Append-only, y no por convención de la UI**: la RLS de la `0004` no tiene políticas de UPDATE
/// ni de DELETE, así que una entrada cargada no se edita ni se borra desde ningún lado.
///
/// Quién escribe (matriz de la `0004` corregida por la `0134`): admin_maestro, profesional y
/// constructor. **El cliente no escribe** — lee todo.
///
/// `entradaPadreId` existe en la tabla y **la app no lo usa**: la conversación es plana. Se conserva
/// por si algún día se agrega "responder citando"; el trigger de la `0137` ya protege ese caso.
class LibroEntrada {
  final String id;
  final String obraId;
  final TipoLibro libro;
  final String autorUsuarioId;

  /// Con qué rol firmó, que no es lo mismo que quién es: alguien con dos roles en la obra elige con
  /// cuál escribe, y eso queda registrado.
  final RolProyecto autorRol;

  final String contenido;
  final List<String> adjuntos;
  final String? entradaPadreId;
  final DateTime fechaCreacion;

  const LibroEntrada({
    required this.id,
    required this.obraId,
    required this.libro,
    required this.autorUsuarioId,
    required this.autorRol,
    required this.contenido,
    this.adjuntos = const [],
    this.entradaPadreId,
    required this.fechaCreacion,
  });

  /// Una fila de `libro_entradas` tal como la devuelve Supabase.
  ///
  /// Sin `numero`: la `0137` sacó la columna. *"Numerar cada mensaje de una conversación no aporta:
  /// la fecha y la firma ya dan el orden"* (Seba).
  factory LibroEntrada.desdeRow(Map<String, dynamic> row) {
    return LibroEntrada(
      id: row['id'].toString(),
      obraId: row['obra_id'].toString(),
      libro: tipoLibroDesdeColumna(row['libro']?.toString()),
      autorUsuarioId: row['autor_usuario_id'].toString(),
      autorRol: rolProyectoDesdeColumna(row['autor_rol']?.toString()),
      contenido: row['contenido']?.toString() ?? '',
      adjuntos: row['adjuntos'] == null
          ? const []
          : List<String>.from((row['adjuntos'] as List).map((a) => a.toString())),
      entradaPadreId: row['entrada_padre_id']?.toString(),
      fechaCreacion:
          DateTime.tryParse(row['created_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
    );
  }
}
