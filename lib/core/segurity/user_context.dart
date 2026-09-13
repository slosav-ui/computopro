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

  // Regla de visibilidad 1: ¿Puede ver valores financieros y APU? (Caja Blanca) -- precios del
  // cómputo, Mat y MO con precios, la Solapa APU y el Factor K de la obra.
  //
  // CAMBIO DE MATRIZ (Seba, 2026-09-12): `constructor` pasa a ver montos igual que `profesional`.
  // El diseño lo había pensado como capataz ("vista operativa sin montos"), pero en el rubro
  // argentino el constructor es la empresa que cotiza y ejecuta -- textual: "es el que HACE EL
  // PRESUPUESTO. Nunca es el capataz -- el capataz es capataz". El rol le estaba ocultando montos
  // justamente a quien los armó. Ver docs/etapa3_roles_permisos_diseno_datos.md §8.
  //
  // Ver no es editar: los precios de la obra, el Factor K y la vista del presupuesto siguen siendo
  // de admin_maestro/profesional (`puedeEditarPreciosObra`, `puedeEditarComputo`), igual que en la
  // RLS. La receta personal de cada uno sigue siendo privada (APU por persona, `puede_ver_apu_ajena`)
  // -- eso no cambia.
  bool get puedeVerMontosYAPU =>
      _tieneAlgunRol([RolProyecto.adminMaestro, RolProyecto.profesional, RolProyecto.constructor]);

  // Regla de visibilidad 2: ¿no ve montos en ningún lado? Antes era "constructor puro" (vista
  // operativa); desde el cambio de matriz de arriba el constructor ya no es eso. Queda como la
  // negación de las dos reglas de montos: hoy, el invitado_veedor (y un apoderado sin delegación
  // vigente). Sin uso en pantallas al momento del cambio -- se deja coherente, no se borra.
  bool get esVistaOperativa => !puedeVerMontosYAPU && !puedeVerMontosGestionObra;

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

  // Regla de visibilidad 4-ter (0121, docs/etapa3_roles_permisos_diseno_datos.md §10): ¿puede
  // editar el presupuesto y firmar sus actos formales? Espejo EXACTO del helper SQL
  // `puede_editar_presupuesto(obra)`: admin_maestro siempre; profesional o constructor solo con el
  // permiso `puedeEditarPresupuesto` de su fila. "El rol define qué ves, el permiso qué editás."
  // Los getters de edición y actos formales de abajo se apoyan en esta regla -- un solo lugar, igual
  // que en la base.
  bool get puedeEditarPresupuesto =>
      _tieneAlgunRol([RolProyecto.adminMaestro]) ||
      membresias.any((m) =>
          (m.rol == RolProyecto.profesional || m.rol == RolProyecto.constructor) &&
          m.permisosEspeciales.puedeEditarPresupuesto);

  // ¿Puede otorgar o sacar `puedeEditarPresupuesto` a otro? Solo admin_maestro (0121, §10.6-3):
  // mismo chequeo que `invitaciones_insert`/`obra_members_insert`/`obra_members_update` para este
  // permiso. Getter propio aunque hoy coincida con `puedeOtorgarAdminMaestro`.
  bool get puedeOtorgarEditarPresupuesto => _tieneAlgunRol([RolProyecto.adminMaestro]);

  // Regla de visibilidad 4: ¿Puede tildar/destildar subitems y cargar cantidades (obra_subitems)?
  // Desde la 0121, el permiso de editar el presupuesto (políticas de 0019/0028). No es lo mismo que
  // puedeVerMontosYAPU: esa es qué ve, esta qué edita.
  bool get puedeEditarComputo => puedeEditarPresupuesto;

  // Regla de visibilidad 4-bis: ¿puede EDITAR los precios y la configuración económica de la obra
  // -- Factor K e impuestos, vista del presupuesto (con/sin materiales, impuestos), precio de un
  // insumo o valor hora en Mat y MO, precio desde la composición de APU? Mirroreada contra la RLS
  // real de esas tablas (`obra_presupuesto_config`/`obra_impuestos`, 0020; `obra_insumo_precios`,
  // 0030; `obra_valor_hora_override`, 0036) -- desde la 0121, el permiso de editar el presupuesto.
  // Separada de `puedeVerMontosYAPU` desde que el constructor ve montos (2026-09-12): ver no implica
  // editar, y sin este gate la app ofrecía controles que la base rechaza (o, en un UPDATE, ignora sin
  // error). Getter propio aunque hoy coincida con `puedeEditarComputo`: otras tablas.
  bool get puedeEditarPreciosObra => puedeEditarPresupuesto;

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
  // Veedor queda afuera de la lista: ve porcentajes de avance, nunca pesos. Constructor entra desde
  // el cambio de matriz (2026-09-12):
  // CAMBIO DE MATRIZ (Seba, 2026-09-12): `constructor` pasa a ver montos igual que `profesional`.
  // El diseño lo había pensado como capataz ("vista operativa sin montos"), pero en el rubro
  // argentino el constructor es la empresa que cotiza y ejecuta -- textual: "es el que HACE EL
  // PRESUPUESTO. Nunca es el capataz -- el capataz es capataz". El rol le estaba ocultando montos
  // justamente a quien los armó. Ver docs/etapa3_roles_permisos_diseno_datos.md §8.
  bool get puedeVerMontosGestionObra =>
      _tieneAlgunRol([
        RolProyecto.adminMaestro,
        RolProyecto.profesional,
        RolProyecto.constructor,
        RolProyecto.clientePrincipal,
      ]) ||
      membresias.any((m) => m.rol == RolProyecto.invitadoApoderado && _delegacionVigente(m));

  // Regla de visibilidad 8: ¿puede emitir un certificado (Borrador -> Emitido)? Espejo de
  // `emitir_certificado` (0121): el permiso de editar el presupuesto -- "si cotiza y ejecuta la obra,
  // es el que emite los certificados" (Seba). A propósito distinto de `puedeCargarAvance` (por rol:
  // cargar el borrador es tarea de posta, lo hace también quien no tiene el permiso).
  bool get puedeEmitirCertificado => puedeEditarPresupuesto;

  // Regla de visibilidad 9: ¿puede proponer o resolver (aprobar/rechazar) la anulación de un
  // certificado emitido? Espejo de proponer_anulacion_certificado/resolver_anulacion_certificado
  // (0121): profesional o constructor — la dupla que arma el borrador — Y con el permiso de editar
  // el presupuesto (anular es un acto formal, como emitir: §10.6-1). A propósito SIN admin_maestro
  // que no sea técnico y sin cliente_principal (el Cliente observa el error, no participa del
  // circuito). La regla de "nunca la misma persona en los dos lados" no se puede expresar acá
  // (depende de quién propuso una anulación puntual, no de los roles del usuario en general) — la
  // verifica la propia función del lado del servidor.
  bool get puedeGestionarAnulacionCertificado =>
      _tieneAlgunRol([RolProyecto.profesional, RolProyecto.constructor]) && puedeEditarPresupuesto;

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

  // Regla 14: ¿puede marcar un certificado como Impactado y Cerrado? El lado que cobra y cierra
  // administrativamente -- espejo de `marcar_certificado_impactado` (0121): el permiso de editar el
  // presupuesto (desde §9.5-C el profesional también cierra), nunca el Cliente.
  bool get puedeMarcarCertificadoImpactado => puedeEditarPresupuesto;

  // Regla de visibilidad 15: ¿puede aprobar/rechazar una Demasía o Quita? Mirroreada EXACTO contra
  // `puede_aprobar_quita_demasia` (0109), no contra `puedeGestionarAnulacionCertificado` (regla 9)
  // aunque hoy compartan el mismo par de roles -- son autoridades de circuitos distintos que no
  // tienen por qué seguir coincidiendo (mismo criterio que ya separó `puedeQuitarMiembros` de
  // `puedeOtorgarAdminMaestro`, regla 11-bis). A propósito SIN cliente_principal ni admin_maestro
  // que no sea técnico: "al propietario se le informa, no se le pide permiso" (docs/adicionales_
  // quitas_demasias_diagnostico.md §7-A/§6). Desde la 0121 además pide el permiso de editar el
  // presupuesto: aprobar cambia cantidades del cómputo y del congelado (§10.6-1). Solicitar sigue
  // siendo de cualquiera.
  bool get puedeAprobarQuitaDemasia =>
      _tieneAlgunRol([RolProyecto.profesional, RolProyecto.constructor]) && puedeEditarPresupuesto;

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
      _delegacionVigente(m);

  // Regla de visibilidad 17: ¿puede enviar (o reenviar) para aprobación un adicional presupuestado
  // con la app? En la base (`enviar_adicional_a_aprobacion`, 0121) es el permiso de editar el
  // presupuesto en la OBRA HIJA. Desde la madre eso es: tenerlo acá (el equipo, con sus permisos, se
  // copia a la hija, y se vuelve a copiar al enviar) o haber creado el adicional (el bootstrap de
  // 0033 lo hace admin_maestro de la hija aunque en la madre no edite -- §10.6-4, a propósito).
  bool puedeEnviarAdicional({required String solicitadoPor}) =>
      puedeEditarPresupuesto || solicitadoPor == userId;

  // Regla de visibilidad 18: ¿puede certificar avance de un adicional aprobado? Mirroreada contra
  // `certificar_avance_adicional` (0120): admin_maestro, profesional o constructor -- "certificar
  // avance no es emitir un certificado: es medir qué se hizo, y eso lo hace el que está en la obra"
  // (Seba, docs/adicionales_quitas_demasias_diagnostico.md §14.5-B). Getter propio aunque hoy
  // coincida con `puedeCargarAvance`: son circuitos distintos, pueden dejar de coincidir.
  bool get puedeCertificarAvanceAdicional =>
      _tieneAlgunRol([RolProyecto.adminMaestro, RolProyecto.profesional, RolProyecto.constructor]);

  // ÚNICO helper de delegación de la app, espejo EXACTO de la regla de la BASE (0004/0011/0116):
  // sin ninguna de las dos fechas = delegación permanente, vigente; con las dos, tiene que caer
  // dentro del rango; con una sola cargada, no vigente (en SQL `now() between inicio and fin` da
  // NULL, o sea falso, si falta una punta).
  //
  // Hasta 2026-09-13 convivían dos helpers: este (que ya usaban los adicionales) y uno viejo que
  // trataba "sin fechas" como NO vigente, que usaban los getters de certificados. Con el viejo, un
  // apoderado con delegación permanente no podía marcar Leído ni Pagado en la app aunque el
  // servidor sí lo autorizaba: la UI le escondía acciones que tenía. Se borró el viejo y quedó uno
  // solo para que la divergencia no pueda volver a aparecer.
  bool _delegacionVigente(ObraMember m) {
    final inicio = m.permisosEspeciales.delegacionTemporalInicio;
    final fin = m.permisosEspeciales.delegacionTemporalFin;
    if (inicio == null && fin == null) return true;
    if (inicio == null || fin == null) return false;
    final ahora = DateTime.now();
    return !ahora.isBefore(inicio) && !ahora.isAfter(fin);
  }

  // Sello de auditoría para trazabilidad de cambios en las obras
  String get auditLogSello =>
      'Usuario: $userId | Roles: ${roles.map((r) => r.name).join("+")} | Fecha: ${DateTime.now()}';
}
