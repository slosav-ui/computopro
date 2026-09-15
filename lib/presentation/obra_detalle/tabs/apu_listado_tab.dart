import 'package:flutter/material.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/models/apu_precio_subitem.dart';
import '../../../data/models/rubro_catalogo.dart';
import '../../../data/models/subitem_catalogo.dart';
import '../../../services/apu_composiciones_repository.dart';
import '../../../services/auth_service.dart';
import '../../../services/obra_subitems_repository.dart';
import '../../../services/rubros_repository.dart';
import '../../../services/subitems_repository.dart';
import '../screens/composicion_apu_screen.dart';
import '../widgets/cartel_vista_previa.dart';

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
  final AuthService _authService = AuthService();

  bool _cargando = true;
  String? _error;
  List<_GrupoRubro> _grupos = [];
  Map<String, ApuPrecioSubitem> _precios = {};

  /// `true` cuando lo que se está listando NO son las partidas de esta obra sino las del catálogo,
  /// para atenuarlas y explicar por qué (ver `cartel_vista_previa.dart`). Los grupos y los
  /// builders son los mismos -- lo único que cambia es de dónde salieron las partidas y que la fila
  /// no muestra precio, porque una partida que no está en la obra no tiene ninguno todavía.
  bool _vitrina = false;

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
        // Obra sin nada tildado: mismo tratamiento que obra con partidas pero sin análisis. Lo que
        // falta es lo mismo y lo que hay para mostrar también.
        final catalogo = await _gruposDelCatalogo();
        if (!mounted) return;
        setState(() {
          _grupos = catalogo;
          _precios = {};
          _vitrina = true;
          _cargando = false;
        });
        return;
      }

      final subitemsFuture = _subitemsRepository.getPorIds(subitemIds);
      // `getCatalogoOficial` alcanza y es lo correcto: solo un subítem oficial tiene composición,
      // así que los rubros de la carpeta de la obra (0151) y los propios no aportan nada acá --
      // sus partidas quedan filtradas por `usaApu` de todas formas.
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

      // Sin partidas propias con análisis, se lista el catálogo: las que SÍ tienen análisis
      // cargado, oficiales y propias del usuario. Se resuelve acá y no en un widget aparte para
      // que la pantalla que se muestra sea esta misma, con los mismos `_buildGrupo`/`_buildFila`.
      final vitrina = grupos.isEmpty;
      final gruposFinales = vitrina ? await _gruposDelCatalogo() : grupos;

      if (!mounted) return;
      setState(() {
        _grupos = gruposFinales;
        _precios = precios;
        _vitrina = vitrina;
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

  /// Las partidas del CATÁLOGO que ya tienen análisis cargado -- oficiales y propias del usuario --
  /// agrupadas por rubro igual que las de la obra.
  ///
  /// **Sin `obraId` en las dos consultas, a propósito**: acá se muestra el catálogo. La carpeta de
  /// la obra (0151) queda afuera por definición, porque sus partidas tienen precio cerrado y nunca
  /// tienen análisis -- listarlas sería mostrar justo lo que nunca va a llenar esta pantalla.
  Future<List<_GrupoRubro>> _gruposDelCatalogo() async {
    final usuarioId = _authService.usuarioActual?.id;
    final subitems = await _subitemsRepository.getTodos(usuarioId: usuarioId);
    if (subitems.isEmpty) return [];

    final rubros = usuarioId == null
        ? await _rubrosRepository.getCatalogoOficial()
        : await _rubrosRepository.getCatalogoCompleto(usuarioId);
    final rubrosPorId = {for (final r in rubros) r.id: r};

    final conAnalisis = await _apuComposicionesRepository.getSubitemIdsConComposicion(
      subitems.map((s) => s.id).toList(),
    );

    final porRubro = <String, List<SubitemCatalogo>>{};
    for (final s in subitems.where((s) => conAnalisis.contains(s.id))) {
      porRubro.putIfAbsent(s.rubroId, () => []).add(s);
    }
    return porRubro.entries
        .where((e) => rubrosPorId.containsKey(e.key))
        .map((e) {
          final subs = [...e.value]..sort((a, b) => _compararCodigoNatural(a.codigo, b.codigo));
          return _GrupoRubro(rubrosPorId[e.key]!, subs);
        })
        .toList()
      ..sort((a, b) => a.rubro.orden.compareTo(b.rubro.orden));
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
    // **Se bloquea la edición, no el desplazamiento.** La versión anterior envolvía todo en un
    // `IgnorePointer` y eso también se comía el scroll: se veía la primera pantalla del catálogo y
    // no se podía bajar, que es justo lo contrario de "recorrer el catálogo para ver qué trae la
    // app". Ahora el cartel es un ítem más de la lista, cada grupo se atenúa con `Opacity` (que no
    // toca el hit-test) y lo que no se puede tocar es el `onTap` de cada fila, apagado en
    // `_buildFila`.
    //
    // De paso desaparece el `Column` + `Expanded` que envolvía la lista, que era el desborde de 6.2
    // píxeles al pie: el alto de la lista ya no compite con el del cartel.
    final total = _grupos.fold<int>(0, (n, g) => n + g.subitems.length);

    return RefreshIndicator(
      onRefresh: _cargarDatos,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        // +1 por el cartel cuando corresponde. El cartel se descarta solo (devuelve un
        // SizedBox.shrink si ya lo cerraron), así que acá no hay que saber si está visible.
        itemCount: _grupos.length + (_vitrina ? 1 : 0),
        itemBuilder: (context, index) {
          if (_vitrina && index == 0) {
            return CartelVistaPrevia(
              obraId: widget.obraId,
              scope: 'apu',
              mensaje: 'Así se va a ver esta solapa. Estas son las partidas del catálogo que ya '
                  'tienen su análisis cargado: qué insumos llevan y en qué rendimiento. Tildá una '
                  'en la solapa Cómputo y aparece acá con su precio, desglosado paso a paso.',
              detalle: total > 0 ? '$total partidas con análisis, listas para usar.' : null,
              notaPro: 'Editar el análisis de una partida y crear los tuyos es una función PRO.',
            );
          }
          final grupo = _grupos[index - (_vitrina ? 1 : 0)];
          if (!_vitrina) return _buildGrupo(grupo);
          // `Opacity` sin `IgnorePointer`: atenúa sin bloquear el gesto de desplazar.
          return Opacity(opacity: 0.55, child: _buildGrupo(grupo));
        },
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
      // En vitrina no hay a dónde ir: la partida no está en esta obra, así que no hay una
      // composición de esta obra que abrir. **Y acá es donde se bloquea de verdad**: no hay ningún
      // IgnorePointer por encima, justamente para que la lista se pueda seguir desplazando.
      onTap: (resultado != null && !_vitrina) ? () => _abrirComposicion(subitem, resultado) : null,
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
            // En vitrina la columna de precio queda vacía, y no en "Incompleto": una partida del
            // catálogo que no está en la obra no tiene precio acá porque no fue tildada, no porque
            // le falte algo. Mostrar 97 renglones en naranja diciendo "Incompleto" sería lo
            // contrario de mostrar lo que la app puede hacer.
            if (!_vitrina)
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
