/// Defaults de los 7 parámetros de cargas sociales de `obra_presupuesto_config` — copia a mano de
/// los defaults reales de la columna, para el "por defecto X" del panel de "Ajustar cargas
/// sociales" (`PanelParametrosCargasSociales`). Se descartó leerlos en vivo del catálogo de
/// Postgres (una función `security definer` que evalúa expresiones de `pg_attrdef` era
/// desproporcionada para mostrar 6 números en una etiqueta) — mismo criterio que la escala
/// salarial UOCRA o FICS/IERIC/FODECO: dato que cambia poco y a mano. Ver
/// docs/costo_mano_de_obra_decisiones.md §15/§16.
///
/// IMPORTANTE: esto NO se actualiza solo. Toda migración futura que cambie un default de
/// `obra_presupuesto_config` con `alter column ... set default` tiene que actualizar también estas
/// constantes a mano, o el "por defecto X" del panel queda mostrando un valor viejo.
class CargasSocialesDefaults {
  CargasSocialesDefaults._();

  /// `obra_presupuesto_config.art_pct` — default original de `0036`, sin tocar desde entonces.
  static const double artPct = 10.23;

  /// `obra_presupuesto_config.fondo_cese_pct` — default original de `0036`, sin tocar desde
  /// entonces.
  static const double fondoCesePct = 12;

  /// `obra_presupuesto_config.suss_pct` — default original de `0036` (18 = con certificado
  /// MiPyME).
  static const double sussPct = 18;

  /// `obra_presupuesto_config.horas_mensuales` — `0036` lo puso en 176, `0046` lo cambió a 190.67.
  static const double horasMensuales = 190.67;

  /// `obra_presupuesto_config.horas_improductivas_mensuales` — `0036` lo puso en 14.41, `0046` lo
  /// cambió a 15.62.
  static const double horasImproductivasMensuales = 15.62;

  /// `obra_presupuesto_config.vacaciones_jornales_mes` — default original de `0037`, sin tocar
  /// desde entonces.
  static const double vacacionesJornalesMes = 1;

  /// `obra_presupuesto_config.zona_uocra` — default original de `0038`, sin tocar desde entonces.
  static const String zonaUocra = 'B';
}
