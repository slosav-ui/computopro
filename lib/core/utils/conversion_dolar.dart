/// Convierte un monto guardado en ARS -- todo el sistema de precios de ComputoPRO trabaja en
/// pesos, sin importar en qué moneda esté dada de alta la obra -- a la moneda de visualización
/// que corresponda. Mismo criterio que ya usa `ObrasListScreen._convertirMonto` para el
/// presupuesto vivo: promedio compra/venta BNA, sin la "Proyección/Dólar Libre" personalizada
/// (PRO) de esa pantalla -- esa es puramente sesión local de `ObrasListScreen`, nunca se persiste,
/// así que no hay nada que reusar de ahí desde otra pantalla.
///
/// `cotizacion <= 0` o `moneda` distinta de `'USD'` devuelve el monto tal cual, sin convertir --
/// fallo seguro, nunca una división por cero ni un monto inventado.
double convertirArsAMoneda(double montoArs, String moneda, double cotizacion) {
  if (moneda != 'USD' || cotizacion <= 0) return montoArs;
  return montoArs / cotizacion;
}
