// lib/core/security/user_context.dart

enum UserRole {
  adminMaestro,      // 100% Acceso (Caja Blanca)
  profesional,       // 100% Acceso (Caja Blanca)
  constructor,       // Vista Operativa (Sin montos, solo cargas de avance)
  clientePrincipal,  // Caja Negra Comercial (Totales por rubro, sin APU ni fórmulas)
  veedor,            // Lectura pasiva (Avances y fotos)
  apoderado          // Hereda vista del cliente con permisos de firma limitados
}

class UserContext {
  final String userId;
  final UserRole role;

  UserContext({
    required this.userId,
    required this.role,
  });

  // Regla de visibilidad 1: ¿Puede ver valores financieros y APU? (Caja Blanca)
  bool get puedeVerMontosYAPU {
    return [UserRole.adminMaestro, UserRole.profesional].contains(role);
  }

  // Regla de visibilidad 2: ¿Es vista estrictamente operativa sin dinero? (Constructor)
  bool get esVistaOperativa {
    return role == UserRole.constructor;
  }

  // Regla de visibilidad 3: ¿Puede aprobar certificados de obra?
  bool get puedeAprobarCertificados {
    return [UserRole.adminMaestro, UserRole.apoderado].contains(role);
  }

  // Sello de auditoría para trazabilidad de cambios en las obras
  String get auditLogSello {
    return "Usuario: $userId | Rol: ${role.name} | Fecha: ${DateTime.now()}";
  }
}