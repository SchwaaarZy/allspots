import 'dart:async';
import 'dart:math' as math;
import '../domain/poi.dart';

// Helper pour éviter import explicite de dart:math
double sin(double x) => math.sin(x);
double cos(double x) => math.cos(x);
double sqrt(double x) => math.sqrt(x);
double atan2(double a, double b) => math.atan2(a, b);

/// Gestionnaire pour charger les POIs par batches (lazy loading)
/// Évite de créer 500+ widgets d'un coup
class PoiBatchLoader {
  final List<Poi> allPois;
  final int batchSize;
  final Duration delayBetweenBatches;

  PoiBatchLoader({
    required this.allPois,
    this.batchSize = 20,
    this.delayBetweenBatches = const Duration(milliseconds: 100),
  });

  /// Charge les POIs par batches
  /// Retourne un stream de listes croissantes de POIs
  Stream<List<Poi>> loadInBatches() async* {
    final totalBatches = (allPois.length / batchSize).ceil();
    
    for (int i = 0; i < totalBatches; i++) {
      final end = (i + 1) * batchSize;
      final endIndex = end > allPois.length ? allPois.length : end;
      
      // Yield la liste croissante (tous les POIs jusqu'à maintenant)
      yield allPois.sublist(0, endIndex);
      
      // Attendre avant le prochain batch (évite la saturation GPU)
      if (i < totalBatches - 1) {
        await Future.delayed(delayBetweenBatches);
      }
    }
  }

  /// Filtre les POIs visibles à l'écran (viewport)
  /// Utilise un rayon pour pré-filtrer avant virtualization
  List<Poi> getVisibleInViewport({
    required double centerLat,
    required double centerLng,
    required double radiusMeters,
  }) {
    return allPois
        .where(
          (poi) => _distanceMeters(centerLat, centerLng, poi.lat, poi.lng) <=
              radiusMeters,
        )
        .toList();
  }

  /// Calcul rapide de distance en mètres
  static double _distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const R = 6371000;
    final dLat = (lat2 - lat1) * 3.14159 / 180;
    final dLon = (lon2 - lon1) * 3.14159 / 180;
    final a = (sin(dLat / 2) * sin(dLat / 2)) +
        cos(lat1 * 3.14159 / 180) *
            cos(lat2 * 3.14159 / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  /// Calcul rapide: approximation pour distances courtes
  static double distanceKm(double lat1, double lon1, double lat2, double lon2) {
    return _distanceMeters(lat1, lon1, lat2, lon2) / 1000;
  }
}
