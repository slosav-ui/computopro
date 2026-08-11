import 'package:flutter/material.dart';
import '../screens/obras/obras_list_screen.dart';
import '../screens/presupuestos/presupuestos_screen.dart';

class AppRoutes {
  static const String obrasList = '/';
  static const String presupuestos = '/presupuestos';

  static Map<String, WidgetBuilder> getRoutes() {
    return {
      obrasList: (context) => const ObrasListScreen(),
      presupuestos: (context) => const PresupuestosScreen(),
    };
  }
}