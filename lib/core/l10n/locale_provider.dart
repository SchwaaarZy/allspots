import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Provider pour gérer la locale (FR/EN)
final localeProvider = StateProvider<Locale>((ref) {
  // Détecte la locale du système par défaut
  // Sinon utilise le français (FR)
  return const Locale('fr');
});

/// Fonction pour changer la langue
Future<void> changeLanguage(WidgetRef ref, String languageCode) async {
  ref.read(localeProvider.notifier).state = Locale(languageCode);
  // TPersister le choix dans SharedPreferences si souhaité
}
