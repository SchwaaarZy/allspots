import '../domain/poi.dart';
import '../domain/poi_filters.dart';

abstract class PoiRepository {
  Future<List<Poi>> getNearbyPois({
    required double userLat,
    required double userLng,
    required double radiusMeters,
    required PoiFilters filters,
  });
}
