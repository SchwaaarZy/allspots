import 'poi_category.dart';

class Poi {
  final String id;
  final String name;
  final PoiCategory category;
  final String? subCategory;
  final double lat;
  final double lng;
  final String shortDescription;
  final List<String> imageUrls;
  final String? websiteUrl;

  final bool? isFree;
  final int? visitDurationMin;
  final bool? pmrAccessible;
  final bool? kidsFriendly;
  
  final double? googleRating; // Note Google (0-5)
  final int? googleRatingCount; // Nombre d'avis Google

  final String source; // "mock", "osm", "curated", "user"
  final DateTime updatedAt;

  const Poi({
    required this.id,
    required this.name,
    required this.category,
    required this.lat,
    required this.lng,
    required this.shortDescription,
    required this.imageUrls,
    required this.source,
    required this.updatedAt,
    this.subCategory,
    this.websiteUrl,
    this.isFree,
    this.visitDurationMin,
    this.pmrAccessible,
    this.kidsFriendly,
    this.googleRating,
    this.googleRatingCount,
  });
}
