import 'package:flutter/material.dart';
import '../../../data/models/certificado_subitem_avance.dart';
import '../../../data/models/rubro_catalogo.dart';

/// **Avance certificado** de la obra: el porcentaje ponderado por monto, con el desglose por rubro
/// colapsable.
///
/// Cierra el punto 1 de `docs/gestion_obra_estado_real_auditoria.md` §2.1: la app venía calculando
/// esto desde la `0052` (`calcular_avance_ponderado_rubros`/`_obra`), lo tenía envuelto en
/// `CertificadoSubitemsAvanceRepository` y **ninguna pantalla lo mostraba**.
///
/// **Se llama "avance certificado" a propósito, no "avance de obra".**
/// `calcular_avance_acumulado_subitem` (`0052`, ampliada en `0056`) suma solo los certificados que ya
/// dejaron de ser borrador: lo que se esté cargando ahora mismo en el borrador **no cuenta**, y los
/// anulados tampoco. Decir "avance de obra" afirmaría algo que el número no sabe (criterio de Seba,
/// 2026-09-13).
///
/// **Ponderado por monto, no por cantidad de partidas**: un rubro de 8 millones pesa más que uno de
/// 200 mil, que es la única forma en que el porcentaje total significa algo.
///
/// Montos: el `montoPonderado` de cada rubro es plata, así que se muestra solo a quien ve montos en
/// Gestión de Obra (`puedeVerMontosGestionObra`). **El porcentaje se muestra siempre** — el avance
/// físico es lo único que la matriz de permisos le da al veedor desde la spec fundacional
/// (`docs/especificacion_funcional_3.md:404`), y esconderlo lo dejaría sin nada que mirar.
class PanelAvanceObra extends StatefulWidget {
  /// `null` mientras carga o si falló: el panel no se muestra (no hay avance que afirmar).
  final double? avanceObraPct;

  /// Desglose por rubro. Vacío = no se muestra el desglose, solo el total.
  final List<AvancePonderadoRubro> porRubro;

  /// Catálogo para resolver el nombre de cada rubro: la RPC devuelve `rubro_id` y nada más. Mismo
  /// patrón que `CargaAvanceRubrosScreen`, que ya resuelve los nombres así.
  final List<RubroCatalogo> catalogoRubros;

  /// `montoPonderado` solo para quien ve montos; el porcentaje, para todos.
  final bool mostrarMontos;

  /// Formateador de la pantalla que lo usa (convierte ARS a la moneda de la obra) — no se reimplementa
  /// acá, igual que el resto de los widgets de esta solapa.
  final String Function(double montoArs) fmtMonto;

  const PanelAvanceObra({
    super.key,
    required this.avanceObraPct,
    required this.porRubro,
    required this.catalogoRubros,
    required this.mostrarMontos,
    required this.fmtMonto,
  });

  @override
  State<PanelAvanceObra> createState() => _PanelAvanceObraState();
}

class _PanelAvanceObraState extends State<PanelAvanceObra> {
  bool _expandido = false;

  static const Color _azul = Color(0xFF1B365D);

  /// Los rubros sin ningún subítem con monto vienen con `avancePct` en null (el `nullif` del divisor
  /// en la `0052`): no son "0% de avance", son "nada que medir". No se listan.
  ///
  /// **Ordenados por el orden del rubro, no por porcentaje.** Ordenar por % armaría un ranking de "lo
  /// más avanzado primero", que se lee lindo y es inútil: en obra los rubros se recorren en su orden
  /// (1 Trabajos preliminares, 2 Movimiento de suelos, ...), y es el mismo orden que ya usan Cómputo y
  /// la pantalla de carga de avance. Que la lista cambie de orden entre pantallas es peor que
  /// cualquier ranking. Un rubro que no está en el catálogo del usuario va al final.
  List<AvancePonderadoRubro> get _rubrosConAvance {
    final orden = {
      for (var i = 0; i < widget.catalogoRubros.length; i++) widget.catalogoRubros[i].id: i,
    };
    return widget.porRubro.where((r) => r.avancePct != null).toList()
      ..sort((a, b) => (orden[a.rubroId] ?? 1 << 30).compareTo(orden[b.rubroId] ?? 1 << 30));
  }

  String _nombreRubro(String rubroId) {
    for (final r in widget.catalogoRubros) {
      if (r.id == rubroId) return '${r.codigo} · ${r.nombre}';
    }
    // Un rubro que no está en el catálogo del usuario: se muestra igual, sin nombre, en vez de
    // esconder el renglón y que el total no cierre con la suma.
    //
    // **El caso se achicó con la tanda 4** (docs/carpetas_importado_y_catalogo_diseno_datos.md
    // §5.1): desde que GestionObraTab pasa `obraId` a getCatalogoCompleto, los rubros de la carpeta
    // de esta obra SÍ vienen en el catálogo y se resuelven bien. Lo que queda cayendo acá es el
    // caso original: un rubro propio de OTRA persona, en el catálogo personal de ella, usado en una
    // obra compartida. Ese sigue sin resolverse por diseño -- el catálogo personal de cada uno es
    // suyo, y taparlo pediría una consulta aparte por membresía.
    return 'Rubro';
  }

  String _fmtPct(double pct) {
    final entero = pct == pct.roundToDouble();
    return '${entero ? pct.toStringAsFixed(0) : pct.toStringAsFixed(1)}%';
  }

  @override
  Widget build(BuildContext context) {
    final avance = widget.avanceObraPct;
    if (avance == null) return const SizedBox.shrink();
    final rubros = _rubrosConAvance;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Expanded(
                child: Text(
                  'Avance certificado',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54),
                ),
              ),
              Text(
                _fmtPct(avance),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _azul),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _BarraAvance(pct: avance),
          const SizedBox(height: 4),
          // Qué NO incluye: dicho una vez, acá, en vez de repetirlo en cada renglón del desglose.
          const Text(
            'Sobre el monto de cada partida. No incluye el borrador en curso.',
            style: TextStyle(fontSize: 9.5, color: Colors.black45),
          ),
          if (rubros.isNotEmpty) ...[
            const SizedBox(height: 6),
            InkWell(
              onTap: () => setState(() => _expandido = !_expandido),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _expandido ? 'Ocultar el detalle por rubro' : 'Ver el detalle por rubro',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _azul),
                    ),
                    Icon(_expandido ? Icons.expand_less : Icons.expand_more, size: 16, color: _azul),
                  ],
                ),
              ),
            ),
            if (_expandido)
              for (final r in rubros)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _nombreRubro(r.rubroId),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11, color: Colors.black87),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _fmtPct(r.avancePct!),
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: _azul),
                          ),
                        ],
                      ),
                      if (widget.mostrarMontos)
                        Text(
                          'Peso en la obra: ${widget.fmtMonto(r.montoPonderado)}',
                          style: const TextStyle(fontSize: 9.5, color: Colors.black45),
                        ),
                      const SizedBox(height: 3),
                      _BarraAvance(pct: r.avancePct!, alto: 4),
                    ],
                  ),
                ),
          ],
        ],
      ),
    );
  }
}

/// Barra de progreso propia y no `LinearProgressIndicator`: hace falta que el 0% y el 100% se lean
/// distinto del fondo y con el alto controlado, sin heredar el tema del Material.
class _BarraAvance extends StatelessWidget {
  final double pct;
  final double alto;

  const _BarraAvance({required this.pct, this.alto = 7});

  @override
  Widget build(BuildContext context) {
    // Clamp defensivo: el acumulado nunca debería pasar 100 (lo impide el candado de excesos de la
    // 0054), pero una barra pintada fuera de su caja sería un bug visual por un dato de más.
    final fraccion = (pct / 100).clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(alto),
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            Container(height: alto, width: constraints.maxWidth, color: Colors.black12),
            Container(
              height: alto,
              width: constraints.maxWidth * fraccion,
              color: fraccion >= 1 ? Colors.green.shade600 : const Color(0xFF1B365D),
            ),
          ],
        ),
      ),
    );
  }
}
