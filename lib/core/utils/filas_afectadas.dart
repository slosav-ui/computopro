import 'package:supabase_flutter/supabase_flutter.dart';

/// Con RLS, un UPDATE o DELETE que la política no deja pasar NO da error: afecta 0 filas, y la app
/// cree que guardó (el caso que ya pasó, docs/etapa3_roles_permisos_diseno_datos.md §10.4). Los
/// repositorios que escriben tablas protegidas piden las filas de vuelta (`.select()`) y pasan el
/// resultado por acá.
///
/// Lanza la misma `PostgrestException` que da la base cuando rechaza un INSERT (código 42501,
/// insufficient_privilege): cada pantalla ya muestra `e.message` en ese caso, así que el rechazo se
/// ve por el mismo camino, sin tocar ninguna. Antes, un `.single()` sobre 0 filas tiraba un error
/// genérico de PostgREST ("JSON object requested, multiple (or no) rows returned") que no decía
/// nada útil; y sin `.select()`, ni eso.
const String mensajeSinPermisoPresupuesto = 'No tenés permiso para editar el presupuesto de esta obra.';

void exigirFilasAfectadas(Object? filas, {String mensaje = mensajeSinPermisoPresupuesto}) {
  if (filas is! List || filas.isEmpty) {
    throw PostgrestException(message: mensaje, code: '42501');
  }
}

/// Igual que `exigirFilasAfectadas`, para un UPDATE de una sola fila que devuelve la fila
/// actualizada (reemplaza `.select().single()`).
Map<String, dynamic> filaAfectadaOSinPermiso(Object? filas, {String mensaje = mensajeSinPermisoPresupuesto}) {
  exigirFilasAfectadas(filas, mensaje: mensaje);
  return (filas as List).first as Map<String, dynamic>;
}
