import 'package:flutter/material.dart';

/// Configuration de performance globale
class PerformanceConfig {
  // Max de POIs à afficher simultanément sur la carte
  // Au-delà, c'est trop lourd pour le GPU
  static const int maxMarkersPerView = 40;

  // Délai avant d'afficher le prochain batch de POIs
  // Plus ce délai est long, plus fluide est l'app
  static const Duration batchLoadDelay = Duration(milliseconds: 150);

  // Limite de recherche en cas de requête gourmande
  static const int maxSearchResults = 200;

  // Délai minimum entre deux refetch (debounce)
  static const Duration minRefreshInterval = Duration(seconds: 2);

  // Seuil de variation du rayon avant refetch (en %)
  static const double radiusDeltaThreshold = 0.05; // 5%

  // Cache TTL
  static const Duration cacheTTL = Duration(minutes: 2);

  // Frame rate cible (60 FPS = ~16.7ms par frame)
  // On vise 60 FPS pour fluidité
  static const int targetFPS = 60;
  static Duration get targetFrameTime =>
      Duration(milliseconds: (1000 / targetFPS).round());

  // Nombre d'images à charger en parallèle (évite saturation réseau)
  static const int maxConcurrentImageLoads = 3;

  // Taille max des images en cache (en MB)
  static const int imageCacheSizeMB = 100;
}

/// Utilitaires de performance
class PerformanceUtils {
  /// Mesure le temps d'exécution d'une fonction
  static Future<T> measureDuration<T>(
    String label,
    Future<T> Function() fn,
  ) async {
    final stopwatch = Stopwatch()..start();
    try {
      return await fn();
    } finally {
      stopwatch.stop();
      debugPrint(
        '⏱️ $label took ${stopwatch.elapsedMilliseconds}ms',
      );
    }
  }

  /// Throttle: exécute une fonction au max une fois par période
  static VoidCallback throttle(
    Function() fn, {
    Duration duration = const Duration(milliseconds: 500),
  }) {
    DateTime? lastCall;
    return () {
      final now = DateTime.now();
      if (lastCall == null || now.difference(lastCall!) > duration) {
        lastCall = now;
        fn();
      }
    };
  }

  /// Check si on peut faire la prochaine recherche (throttle)
  static bool canRefresh(Duration minInterval, DateTime? lastRefresh) {
    if (lastRefresh == null) return true;
    final elapsed = DateTime.now().difference(lastRefresh);
    return elapsed >= minInterval;
  }
}
