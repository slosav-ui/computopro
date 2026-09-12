import 'package:flutter/material.dart';
import '../../data/models/pendiente.dart';

/// "Tenés N cosas esperándote" -- arriba de la lista de obras (docs/avisos_pendientes_diseno.md §3).
/// Al tocarlo, una hoja con el detalle; cada ítem lleva a donde se resuelve (`onAbrir`, lo resuelve
/// el dashboard, que es quien sabe navegar y recargar).
///
/// Mismo criterio que `CartelFirmaPendiente`: no se descarta ni recuerda si se cerró -- desaparece
/// cuando ya no hay nada pendiente. Quien lo usa no lo muestra con la lista vacía.
class CartelPendientes extends StatelessWidget {
  final List<Pendiente> pendientes;
  final Future<void> Function(Pendiente) onAbrir;

  const CartelPendientes({super.key, required this.pendientes, required this.onAbrir});

  static String _fmtFecha(DateTime? f) {
    if (f == null) return '';
    final l = f.toLocal();
    return '${l.day}/${l.month}/${l.year}';
  }

  static IconData _icono(TipoPendiente tipo) {
    switch (tipo) {
      case TipoPendiente.adicional:
        return Icons.add_box_outlined;
      case TipoPendiente.quita:
      case TipoPendiente.demasia:
        return Icons.straighten;
      case TipoPendiente.certificadoEmitido:
      case TipoPendiente.certificadoLeido:
      case TipoPendiente.certificadoPagado:
        return Icons.receipt_long_outlined;
      case TipoPendiente.anulacion:
        return Icons.block_outlined;
      case TipoPendiente.firmaFisica:
        return Icons.draw_outlined;
    }
  }

  void _mostrarLista(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Esperándote',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1B365D)),
                ),
              ),
              for (final p in pendientes)
                ListTile(
                  dense: true,
                  leading: Icon(_icono(p.tipo), color: const Color(0xFF1B365D)),
                  title: Text(p.titulo, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    '${p.obraNombre} · ${p.detalle}'
                    '${p.desde != null ? "\nDesde el ${_fmtFecha(p.desde)}" : ""}',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  isThreeLine: p.desde != null,
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () {
                    Navigator.pop(ctx);
                    onAbrir(p);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = pendientes.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Material(
        color: Colors.amber.shade100,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _mostrarLista(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.notifications_active_outlined, size: 20, color: Colors.amber.shade900),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    n == 1 ? 'Tenés 1 cosa esperándote' : 'Tenés $n cosas esperándote',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                ),
                Text('Ver', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.amber.shade900)),
                Icon(Icons.chevron_right, size: 18, color: Colors.amber.shade900),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
