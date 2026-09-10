/// Nombre, teléfono y matrícula profesional de un usuario, tal como los devuelve
/// `get_perfiles_de_obra` -- nunca `es_pro`, que es estrictamente privado de cada uno (ver
/// `supabase/migrations/0099_perfiles_nombre_telefono.sql`/`0100_perfiles_matricula.sql`). No es
/// el perfil completo, es la proyección mínima para mostrar "quién es quién" a un compañero de
/// obra.
class PerfilBasico {
  final String usuarioId;
  final String? nombre;
  final String? telefono;
  final String? matricula;

  const PerfilBasico({required this.usuarioId, this.nombre, this.telefono, this.matricula});

  static String? _oNulo(dynamic valor) {
    final v = valor as String?;
    return (v == null || v.trim().isEmpty) ? null : v;
  }

  factory PerfilBasico.fromRow(Map<String, dynamic> row) {
    return PerfilBasico(
      usuarioId: row['usuario_id'].toString(),
      nombre: _oNulo(row['nombre']),
      telefono: _oNulo(row['telefono']),
      matricula: _oNulo(row['matricula']),
    );
  }
}
