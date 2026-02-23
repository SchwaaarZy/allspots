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
}

class RoadTripService {
  static const int maxItemsFree = 5;
  static const int maxItemsPremium = 10;

  static int maxItemsFor(bool hasPremiumPass) {
    return hasPremiumPass ? maxItemsPremium : maxItemsFree;
  }

  static DocumentReference<Map<String, dynamic>> _doc(String uid) {
    return FirebaseFirestore.instance
        .collection('profiles')
        .doc(uid)
        .collection('roadTrips')
        .doc('active');
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> stream(String uid) {
    return _doc(uid).snapshots();
  }

  static Future<List<RoadTripItem>> getItems(String uid) async {
    final snap = await _doc(uid).get();
    final data = snap.data();
    final rawItems = (data?['items'] as List?) ?? [];
    return rawItems
        .whereType<Map>()
        .map((e) => RoadTripItem.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Future<void> saveItems(String uid, List<RoadTripItem> items) async {
    await _doc(uid).set({
      'items': items.map((e) => e.toMap()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<RoadTripAddResult> addPoi(
    String uid,
    Poi poi, {
    required int maxItems,
  }) async {
    final items = await getItems(uid);
    final exists = items.any(
      (item) => item.id == poi.id && item.source == poi.source,
    );
    if (exists) return RoadTripAddResult.alreadyExists;
    if (items.length >= maxItems) return RoadTripAddResult.maxReached;

    items.add(RoadTripItem.fromPoi(poi));
    await saveItems(uid, items);
    return RoadTripAddResult.added;
  }

  static Future<void> removeAt(String uid, int index) async {
    final items = await getItems(uid);
    if (index < 0 || index >= items.length) return;
    items.removeAt(index);
    await saveItems(uid, items);
  }

  static Future<void> clear(String uid) async {
    await saveItems(uid, const []);
  }
}
