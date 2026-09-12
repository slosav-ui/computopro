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

  // Regla de visibilidad 8: ¿puede emitir un certificado (Borrador -> Emitido)? Verificado contra
  // el chequeo de autoridad real dentro de `emitir_certificado` (0011/0054), no asumido: solo
  // `admin_maestro`/`profesional` — a propósito distinto de `puedeCargarAvance` (que suma
  // `constructor`, porque cargar el borrador sí es tarea de posta entre los 3). Emitir es un paso
  // más restringido que cargar, con autoridad propia, no una extensión del mismo permiso.
  bool get puedeEmitirCertificado =>
      _tieneAlgunRol([RolProyecto.adminMaestro, RolProyecto.profesional]);

  // Regla de visibilidad 9: ¿puede proponer o resolver (aprobar/rechazar) la anulación de un
  // certificado emitido? Verificado contra proponer_anulacion_certificado/
  // resolver_anulacion_certificado (0056), no asumido: solo profesional o constructor — la dupla
  // que arma el borrador —, a propósito SIN admin_maestro (a diferencia de casi todos los demás
  // getters de acá) y sin cliente_principal (el Cliente observa el error, no participa del
  // circuito). La regla de "nunca la misma persona en los dos lados" no se puede expresar acá
  // (depende de quién propuso una anulación puntual, no de los roles del usuario en general) — la
  // verifica la propia función del lado del servidor.
  bool get puedeGestionarAnulacionCertificado =>
      _tieneAlgunRol([RolProyecto.profesional, RolProyecto.constructor]);

  // Regla de visibilidad 10: ¿puede invitar gente a la obra (generar un código de invitación)?
  // Mismo criterio que la política `invitaciones_insert` (`0095_invitaciones.sql`): admin_maestro,
  // o cualquier rol con `puedeInvitarTerceros` en `PermisosEspeciales` — a propósito no reusa
  // `puedeEditarComputo`/`puedeVerMontosYAPU`, porque invitar no depende de la caja blanca, sino
  // del permiso puntual que cada fila de `obra_members` trae.
  bool get puedeInvitarMiembros =>
      _tieneAlgunRol([RolProyecto.adminMaestro]) ||
      membresias.any((m) => m.permisosEspeciales.puedeInvitarTerceros);

  // Regla de visibilidad 11: ¿puede sacar a otro miembro de la obra (o revocar su/sus roles)?
  // Mismo criterio que quitar_miembro_obra (0098_quitar_miembro_obra.sql): solo admin_maestro --
  // a propósito más estricto que la RLS cruda de obra_members_update, que también deja que
  // cliente_principal toque filas de invitado_apoderado (gestión de delegación de firma, pieza
  // aparte, no la gestión general de miembros). No reusa puedeInvitarMiembros (esa suma
  // puede_invitar_terceros, que no alcanza para sacar gente -- son permisos independientes).
  bool get puedeQuitarMiembros => _tieneAlgunRol([RolProyecto.adminMaestro]);

  // Regla de visibilidad 11-bis: ¿puede nombrar a otro miembro como admin_maestro? Mismo cómputo
  // que puedeQuitarMiembros hoy (solo admin_maestro), getter propio a propósito -- son acciones
  // distintas (`otorgar_admin_maestro`/`quitar_miembro_obra`, `0108`) que hoy comparten la misma
  // autoridad pero no tienen por qué seguir coincidiendo si algún día una de las dos cambia.
  bool get puedeOtorgarAdminMaestro => _tieneAlgunRol([RolProyecto.adminMaestro]);

  // Reglas de visibilidad 12-14: cierre del ciclo del certificado (Leído/Pagado/Impactado, Gestión
  // de Obra pieza 5) — mirroreadas EXACTO contra la autoridad real del lado del servidor
  // (marcar_certificado_leido/pagado/impactado, 0011), no contra `puedeAprobarCertificados` (regla
  // 3, arriba): esa regla incluye `admin_maestro` porque su comentario cita la "Matriz de permisos
  // consolidada" de CLAUDE.md, pero `puede_gestionar_certificado` (la función real que usa
  // marcar_certificado_pagado) NUNCA incluye admin_maestro -- solo cliente_principal o
  // invitado_apoderado. Es un desajuste real entre lo documentado y lo que el servidor exige
  // (encontrado auditando Gestión de Obra, 2026-09-11) -- `puedeAprobarCertificados` queda sin
  // tocar (no la usa ninguna pantalla hoy, confirmado), pero estas 3 reglas nuevas no la reusan.

  // Regla 12: ¿puede marcar un certificado como Leído? Quien lo recibe -- cliente_principal
  // siempre, invitado_apoderado solo con delegación vigente (sin chequeo de
  // puede_aprobar_certificados ni de tope: leer no es un acto económico, mismo criterio que ya
  // cerró el diseño original, docs/certificados_ciclo_vida_diseno_datos.md §7).
  bool get puedeMarcarCertificadoLeido =>
      _tieneAlgunRol([RolProyecto.clientePrincipal]) ||
      membresias.any((m) => m.rol == RolProyecto.invitadoApoderado && _delegacionVigente(m));

  // Regla 13: ¿puede marcar un certificado como Pagado? Quien paga -- cliente_principal siempre,
  // invitado_apoderado solo con `puedeAprobarCertificados` (el flag de PermisosEspeciales, no esta
  // regla), delegación vigente, Y dentro de su tope de monto -- mismo chequeo exacto que
  // `puede_gestionar_certificado` (0011). Recibe el monto del certificado puntual porque el tope
  // es por certificado, no un booleano fijo de la obra.
  bool puedeMarcarCertificadoPagado(double monto) =>
      _tieneAlgunRol([RolProyecto.clientePrincipal]) ||
      membresias.any((m) =>
          m.rol == RolProyecto.invitadoApoderado &&
          m.permisosEspeciales.puedeAprobarCertificados &&
          (m.permisosEspeciales.topeMontoAprobacion == null ||
              monto <= m.permisosEspeciales.topeMontoAprobacion!) &&
          _delegacionVigente(m));

  // Regla 14: ¿puede marcar un certificado como Impactado y Cerrado? El lado de la
  // Empresa/Constructor que cobra y cierra administrativamente -- admin_maestro o constructor,
  // nunca el Cliente (mismo par que `marcar_certificado_impactado`, 0011).
  bool get puedeMarcarCertificadoImpactado =>
      _tieneAlgunRol([RolProyecto.adminMaestro, RolProyecto.constructor]);

  // Regla de visibilidad 15: ¿puede aprobar/rechazar una Demasía o Quita? Mirroreada EXACTO contra
  // `puede_aprobar_quita_demasia` (0109), no contra `puedeGestionarAnulacionCertificado` (regla 9)
  // aunque hoy compartan el mismo par de roles -- son autoridades de circuitos distintos que no
  // tienen por qué seguir coincidiendo (mismo criterio que ya separó `puedeQuitarMiembros` de
  // `puedeOtorgarAdminMaestro`, regla 11-bis). A propósito SIN cliente_principal ni admin_maestro:
  // "al propietario se le informa, no se le pide permiso" (docs/adicionales_quitas_demasias_
  // diagnostico.md §7-A/§6) -- el Cliente comenta vía `observar`, nunca aprueba.
  bool get puedeAprobarQuitaDemasia =>
      _tieneAlgunRol([RolProyecto.profesional, RolProyecto.constructor]);

  // Regla de visibilidad 16: ¿puede aprobar/rechazar un Adicional? Mirroreada EXACTO contra
  // `puede_aprobar_adicional`/`puede_rechazar_adicional` (0116): cliente_principal sin tope, o
  // invitado_apoderado con `puedeAprobarAdicionales` + delegación vigente (+ tope, solo al aprobar
  // -- rechazar no compromete plata). Nunca admin_maestro ni profesional: "si el profesional o el
  // administrador pueden aprobar un adicional, deja de ser una aprobación del que paga" (docs/
  // adicionales_quitas_demasias_diagnostico.md §7-B), sin excepción aunque la obra no tenga cliente
  // (§13.6-C). La base igual valida el tope contra el monto REAL, no contra este.
  bool get puedeRechazarAdicional =>
      _tieneAlgunRol([RolProyecto.clientePrincipal]) || membresias.any(_esApoderadoDeAdicionales);

  bool puedeAprobarAdicional(double monto) =>
      _tieneAlgunRol([RolProyecto.clientePrincipal]) ||
      membresias.any((m) =>
          _esApoderadoDeAdicionales(m) &&
          (m.permisosEspeciales.topeMontoAprobacion == null ||
              monto <= m.permisosEspeciales.topeMontoAprobacion!));

  bool _esApoderadoDeAdicionales(ObraMember m) =>
      m.rol == RolProyecto.invitadoApoderado &&
      m.permisosEspeciales.puedeAprobarAdicionales &&
      _delegacionVigenteSegunBase(m);

  // Regla de visibilidad 17: ¿puede enviar (o reenviar) para aprobación un adicional presupuestado
  // con la app? En la base (`enviar_adicional_a_aprobacion`, 0116) es admin_maestro/profesional de
  // la OBRA HIJA -- quienes cotizan. Desde la madre eso es: admin_maestro/profesional de acá (el
  // equipo se copia a la hija, y se vuelve a copiar al enviar) o quien creó el adicional (el
  // bootstrap de 0033 lo hace admin_maestro de la hija, tenga el rol que tenga en la madre).
  bool puedeEnviarAdicional({required String solicitadoPor}) =>
      puedeEditarComputo || solicitadoPor == userId;

  // La regla de la BASE para la delegación (0004/0011/0116): sin fechas = permanente, vigente; con
  // las dos fechas, dentro del rango; con una sola, no. Distinta de `_delegacionVigente` a propósito:
  // ese helper trata "sin fechas" como NO vigente -- divergencia anotada como pendiente aparte
  // (§13.4, afecta a certificados), así que los getters de adicionales no lo reusan. Cuando se
  // alinee el helper, se unifican.
  bool _delegacionVigenteSegunBase(ObraMember m) {
    final inicio = m.permisosEspeciales.delegacionTemporalInicio;
    final fin = m.permisosEspeciales.delegacionTemporalFin;
    if (inicio == null && fin == null) return true;
    if (inicio == null || fin == null) return false;
    final ahora = DateTime.now();
    return !ahora.isBefore(inicio) && !ahora.isAfter(fin);
  }

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
