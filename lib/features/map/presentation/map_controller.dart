import 'package:collection/collection.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/config/app_config.dart';
import '../../../core/constants/poi_categories.dart';
import '../data/empty_poi_repository.dart';
import '../data/firestore_poi_repository.dart';
import '../data/mixed_poi_repository.dart';
import '../data/osm_api_poi_repository.dart';
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
  const fallbackKey = 'AIzaSyBbHU0nLg_T6v9tDsdh9_0cc3ksc1TC-dU';
  final placesKey = envKey.isNotEmpty ? envKey : fallbackKey;
  final placesRepo = AppConfig.enableGooglePlaces
      ? PlacesPoiRepository(placesKey)
      : EmptyPoiRepository();
  final osmRepo = AppConfig.enableOsmApi
      ? OsmApiPoiRepository(AppConfig.osmApiBaseUrl)
      : EmptyPoiRepository();

  return MixedPoiRepository(
    firestoreRepo: FirestorePoiRepository(FirebaseFirestore.instance),
    placesRepo: placesRepo,
    extraRepos: [osmRepo],
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
    final pos = state.userPosition;
    if (pos == null) {
      state = state.copyWith(error: 'Position non disponible');
      return;
    }

    state = state.copyWith(isLoading: true, error: null);
    
    try {
      final pois = await _repo.getNearbyPois(
        userLat: pos.latitude,
        userLng: pos.longitude,
        radiusMeters: state.radiusMeters,
        filters: state.filters,
      );

      state = state.copyWith(nearbyPois: pois, isLoading: false);
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
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

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );
  }

  Set<PoiCategory> _categoriesFromPreferences(List<String> preferences) {
    // Si l'utilisateur a des préférences, respecter UNIQUEMENT celles-ci
    if (preferences.isEmpty) {
      // Aucune préférence = afficher toutes les catégories
      return PoiCategory.values.toSet();
    }

    // L'utilisateur a des préférences: les utiliser strictement
    final preferenceSet = preferences.toSet();
    final categories = <PoiCategory>{};

    for (final group in poiCategoryGroups) {
      // Vérifier si au moins un élément du groupe est dans les préférences
      final hasMatch = group.items.any(preferenceSet.contains);
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

    // Retourner les catégories trouvées (même si vide)
    return categories;
  }
}
