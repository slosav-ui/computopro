/// Fila de `certificado_subitems_avance` — el % de avance cargado en UN certificado puntual para
/// UN subítem de la obra (no el acumulado, eso se calcula, ver
/// `CertificadoSubitemsAvanceRepository.getAcumuladoSubitem`).
/// Ver supabase/migrations/0052_certificado_subitems_avance.sql.
///
/// Apunta a `obra_subitems`, no al catálogo compartido de subítems — un mismo subítem puede
/// repetirse en distintos sectores de la misma obra, cada uno con su propio avance.
class CertificadoSubitemAvance {
  final String id;
  final String certificadoId;
  final String obraSubitemId;
  final double porcentajePeriodo;
  final double montoPeriodo; // snapshot server-side, ver el trigger de la 0052
  final String creadoPor;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CertificadoSubitemAvance({
    required this.id,
    required this.certificadoId,
    required this.obraSubitemId,
    required this.porcentajePeriodo,
    required this.montoPeriodo,
    required this.creadoPor,
    required this.createdAt,
    required this.updatedAt,
  });
}

/// Una línea del historial de avance de un subítem — su % en UN certificado puntual, con el
/// número, versión y estado de ese certificado para poder mostrarlo ("Certificado N°1 bis: 15%").
/// No es una fila de `certificado_subitems_avance` directa: junta esa tabla con `certificados`
/// (numero, version, estado), que `CertificadoSubitemAvance` no trae.
///
/// `versionCertificado`: sin esto, un certificado anulado y su reemplazo (mismo `numero`, ver
/// `resolver_anulacion_certificado`, 0056) eran indistinguibles acá -- las dos filas se mostraban
/// como "Certificado N°1", aunque una perteneciera al anulado y la otra a su corrección (hallazgo
/// de Seba, 2026-09-12). Usar junto con `Certificado.formatearNumero` para el mismo "1 bis"/"1 ter"
/// que ya muestra el resto de las pantallas de certificados.
class AvanceHistorialItem {
  final int numeroCertificado;
  final int versionCertificado;
  final String estadoCertificado;
  final double porcentajePeriodo;
  final double montoPeriodo;

  const AvanceHistorialItem({
    required this.numeroCertificado,
    required this.versionCertificado,
    required this.estadoCertificado,
    required this.porcentajePeriodo,
    required this.montoPeriodo,
  });
}

/// Monto real de un `obra_subitems` en la obra — salida de `calcular_monto_obra_subitems` (0052).
class MontoObraSubitem {
  final String obraSubitemId;
  final double montoTotal;
  final bool tienePrecioCompleto;

  const MontoObraSubitem({
    required this.obraSubitemId,
    required this.montoTotal,
    required this.tienePrecioCompleto,
  });
}

/// Monto de una partida congelada, ya ajustado por CAC si corresponde — salida de
/// `calcular_monto_congelado_ajustado` (`0105`/`0106`). `serieAplicada`: `null` (obra sin CAC
/// activo, `montoTotal` es el pactado tal cual), `'general'`/`'materiales_mano_obra'`/
/// `'mano_obra'` (ajuste aplicado normalmente), o `'sin_ajustar_indice_pendiente'` (el índice del
/// mes de congelamiento todavía no se publicó — `montoTotal` es el pactado sin ajustar, hasta que
/// aparezca). `fallbackGeneral`: esta partida puntual cayó al índice general aunque la obra eligió
/// separar series (rubro de precio manual, o sin ningún insumo con precio al congelar).
class MontoCongeladoAjustado {
  final String obraSubitemId;
  final double montoTotal;
  final String? serieAplicada;
  final bool fallbackGeneral;

  const MontoCongeladoAjustado({
    required this.obraSubitemId,
    required this.montoTotal,
    required this.serieAplicada,
    required this.fallbackGeneral,
  });
}

/// Avance ponderado de un rubro — salida de `calcular_avance_ponderado_rubros` (0052).
class AvancePonderadoRubro {
  final String rubroId;
  final double? avancePct; // null si el rubro no tiene ningún subítem con monto (nullif del divisor)
  final double montoPonderado;

  const AvancePonderadoRubro({
    required this.rubroId,
    required this.avancePct,
    required this.montoPonderado,
  });
}

/// "Certificado y pagado a la fecha" de una obra — para el resumen chico de la pantalla de carga
/// de avance. No sale de ninguna función SQL nueva: es una suma simple sobre `certificados`, se
/// calcula en el repositorio.
class ResumenCertificadoObra {
  final double totalCertificado; // suma de monto de certificados que ya dejaron de ser borrador
  final double totalPagado; // suma de monto_neto_a_pagar de los certificados pagados/cerrados

  const ResumenCertificadoObra({
    required this.totalCertificado,
    required this.totalPagado,
  });
}

/// El desglose completo de un certificado — salida de `calcular_totales_certificado` (0054). La
/// misma cuenta que la vista previa muestra antes de emitir y que `emitir_certificado` congela:
/// no se recalcula en Dart, se lee de acá en los dos lugares.
class TotalesCertificado {
  final double monto;
  final double? anticipoPct;
  final double? fondoReparoPct;
  final double montoAnticipo;
  final double montoFondoReparo;
  final double montoNeto;
  final int? diasPlazoPago;
  // Desglose pactado/ajuste CAC (0105) -- montoPactado + montoAjusteCac = monto, siempre. 0 en
  // montoAjusteCac para cualquier obra sin CAC activo o sin congelar -- no hace falta distinguir
  // esos dos casos acá, la UI solo se pregunta si hay algo que mostrar (!= 0).
  final double montoPactado;
  final double montoAjusteCac;

  const TotalesCertificado({
    required this.monto,
    required this.anticipoPct,
    required this.fondoReparoPct,
    required this.montoAnticipo,
    required this.montoFondoReparo,
    required this.montoNeto,
    required this.diasPlazoPago,
    required this.montoPactado,
    required this.montoAjusteCac,
  });
}

/// Un subítem de este borrador que excede el 100% acumulado — salida de
/// `calcular_excesos_certificado` (0054). Misma cuenta que bloquea `emitir_certificado`, mostrada
/// antes de intentar emitir en vez de recién al fallar.
class ExcesoCertificado {
  final String obraSubitemId;
  final String descripcion;
  final double acumuladoPrevio;
  final double disponible;
  final double intentado;

  const ExcesoCertificado({
    required this.obraSubitemId,
    required this.descripcion,
    required this.acumuladoPrevio,
    required this.disponible,
    required this.intentado,
  });
}
