import 'package:collection/collection.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/constants/poi_categories.dart';
import '../data/firestore_poi_repository.dart';
import '../data/mixed_poi_repository.dart';
import '../data/places_poi_repository.dart';
import '../data/poi_repository.dart';
import '../domain/poi.dart';
import '../domain/poi_category.dart';
import '../domain/poi_filters.dart';

class MapState {
  final Position? userPosition;
  final bool isLoading;
  final String? error;
  final List<Poi> nearbyPois;
  final PoiFilters filters;
  final double radiusMeters;
  final bool isSatellite;
  final bool buildingsEnabled;

  const MapState({
    required this.userPosition,
    required this.isLoading,
    required this.error,
    required this.nearbyPois,
    required this.filters,
    required this.radiusMeters,
    required this.isSatellite,
    required this.buildingsEnabled,
  });

  factory MapState.initial() => MapState(
        userPosition: null,
        isLoading: false,
        error: null,
        nearbyPois: const [],
        filters: PoiFilters.defaults(),
        radiusMeters: 10000, // 10 km par défaut
        isSatellite: false,
        buildingsEnabled: true,
      );

  MapState copyWith({
    Position? userPosition,
    bool? isLoading,
    String? error,
    List<Poi>? nearbyPois,
    PoiFilters? filters,
    double? radiusMeters,
    bool? isSatellite,
    bool? buildingsEnabled,
  }) {
    return MapState(
      userPosition: userPosition ?? this.userPosition,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      nearbyPois: nearbyPois ?? this.nearbyPois,
      filters: filters ?? this.filters,
      radiusMeters: radiusMeters ?? this.radiusMeters,
      isSatellite: isSatellite ?? this.isSatellite,
      buildingsEnabled: buildingsEnabled ?? this.buildingsEnabled,
    );
  }
}

final poiRepositoryProvider = Provider<PoiRepository>((ref) {
  // Clé API Google Places (fournie ou depuis env)
  const envKey = String.fromEnvironment('PLACES_API_KEY');
  const fallbackKey = 'AIzaSyD1ky3i7gYB9SKRgNuhYeMVE2l9COaZIUI';
  final placesKey = envKey.isNotEmpty ? envKey : fallbackKey;
  
  return MixedPoiRepository(
    firestoreRepo: FirestorePoiRepository(FirebaseFirestore.instance),
    placesRepo: PlacesPoiRepository(placesKey),
  );
});

final mapControllerProvider =
    StateNotifierProvider<MapController, MapState>((ref) {
  final repo = ref.watch(poiRepositoryProvider);
  return MapController(repo);
});

class MapController extends StateNotifier<MapState> {
  MapController(this._repo) : super(MapState.initial());

  final PoiRepository _repo;
  Future<void>? _refreshInFlight;
  DateTime? _lastRefreshAt;
  double? _lastRefreshLat;
  double? _lastRefreshLng;
  double? _lastRefreshRadius;
  Set<PoiCategory>? _lastRefreshCategories;
  bool? _lastRefreshOpenNow;
  static const Duration _refreshCacheTtl = Duration(seconds: 25);

  Future<void> init() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final pos = await _determinePosition();
      state = state.copyWith(userPosition: pos);

      await refreshNearby();
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> refreshNearby() async {
    if (_refreshInFlight != null) {
      return _refreshInFlight!;
    }

    final now = DateTime.now();
    final pos = state.userPosition;
    if (pos == null) {
      state = state.copyWith(error: 'Position non disponible');
      return;
    }

    if (_isRefreshCacheValid(now, pos)) {
      return;
    }

    final refreshFuture = () async {
      state = state.copyWith(isLoading: true, error: null);

      try {
        final pois = await _repo.getNearbyPois(
          userLat: pos.latitude,
          userLng: pos.longitude,
          radiusMeters: state.radiusMeters,
          filters: state.filters,
        );

        state = state.copyWith(nearbyPois: pois, isLoading: false);
        _rememberRefresh(now, pos);
      } catch (e) {
        state = state.copyWith(error: e.toString(), isLoading: false);
      } finally {
        _refreshInFlight = null;
      }
    }();

    _refreshInFlight = refreshFuture;
    return refreshFuture;
  }

  Future<void> setRadiusMeters(double value) async {
    state = state.copyWith(radiusMeters: value);
    await refreshNearby();
  }

  Future<void> applyCategoryPreferences(List<String> preferences) async {
    final categories = _categoriesFromPreferences(preferences);
    const setEq = SetEquality<PoiCategory>();
    if (setEq.equals(categories, state.filters.categories)) return;

    state = state.copyWith(
      filters: state.filters.copyWith(categories: categories),
    );
    await refreshNearby();
  }

  Future<void> setOpenNow(bool value) async {
    state = state.copyWith(
      filters: state.filters.copyWith(openNow: value),
    );
    await refreshNearby();
  }

  void toggleMapType() {
    final nextIsSatellite = !state.isSatellite;
    state = state.copyWith(
      isSatellite: nextIsSatellite,
      buildingsEnabled: nextIsSatellite ? state.buildingsEnabled : false,
    );
  }

  void toggleBuildings() {
    state = state.copyWith(buildingsEnabled: !state.buildingsEnabled);
  }

  Future<Position> _determinePosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Service de localisation désactivé.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Permission localisation refusée.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception('Permission localisation refusée définitivement.');
    }

    final lastKnown = await Geolocator.getLastKnownPosition();
    if (lastKnown != null) {
      return lastKnown;
    }

    return Geolocator
        .getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
          ),
        )
        .timeout(
          const Duration(seconds: 8),
          onTimeout: () => throw Exception('Timeout de localisation'),
        );
  }

  bool _isRefreshCacheValid(DateTime now, Position pos) {
    final lastAt = _lastRefreshAt;
    if (lastAt == null) return false;
    if (now.difference(lastAt) > _refreshCacheTtl) return false;

    if (_lastRefreshRadius != state.radiusMeters ||
        _lastRefreshOpenNow != state.filters.openNow) {
      return false;
    }

    final categories = _lastRefreshCategories;
    if (categories == null || !const SetEquality<PoiCategory>().equals(categories, state.filters.categories)) {
      return false;
    }

    final lat = _lastRefreshLat;
    final lng = _lastRefreshLng;
    if (lat == null || lng == null) return false;

    final movedMeters = Geolocator.distanceBetween(
      lat,
      lng,
      pos.latitude,
      pos.longitude,
    );

    return movedMeters < 80;
  }

  void _rememberRefresh(DateTime now, Position pos) {
    _lastRefreshAt = now;
    _lastRefreshLat = pos.latitude;
    _lastRefreshLng = pos.longitude;
    _lastRefreshRadius = state.radiusMeters;
    _lastRefreshCategories = Set<PoiCategory>.from(state.filters.categories);
    _lastRefreshOpenNow = state.filters.openNow;
  }

  Set<PoiCategory> _categoriesFromPreferences(List<String> preferences) {
    // Si l'utilisateur a des préférences, respecter UNIQUEMENT celles-ci
    if (preferences.isEmpty) {
      // Aucune préférence = afficher toutes les catégories
      return PoiCategory.values.toSet();
    }

    final preferenceSet = preferences.map(_normalize).toSet();
    final categories = <PoiCategory>{};

    for (final group in poiCategoryGroups) {
      // Vérifier si au moins un élément du groupe est dans les préférences
      final hasTitleMatch = preferenceSet.contains(_normalize(group.title));
      final hasItemMatch = group.items
          .map(_normalize)
          .any(preferenceSet.contains);
      final hasMatch = hasTitleMatch || hasItemMatch;
      if (!hasMatch) continue;

      // Mapper le groupe à sa catégorie
      switch (group.title) {
        case 'Patrimoine et Histoire':
          categories.add(PoiCategory.histoire);
          break;
        case 'Nature':
          categories.add(PoiCategory.nature);
          break;
        case 'Culture':
          categories.add(PoiCategory.culture);
          break;
        case 'Experience gustative':
          categories.add(PoiCategory.experienceGustative);
          break;
        case 'Activites plein air':
          categories.add(PoiCategory.activites);
          break;
      }
    }

    // Fallback sécurité: ne jamais filtrer à vide
    if (categories.isEmpty) {
      return PoiCategory.values.toSet();
    }

    return categories;
  }

  String _normalize(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('ë', 'e')
        .replaceAll('à', 'a')
        .replaceAll('â', 'a')
        .replaceAll('ä', 'a')
        .replaceAll('î', 'i')
        .replaceAll('ï', 'i')
        .replaceAll('ô', 'o')
        .replaceAll('ö', 'o')
        .replaceAll('ù', 'u')
        .replaceAll('û', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ç', 'c');
  }
}
