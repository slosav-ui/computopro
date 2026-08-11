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
      cardTheme: const CardThemeData(
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