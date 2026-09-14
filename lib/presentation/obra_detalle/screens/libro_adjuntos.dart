import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import '../../../services/libro_repository.dart';

/// Los adjuntos de una entrada del libro: fotos y notas de voz (tanda 3 de
/// docs/libro_obra_horizonte.md).
///
/// **El bucket es privado**, así que nada se muestra con una URL directa: cada adjunto se abre con
/// una URL firmada que pide el repositorio en el momento. Por eso todo esto es asincrónico y tiene
/// estado de carga — una foto en una lista no aparece instantánea, y disimularlo con un placeholder
/// vacío haría pensar que el adjunto se perdió.
///
/// Qué es qué se decide por la extensión del path. Es rústico y alcanza: los dos únicos productores
/// de adjuntos son el compositor de esta misma pieza (que nombra los archivos) y, más adelante, la
/// documentación de obra.
bool esAudio(String path) {
  final p = path.toLowerCase();
  return p.endsWith('.m4a') || p.endsWith('.aac') || p.endsWith('.mp3') || p.endsWith('.wav');
}

/// La tira de adjuntos de una entrada. Fotos primero y audios abajo: la foto se lee de un vistazo,
/// el audio hay que decidir escucharlo.
class LibroAdjuntos extends StatelessWidget {
  final List<String> paths;
  final LibroRepository repository;

  const LibroAdjuntos({super.key, required this.paths, required this.repository});

  @override
  Widget build(BuildContext context) {
    if (paths.isEmpty) return const SizedBox.shrink();
    final fotos = paths.where((p) => !esAudio(p)).toList();
    final audios = paths.where(esAudio).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (fotos.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final f in fotos) _Foto(path: f, repository: repository)],
          ),
        ],
        for (final a in audios) _Audio(path: a, repository: repository),
      ],
    );
  }
}

class _Foto extends StatefulWidget {
  final String path;
  final LibroRepository repository;

  const _Foto({required this.path, required this.repository});

  @override
  State<_Foto> createState() => _FotoState();
}

class _FotoState extends State<_Foto> {
  String? _url;
  bool _fallo = false;

  @override
  void initState() {
    super.initState();
    _pedirUrl();
  }

  Future<void> _pedirUrl() async {
    try {
      final url = await widget.repository.urlAdjunto(widget.path);
      if (!mounted) return;
      setState(() => _url = url);
    } catch (_) {
      if (!mounted) return;
      setState(() => _fallo = true);
    }
  }

  /// A pantalla completa, con zoom: una foto de obra se saca para mirar un detalle, y una miniatura
  /// de 80 píxeles no sirve para eso.
  void _abrirGrande() {
    final url = _url;
    if (url == null) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(child: Image.network(url)),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_fallo) {
      return _caja(const Icon(Icons.broken_image_outlined, size: 20, color: Colors.black38));
    }
    if (_url == null) {
      return _caja(const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      ));
    }
    return GestureDetector(
      onTap: _abrirGrande,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.network(
          _url!,
          width: 84,
          height: 84,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) =>
              _caja(const Icon(Icons.broken_image_outlined, size: 20, color: Colors.black38)),
        ),
      ),
    );
  }

  Widget _caja(Widget hijo) => Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          color: Colors.black12,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Center(child: hijo),
      );
}

class _Audio extends StatefulWidget {
  final String path;
  final LibroRepository repository;

  const _Audio({required this.path, required this.repository});

  @override
  State<_Audio> createState() => _AudioState();
}

class _AudioState extends State<_Audio> {
  final AudioPlayer _player = AudioPlayer();
  bool _sonando = false;
  bool _cargando = false;

  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _sonando = false);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  /// La URL se pide recién al tocar play, no al dibujar la lista: firmar la URL de cada audio de un
  /// libro largo sería una consulta por mensaje para audios que quizá nadie escuche.
  Future<void> _alternar() async {
    if (_sonando) {
      await _player.pause();
      if (mounted) setState(() => _sonando = false);
      return;
    }
    setState(() => _cargando = true);
    try {
      final url = await widget.repository.urlAdjunto(widget.path);
      await _player.play(UrlSource(url));
      if (!mounted) return;
      setState(() {
        _sonando = true;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo reproducir la nota de voz.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 26,
            color: const Color(0xFF1B365D),
            icon: _cargando
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(_sonando ? Icons.pause_circle_filled : Icons.play_circle_fill),
            onPressed: _cargando ? null : _alternar,
          ),
          const Text('Nota de voz', style: TextStyle(fontSize: 12, color: Colors.black87)),
        ],
      ),
    );
  }
}
