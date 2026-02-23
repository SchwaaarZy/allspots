import 'package:flutter/material.dart';
import 'l10n_fr.dart';
import 'l10n_en.dart';

/// Classe pour gérer les traductions de l'app (FR/EN)
/// Utilisation: context.l10n.categoryName('culture')
class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        AppLocalizations(const Locale('fr'));
  }

  /// Récupère les chaînes de traduction
  late final _strings = _getStrings();

  Map<String, String> _getStrings() {
    if (locale.languageCode == 'fr') {
      return frStrings;
    }
    return enStrings;
  }

  /// Catégories
  String get cultureCategoryLabel => _strings['culture_label'] ?? 'Culture';
  String get natureCategoryLabel => _strings['nature_label'] ?? 'Nature';
  String get experienceGustativeCategoryLabel =>
      _strings['experience_gustative_label'] ?? 'Expérience gustative';
  String get histoireCategoryLabel => _strings['histoire_label'] ?? 'Histoire';
  String get activitesCategoryLabel =>
      _strings['activites_label'] ?? 'Activités';

  /// Noms génériques
  String get appTitle => _strings['app_title'] ?? 'AllSpots';
  String get mapTitle => _strings['map_title'] ?? 'Carte';
  String get searchTitle => _strings['search_title'] ?? 'Recherche';
  String get profileTitle => _strings['profile_title'] ?? 'Profil';

  /// Boutons et actions
  String get viewDetails => _strings['view_details'] ?? 'Voir détails';
  String get addToRoadTrip => _strings['add_to_road_trip'] ?? 'Ajouter au road trip';
  String get centerMe => _strings['center_me'] ?? 'Me centrer';
  String get legend => _strings['legend'] ?? 'Légende';

  /// Messages
  String get loading => _strings['loading'] ?? 'Chargement...';
  String get error => _strings['error'] ?? 'Erreur';
  String get ok => _strings['ok'] ?? 'OK';

  /// Catégorie dynamique
  String categoryLabel(String categoryKey) {
    switch (categoryKey) {
      case 'culture':
        return cultureCategoryLabel;
      case 'nature':
        return natureCategoryLabel;
      case 'experience_gustative':
      case 'experienceGustative':
        return experienceGustativeCategoryLabel;
      case 'histoire':
        return histoireCategoryLabel;
      case 'activites':
        return activitesCategoryLabel;
      default:
        return categoryKey;
    }
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return ['fr', 'en'].contains(locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

/// Extension pour accès rapide: context.l10n
extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
