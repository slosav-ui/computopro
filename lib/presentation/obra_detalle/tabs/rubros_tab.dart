import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../../../data/models/obra_model.dart';
import '../../../data/models/rubro_catalogo.dart';
import '../../../services/rubros_repository.dart';
import '../../../services/subitems_repository.dart';
import '../../../services/obra_subitems_repository.dart';
import '../../../services/perfil_repository.dart';
import '../../../services/auth_service.dart';
import '../../shared/pro_gate_dialog.dart';
import '../screens/subitems_screen.dart';

class RubrosTab extends StatefulWidget {
  final ObraModel? obra;
  final String obraId;
  final bool puedeEditarComputo;

  const RubrosTab({
    Key? key,
    this.obra,
    required this.obraId,
    required this.puedeEditarComputo,
  }) : super(key: key);

  @override
  State<RubrosTab> createState() => _RubrosTabState();
}

class _RubrosTabState extends State<RubrosTab> {
  final RubrosRepository _rubrosRepository = RubrosRepository();
  final SubitemsRepository _subitemsRepository = SubitemsRepository();
  final ObraSubitemsRepository _obraSubitemsRepository = ObraSubitemsRepository();
  final PerfilRepository _perfilRepository = PerfilRepository();
  final AuthService _authService = AuthService();

  List<RubroCatalogo> _catalogo = [];
  // Indicador "N de M tildados" por rubro (ver diagnóstico: sin monto real
  // todavía, unit-agnostic, no depende de APU/precio_unitario_manual).
  Map<String, int> _totalPorRubro = {};
  Map<String, int> _tildadosPorRubro = {};
  bool _cargando = true;
  String? _error;

  // Fail-closed a Free hasta que se resuelva la consulta real (ver
  // PerfilRepository.esPro) — el botón "Nuevo Rubro" queda deshabilitado
  // mientras _cargando es true, así que no llega a mostrarse con este
  // default incorrecto.
  bool _esPro = false;

  @override
  void initState() {
    super.initState();
    _cargarCatalogo();
  }

  Future<void> _cargarCatalogo() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final usuarioId = _authService.usuarioActual?.id;
      final rubros = usuarioId != null
          ? await _rubrosRepository.getCatalogoCompleto(usuarioId)
          : await _rubrosRepository.getCatalogoOficial();
      final esPro = usuarioId != null ? await _perfilRepository.esPro(usuarioId) : false;
      final totales = await _subitemsRepository.getConteoOficialPorRubro();
      final tildados = await _obraSubitemsRepository.getConteoTildadosPorObra(widget.obraId);
      if (!mounted) return;
      setState(() {
        _catalogo = rubros;
        _esPro = esPro;
        _totalPorRubro = totales;
        _tildadosPorRubro = tildados;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar el catálogo de rubros.';
        _cargando = false;
      });
    }
  }

  /// Refresca solo los dos mapas de conteo (no el catálogo entero) al volver
  /// de SubitemsScreen — tildar/destildar ahí deja el "N de M" desactualizado
  /// si no se refresca. Falla en silencio: un conteo desactualizado no
  /// amerita interrumpir con un SnackBar, se corrige solo en el próximo
  /// pull-to-refresh o reingreso a la pantalla.
  Future<void> _cargarConteos() async {
    try {
      final totales = await _subitemsRepository.getConteoOficialPorRubro();
      final tildados = await _obraSubitemsRepository.getConteoTildadosPorObra(widget.obraId);
      if (!mounted) return;
      setState(() {
        _totalPorRubro = totales;
        _tildadosPorRubro = tildados;
      });
    } catch (e) {
      // silencioso, ver doc del método.
    }
  }

  @override
  Widget build(BuildContext context) {
    final ObraModel? obra = widget.obra;

    return Column(
      children: [
        if (obra != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.blueGrey[50],
            child: Row(
              children: [
                const Icon(Icons.architecture, size: 18, color: Color(0xFF1B365D)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${obra.nombre} • ${obra.propietario} (${obra.tipoObra})',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1B365D)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        // Siempre visible, para PRO y para Free (Free ve el diálogo de
        // función PRO al tocarlo, ver _onNuevoRubro — no se oculta la
        // función, mismo criterio que el resto del spec Free/PRO).
        // RubrosTab no es un Scaffold (vive dentro del TabBarView de
        // PresupuestosScreen), así que va como fila propia en vez de un
        // floatingActionButton.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: _cargando ? null : _onNuevoRubro,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Nuevo Rubro'),
              style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1B365D)),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _cargarCatalogo,
            child: _buildContenido(),
          ),
        ),
      ],
    );
  }

  Widget _buildContenido() {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                Icon(Icons.error_outline, color: Colors.red.shade400, size: 32),
                const SizedBox(height: 8),
                Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
              ],
            ),
          ),
        ],
      );
    }
    if (_catalogo.isEmpty) {
      return ListView(
        children: const [
          Padding(
            padding: EdgeInsets.all(24.0),
            child: Text(
              'No hay rubros en el catálogo todavía.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12.0),
      itemCount: _catalogo.length,
      itemBuilder: (context, index) {
        final rubro = _catalogo[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8.0),
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: ListTile(
            title: Text(
              '${rubro.codigo} - ${rubro.nombre}',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1B365D), fontSize: 14),
            ),
            subtitle: rubro.usaApu
                ? null
                : Text(
                    'Precio manual (${rubro.tipoPrecioManual})',
                    style: const TextStyle(color: Colors.black54, fontSize: 11),
                  ),
            // Un rubro propio hoy siempre tiene 0 subitems en catálogo (no
            // existe todavía UI para agregarle subitems custom), así que
            // _buildConteoBadge devolvería null de cualquier forma — el
            // chip "Propio" ocupa ese lugar en vez de convivir con el N/M.
            // Revisar cuando exista esa UI y un rubro propio sí tenga
            // subitems.
            trailing: rubro.creadorUsuarioId != null
                ? _buildChipPropio()
                : _buildConteoBadge(rubro),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SubitemsScreen(
                    rubro: rubro,
                    obraId: widget.obraId,
                    puedeEditarComputo: widget.puedeEditarComputo,
                  ),
                ),
              );
              await _cargarConteos();
            },
          ),
        );
      },
    );
  }

  /// "N de M" tildados en esta obra, para ese rubro. `null` (sin badge) si
  /// el rubro todavía no tiene subitems en el catálogo — evita mostrar un
  /// confuso "0/0" en un rubro custom recién creado (ver Etapa A).
  Widget? _buildConteoBadge(RubroCatalogo rubro) {
    final total = _totalPorRubro[rubro.id] ?? 0;
    if (total == 0) return null;
    final tildados = _tildadosPorRubro[rubro.id] ?? 0;
    final trabajado = tildados > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: trabajado ? Colors.green[50] : Colors.grey[200],
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$tildados/$total',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: trabajado ? Colors.green[800] : Colors.black45,
        ),
      ),
    );
  }

  Widget _buildChipPropio() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.amber[50],
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.amber[700]!),
      ),
      child: Text(
        'Propio',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber[900]),
      ),
    );
  }

  void _onNuevoRubro() {
    if (_esPro) {
      _mostrarDialogoAltaRubro();
    } else {
      mostrarDialogoFuncionPro(
        context,
        mensaje: 'Crear tus propios rubros (para lo que el catálogo no cubre — '
            'piscina, ascensor, paisajismo, etc.) es una función PRO.',
      );
    }
  }

  void _mostrarDialogoAltaRubro() {
    final codigoCtrl = TextEditingController();
    final nombreCtrl = TextEditingController();
    // Declaradas fuera del builder: StatefulBuilder vuelve a ejecutar su
    // builder en cada setModalState, así que una variable local ahí adentro
    // se resetearía a su valor inicial en cada rebuild.
    bool guardando = false;
    String? error;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setModalState) {
          Future<void> guardar() async {
            final codigo = codigoCtrl.text.trim();
            final nombre = nombreCtrl.text.trim();
            if (codigo.isEmpty || nombre.isEmpty) {
              setModalState(() => error = 'Completá código y nombre.');
              return;
            }
            final usuarioId = _authService.usuarioActual?.id;
            if (usuarioId == null) {
              setModalState(() => error = 'No se pudo identificar al usuario.');
              return;
            }
            // Validación contra el catálogo ya cargado (oficiales + propios,
            // getCatalogoCompleto) antes de intentar el insert — unicidad
            // global de código, decisión de negocio: dos ítems con el mismo
            // número en el presupuesto impreso confunden al cliente.
            final codigoNormalizado = codigo.toLowerCase();
            RubroCatalogo? conflicto;
            for (final r in _catalogo) {
              if (r.codigo.trim().toLowerCase() == codigoNormalizado) {
                conflicto = r;
                break;
              }
            }
            if (conflicto != null) {
              setModalState(() {
                error = 'Ya existe un rubro con el código ${conflicto!.codigo} (${conflicto.nombre}).';
              });
              return;
            }
            setModalState(() {
              guardando = true;
              error = null;
            });
            try {
              await _rubrosRepository.crearPersonalizado(
                codigo: codigo,
                nombre: nombre,
                creadorUsuarioId: usuarioId,
              );
              if (!dialogCtx.mounted) return;
              Navigator.of(dialogCtx).pop();
              await _cargarCatalogo(); // trae el rubro nuevo, no solo los conteos
            } on PostgrestException catch (e) {
              // Red de seguridad del constraint de la base (0025), para el
              // caso raro que la validación de arriba no cubre (ej. otro
              // dispositivo creó el mismo código un instante antes de este
              // insert). Código 23505 = unique_violation en Postgres.
              setModalState(() {
                guardando = false;
                error = e.code == '23505'
                    ? 'Ese código ya existe. Elegí otro.'
                    : 'No se pudo crear el rubro. Probá de nuevo.';
              });
            } catch (e) {
              setModalState(() {
                guardando = false;
                error = 'No se pudo crear el rubro. Probá de nuevo.';
              });
            }
          }

          return AlertDialog(
            title: const Text(
              'Nuevo Rubro',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1B365D)),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: codigoCtrl,
                  decoration: const InputDecoration(labelText: 'Código', border: OutlineInputBorder(), isDense: true),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nombreCtrl,
                  decoration: const InputDecoration(labelText: 'Nombre', border: OutlineInputBorder(), isDense: true),
                ),
                // Precio manual por subítem, sin selector — 'global' queda
                // reservado a Instalaciones/Carpinterías (decisión de negocio,
                // ver RubrosRepository.crearPersonalizado).
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Se carga con precio manual por subítem, igual que Tareas '
                    'Preliminares y Varios.',
                    style: TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: guardando ? null : () => Navigator.of(dialogCtx).pop(),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: guardando ? null : guardar,
                child: guardando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Crear'),
              ),
            ],
          );
        },
      ),
    );
  }
}
