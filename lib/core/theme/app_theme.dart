import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static ThemeData light() {
    const primaryBlue = Color(0xFF3B82F6);
    const accentGreen = Color(0xFF10B981);
    const glassTopBlue = Color(0xFF38BDF8);
    const appRadius = 24.0;
    final roundedShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(appRadius),
    );

    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: Colors.white,
      fontFamily: GoogleFonts.oswald().fontFamily,
      textTheme: GoogleFonts.oswaldTextTheme(),
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryBlue,
        primary: primaryBlue,
        secondary: accentGreen,
        surfaceTint: Colors.white,
        surface: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: primaryBlue,
        foregroundColor: Colors.black,
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: Colors.black,
        ),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: glassTopBlue,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        selectedItemColor: primaryBlue,
        unselectedItemColor: Colors.black54,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
      ),
      cardTheme: CardThemeData(shape: roundedShape),
      dialogTheme: DialogThemeData(shape: roundedShape),
      bottomSheetTheme: BottomSheetThemeData(shape: roundedShape),
      snackBarTheme: SnackBarThemeData(shape: roundedShape),
      menuTheme: MenuThemeData(style: MenuStyle(shape: WidgetStateProperty.all(roundedShape))),
      popupMenuTheme: PopupMenuThemeData(shape: roundedShape),
      chipTheme: ChipThemeData(shape: roundedShape),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(appRadius),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(appRadius),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(appRadius),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(appRadius),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: roundedShape),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(shape: roundedShape),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          shape: roundedShape,
          elevation: 0,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: primaryBlue.withValues(alpha: 0.18),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? primaryBlue : Colors.black54);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontFamily: GoogleFonts.oswald().fontFamily,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: selected ? primaryBlue : Colors.black54,
          );
        }),
      ),
    );
  }
}
