import 'obra_member.dart';

/// Estado de una fila de `invitaciones` (ver `supabase/migrations/0095_invitaciones.sql`).
/// Las transiciones pasan siempre por `aceptar_invitacion`/`revocar_invitacion` — nunca por un
/// UPDATE directo, así que este enum es de solo lectura del lado de la app.
enum EstadoInvitacion { pendiente, aceptada, revocada }

EstadoInvitacion _estadoDesdeColumna(String? valor) {
  switch (valor) {
    case 'aceptada':
      return EstadoInvitacion.aceptada;
    case 'revocada':
      return EstadoInvitacion.revocada;
    default:
      return EstadoInvitacion.pendiente;
  }
}

/// Una invitación pendiente (o resuelta) a una obra — ver
/// `docs/invitaciones_diseno_datos.md`. Mismos campos que `PermisosEspeciales` de `ObraMember`
/// porque `aceptar_invitacion` los copia tal cual al crear la fila de `obra_members`.
class Invitacion {
  final String id;
  final String obraId;
  final RolProyecto rol;
  final PermisosEspeciales permisosEspeciales;
  final String codigo;
  final String invitadoPorUsuarioId;
  final EstadoInvitacion estado;
  final DateTime creadoAt;
  final DateTime expiraEn;
  final String? aceptadaPorUsuarioId;
  final DateTime? aceptadaEn;

  const Invitacion({
    required this.id,
    required this.obraId,
    required this.rol,
    required this.permisosEspeciales,
    required this.codigo,
    required this.invitadoPorUsuarioId,
    required this.estado,
    required this.creadoAt,
    required this.expiraEn,
    this.aceptadaPorUsuarioId,
    this.aceptadaEn,
  });

  bool get vigente => estado == EstadoInvitacion.pendiente && expiraEn.isAfter(DateTime.now());

  /// Traduce la fila cruda de la tabla (snake_case) — mismo criterio que
  /// `ObraMembersRepository._fromRow`: no reusa un `fromMap` de forma serializada de la app
  /// porque esta es la forma tal cual la devuelve Supabase.
  factory Invitacion.fromRow(Map<String, dynamic> row) {
    return Invitacion(
      id: row['id'].toString(),
      obraId: row['obra_id'].toString(),
      rol: rolDesdeColumna(row['rol']?.toString()),
      permisosEspeciales: PermisosEspeciales(
        puedeAprobarCertificados: row['puede_aprobar_certificados'] == true,
        puedeAprobarAdicionales: row['puede_aprobar_adicionales'] == true,
        topeMontoAprobacion: (row['tope_monto_aprobacion'] as num?)?.toDouble(),
        delegacionTemporalInicio: row['delegacion_inicio'] != null
            ? DateTime.tryParse(row['delegacion_inicio'].toString())
            : null,
        delegacionTemporalFin: row['delegacion_fin'] != null
            ? DateTime.tryParse(row['delegacion_fin'].toString())
            : null,
        puedeInvitarTerceros: row['puede_invitar_terceros'] == true,
        puedeVerApuAjena: row['puede_ver_apu_ajena'] == true,
      ),
      codigo: row['codigo'].toString(),
      invitadoPorUsuarioId: row['invitado_por_usuario_id'].toString(),
      estado: _estadoDesdeColumna(row['estado']?.toString()),
      creadoAt: DateTime.tryParse(row['creado_at']?.toString() ?? '') ?? DateTime.now(),
      expiraEn: DateTime.tryParse(row['expira_en']?.toString() ?? '') ?? DateTime.now(),
      aceptadaPorUsuarioId: row['aceptada_por_usuario_id']?.toString(),
      aceptadaEn: row['aceptada_en'] != null ? DateTime.tryParse(row['aceptada_en'].toString()) : null,
    );
  }
}

/// `rol` de `RolProyecto` <-> el texto de la columna. Sin `adminMaestro`: nunca es un rol
/// invitable (decisión cerrada, `docs/invitaciones_diseno_datos.md` §3 — la propia constraint
/// `check` de la tabla ya lo excluye, esto es solo la traducción del lado de Dart).
String columnaDesdeRol(RolProyecto rol) {
  switch (rol) {
    case RolProyecto.profesional:
      return 'profesional';
    case RolProyecto.constructor:
      return 'constructor';
    case RolProyecto.clientePrincipal:
      return 'cliente_principal';
    case RolProyecto.invitadoVeedor:
      return 'invitado_veedor';
    case RolProyecto.invitadoApoderado:
      return 'invitado_apoderado';
    case RolProyecto.adminMaestro:
      throw ArgumentError('admin_maestro no es un rol invitable.');
  }
}

RolProyecto rolDesdeColumna(String? valor) {
  switch (valor) {
    case 'profesional':
      return RolProyecto.profesional;
    case 'constructor':
      return RolProyecto.constructor;
    case 'cliente_principal':
      return RolProyecto.clientePrincipal;
    case 'invitado_apoderado':
      return RolProyecto.invitadoApoderado;
    case 'invitado_veedor':
    default:
      // Fallback más restrictivo posible ante un valor corrupto o desconocido — mismo criterio
      // que ObraMembersRepository._rolDesdeColumna: nunca asumir un rol con más acceso.
      return RolProyecto.invitadoVeedor;
  }
}

/// Etiqueta en español para mostrar en las pantallas de invitar/aceptar — un solo lugar para no
/// repetir el mismo `switch` en cada pantalla.
String etiquetaRol(RolProyecto rol) {
  switch (rol) {
    case RolProyecto.adminMaestro:
      return 'Administrador';
    case RolProyecto.profesional:
      return 'Profesional';
    case RolProyecto.constructor:
      return 'Constructor';
    case RolProyecto.clientePrincipal:
      return 'Cliente Principal';
    case RolProyecto.invitadoVeedor:
      return 'Invitado Veedor';
    case RolProyecto.invitadoApoderado:
      return 'Invitado Apoderado';
  }
}

/// Lo que devuelve `aceptar_invitacion` — no es una fila de `invitaciones` (esa la vuelve a leer
/// quien invitó, no quien acepta), es el resumen para mostrarle a quien se acaba de sumar.
class ResultadoInvitacionAceptada {
  final String obraId;
  final String obraNombre;
  final RolProyecto rol;

  const ResultadoInvitacionAceptada({
    required this.obraId,
    required this.obraNombre,
    required this.rol,
  });
}
