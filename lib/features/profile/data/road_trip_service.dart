import 'package:cloud_firestore/cloud_firestore.dart';

import '../../map/domain/poi.dart';

class RoadTripItem {
  final String id;
  final String source;
  final String name;
  final double lat;
  final double lng;
  final String category;
  final String? subCategory;

  const RoadTripItem({
    required this.id,
    required this.source,
    required this.name,
    required this.lat,
    required this.lng,
    required this.category,
    this.subCategory,
  });

  factory RoadTripItem.fromMap(Map<String, dynamic> map) {
    return RoadTripItem(
      id: map['id'] as String? ?? '',
      source: map['source'] as String? ?? '',
      name: map['name'] as String? ?? '',
      lat: (map['lat'] as num?)?.toDouble() ?? 0,
      lng: (map['lng'] as num?)?.toDouble() ?? 0,
      category: map['category'] as String? ?? 'culture',
      subCategory: map['subCategory'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'source': source,
      'name': name,
      'lat': lat,
      'lng': lng,
      'category': category,
      'subCategory': subCategory,
    };
  }

  static RoadTripItem fromPoi(Poi poi) {
    return RoadTripItem(
      id: poi.id,
      source: poi.source,
      name: poi.displayName,
      lat: poi.lat,
      lng: poi.lng,
      category: poi.category.name,
      subCategory: poi.subCategory,
    );
  }
}

enum RoadTripAddResult {
  added,
  alreadyExists,
  maxReached,
  maxTripsReached,
}

class RoadTripPlan {
  final String id;
  final String name;
  final List<RoadTripItem> items;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const RoadTripPlan({
    required this.id,
    required this.name,
    required this.items,
    this.createdAt,
    this.updatedAt,
  });

  factory RoadTripPlan.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final rawItems = (data['items'] as List?) ?? const <dynamic>[];
    final items = rawItems
        .whereType<Map>()
        .map((e) => RoadTripItem.fromMap(Map<String, dynamic>.from(e)))
        .toList();
    final createdTs = data['createdAt'] as Timestamp?;
    final updatedTs = data['updatedAt'] as Timestamp?;
    final fallbackName =
        doc.id == 'active' ? 'Road trip principal' : 'Road trip';
    return RoadTripPlan(
      id: doc.id,
      name: (data['name'] as String?)?.trim().isNotEmpty == true
          ? (data['name'] as String).trim()
          : fallbackName,
      items: items,
      createdAt: createdTs?.toDate(),
      updatedAt: updatedTs?.toDate(),
    );
  }
}

class RoadTripService {
  static const int maxItemsFree = 10;
  static const int maxItemsPremium = 10;
  static const int maxTripsFree = 2;
  static const int maxTripsPremium = 5;

  static int maxItemsFor(bool hasPremiumPass) {
    return hasPremiumPass ? maxItemsPremium : maxItemsFree;
  }

  static int maxTripsFor(bool hasPremiumPass) {
    return hasPremiumPass ? maxTripsPremium : maxTripsFree;
  }

  static CollectionReference<Map<String, dynamic>> _collection(String uid) {
    return FirebaseFirestore.instance
        .collection('profiles')
        .doc(uid)
        .collection('roadTrips');
  }

  static DocumentReference<Map<String, dynamic>> _doc(
    String uid,
    String tripId,
  ) {
    return _collection(uid).doc(tripId);
  }

  static int _sortScore(RoadTripPlan plan) {
    final updated = plan.updatedAt?.millisecondsSinceEpoch ?? 0;
    final created = plan.createdAt?.millisecondsSinceEpoch ?? 0;
    return updated > 0 ? updated : created;
  }

  static List<RoadTripPlan> _sortPlans(List<RoadTripPlan> plans) {
    final sorted = [...plans];
    sorted.sort((a, b) => _sortScore(b).compareTo(_sortScore(a)));
    return sorted;
  }

  static Stream<List<RoadTripPlan>> plansStream(String uid) {
    return _collection(uid).snapshots().map((snapshot) {
      final plans = snapshot.docs.map(RoadTripPlan.fromDoc).toList();
      return _sortPlans(plans);
    });
  }

  static Future<List<RoadTripPlan>> getPlans(String uid) async {
    final snapshot = await _collection(uid).get();
    final plans = snapshot.docs.map(RoadTripPlan.fromDoc).toList();
    return _sortPlans(plans);
  }

  static Future<String?> createPlan(
    String uid, {
    required int maxTrips,
    String? name,
  }) async {
    final plans = await getPlans(uid);
    if (plans.length >= maxTrips) return null;

    final doc = _collection(uid).doc();
    await doc.set({
      'name': (name?.trim().isNotEmpty == true) ? name!.trim() : 'Road trip',
      'items': const <Map<String, dynamic>>[],
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  static Future<void> deletePlan(String uid, String tripId) async {
    await _doc(uid, tripId).delete();
  }

  static Future<List<RoadTripItem>> getItems(
    String uid, {
    String? tripId,
  }) async {
    final plans = await getPlans(uid);
    if (plans.isEmpty) return const <RoadTripItem>[];
    if (tripId != null) {
      for (final plan in plans) {
        if (plan.id == tripId) return plan.items;
      }
    }
    return plans.first.items;
  }

  static Stream<List<RoadTripItem>> itemsStream(
    String uid, {
    String? tripId,
  }) {
    return plansStream(uid).map((plans) {
      if (plans.isEmpty) return const <RoadTripItem>[];
      if (tripId != null) {
        for (final plan in plans) {
          if (plan.id == tripId) return plan.items;
        }
      }
      return plans.first.items;
    });
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> stream(String uid) {
    // Kept for backward compatibility with existing code paths.
    return _doc(uid, 'active').snapshots();
  }

  static Future<void> saveItems(
    String uid,
    List<RoadTripItem> items, {
    String? tripId,
  }) async {
    var targetTripId = tripId;
    if (targetTripId == null) {
      final plans = await getPlans(uid);
      if (plans.isEmpty) {
        await _doc(uid, 'active').set({
          'name': 'Road trip principal',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'items': items.map((e) => e.toMap()).toList(),
        }, SetOptions(merge: true));
        return;
      }
      targetTripId = plans.first.id;
    }

    await _doc(uid, targetTripId).set({
      'items': items.map((e) => e.toMap()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<RoadTripAddResult> addPoi(
    String uid,
    Poi poi, {
    required int maxItems,
    required int maxTrips,
    String? tripId,
  }) async {
    final plans = await getPlans(uid);
    RoadTripPlan? target;

    if (plans.isEmpty) {
      final createdTripId = await createPlan(uid, maxTrips: maxTrips);
      if (createdTripId == null) return RoadTripAddResult.maxTripsReached;
      final refreshed = await getPlans(uid);
      for (final plan in refreshed) {
        if (plan.id == createdTripId) {
          target = plan;
          break;
        }
      }
      target ??= refreshed.isNotEmpty ? refreshed.first : null;
    } else if (tripId != null) {
      for (final plan in plans) {
        if (plan.id == tripId) {
          target = plan;
          break;
        }
      }
      target ??= plans.first;
    } else {
      target = plans.first;
    }

    if (target == null) return RoadTripAddResult.maxTripsReached;
    final items = [...target.items];
    final exists = items.any(
      (item) => item.id == poi.id && item.source == poi.source,
    );
    if (exists) return RoadTripAddResult.alreadyExists;
    if (items.length >= maxItems) return RoadTripAddResult.maxReached;

    items.add(RoadTripItem.fromPoi(poi));
    await saveItems(uid, items, tripId: target.id);
    return RoadTripAddResult.added;
  }

  static Future<void> removeAt(
    String uid,
    int index, {
    String? tripId,
  }) async {
    final items = await getItems(uid, tripId: tripId);
    if (index < 0 || index >= items.length) return;
    items.removeAt(index);
    await saveItems(uid, items, tripId: tripId);
  }

  static Future<void> clear(String uid, {String? tripId}) async {
    await saveItems(uid, const <RoadTripItem>[], tripId: tripId);
  }
}
