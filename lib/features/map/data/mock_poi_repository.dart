import 'package:uuid/uuid.dart';
import '../../../core/utils/geo_utils.dart';
import '../domain/poi.dart';
import '../domain/poi_category.dart';
import '../domain/poi_filters.dart';
import 'poi_repository.dart';

class MockPoiRepository implements PoiRepository {
  final _uuid = const Uuid();

  // Quelques POI exemple autour de Paris (pour test)
  late final List<Poi> _all = [
    Poi(
      id: _uuid.v4(),
      name: 'Tour Eiffel',
      category: PoiCategory.histoire,
      lat: 48.858370,
      lng: 2.294481,
      shortDescription: 'Monument emblématique de Paris.',
      imageUrls: const [],
      websiteUrl: 'https://www.toureiffel.paris/',
      isFree: false,
      pmrAccessible: true,
      kidsFriendly: true,
      source: 'mock',
      updatedAt: DateTime.now(),
    ),
    Poi(
      id: _uuid.v4(),
      name: 'Musée du Louvre',
      category: PoiCategory.culture,
      lat: 48.860611,
      lng: 2.337644,
      shortDescription: 'Musée incontournable, collections d’art majeures.',
      imageUrls: const [],
      websiteUrl: 'https://www.louvre.fr/',
      isFree: false,
      pmrAccessible: true,
      kidsFriendly: true,
      source: 'mock',
      updatedAt: DateTime.now(),
    ),
    Poi(
      id: _uuid.v4(),
      name: 'Parc des Buttes-Chaumont',
      category: PoiCategory.nature,
      lat: 48.880950,
      lng: 2.381750,
      shortDescription: 'Grand parc urbain avec belvédère.',
      imageUrls: const [],
      isFree: true,
      pmrAccessible: true,
      kidsFriendly: true,
      source: 'mock',
      updatedAt: DateTime.now(),
    ),
  ];

  @override
  Future<List<Poi>> getNearbyPois({
    required double userLat,
    required double userLng,
    required double radiusMeters,
    required PoiFilters filters,
  }) async {
    // Simule une latence réseau
    await Future<void>.delayed(const Duration(milliseconds: 250));

    final filtered = _all.where((p) {
      if (!filters.categories.contains(p.category)) return false;
      if (filters.onlyFree && (p.isFree != true)) return false;
      if (filters.pmrOnly && (p.pmrAccessible != true)) return false;
      if (filters.kidsOnly && (p.kidsFriendly != true)) return false;
      if (filters.maxVisitDurationMin != null &&
          p.visitDurationMin != null &&
          p.visitDurationMin! > filters.maxVisitDurationMin!) {
        return false;
      }

      final d = GeoUtils.distanceMeters(
        lat1: userLat,
        lon1: userLng,
        lat2: p.lat,
        lon2: p.lng,
      );
      return d <= radiusMeters;
    }).toList();

    return filtered;
  }
}
