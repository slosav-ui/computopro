import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../services/auth_service.dart';
import '../../../services/excel_parser.dart';
import '../../../services/importaciones_repository.dart';
import 'revisar_importacion_screen.dart';

/// Importar un presupuesto a esta obra. Ver docs/importador_inteligente_diagnostico.md.
///
/// ================== HOY: SOLO EXCEL ==================
///
/// **Decisión de Seba del 2026-09-14: se sale sin importador de PDF.** El de Excel ya funciona, no
/// cuesta nada y cubre al que tiene su planilla, que es la mayoría. La lectura con IA está
/// construida entera y **apagada** con [lecturaConIaDisponible]; se retoma cuando la app genere
/// ingresos (§10 del diagnóstico, con los dos caminos posibles).
///
/// Apagada, esta pantalla **no ofrece lo que no puede cumplir**: el selector acepta solo `.xlsx` y
/// `.xls`, no hay botón de cámara, no se muestra el cupo, y un Excel cuyos encabezados el parser no
/// reconoce termina en un mensaje que dice qué arreglar en la planilla -- no en una oferta de leerlo
/// con IA. Mismo criterio que la solapa Proveedores, que dice "en construcción" en vez de mostrar un
/// borrador: ofrecer un PDF con la Edge Function sin desplegar sería ofrecer un error.
///
/// ================== PRENDIDA: TRES PUERTAS, UN DESTINO ==================
///
/// Excel, PDF o foto entran por acá y terminan siempre en `RevisarImportacionScreen`, que no se
/// entera de por dónde entraron.
///
///   - **Excel** intenta primero el parser determinístico del cliente: gratis, instantáneo y exacto
///     cuando reconoce los encabezados. Si no los reconoce, se ofrece leerlo con IA -- se ofrece,
///     no se hace solo, porque eso gasta una lectura del cupo.
///   - **PDF y foto** van directo al modelo, sin extraer texto primero.
///
/// El cupo mensual (0145) se muestra **antes** de elegir el archivo. Que alguien saque una foto, la
/// suba y recién ahí se entere de que no le quedan lecturas es la peor forma de decirlo.

/// El interruptor de la lectura con IA. Hoy `false` -- ver la cabecera de este archivo.
///
/// Para prenderlo: ponerlo en `true` **y desplegar la Edge Function** (`supabase secrets set
/// ANTHROPIC_API_KEY=...` y `supabase functions deploy leer-documento`). Las dos cosas o ninguna:
/// prenderlo sin desplegar deja la pantalla ofreciendo un error, que es justo lo que apagarlo
/// evita.
const bool lecturaConIaDisponible = false;

class ImportarPresupuestoScreen extends StatefulWidget {
  final String obraId;

  const ImportarPresupuestoScreen({super.key, required this.obraId});

  @override
  State<ImportarPresupuestoScreen> createState() => _ImportarPresupuestoScreenState();
}

enum _Paso { eligiendoArchivo, eligiendoHojas, ofreciendoIa, procesando }

class _ImportarPresupuestoScreenState extends State<ImportarPresupuestoScreen> {
  static const _azul = Color(0xFF1B365D);

  final ImportacionesRepository _repository = ImportacionesRepository();
  final AuthService _authService = AuthService();

  _Paso _paso = _Paso.eligiendoArchivo;
  String? _nombreArchivo;
  Uint8List? _bytesArchivo;
  String _tipoArchivo = 'excel';
  List<String> _hojasDisponibles = [];
  final Set<String> _hojasElegidas = {};
  String? _error;
  String? _avisoCupo;
  String _textoDeEspera = 'Procesando...';

  CupoIa? _cupo;
  bool _cargandoCupo = true;

  @override
  void initState() {
    super.initState();
    _cargarCupo();
  }

  Future<void> _cargarCupo() async {
    if (!lecturaConIaDisponible) {
      setState(() => _cargandoCupo = false);
      return;
    }
    try {
      final cupo = await _repository.cupoIa();
      if (!mounted) return;
      setState(() {
        _cupo = cupo;
        _cargandoCupo = false;
      });
    } catch (_) {
      // Sin cupo no se bloquea la pantalla: el Excel determinístico no lo necesita, y el tope real
      // lo aplica el servidor de todos modos. Lo único que se pierde acá es poder anticiparlo.
      if (!mounted) return;
      setState(() => _cargandoCupo = false);
    }
  }

  void _limpiar() {
    _nombreArchivo = null;
    _bytesArchivo = null;
    _hojasDisponibles = [];
    _hojasElegidas.clear();
    _avisoCupo = null;
    _paso = _Paso.eligiendoArchivo;
  }

  // ==========================================================================
  // Elegir el documento
  // ==========================================================================

  Future<void> _elegirArchivo() async {
    setState(() => _error = null);
    final resultado = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: lecturaConIaDisponible
          ? ['xlsx', 'xls', 'pdf', 'jpg', 'jpeg', 'png']
          : ['xlsx', 'xls'],
      withData: true,
    );
    if (resultado == null || resultado.files.isEmpty) return;
    final archivo = resultado.files.single;
    if (archivo.bytes == null) {
      setState(() => _error = 'No se pudo leer el archivo elegido. Probá de nuevo.');
      return;
    }

    final extension = archivo.name.toLowerCase().split('.').last;
    if (extension == 'xlsx' || extension == 'xls') {
      _prepararExcel(archivo.name, archivo.bytes!);
    } else {
      _prepararParaIa(archivo.name, archivo.bytes!, extension == 'pdf' ? 'pdf' : 'foto');
    }
  }

  Future<void> _sacarFoto() async {
    setState(() => _error = null);
    final foto = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 85);
    if (foto == null) return;
    final bytes = await foto.readAsBytes();
    if (!mounted) return;
    _prepararParaIa(foto.name, bytes, 'foto');
  }

  void _prepararExcel(String nombre, Uint8List bytes) {
    List<String> hojas;
    try {
      hojas = ExcelParser.listarHojas(bytes);
    } catch (e, st) {
      debugPrint('ExcelParser.listarHojas falló para "$nombre": $e\n$st');
      setState(() => _error = 'No se pudo abrir el archivo -- ¿es un Excel válido (.xlsx/.xls)? '
          'Detalle en consola: $e');
      return;
    }
    if (hojas.isEmpty) {
      setState(() => _error = 'El archivo no tiene ninguna hoja.');
      return;
    }
    setState(() {
      _nombreArchivo = nombre;
      _bytesArchivo = bytes;
      _tipoArchivo = 'excel';
      _hojasDisponibles = hojas;
      _hojasElegidas.clear();
      if (hojas.length == 1) _hojasElegidas.add(hojas.first);
      _paso = _Paso.eligiendoHojas;
    });
  }

  void _prepararParaIa(String nombre, Uint8List bytes, String tipo) {
    setState(() {
      _nombreArchivo = nombre;
      _bytesArchivo = bytes;
      _tipoArchivo = tipo;
      _hojasDisponibles = [];
      _hojasElegidas.clear();
      _paso = _Paso.ofreciendoIa;
    });
  }

  // ==========================================================================
  // Leer
  // ==========================================================================

  /// Camino rápido: el parser del cliente. Si reconoce los encabezados, termina acá -- sin red,
  /// sin costo y sin tocar el cupo.
  Future<void> _leerExcel() async {
    final bytes = _bytesArchivo;
    final nombre = _nombreArchivo;
    final usuarioId = _authService.usuarioActual?.id;
    if (bytes == null || nombre == null || usuarioId == null || _hojasElegidas.isEmpty) return;

    setState(() {
      _paso = _Paso.procesando;
      _textoDeEspera = 'Leyendo la planilla...';
      _error = null;
    });

    try {
      final hojas = _hojasElegidas.toList();
      final filas = ExcelParser.procesarFilas(bytes, hojas);

      if (filas.isEmpty) {
        // Con la IA prendida esto **no es un error, es la otra puerta**: el parser no reconoció los
        // encabezados, que es exactamente el caso para el que existe el modelo. Se ofrece, no se
        // hace solo, porque gasta una lectura del cupo y esa decisión es del usuario.
        //
        // Apagada, no hay otra puerta que ofrecer, así que se dice qué falta **en términos de lo
        // que el usuario puede hacer**: cambiar los encabezados de su planilla. Mandarlo a un
        // "no se pudo" sin salida sería dejarlo trabado con el archivo en la mano.
        if (lecturaConIaDisponible) {
          setState(() => _paso = _Paso.ofreciendoIa);
          return;
        }
        setState(() {
          _paso = _Paso.eligiendoHojas;
          _error = 'No se reconocieron los encabezados en las hojas elegidas. La planilla tiene que '
              'tener una fila de títulos con al menos Descripción, Cantidad y Precio Unitario '
              '(Rubro y Unidad son opcionales). Revisá que esa fila exista y volvé a intentar.';
        });
        return;
      }

      final importacion = await _repository.subirYCrear(
        obraId: widget.obraId,
        usuarioId: usuarioId,
        archivoNombre: nombre,
        bytes: bytes,
        hojasSeleccionadas: hojas,
        tipoArchivo: 'excel',
      );
      await _repository.insertarItems(importacion.id, filas);
      await _irARevisar(importacion.id);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _paso = _Paso.eligiendoHojas;
        _error = 'No se pudo procesar el archivo: $e';
      });
    }
  }

  /// Camino con modelo: sube el documento y lo manda a la Edge Function.
  Future<void> _leerConIa() async {
    final bytes = _bytesArchivo;
    final nombre = _nombreArchivo;
    final usuarioId = _authService.usuarioActual?.id;
    if (bytes == null || nombre == null || usuarioId == null) return;

    setState(() {
      _paso = _Paso.procesando;
      _textoDeEspera = 'Leyendo el documento. Puede tardar hasta un minuto.';
      _error = null;
      _avisoCupo = null;
    });

    String? importacionId;
    try {
      final importacion = await _repository.subirYCrear(
        obraId: widget.obraId,
        usuarioId: usuarioId,
        archivoNombre: nombre,
        bytes: bytes,
        hojasSeleccionadas: _hojasElegidas.toList(),
        tipoArchivo: _tipoArchivo,
      );
      importacionId = importacion.id;
      await _repository.leerConIa(importacion.id);
      await _cargarCupo();
      await _irARevisar(importacion.id);
    } on CupoAgotadoException catch (e) {
      if (!mounted) return;
      setState(() {
        _paso = _Paso.ofreciendoIa;
        // Va al cartel de cupo y no al de errores: no es una falla, es un límite conocido con una
        // salida concreta, y el texto lo escribió la base para leerse tal cual.
        _avisoCupo = e.mensaje;
      });
      await _cargarCupo();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _paso = _Paso.ofreciendoIa;
        _error = importacionId == null
            ? 'No se pudo subir el documento: $e'
            : 'No se pudo leer el documento: $e';
      });
    }
  }

  /// Abre la revisión y devuelve, a quien abrió el importador, **si la importación se aplicó**.
  ///
  /// Antes era un `pushReplacement`, y ahí estaba el bug de "hay que salir de la solapa y volver
  /// para ver lo importado": `pushReplacement` cierra la ruta anterior en el acto, así que el
  /// `await` de la solapa Cómputo terminaba acá -- con el usuario todavía revisando fila por fila,
  /// mucho antes de que existiera nada que mostrar. La solapa refrescaba en el momento equivocado
  /// y nunca más.
  ///
  /// Con `push` + `pop`, la solapa espera de verdad hasta que la revisión termina, y recibe `true`
  /// solo si el presupuesto entró. El motivo original del `pushReplacement` se mantiene: al cerrar
  /// la revisión esta pantalla se cierra sola, así que nadie vuelve atrás a un formulario de
  /// subida ya completado.
  Future<void> _irARevisar(String importacionId) async {
    if (!mounted) return;
    final aplicado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) =>
            RevisarImportacionScreen(obraId: widget.obraId, importacionId: importacionId),
      ),
    );
    if (!mounted) return;
    Navigator.of(context).pop(aplicado ?? false);
  }

  // ==========================================================================
  // Pantalla
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Importar presupuesto'),
        backgroundColor: _azul,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              lecturaConIaDisponible
                  ? 'Traé el presupuesto como lo tengas: una planilla de Excel, un PDF o una foto '
                      'de la hoja. Después vas a poder revisar partida por partida antes de que se '
                      'cargue nada.'
                  : 'Subí la planilla de tu cómputo, con una fila por partida (descripción, '
                      'cantidad y precio unitario). Después vas a poder revisar partida por partida '
                      'antes de que se cargue nada.',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 16),
            _buildCupo(),
            const SizedBox(height: 20),
            _buildPasoArchivo(),
            if (_paso == _Paso.eligiendoHojas) ...[
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 12),
              _buildPasoHojas(),
            ],
            if (_paso == _Paso.ofreciendoIa) ...[
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 12),
              _buildPasoIa(),
            ],
            if (_paso == _Paso.procesando) ...[
              const SizedBox(height: 24),
              Row(
                children: [
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_textoDeEspera,
                        style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  ),
                ],
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }

  /// El cupo, siempre a la vista. Cuando se agotó cambia de tono pero **no desaparece ni bloquea la
  /// pantalla**: el Excel con encabezados reconocibles sigue entrando, y esa es la salida que hace
  /// que el límite no sea una pared.
  Widget _buildCupo() {
    if (_cargandoCupo) return const SizedBox.shrink();
    final cupo = _cupo;
    if (cupo == null) return const SizedBox.shrink();

    final agotado = cupo.agotado;
    final color = agotado ? Colors.orange.shade800 : Colors.grey.shade700;
    final fondo = agotado ? Colors.orange.shade50 : Colors.grey.shade100;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: agotado ? Colors.orange.shade200 : Colors.grey.shade300),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(agotado ? Icons.hourglass_empty : Icons.auto_awesome_outlined, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  agotado
                      ? 'Usaste las ${cupo.limite} lecturas con IA de este mes'
                      : 'Te ${cupo.quedan == 1 ? "queda" : "quedan"} ${cupo.quedan} de '
                          '${cupo.limite} lecturas con IA este mes',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: color),
                ),
                const SizedBox(height: 3),
                Text(
                  agotado
                      ? 'El contador se reinicia el ${_fecha(cupo.seReiniciaEl)}. Mientras tanto '
                          'podés importar una planilla de Excel con encabezados reconocibles: esa '
                          'lectura no consume cupo.'
                      : 'Se usa una por cada PDF o foto. Las planillas de Excel con encabezados '
                          'reconocibles no consumen ninguna.',
                  style: TextStyle(fontSize: 11.5, height: 1.4, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasoArchivo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('1. El documento',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _azul)),
        const SizedBox(height: 8),
        if (_nombreArchivo == null)
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: _elegirArchivo,
                icon: const Icon(Icons.upload_file, size: 18),
                label: const Text('Elegir archivo'),
              ),
              if (lecturaConIaDisponible)
                OutlinedButton.icon(
                  onPressed: _sacarFoto,
                  icon: const Icon(Icons.photo_camera_outlined, size: 18),
                  label: const Text('Sacar una foto'),
                ),
            ],
          )
        else
          Row(
            children: [
              Icon(_iconoDelTipo(), size: 18, color: Colors.black54),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_nombreArchivo!,
                    style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
              ),
              if (_paso != _Paso.procesando)
                TextButton(onPressed: () => setState(_limpiar), child: const Text('Cambiar')),
            ],
          ),
        if (_nombreArchivo == null) ...[
          const SizedBox(height: 8),
          Text(
            lecturaConIaDisponible ? 'Excel, PDF o imagen.' : 'Planilla de Excel (.xlsx o .xls).',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ],
      ],
    );
  }

  IconData _iconoDelTipo() {
    switch (_tipoArchivo) {
      case 'pdf':
        return Icons.picture_as_pdf_outlined;
      case 'foto':
        return Icons.image_outlined;
      default:
        return Icons.table_chart_outlined;
    }
  }

  Widget _buildPasoHojas() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('2. Hojas a leer',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _azul)),
        const SizedBox(height: 4),
        const Text('Elegí una o más -- solo se leen las que tildes.',
            style: TextStyle(fontSize: 11, color: Colors.black54)),
        const SizedBox(height: 8),
        ..._hojasDisponibles.map(
          (hoja) => CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(hoja, style: const TextStyle(fontSize: 13)),
            value: _hojasElegidas.contains(hoja),
            onChanged: (marcado) => setState(() {
              if (marcado == true) {
                _hojasElegidas.add(hoja);
              } else {
                _hojasElegidas.remove(hoja);
              }
            }),
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: _hojasElegidas.isEmpty ? null : _leerExcel,
          child: const Text('Leer y continuar'),
        ),
      ],
    );
  }

  /// El paso que aparece cuando hace falta el modelo: siempre para PDF y foto, y para un Excel cuyos
  /// encabezados el parser no reconoció.
  ///
  /// Dice **que va a consumir una lectura antes de consumirla**. Un costo que se descubre después
  /// de gastarlo no es una decisión del usuario.
  Widget _buildPasoIa() {
    final cupo = _cupo;
    final agotado = cupo?.agotado ?? false;
    final vieneDeExcel = _tipoArchivo == 'excel';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(vieneDeExcel ? '3. Leerlo con IA' : '2. Leerlo con IA',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _azul)),
        const SizedBox(height: 6),
        Text(
          vieneDeExcel
              ? 'La planilla no tiene encabezados reconocibles (descripción, cantidad, precio '
                  'unitario), así que no se pudo leer de la forma rápida. Se puede leer igual con '
                  'IA, y eso consume una de tus lecturas del mes.'
              : 'Se va a leer el documento con IA. Consume una de tus lecturas del mes.',
          style: const TextStyle(fontSize: 12, height: 1.45, color: Colors.black87),
        ),
        const SizedBox(height: 8),
        Text(
          'Después vas a poder revisar y corregir partida por partida: la lectura se propone, no se '
          'da por buena.',
          style: TextStyle(fontSize: 11.5, height: 1.4, color: Colors.grey.shade600),
        ),
        if (_avisoCupo != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.hourglass_empty, size: 18, color: Colors.orange.shade800),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _avisoCupo!,
                    style: TextStyle(fontSize: 12, height: 1.45, color: Colors.orange.shade900),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: agotado ? null : _leerConIa,
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('Leer con IA'),
            ),
            const SizedBox(width: 10),
            TextButton(onPressed: () => setState(_limpiar), child: const Text('Elegir otro')),
          ],
        ),
      ],
    );
  }

  String _fecha(DateTime? fecha) {
    if (fecha == null) return 'el mes que viene';
    final dd = fecha.day.toString().padLeft(2, '0');
    final mm = fecha.month.toString().padLeft(2, '0');
    return '$dd/$mm/${fecha.year}';
  }
}
