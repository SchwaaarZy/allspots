import 'package:flutter/material.dart';

/// Classe helper pour gérer la responsivité sur tous les appareils mobiles
/// Gère: hauteurs d'images, tailles de police, breakpoints, padding/margin adaptatifs
class ResponsiveUtils {
  // Singleton pattern
  static final ResponsiveUtils _instance = ResponsiveUtils._internal();

  factory ResponsiveUtils() {
    return _instance;
  }

  ResponsiveUtils._internal();

  // Breakpoints (largueur d'écran en pixels)
  static const double mobileSmall = 280;     // iPhone SE
  static const double mobileMedium = 390;    // iPhone 12/13/14
  static const double mobileLarge = 600;     // Tablette petite
  static const double tabletSmall = 1024;    // iPad Mini
  static const double tabletLarge = 1366;    // iPad Pro

  /// Retourne la catégorie de device en fonction de sa largeur
  static DeviceCategory getDeviceCategory(double screenWidth) {
    if (screenWidth < mobileSmall) return DeviceCategory.small;
    if (screenWidth < mobileMedium) return DeviceCategory.small;
    if (screenWidth < mobileLarge) return DeviceCategory.medium;
    if (screenWidth < tabletSmall) return DeviceCategory.large;
    if (screenWidth < tabletLarge) return DeviceCategory.tablet;
    return DeviceCategory.tabletLarge;
  }

  /// Hauteur adaptative pour les images (ProfilePage, MapPage, CarouselImages)
  /// Exemples: 280px → 120px | 390px → 150px | 600px → 180px
  static double getImageHeight(double screenWidth, {double? customRatio}) {
    final category = getDeviceCategory(screenWidth);
    // Note: customRatio peut être utilisé à l'avenir pour des cas spécifiques
    // ignore: unused_local_variable
    final ratio = customRatio;

    switch (category) {
      case DeviceCategory.small:
        return 120; // iPhone SE
      case DeviceCategory.medium:
        return screenWidth * 0.38; // iPhone 12-14: ~150px
      case DeviceCategory.large:
        return screenWidth * 0.30; // Petit tablet: ~180px
      case DeviceCategory.tablet:
        return screenWidth * 0.25; // iPad: ~256px
      case DeviceCategory.tabletLarge:
        return screenWidth * 0.20; // iPad Pro: ~273px
    }
  }

  /// Taille de police adaptative
  static double getFontSize(double screenWidth, double baseSize) {
    final category = getDeviceCategory(screenWidth);
    final scaleFactor = _getScaleFactor(category);
    return baseSize * scaleFactor;
  }

  /// Facteur d'échelle pour les différentes catégories d'appareil
  static double _getScaleFactor(DeviceCategory category) {
    switch (category) {
      case DeviceCategory.small:
        return 0.85;
      case DeviceCategory.medium:
        return 1.0; // Référence
      case DeviceCategory.large:
        return 1.1;
      case DeviceCategory.tablet:
        return 1.3;
      case DeviceCategory.tabletLarge:
        return 1.5;
    }
  }

  /// Padding/Margin adaptatif
  static double getPadding(double screenWidth, {double? baseValue}) {
    final base = baseValue ?? 16.0;
    final category = getDeviceCategory(screenWidth);

    switch (category) {
      case DeviceCategory.small:
        return base * 0.75;
      case DeviceCategory.medium:
        return base;
      case DeviceCategory.large:
        return base * 1.25;
      case DeviceCategory.tablet:
        return base * 1.5;
      case DeviceCategory.tabletLarge:
        return base * 2.0;
    }
  }

  /// Largeur max adaptative pour les dialogs et modals
  static double getDialogMaxWidth(double screenWidth) {
    final category = getDeviceCategory(screenWidth);

    switch (category) {
      case DeviceCategory.small:
      case DeviceCategory.medium:
        return screenWidth * 0.9;
      case DeviceCategory.large:
        return screenWidth * 0.85;
      case DeviceCategory.tablet:
        return 600;
      case DeviceCategory.tabletLarge:
        return 800;
    }
  }

  /// Nombre de colonnes pour grille/liste responsive
  static int getGridColumns(double screenWidth) {
    final category = getDeviceCategory(screenWidth);

    switch (category) {
      case DeviceCategory.small:
        return 1;
      case DeviceCategory.medium:
        return 1;
      case DeviceCategory.large:
        return 2;
      case DeviceCategory.tablet:
        return 3;
      case DeviceCategory.tabletLarge:
        return 4;
    }
  }

  /// Spacing horizontal adaptatif (entre éléments)
  static double getHorizontalSpacing(double screenWidth) {
    return getPadding(screenWidth, baseValue: 12.0);
  }

  /// Spacing vertical adaptatif
  static double getVerticalSpacing(double screenWidth) {
    return getPadding(screenWidth, baseValue: 8.0);
  }

  /// Rayon de BorderRadius adaptatif
  static double getBorderRadius(double screenWidth) {
    final category = getDeviceCategory(screenWidth);

    switch (category) {
      case DeviceCategory.small:
        return 8.0;
      case DeviceCategory.medium:
        return 12.0;
      case DeviceCategory.large:
        return 16.0;
      case DeviceCategory.tablet:
        return 20.0;
      case DeviceCategory.tabletLarge:
        return 24.0;
    }
  }

  /// Hauteur de Button/ActionButton adaptative
  static double getButtonHeight(double screenWidth) {
    final category = getDeviceCategory(screenWidth);

    switch (category) {
      case DeviceCategory.small:
        return 40;
      case DeviceCategory.medium:
        return 48;
      case DeviceCategory.large:
        return 52;
      case DeviceCategory.tablet:
        return 56;
      case DeviceCategory.tabletLarge:
        return 60;
    }
  }

  /// Icon size adaptatif
  static double getIconSize(double screenWidth, {bool isLarge = false}) {
    final base = isLarge ? 32.0 : 24.0;
    final category = getDeviceCategory(screenWidth);
    final scaleFactor = _getScaleFactor(category);

    return base * scaleFactor;
  }

  /// Vérifie si on est sur mobile (< 600px)
  static bool isMobile(double screenWidth) => screenWidth < mobileLarge;

  /// Vérifie si on est sur tablet (>= 600px)
  static bool isTablet(double screenWidth) => screenWidth >= mobileLarge;
}

/// Énumération des catégories d'appareil
enum DeviceCategory {
  small,      // < 390px (iPhone SE)
  medium,     // 390-600px (iPhone 12-14)
  large,      // 600-1024px (Petit tablet)
  tablet,     // 1024-1366px (iPad)
  tabletLarge // >= 1366px (iPad Pro)
}

/// Extension pour faciliter accès au responsive depuis BuildContext
extension ResponsiveExtension on BuildContext {
  double get screenWidth => MediaQuery.of(this).size.width;
  double get screenHeight => MediaQuery.of(this).size.height;
  double get imageHeight => ResponsiveUtils.getImageHeight(screenWidth);
  double get padding => ResponsiveUtils.getPadding(screenWidth);
  double get buttonHeight => ResponsiveUtils.getButtonHeight(screenWidth);
  bool get isMobile => ResponsiveUtils.isMobile(screenWidth);
  bool get isTablet => ResponsiveUtils.isTablet(screenWidth);

  double fontSize(double baseSize) => ResponsiveUtils.getFontSize(screenWidth, baseSize);
  double iconSize({bool isLarge = false}) => ResponsiveUtils.getIconSize(screenWidth, isLarge: isLarge);
  int gridColumns() => ResponsiveUtils.getGridColumns(screenWidth);
}
