import 'package:flutter/material.dart';

/// Una acción de la barra de Gestión de Obra. `destacada` es la principal (hoy "Nuevo
/// certificado"): mismo tamaño que el resto, pero con el ícono en fondo lleno, para que haya
/// jerarquía sin romper la grilla.
class AccionObra {
  final IconData icono;
  final String label;
  final VoidCallback onTap;
  final bool destacada;

  /// El globito con el número, arriba a la derecha del ícono -- como el de WhatsApp. `0` o `null`
  /// no dibuja nada: un globito en cero no informa, ocupa.
  ///
  /// Es para cosas que se leen, no para cosas que se resuelven: lo que requiere acción va al cartel
  /// del dashboard (ver `mis_pendientes`), no acá.
  final int? pendientes;

  const AccionObra({
    required this.icono,
    required this.label,
    required this.onTap,
    this.destacada = false,
    this.pendientes,
  });
}

/// Barra de acciones de Gestión de Obra: **grilla de ícono + etiqueta, en un solo bloque**.
///
/// Reemplaza a los cuatro `OutlinedButton.icon` sueltos en un `Wrap` (Seba, 2026-09-13: *"están
/// como globitos ahí perdidos, y el diseño deja mucho que desear"*). El problema de fondo no era el
/// tamaño sino que **van a ser más**: el Libro de Obra suma por lo menos una acción y probablemente
/// dos (Órdenes de Servicio y Notas de Pedido), y una fila de botones con texto no llega a seis u
/// ocho sin comerse la pantalla.
///
/// Por qué esta forma y no las otras que estaban sobre la mesa:
///
/// - **No un menú de tres puntos**: las acciones tienen que verse. Un menú las esconde y nadie
///   descubre lo que no ve — es la primera restricción que puso Seba.
/// - **No una fila con scroll horizontal**: lo que queda fuera del borde es invisible en la
///   práctica, con el agravante de que no hay ninguna señal de que haya más.
/// - **No una barra inferior**: esta barra vive dentro de una solapa de `PresupuestosScreen`, no en
///   una pantalla propia; una barra inferior sería de toda la pantalla, no de esta solapa.
/// - **Sí una grilla de íconos con etiqueta**: entra el doble de acciones en el mismo alto, el ícono
///   se escanea de un vistazo, la etiqueta la hace descubrible, y con 8 acciones son dos filas
///   prolijas en vez de seis botones desordenados.
///
/// Pantalla angosta con fuente grande (donde ya falló antes, ver el comentario histórico del `Wrap`
/// de esta barra): la cantidad de columnas se calcula del ancho real (`LayoutBuilder`), entre 3 y 5,
/// y **ninguna altura está fijada** — cada ítem se mide solo y la fila crece si la etiqueta necesita
/// dos líneas. El texto nunca se recorta por el borde: como mucho pasa a la segunda línea.
class BarraAccionesObra extends StatelessWidget {
  final List<AccionObra> acciones;

  const BarraAccionesObra({super.key, required this.acciones});

  /// Ancho objetivo por ítem. No es un mínimo rígido: divide el ancho disponible en la mayor
  /// cantidad de columnas que entren con ~88px cada una, con 3 como piso (menos de 3 se ve como una
  /// lista, no como una barra) y 5 como techo (más columnas dejan las etiquetas ilegibles).
  static const double _anchoObjetivo = 88;
  static const double _separacion = 4;

  @override
  Widget build(BuildContext context) {
    if (acciones.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black12),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columnas = (constraints.maxWidth / _anchoObjetivo).floor().clamp(3, 5);
          final ancho =
              (constraints.maxWidth - _separacion * (columnas - 1)) / columnas;
          return Wrap(
            spacing: _separacion,
            runSpacing: 10,
            children: [
              for (final a in acciones) SizedBox(width: ancho, child: _Accion(accion: a)),
            ],
          );
        },
      ),
    );
  }
}

class _Accion extends StatelessWidget {
  final AccionObra accion;

  const _Accion({required this.accion});

  static const Color _azul = Color(0xFF1B365D);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: accion.onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: accion.destacada ? _azul : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: accion.destacada ? _azul : Colors.black12),
                  ),
                  child: Icon(
                    accion.icono,
                    size: 19,
                    color: accion.destacada ? Colors.white : _azul,
                  ),
                ),
                if ((accion.pendientes ?? 0) > 0)
                  Positioned(
                    top: -3,
                    right: -3,
                    // `clipBehavior: none` arriba es lo que deja que el globito se salga del círculo
                    // sin recortarse. Y "99+" en vez de un número de tres cifras: el globito crece y
                    // rompe la grilla de la barra, que se calcula por ancho.
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      constraints: const BoxConstraints(minWidth: 18),
                      decoration: BoxDecoration(
                        color: Colors.red.shade600,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: Text(
                        accion.pendientes! > 99 ? '99+' : '${accion.pendientes}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 9.5,
                          height: 1.1,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              accion.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10.5, height: 1.15, color: _azul, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
