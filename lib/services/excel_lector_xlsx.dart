import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Lector de .xlsx propio, que reemplaza a `package:excel` **solo para leer**.
///
/// ---------------------------------------------------------------- por qué existe
///
/// Dos planillas reales de arquitectos no se podían abrir, y ninguna de las dos tenía nada malo:
///
///   * una redefine los formatos de número 43 y 44 -- los de contabilidad -- como hace Excel en
///     cualquier planilla con columnas de plata. `package:excel` corta con
///     `Exception: custom numFmtId starts at 164 but found a value of 43`;
///   * la otra tiene la fila 1 con las 16.384 columnas llenas de "Columna1".."Columna16384", resto
///     de una tabla vieja. `package:excel` corta con
///     `ArgumentError: Reached Max (16384) or (XFD) columns value` -- y encima por un error de
///     cuenta suyo: compara una CANTIDAD de columnas contra el límite de Excel con `>=`, así que
///     rechaza una hoja que usa las 16.384 columnas que Excel permite.
///
/// **Las dos fallas son por cosas que el importador no necesita mirar**: formatos de moneda y el
/// ancho declarado de la hoja. De un Excel solo hacen falta textos y números.
///
/// **Por qué un lector propio y no un parche.** Para esquivar esos dos errores habría que
/// descomprimir el .xlsx, editarle el `styles.xml`, recortar la fila ancha, volver a comprimirlo y
/// recién ahí dárselo al paquete. Una vez que hay que abrir el zip y leer el XML, **leer los
/// valores es menos código que reescribir el archivo** -- y saca de encima una familia entera de
/// fallas en vez de dos.
///
/// Criterio de producto detrás (Seba, 2026-09-15): *"el usuario sube la planilla tal como la tiene
/// y la app la tiene que abrir. No se le pide que la modifique ni que pruebe con otra."*
///
/// ---------------------------------------------------------------- qué lee y qué ignora
///
/// Lee: los nombres de las hojas, la tabla de textos compartidos, y las celdas de la hoja pedida.
///
/// **Ignora por completo** estilos, formatos, colores, anchos y el `dimension` declarado. Ahí vive
/// casi todo lo que rompe, y nada de eso cambia qué dice una celda.
///
/// Las fechas vienen como número (Excel las guarda así, y saber que son fechas exige justamente el
/// subsistema de formatos que se está evitando). **Al importador no le importan**: lee rubro,
/// descripción, unidad, cantidad y precio.
class LibroXlsx {
  final Archive _zip;
  final List<_HojaRef> _hojas;
  List<String>? _textosCompartidos;

  LibroXlsx._(this._zip, this._hojas);

  /// Los nombres de las hojas, **en el orden en que las declara el archivo** (que es el orden de
  /// las pestañas, no el de los archivos internos).
  List<String> get nombresDeHojas => [for (final h in _hojas) h.nombre];

  /// Abre el archivo. Lanza [FormatException] si no es un .xlsx legible.
  factory LibroXlsx.desdeBytes(Uint8List bytes) {
    final Archive zip;
    try {
      zip = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      // Caso típico: un .xls viejo (binario, no es un zip) elegido desde el selector.
      throw const FormatException('El archivo no es un .xlsx (no se pudo abrir como paquete).');
    }

    final workbook = _leerXml(zip, 'xl/workbook.xml');
    if (workbook == null) {
      throw const FormatException('El archivo no tiene xl/workbook.xml: no es un .xlsx válido.');
    }

    // rId -> archivo de la hoja. **Hace falta el mapa, no alcanza con el orden**: en las planillas
    // reales el orden de las pestañas no coincide con el de los archivos internos (en una de las
    // de prueba, la primera pestaña es sheet8.xml).
    final destinos = <String, String>{};
    final rels = _leerXml(zip, 'xl/_rels/workbook.xml.rels');
    if (rels != null) {
      for (final r in rels.findAllElements('Relationship')) {
        final id = r.getAttribute('Id');
        final target = r.getAttribute('Target');
        if (id != null && target != null) destinos[id] = target;
      }
    }

    final hojas = <_HojaRef>[];
    for (final s in workbook.findAllElements('sheet')) {
      final nombre = s.getAttribute('name');
      if (nombre == null) continue;
      final rid = s.getAttribute('r:id') ?? s.getAttribute('id');
      final target = rid == null ? null : destinos[rid];
      hojas.add(_HojaRef(nombre, _rutaDeHoja(target), s.getAttribute('state')));
    }

    if (hojas.isEmpty) {
      throw const FormatException('El archivo no declara ninguna hoja.');
    }
    return LibroXlsx._(zip, hojas);
  }

  /// Las filas de una hoja como una grilla de valores: `String`, `num` o `null`.
  ///
  /// El ancho y el alto salen **de las celdas con contenido real**, no del `dimension` que declara
  /// el archivo -- que en una de las planillas de prueba dice `A1:XFD81` cuando lo que se usa es de
  /// la A a la L.
  ///
  /// Hoja inexistente: lista vacía, no excepción. La pantalla de revisión ya sabe manejar una hoja
  /// que no aporta filas, y romper por una hoja que el usuario deseleccionó sería peor.
  List<List<Object?>> filasDe(String nombreHoja) {
    final ref = _hojas.where((h) => h.nombre == nombreHoja).firstOrNull;
    if (ref == null || ref.ruta == null) return const [];

    final doc = _leerXml(_zip, ref.ruta!);
    if (doc == null) return const [];

    // Disperso primero: una hoja puede declarar la fila 81 y tener llenas solo cinco.
    final celdas = <int, Map<int, Object?>>{};
    var maxFila = -1;
    var maxColumna = -1;

    for (final row in doc.findAllElements('row')) {
      for (final c in row.findElements('c')) {
        final ref0 = c.getAttribute('r');
        if (ref0 == null) continue;
        final pos = _posicion(ref0);
        if (pos == null) continue;

        final valor = _valorDeCelda(c);
        if (valor == null) continue;

        celdas.putIfAbsent(pos.fila, () => {})[pos.columna] = valor;

        if (pos.fila > maxFila) maxFila = pos.fila;
        // **El relleno no agranda la hoja.** "Columna1".."Columna16384" en la fila 1 es lo que Excel
        // deja cuando una tabla tenía encabezados automáticos: no es contenido, y si contara, la
        // grilla pasaría de 12 columnas a 16.384.
        if (!_esRelleno(valor) && pos.columna > maxColumna) maxColumna = pos.columna;
      }
    }

    if (maxFila < 0 || maxColumna < 0) return const [];

    final filas = <List<Object?>>[];
    for (var f = 0; f <= maxFila; f++) {
      final fila = celdas[f];
      final valores = <Object?>[
        for (var c = 0; c <= maxColumna; c++) fila?[c],
      ];
      // Una fila entera de relleno se descarta. No es imprescindible -- el detector de encabezados
      // la saltearía igual -- pero deja la grilla diciendo la verdad sobre la planilla.
      if (valores.every((v) => v == null || _esRelleno(v))) {
        filas.add(const []);
      } else {
        filas.add(valores);
      }
    }
    return filas;
  }

  // ---------------------------------------------------------------- internos

  List<String> get _compartidos {
    if (_textosCompartidos != null) return _textosCompartidos!;
    final doc = _leerXml(_zip, 'xl/sharedStrings.xml');
    final lista = <String>[];
    if (doc != null) {
      for (final si in doc.findAllElements('si')) {
        // Un texto con formato mixto viene partido en varios `t` (uno por tramo con su estilo).
        // Concatenarlos es lo que devuelve la frase entera: tomar solo el primero cortaría
        // "Hormigón **armado**" en "Hormigón ".
        lista.add(si.findAllElements('t').map((t) => t.innerText).join());
      }
    }
    _textosCompartidos = lista;
    return lista;
  }

  Object? _valorDeCelda(XmlElement c) {
    final tipo = c.getAttribute('t');

    if (tipo == 'inlineStr') {
      final texto = c.findAllElements('t').map((t) => t.innerText).join().trim();
      return texto.isEmpty ? null : texto;
    }

    final v = c.findElements('v').firstOrNull;
    if (v == null) {
      // Fórmula sin valor guardado: la planilla nunca se recalculó antes de guardarse. No hay nada
      // que leer -- ningún lector puede inventarlo -- y la celda queda vacía.
      return null;
    }
    final crudo = v.innerText.trim();
    if (crudo.isEmpty) return null;

    switch (tipo) {
      case 's':
        final i = int.tryParse(crudo);
        if (i == null || i < 0 || i >= _compartidos.length) return null;
        final texto = _compartidos[i].trim();
        return texto.isEmpty ? null : texto;
      case 'e':
        return null; // #REF!, #VALOR!, #N/A: un error de la planilla no es un dato
      case 'b':
        return crudo == '1';
      case 'str':
        return crudo.isEmpty ? null : crudo;
      default:
        // Número. Las fechas caen acá como número de serie, a propósito.
        return num.tryParse(crudo) ?? crudo;
    }
  }

  /// "Columna17", "Column17": encabezado que Excel genera solo cuando una tabla no tiene títulos.
  /// Nunca es un dato del presupuesto.
  static bool _esRelleno(Object? valor) {
    if (valor is! String) return false;
    return RegExp(r'^columnas?\s*\d+$', caseSensitive: false).hasMatch(valor.trim()) ||
        RegExp(r'^column\s*\d+$', caseSensitive: false).hasMatch(valor.trim());
  }

  /// "BK12" -> columna 62 (base 0), fila 11 (base 0).
  static _Posicion? _posicion(String ref) {
    var i = 0;
    var columna = 0;
    while (i < ref.length) {
      final code = ref.codeUnitAt(i);
      final esLetra = (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
      if (!esLetra) break;
      columna = columna * 26 + ((code & 0x5F) - 64);
      i++;
    }
    if (i == 0 || i >= ref.length) return null;
    final fila = int.tryParse(ref.substring(i));
    if (fila == null || fila < 1) return null;
    return _Posicion(fila - 1, columna - 1);
  }

  /// El target de la relación es relativo a `xl/`, pero algunas herramientas lo escriben absoluto
  /// (`/xl/worksheets/sheet1.xml`). Las dos formas se resuelven acá -- es exactamente el caso que
  /// hacía explotar a `package:excel` con un "Null check operator used on a null value", anotado en
  /// `excel_parser.dart` desde que se armó esa pieza.
  static String? _rutaDeHoja(String? target) {
    if (target == null) return null;
    final limpio = target.startsWith('/') ? target.substring(1) : 'xl/$target';
    return limpio;
  }

  static XmlDocument? _leerXml(Archive zip, String ruta) {
    final archivo = zip.findFile(ruta);
    if (archivo == null) return null;
    try {
      // utf8, no fromCharCodes: el XML de un .xlsx es UTF-8 siempre, y `fromCharCodes` toma cada
      // byte como un carácter -- "Descripción" se leía "DescripciÃ³n" y "Baño" "BaÃ±o". Con
      // `allowMalformed` un byte suelto raro no voltea el archivo entero.
      return XmlDocument.parse(utf8.decode(archivo.content as List<int>, allowMalformed: true));
    } catch (_) {
      return null;
    }
  }
}

class _HojaRef {
  final String nombre;
  final String? ruta;

  /// `hidden` / `veryHidden` cuando la hoja está oculta. Hoy no se usa para filtrar -- queda leído
  /// para cuando se decida qué hacer con las hojas ocultas en el selector.
  final String? estado;

  const _HojaRef(this.nombre, this.ruta, this.estado);
}

class _Posicion {
  final int fila;
  final int columna;
  const _Posicion(this.fila, this.columna);
}
