import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/poi.dart';

/// Cache simple avec TTL pour les résultats POI
/// Évite les refetch inutiles
class PoiCache {
  final Map<String, _CacheEntry> _cache = {};
  final Duration ttl;

  PoiCache({this.ttl = const Duration(minutes: 2)});

  static String buildKey({
    required double userLat,
    required double userLng,
    required double radiusMeters,
    required Set<String> categoryIds,
  }) {
    return '${userLat.toStringAsFixed(4)}_${userLng.toStringAsFixed(4)}_${radiusMeters.toInt()}_${categoryIds.join(",")}';
  }

  /// Génère une clé de cache unique pour une requête
  String _generateKey({
    required double userLat,
    required double userLng,
    required double radiusMeters,
    required Set<String> categoryIds,
  }) {
    return buildKey(
      userLat: userLat,
      userLng: userLng,
      radiusMeters: radiusMeters,
      categoryIds: categoryIds,
    );
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

class PersistentPoiCache {
  static const String _storageKey = 'poi_cache_v1';
  final Duration ttl;

  PersistentPoiCache({this.ttl = const Duration(minutes: 10)});

  Future<List<Poi>?> get({required String cacheKey}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return null;

    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final entries = decoded['entries'] as Map<String, dynamic>?;
    if (entries == null) return null;

    final entry = entries[cacheKey] as Map<String, dynamic>?;
    if (entry == null) return null;

    final ts = entry['ts'] as int?;
    if (ts == null) return null;

    final elapsed = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(ts),
    );
    if (elapsed > ttl) {
      entries.remove(cacheKey);
      await prefs.setString(_storageKey, jsonEncode(decoded));
      return null;
    }

    final poisRaw = entry['pois'] as List?;
    if (poisRaw == null) return null;

    return poisRaw
        .whereType<Map<String, dynamic>>()
        .map(Poi.fromCacheMap)
        .toList();
  }

  Future<void> put({
    required String cacheKey,
    required List<Poi> pois,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    final decoded = raw == null || raw.isEmpty
        ? <String, dynamic>{'entries': <String, dynamic>{}}
        : jsonDecode(raw) as Map<String, dynamic>;

    final entries = decoded['entries'] as Map<String, dynamic>;
    entries[cacheKey] = {
      'ts': DateTime.now().millisecondsSinceEpoch,
      'pois': pois.map((p) => p.toCacheMap()).toList(),
    };

    await prefs.setString(_storageKey, jsonEncode(decoded));
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
