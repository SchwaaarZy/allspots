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
  
  final String? createdBy; // UID de l'utilisateur qui a créé le spot (null pour Google Places/OSM)
  final String? departmentCode; // Code département (ex: "06", "13", "83")

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
    this.createdBy,
    this.departmentCode,
  });

  /// Retourne le nom du POI, ou une étiquette pertinente si le nom est vide
  String get displayName {
    final trimmedName = name.trim();
    final normalizedName = _normalizeLabel(trimmedName);
    final isPlaceholderName = _isPlaceholderName(normalizedName);

    if (!isPlaceholderName) return trimmedName;

    final normalizedDescription = shortDescription.trim().toLowerCase();
    if (normalizedDescription.contains('point de vue')) {
      return 'Point de vue';
    }

    final subCategoryLabel = formatPoiSubCategory(subCategory);
    final isPointInteret = normalizedDescription.contains("point d'interet") ||
        normalizedDescription.contains("point d'interêt") ||
        normalizedDescription.contains('point d interet');

    if (isPointInteret && subCategoryLabel.isNotEmpty) {
      return subCategoryLabel;
    }

    if (subCategoryLabel.isNotEmpty) return subCategoryLabel;
    return category.label;
  }

  bool _isPlaceholderName(String normalizedName) {
    if (normalizedName.isEmpty) return true;

    const placeholders = {
      'poi sans nom',
      'point d interet poi sans nom',
      'point dinteret poi sans nom',
      'point interet poi sans nom',
      'sans nom',
      'spot',
      'unknown',
      'unnamed',
      'poi',
    };

    if (placeholders.contains(normalizedName)) return true;
    if (normalizedName.contains('poi sans nom')) return true;
    if (normalizedName.contains('point d interet') &&
        normalizedName.contains('sans nom')) {
      return true;
    }
    return false;
  }

  String _normalizeLabel(String input) {
    return input
        .toLowerCase()
        .trim()
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('à', 'a')
        .replaceAll('â', 'a')
        .replaceAll('ù', 'u')
        .replaceAll('û', 'u')
        .replaceAll('ô', 'o')
        .replaceAll('î', 'i')
        .replaceAll('ï', 'i')
        .replaceAll("'", ' ')
        .replaceAll('-', ' ')
        .replaceAll(':', ' ')
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Map<String, dynamic> toCacheMap() {
    return {
      'id': id,
      'name': name,
      'categoryIndex': category.index,
      'subCategory': subCategory,
      'lat': lat,
      'lng': lng,
      'shortDescription': shortDescription,
      'imageUrls': imageUrls,
      'websiteUrl': websiteUrl,
      'isFree': isFree,
      'visitDurationMin': visitDurationMin,
      'pmrAccessible': pmrAccessible,
      'kidsFriendly': kidsFriendly,
      'googleRating': googleRating,
      'googleRatingCount': googleRatingCount,
      'source': source,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
      'createdBy': createdBy,
      'departmentCode': departmentCode,
    };
  }

  static Poi fromCacheMap(Map<String, dynamic> map) {
    final categoryIndex = map['categoryIndex'] as int? ?? 0;
    final category = categoryIndex >= 0 &&
            categoryIndex < PoiCategory.values.length
        ? PoiCategory.values[categoryIndex]
        : PoiCategory.culture;

    return Poi(
      id: (map['id'] as String?) ?? '',
      name: (map['name'] as String?) ?? '',
      category: category,
      subCategory: map['subCategory'] as String?,
      lat: (map['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (map['lng'] as num?)?.toDouble() ?? 0.0,
      shortDescription: (map['shortDescription'] as String?) ?? '',
      imageUrls: (map['imageUrls'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      websiteUrl: map['websiteUrl'] as String?,
      isFree: map['isFree'] as bool?,
      visitDurationMin: map['visitDurationMin'] as int?,
      pmrAccessible: map['pmrAccessible'] as bool?,
      kidsFriendly: map['kidsFriendly'] as bool?,
      googleRating: (map['googleRating'] as num?)?.toDouble(),
      googleRatingCount: map['googleRatingCount'] as int?,
      source: (map['source'] as String?) ?? 'cache',
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['updatedAt'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
      ),
      createdBy: map['createdBy'] as String?,
      departmentCode: map['departmentCode'] as String?,
    );
  }
}

