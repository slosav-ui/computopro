import 'package:flutter/material.dart';
import '../../../data/models/rubro_catalogo.dart';
import '../../../data/models/subitem_catalogo.dart';
import '../../../services/apu_composiciones_repository.dart';
import '../../../services/auth_service.dart';
import '../../../services/obra_subitems_repository.dart';
import '../../../services/perfil_repository.dart';
import '../../../services/rubros_repository.dart';
import '../../../services/subitems_repository.dart';

/// El vacío de las solapas APU y Mat y MO, resuelto mostrando la estructura de la obra en gris.
///
/// **Criterio de Seba (2026-09-15), y no es cosmético:**
///
/// > *"Una solapa vacía parece rota; una con las partidas a la vista en gris se entiende sola y
/// > además muestra qué va a haber ahí."*
///
/// Reemplaza a un cartel suelto que, además de parecer una pantalla rota, daba una instrucción
/// imposible de seguir: *"tildá partidas en Cómputo (de un rubro con composición de APU)"*, en una
/// obra donde todas las partidas están tildadas y ninguna tiene composición. El cartel explicaba la
/// mecánica de la app en vez de explicar esta obra.
///
/// Con las partidas a la vista el vacío dice tres cosas de una: qué partidas tiene la obra, que la
/// app las conoce, y qué le falta a cada una para aparecer entera.
///
/// **Las partidas van atenuadas y no se tocan**: no hay a dónde ir. Un gris que se puede tocar y no
/// hace nada es peor que un gris que se ve inerte.
///
/// Dos piezas: `ListaPartidasAtenuadas` (presentacional, para quien ya tiene los datos cargados —
/// la solapa APU los tiene) y `PartidasAtenuadasDeLaObra` (se los trae solo — Mat y MO no los
/// tiene).

/// Un rubro con sus partidas, para el listado en gris. Nombres y códigos, nada más: acá no hay
/// precio que mostrar, que es justamente el punto.
class GrupoAtenuado {
  final String nombreRubro;
  final List<SubitemCatalogo> partidas;

  const GrupoAtenuado(this.nombreRubro, this.partidas);
}

/// Cartel + partidas en gris. Presentacional puro.
class ListaPartidasAtenuadas extends StatelessWidget {
  /// Qué falta y por qué, dicho sobre ESTA obra. No una instrucción genérica.
  final String mensaje;

  /// Se agrega al mensaje solo cuando el usuario es Free. A un PRO decirle que algo es función PRO
  /// es ruido.
  final String? notaPro;

  final List<GrupoAtenuado> grupos;
  final Future<void> Function() onRefresh;

  const ListaPartidasAtenuadas({
    Key? key,
    required this.mensaje,
    required this.grupos,
    required this.onRefresh,
    this.notaPro,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(12),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _buildCartel(),
          const SizedBox(height: 12),
          for (final grupo in grupos) _buildGrupo(grupo),
        ],
      ),
    );
  }

  /// Fondo ámbar suave y no un cartel de error: no hay nada roto ni nada que corregir. Es una
  /// explicación, y el tono de la UI es informativo, nunca de reproche.
  Widget _buildCartel() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber[200]!),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: Colors.amber[800]),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mensaje,
                  style: const TextStyle(fontSize: 12, color: Colors.black87, height: 1.35),
                ),
                if (notaPro != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    notaPro!,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.amber[900],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Misma forma que la tarjeta de un rubro con contenido real (Card, nombre arriba, divisor, las
  /// partidas debajo) pero en gris. Que la estructura se reconozca es el punto: cuando la obra
  /// tenga composiciones, lo que aparece acá es esto mismo con precio.
  Widget _buildGrupo(GrupoAtenuado grupo) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: Colors.grey[100],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey[300]!),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              grupo.nombreRubro,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey[700]),
            ),
            Divider(height: 16, color: Colors.grey[300]),
            for (final partida in grupo.partidas)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 46,
                      child: Text(
                        partida.codigo,
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        partida.descripcion,
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// La misma lista, trayéndose los datos por su cuenta: las partidas tildadas de la obra agrupadas
/// por rubro, sin las que ya tienen composición de APU.
///
/// Lo usa Mat y MO, que no tiene nada de esto cargado (su consolidado son insumos, no partidas). La
/// solapa APU no lo usa: ya tiene las partidas y los rubros en memoria, y pedirlos de nuevo sería
/// un viaje al servidor por nada.
class PartidasAtenuadasDeLaObra extends StatefulWidget {
  final String obraId;
  final String mensaje;
  final String? notaPro;

  /// Qué mostrar cuando la obra **no tiene ninguna partida tildada**. Ahí el vacío no es un vacío
  /// explicable: es una obra sin cómputo, y la instrucción de ir a Cómputo sí corresponde.
  final String mensajeSinPartidas;

  const PartidasAtenuadasDeLaObra({
    Key? key,
    required this.obraId,
    required this.mensaje,
    required this.mensajeSinPartidas,
    this.notaPro,
  }) : super(key: key);

  @override
  State<PartidasAtenuadasDeLaObra> createState() => _PartidasAtenuadasDeLaObraState();
}

class _PartidasAtenuadasDeLaObraState extends State<PartidasAtenuadasDeLaObra> {
  final ObraSubitemsRepository _obraSubitemsRepository = ObraSubitemsRepository();
  final SubitemsRepository _subitemsRepository = SubitemsRepository();
  final RubrosRepository _rubrosRepository = RubrosRepository();
  final ApuComposicionesRepository _apuComposicionesRepository = ApuComposicionesRepository();
  final PerfilRepository _perfilRepository = PerfilRepository();
  final AuthService _authService = AuthService();

  bool _cargando = true;
  bool _esPro = true; // fail-safe: sin dato, no se muestra la nota PRO
  List<GrupoAtenuado> _grupos = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    if (mounted) setState(() => _cargando = true);
    try {
      final usuarioId = _authService.usuarioActual?.id;
      final tildados = await _obraSubitemsRepository.getTildadosDeObra(widget.obraId);
      final ids = [
        for (final t in tildados)
          if (t.subitemId != null) t.subitemId!,
      ];

      final subitems = await _subitemsRepository.getPorIds(ids);
      // `obraId`: sin esto los rubros de la carpeta importada no resuelven y una obra traída de una
      // planilla mostraría un vacío igual de mudo que antes -- que es justo el caso que esto viene
      // a resolver.
      final rubros = usuarioId == null
          ? await _rubrosRepository.getCatalogoOficial()
          : await _rubrosRepository.getCatalogoCompleto(usuarioId, obraId: widget.obraId);
      final conComposicion = subitems.isEmpty
          ? <String>{}
          : await _apuComposicionesRepository.getSubitemIdsConComposicion(
              subitems.map((s) => s.id).toList(),
            );
      final esPro = usuarioId == null ? true : await _perfilRepository.esPro(usuarioId);

      if (!mounted) return;
      setState(() {
        _grupos = agruparPorRubro(
          subitems.where((s) => !conComposicion.contains(s.id)).toList(),
          rubros,
        );
        _esPro = esPro;
        _cargando = false;
      });
    } catch (e) {
      // Sin rama de error propia: este widget YA es el estado de "no hay nada que mostrar". Fallar
      // en cargar el adorno del vacío no justifica pisar la pantalla con un error -- queda el
      // cartel solo, que es lo que había antes de esta pieza.
      if (!mounted) return;
      setState(() {
        _grupos = [];
        _cargando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    return ListaPartidasAtenuadas(
      mensaje: _grupos.isEmpty ? widget.mensajeSinPartidas : widget.mensaje,
      notaPro: (_grupos.isEmpty || _esPro) ? null : widget.notaPro,
      grupos: _grupos,
      onRefresh: _cargar,
    );
  }
}

/// Agrupa partidas por rubro y ordena: los rubros por `orden`, las partidas por código natural
/// ("12.2" antes que "12.10", que un `compareTo` de texto pondría al revés).
///
/// Público a propósito: la solapa APU lo usa con los datos que ya tiene cargados.
List<GrupoAtenuado> agruparPorRubro(
  List<SubitemCatalogo> partidas,
  List<RubroCatalogo> rubros,
) {
  final rubrosPorId = {for (final r in rubros) r.id: r};
  final porRubro = <String, List<SubitemCatalogo>>{};
  for (final p in partidas) {
    porRubro.putIfAbsent(p.rubroId, () => []).add(p);
  }

  final grupos = porRubro.entries
      .where((e) => rubrosPorId.containsKey(e.key))
      .map((e) {
        final subs = [...e.value]..sort((a, b) => compararCodigoNatural(a.codigo, b.codigo));
        return (rubro: rubrosPorId[e.key]!, grupo: GrupoAtenuado(rubrosPorId[e.key]!.nombre, subs));
      })
      .toList()
    ..sort((a, b) => a.rubro.orden.compareTo(b.rubro.orden));

  return [for (final g in grupos) g.grupo];
}

/// "12.2" antes que "12.10". Mismo comparador que ya usaban ApuListadoTab y SubitemsRepository --
/// el código es jerárquico, no texto ni número.
int compararCodigoNatural(String a, String b) {
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
