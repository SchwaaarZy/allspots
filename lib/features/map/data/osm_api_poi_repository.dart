import 'dart:convert';

import 'package:http/http.dart' as http;
import '../domain/poi.dart';
import '../domain/poi_category.dart';
import '../domain/poi_filters.dart';
import 'poi_repository.dart';

class OsmApiPoiRepository implements PoiRepository {
  OsmApiPoiRepository(String baseUrl)
      : baseUrl = baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl;

  final String baseUrl;

  @override
  Future<List<Poi>> getNearbyPois({
    required double userLat,
    required double userLng,
    required double radiusMeters,
    required PoiFilters filters,
  }) async {
    final uri = Uri.parse('$baseUrl/poi').replace(
      queryParameters: {
        'lat': userLat.toString(),
        'lng': userLng.toString(),
        'radius': radiusMeters.toString(),
        'categories': filters.categories.map(_categoryKey).join(','),
      },
    );

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        return const [];
      }

      final data = jsonDecode(response.body);
      if (data is! List) return const [];

      return data
          .whereType<Map<String, dynamic>>()
          .map(_poiFromMap)
          .whereType<Poi>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Poi? _poiFromMap(Map<String, dynamic> map) {
    final id = map['id']?.toString();
    final name = map['name']?.toString();
    final lat = (map['lat'] as num?)?.toDouble();
    final lng = (map['lng'] as num?)?.toDouble();
    final category = _parseCategory(map['category']?.toString());

    if (id == null || name == null || lat == null || lng == null || category == null) {
      return null;
    }

    final imageUrls = map['imageUrls'] is List
        ? (map['imageUrls'] as List).whereType<String>().toList()
        : const <String>[];

    final updatedAt = DateTime.tryParse(map['updatedAt']?.toString() ?? '') ??
        DateTime.now();

    return Poi(
      id: id,
      name: name,
      category: category,
      subCategory: map['subCategory']?.toString(),
      lat: lat,
      lng: lng,
      shortDescription: map['shortDescription']?.toString() ?? '',
      imageUrls: imageUrls,
      websiteUrl: map['websiteUrl']?.toString(),
      isFree: map['isFree'] as bool?,
      pmrAccessible: map['pmrAccessible'] as bool?,
      kidsFriendly: map['kidsFriendly'] as bool?,
      source: 'osm',
      updatedAt: updatedAt,
    );
  }

  PoiCategory? _parseCategory(String? raw) {
    switch (raw?.toLowerCase()) {
      case 'culture':
        return PoiCategory.culture;
      case 'nature':
        return PoiCategory.nature;
      case 'experiencegustative':
      case 'experience_gustative':
      case 'gustative':
        return PoiCategory.experienceGustative;
      case 'histoire':
        return PoiCategory.histoire;
      case 'activites':
      case 'activite':
        return PoiCategory.activites;
      default:
        return null;
    }
  }

  String _categoryKey(PoiCategory category) {
    switch (category) {
      case PoiCategory.culture:
        return 'culture';
      case PoiCategory.nature:
        return 'nature';
      case PoiCategory.experienceGustative:
        return 'experience_gustative';
      case PoiCategory.histoire:
        return 'histoire';
      case PoiCategory.activites:
        return 'activites';
    }
  }
}
