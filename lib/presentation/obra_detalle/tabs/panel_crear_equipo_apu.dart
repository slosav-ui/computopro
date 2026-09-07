import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/utils/parser_numero_ar.dart';
import '../../../services/apu_composiciones_repository.dart';
import '../../../services/auth_service.dart';
import '../../../services/insumos_repository.dart';
import '../../../services/perfil_repository.dart';
import '../../shared/pro_gate_dialog.dart';

/// Alta directa de un equipo -- se usa mientras el catálogo de equipos está vacío (nadie cargó
/// ninguno todavía, ver `ComposicionApuScreen._abrirAgregarItem`) y también como salida de
/// "no lo encontrás" desde el buscador (`PanelAgregarItemApu`) una vez que el catálogo ya tiene
/// algo. Los 4 campos que pidió Seba en un solo paso: nombre, unidad (hora o día), precio por esa
/// unidad y rendimiento -- la identidad del equipo es el nombre, no el precio (ver
/// `buscar_o_crear_equipo_apu`, `0074_catalogo_colaborativo_equipos.sql`): si ya existe un equipo
/// con ese nombre (de cualquier usuario, el catálogo es compartido) se reusa esa fila en vez de
/// crear un duplicado, y el precio que carga este usuario queda en su propia obra
/// (`obra_insumo_precios`), sin pisar el de nadie más.
///
/// Gate de PRO al Guardar, no al abrir -- mismo criterio que el resto de los paneles de edición de
/// APU.
///
/// Devuelve por `Navigator.pop`: `null` si se cancela, o la receta completa ya actualizada.
class PanelCrearEquipoApu extends StatefulWidget {
  final String obraId;
  final String subitemId;

  const PanelCrearEquipoApu({
    Key? key,
    required this.obraId,
    required this.subitemId,
  }) : super(key: key);

  @override
  State<PanelCrearEquipoApu> createState() => _PanelCrearEquipoApuState();
}

class _PanelCrearEquipoApuState extends State<PanelCrearEquipoApu> {
  final InsumosRepository _insumosRepository = InsumosRepository();
  final ApuComposicionesRepository _composicionesRepository = ApuComposicionesRepository();
  final PerfilRepository _perfilRepository = PerfilRepository();
  final AuthService _authService = AuthService();

  final TextEditingController _nombreController = TextEditingController();
  final TextEditingController _precioController = TextEditingController();
  final TextEditingController _rendimientoController = TextEditingController();

  // 'hs' | 'dia' -- únicos dos valores válidos para unidad de equipo (ver
  // insumos_unidad_valida, 0074).
  String _unidad = 'hs';

  String? _error;
  bool _guardando = false;
  bool _verificandoPro = false;

  @override
  void dispose() {
    _nombreController.dispose();
    _precioController.dispose();
    _rendimientoController.dispose();
    super.dispose();
  }

  Future<void> _onGuardar() async {
    final nombre = _nombreController.text.trim();
    if (nombre.isEmpty) {
      setState(() => _error = 'Ingresá el nombre del equipo.');
      return;
    }
    final precio = ParserNumeroAr.parsear(_precioController.text);
    if (precio == null || precio < 0) {
      setState(() => _error = 'Precio inválido. Ingresá un número mayor o igual a 0.');
      return;
    }
    final rendimiento = ParserNumeroAr.parsear(_rendimientoController.text);
    if (rendimiento == null || rendimiento < 0) {
      setState(() => _error = 'Rendimiento inválido. Ingresá un número mayor o igual a 0.');
      return;
    }

    final usuarioId = _authService.usuarioActual?.id;
    setState(() {
      _error = null;
      _verificandoPro = true;
    });
    final esProAhora = usuarioId != null ? await _perfilRepository.esPro(usuarioId) : false;
    if (!mounted) return;
    setState(() => _verificandoPro = false);

    if (!esProAhora) {
      await mostrarDialogoFuncionPro(context, mensaje: 'Editar la composición de APU es una función PRO.');
      return;
    }

    setState(() => _guardando = true);
    try {
      final equipo = await _insumosRepository.buscarOCrearEquipo(nombre: nombre, unidad: _unidad);
      await _composicionesRepository.agregarEquipo(
        obraId: widget.obraId,
        subitemId: widget.subitemId,
        insumoId: equipo.id,
        rendimiento: rendimiento,
        precioInicial: precio,
      );
      // Se pide la composición de nuevo por separado en vez de confiar en lo que devuelve
      // agregar_equipo_apu -- la fila del equipo recién creado aparecía sin nombre ni números (ver
      // conversación, sin causa raíz confirmada: la lectura de obra_insumo_precios en
      // calcular_composicion_detalle_subitem se revisó y es correcta en el código). Candidato más
      // probable: agregar_equipo_apu cambió de firma en 0074 (drop + create, 4 args -> 5) y se
      // volvió a definir en 0076 -- si el schema cache de PostgREST quedó desactualizado con esa
      // firma nueva en algún momento, este segundo pedido lo esquiva por completo:
      // calcular_composicion_detalle_subitem no cambió de firma desde 0072, PostgREST la tiene
      // cacheada hace rato.
      final recetaActualizada = await _composicionesRepository.getComposicionDetalle(
        widget.obraId,
        widget.subitemId,
      );
      if (!mounted) return;
      Navigator.pop(context, recetaActualizada);
    } on PostgrestException catch (e) {
      // El mensaje que ve el usuario queda genérico a propósito -- el motivo real (el `raise
      // exception` de buscar_o_crear_equipo_apu/agregar_equipo_apu, o un error de RLS/constraint)
      // va a la consola para poder diagnosticarlo. No se puede reproducir desde el SQL Editor
      // porque las dos funciones son SECURITY INVOKER y dependen de auth.uid() (usuario logueado).
      debugPrint(
        'Error creando equipo (Postgrest) -- code=${e.code} message=${e.message} '
        'details=${e.details} hint=${e.hint}',
      );
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _error = 'No se pudo crear el equipo. Probá de nuevo.';
      });
    } catch (e) {
      debugPrint('Error creando equipo: $e');
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _error = 'No se pudo crear el equipo. Probá de nuevo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'Crear equipo',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1B365D)),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nombreController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                hintText: 'Ej. Hormigonera 130 litros',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            const Text('Unidad', style: TextStyle(fontSize: 11, color: Colors.black54)),
            const SizedBox(height: 4),
            Row(
              children: [
                ChoiceChip(
                  label: const Text('Hora'),
                  selected: _unidad == 'hs',
                  onSelected: (_) => setState(() => _unidad = 'hs'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Día'),
                  selected: _unidad == 'dia',
                  onSelected: (_) => setState(() => _unidad = 'dia'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _precioController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Precio',
                prefixText: '\$ ',
                suffixText: '/ ${_unidad == 'hs' ? 'HORA' : 'DÍA'}',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _rendimientoController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Rendimiento',
                suffixText: (_unidad == 'hs' ? 'HS' : 'DIA'),
                border: const OutlineInputBorder(),
                isDense: true,
                helperText: 'Cuánto de este equipo lleva una unidad de la partida',
                helperMaxLines: 2,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: (_guardando || _verificandoPro) ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: (_guardando || _verificandoPro) ? null : _onGuardar,
          child: (_guardando || _verificandoPro)
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(_verificandoPro ? 'Verificando...' : 'Guardar'),
        ),
      ],
    );
  }
}
