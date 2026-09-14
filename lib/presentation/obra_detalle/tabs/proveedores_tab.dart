import 'package:flutter/material.dart';

/// Solapa Proveedores — en construcción.
///
/// Hasta hoy esta pantalla mostraba un directorio con proveedores inventados ("Corralón El Valle",
/// "Electrostock S.A.") que no salían de la base ni se guardaban en ningún lado. Se reemplazó por
/// este anticipo antes de mostrarle la app a arquitectos: **es mejor que vean que va a estar a que
/// entren a un borrador** y crean que eso es lo construido. La versión anterior queda en el
/// historial de git si hace falta mirar el armado visual.
///
/// Ojo con la historia de este archivo: el `ProveedoresTab` que vivía acá **no lo usaba nadie** --
/// la solapa que se ve en la app la arma `_buildTabProveedores()` dentro de `presupuestos_screen.
/// dart`, y era otro mock distinto, con otros proveedores inventados. Ahora hay un solo lugar: esa
/// función devuelve este widget.
///
/// El diseño de lo que va a ir acá está cerrado y sin construir:
/// `docs/proveedores_canje_diseno.md`. Lo que se muestra abajo es la parte que le sirve saber al
/// usuario de la app — el trato con el proveedor no se cuenta acá.
class ProveedoresEnConstruccion extends StatelessWidget {
  const ProveedoresEnConstruccion({super.key});

  static const _azul = Color(0xFF1B365D);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_shipping_outlined, color: _azul, size: 26),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Proveedores',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: _azul),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'En construcción',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.amber.shade900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            'Pedir cotización sin volver a cargar nada',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _azul),
          ),
          const SizedBox(height: 10),
          Text(
            'La app ya sabe qué materiales lleva la obra y en qué cantidad. Esta solapa va a usar ese '
            'cómputo para pedirle precio a los proveedores de la zona, sin rehacer la lista a mano.',
            style: TextStyle(fontSize: 13.5, height: 1.5, color: Colors.grey.shade800),
          ),
          const SizedBox(height: 24),
          _Punto(
            icono: Icons.request_quote_outlined,
            titulo: 'El pedido sale con el cómputo hecho',
            detalle:
                'El proveedor recibe la lista de materiales con sus cantidades, no una consulta suelta.',
          ),
          _Punto(
            icono: Icons.category_outlined,
            titulo: 'Cada pedido va a quien corresponde',
            detalle:
                'Los materiales se agrupan por rubro comercial, para no pedirle revestimientos a un '
                'corralón de obra gruesa.',
          ),
          _Punto(
            icono: Icons.pin_drop_outlined,
            titulo: 'Y siempre podés elegir vos',
            detalle: 'Si ya trabajás con alguien, el pedido va a ese proveedor y listo.',
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 18, color: Colors.grey.shade600),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Mientras tanto, los precios de los materiales se cargan y se comparan desde la '
                    'solapa Mat y MO, que ya está funcionando.',
                    style: TextStyle(fontSize: 12.5, height: 1.45, color: Colors.grey.shade700),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Punto extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String detalle;

  const _Punto({required this.icono, required this.titulo, required this.detalle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 20, color: const Color(0xFF1B365D)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1B365D),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detalle,
                  style: TextStyle(fontSize: 12.5, height: 1.4, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
