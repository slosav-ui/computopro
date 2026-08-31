import 'package:flutter/material.dart';

/// Diálogo informativo para una función exclusiva de PRO, cuando quien toca
/// el control es Free.
///
/// Mismo criterio en toda la app (spec funcional, "Free ve todo, no edita"):
/// el control sigue visible para Free, no se oculta — al tocarlo se explica
/// que requiere PRO en vez de dejarlo actuar o esconder la función. Primer
/// lugar donde se implementa (RubrosTab, alta de rubro personalizado);
/// pensado para reusarse tal cual en cualquier otra pantalla con el mismo
/// patrón, sin duplicar el diálogo.
Future<void> mostrarDialogoFuncionPro(
  BuildContext context, {
  required String mensaje,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.workspace_premium, color: Colors.amber),
          SizedBox(width: 8),
          // Mismo patrón que los demás títulos de diálogo de la app —
          // riesgo casi nulo acá (texto corto), pero consistente con el
          // resto para no dejar el mismo hueco sin cerrar en un widget
          // compartido que se reusa en varias pantallas.
          Expanded(child: Text('Función PRO')),
        ],
      ),
      content: Text(mensaje),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Entendido'),
        ),
      ],
    ),
  );
}
