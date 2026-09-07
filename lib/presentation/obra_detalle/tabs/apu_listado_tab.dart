import 'package:flutter/material.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/models/apu_precio_subitem.dart';
import '../../../data/models/rubro_catalogo.dart';
import '../../../data/models/subitem_catalogo.dart';
import '../../../services/apu_composiciones_repository.dart';
import '../../../services/obra_subitems_repository.dart';
import '../../../services/rubros_repository.dart';
import '../../../services/subitems_repository.dart';
import '../screens/composicion_apu_screen.dart';

/// Listado de la Solapa APU — "cuánto cuesta". Corrige la decisión original de esta pieza (ver
/// `docs/factor_k_apu_decisiones.md`, sección agregada 2026-09-07): se había decidido no armar un
/// listado propio acá "para no duplicar Rubros/Cómputo", entrando siempre desde ahí. El resultado
/// fue que la Solapa APU quedaba casi vacía y todo el trabajo de precios se hacía desde la solapa
/// equivocada. No es duplicación -- son dos vistas de la misma obra: Cómputo es cuánto hay
/// (cantidades), esto es cuánto cuesta (precios). Misma separación que la planilla real
/// (`PLANILLA_BASE_2_0_v3_CORREGIDA.ods`, hojas RUBROS y APU comunicadas por precio unitario).
///
/// Lista las partidas TILDADAS de la obra (`obra_subitems.es_aplicable = true`) que tienen precio
/// derivado de una composición de APU -- excluye a propósito los rubros de precio manual (1/18/19/20
/// y cualquier custom, `usaApu == false`) y los subítems propios (siempre precio manual, nunca
/// composición, ver `SubitemsScreen`): no tienen una `ComposicionApuScreen` a la que ir. Agrupado
/// por rubro, cada partida con su precio unitario -- tocarla abre la composición completa, la misma
/// pantalla a la que ya se llega desde Cómputo.
///
/// No es función PRO -- Free ve el listado y el precio unitario igual que PRO (mismo criterio que
/// ya vale en `ComposicionApuScreen`: la composición se ve, lo que es PRO es editarla y ver el
/// desglose del Factor K, ver `BloqueFactorKPartida`).
class ApuListadoTab extends StatefulWidget {
  final String obraId;

  const ApuListadoTab({Key? key, required this.obraId}) : super(key: key);

  @override
  State<ApuListadoTab> createState() => _ApuListadoTabState();
}

/// Un rubro con sus partidas tildadas-con-precio-de-APU, ya ordenadas.
class _GrupoRubro {
  final RubroCatalogo rubro;
  final List<SubitemCatalogo> subitems;

  _GrupoRubro(this.rubro, this.subitems);
}

class _ApuListadoTabState extends State<ApuListadoTab> {
  final ObraSubitemsRepository _obraSubitemsRepository = ObraSubitemsRepository();
  final SubitemsRepository _subitemsRepository = SubitemsRepository();
  final RubrosRepository _rubrosRepository = RubrosRepository();
  final ApuComposicionesRepository _apuComposicionesRepository = ApuComposicionesRepository();

  bool _cargando = true;
  String? _error;
  List<_GrupoRubro> _grupos = [];
  Map<String, ApuPrecioSubitem> _precios = {};

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final tildados = await _obraSubitemsRepository.getTildadosDeObra(widget.obraId);
      final subitemIds = [
        for (final t in tildados)
          if (t.subitemId != null) t.subitemId!,
      ];
      if (subitemIds.isEmpty) {
        if (!mounted) return;
        setState(() {
          _grupos = [];
          _precios = {};
          _cargando = false;
        });
        return;
      }

      final subitemsFuture = _subitemsRepository.getPorIds(subitemIds);
      final rubrosFuture = _rubrosRepository.getCatalogoOficial();
      final subitems = await subitemsFuture;
      final rubros = await rubrosFuture;
      final rubrosPorId = {for (final r in rubros) r.id: r};

      // Solo oficiales (los propios siempre son precio manual, nunca composición) de un rubro que
      // usa APU (los de precio manual no tienen composición a la que ir).
      final candidatos = subitems.where((s) {
        if (s.creadorUsuarioId != null) return false;
        final rubro = rubrosPorId[s.rubroId];
        return rubro != null && rubro.usaApu;
      }).toList();

      final conComposicion = candidatos.isEmpty
          ? <String>{}
          : await _apuComposicionesRepository.getSubitemIdsConComposicion(
              candidatos.map((s) => s.id).toList(),
            );
      final listados = candidatos.where((s) => conComposicion.contains(s.id)).toList();

      final precios = listados.isEmpty
          ? <String, ApuPrecioSubitem>{}
          : await _apuComposicionesRepository.calcularPreciosSubitems(
              widget.obraId,
              listados.map((s) => s.id).toList(),
            );

      final porRubro = <String, List<SubitemCatalogo>>{};
      for (final s in listados) {
        porRubro.putIfAbsent(s.rubroId, () => []).add(s);
      }
      final grupos = porRubro.entries
          .map((e) {
            final rubro = rubrosPorId[e.key]!;
            final subs = [...e.value]..sort((a, b) => _compararCodigoNatural(a.codigo, b.codigo));
            return _GrupoRubro(rubro, subs);
          })
          .toList()
        ..sort((a, b) => a.rubro.orden.compareTo(b.rubro.orden));

      if (!mounted) return;
      setState(() {
        _grupos = grupos;
        _precios = precios;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar el listado de precios.';
        _cargando = false;
      });
    }
  }

  int _compararCodigoNatural(String a, String b) {
    final segmentosA = a.split('.');
    final segmentosB = b.split('.');
    final largo = segmentosA.length < segmentosB.length ? segmentosA.length : segmentosB.length;
    for (var i = 0; i < largo; i++) {
      final numA = int.tryParse(segmentosA[i]);
      final numB = int.tryParse(segmentosB[i]);
      if (numA == null || numB == null) {
        final cmp = segmentosA[i].compareTo(segmentosB[i]);
        if (cmp != 0) return cmp;
        continue;
      }
      if (numA != numB) return numA.compareTo(numB);
    }
    return segmentosA.length.compareTo(segmentosB.length);
  }

  Future<void> _abrirComposicion(SubitemCatalogo subitem, ApuPrecioSubitem resultado) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ComposicionApuScreen(
          obraId: widget.obraId,
          subitemId: subitem.id,
          subitemCodigo: subitem.codigo,
          subitemDescripcion: subitem.descripcion,
          precioAgregado: resultado,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
        ),
      );
    }
    if (_grupos.isEmpty) {
      return RefreshIndicator(
        onRefresh: _cargarDatos,
        child: ListView(
          children: const [
            Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Todavía no hay partidas con precio de APU cargado. Tildá partidas en la solapa '
                'Cómputo (de un rubro con composición de APU) para que aparezcan acá.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _cargarDatos,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _grupos.length,
        itemBuilder: (context, index) => _buildGrupo(_grupos[index]),
      ),
    );
  }

  Widget _buildGrupo(_GrupoRubro grupo) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              grupo.rubro.nombre,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1B365D)),
            ),
            const Divider(height: 16),
            for (final subitem in grupo.subitems) _buildFila(subitem),
          ],
        ),
      ),
    );
  }

  Widget _buildFila(SubitemCatalogo subitem) {
    final resultado = _precios[subitem.id];
    final completo = resultado?.completo ?? false;
    return InkWell(
      onTap: resultado != null ? () => _abrirComposicion(subitem, resultado) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${subitem.codigo} - ${subitem.descripcion}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
            completo
                ? Text(
                    CurrencyFormatter.formatARS(resultado!.precioTotal),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1B365D)),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.info_outline, size: 12, color: Colors.orange[800]),
                      const SizedBox(width: 4),
                      Text(
                        'Incompleto',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange[800]),
                      ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }
}
