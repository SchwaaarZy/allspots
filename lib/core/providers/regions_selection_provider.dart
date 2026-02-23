import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Provider pour accéder à SharedPreferences
final sharedPreferencesProvider = FutureProvider<SharedPreferences>((ref) async {
  return SharedPreferences.getInstance();
});

/// Provider pour gérer si la France a été sélectionnée
final franceSelectedProvider = StateNotifierProvider<FranceSelectedNotifier, bool>((ref) {
  return FranceSelectedNotifier(ref);
});

/// Provider pour vérifier si la sélection initiale a été faite
final hasCompletedRegionSelectionProvider = FutureProvider<bool>((ref) async {
  final prefs = await ref.watch(sharedPreferencesProvider.future);
  return prefs.getBool('has_completed_region_selection') ?? false;
});

/// Provider pour obtenir les codes de départements sélectionnés (pour compatibilité)
final selectedDepartmentCodesProvider = Provider<List<String>>((ref) {
  final franceSel = ref.watch(franceSelectedProvider);
  // Si France est sélectionnée, retourner une liste spéciale (on ne filtre pas par département)
  return franceSel ? ['ALL_FRANCE'] : [];
});

/// Notifier pour gérer la sélection de la France
class FranceSelectedNotifier extends StateNotifier<bool> {
  FranceSelectedNotifier(this.ref) : super(false) {
    _loadSavedSelection();
  }

  final Ref ref;

  /// Charger la sélection sauvegardée
  Future<void> _loadSavedSelection() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final selected = prefs.getBool('france_selected') ?? false;
      state = selected;
    } catch (e) {
      debugPrint('[FranceSelected] Error loading: $e');
      state = false;
    }
  }

  /// Sélectionner la France
  Future<void> selectFrance() async {
    state = true;
    await _saveSelection(true);
  }

  /// Désélectionner la France
  Future<void> deselectFrance() async {
    state = false;
    await _saveSelection(false);
  }

  /// Sauvegarder la sélection
  Future<void> _saveSelection(bool selected) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('france_selected', selected);
    } catch (e) {
      debugPrint('[FranceSelected] Error saving: $e');
    }
  }

  /// Marquer que la sélection initiale a été complétée
  Future<void> completeInitialSelection() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('has_completed_region_selection', true);
    } catch (e) {
      debugPrint('[FranceSelected] Error completing selection: $e');
    }
  }

  /// Réinitialiser la sélection
  Future<void> resetSelection() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('france_selected');
      await prefs.remove('has_completed_region_selection');
      state = false;
    } catch (e) {
      debugPrint('[FranceSelected] Error resetting: $e');
    }
  }
}
