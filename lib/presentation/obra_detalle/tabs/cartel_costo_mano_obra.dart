import 'package:flutter/material.dart';
import '../../../data/models/obra_presupuesto_config.dart';
import '../../../data/models/valor_hora_categoria.dart';
import '../../../services/obra_presupuesto_config_repository.dart';
import '../../../services/valor_hora_mano_obra_repository.dart';

/// Cartel de costo de mano de obra + tilde de cargas sociales — "Nivel 1" del Paso 5 (tanda 1, ver
/// docs/costo_mano_de_obra_decisiones.md §14). Vive arriba de la sección "Mano de obra" de
/// `MatYMoTab`, autocontenido (mismo patrón que `SelectorTipoPresupuesto`): carga su propia config
/// y su propio valor hora, sin depender del estado de la pantalla que lo contiene.
///
/// El panel de los 7 parámetros de cargas sociales (detrás del lapicito de cada fila de mano de
/// obra) es la tanda siguiente del Paso 5 — acá solo se leen esos 7 valores para el desglose, no
/// se editan.
class CartelCostoManoObra extends StatefulWidget {
  final String obraId;

  /// Se llama después de guardar el tilde de cargas sociales — el valor hora de mano de obra
  /// cambia con el toggle, así que el consolidado de `MatYMoTab` tiene que recargarse.
  final VoidCallback onCambio;

  const CartelCostoManoObra({Key? key, required this.obraId, required this.onCambio}) : super(key: key);

  @override
  State<CartelCostoManoObra> createState() => _CartelCostoManoObraState();
}

class _CartelCostoManoObraState extends State<CartelCostoManoObra> {
  final ObraPresupuestoConfigRepository _configRepository = ObraPresupuestoConfigRepository();
  final ValorHoraManoObraRepository _valorHoraRepository = ValorHoraManoObraRepository();

  bool _cargando = true;
  bool _expandido = false;
  ObraPresupuestoConfig? _config;
  ValorHoraCategoria? _ayud;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final configFuture = _configRepository.getConfig(widget.obraId);
    final valoresFuture = _valorHoraRepository.getValorHoraPorCategoria(widget.obraId);

    final config = await configFuture;
    final valores = await valoresFuture;
    if (!mounted) return;
    // AYUD es la categoría de referencia del cartel (ver docs/costo_mano_de_obra_decisiones.md
    // §14 para el motivo) — siempre presente, calcular_valor_hora_mano_obra devuelve las 5. Sin
    // package:collection (transitiva, no declarada en pubspec.yaml) para no repetir el mismo gap
    // que ya tiene intl en este proyecto.
    ValorHoraCategoria? ayud;
    for (final v in valores) {
      if (v.categoriaUocra == 'AYUD') {
        ayud = v;
        break;
      }
    }
    setState(() {
      _config = config;
      _ayud = ayud;
      _cargando = false;
    });
  }

  Future<void> _onCambiarCargasSociales(bool aplica) async {
    final actual = _config;
    if (actual == null || actual.aplicaCargasSociales == aplica) return;

    final actualizado = await _configRepository.actualizarAplicaCargasSociales(
      obraId: widget.obraId,
      aplicaCargasSociales: aplica,
    );
    if (!mounted) return;
    setState(() => _config = actualizado);
    widget.onCambio();
  }

  String _fmtPct(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2).replaceAll('.', ',');
  }

  String _fmtDosDecimales(double v) => v.toStringAsFixed(2).replaceAll('.', ',');

  @override
  Widget build(BuildContext context) {
    if (_cargando || _config == null || _ayud == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: SizedBox(
          height: 16,
          width: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final config = _config!;
    final ayud = _ayud!;
    final conCargas = config.aplicaCargasSociales;
    // X%: cuánto más caro es el modo con cargas contra el sin cargas — independiente del toggle,
    // por eso usa valorHoraConCargas/valorHoraSinCargas, nunca valorHora (que sí depende del modo).
    final diferenciaPct = ((ayud.valorHoraConCargas / ayud.valorHoraSinCargas - 1) * 100).round();
    // Aclaración acotada a AYUD (ver §14): si Oficial tiene override, su propia fila ya lo dice
    // con su marca — acá solo importa cuando la categoría que el cartel describe (AYUD) es la que
    // tiene el override, porque ahí el número del cartel y el de la fila de al lado divergen.
    final ayudTieneOverride = ayud.tieneOverride;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, size: 16, color: Color(0xFF1B365D)),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text('Costo de mano de obra', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
                const Text('Cargas sociales', style: TextStyle(fontSize: 11, color: Colors.black54)),
                Transform.scale(
                  scale: 0.75,
                  child: Switch(
                    value: conCargas,
                    onChanged: _onCambiarCargasSociales,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (conCargas) ...[
              const Text(
                'Los valores son costo empresa por hora, no jornal de bolsillo.',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text.rich(
                TextSpan(
                  style: const TextStyle(fontSize: 11, color: Colors.black87),
                  children: [
                    const TextSpan(
                      text: 'Incluye el básico UOCRA más las cargas sociales y contribuciones '
                          'patronales del empleador. Multiplicador: ',
                    ),
                    TextSpan(
                      text: 'aproximadamente ${_fmtDosDecimales(ayud.multiplicadorConCargas)}×',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ] else ...[
              const Text(
                'Modo sin cargas sociales.',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text.rich(
                TextSpan(
                  style: const TextStyle(fontSize: 11, color: Colors.black87),
                  children: [
                    const TextSpan(
                      text: 'Los valores muestran el básico de convenio sin las contribuciones '
                          'patronales. El costo real de un operario en relación de dependencia es '
                          'aproximadamente un ',
                    ),
                    TextSpan(
                      text: '$diferenciaPct%',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const TextSpan(
                      text: ' mayor. Si presupuestás en este modo, considerá cubrir esa diferencia '
                          'en Gastos Generales según tu criterio.',
                    ),
                  ],
                ),
              ),
            ],
            if (ayudTieneOverride) ...[
              const SizedBox(height: 4),
              const Text(
                'El multiplicador corresponde al valor calculado por la escala. El de Ayudante '
                'está fijado a mano, así que no surge de este cálculo.',
                style: TextStyle(fontSize: 10, color: Colors.black54, fontStyle: FontStyle.italic),
              ),
            ],
            const SizedBox(height: 4),
            InkWell(
              onTap: () => setState(() => _expandido = !_expandido),
              child: Text(
                _expandido ? '▾ Ocultar detalle' : '▸ Ver detalle',
                style: const TextStyle(fontSize: 11, color: Color(0xFF1B365D), fontWeight: FontWeight.w600),
              ),
            ),
            if (_expandido) ...[
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              // El detalle describe siempre la composición "con cargas" — es la referencia, esté
              // el toggle activo o no (ver §14: en modo sin cargas es justo lo más útil, no menos).
              const Text(
                'El valor hora se compone del básico del CCT 76/75 (UOCRA) vigente para la '
                'categoría y zona, con sus adicionales de convenio, más las contribuciones a cargo '
                'del empleador del régimen de la industria de la construcción (Ley 22.250 y su '
                'Decreto reglamentario 1342/81):',
                style: TextStyle(fontSize: 10, color: Colors.black87),
              ),
              const SizedBox(height: 6),
              _buildLineaDesglose(
                'Contribuciones patronales de seguridad social — art. 19, Ley 27.541',
                '${_fmtPct(config.sussPct)}%',
              ),
              _buildLineaDesglose(
                'Obra social patronal — Ley 23.660',
                '${_fmtPct(config.obraSocialPatronalPct)}%',
              ),
              _buildLineaDesglose(
                'Fondo de Cese Laboral — art. 15, Ley 22.250',
                '${_fmtPct(config.fondoCesePct)}%',
              ),
              _buildLineaDesglose(
                'Seguro de riesgos del trabajo (ART) — Ley 24.557',
                '${_fmtPct(config.artPct)}%',
              ),
              _buildLineaDesglose(
                'Contribución patronal al sindicato (UOCRA)',
                '${_fmtPct(config.uocraEmpleadorPct)}%',
              ),
              // El 4% de IERIC+FICS+FODECO se aplica sobre el Fondo de Cese, no sobre el
              // remunerativo como las otras 5 líneas — sumarlo crudo rompía el chequeo permanente
              // (la suma del desglose tiene que dar el multiplicador de arriba, ver
              // docs/costo_mano_de_obra_decisiones.md §14). Se muestra el impacto real sobre el
              // remunerativo (fondo_cese_pct × (fics+ieric+fodeco) / 100) como número principal —
              // el que sí suma — con el 4% reconocible entre paréntesis, sin que compita por ser
              // "el" número de la línea.
              _buildLineaDesglose(
                'IERIC, FICS y FODECO — art. 49 del CCT',
                '${_fmtPct(config.fondoCesePct * (config.ficsPct + config.iericPct + config.fodecoPct) / 100)}% '
                    '(equivale al ${_fmtPct(config.ficsPct + config.iericPct + config.fodecoPct)}% '
                    'aplicado sobre el Fondo de Cese)',
              ),
              const SizedBox(height: 8),
              const Text(
                'Los aportes que se le retienen al trabajador de su propio sueldo no están '
                'incluidos: no son un costo adicional para la empresa.',
                style: TextStyle(fontSize: 10, color: Colors.black87),
              ),
              const SizedBox(height: 6),
              const Text(
                'Las escalas salariales se actualizan por paritaria y las alícuotas por normativa. '
                'computoPRO no presta asesoramiento legal ni contable: verificá los valores '
                'vigentes con tu contador y la alícuota de tu póliza de ART.',
                style: TextStyle(fontSize: 10, color: Colors.black45, fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// [valorTexto] ya trae el "%" y cualquier aclaración (ver la línea de IERIC/FICS/FODECO) — no
  /// se le agrega nada acá, para poder mostrar un número acompañado de un paréntesis cuando hace
  /// falta sin romper el resto de las líneas, que son un porcentaje solo.
  Widget _buildLineaDesglose(String concepto, String valorTexto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  ', style: TextStyle(fontSize: 10, color: Colors.black54)),
          Expanded(
            child: Text(
              '$concepto — $valorTexto',
              style: const TextStyle(fontSize: 10, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}
