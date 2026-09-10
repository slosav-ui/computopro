/// Nombre y teléfono de un usuario, tal como los devuelve `get_perfiles_de_obra` -- nunca
/// `es_pro`, que es estrictamente privado de cada uno (ver
/// `supabase/migrations/0099_perfiles_nombre_telefono.sql`). No es el perfil completo, es la
/// proyección mínima para mostrar "quién es quién" a un compañero de obra.
class PerfilBasico {
  final String usuarioId;
  final String? nombre;
  final String? telefono;

  const PerfilBasico({required this.usuarioId, this.nombre, this.telefono});

  factory PerfilBasico.fromRow(Map<String, dynamic> row) {
    return PerfilBasico(
      usuarioId: row['usuario_id'].toString(),
      nombre: (row['nombre'] as String?)?.trim().isEmpty == true ? null : row['nombre'] as String?,
      telefono: (row['telefono'] as String?)?.trim().isEmpty == true ? null : row['telefono'] as String?,
    );
  }
}
