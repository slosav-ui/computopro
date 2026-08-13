// lib/core/utils/currency_formatter.dart

import 'package:intl/intl.dart';

class CurrencyFormatter {
  // Formateador para pesos argentinos ($ 185.000,00)
  static String formatARS(double amount) {
    final formatter = NumberFormat.currency(
      locale: 'es_AR',
      symbol: '\$',
      decimalDigits: 2,
    );
    return formatter.format(amount);
  }

  // Formateador para dólares (USD 1,365.00)
  static String formatUSD(double amount) {
    final formatter = NumberFormat.currency(
      locale: 'en_US',
      symbol: 'USD ',
      decimalDigits: 2,
    );
    return formatter.format(amount);
  }

  // Formateador dinámico según el tipo de moneda ('ARS' o 'USD')
  static String formatByCurrency(double amount, String currencyType) {
    if (currencyType.toUpperCase() == 'USD') {
      return formatUSD(amount);
    }
    return formatARS(amount);
  }

  // Formateador para superficies en metros cuadrados (ej: 185.5 m²)
  static String formatSurface(double area) {
    return '${area.toStringAsFixed(1)} m²';
  }
}