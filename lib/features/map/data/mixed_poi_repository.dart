import 'dart:async';

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
      onlyFree: filters.onlyFree,
      pmrOnly: filters.pmrOnly,
      kidsOnly: filters.kidsOnly,
      openNow: filters.openNow,
      maxVisitDurationMin: filters.maxVisitDurationMin ?? -1,
    );

    if (cached != null) {
      return cached;
    }

    final cacheKey = PoiCache.buildKey(
      userLat: userLat,
      userLng: userLng,
      radiusMeters: radiusMeters,
      categoryIds: categoryIds,
      onlyFree: filters.onlyFree,
      pmrOnly: filters.pmrOnly,
      kidsOnly: filters.kidsOnly,
      openNow: filters.openNow,
      maxVisitDurationMin: filters.maxVisitDurationMin ?? -1,
    );

    final persistentCached = await _persistentCache.get(cacheKey: cacheKey);
    if (persistentCached != null && persistentCached.isNotEmpty) {
      _cache.put(
        userLat: userLat,
        userLng: userLng,
        radiusMeters: radiusMeters,
        categoryIds: categoryIds,
        pois: persistentCached,
        onlyFree: filters.onlyFree,
        pmrOnly: filters.pmrOnly,
        kidsOnly: filters.kidsOnly,
        openNow: filters.openNow,
        maxVisitDurationMin: filters.maxVisitDurationMin ?? -1,
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

    if (firestorePois.isNotEmpty) {
      _cache.put(
        userLat: userLat,
        userLng: userLng,
        radiusMeters: radiusMeters,
        categoryIds: categoryIds,
        pois: firestorePois,
        onlyFree: filters.onlyFree,
        pmrOnly: filters.pmrOnly,
        kidsOnly: filters.kidsOnly,
        openNow: filters.openNow,
        maxVisitDurationMin: filters.maxVisitDurationMin ?? -1,
      );
      await _persistentCache.put(
        cacheKey: cacheKey,
        pois: firestorePois,
      );

      unawaited(
        _enrichCacheWithSecondarySources(
          firestorePois: firestorePois,
          userLat: userLat,
          userLng: userLng,
          radiusMeters: radiusMeters,
          filters: filters,
          categoryIds: categoryIds,
          cacheKey: cacheKey,
        ),
      );
      return firestorePois;
    }

    final secondaryPois = await _fetchSecondaryPois(
      userLat: userLat,
      userLng: userLng,
      radiusMeters: radiusMeters,
      filters: filters,
    );

    final result = secondaryPois;

    // Cache le résultat
    _cache.put(
      userLat: userLat,
      userLng: userLng,
      radiusMeters: radiusMeters,
      categoryIds: categoryIds,
      pois: result,
      onlyFree: filters.onlyFree,
      pmrOnly: filters.pmrOnly,
      kidsOnly: filters.kidsOnly,
      openNow: filters.openNow,
      maxVisitDurationMin: filters.maxVisitDurationMin ?? -1,
    );

    if (result.isNotEmpty) {
      await _persistentCache.put(
        cacheKey: cacheKey,
        pois: result,
      );
    }

    return result;
  }

  Future<void> _enrichCacheWithSecondarySources({
    required List<Poi> firestorePois,
    required double userLat,
    required double userLng,
    required double radiusMeters,
    required PoiFilters filters,
    required Set<String> categoryIds,
    required String cacheKey,
  }) async {
    final secondaryPois = await _fetchSecondaryPois(
      userLat: userLat,
      userLng: userLng,
      radiusMeters: radiusMeters,
      filters: filters,
    );

    if (secondaryPois.isEmpty) return;

    final merged = <String, Poi>{
      for (final poi in firestorePois) poi.id: poi,
    };
    for (final poi in secondaryPois) {
      merged.putIfAbsent(poi.id, () => poi);
    }

    final enriched = merged.values.toList();

    _cache.put(
      userLat: userLat,
      userLng: userLng,
      radiusMeters: radiusMeters,
      categoryIds: categoryIds,
      pois: enriched,
      onlyFree: filters.onlyFree,
      pmrOnly: filters.pmrOnly,
      kidsOnly: filters.kidsOnly,
      openNow: filters.openNow,
      maxVisitDurationMin: filters.maxVisitDurationMin ?? -1,
    );

    await _persistentCache.put(
      cacheKey: cacheKey,
      pois: enriched,
    );
  }

  Future<List<Poi>> _fetchSecondaryPois({
    required double userLat,
    required double userLng,
    required double radiusMeters,
    required PoiFilters filters,
  }) async {
    final repos = <PoiRepository>[placesRepo, ...extraRepos];
    if (repos.isEmpty) return const [];

    final tasks = repos
        .map(
          (repo) => repo
              .getNearbyPois(
                userLat: userLat,
                userLng: userLng,
                radiusMeters: radiusMeters,
                filters: filters,
              )
              .timeout(const Duration(milliseconds: 1800), onTimeout: () => const <Poi>[])
              .catchError((_) => const <Poi>[]),
        )
        .toList();

    final lists = await Future.wait(tasks);
    final merged = <String, Poi>{};
    for (final list in lists) {
      for (final poi in list) {
        merged.putIfAbsent(poi.id, () => poi);
      }
    }
    return merged.values.toList();
  }
}
