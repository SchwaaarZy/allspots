import 'dart:async';
import 'package:collection/collection.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/config/app_config.dart';
import '../../../core/constants/poi_categories.dart';
import '../../../core/utils/geo_utils.dart';
import '../data/empty_poi_repository.dart';
import '../data/firestore_poi_repository.dart';
import '../data/mixed_poi_repository.dart';
import '../data/osm_api_poi_repository.dart';
import '../data/places_poi_repository.dart';
import '../data/poi_repository.dart';
import '../domain/poi.dart';
import '../domain/poi_category.dart';
import '../domain/poi_filters.dart';
import '../domain/map_style.dart';

class MapState {
  final Position? userPosition;
  final bool isLoading;
  final String? error;
  final List<Poi> nearbyPois;
  // OPTIMISÉ: Afficher QUE les POIs visibles sur l'écran
  // Évite de créer 500+ widgets d'un coup
  final List<Poi> displayedPois;
  final PoiFilters filters;
  final double radiusMeters;
  final bool isSatellite;
  final bool buildingsEnabled;
  final MapStyle mapStyle;

  const MapState({
    required this.userPosition,
    required this.isLoading,
    required this.error,
    required this.nearbyPois,
    required this.displayedPois,
    required this.filters,
    required this.radiusMeters,
    required this.isSatellite,
    required this.buildingsEnabled,
    required this.mapStyle,
  });

  factory MapState.initial() => MapState(
        userPosition: null,
        isLoading: false,
        error: null,
        nearbyPois: const [],
        displayedPois: const [],
        filters: PoiFilters.defaults(),
        radiusMeters: 5000, // 5 km par défaut
        isSatellite: false,
        buildingsEnabled: true,
        mapStyle: MapStyle.openStreetMapFrance,
      );

  MapState copyWith({
    Position? userPosition,
    bool? isLoading,
    String? error,
    List<Poi>? nearbyPois,
    List<Poi>? displayedPois,
    PoiFilters? filters,
    double? radiusMeters,
    bool? isSatellite,
    bool? buildingsEnabled,
    MapStyle? mapStyle,
  }) {
    return MapState(
      userPosition: userPosition ?? this.userPosition,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      nearbyPois: nearbyPois ?? this.nearbyPois,
      displayedPois: displayedPois ?? this.displayedPois,
      filters: filters ?? this.filters,
      radiusMeters: radiusMeters ?? this.radiusMeters,
      isSatellite: isSatellite ?? this.isSatellite,
      buildingsEnabled: buildingsEnabled ?? this.buildingsEnabled,
      mapStyle: mapStyle ?? this.mapStyle,
    );
  }
}

final poiRepositoryProvider = Provider<PoiRepository>((ref) {
  // Clé API Google Places (fournie ou depuis env)
  const envKey = String.fromEnvironment('PLACES_API_KEY');
  const fallbackKey = 'AIzaSyBbHU0nLg_T6v9tDsdh9_0cc3ksc1TC-dU';
  final placesKey = envKey.isNotEmpty ? envKey : fallbackKey;

  // OPTIMISÉ: Google Places désactivé pour réduire les requêtes API
  // Utilise Firestore seul (données locales, plus rapide)
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
  static const List<
          ({double minLat, double maxLat, double minLng, double maxLng})>
      _supportedCoverageZones = [
    (
      minLat: 41.0,
      maxLat: 51.7,
      minLng: -5.9,
      maxLng: 10.0
    ), // France métropolitaine
    (minLat: 15.7, maxLat: 16.6, minLng: -61.95, maxLng: -61.0), // Guadeloupe
    (minLat: 14.3, maxLat: 14.95, minLng: -61.3, maxLng: -60.7), // Martinique
    (minLat: 1.8, maxLat: 6.0, minLng: -54.8, maxLng: -51.5), // Guyane
    (minLat: -21.45, maxLat: -20.85, minLng: 55.1, maxLng: 55.9), // Réunion
    (minLat: -13.2, maxLat: -12.55, minLng: 45.0, maxLng: 45.4), // Mayotte
    (
      minLat: 46.65,
      maxLat: 47.2,
      minLng: -56.6,
      maxLng: -56.0
    ), // Saint-Pierre-et-Miquelon
    (
      minLat: 17.82,
      maxLat: 18.22,
      minLng: -63.3,
      maxLng: -62.7
    ), // Saint-Barthélemy
    (
      minLat: 18.0,
      maxLat: 18.16,
      minLng: -63.2,
      maxLng: -62.95
    ), // Saint-Martin
    (
      minLat: -14.5,
      maxLat: -13.1,
      minLng: -177.4,
      maxLng: -176.0
    ), // Wallis-et-Futuna
    (
      minLat: -28.5,
      maxLat: -7.5,
      minLng: -154.0,
      maxLng: -134.0
    ), // Polynésie française
    (
      minLat: -23.0,
      maxLat: -19.0,
      minLng: 163.0,
      maxLng: 168.5
    ), // Nouvelle-Calédonie
  ];

  // OPTIMISÉ: Évite les refetch trop fréquents (min 2 secondes entre deux)
  DateTime? _lastRefreshTime;
  static const Duration _minRefreshInterval = Duration(seconds: 2);

  // Accumule TOUS les POIs jamais fetches (ne remplace pas, fusionne)
  final Map<String, Poi> _allPoisBySameSession = {};

  DateTime? _lastPrefetchTime;
  static const Duration _minPrefetchInterval = Duration(seconds: 30);
  static const double _prefetchRadiusMeters = 20000;

  Future<void> init() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final pos = await _determinePosition();
      state = state.copyWith(userPosition: pos);

      if (!_isInSupportedCoverage(pos.latitude, pos.longitude)) {
        state = state.copyWith(
          nearbyPois: const [],
          displayedPois: const [],
          isLoading: false,
          error: 'Aucun spot disponible dans ce pays pour le moment.',
        );
        return;
      }

      await refreshNearby();
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(
        nearbyPois: const [],
        displayedPois: const [],
        isLoading: false,
        error:
            'Localisation indisponible. Activez la localisation pour charger les spots.',
      );
    }
  }

  Future<void> refreshNearby({
    double? userLatOverride,
    double? userLngOverride,
  }) async {
    // Les spots s'affichent automatiquement par proximité (5km)
    // Pas de vérification de sélection nécessaire

    // OPTIMISÉ: Vérifie que suffisamment de temps s'est écoulé
    final now = DateTime.now();
    if (_lastRefreshTime != null &&
        now.difference(_lastRefreshTime!) < _minRefreshInterval) {
      // Si on ne peut pas rafraîchir à cause du throttle mais qu'une erreur se montre,
      // on s'assure que c'est bien une erreur valide (pas juste "pas de destination")
      // qui persiste correctement
      return; // Trop récent, ignore
    }
    _lastRefreshTime = now;

    final pos = state.userPosition;
    final userLat = userLatOverride ?? pos?.latitude;
    final userLng = userLngOverride ?? pos?.longitude;

    if (userLat == null || userLng == null) {
      state = state.copyWith(
        nearbyPois: const [],
        displayedPois: const [],
        isLoading: false,
        error:
            'Localisation indisponible. Activez la localisation pour charger les spots.',
      );
      return;
    }

    if (!_isInSupportedCoverage(userLat, userLng)) {
      state = state.copyWith(
        nearbyPois: const [],
        displayedPois: const [],
        isLoading: false,
        error: 'Aucun spot disponible dans ce pays pour le moment.',
      );
      return;
    }

    state = state.copyWith(isLoading: true, error: null);

    try {
      final pois = await _repo.getNearbyPois(
        userLat: userLat,
        userLng: userLng,
        radiusMeters: state.radiusMeters,
        filters: state.filters,
      );

      // Ajoute les nouveaux POIs à l'accumulator (fusionne au lieu de remplacer)
      for (final poi in pois) {
        _allPoisBySameSession[poi.id] = poi;
      }

      // Récupère TOUS les POIs accumulés ET les trie par distance
      final allPois = _allPoisBySameSession.values.toList();
      allPois.sort((a, b) {
        final distA = GeoUtils.distanceMeters(
          lat1: userLat,
          lon1: userLng,
          lat2: a.lat,
          lon2: a.lng,
        );
        final distB = GeoUtils.distanceMeters(
          lat1: userLat,
          lon1: userLng,
          lat2: b.lat,
          lon2: b.lng,
        );
        return distA.compareTo(distB);
      });

      // Filtre pour n'afficher que les POIs dans le rayon actuel
      final displayedPois = allPois.where((poi) {
        final dist = GeoUtils.distanceMeters(
          lat1: userLat,
          lon1: userLng,
          lat2: poi.lat,
          lon2: poi.lng,
        );
        return dist <= state.radiusMeters;
      }).toList();

      state = state.copyWith(
        nearbyPois: allPois,
        displayedPois: displayedPois,
        isLoading: false,
      );

      _prefetchAroundMe(userLat: userLat, userLng: userLng);
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
  }

  bool _isInSupportedCoverage(double lat, double lng) {
    for (final zone in _supportedCoverageZones) {
      final matchesLat = lat >= zone.minLat && lat <= zone.maxLat;
      final matchesLng = lng >= zone.minLng && lng <= zone.maxLng;
      if (matchesLat && matchesLng) {
        return true;
      }
    }
    return false;
  }

  void _prefetchAroundMe({
    required double userLat,
    required double userLng,
  }) {
    final now = DateTime.now();
    if (_lastPrefetchTime != null &&
        now.difference(_lastPrefetchTime!) < _minPrefetchInterval) {
      return;
    }
    _lastPrefetchTime = now;

    if (state.radiusMeters >= _prefetchRadiusMeters) return;

    unawaited(
      _repo.getNearbyPois(
        userLat: userLat,
        userLng: userLng,
        radiusMeters: _prefetchRadiusMeters,
        filters: state.filters,
      ),
    );
  }

  Future<void> setRadiusMeters(double value) async {
    // Rafraîchit TOUJOURS quand le rayon change (pas de seuil)
    state = state.copyWith(radiusMeters: value);
    await refreshNearby();
  }

  Future<void> updateRadius(double radiusMeters) async {
    await setRadiusMeters(radiusMeters);
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

  void setMapStyle(MapStyle style) {
    state = state.copyWith(mapStyle: style);
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
    final preferenceSet = preferences.map(_normalizeLabel).toSet();
    final categories = <PoiCategory>{};

    for (final group in poiCategoryGroups) {
      // Vérifier si au moins un élément du groupe est dans les préférences
      final hasMatch =
          group.items.map(_normalizeLabel).any(preferenceSet.contains);
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

    // Si aucun match (anciens libellés / accents), ne pas bloquer la carte
    if (categories.isEmpty) {
      return PoiCategory.values.toSet();
    }

    return categories;
  }

  String _normalizeLabel(String input) {
    return input
        .toLowerCase()
        .trim()
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('à', 'a')
        .replaceAll('â', 'a')
        .replaceAll('ù', 'u')
        .replaceAll('û', 'u')
        .replaceAll('ô', 'o')
        .replaceAll('î', 'i')
        .replaceAll('ï', 'i')
        .replaceAll("'", '')
        .replaceAll('-', ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
  }
}
