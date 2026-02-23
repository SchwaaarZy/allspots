import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'dart:math' as math;
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
  static const int _pageSize = 300;
  static const int _maxDocsPerZone = 3000;
  static const int _maxPriorityLocalDocs = 2000;
  static const double _priorityLocalRadiusMeters = 150000; // 150 km

  static const List<_GeoZone> _zones = [
    _GeoZone('fr_nord_ouest', 46.0, 51.5, -5.8, 1.0),
    _GeoZone('fr_nord_est', 46.0, 51.5, 1.0, 8.5),
    _GeoZone('fr_sud_ouest', 41.0, 46.0, -5.8, 1.5),
    _GeoZone('fr_sud_est', 41.0, 46.0, 1.5, 9.8),
    _GeoZone('gp', 15.7, 16.6, -61.95, -61.0),
    _GeoZone('mq', 14.3, 14.95, -61.3, -60.7),
    _GeoZone('gf', 1.8, 6.0, -54.8, -51.5),
    _GeoZone('re', -21.45, -20.85, 55.1, 55.9),
    _GeoZone('yt', -13.2, -12.55, 45.0, 45.4),
    _GeoZone('pm', 46.65, 47.2, -56.6, -56.0),
    _GeoZone('bl', 17.82, 18.22, -63.3, -62.7),
    _GeoZone('mf', 18.0, 18.16, -63.2, -62.95),
    _GeoZone('wf', -14.5, -13.1, -177.4, -176.0),
    _GeoZone('pf', -28.5, -7.5, -154.0, -134.0),
    _GeoZone('nc', -23.0, -19.0, 163.0, 168.5),
  ];

  @override
  Future<List<Poi>> getNearbyPois({
    required double userLat,
    required double userLng,
    required double radiusMeters,
    required PoiFilters filters,
  }) async {
    try {
      final candidateZones = _selectZones(
        userLat: userLat,
        userLng: userLng,
        radiusMeters: radiusMeters,
      );

      final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      final seenIds = <String>{};

      final priorityRadius = math.min(radiusMeters, _priorityLocalRadiusMeters);
      final priorityDocs = await _fetchPriorityLocalDocuments(
        userLat: userLat,
        userLng: userLng,
        radiusMeters: priorityRadius,
      );

      for (final doc in priorityDocs) {
        if (seenIds.add(doc.id)) {
          docs.add(doc);
        }
      }

      for (final zone in candidateZones) {
        final zoneDocs = await _fetchZoneDocuments(zone);
        for (final doc in zoneDocs) {
          if (seenIds.add(doc.id)) {
            docs.add(doc);
          }
        }
      }

      final results = <Poi>[];

      for (final doc in docs) {
        final data = doc.data();
        if (data['isPublic'] == false) continue;

        final coordinates = _extractCoordinates(data);
        final lat = coordinates.$1;
        final lng = coordinates.$2;
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

        final category = _extractCategory(data);
        if (!filters.categories.contains(category)) continue;

        results.add(
          Poi(
            id: doc.id,
            name: (data['name'] as String?) ?? 'Spot',
            category: category,
            subCategory: (data['categoryItem'] as String?) ??
                (data['subCategory'] as String?),
            lat: lat,
            lng: lng,
            shortDescription: (data['description'] as String?) ?? '',
            imageUrls: _stringList(data['imageUrls']).isNotEmpty
                ? _stringList(data['imageUrls'])
                : _stringList(data['images']),
            websiteUrl:
                (data['websiteUrl'] as String?) ?? (data['website'] as String?),
            isFree: data['isFree'] as bool?,
            pmrAccessible: data['pmrAccessible'] as bool?,
            kidsFriendly: data['kidsFriendly'] as bool?,
            source: 'firestore',
            updatedAt: _extractUpdatedAt(data),
            createdBy: data['createdBy'] as String?,
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

  List<_GeoZone> _selectZones({
    required double userLat,
    required double userLng,
    required double radiusMeters,
  }) {
    if (radiusMeters >= 5000000) {
      return _zones;
    }

    final latDelta = radiusMeters / 111320.0;
    final latRad = userLat * (math.pi / 180.0);
    final cosLat = math.cos(latRad).abs().clamp(0.2, 1.0);
    final lonDelta = radiusMeters / (111320.0 * cosLat);

    final minLat = userLat - latDelta;
    final maxLat = userLat + latDelta;
    final minLng = userLng - lonDelta;
    final maxLng = userLng + lonDelta;

    final selected = _zones.where((zone) {
      final latOverlap = zone.maxLat >= minLat && zone.minLat <= maxLat;
      final lngOverlap = zone.maxLng >= minLng && zone.minLng <= maxLng;
      return latOverlap && lngOverlap;
    }).toList();

    if (selected.isEmpty) {
      return _zones;
    }

    return selected;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _fetchZoneDocuments(
    _GeoZone zone,
  ) async {
    final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    QueryDocumentSnapshot<Map<String, dynamic>>? lastDoc;

    while (docs.length < _maxDocsPerZone) {
      Query<Map<String, dynamic>> query = _firestore
          .collection('spots')
          .where('lat', isGreaterThanOrEqualTo: zone.minLat)
          .where('lat', isLessThanOrEqualTo: zone.maxLat)
          .orderBy('lat')
          .limit(_pageSize);

      if (lastDoc != null) {
        query = query.startAfterDocument(lastDoc);
      }

      final page = await query.get();
      if (page.docs.isEmpty) {
        break;
      }

      for (final doc in page.docs) {
        final data = doc.data();
        final lng = (data['lng'] as num?)?.toDouble();
        if (lng == null) continue;
        if (lng < zone.minLng || lng > zone.maxLng) continue;
        docs.add(doc);
        if (docs.length >= _maxDocsPerZone) break;
      }

      if (page.docs.length < _pageSize) {
        break;
      }
      lastDoc = page.docs.last;
    }

    return docs;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _fetchPriorityLocalDocuments({
    required double userLat,
    required double userLng,
    required double radiusMeters,
  }) async {
    final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    QueryDocumentSnapshot<Map<String, dynamic>>? lastDoc;

    final latDelta = radiusMeters / 111320.0;
    final latRad = userLat * (math.pi / 180.0);
    final cosLat = math.cos(latRad).abs().clamp(0.2, 1.0);
    final lonDelta = radiusMeters / (111320.0 * cosLat);

    final minLat = userLat - latDelta;
    final maxLat = userLat + latDelta;
    final minLng = userLng - lonDelta;
    final maxLng = userLng + lonDelta;

    while (docs.length < _maxPriorityLocalDocs) {
      Query<Map<String, dynamic>> query = _firestore
          .collection('spots')
          .where('lat', isGreaterThanOrEqualTo: minLat)
          .where('lat', isLessThanOrEqualTo: maxLat)
          .orderBy('lat')
          .limit(_pageSize);

      if (lastDoc != null) {
        query = query.startAfterDocument(lastDoc);
      }

      final page = await query.get();
      if (page.docs.isEmpty) {
        break;
      }

      for (final doc in page.docs) {
        final data = doc.data();
        final lng = (data['lng'] as num?)?.toDouble();
        if (lng == null) continue;
        if (lng < minLng || lng > maxLng) continue;
        docs.add(doc);
        if (docs.length >= _maxPriorityLocalDocs) break;
      }

      if (page.docs.length < _pageSize) {
        break;
      }
      lastDoc = page.docs.last;
    }

    return docs;
  }

  (double?, double?) _extractCoordinates(Map<String, dynamic> data) {
    final lat = (data['lat'] as num?)?.toDouble();
    final lng = (data['lng'] as num?)?.toDouble();
    if (lat != null && lng != null) {
      return (lat, lng);
    }

    final location = data['location'];
    if (location is GeoPoint) {
      return (location.latitude, location.longitude);
    }

    if (location is Map<String, dynamic>) {
      final locationLat = (location['_latitude'] as num?)?.toDouble() ??
          (location['latitude'] as num?)?.toDouble();
      final locationLng = (location['_longitude'] as num?)?.toDouble() ??
          (location['longitude'] as num?)?.toDouble();
      return (locationLat, locationLng);
    }

    return (null, null);
  }

  PoiCategory _extractCategory(Map<String, dynamic> data) {
    final raw = ((data['categoryGroup'] as String?) ??
            (data['category'] as String?) ??
            '')
        .trim()
        .toLowerCase();

    switch (raw) {
      case 'patrimoine et histoire':
      case 'histoire':
        return PoiCategory.histoire;
      case 'nature':
        return PoiCategory.nature;
      case 'culture':
        return PoiCategory.culture;
      case 'experience gustative':
      case 'expérience gustative':
      case 'experiencegustative':
      case 'experience_gustative':
        return PoiCategory.experienceGustative;
      case 'activites plein air':
      case 'activités plein air':
      case 'activites':
      case 'activités':
        return PoiCategory.activites;
      default:
        return PoiCategory.culture;
    }
  }

  DateTime _extractUpdatedAt(Map<String, dynamic> data) {
    final updatedAt = data['updatedAt'];
    if (updatedAt is Timestamp) {
      return updatedAt.toDate();
    }
    if (updatedAt is String) {
      final parsed = DateTime.tryParse(updatedAt);
      if (parsed != null) return parsed;
    }

    final createdAt = data['createdAt'];
    if (createdAt is Timestamp) {
      return createdAt.toDate();
    }

    return DateTime.now();
  }

  List<String> _stringList(dynamic value) {
    if (value is List) {
      return value.whereType<String>().toList();
    }
    return const [];
  }
}

class _GeoZone {
  const _GeoZone(this.id, this.minLat, this.maxLat, this.minLng, this.maxLng);

  final String id;
  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;
}
