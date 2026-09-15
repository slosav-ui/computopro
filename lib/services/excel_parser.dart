import 'dart:typed_data';
import 'excel_lector_xlsx.dart';

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
  /// Sinónimos de encabezado, por campo. Comparación exacta contra el texto de la celda ya
  /// normalizado (minúsculas, sin espacios al borde) -- **a propósito, no `contains`**: "Precio
  /// item" contiene "precio" y es un TOTAL, no un precio unitario. Meterlo en la misma columna es
  /// justamente el error de emparejado que esta lista evita.
  ///
  /// Las variantes largas salieron de planillas reales (`docs/planillas_prueba/`): "UND." y
  /// "CANT." en la de Hotel Milan, "Un.", "Cant. Total" y "Precio uni Mano de Obra" en la de
  /// Bocián. Cada una está acá porque un arquitecto la escribió así, no por si acaso.
  ///
  /// **Lo que NO está y no se agrega**: "unidades". En la hoja de estructura de Hotel Milan esa
  /// columna cuenta piezas (24, 12), no dice metros ni kilos -- tomarla como unidad de medida
  /// pondría "24" donde va "m2".
  static const Map<String, List<String>> _campos = {
    'rubro': ['rubro', 'item', 'ítem', 'capitulo', 'capítulo', 'rubro/item', 'nro', 'n°', 'cod', 'codigo', 'código'],
    'descripcion': ['descripcion', 'descripción', 'detalle', 'concepto', 'tarea', 'designacion', 'designación'],
    'unidad': [
      'unidad',
      'un',
      'un.',
      'u',
      'u.',
      'ud',
      'und',
      'und.',
      'unid',
      'unid.',
      'um',
      'u.m.',
      'unidad de medida',
      'u.medida',
      'medida',
    ],
    'cantidad': [
      'cantidad',
      'cant',
      'cant.',
      'cant. total',
      'cant total',
      'cant.total',
      'cantidad total',
      'computo',
      'cómputo',
      'computo total',
      'metros',
    ],
    'precio_unitario': [
      'precio unitario',
      'precio unit',
      'p.unit',
      'p. unitario',
      'preciounitario',
      'p.u.',
      'precio unit.',
      'precio uni',
      'precio uni mano de obra',
      'precio unitario mano de obra',
      'precio unit mano de obra',
      'precio u.',
      'valor unitario',
    ],
    // Reconocidos para **no** confundirlos con el precio unitario, y para dejarlos en
    // `datos_originales` como respaldo de lo que decía la planilla. No se cargan como precio: el
    // total es cantidad x unitario, y escribirlo en la columna del unitario multiplica la obra.
    'precio_total': [
      'precio item',
      'precio ítem',
      'p. total item',
      'p.total item',
      'precio total item',
      'total item',
      'importe',
      'precio total',
      'p. total',
    ],
    'total_rubro': ['total del rubro', 'total rubro', 'subtotal rubro', 'total por rubro'],
  };

  /// Un código de partida: "1", "1.1", "2.3.4". **No** es el nombre de un rubro.
  ///
  /// Distinguirlos es lo que arregla el emparejado en las dos planillas reales: la columna que se
  /// llama "ITEM" o "Rubro" trae el NÚMERO de la partida, y el nombre del rubro vive en una fila
  /// aparte, sin cantidad ni precio ("1 - TAREAS PRELIMINARES", "CERRAMIENTO EXTERIOR E INTERIOR").
  /// Antes de esto, cada partida importada llegaba a la revisión con "1.1" en el campo Rubro, y
  /// había que reescribir el rubro a mano en todas.
  static final RegExp _codigoDePartida = RegExp(r'^\d+(\.\d+)*\.?$');

  /// Nombres de hoja del archivo -- instantáneo, sin red, apenas se elige el archivo (antes de
  /// subirlo a ningún lado), para que el usuario elija cuál leer (Capa 1, decisión D: la IA/el
  /// parser no adivina cuál es la relevante).
  static List<String> listarHojas(Uint8List bytes) {
    return LibroXlsx.desdeBytes(bytes).nombresDeHojas;
  }

  /// Filas reconocidas de las hojas elegidas, listas para insertar en `importaciones_items` (sin
  /// `importacion_id`/`moneda`, los agrega quien llama).
  ///
  /// Por cada hoja: busca la primera fila que nombre al menos descripción + (cantidad o precio
  /// unitario) -- esa es el encabezado, nunca se guarda como partida -- y trata todo lo que sigue
  /// como datos hasta el final de la hoja.
  ///
  /// ------------------------------------------------------- rubro de sección vs. código de partida
  ///
  /// Una planilla de presupuesto no repite el rubro en cada fila: lo escribe UNA VEZ, en una fila
  /// sola, y abajo van sus partidas numeradas. Las dos planillas reales lo hacen igual:
  ///
  ///     1 - TAREAS PRELIMINARES                              <- fila de rubro
  ///     1.1 | Replanteo | Gl. | 1 | 286.839,00 | ...         <- partida
  ///
  ///     CERRAMIENTO EXTERIOR E INTERIOR                      <- fila de rubro
  ///     2 | Pared exterior steel framing | m2 | 49,4 | ...   <- partida
  ///
  /// Se reconoce como **fila de rubro** la que no tiene ni cantidad ni precio unitario y cuyo
  /// primer texto no es un código. Su nombre queda como rubro de todo lo que sigue, hasta el
  /// próximo. El número de la partida va a `datos_originales`, no al campo de rubro.
  ///
  /// Antes de esto, cada partida llegaba a la pantalla de revisión con "1.1" en el campo Rubro --
  /// el número de la planilla en el lugar del rubro de destino -- y había que reescribirlo a mano
  /// en todas.
  ///
  /// Una fila sin descripción se salta (subtotal, fila vacía) sin cortar el resto: el usuario
  /// decide qué hacer con lo que sí se extrajo en la pantalla de revisión.
  static List<Map<String, dynamic>> procesarFilas(Uint8List bytes, List<String> hojas) {
    final libro = LibroXlsx.desdeBytes(bytes);
    final filas = <Map<String, dynamic>>[];
    var orden = 0;

    for (final nombreHoja in hojas) {
      // Hoja elegida que ya no está en el archivo: `filasDe` devuelve vacío y el for no itera.
      Map<String, int>? encabezados;
      // El rubro vigente arranca en null y vale hasta que aparezca otra fila de rubro. Se reinicia
      // por hoja: dos hojas elegidas son dos presupuestos, no uno partido al medio.
      String? rubroVigente;

      for (final fila in libro.filasDe(nombreHoja)) {
        if (encabezados == null) {
          encabezados = _detectarEncabezados(fila);
          continue;
        }

        final primera = _aTexto(_valorEn(fila, encabezados['rubro']));
        final descripcion = _aTexto(_valorEn(fila, encabezados['descripcion']));
        final cantidad = _aNumero(_valorEn(fila, encabezados['cantidad']));
        final precioUnitario = _aNumero(_valorEn(fila, encabezados['precio_unitario']));
        final precioTotal = _aNumero(_valorEn(fila, encabezados['precio_total']));

        final esCodigo = primera != null && _codigoDePartida.hasMatch(primera);
        final sinNumeros = cantidad == null && precioUnitario == null;

        // Fila de rubro con el nombre en la primera columna ("1 - TAREAS PRELIMINARES"): no tiene
        // descripción propia, así que se mira antes del descarte por descripción vacía.
        if (!esCodigo && primera != null && descripcion == null && sinNumeros) {
          rubroVigente = primera;
          continue;
        }

        if (descripcion == null) continue;

        // Fila de rubro con el nombre en la columna de descripción ("CERRAMIENTO EXTERIOR E
        // INTERIOR"): sin número de partida y sin cantidad ni precio. Una partida que quedó sin
        // cotizar NO cae acá -- tiene su código ("1.3 | Cerco de obra (NO SE COTIZA)") y sigue
        // entrando como partida, que es lo que el usuario espera ver en la revisión.
        if (!esCodigo && primera == null && sinNumeros) {
          rubroVigente = descripcion;
          continue;
        }

        orden += 1;
        filas.add({
          'orden': orden,
          // El rubro de sección primero. Si la planilla en cambio repite el nombre del rubro en
          // cada fila (no es un código), ese nombre vale: es el comportamiento de antes de esta
          // corrección y sigue siendo el correcto para esas planillas.
          'rubro_texto': rubroVigente ?? (esCodigo ? null : primera),
          'descripcion_texto': descripcion,
          'unidad_texto': _aTexto(_valorEn(fila, encabezados['unidad'])),
          'cantidad': cantidad,
          'precio_unitario': precioUnitario,
          // Catch-all, mismo patrón que libro_entradas.adjuntos/audit_log.detalle -- respaldo de
          // lo que decía la planilla, para cuando el parser se equivocó y hay que revisar el
          // original. El código de partida vive acá y no en una columna propia: capturarlo de
          // verdad (para numerar con él) es una pieza aparte, anotada en §8 del doc de carpetas.
          'datos_originales': {
            'hoja': nombreHoja,
            if (esCodigo) 'codigo_planilla': primera,
            'precio_total_planilla': ?precioTotal,
          },
        });
      }
    }
    return filas;
  }

  static Object? _valorEn(List<Object?> fila, int? indice) {
    if (indice == null || indice >= fila.length) return null;
    return fila[indice];
  }

  static Map<String, int>? _detectarEncabezados(List<Object?> fila) {
    final mapa = <String, int>{};
    for (var i = 0; i < fila.length; i++) {
      final texto = _normalizar(fila[i]);
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

  static String? _aTexto(Object? valor) {
    if (valor == null) return null;
    final texto = valor.toString().trim();
    return texto.isEmpty ? null : texto;
  }

  /// Un número de la planilla, ya redondeado a lo que la app muestra.
  ///
  /// ---------------------------------------------------------------- por qué se redondea acá
  ///
  /// Una planilla de Excel casi nunca guarda el número que se ve: guarda el resultado de la
  /// fórmula. "286.839,00" en pantalla es `286839.00000000006` en el archivo, y `51.093,55` es
  /// `51093.553045333334`. Al importar entraban así, con diez decimales, y aparecían en el Cómputo
  /// como los vio Seba en el teléfono.
  ///
  /// Se redondea **en la entrada** y no en la pantalla a propósito: es el mismo criterio que la
  /// migración 0149 dejó en la base -- redondear donde el número se produce, una sola vez, para
  /// que no haya un lugar más donde se pueda perder.
  ///
  /// ---------------------------------------------------------------- la excepción
  ///
  /// Dos decimales, **salvo que eso convierta una cantidad real en cero**. Las hojas de análisis
  /// de precios de las planillas reales traen rendimientos chicos de verdad -- 0,048 m3 de arena
  /// por m2 de contrapiso, 0,008 tn de hierro. Redondear 0,008 a 0,01 exagera un 25%; redondear
  /// 0,002 a 0,00 deja la partida valiendo nada, en silencio, y eso sí es un dato perdido.
  ///
  /// Así que si el redondeo da cero y el número no era cero, se conserva con los decimales que
  /// hagan falta. Un número mal redondeado se ve y se corrige; un cero que apareció solo, no.
  static double? _aNumero(Object? valor) {
    final crudo = _aNumeroCrudo(valor);
    if (crudo == null) return null;
    final redondeado = double.parse(crudo.toStringAsFixed(2));
    if (redondeado != 0 || crudo == 0) return redondeado;
    // Cantidad chica de verdad: se guarda entera, sin recortarla a cero.
    return crudo;
  }

  static double? _aNumeroCrudo(Object? valor) {
    if (valor == null) return null;
    if (valor is num) return valor.toDouble();
    final texto = valor.toString().trim();
    if (texto.isEmpty) return null;
    // Convención argentina (punto de miles, coma decimal) primero -- mismo criterio que
    // ParserNumeroAr en el resto de la app; si no matchea, se prueba el número tal cual (por si el
    // Excel ya trae el separador en formato "de máquina").
    final normalizado = texto.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(normalizado) ?? double.tryParse(texto);
  }
}
