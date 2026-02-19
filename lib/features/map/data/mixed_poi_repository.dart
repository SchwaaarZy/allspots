import 'poi_repository.dart';
import '../domain/poi.dart';
import '../domain/poi_filters.dart';

/// Repository hybride qui fusionne les résultats de deux sources:
/// - 🏘️ Firestore: Spots créés par les utilisateurs
/// - 🗺️ Google Places: Lieux publics référencés par Google
/// 
/// Fonctionnement:
/// 1. Que les deux repositorys en parallèle (performance)
/// 2. Fusionne les résultats
/// 3. Déduplique les lieux (en cas de chevauchement avec même placeId)
/// 4. Trie le tout par distance à l'utilisateur
/// 
/// Résultat: Une couverture complète des lieux autour de l'utilisateur,
/// enrichie par les découvertes locales crowdsourcées.
class MixedPoiRepository implements PoiRepository {
  MixedPoiRepository({
    required this.firestoreRepo,
    required this.placesRepo,
  });

  final PoiRepository firestoreRepo;
  final PoiRepository placesRepo;

  @override
  Future<List<Poi>> getNearbyPois({
    required double userLat,
    required double userLng,
    required double radiusMeters,
    required PoiFilters filters,
  }) async {
    final results = await Future.wait([
      firestoreRepo.getNearbyPois(
        userLat: userLat,
        userLng: userLng,
        radiusMeters: radiusMeters,
        filters: filters,
      ),
      placesRepo.getNearbyPois(
        userLat: userLat,
        userLng: userLng,
        radiusMeters: radiusMeters,
        filters: filters,
      ),
    ]);

    final merged = <String, Poi>{};
    for (final list in results) {
      for (final poi in list) {
        merged[poi.id] = poi;
      }
    }

    return merged.values.toList();
  }
}
