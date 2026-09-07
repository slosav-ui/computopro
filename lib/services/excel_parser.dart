import 'dart:typed_data';
import 'package:excel/excel.dart' as xlsx;

/// Parser determinístico de un Excel de cómputo, sin IA — corre en el cliente, no en un servidor.
///
/// Decisión explícita (ver CLAUDE.md, "Importador de Excel/PDF"): la primera versión de esta pieza
/// usaba una Edge Function de Supabase (queda el archivo en
/// `supabase/functions/importar-excel/`, **sin desplegar ni usar en esta ronda**, guardado como
/// referencia para la segunda tanda). Se sacó porque los dos motivos que justificaban un servidor
/// en el diseño original (proteger una clave de IA, aplicar un límite de documentos/mes de Free) no
/// aplican acá: esta ronda no usa IA, y el importador es PRO exclusivo -- no hay límite que hacer
/// cumplir del lado servidor. Con eso afuera, sumar una segunda pieza de infraestructura (Deno,
/// deploy manual aparte, logs propios) para un proyecto sostenido por una sola persona no se
/// justificaba. Trade-off aceptado: un bug en este parser se corrige con una versión nueva de la
/// app, no con un redeploy de función -- el motivo real por el que valdrá la pena volver a un
/// servidor en la segunda tanda es otro: ahí sí hay una clave de un modelo de visión que proteger y
/// un costo por documento que controlar.
///
/// Misma lógica de reconocimiento de encabezados que la Edge Function de referencia (para que
/// migrar a PDF/foto más adelante no tenga que redescubrir el criterio), reescrita en Dart puro con
/// el paquete `excel`.
///
/// Límite real del paquete `excel` (4.0.6), encontrado al armar el archivo de prueba de esta
/// pieza: `Excel.decodeBytes` explota con "Null check operator used on a null value" si
/// `xl/_rels/workbook.xml.rels` declara el target de una hoja como ruta absoluta dentro del
/// paquete (`Target="/xl/worksheets/sheet1.xml"`) en vez de relativa a `xl/`
/// (`Target="worksheets/sheet1.xml"`, lo que escribe Excel/LibreOffice/Google Sheets siempre) --
/// el parser arma la ruta a buscar como `'xl/' + target` sin contemplar que `target` ya venga con
/// el `/xl/` puesto, y `archive.findFile(...)` no encuentra nada. Openpyxl (Python) generó ese
/// caso real en una prueba puntual, de forma inconsistente con sus propias relaciones de
/// styles/theme en el mismo archivo. No se parchea acá -- un archivo real exportado desde una
/// planilla de verdad no debería pisar este caso -- pero si algún día un usuario reporta "no se
/// pudo abrir el archivo" con un Excel que sí abre en todos lados, este es el primer sospechoso.
class ExcelParser {
  static const Map<String, List<String>> _campos = {
    'rubro': ['rubro', 'item', 'ítem', 'capitulo', 'capítulo', 'rubro/item'],
    'descripcion': ['descripcion', 'descripción', 'detalle', 'concepto', 'tarea', 'designacion', 'designación'],
    'unidad': ['unidad', 'un', 'u', 'ud', 'unidad de medida', 'u.medida'],
    'cantidad': ['cantidad', 'cant', 'cant.', 'computo', 'cómputo'],
    'precio_unitario': [
      'precio unitario',
      'precio unit',
      'p.unit',
      'p. unitario',
      'preciounitario',
      'p.u.',
      'precio unit.',
    ],
  };

  /// Nombres de hoja del archivo -- instantáneo, sin red, apenas se elige el archivo (antes de
  /// subirlo a ningún lado), para que el usuario elija cuál leer (Capa 1, decisión D: la IA/el
  /// parser no adivina cuál es la relevante).
  static List<String> listarHojas(Uint8List bytes) {
    final libro = xlsx.Excel.decodeBytes(bytes);
    return libro.tables.keys.toList();
  }

  /// Filas reconocidas de las hojas elegidas, listas para insertar en `importaciones_items` (sin
  /// `importacion_id`/`moneda`, los agrega quien llama). Por cada hoja: busca la primera fila que
  /// nombre al menos descripción + (cantidad o precio unitario) -- esa es el encabezado, nunca se
  /// guarda como partida -- y trata todo lo que sigue como datos hasta el final de la hoja. Una
  /// fila sin descripción se salta (encabezado de sección, subtotal, fila vacía) sin cortar el
  /// resto -- el usuario decide qué hacer con lo que sí se extrajo en la pantalla de revisión.
  static List<Map<String, dynamic>> procesarFilas(Uint8List bytes, List<String> hojas) {
    final libro = xlsx.Excel.decodeBytes(bytes);
    final filas = <Map<String, dynamic>>[];
    var orden = 0;

    for (final nombreHoja in hojas) {
      final hoja = libro.tables[nombreHoja];
      if (hoja == null) continue; // hoja elegida que ya no está en el archivo -- se ignora sola

      Map<String, int>? encabezados;
      for (final fila in hoja.rows) {
        if (encabezados == null) {
          encabezados = _detectarEncabezados(fila);
          continue;
        }
        final descripcion = _aTexto(_valorEn(fila, encabezados['descripcion']));
        if (descripcion == null) continue;

        orden += 1;
        filas.add({
          'orden': orden,
          'rubro_texto': _aTexto(_valorEn(fila, encabezados['rubro'])),
          'descripcion_texto': descripcion,
          'unidad_texto': _aTexto(_valorEn(fila, encabezados['unidad'])),
          'cantidad': _aNumero(_valorEn(fila, encabezados['cantidad'])),
          'precio_unitario': _aNumero(_valorEn(fila, encabezados['precio_unitario'])),
          // Catch-all, mismo patrón que libro_entradas.adjuntos/audit_log.detalle -- respaldo de
          // en qué hoja apareció, para cuando el parser se equivocó y hay que revisar el original.
          'datos_originales': {'hoja': nombreHoja},
        });
      }
    }
    return filas;
  }

  static xlsx.CellValue? _valorEn(List<xlsx.Data?> fila, int? indice) {
    if (indice == null || indice >= fila.length) return null;
    return fila[indice]?.value;
  }

  static Map<String, int>? _detectarEncabezados(List<xlsx.Data?> fila) {
    final mapa = <String, int>{};
    for (var i = 0; i < fila.length; i++) {
      final texto = _normalizar(fila[i]?.value);
      if (texto.isEmpty) continue;
      for (final campo in _campos.keys) {
        if (mapa.containsKey(campo)) continue;
        if (_campos[campo]!.any((s) => _normalizar(s) == texto)) mapa[campo] = i;
      }
    }
    if (!mapa.containsKey('descripcion')) return null;
    if (!mapa.containsKey('cantidad') && !mapa.containsKey('precio_unitario')) return null;
    return mapa;
  }

  static String _normalizar(Object? valor) {
    if (valor == null) return '';
    return valor.toString().trim().toLowerCase();
  }

  static String? _aTexto(xlsx.CellValue? valor) {
    if (valor == null) return null;
    final texto = valor.toString().trim();
    return texto.isEmpty ? null : texto;
  }

  static double? _aNumero(xlsx.CellValue? valor) {
    if (valor == null) return null;
    if (valor is xlsx.IntCellValue) return valor.value.toDouble();
    if (valor is xlsx.DoubleCellValue) return valor.value;
    final texto = valor.toString().trim();
    if (texto.isEmpty) return null;
    // Convención argentina (punto de miles, coma decimal) primero -- mismo criterio que
    // ParserNumeroAr en el resto de la app; si no matchea, se prueba el número tal cual (por si el
    // Excel ya trae el separador en formato "de máquina").
    final normalizado = texto.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(normalizado) ?? double.tryParse(texto);
  }
}
