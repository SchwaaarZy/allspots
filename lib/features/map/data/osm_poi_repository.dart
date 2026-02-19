import '../domain/poi.dart';
import '../domain/poi_category.dart';
import '../domain/poi_filters.dart';

/// Repository pour récupérer les POIs d'OpenStreetMap via l'API Overpass
/// 
/// Source: Gratuit, données stockables, riche pour le naturel
/// 
/// Catégories supportées:
/// - NATURE: Cascades, gorges, belvédères, cols, sites naturels
/// - HISTOIRE: Ruines
/// - ACTIVITES: Randonnées
class OsmPoiRepository {
  static const String overpassUrl = 'https://overpass-api.de/api/interpreter';

  Future<List<Poi>> fetchNearby({
    required double userLat,
    required double userLng,
    required double radiusMeters,
    required PoiFilters filters,
  }) async {
    final results = <Poi>[];

    try {
      // Construction de la query Overpass pour les catégories supportées
      // ignore: unused_local_variable
      final queries = _buildOverpassQueries(filters);
      
      // Implémenter l'appel à Overpass API pour chaque query
      // for (final (queryStr, category) in queries) {
      //   final poiList = await _fetchFromOverpass(queryStr, userLat, userLng, radiusMeters);
      //   results.addAll(poiList);
      // }

      return results;
    } catch (e) {
      return const [];
    }
  }

  /// Construit les queries Overpass pour les catégories demandées
  List<(String, PoiCategory)> _buildOverpassQueries(PoiFilters filters) {
    final queries = <(String, PoiCategory)>[];

    if (filters.categories.contains(PoiCategory.nature)) {
      // Cascades
      queries.add(('node[waterway=waterfall](around:RADIUS,LAT,LNG);', PoiCategory.nature));
      // Belvédères
      queries.add(('node[tourism=viewpoint](around:RADIUS,LAT,LNG);', PoiCategory.nature));
      // Cols
      queries.add(('node[mountain_pass=yes](around:RADIUS,LAT,LNG);', PoiCategory.nature));
      // Grottes/Gorges
      queries.add(('node[cave_entrance=yes](around:RADIUS,LAT,LNG);', PoiCategory.nature));
      // Sites naturels
      queries.add(('node[natural=peak](around:RADIUS,LAT,LNG);', PoiCategory.nature));
      queries.add(('node[natural=cave](around:RADIUS,LAT,LNG);', PoiCategory.nature));
    }

    if (filters.categories.contains(PoiCategory.histoire)) {
      // Ruines
      queries.add(('node[historic=ruins](around:RADIUS,LAT,LNG);', PoiCategory.histoire));
    }

    if (filters.categories.contains(PoiCategory.activites)) {
      // Randonnées / sentiers de montagne
      queries.add(('node[tourism=alpine_hut](around:RADIUS,LAT,LNG);', PoiCategory.activites));
      queries.add(('node[tourism=wilderness_hut](around:RADIUS,LAT,LNG);', PoiCategory.activites));
    }

    return queries;
  }
}
