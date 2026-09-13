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
      // Sombra navy y `elevation: 3` (2026-09-13, conclusión del barrido de
      // docs/barrido_cards_theme_blanco.md §5): el problema de las 21 pantallas con `Card` no era que
      // la tarjeta quedara plana -- ya tenía la sombra de `elevation: 1.5` -- sino que esa sombra es
      // floja para el fondo `F4F6F8` que todas heredan. Un solo cambio acá en vez de doce por
      // pantalla.
      //
      // **El navy va a opacidad PLENA (`0xFF1B365D`), no al 10% como en la tarjeta de MIS OBRAS.**
      // Flutter aplica su propia rampa de opacidad según la elevación: si el color ya viene al 10%,
      // la multiplica de nuevo y la sombra desaparece. Acá la intensidad se regula con `elevation`,
      // no con la opacidad del color. Si queda floja, 4; más que eso, mirarlo antes.
      //
      // `CardThemeData` no acepta `boxShadow`, así que el desplazamiento `(2,3)` de MIS OBRAS no se
      // puede replicar desde el theme -- el offset lo calcula Flutter desde la elevación. Queda
      // parecido pero no idéntico, y está bien: la portada tiene tratamiento propio (un `Container`
      // que no hereda nada de acá) y ninguna otra tarjeta se convierte en `Container` para imitarla.
      //
      // `margin` y `shape` quedan tal cual estaban.
      cardTheme: const CardThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        shadowColor: Color(0xFF1B365D),
        elevation: 3,
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