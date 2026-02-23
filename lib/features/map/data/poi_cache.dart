import '../domain/poi.dart';

/// Cache simple avec TTL pour les résultats POI
/// Évite les refetch inutiles
class PoiCache {
  final Map<String, _CacheEntry> _cache = {};
  final Duration ttl;

  PoiCache({this.ttl = const Duration(minutes: 2)});

  /// Génère une clé de cache unique pour une requête
  String _generateKey({
    required double userLat,
    required double userLng,
    required double radiusMeters,
    required Set<String> categoryIds,
  }) {
    return '${userLat.toStringAsFixed(4)}_${userLng.toStringAsFixed(4)}_${radiusMeters.toInt()}_${categoryIds.join(",")}';
  }

  /// Récupère les POIs du cache s'ils sont valides
  List<Poi>? get({
    required double userLat,
    required double userLng,
    required double radiusMeters,
    required Set<String> categoryIds,
  }) {
    final key = _generateKey(
      userLat: userLat,
      userLng: userLng,
      radiusMeters: radiusMeters,
      categoryIds: categoryIds,
    );

    final entry = _cache[key];
    if (entry == null) return null;

    final elapsed = DateTime.now().difference(entry.timestamp);
    if (elapsed > ttl) {
      _cache.remove(key);
      return null;
    }

    return entry.pois;
  }

  /// Stocke les POIs en cache
  void put({
    required double userLat,
    required double userLng,
    required double radiusMeters,
    required Set<String> categoryIds,
    required List<Poi> pois,
  }) {
    final key = _generateKey(
      userLat: userLat,
      userLng: userLng,
      radiusMeters: radiusMeters,
      categoryIds: categoryIds,
    );

    _cache[key] = _CacheEntry(
      pois: pois,
      timestamp: DateTime.now(),
    );
  }

  /// Vide le cache
  void clear() {
    _cache.clear();
  }

  /// Nettoie les entries expirées
  void prune() {
    final now = DateTime.now();
    _cache.removeWhere((key, entry) {
      final elapsed = now.difference(entry.timestamp);
      return elapsed > ttl;
    });
  }
}

class _CacheEntry {
  final List<Poi> pois;
  final DateTime timestamp;

  _CacheEntry({
    required this.pois,
    required this.timestamp,
  });
}
