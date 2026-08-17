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
