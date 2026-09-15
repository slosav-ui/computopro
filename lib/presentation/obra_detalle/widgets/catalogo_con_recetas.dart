import 'package:flutter/material.dart';
import '../../../data/models/rubro_catalogo.dart';
import '../../../data/models/subitem_catalogo.dart';
import '../../../services/apu_composiciones_repository.dart';
import '../../../services/auth_service.dart';
import '../../../services/perfil_repository.dart';
import '../../../services/rubros_repository.dart';
import '../../../services/subitems_repository.dart';

/// Lo que muestran las solapas APU y Mat y MO cuando esta obra todavía no tiene nada que mostrar:
/// **el catálogo de partidas que sí tienen receta cargada**, en gris.
///
/// ---------------------------------------------------------------- por qué ESTO y no la obra
///
/// La primera versión de esta pieza mostraba en gris las partidas **de la obra**, para explicar el
/// vacío. Seba lo corrigió el 2026-09-15 y la corrección cambia el propósito entero:
///
/// > *"Muestra en gris las partidas importadas, que nunca van a tener APU. Eso no muestra nada. Lo
/// > que tiene que aparecer en gris es el catálogo de la app —las partidas oficiales con sus
/// > recetas— y las propias del PRO. Porque el punto no es explicar un vacío: es mostrar el
/// > potencial de la app. El que abre APU tiene que ver qué puede hacer."*
///
/// La diferencia no es de contenido, es de para qué existe la pantalla. Mostrar las partidas de una
/// obra importada era honesto y **completamente inútil**: son justamente las que nunca van a tener
/// composición, porque su precio ya viene cerrado del presupuesto. Explicaba mejor un vacío y no
/// ofrecía nada.
///
/// El catálogo con recetas sí ofrece: es lo que la app puede hacer y el usuario todavía no usó.
/// Y en Mat y MO el argumento es más fuerte todavía — **los insumos salen de las recetas, no de un
/// precio cerrado**, así que mostrar ahí partidas importadas apuntaba al lado contrario del que
/// genera insumos.
///
/// ---------------------------------------------------------------- cuándo desaparece
///
/// Solo. No hay lógica nueva para eso: las dos solapas muestran esto cuando su listado real está
/// vacío. **En cuanto el usuario tilda en Cómputo una partida del catálogo que tiene receta**, esa
/// partida entra en el listado de APU con su precio desglosado y sus insumos aparecen en Mat y MO,
/// y este cartel deja de mostrarse.
///
/// ---------------------------------------------------------------- las recetas propias
///
/// Una receta propia es un **clon por persona** de la oficial (`0071_personalizacion_apu_pro.sql`):
/// el PRO cambia un rendimiento o reemplaza un insumo sin tocar la de nadie más. Por eso viven
/// sobre el mismo subítem oficial y no como partidas aparte -- acá se marcan con un chip en vez de
/// listarse por separado.
class CatalogoConRecetas extends StatefulWidget {
  /// Qué hay acá y qué pasa al tildar una, dicho para esta solapa.
  final String mensaje;

  /// Se muestra solo a un usuario Free. A un PRO decirle que algo es PRO es ruido.
  final String notaPro;

  const CatalogoConRecetas({
    Key? key,
    required this.mensaje,
    required this.notaPro,
  }) : super(key: key);

  @override
  State<CatalogoConRecetas> createState() => _CatalogoConRecetasState();
}

class _GrupoCatalogo {
  final RubroCatalogo rubro;
  final List<SubitemCatalogo> partidas;

  const _GrupoCatalogo(this.rubro, this.partidas);
}

class _CatalogoConRecetasState extends State<CatalogoConRecetas> {
  final SubitemsRepository _subitemsRepository = SubitemsRepository();
  final RubrosRepository _rubrosRepository = RubrosRepository();
  final ApuComposicionesRepository _apuComposicionesRepository = ApuComposicionesRepository();
  final PerfilRepository _perfilRepository = PerfilRepository();
  final AuthService _authService = AuthService();

  bool _cargando = true;
  bool _esPro = true; // fail-safe: sin dato, no se muestra la nota PRO
  List<_GrupoCatalogo> _grupos = [];
  Set<String> _conRecetaPropia = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    if (mounted) setState(() => _cargando = true);
    try {
      final usuarioId = _authService.usuarioActual?.id;

      // **Sin `obraId` a propósito, en las dos consultas.** Acá se muestra el catálogo: lo oficial
      // más lo propio del usuario. La carpeta de la obra queda afuera por definición -- sus
      // partidas tienen precio cerrado y nunca tienen receta, que es exactamente el error que esta
      // versión corrige.
      final subitems = await _subitemsRepository.getTodos(usuarioId: usuarioId);
      final rubros = usuarioId == null
          ? await _rubrosRepository.getCatalogoOficial()
          : await _rubrosRepository.getCatalogoCompleto(usuarioId);

      final conReceta = await _apuComposicionesRepository.getSubitemIdsConComposicion(
        subitems.map((s) => s.id).toList(),
      );
      final propias = usuarioId == null
          ? <String>{}
          : await _apuComposicionesRepository.getSubitemIdsConRecetaPropia(usuarioId);
      final esPro = usuarioId == null ? true : await _perfilRepository.esPro(usuarioId);

      if (!mounted) return;
      setState(() {
        _grupos = _agrupar(subitems.where((s) => conReceta.contains(s.id)).toList(), rubros);
        _conRecetaPropia = propias;
        _esPro = esPro;
        _cargando = false;
      });
    } catch (e) {
      // Sin rama de error propia: este widget YA es el estado de "no hay nada que mostrar". Fallar
      // al traer el catálogo no justifica pisar la pantalla con un error -- queda el cartel solo,
      // que es lo que había antes de esta pieza.
      if (!mounted) return;
      setState(() {
        _grupos = [];
        _cargando = false;
      });
    }
  }

  List<_GrupoCatalogo> _agrupar(List<SubitemCatalogo> partidas, List<RubroCatalogo> rubros) {
    final rubrosPorId = {for (final r in rubros) r.id: r};
    final porRubro = <String, List<SubitemCatalogo>>{};
    for (final p in partidas) {
      porRubro.putIfAbsent(p.rubroId, () => []).add(p);
    }
    return porRubro.entries
        .where((e) => rubrosPorId.containsKey(e.key))
        .map((e) {
          final subs = [...e.value]..sort((a, b) => _compararCodigoNatural(a.codigo, b.codigo));
          return _GrupoCatalogo(rubrosPorId[e.key]!, subs);
        })
        .toList()
      ..sort((a, b) => a.rubro.orden.compareTo(b.rubro.orden));
  }

  /// "12.2" antes que "12.10": el código es jerárquico, no texto ni número.
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

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Center(child: CircularProgressIndicator());

    final propias = _grupos
        .expand((g) => g.partidas)
        .where((p) => _conRecetaPropia.contains(p.id))
        .length;
    final total = _grupos.fold<int>(0, (n, g) => n + g.partidas.length);

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.all(12),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _buildCartel(total, propias),
          const SizedBox(height: 12),
          for (final grupo in _grupos) _buildGrupo(grupo),
        ],
      ),
    );
  }

  /// Fondo ámbar suave y no un cartel de error: no hay nada roto ni nada que corregir. Es una
  /// invitación, y el tono de la UI es informativo, nunca de reproche.
  Widget _buildCartel(int total, int propias) {
    // El catálogo siempre trae recetas, así que 0 es un problema de carga, no un estado real.
    if (total == 0) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          widget.mensaje,
          style: const TextStyle(fontSize: 12, color: Colors.black87, height: 1.35),
        ),
      );
    }

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
          Icon(Icons.auto_awesome_outlined, size: 18, color: Colors.amber[800]),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.mensaje,
                  style: const TextStyle(fontSize: 12, color: Colors.black87, height: 1.35),
                ),
                const SizedBox(height: 6),
                Text(
                  propias > 0
                      ? '$total partidas con receta, $propias con tu versión.'
                      : '$total partidas con receta.',
                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                ),
                if (!_esPro) ...[
                  const SizedBox(height: 6),
                  Text(
                    widget.notaPro,
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
  /// partidas debajo) pero en gris. Que la estructura se reconozca es el punto: cuando el usuario
  /// tilde una de estas, lo que aparece es esto mismo con precio.
  ///
  /// **Inertes, no tocables.** Estas partidas no están en la obra: no hay una composición de ESTA
  /// obra que abrir. Un gris que se toca y no hace nada es peor que uno que se ve inerte.
  Widget _buildGrupo(_GrupoCatalogo grupo) {
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
              grupo.rubro.nombre,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey[700]),
            ),
            Divider(height: 16, color: Colors.grey[300]),
            for (final partida in grupo.partidas) _buildFila(partida),
          ],
        ),
      ),
    );
  }

  Widget _buildFila(SubitemCatalogo partida) {
    final propia = _conRecetaPropia.contains(partida.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 46,
            child: Text(partida.codigo, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          ),
          Expanded(
            child: Text(
              partida.descripcion,
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // El trabajo propio del PRO, visible. Es la mitad de "y las propias del PRO": sin esto,
          // una receta que el usuario ajustó se ve igual que una oficial que nunca tocó.
          if (propia) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.amber[100],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'tu receta',
                style: TextStyle(fontSize: 9, color: Colors.amber[900], fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
