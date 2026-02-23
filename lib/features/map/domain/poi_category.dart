import 'package:flutter/material.dart';

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
    // Import dynamique pour éviter les dépendances circulaires
    try {
      // ignore: avoid_dynamic_calls
      final l10n = (context as dynamic).l10n;
      switch (this) {
        case PoiCategory.culture:
          return l10n.cultureCategoryLabel ?? label;
        case PoiCategory.nature:
          return l10n.natureCategoryLabel ?? label;
        case PoiCategory.experienceGustative:
          return l10n.experienceGustativeCategoryLabel ?? label;
        case PoiCategory.histoire:
          return l10n.histoireCategoryLabel ?? label;
        case PoiCategory.activites:
          return l10n.activitesCategoryLabel ?? label;
      }
    } catch (_) {
      // En cas d'erreur, retourner le label par défaut
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
  switch (value.toLowerCase()) {
    case 'culture':
      return PoiCategory.culture;
    case 'nature':
      return PoiCategory.nature;
    case 'experiencegustative':
    case 'experience gustative':
      return PoiCategory.experienceGustative;
    case 'histoire':
      return PoiCategory.histoire;
    case 'activites':
      return PoiCategory.activites;
    default:
      return PoiCategory.culture;
  }
}

String formatPoiSubCategory(String? value) {
  if (value == null || value.trim().isEmpty) return '';
  final normalized = value.trim().toLowerCase();
  const map = {
    'art_gallery': "Galerie d'art",
    'park': 'Parc',
    'tourist_attraction': 'Attraction touristique',
    'museum': 'Musee',
    'cafe': 'Cafe',
    'restaurant': 'Restaurant',
    'natural_feature': 'Site naturel',
    'scenic_viewpoint': 'Point de vue',
    'hiking_area': 'Zone de randonnee',
    'sports_complex': 'Complexe sportif',
    'stadium': 'Stade',
    'church': 'Eglise',
    'place_of_worship': 'Lieu de culte',
    'mosque': 'Mosquee',
    'synagogue': 'Synagogue',
    'castle': 'Chateau',
    'campground': 'Camping',
    'market': 'Marche',
    'sporting_goods_store': 'Magasin de sport',
    'zoo': 'Zoo',
    'library': 'Bibliotheque',
    'amusement_park': 'Parc d\'attractions',
    'gym': 'Salle de sport',
  };
  final mapped = map[normalized];
  if (mapped != null) return mapped;

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
