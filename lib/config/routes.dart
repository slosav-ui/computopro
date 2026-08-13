import 'package:flutter/material.dart';
import '../presentation/dashboard/obras_list_screen.dart';
import '../presentation/obra_detalle/screens/presupuestos_screen.dart';

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