import 'poi_category.dart';

class PoiFilters {
  final Set<PoiCategory> categories;
  final bool onlyFree;
  final bool pmrOnly;
  final bool kidsOnly;
  final bool openNow;
  final int? maxVisitDurationMin;

  const PoiFilters({
    required this.categories,
    this.onlyFree = false,
    this.pmrOnly = false,
    this.kidsOnly = false,
    this.openNow = false,
    this.maxVisitDurationMin,
  });

  factory PoiFilters.defaults() => PoiFilters(
        categories: PoiCategory.values.toSet(),
      );

  PoiFilters copyWith({
    Set<PoiCategory>? categories,
    bool? onlyFree,
    bool? pmrOnly,
    bool? kidsOnly,
    bool? openNow,
    int? maxVisitDurationMin,
  }) {
    return PoiFilters(
      categories: categories ?? this.categories,
      onlyFree: onlyFree ?? this.onlyFree,
      pmrOnly: pmrOnly ?? this.pmrOnly,
      kidsOnly: kidsOnly ?? this.kidsOnly,
      openNow: openNow ?? this.openNow,
      maxVisitDurationMin: maxVisitDurationMin ?? this.maxVisitDurationMin,
    );
  }
}
