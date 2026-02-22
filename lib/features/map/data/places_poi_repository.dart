import 'package:flutter_google_maps_webservices/places.dart';
import '../../../core/utils/geo_utils.dart';
import '../domain/poi.dart';
import '../domain/poi_category.dart';
import '../domain/poi_filters.dart';
import 'poi_repository.dart';

/// Repository pour récupérer les points d'intérêt depuis Google Places API
/// 
/// Le système fonctionne en deux étapes:
/// 1. Récupère tous les lieux à proximité via Google Places
/// 2. Les mappe aux catégories AllSpots et filtre selon les préférences utilisateur
/// 
/// Les données Google Places enrichissent les spots créés par les utilisateurs,
/// offrant une couverture complète des lieux autour de l'utilisateur.
class PlacesPoiRepository implements PoiRepository {
  PlacesPoiRepository(this._apiKey)
      : _placesClient = GoogleMapsPlaces(apiKey: _apiKey);

  final String _apiKey;
  final GoogleMapsPlaces _placesClient;

  @override
  Future<List<Poi>> getNearbyPois({
    required double userLat,
    required double userLng,
    required double radiusMeters,
    required PoiFilters filters,
  }) async {
    if (_apiKey.isEmpty) {
      return const [];
    }

    try {
      final results = <Poi>[];
      final seenIds = <String>{};
      final typesToSearch = _typesForCategories(filters.categories);

      final requests = typesToSearch
          .map(
            (type) async {
              try {
                return await _placesClient
                    .searchNearbyWithRadius(
                      Location(lat: userLat, lng: userLng),
                      radiusMeters.toInt().clamp(1, 50000),
                      type: type,
                    )
                    .timeout(const Duration(seconds: 4));
              } catch (_) {
                return null;
              }
            },
          )
          .toList();

      final responses = await Future.wait(requests);

      for (final response in responses) {
        if (response == null || response.isDenied || response.errorMessage != null) {
          continue;
        }

        for (final place in response.results) {
          final geometry = place.geometry?.location;
          if (geometry == null) continue;

          if (filters.openNow) {
            final isOpen = place.openingHours?.openNow;
            if (isOpen != true) continue;
          }

          final category = _mapPlaceTypes(place.types);
          if (category == null || !filters.categories.contains(category)) {
            continue;
          }

          final distance = GeoUtils.distanceMeters(
            lat1: userLat,
            lon1: userLng,
            lat2: geometry.lat,
            lon2: geometry.lng,
          );
          if (distance > radiusMeters) continue;

          if (!seenIds.add(place.placeId)) continue;

          final photoUrls = <String>[];
          if (place.photos.isNotEmpty) {
            for (final photo in place.photos) {
              final photoUrl = 'https://maps.googleapis.com/maps/api/place/photo'
                  '?maxwidth=400'
                  '&photoreference=${photo.photoReference}'
                  '&key=$_apiKey';
              photoUrls.add(photoUrl);
            }
          }

          results.add(
            Poi(
              id: place.placeId,
              name: place.name,
              category: category,
              subCategory: place.types.isNotEmpty ? place.types.first : null,
              lat: geometry.lat,
              lng: geometry.lng,
              shortDescription: place.vicinity ?? '',
              imageUrls: photoUrls,
              websiteUrl: null,
              isFree: null,
              pmrAccessible: null,
              kidsFriendly: null,
              googleRating: place.rating?.toDouble(),
              googleRatingCount: null,
              source: 'places',
              updatedAt: DateTime.now(),
            ),
          );
        }
      }

      results.sort((a, b) {
        final da = GeoUtils.distanceMeters(
          lat1: userLat,
          lon1: userLng,
          lat2: a.lat,
          lon2: a.lng,
        );
        final db = GeoUtils.distanceMeters(
          lat1: userLat,
          lon1: userLng,
          lat2: b.lat,
          lon2: b.lng,
        );
        return da.compareTo(db);
      });

      return results;
    } catch (e) {
      return const [];
    }
  }

  Set<String> _typesForCategories(Set<PoiCategory> categories) {
    final types = <String>{};

    if (categories.contains(PoiCategory.culture)) {
      types.addAll({'museum', 'art_gallery', 'tourist_attraction', 'library'});
    }
    if (categories.contains(PoiCategory.nature)) {
      types.addAll({'park', 'natural_feature', 'scenic_viewpoint', 'zoo'});
    }
    if (categories.contains(PoiCategory.histoire)) {
      types.addAll({'church', 'place_of_worship', 'hindu_temple', 'mosque', 'synagogue', 'castle'});
    }
    if (categories.contains(PoiCategory.experienceGustative)) {
      types.addAll({'restaurant', 'cafe', 'market'});
    }
    if (categories.contains(PoiCategory.activites)) {
      types.addAll({'hiking_area', 'amusement_park', 'sports_complex'});
    }

    if (types.isEmpty) {
      types.addAll({
        'museum',
        'art_gallery',
        'tourist_attraction',
        'library',
        'park',
        'natural_feature',
        'scenic_viewpoint',
        'zoo',
        'church',
        'place_of_worship',
        'hindu_temple',
        'mosque',
        'synagogue',
        'castle',
        'restaurant',
        'cafe',
        'market',
        'hiking_area',
        'amusement_park',
        'sports_complex',
      });
    }

    return types;
  }

  /// Mappe les types Google Places aux catégories AllSpots
  /// 
  /// Filtrée pour afficher UNIQUEMENT:
  /// - CULTURE: musées, sites touristiques
  /// - HISTOIRE: monuments, églises, châteaux
  /// - NATURE: parcs, sites naturels, points de vue
  /// - EXPERIENCE GUSTATIVE: restaurants, marchés
  /// - ACTIVITES: randonnées, activités de plein air
  PoiCategory? _mapPlaceTypes(List<String> types) {
    // CULTURE: Musées et sites touristiques
    if (types.contains('museum') ||
        types.contains('art_gallery') ||
        types.contains('tourist_attraction')) {
      return PoiCategory.culture;
    }

    // NATURE: Parcs, sites naturels, points de vue
    if (types.contains('park') ||
        types.contains('natural_feature') ||
        types.contains('scenic_viewpoint') ||
        types.contains('zoo')) {
      return PoiCategory.nature;
    }

    // HISTOIRE: Monuments, églises, châteaux, ruines
    if (types.contains('church') ||
        types.contains('place_of_worship') ||
        types.contains('hindu_temple') ||
        types.contains('mosque') ||
        types.contains('synagogue') ||
        types.contains('castle')) {
      return PoiCategory.histoire;
    }

    // EXPERIENCE GUSTATIVE: Restaurants, marchés
    if (types.contains('restaurant') ||
        types.contains('cafe') ||
        types.contains('market')) {
      return PoiCategory.experienceGustative;
    }

    // ACTIVITES: Randonnées, activités de plein air
    if (types.contains('hiking_area') ||
        types.contains('amusement_park') ||
        types.contains('sports_complex')) {
      return PoiCategory.activites;
    }

    // Tous les autres types sont rejetés
    return null;
  }
}
