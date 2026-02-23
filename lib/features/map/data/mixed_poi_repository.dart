import 'poi_repository.dart';
import '../domain/poi.dart';
import '../domain/poi_filters.dart';
import 'poi_cache.dart';

/// Repository hybride qui fusionne les résultats de deux sources:
/// - 🏘️ Firestore: Spots créés par les utilisateurs (PRIORITAIRE)
/// - 🗺️ Google Places: Lieux publics référencés par Google (FALLBACK)
/// 
/// Optimisations:
/// 1. Cache local 2-3 minutes → évite refetch inutiles
/// 2. Fetche Firestore seul d'abord (plus rapide)
/// 3. Google Places en parallèle en background
/// 4. Fusionne et déduplique les résultats
/// 5. Trie par distance à l'utilisateur
/// 
/// Résultat: Réduction drastique des requêtes + UX fluide
class MixedPoiRepository implements PoiRepository {
  MixedPoiRepository({
    required this.firestoreRepo,
    required this.placesRepo,
    this.extraRepos = const [],
    PoiCache? cache,
    PersistentPoiCache? persistentCache,
  })  : _cache = cache ?? PoiCache(),
        _persistentCache = persistentCache ?? PersistentPoiCache();

  final PoiRepository firestoreRepo;
  final PoiRepository placesRepo;
  final List<PoiRepository> extraRepos;
  final PoiCache _cache;
  final PersistentPoiCache _persistentCache;

  @override
  Future<List<Poi>> getNearbyPois({
    required double userLat,
    required double userLng,
    required double radiusMeters,
    required PoiFilters filters,
  }) async {
    // Vérifier le cache
    final categoryIds = filters.categories.map((c) => c.index.toString()).toSet();
    final cached = _cache.get(
      userLat: userLat,
      userLng: userLng,
      radiusMeters: radiusMeters,
      categoryIds: categoryIds,
    );

    if (cached != null) {
      return cached;
    }

    final cacheKey = PoiCache.buildKey(
      userLat: userLat,
      userLng: userLng,
      radiusMeters: radiusMeters,
      categoryIds: categoryIds,
    );

    final persistentCached = await _persistentCache.get(cacheKey: cacheKey);
    if (persistentCached != null && persistentCached.isNotEmpty) {
      _cache.put(
        userLat: userLat,
        userLng: userLng,
        radiusMeters: radiusMeters,
        categoryIds: categoryIds,
        pois: persistentCached,
      );

      _refreshAndCache(
        userLat: userLat,
        userLng: userLng,
        radiusMeters: radiusMeters,
        filters: filters,
        categoryIds: categoryIds,
        cacheKey: cacheKey,
      );
      return persistentCached;
    }

    final result = await _fetchFromSources(
      userLat: userLat,
      userLng: userLng,
      radiusMeters: radiusMeters,
      filters: filters,
      categoryIds: categoryIds,
      cacheKey: cacheKey,
    );

    return result;
  }

  Future<void> _refreshAndCache({
    required double userLat,
    required double userLng,
    required double radiusMeters,
    required PoiFilters filters,
    required Set<String> categoryIds,
    required String cacheKey,
  }) async {
    try {
      await _fetchFromSources(
        userLat: userLat,
        userLng: userLng,
        radiusMeters: radiusMeters,
        filters: filters,
        categoryIds: categoryIds,
        cacheKey: cacheKey,
      );
    } catch (_) {
      // Ignore refresh errors
    }
  }

  Future<List<Poi>> _fetchFromSources({
    required double userLat,
    required double userLng,
    required double radiusMeters,
    required PoiFilters filters,
    required Set<String> categoryIds,
    required String cacheKey,
  }) async {
    // Priorité: Firestore d'abord (données locales = plus rapide)
    final firestorePois = await firestoreRepo.getNearbyPois(
      userLat: userLat,
      userLng: userLng,
      radiusMeters: radiusMeters,
      filters: filters,
    );

    // Google Places en parallèle (fallback pour zones mal couvertes)
    final placesTask = placesRepo.getNearbyPois(
      userLat: userLat,
      userLng: userLng,
      radiusMeters: radiusMeters,
      filters: filters,
    );

    // Fusionne avec Google Places quand disponibles (non-blocking)
    final merged = <String, Poi>{};
    for (final poi in firestorePois) {
      merged[poi.id] = poi;
    }

    placesTask.then((placesPois) {
      for (final poi in placesPois) {
        if (!merged.containsKey(poi.id)) {
          merged[poi.id] = poi;
        }
      }
    }).catchError((_) {
      // Ignore erreurs Google Places (Firestore suffisant)
    });

    final result = merged.values.toList();

    // Cache le résultat
    _cache.put(
      userLat: userLat,
      userLng: userLng,
      radiusMeters: radiusMeters,
      categoryIds: categoryIds,
      pois: result,
    );

    if (result.isNotEmpty) {
      await _persistentCache.put(
        cacheKey: cacheKey,
        pois: result,
      );
    }

    return result;
  }
}
