import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/segurity/user_context.dart';
import '../../../data/models/libro_entrada.dart';
import '../../../data/models/obra_member.dart';
import '../../../data/models/perfil_basico.dart';
import '../../../services/auth_service.dart';
import '../../../services/libro_repository.dart';
import '../../../services/perfil_repository.dart';
import 'cartel_aviso_legal_libro.dart';
import 'libro_adjuntos.dart';

/// El libro de comunicaciones de obra. Diseño: docs/libro_obra_horizonte.md.
///
/// **Una conversación, no un trámite** (cambio de alcance de Seba, 2026-09-14). Antes eran dos
/// libros direccionales con orden, acuse de recibo y plazo; en obra la empresa no responde adentro
/// de la orden, contesta con otro libro, y reproducir ese ida y vuelta complicaba sin aportar. Acá
/// escriben y se responden el constructor y el profesional, y **el cliente solo lee**.
///
/// **Sigue sin ser un chat cualquiera**, y eso es lo que se conserva de la idea original: cada
/// mensaje muestra **nombre, rol, fecha y hora**, y no se puede editar ni borrar. El "quién y
/// cuándo" es el valor de la pieza, no un detalle que se esconde en un tooltip.
///
/// **El cliente y el veedor no ven un compositor en gris**: directamente no está.
class LibroObraScreen extends StatefulWidget {
  final String obraId;
  final UserContext? userContext;

  const LibroObraScreen({super.key, required this.obraId, required this.userContext});

  @override
  State<LibroObraScreen> createState() => _LibroObraScreenState();
}

class _LibroObraScreenState extends State<LibroObraScreen> {
  final LibroRepository _repository = LibroRepository();
  final PerfilRepository _perfilRepository = PerfilRepository();
  final AuthService _authService = AuthService();
  final ScrollController _scroll = ScrollController();

  bool _cargando = true;

  /// Subir una foto tarda, y en obra la conexión es la que es. Sin esto, tocar "Registrar" no
  /// da ninguna señal hasta que la entrada aparece en la lista.
  bool _guardando = false;

  String? _error;
  bool _avisoDescartado = false;



  List<LibroEntrada> _entradas = [];

  /// usuario_id -> nombre. Secundario: si `get_perfiles_de_obra` falla, se muestra el rol solo --
  /// mismo criterio que `MiembrosObraScreen`. El libro no se cae porque falte un nombre.
  final Map<String, String> _nombres = {};

  bool get _puedeEscribir => widget.userContext?.puedeEscribirLibroObra == true;

  @override
  void initState() {
    super.initState();
    _cargar();
    _cargarAviso();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _cargarAviso() async {
    final descartado = await AvisoLegalLibroPref.leerDescartado(widget.obraId);
    if (!mounted) return;
    setState(() => _avisoDescartado = descartado);
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final entradas = await _repository.getEntradas(obraId: widget.obraId);
      await _cargarNombres();
      if (!mounted) return;
      setState(() {
        _entradas = entradas;
        _cargando = false;
      });
      _alFinal();
      // Abrir el libro ES leerlo: no hay botón de "marcar como leído" (decisión de Seba,
      // 2026-09-14 -- "si hay que tocar algo para que se apague el aviso, aparece un paso que nadie
      // entiende y que se olvida siempre"). Se marca hasta la última entrada que se cargó, no hasta
      // ahora: un mensaje que llegue entre la consulta y esta línea no se puede dar por leído.
      await _repository.marcarLeido(
        obraId: widget.obraId,
        hasta: entradas.isEmpty ? null : entradas.last.fechaCreacion,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar el libro.';
        _cargando = false;
      });
    }
  }

  /// Arranca abajo, en lo último escrito: un libro se lee desde donde quedó, no desde el principio.
  void _alFinal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _cargarNombres() async {
    try {
      final perfiles = await _perfilRepository.getPerfilesDeObra(widget.obraId);
      _nombres
        ..clear()
        ..addEntries(perfiles
            .where((PerfilBasico p) => p.nombre != null)
            .map((p) => MapEntry(p.usuarioId, p.nombre!)));
    } catch (_) {
      // Dato secundario -- ver el comentario de `_nombres`.
    }
  }

  /// "Fulano · Profesional", o solo el rol si el nombre no llegó. El rol va SIEMPRE, aunque el
  /// nombre esté: es con qué rol firmó, y eso es parte del registro, no un adorno.
  String _firma(LibroEntrada e) {
    final nombre = _nombres[e.autorUsuarioId];
    final rol = rolEtiqueta(e.autorRol);
    return nombre == null ? rol : '$nombre · $rol';
  }

  static String _fechaHora(DateTime f) {
    final l = f.toLocal();
    final dd = l.day.toString().padLeft(2, '0');
    final mm = l.month.toString().padLeft(2, '0');
    final hh = l.hour.toString().padLeft(2, '0');
    final mi = l.minute.toString().padLeft(2, '0');
    return '$dd/$mm/${l.year} $hh:$mi';
  }

  Future<void> _descartarAviso() async {
    setState(() => _avisoDescartado = true);
    await AvisoLegalLibroPref.guardarDescartado(widget.obraId);
  }

  // ===========================================================================
  // Escribir
  // ===========================================================================

  Future<void> _escribir() async {
    final rol = widget.userContext?.rolParaEscribirLibro();
    final usuarioId = _authService.usuarioActual?.id;
    if (rol == null || usuarioId == null) return;

    final borrador = await _pedirEntrada();
    if (borrador == null || !mounted) return;

    setState(() => _guardando = true);
    try {
      // Los adjuntos se suben ANTES de crear la entrada: si algo falla, no queda una entrada
      // publicada que promete una foto que no está. Al revés no se puede arreglar -- la tabla es
      // append-only, así que una entrada mal guardada no se edita ni se borra nunca más.
      final paths = <String>[];
      for (final a in borrador.adjuntos) {
        paths.add(await _repository.subirAdjunto(
          obraId: widget.obraId,
          nombreArchivo: a.nombre,
          bytes: a.bytes,
        ));
      }

      await _repository.crearEntrada(
        obraId: widget.obraId,
        contenido: borrador.texto,
        autorRol: rol,
        autorUsuarioId: usuarioId,
        adjuntos: paths,
      );
      await _cargar();
    } catch (e) {
      if (!mounted) return;
      // El mensaje de la base, tal cual: si la policy rechazó, dice por qué mejor que un genérico.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e is PostgrestException && e.message.trim().isNotEmpty
              ? e.message
              : 'No se pudo guardar la entrada.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  /// El compositor. Hoja abajo y no un diálogo: **el micrófono primero y el teclado después** -- nadie
  /// en obra, con el casco puesto, va a tipear un texto largo parado.
  ///
  /// La nota de voz **se guarda siempre y el texto la acompaña** (decisión 3 del diseño): el audio es
  /// la prueba de lo que se dijo, y la línea de texto es para poder leer y buscar sin escuchar
  /// cincuenta grabaciones. Por eso el texto sigue siendo obligatorio aunque haya audio.
  Future<_BorradorEntrada?> _pedirEntrada() {
    final controller = TextEditingController();
    final adjuntos = <_AdjuntoLocal>[];
    final grabador = AudioRecorder();
    var grabando = false;

    return showModalBottomSheet<_BorradorEntrada>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Future<void> sacarFoto(ImageSource origen) async {
            try {
              // maxWidth + imageQuality no son un lujo: una foto de un teléfono actual pesa entre 5
              // y 10 MB, y en obra se suben con datos móviles. A 1600px y 70% queda en el orden de
              // los 300 KB, que para mirar un detalle de obra alcanza de sobra.
              final x = await ImagePicker()
                  .pickImage(source: origen, maxWidth: 1600, imageQuality: 70);
              if (x == null) return;
              final bytes = await x.readAsBytes();
              setSheet(() => adjuntos.add(_AdjuntoLocal(nombre: x.name, bytes: bytes)));
            } catch (_) {
              if (!ctx.mounted) return;
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('No se pudo tomar la foto.')),
              );
            }
          }

          Future<void> alternarGrabacion() async {
            try {
              if (grabando) {
                final ruta = await grabador.stop();
                setSheet(() => grabando = false);
                if (ruta == null) return;
                final archivo = File(ruta);
                final bytes = await archivo.readAsBytes();
                setSheet(() => adjuntos.add(_AdjuntoLocal(
                      nombre: 'nota-de-voz-${DateTime.now().millisecondsSinceEpoch}.m4a',
                      bytes: bytes,
                    )));
                await archivo.delete();
                return;
              }
              // El permiso se pide acá, en el momento en que se va a usar el micrófono, y no al
              // abrir la pantalla: un permiso que aparece sin que hayas pedido nada se rechaza.
              if (!await grabador.hasPermission()) {
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Sin permiso de micrófono no se puede grabar.')),
                );
                return;
              }
              final dir = await getTemporaryDirectory();
              final destino = '${dir.path}/libro-${DateTime.now().millisecondsSinceEpoch}.m4a';
              await grabador.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: destino);
              setSheet(() => grabando = true);
            } catch (_) {
              setSheet(() => grabando = false);
              if (!ctx.mounted) return;
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('No se pudo grabar la nota de voz.')),
              );
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Escribir en el libro',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1B365D)),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Queda registrado con tu nombre, tu rol y la fecha. No se puede editar ni borrar después.',
                  style: TextStyle(fontSize: 11, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(grabando ? Icons.stop_circle_outlined : Icons.mic_none_outlined, size: 22),
                      color: grabando ? Colors.red.shade700 : const Color(0xFF1B365D),
                      tooltip: grabando ? 'Terminar la nota de voz' : 'Grabar una nota de voz',
                      onPressed: alternarGrabacion,
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.photo_camera_outlined, size: 22),
                      color: const Color(0xFF1B365D),
                      tooltip: 'Sacar una foto',
                      onPressed: grabando ? null : () => sacarFoto(ImageSource.camera),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.image_outlined, size: 22),
                      color: const Color(0xFF1B365D),
                      tooltip: 'Elegir una foto',
                      onPressed: grabando ? null : () => sacarFoto(ImageSource.gallery),
                    ),
                    if (grabando)
                      const Expanded(
                        child: Text('Grabando…',
                            style: TextStyle(fontSize: 11, color: Colors.black54)),
                      ),
                  ],
                ),
                if (adjuntos.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final a in adjuntos)
                        Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text(
                            a.esAudio ? 'Nota de voz' : 'Foto',
                            style: const TextStyle(fontSize: 11),
                          ),
                          avatar: Icon(a.esAudio ? Icons.mic : Icons.image, size: 14),
                          onDeleted: () => setSheet(() => adjuntos.remove(a)),
                        ),
                    ],
                  ),
                const SizedBox(height: 4),
                TextField(
                  controller: controller,
                  autofocus: false,
                  maxLines: 5,
                  minLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    isDense: true,
                    hintText: adjuntos.any((a) => a.esAudio)
                        ? 'En una línea, de qué es la nota de voz'
                        : null,
                    hintStyle: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () async {
                        if (grabando) await grabador.stop();
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      child: const Text('Cancelar'),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1B365D),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: grabando
                          ? null
                          : () {
                              final texto = controller.text.trim();
                              if (texto.isEmpty) return;
                              Navigator.pop(
                                ctx,
                                _BorradorEntrada(texto: texto, adjuntos: List.of(adjuntos)),
                              );
                            },
                      child: const Text('Registrar'),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    ).whenComplete(grabador.dispose);
  }

  // ===========================================================================
  // Pantalla
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Libro de obra', style: TextStyle(fontSize: 15)),
        backgroundColor: const Color(0xFF1B365D),
        foregroundColor: Colors.white,
        actions: [
          if (_avisoDescartado)
            IconButton(
              icon: const Icon(Icons.gavel_outlined, size: 20),
              tooltip: 'Sobre este registro',
              onPressed: () => CartelAvisoLegalLibro.mostrarComoDialogo(context),
            ),
        ],
      ),
      body: Column(
        children: [
          if (!_avisoDescartado) CartelAvisoLegalLibro(onDescartar: _descartarAviso),
          Expanded(child: _buildContenido()),
        ],
      ),
      floatingActionButton: _puedeEscribir && !_cargando && _error == null
          ? FloatingActionButton.extended(
              backgroundColor: const Color(0xFF1B365D),
              foregroundColor: Colors.white,
              onPressed: _guardando ? null : _escribir,
              icon: _guardando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.edit_outlined, size: 18),
              label: Text(_guardando ? 'Guardando…' : 'Escribir',
                  style: const TextStyle(fontSize: 12)),
            )
          : null,
    );
  }

  Widget _buildContenido() {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
        ),
      );
    }
    if (_entradas.isEmpty) {
      return RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
              child: Text(
                _puedeEscribir
                    ? 'Todavía no hay nada escrito en el libro de esta obra.'
                    : 'Todavía no hay nada escrito en el libro de esta obra. Escriben el profesional '
                        'y el constructor.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 88), // 88: no quedar tapado por el botón
        itemCount: _entradas.length,
        itemBuilder: (_, i) => _buildEntrada(_entradas[i]),
      ),
    );
  }

  /// Cada entrada, alineada según quién la escribió: las propias a la derecha, las de la otra parte
  /// a la izquierda. Es lo único que esta pantalla toma prestado de un chat, y sirve para leer de un
  /// vistazo de qué lado viene cada cosa.
  Widget _buildEntrada(LibroEntrada e) {
    final propia = e.autorUsuarioId == _authService.usuarioActual?.id;
    return Align(
      alignment: propia ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
        child: Card(
          margin: const EdgeInsets.only(bottom: 8),
          elevation: 1,
          color: propia ? const Color(0xFFEEF2F7) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_firma(e)} · ${_fechaHora(e.fechaCreacion)}',
                  style: const TextStyle(fontSize: 10.5, color: Colors.black54),
                ),
                const SizedBox(height: 4),
                Text(e.contenido, style: const TextStyle(fontSize: 13, color: Colors.black87)),
                LibroAdjuntos(paths: e.adjuntos, repository: _repository),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Un adjunto elegido en el compositor y todavía sin subir. Vive en memoria hasta que se toca
/// "Registrar": si se cancela, no queda nada en el bucket -- un archivo huérfano en Storage no lo
/// borra nadie nunca.
class _AdjuntoLocal {
  final String nombre;
  final Uint8List bytes;

  const _AdjuntoLocal({required this.nombre, required this.bytes});

  bool get esAudio => nombre.toLowerCase().endsWith('.m4a');
}

/// Lo que devuelve el compositor: el texto (siempre) y los adjuntos (si los hay).
class _BorradorEntrada {
  final String texto;
  final List<_AdjuntoLocal> adjuntos;

  const _BorradorEntrada({required this.texto, required this.adjuntos});
}
