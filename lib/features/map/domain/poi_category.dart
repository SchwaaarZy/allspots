import 'package:flutter/material.dart';
import '../../../core/l10n/app_localizations.dart';

enum PoiCategory {
  culture,
  nature,
  experienceGustative,
  histoire,
  activites,
}

extension PoiCategoryX on PoiCategory {
  /// Récupère le label français (par défaut)
  String get label {
    switch (this) {
      case PoiCategory.culture:
        return 'Culture';
      case PoiCategory.nature:
        return 'Nature';
      case PoiCategory.experienceGustative:
        return 'Expérience gustative';
      case PoiCategory.histoire:
        return 'Histoire';
      case PoiCategory.activites:
        return 'Activités';
    }
  }

  /// Récupère le label localisé (FR/EN) depuis le context
  String localizationLabel(BuildContext context) {
    try {
      final l10n = AppLocalizations.of(context);
      switch (this) {
        case PoiCategory.culture:
          return l10n.cultureCategoryLabel;
        case PoiCategory.nature:
          return l10n.natureCategoryLabel;
        case PoiCategory.experienceGustative:
          return l10n.experienceGustativeCategoryLabel;
        case PoiCategory.histoire:
          return l10n.histoireCategoryLabel;
        case PoiCategory.activites:
          return l10n.activitesCategoryLabel;
      }
    } catch (_) {
      // En cas d'erreur, retourner le label français par défaut
      return label;
    }
  }

  IconData get icon {
    switch (this) {
      case PoiCategory.culture:
        return Icons.museum;
      case PoiCategory.nature:
        return Icons.park;
      case PoiCategory.experienceGustative:
        return Icons.restaurant;
      case PoiCategory.histoire:
        return Icons.account_balance;
      case PoiCategory.activites:
        return Icons.directions_run;
    }
  }

  Color get color {
    switch (this) {
      case PoiCategory.culture:
        return Colors.deepPurple;
      case PoiCategory.nature:
        return Colors.green;
      case PoiCategory.experienceGustative:
        return Colors.orange;
      case PoiCategory.histoire:
        return Colors.brown;
      case PoiCategory.activites:
        return Colors.blue;
    }
  }
}

/// Convertit une string en PoiCategory
PoiCategory poiCategoryFromString(String value) {
  final normalized = value
      .toLowerCase()
      .trim()
      .replaceAll('é', 'e')
      .replaceAll('è', 'e')
      .replaceAll('ê', 'e')
      .replaceAll('à', 'a')
      .replaceAll('â', 'a')
      .replaceAll('ù', 'u')
      .replaceAll('û', 'u')
      .replaceAll('ô', 'o')
      .replaceAll('î', 'i')
      .replaceAll('ï', 'i')
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  if (normalized.contains('patrimoine') || normalized.contains('histoire')) {
    return PoiCategory.histoire;
  }
  if (normalized.contains('nature')) {
    return PoiCategory.nature;
  }
  if (normalized.contains('culture')) {
    return PoiCategory.culture;
  }
  if (normalized.contains('experience') || normalized.contains('gustative')) {
    return PoiCategory.experienceGustative;
  }
  if (normalized.contains('activite') || normalized.contains('plein air')) {
    return PoiCategory.activites;
  }

  return PoiCategory.culture;
}

String formatPoiSubCategory(String? value) {
  if (value == null || value.trim().isEmpty) return '';
  final normalized = value.trim().toLowerCase();
  
  // Dictionnaire complet de traductions FR/EN
  const map = {
    // Attractions
    'art_gallery': "Galerie d'art",
    'park': 'Parc',
    'tourist_attraction': 'Attraction touristique',
    'attraction': 'Attraction',
    'museum': 'Musée',
    'gallery': 'Galerie',
    'monument': 'Monument',
    'memorial': 'Mémorial',
    
    // Restauration
    'cafe': 'Café',
    'restaurant': 'Restaurant',
    'bar': 'Bar',
    'pub': 'Pub',
    'fast_food': 'Restauration rapide',
    'bistro': 'Bistro',
    'bakery': 'Boulangerie',
    
    // Nature
    'natural_feature': 'Site naturel',
    'scenic_viewpoint': 'Point de vue',
    'viewpoint': 'Point de vue',
    'hiking_area': 'Zone de randonnée',
    'forest': 'Forêt',
    'mountain': 'Montagne',
    'waterfall': 'Cascade',
    'water': 'Plan d\'eau',
    'lake': 'Lac',
    'river': 'Rivière',
    'beach': 'Plage',
    'valley': 'Vallée',
    
    // Activités
    'sports_complex': 'Complexe sportif',
    'stadium': 'Stade',
    'gym': 'Salle de sport',
    'sports': 'Sports',
    'tennis': 'Tennis',
    'swimming_pool': 'Piscine',
    'ski': 'Ski',
    'climbing': 'Escalade',
    'golf': 'Golf',
    
    // Histoire/Culture
    'church': 'Église',
    'place_of_worship': 'Lieu de culte',
    'mosque': 'Mosquée',
    'synagogue': 'Synagogue',
    'temple': 'Temple',
    'castle': 'Château',
    'archaeological_site': 'Site archéologique',
    'historic_site': 'Site historique',
    'ruins': 'Ruines',
    'fort': 'Fort',
    'abbey': 'Abbaye',
    'chateau': 'Château',
    
    // Commerce/Loisirs
    'campground': 'Camping',
    'market': 'Marché',
    'sporting_goods_store': 'Magasin de sport',
    'zoo': 'Zoo',
    'library': 'Bibliothèque',
    'amusement_park': 'Parc d\'attractions',
    'cinema': 'Cinéma',
    'theatre': 'Théâtre',
    'theatre_cinema': 'Théâtre/Cinéma',
    
    // Autres/Défaut
    'other': 'Autre',
    'poi': 'Point d\'intérêt',
    'landmark': 'Point de repère',
  };
  
  final mapped = map[normalized];
  if (mapped != null) return mapped;

  // Fallback: formater en titrant les mots
  final words = normalized
      .replaceAll('-', ' ')
      .replaceAll('_', ' ')
      .split(' ')
      .where((w) => w.isNotEmpty)
      .toList();
  return words
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
}

IconData iconForSubCategory(String? value, PoiCategory fallbackCategory) {
  if (value == null || value.trim().isEmpty) return fallbackCategory.icon;
  final normalized = value.trim().toLowerCase();

  const iconMap = {
    // Attractions
    'art_gallery': Icons.brush,
    'park': Icons.park,
    'tourist_attraction': Icons.attractions,
    'attraction': Icons.attractions,
    'museum': Icons.museum,
    'gallery': Icons.image,
    'monument': Icons.account_balance,
    'memorial': Icons.flag,

    // Restauration
    'cafe': Icons.local_cafe,
    'restaurant': Icons.restaurant,
    'bar': Icons.local_bar,
    'pub': Icons.local_bar,
    'fast_food': Icons.fastfood,
    'bistro': Icons.restaurant,
    'bakery': Icons.local_dining,

    // Nature
    'natural_feature': Icons.landscape,
    'scenic_viewpoint': Icons.remove_red_eye,
    'viewpoint': Icons.remove_red_eye,
    'hiking_area': Icons.hiking,
    'forest': Icons.park,
    'mountain': Icons.terrain,
    'waterfall': Icons.water,
    'water': Icons.water,
    'lake': Icons.water,
    'river': Icons.water,
    'beach': Icons.beach_access,
    'valley': Icons.landscape,

    // Activites
    'sports_complex': Icons.sports,
    'stadium': Icons.sports_soccer,
    'gym': Icons.fitness_center,
    'sports': Icons.sports,
    'tennis': Icons.sports_tennis,
    'swimming_pool': Icons.pool,
    'ski': Icons.sports,
    'climbing': Icons.terrain,
    'golf': Icons.golf_course,
  };

  return iconMap[normalized] ?? fallbackCategory.icon;
}
