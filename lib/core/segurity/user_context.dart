// lib/core/segurity/user_context.dart

import '../../data/models/obra_member.dart';

/// Contexto de permisos de un usuario dentro de UNA obra puntual — ya no un
/// rol global (Etapa 3, paso 4). Se construye a partir de las filas de
/// obra_members del usuario en esa obra; roles combinables = varias filas.
/// Ver docs/etapa3_roles_permisos_diseno_datos.md para el diseño completo.
class UserContext {
  final String userId;
  final String obraId;
  final List<ObraMember> membresias; // ya filtradas a este usuario+obra+activas

  UserContext({
    required this.userId,
    required this.obraId,
    required this.membresias,
  });

  /// Construye el contexto filtrando, de todas las membresías conocidas, solo
  /// las de este usuario en esta obra que estén activas.
  factory UserContext.desdeObraMembers({
    required String userId,
    required String obraId,
    required List<ObraMember> todasLasMembresias,
  }) {
    final membresias = todasLasMembresias
        .where((m) => m.usuarioId == userId && m.obraId == obraId && m.activo)
        .toList();
    return UserContext(userId: userId, obraId: obraId, membresias: membresias);
  }

  List<RolProyecto> get roles => membresias.map((m) => m.rol).toList();

  bool _tieneAlgunRol(List<RolProyecto> buscados) =>
      membresias.any((m) => buscados.contains(m.rol));

  // Regla de visibilidad 1: ¿Puede ver valores financieros y APU? (Caja Blanca)
  bool get puedeVerMontosYAPU =>
      _tieneAlgunRol([RolProyecto.adminMaestro, RolProyecto.profesional]);

  // Regla de visibilidad 2: ¿Es vista estrictamente operativa sin dinero? (Constructor)
  // "Constructor puro": si la misma persona combina Constructor con un rol que
  // otorga visibilidad económica (ej. Cliente+Constructor), deja de aplicar —
  // es su propia obra, tiene que ver los montos.
  bool get esVistaOperativa =>
      _tieneAlgunRol([RolProyecto.constructor]) &&
      !_tieneAlgunRol([RolProyecto.adminMaestro, RolProyecto.profesional, RolProyecto.clientePrincipal]);

  // Regla de visibilidad 3: ¿Puede aprobar certificados de obra?
  // Admin Maestro y Cliente/Propietario Principal aprueban siempre (ver
  // "Matriz de permisos consolidada" en CLAUDE.md); el Apoderado solo dentro
  // de una delegación vigente.
  bool get puedeAprobarCertificados =>
      _tieneAlgunRol([RolProyecto.adminMaestro, RolProyecto.clientePrincipal]) ||
      membresias.any((m) =>
          m.rol == RolProyecto.invitadoApoderado &&
          m.permisosEspeciales.puedeAprobarCertificados &&
          _delegacionVigente(m));

  // Regla de visibilidad 4: ¿Puede tildar/destildar subitems y cargar
  // cantidades (obra_subitems)? Mismos dos roles que la política
  // INSERT/UPDATE de supabase/migrations/0019_obra_subitems.sql. No es lo
  // mismo que puedeVerMontosYAPU (esa regla es sobre visibilidad de $ y APU,
  // esta es sobre edición de cómputo métrico) aunque hoy coincidan los
  // mismos dos roles — no reusar una por la otra si en algún momento divergen.
  bool get puedeEditarComputo =>
      _tieneAlgunRol([RolProyecto.adminMaestro, RolProyecto.profesional]);

  // Regla de visibilidad 5: ¿puede editar la configuración de certificación de la obra (Modelo
  // A/B, plazo de pago, anticipo, fondo de reparo, carga inicial de monto total contratado)?
  // Solo admin_maestro, a propósito distinto de puedeEditarComputo/puedeVerMontosYAPU (que
  // incluyen a profesional) — la base sigue mirando obras.id_admin_creador para esto, no un rol
  // de obra_members (ver ObraConfigCertificacionRepository), así que este getter es la intención,
  // no la autoridad real: los dos coinciden hoy porque 0033_obra_members_bootstrap.sql sincroniza
  // al creador como admin_maestro al crear la obra, pero podrían divergir si alguna vez se agrega
  // un segundo admin_maestro que no sea también el id_admin_creador — ese usuario pasaría este
  // getter pero el guardado le fallaría igual contra la RLS real.
  bool get puedeEditarConfigCertificacion => _tieneAlgunRol([RolProyecto.adminMaestro]);

  // Regla de visibilidad 6: ¿puede crear/cargar el Borrador de un certificado? Verificado contra
  // las políticas certificados_insert (0009) y certificados_update (0010, la que rige hoy) tal
  // como quedaron aplicadas, no asumido: admin_maestro, profesional o constructor — es la posta
  // de carga de avance ("uno carga, se lo pasa al otro"), no la autoridad de emitir (esa sigue
  // siendo solo admin_maestro/profesional, verificada en emitir_certificado, 0011 — no hay getter
  // acá para eso porque la propia función ya la exige del lado del servidor).
  bool get puedeCargarAvance =>
      _tieneAlgunRol([RolProyecto.adminMaestro, RolProyecto.profesional, RolProyecto.constructor]);

  // Regla de visibilidad 7: ¿ve montos en Gestión de Obra (certificados, avance en pesos)? A
  // propósito NO reusa puedeVerMontosYAPU (esa es admin_maestro/profesional únicamente, pensada
  // para editar APU/Mat y MO — le ocultaría montos al Cliente, que según la matriz sí los ve:
  // "Caja Negra Comercial... certificados") ni la negación de esVistaOperativa (esa solo cubre al
  // Constructor puro — un Invitado Veedor sin rol constructor le daría esVistaOperativa = false,
  // y por matriz el Veedor tampoco ve montos, "Caja Negra Básica"). Lista positiva de quién sí ve,
  // no negación de quién no — admin_maestro/profesional/cliente_principal siempre,
  // invitado_apoderado solo con delegación vigente (mismo criterio que puedeAprobarCertificados,
  // extendido acá a la visibilidad, no solo a la aprobación — el resto de la matriz no distingue
  // explícitamente este caso, es una lectura razonable, no algo verificado literal en la spec).
  // Constructor y Veedor quedan afuera de la lista: ven porcentajes de avance, nunca pesos.
  bool get puedeVerMontosGestionObra =>
      _tieneAlgunRol([RolProyecto.adminMaestro, RolProyecto.profesional, RolProyecto.clientePrincipal]) ||
      membresias.any((m) => m.rol == RolProyecto.invitadoApoderado && _delegacionVigente(m));

  bool _delegacionVigente(ObraMember m) {
    final inicio = m.permisosEspeciales.delegacionTemporalInicio;
    final fin = m.permisosEspeciales.delegacionTemporalFin;
    if (inicio == null || fin == null) return false;
    final ahora = DateTime.now();
    return !ahora.isBefore(inicio) && !ahora.isAfter(fin);
  }

  // Sello de auditoría para trazabilidad de cambios en las obras
  String get auditLogSello =>
      'Usuario: $userId | Roles: ${roles.map((r) => r.name).join("+")} | Fecha: ${DateTime.now()}';
}
