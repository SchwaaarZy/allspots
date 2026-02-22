import 'package:flutter_google_maps_webservices/places.dart';
import 'package:flutter/foundation.dart';
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
  PlacesPoiRepository(this._apiKey);

  final String _apiKey;

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
      final places = GoogleMapsPlaces(apiKey: _apiKey);
      final results = <Poi>[];
      
      // Types de lieux à rechercher pour chaque catégorie
      final typesToSearch = [
        // Culture: Musées, galeries, sites touristiques
        'museum', 'art_gallery', 'tourist_attraction', 'library', 'zoo',
        // Nature: Parcs, points de vue, sites naturels
        'park', 'natural_feature', 'scenic_viewpoint', 'campground',
        // Histoire: Églises, châteaux, monuments historiques
        'church', 'place_of_worship', 'hindu_temple', 'mosque', 'synagogue', 'castle',
        // Alimentation: Restaurants, cafés, marchés, magasins de sport (Decathlon)
        'restaurant', 'cafe', 'market', 'sporting_goods_store',
        // Activités: Sports, loisirs, aventure
        'amusement_park', 'gym', 'sports_complex', 'stadium', 'hiking_area',
      ];
      
      // Rechercher par type pour avoir plus de résultats
      for (final type in typesToSearch) {
        try {
          final response = await places.searchNearbyWithRadius(
            Location(lat: userLat, lng: userLng),
            radiusMeters.toInt().clamp(1, 50000),
            type: type,
          );

          if (response.isDenied || response.errorMessage != null) {
            debugPrint('[PlacesPoiRepository] denied status=${response.status} error=${response.errorMessage}');
            continue;
          }

          for (final place in response.results) {
            final geometry = place.geometry?.location;
            if (geometry == null) continue;

            // Vérifier si le lieu ouvre maintenant (si désiré)
            if (filters.openNow) {
              final isOpen = place.openingHours?.openNow;
              if (isOpen != true) continue;
            }

            final category = _mapPlaceTypes(place.types);
            if (category == null) continue; // Rejeter les types non-whitelistés
            if (!filters.categories.contains(category)) continue;

            final distance = GeoUtils.distanceMeters(
              lat1: userLat,
              lon1: userLng,
              lat2: geometry.lat,
              lon2: geometry.lng,
            );
            if (distance > radiusMeters) continue;

            // Éviter les doublons
            if (results.any((p) => p.id == place.placeId)) continue;

            // Extraire les URLs des photos de Google Places
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
        } catch (e) {
          // Continuer avec le type suivant en cas d'erreur
          continue;
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

      debugPrint('[PlacesPoiRepository] matched=${results.length}');
      return results;
    } catch (e) {
      debugPrint('[PlacesPoiRepository] error=$e');
      return const [];
    }
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
