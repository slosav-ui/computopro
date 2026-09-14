import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// El aviso legal de los libros (decisión 2 de docs/libro_obra_horizonte.md §D, cerrada por Seba el
/// 2026-09-13: **la redacción directa**).
///
/// El texto dice las dos cosas que hay que decir —que sirve como respaldo y que no reemplaza al
/// rubricado— sin asustar. Es la razón de ser de toda la pieza: la app **no** es el libro legal,
/// pero sí es la prueba de quién dijo qué y cuándo si algo termina en una discusión formal.
///
/// **Descartable, y no permanente**: un cartel fijo en pantalla se vuelve invisible en dos días, y
/// entonces no avisa nada. Se descarta por obra y por dispositivo (`SharedPreferences`, mismo
/// mecanismo que el cartel de zona UOCRA y el aviso de orden de rubros), y vuelve con el ícono de
/// la barra. Cuando exista la exportación a PDF, el mismo texto va fijo al pie: ahí no se descarta,
/// porque el papel sale de la app y se lee sin contexto.
class CartelAvisoLegalLibro extends StatelessWidget {
  static const texto =
      'Este registro es un respaldo interno de la obra. No reemplaza al Libro de Obra rubricado '
      'ante el colegio profesional o el municipio, que es el que tiene validez legal.';

  final VoidCallback onDescartar;

  const CartelAvisoLegalLibro({super.key, required this.onDescartar});

  static String claveDescartado(String obraId) => 'libro_aviso_legal_descartado_$obraId';

  /// Para el ícono de la barra, una vez descartado.
  static Future<void> mostrarComoDialogo(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sobre este registro', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        content: const Text(texto, style: TextStyle(fontSize: 12.5)),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2F7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFC8D4E3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.gavel_outlined, size: 18, color: Color(0xFF1B365D)),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(texto, style: TextStyle(fontSize: 11.5, color: Colors.black87)),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 16, color: Colors.black45),
            tooltip: 'Entendido',
            onPressed: onDescartar,
          ),
        ],
      ),
    );
  }
}

/// Lee y escribe el descartado. Default `false` (aviso visible) hasta que la lectura resuelva:
/// mismo criterio fail-closed que el resto de los avisos de la app -- acá lo seguro es mostrarlo.
class AvisoLegalLibroPref {
  static Future<bool> leerDescartado(String obraId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(CartelAvisoLegalLibro.claveDescartado(obraId)) ?? false;
  }

  static Future<void> guardarDescartado(String obraId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(CartelAvisoLegalLibro.claveDescartado(obraId), true);
  }
}
