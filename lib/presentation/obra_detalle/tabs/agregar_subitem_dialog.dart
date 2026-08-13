import 'package:flutter/material.dart';
import '../../../../data/models/subitem.dart';

class AgregarSubitemDialog extends StatefulWidget {
  final Subitem? subitemExistente;

  const AgregarSubitemDialog({super.key, this.subitemExistente});

  @override
  State<AgregarSubitemDialog> createState() => _AgregarSubitemDialogState();
}

class _AgregarSubitemDialogState extends State<AgregarSubitemDialog> {
  late TextEditingController _codigoCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _cantCtrl;
  late TextEditingController _unidCtrl;
  late TextEditingController _precioCtrl;

  @override
  void initState() {
    super.initState();
    _codigoCtrl = TextEditingController(text: widget.subitemExistente?.codigo ?? '');
    _descCtrl = TextEditingController(text: widget.subitemExistente?.descripcion ?? '');
    _cantCtrl = TextEditingController(text: widget.subitemExistente?.cantidad.toString() ?? '1');
    _unidCtrl = TextEditingController(text: widget.subitemExistente?.unidad ?? 'm2');
    _precioCtrl = TextEditingController(text: widget.subitemExistente?.precioUnitario.toString() ?? '0');
  }

  @override
  void dispose() {
    _codigoCtrl.dispose();
    _descCtrl.dispose();
    _cantCtrl.dispose();
    _unidCtrl.dispose();
    _precioCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final esEdicion = widget.subitemExistente != null;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      title: Text(
        esEdicion ? 'Editar Ítem' : 'Nuevo Ítem',
        style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1B365D), fontSize: 16),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _codigoCtrl,
              decoration: const InputDecoration(
                labelText: 'Código (ej: 03.01)',
                hintText: 'ej. 01.01',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descCtrl,
              decoration: const InputDecoration(
                labelText: 'Descripción',
                hintText: 'ej. Muro de ladrillo hueco 12cm',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _cantCtrl,
              decoration: const InputDecoration(labelText: 'Cantidad'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _unidCtrl,
              decoration: const InputDecoration(labelText: 'Unidad (m2, m3, gl, etc.)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _precioCtrl,
              decoration: const InputDecoration(labelText: 'Precio Unitario (\$)'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B365D)),
          onPressed: () {
            final nuevoSubitem = Subitem(
              id: widget.subitemExistente?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
              codigo: _codigoCtrl.text.isEmpty ? '01' : _codigoCtrl.text,
              descripcion: _descCtrl.text,
              cantidad: double.tryParse(_cantCtrl.text.replaceAll(',', '.')) ?? 1.0,
              unidad: _unidCtrl.text.isEmpty ? 'm2' : _unidCtrl.text,
              precioUnitario: double.tryParse(_precioCtrl.text.replaceAll(',', '.')) ?? 0.0,
            );
            Navigator.pop(context, nuevoSubitem);
          },
          child: Text(
            esEdicion ? 'Guardar' : 'Agregar',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ],
    );
  }
}