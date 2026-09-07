import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../services/auth_service.dart';
import '../../../services/excel_parser.dart';
import '../../../services/importaciones_repository.dart';
import 'revisar_importacion_screen.dart';

/// Subida de un presupuesto en Excel para importar a esta obra (docs/importador_capa2_diseno_datos.md).
/// El Excel se lee ENTERO en el cliente (`ExcelParser`, ver el comentario de cabecera de ese
/// archivo para el porqué de no usar un servidor en esta ronda): elegir archivo lista las hojas al
/// instante, sin red -- el usuario elige cuál(es) leer ANTES de que se procese el contenido (Capa
/// 1, decisión D), recién ahí se sube el archivo a Storage (respaldo) y se procesan las filas.
///
/// Al terminar de procesar, reemplaza esta pantalla por RevisarImportacionScreen (pushReplacement):
/// volver atrás desde la revisión no tiene sentido, dejaría al usuario en un formulario de subida
/// ya completado.
class ImportarExcelScreen extends StatefulWidget {
  final String obraId;

  const ImportarExcelScreen({Key? key, required this.obraId}) : super(key: key);

  @override
  State<ImportarExcelScreen> createState() => _ImportarExcelScreenState();
}

enum _Paso { eligiendoArchivo, eligiendoHojas, procesando }

class _ImportarExcelScreenState extends State<ImportarExcelScreen> {
  final ImportacionesRepository _repository = ImportacionesRepository();
  final AuthService _authService = AuthService();

  _Paso _paso = _Paso.eligiendoArchivo;
  String? _nombreArchivo;
  Uint8List? _bytesArchivo;
  List<String> _hojasDisponibles = [];
  final Set<String> _hojasElegidas = {};
  String? _error;

  Future<void> _elegirArchivo() async {
    setState(() => _error = null);
    final resultado = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      withData: true,
    );
    if (resultado == null || resultado.files.isEmpty) return;
    final archivo = resultado.files.single;
    if (archivo.bytes == null) {
      setState(() => _error = 'No se pudo leer el archivo elegido. Probá de nuevo.');
      return;
    }

    List<String> hojas;
    try {
      hojas = ExcelParser.listarHojas(archivo.bytes!);
    } catch (e, st) {
      // El mensaje en pantalla queda genérico a propósito (no todos los errores del parser dicen
      // algo útil para quien no programa), pero el real va a la consola -- sin esto, diagnosticar
      // un archivo que no abre significaba adivinar a ciegas.
      debugPrint('ExcelParser.listarHojas falló para "${archivo.name}": $e\n$st');
      setState(() => _error = 'No se pudo abrir el archivo -- ¿es un Excel válido (.xlsx/.xls)? Detalle en consola: $e');
      return;
    }
    if (hojas.isEmpty) {
      setState(() => _error = 'El archivo no tiene ninguna hoja.');
      return;
    }

    setState(() {
      _nombreArchivo = archivo.name;
      _bytesArchivo = archivo.bytes;
      _hojasDisponibles = hojas;
      _hojasElegidas.clear();
      // Con una sola hoja en el archivo, se preselecciona directo -- no tiene sentido pedirle al
      // usuario que tilde la única opción posible.
      if (hojas.length == 1) _hojasElegidas.add(hojas.first);
      _paso = _Paso.eligiendoHojas;
    });
  }

  Future<void> _subirYProcesar() async {
    final bytes = _bytesArchivo;
    final nombre = _nombreArchivo;
    final usuarioId = _authService.usuarioActual?.id;
    if (bytes == null || nombre == null || usuarioId == null || _hojasElegidas.isEmpty) return;

    setState(() {
      _paso = _Paso.procesando;
      _error = null;
    });
    try {
      final hojas = _hojasElegidas.toList();
      final filas = ExcelParser.procesarFilas(bytes, hojas);
      if (filas.isEmpty) {
        setState(() {
          _paso = _Paso.eligiendoHojas;
          _error = 'No se encontraron filas con encabezados reconocidos '
              '(Rubro/Descripción/Unidad/Cantidad/Precio Unitario) en las hojas elegidas.';
        });
        return;
      }

      final importacion = await _repository.subirYCrear(
        obraId: widget.obraId,
        usuarioId: usuarioId,
        archivoNombre: nombre,
        bytes: bytes,
        hojasSeleccionadas: hojas,
      );
      await _repository.insertarItems(importacion.id, filas);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => RevisarImportacionScreen(obraId: widget.obraId, importacionId: importacion.id),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _paso = _Paso.eligiendoHojas;
        _error = 'No se pudo procesar el archivo: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Importar presupuesto (Excel)'),
        backgroundColor: const Color(0xFF1B365D),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Subí el Excel de tu cómputo (rubro, descripción, unidad, cantidad y precio unitario '
              'por fila) y elegí qué partidas importar. No lee composiciones de APU -- si tu '
              'presupuesto trae eso, se ignora, solo se toma cómputo cerrado.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 20),
            _buildPasoArchivo(),
            if (_paso.index >= _Paso.eligiendoHojas.index) ...[
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 12),
              _buildPasoHojas(),
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

  Widget _buildPasoArchivo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('1. Archivo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1B365D))),
        const SizedBox(height: 8),
        if (_nombreArchivo == null)
          OutlinedButton.icon(
            onPressed: _elegirArchivo,
            icon: const Icon(Icons.upload_file),
            label: const Text('Elegir archivo Excel'),
          )
        else
          Row(
            children: [
              const Icon(Icons.description_outlined, size: 18, color: Colors.black54),
              const SizedBox(width: 8),
              Expanded(child: Text(_nombreArchivo!, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
              if (_paso != _Paso.procesando)
                TextButton(
                  onPressed: () => setState(() {
                    _nombreArchivo = null;
                    _bytesArchivo = null;
                    _hojasDisponibles = [];
                    _hojasElegidas.clear();
                    _paso = _Paso.eligiendoArchivo;
                  }),
                  child: const Text('Cambiar'),
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildPasoHojas() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('2. Hojas a leer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1B365D))),
        const SizedBox(height: 4),
        const Text(
          'Elegí una o más -- solo se leen las que tildes.',
          style: TextStyle(fontSize: 11, color: Colors.black54),
        ),
        const SizedBox(height: 8),
        ..._hojasDisponibles.map(
          (hoja) => CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(hoja, style: const TextStyle(fontSize: 13)),
            value: _hojasElegidas.contains(hoja),
            onChanged: _paso == _Paso.eligiendoHojas
                ? (marcado) => setState(() {
                      if (marcado == true) {
                        _hojasElegidas.add(hoja);
                      } else {
                        _hojasElegidas.remove(hoja);
                      }
                    })
                : null,
          ),
        ),
        const SizedBox(height: 12),
        if (_paso == _Paso.eligiendoHojas)
          ElevatedButton(
            onPressed: _hojasElegidas.isEmpty ? null : _subirYProcesar,
            child: const Text('Leer y continuar'),
          ),
        if (_paso == _Paso.procesando)
          const Row(
            children: [
              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 10),
              Text('Procesando filas...', style: TextStyle(fontSize: 12, color: Colors.black54)),
            ],
          ),
      ],
    );
  }
}
