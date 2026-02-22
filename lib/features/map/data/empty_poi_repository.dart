import '../domain/poi.dart';
import '../domain/poi_filters.dart';
import 'poi_repository.dart';

class EmptyPoiRepository implements PoiRepository {
  @override
  Future<List<Poi>> getNearbyPois({
    required double userLat,
    required double userLng,
    required double radiusMeters,
    required PoiFilters filters,
  }) async {
    return const [];
  }
}
