import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../../core/utils/geo_utils.dart';
import '../domain/poi.dart';
import '../domain/poi_category.dart';
import '../domain/poi_filters.dart';
import 'poi_repository.dart';

/// Repository pour récupérer les spots créés par les utilisateurs depuis Firestore
/// 
/// Le système fonctionne en deux étapes:
/// 1. Requête Firestore pour les spots publics, filtrés par catégorie et distance
/// 2. Mapping des catégories Firestore aux catégories AllSpots
/// 
/// Les spots utilisateurs enrichissent les données Google Places, offrant
/// un contenu personnalisé et du crowd-sourcing de découvertes locales.
class FirestorePoiRepository implements PoiRepository {
  FirestorePoiRepository(this._firestore);

  final FirebaseFirestore _firestore;

  @override
  Future<List<Poi>> getNearbyPois({
    required double userLat,
    required double userLng,
    required double radiusMeters,
    required PoiFilters filters,
  }) async {
    try {
      final groupFilters = _categoryGroupFilters(filters.categories);
      
      Query<Map<String, dynamic>> query =
          _firestore.collection('spots').where('isPublic', isEqualTo: true);

      if (groupFilters.isNotEmpty && groupFilters.length <= 10) {
        query = query.where('categoryGroup', whereIn: groupFilters);
      }

      final snapshot = await query.limit(200).get();
      
      final results = <Poi>[];

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final lat = (data['lat'] as num?)?.toDouble();
        final lng = (data['lng'] as num?)?.toDouble();
        if (lat == null || lng == null) continue;

        final distance = GeoUtils.distanceMeters(
          lat1: userLat,
          lon1: userLng,
          lat2: lat,
          lon2: lng,
        );
        if (distance > radiusMeters) continue;

        if (filters.openNow) {
          final openNow = data['openNow'] as bool?;
          if (openNow != true) continue;
        }

        final categoryGroup = (data['categoryGroup'] as String?) ?? '';
        final category = _mapGroupToCategory(categoryGroup);
        if (!filters.categories.contains(category)) continue;

        results.add(
          Poi(
            id: doc.id,
            name: (data['name'] as String?) ?? 'Spot',
            category: category,
            subCategory: data['categoryItem'] as String?,
            lat: lat,
            lng: lng,
            shortDescription: (data['description'] as String?) ?? '',
            imageUrls: _stringList(data['imageUrls']),
            websiteUrl: data['websiteUrl'] as String?,
            isFree: data['isFree'] as bool?,
            pmrAccessible: data['pmrAccessible'] as bool?,
            kidsFriendly: data['kidsFriendly'] as bool?,
            source: 'firestore',
            updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ??
                DateTime.now(),
          ),
        );
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
      debugPrint('[FirestorePoiRepository] error=$e');
      return const [];
    }
  }

  List<String> _categoryGroupFilters(Set<PoiCategory> categories) {
    if (categories.length == PoiCategory.values.length) return [];

    return categories.map((cat) => _categoryLabel(cat)).toList();
  }

  String _categoryLabel(PoiCategory category) {
    switch (category) {
      case PoiCategory.histoire:
        return 'Patrimoine et Histoire';
      case PoiCategory.nature:
        return 'Nature';
      case PoiCategory.culture:
        return 'Culture';
      case PoiCategory.experienceGustative:
        return 'Experience gustative';
      case PoiCategory.activites:
        return 'Activites plein air';
    }
  }

  PoiCategory _mapGroupToCategory(String group) {
    switch (group) {
      case 'Patrimoine et Histoire':
        return PoiCategory.histoire;
      case 'Nature':
        return PoiCategory.nature;
      case 'Culture':
        return PoiCategory.culture;
      case 'Experience gustative':
        return PoiCategory.experienceGustative;
      case 'Activites plein air':
        return PoiCategory.activites;
      default:
        return PoiCategory.culture;
    }
  }

  List<String> _stringList(dynamic value) {
    if (value is List) {
      return value.whereType<String>().toList();
    }
    return const [];
  }
}
