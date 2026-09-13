import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF1E88E5),
        primary: const Color(0xFF1E88E5),
        secondary: const Color(0xFF26A69A),
        surface: Colors.white,),
      scaffoldBackgroundColor: const Color(0xFFF4F6F8),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1E88E5),
        foregroundColor: Colors.white,
        elevation: 2,
        centerTitle: true,
      ),
      // `color` y `surfaceTintColor` explícitos (2026-09-13): en Material 3 el color por defecto de
      // `Card` NO es blanco -- es `colorScheme.surfaceContainerLow`, que Flutter deriva del
      // `seedColor` azul de arriba, y da un lavanda muy claro. Nunca fue una decisión de diseño:
      // era un default heredado que quedaba casi del mismo tono que el fondo del listado, y por eso
      // las tarjetas se fundían con el fondo (el caso se detectó en MIS OBRAS, ver
      // docs/criterio_pantalla_principal_vs_resumen.md §5.4).
      //
      // `surfaceTintColor: Colors.transparent` es el complemento necesario: sin eso, Material 3
      // vuelve a teñir la superficie según la elevación y el blanco se ensucia igual.
      //
      // Las tarjetas que declaran su propio `color` (navy, ámbar, `EAF1FB`, etc.) no se ven
      // afectadas -- el `color` de la instancia le gana al del theme.
      //
      // El resto (elevation, margin, shape) queda tal cual estaba.
      cardTheme: const CardThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 1.5,
        margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: Color(0xFF1E88E5),
        foregroundColor: Colors.white,
      ),
    ); // <-- Cierra el ThemeData
  } // <-- Cierra el método lightTheme
} // <-- Cierra la clase AppTheme