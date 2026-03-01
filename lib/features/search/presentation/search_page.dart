import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/poi_categories.dart';
import '../../../core/models/region_model.dart';
import '../../../core/utils/geo_utils.dart';
import '../../../core/utils/responsive_utils.dart';
import '../../auth/data/auth_providers.dart';
import '../../map/domain/poi.dart';
import '../../map/domain/poi_category.dart';
import '../../map/presentation/map_controller.dart';
import '../../map/presentation/poi_detail_page.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  static const double _nearbyMaxDistanceMeters = 20000;

  String? _selectedRegionCode;
  String? _selectedDepartmentCode;
  bool _nearbyOnly = false;
  bool _initialized = false;
  final int _itemsPerPage = 10;
  int _currentPage = 0;
  bool _searchPerformed = false;
  late PageController _pageController;
  late final List<RegionModel> _regions;
  late final Map<String, List<DepartmentModel>> _departmentsByRegion;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    final france = allCountries.firstWhere(
      (country) => country.code.toLowerCase() == 'fr',
      orElse: () => allCountries.first,
    );
    _regions = france.regions;
    _departmentsByRegion = {
      for (final region in _regions) region.code: region.departments,
    };

    // Initialize map controller only once
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_initialized) {
        _initialized = true;
        ref.read(mapControllerProvider.notifier).init();
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primaryBlue = Theme.of(context).colorScheme.primary;
    final disabledBlue = primaryBlue.withValues(alpha: 0.45);
    final profile = ref.watch(profileStreamProvider);
    final profileCategories = (profile.value?.categories ?? const <String>[]).toSet();

    final mapState = ref.watch(mapControllerProvider);
    final userPos = mapState.userPosition;
    final selectedDepartments = _selectedRegionCode == null
      ? const <DepartmentModel>[]
      : (_departmentsByRegion[_selectedRegionCode!] ?? const []);
    final hasRequiredGeoSelection =
      _selectedRegionCode != null && _selectedDepartmentCode != null;

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            expandedHeight: 360,
            floating: false,
            pinned: false,
            backgroundColor: Colors.white,
            elevation: 0,
            scrolledUnderElevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _selectedRegionCode,
                      isExpanded: true,
                      iconEnabledColor: primaryBlue,
                      iconDisabledColor: disabledBlue,
                      style: TextStyle(
                        color: primaryBlue,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Région',
                        labelStyle: TextStyle(
                          color: primaryBlue,
                          fontWeight: FontWeight.w600,
                        ),
                        border: const OutlineInputBorder(),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: primaryBlue),
                          borderRadius: BorderRadius.circular(28),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: primaryBlue, width: 1.6),
                          borderRadius: BorderRadius.circular(28),
                        ),
                        isDense: true,
                      ),
                      items: [
                        for (final region in _regions)
                          DropdownMenuItem<String>(
                            value: region.code,
                            child: Text(
                              region.name,
                              style: TextStyle(
                                color: primaryBlue,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _selectedRegionCode = value;
                          _selectedDepartmentCode = null;
                          _searchPerformed = false;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedDepartmentCode,
                      isExpanded: true,
                      iconEnabledColor: primaryBlue,
                      iconDisabledColor: disabledBlue,
                      style: TextStyle(
                        color: primaryBlue,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Département',
                        labelStyle: TextStyle(
                          color: primaryBlue,
                          fontWeight: FontWeight.w600,
                        ),
                        border: const OutlineInputBorder(),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: primaryBlue),
                          borderRadius: BorderRadius.circular(28),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: primaryBlue, width: 1.6),
                          borderRadius: BorderRadius.circular(28),
                        ),
                        isDense: true,
                      ),
                      hint: Text(
                        _selectedRegionCode == null
                            ? 'Sélectionnez une région d\'abord'
                            : 'Sélectionnez un département',
                        style: TextStyle(color: disabledBlue),
                      ),
                      items: [
                        for (final department in selectedDepartments)
                          DropdownMenuItem<String>(
                            value: department.code,
                            child: Text(
                              '${department.code} • ${department.name}',
                              style: TextStyle(
                                color: primaryBlue,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                      onChanged: _selectedRegionCode == null
                          ? null
                          : (value) {
                        if (value == null) return;
                        setState(() {
                          _selectedDepartmentCode = value;
                          _searchPerformed = false;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    // Boutons d'action
                    Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              setState(() {
                                _selectedRegionCode = null;
                                _selectedDepartmentCode = null;
                                _nearbyOnly = false;
                                _currentPage = 0;
                                _searchPerformed = false;
                                _pageController.jumpToPage(0);
                              });
                            },
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text('Réinitialiser'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              setState(() {
                                _nearbyOnly = !_nearbyOnly;
                              });
                            },
                            icon: Icon(
                              _nearbyOnly ? Icons.near_me : Icons.near_me_outlined,
                              size: 16,
                            ),
                            style: OutlinedButton.styleFrom(
                              backgroundColor:
                                  _nearbyOnly ? Colors.blue.shade50 : null,
                            ),
                            label: const Text('À proximité (0 - 20 km)'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: hasRequiredGeoSelection
                                ? () {
                              setState(() => _searchPerformed = true);
                              _resetPage();
                              _pageController.jumpToPage(0);
                            }
                                : null,
                            icon: const Icon(Icons.search, size: 16),
                            label: const Text('Rechercher'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        body: !_searchPerformed || !hasRequiredGeoSelection
            ? _buildInitialSearchState(context)
            : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('spots')
                    .orderBy('updatedAt', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Impossible de charger les spots pour le moment.\nRéessaie dans quelques instants.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      ),
                    );
                  }

                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

            final allPois = snapshot.data!.docs
                .map(_poiFromDoc)
              .where((poi) => (poi.lat != 0 || poi.lng != 0) && !_isGenericSpot(poi))
                .toList(growable: false);

            final geoFiltered = allPois.where((poi) {
              if (!_matchesGeoFilter(poi)) return false;
              if (_nearbyOnly) {
                if (userPos == null) return false;
                final distance = GeoUtils.distanceMeters(
                  lat1: userPos.latitude,
                  lon1: userPos.longitude,
                  lat2: poi.lat,
                  lon2: poi.lng,
                );
                return distance <= _nearbyMaxDistanceMeters;
              }
              return true;
            }).toList(growable: false);

            final categoryFiltered = geoFiltered
                .where((poi) => _matchesCategoryFilter(poi, profileCategories))
                .toList(growable: false);

            final results = _sortedByDistance(categoryFiltered, userPos);
            final totalItems = results.length;
            final totalPages = (totalItems / _itemsPerPage).ceil();
            final pageIndex = totalPages == 0
                ? 0
                : _currentPage.clamp(0, totalPages - 1);
            final startIndex = pageIndex * _itemsPerPage;
            final endIndex = (startIndex + _itemsPerPage).clamp(0, totalItems);

                  return Column(
                    children: [
                      Expanded(
                        child: PageView.builder(
                    controller: _pageController,
                    onPageChanged: (page) {
                      setState(() {
                        _currentPage = page;
                      });
                    },
                    itemCount: totalPages == 0 ? 1 : totalPages,
                        itemBuilder: (context, pageIndex) {
                      final startIdx = pageIndex * _itemsPerPage;
                      final endIdx = (startIdx + _itemsPerPage).clamp(0, totalItems);
                      final pageResults = results.sublist(startIdx, endIdx);

                      if (_nearbyOnly && userPos == null && pageIndex == 0) {
                        return const Center(
                          child: Text(
                            '📍 Activez la localisation pour le filtre à proximité (0-20 km).',
                            style: TextStyle(color: Colors.grey),
                            textAlign: TextAlign.center,
                          ),
                        );
                      }

                      if (results.isEmpty && pageIndex == 0) {
                        return const Center(
                          child: Text(
                            '🔍 Aucun spot trouvé pour ces filtres géographiques.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        );
                      }

                      final items = <_SearchListItem>[];

                      if (pageResults.isNotEmpty) {
                        items.add(
                          _SearchListItem.header(
                            '🗺️ Spots (${pageResults.length})',
                          ),
                        );
                        for (final poi in pageResults) {
                          items.add(_SearchListItem.poi(poi));
                        }
                      }

                      if (pageIndex == totalPages - 1) {
                        items.add(const _SearchListItem.spacer(12));
                        items.add(const _SearchListItem.addSpot());
                      }

                      items.add(const _SearchListItem.spacer(12));

                      return ListView.builder(
                        key: PageStorageKey('search_page_$pageIndex'),
                        padding: const EdgeInsets.all(12),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          switch (item.type) {
                            case _SearchListItemType.header:
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Text(
                                  item.label ?? '',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                              );
                            case _SearchListItemType.poi:
                              return _buildPoiCard(context, item.poi!, userPos);
                            case _SearchListItemType.addSpot:
                              return SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () => context.push('/spots/new'),
                                  icon: const Icon(Icons.add_location_alt),
                                  label: const Text('➕ Ajouter un spot'),
                                ),
                              );
                            case _SearchListItemType.spacer:
                              return SizedBox(height: item.spacing ?? 0);
                          }
                        },
                      );
                          },
                        ),
                      ),
                      if (totalItems > _itemsPerPage)
                        Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        ElevatedButton.icon(
                          onPressed: pageIndex > 0
                              ? () {
                                  _pageController.previousPage(
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.easeInOut,
                                  );
                                }
                              : null,
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('Précédent'),
                        ),
                        Text(
                          '${startIndex + 1} - $endIndex sur $totalItems',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        ElevatedButton.icon(
                          onPressed: pageIndex < totalPages - 1
                              ? () {
                                  _pageController.nextPage(
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.easeInOut,
                                  );
                                }
                              : null,
                          icon: const Icon(Icons.arrow_forward),
                          label: const Text('Suivant'),
                        ),
                      ],
                    ),
                        ),
                    ],
                  );
                },
              ),
      ),
    );
  }

  Widget _buildInitialSearchState(BuildContext context) {
    final hasRegion = _selectedRegionCode != null;
    final hasDepartment = _selectedDepartmentCode != null;

    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search,
              size: 64,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              'Préparez votre Road Trip',
              style: TextStyle(
                fontSize: context.fontSize(16),
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                '1. Sélectionnez une région\n2. Sélectionnez un département de cette région\n3. Les catégories de votre profil sont appliquées automatiquement\n4. Activez "À proximité (0-20 km)" si besoin\n5. Cliquez sur "Rechercher"',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: context.fontSize(13),
                  color: Colors.grey.shade600,
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (!hasRegion || !hasDepartment)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  '⚠️ Région et département sont obligatoires pour afficher les spots.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: context.fontSize(12),
                    color: Colors.orange.shade800,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Poi> _sortedByDistance(
    List<Poi> pois,
    Position? pos,
  ) {
    final list = [...pois];
    if (pos != null) {
      list.sort((a, b) {
        final da = GeoUtils.distanceMeters(
          lat1: pos.latitude,
          lon1: pos.longitude,
          lat2: a.lat,
          lon2: a.lng,
        );
        final db = GeoUtils.distanceMeters(
          lat1: pos.latitude,
          lon1: pos.longitude,
          lat2: b.lat,
          lon2: b.lng,
        );
        return da.compareTo(db);
      });
    }
    return list;
  }

  String _normalizeFilterToken(String value) {
    return value
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

  bool _isGenericSpot(Poi poi) {
    final normalizedName = _normalizeFilterToken(poi.name);
    final normalizedDisplayName = _normalizeFilterToken(poi.displayName);
    final normalizedSubCategory =
        _normalizeFilterToken(formatPoiSubCategory(poi.subCategory));
    final normalizedRawSubCategory = _normalizeFilterToken(poi.subCategory ?? '');

    const genericNames = {
      'autre',
      'other',
      'poi',
      'spot',
      'sans nom',
      'poi sans nom',
      'point d interet poi sans nom',
      'point dinteret poi sans nom',
      'point interet poi sans nom',
      'point d interet',
      'point interet',
    };

    const genericSubCategories = {
      'autre',
      'other',
      'poi',
      'point d interet',
      'point interet',
    };

    if (normalizedName.isEmpty || normalizedDisplayName.isEmpty) {
      return true;
    }

    if (genericNames.contains(normalizedName) ||
        genericNames.contains(normalizedDisplayName)) {
      return true;
    }

    if (normalizedName.contains('poi sans nom') ||
        normalizedDisplayName.contains('poi sans nom')) {
      return true;
    }

    if (genericSubCategories.contains(normalizedSubCategory) ||
        genericSubCategories.contains(normalizedRawSubCategory)) {
      return true;
    }

    return false;
  }

  bool _matchesCategoryFilter(Poi poi, Set<String> selectedCategories) {
    if (selectedCategories.isEmpty) return true;

    final wanted = selectedCategories
        .map(_normalizeFilterToken)
        .where((value) => value.isNotEmpty)
        .toSet();

    if (wanted.isEmpty) return true;

    final candidates = <String>{
      _normalizeFilterToken(poi.category.label),
      _normalizeFilterToken(_groupTitleForCategory(poi.category)),
      _normalizeFilterToken(formatPoiSubCategory(poi.subCategory)),
      _normalizeFilterToken(poi.subCategory ?? ''),
      ..._aliasesForPoiCategory(poi.category),
    }..removeWhere((value) => value.isEmpty);

    final matchesByText = candidates.any((candidate) {
      return wanted.any((interest) {
        if (_tokenEquals(candidate, interest)) return true;
        if (_tokenContains(candidate, interest) ||
            _tokenContains(interest, candidate)) {
          return true;
        }
        final candidateTokens = candidate
            .split(' ')
            .where((t) => t.isNotEmpty)
            .map(_canonicalToken)
            .toSet();
        final interestTokens = interest
            .split(' ')
            .where((t) => t.isNotEmpty)
            .map(_canonicalToken)
            .toSet();
        return candidateTokens.any(interestTokens.contains);
      });
    });

    if (matchesByText) return true;

    return _isWholeGroupSelected(poi.category, wanted);
  }

  bool _isWholeGroupSelected(PoiCategory category, Set<String> wanted) {
    final groupTitle = _groupTitleForCategory(category);
    final group = poiCategoryGroups.where((g) => g.title == groupTitle).firstOrNull;
    if (group == null) return false;

    final normalizedItems = group.items
        .map(_normalizeFilterToken)
        .where((value) => value.isNotEmpty)
        .toSet();

    if (normalizedItems.isEmpty) return false;
    return normalizedItems.every(wanted.contains);
  }

  String _groupTitleForCategory(PoiCategory category) {
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

  Set<String> _aliasesForPoiCategory(PoiCategory category) {
    switch (category) {
      case PoiCategory.histoire:
        return {'patrimoine', 'histoire', 'monument', 'chateau', 'ruine'};
      case PoiCategory.nature:
        return {'nature', 'cascade', 'gorge', 'belvedere', 'site naturel'};
      case PoiCategory.culture:
        return {'culture', 'musee', 'opera', 'exposition', 'festival'};
      case PoiCategory.experienceGustative:
        return {'gustative', 'restaurant', 'degustation', 'viticole', 'brasserie'};
      case PoiCategory.activites:
        return {'activites', 'randonnee', 'sport', 'familiale', 'plein air'};
    }
  }

  String _canonicalToken(String value) {
    final token = _normalizeFilterToken(value);
    if (token.length <= 3) return token;

    if (token.endsWith('aux') && token.length > 4) {
      return '${token.substring(0, token.length - 3)}al';
    }
    if (token.endsWith('eaux') && token.length > 5) {
      return token.substring(0, token.length - 1);
    }
    if (token.endsWith('s') || token.endsWith('x')) {
      return token.substring(0, token.length - 1);
    }
    return token;
  }

  bool _tokenEquals(String left, String right) {
    return _canonicalToken(left) == _canonicalToken(right);
  }

  bool _tokenContains(String text, String query) {
    final normalizedText = _canonicalToken(text);
    final normalizedQuery = _canonicalToken(query);
    return normalizedText.contains(normalizedQuery);
  }

  bool _matchesGeoFilter(Poi poi) {
    if (_selectedRegionCode == null || _selectedDepartmentCode == null) {
      return false;
    }

    final departmentCode = poi.departmentCode?.trim().toUpperCase();

    if (departmentCode == null) return false;

    final regionDepartments =
        _departmentsByRegion[_selectedRegionCode!] ?? const [];
    if (regionDepartments.isEmpty) return false;

    final isDepartmentInSelectedRegion =
        regionDepartments.any((dep) => dep.code == _selectedDepartmentCode);
    if (!isDepartmentInSelectedRegion) return false;

    return departmentCode == _selectedDepartmentCode;
  }

  Poi _poiFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();

    final location = data['location'];
    final lat = (data['lat'] as num?)?.toDouble() ??
        (location is GeoPoint ? location.latitude : 0.0);
    final lng = (data['lng'] as num?)?.toDouble() ??
        (location is GeoPoint ? location.longitude : 0.0);

    final rawDepartment =
        data['departmentCode'] ?? data['departementCode'] ?? data['dept'];
    String? departmentCode;
    if (rawDepartment != null) {
      departmentCode = rawDepartment.toString().trim().toUpperCase();
      if (RegExp(r'^\d$').hasMatch(departmentCode)) {
        departmentCode = '0$departmentCode';
      }
    }

    final updatedAtRaw = data['updatedAt'];
    DateTime updatedAt;
    if (updatedAtRaw is Timestamp) {
      updatedAt = updatedAtRaw.toDate();
    } else if (updatedAtRaw is String) {
      updatedAt = DateTime.tryParse(updatedAtRaw) ?? DateTime.now();
    } else {
      updatedAt = DateTime.now();
    }

    final imageUrls = (data['imageUrls'] as List?)
            ?.whereType<String>()
            .toList(growable: false) ??
        const <String>[];

    return Poi(
      id: doc.id,
      name: (data['name'] as String?)?.trim() ?? '',
      category: poiCategoryFromString(
        (data['categoryGroup'] ?? data['category'] ?? '').toString(),
      ),
      subCategory: data['categoryItem'] as String?,
      lat: lat,
      lng: lng,
      shortDescription: (data['description'] as String?)?.trim() ?? '',
      imageUrls: imageUrls,
      websiteUrl: data['websiteUrl'] as String? ?? data['website'] as String?,
      source: (data['source'] as String?)?.trim().isNotEmpty == true
          ? (data['source'] as String)
          : 'firestore',
      updatedAt: updatedAt,
      googleRating: (data['googleRating'] as num?)?.toDouble(),
      createdBy: data['createdBy'] as String?,
      departmentCode: departmentCode,
    );
  }

  void _resetPage() {
    if (_currentPage == 0) return;
    setState(() => _currentPage = 0);
  }

  String _distanceLabel(Position? pos, double lat, double lng) {
    if (pos == null) return '-';
    final meters = GeoUtils.distanceMeters(
      lat1: pos.latitude,
      lon1: pos.longitude,
      lat2: lat,
      lon2: lng,
    );
    final km = meters / 1000;
    return '${km.toStringAsFixed(1)} km';
  }

  Widget _buildPoiCard(BuildContext context, Poi poi, Position? userPos) {
    final distanceLabel = _distanceLabel(userPos, poi.lat, poi.lng);
    final isFirestore = poi.source == 'firestore';
    final rating = poi.googleRating;
    final photoCount = poi.imageUrls.length;
    final subCategoryLabel = formatPoiSubCategory(poi.subCategory);
    final categoryLabel =
        subCategoryLabel.isNotEmpty ? subCategoryLabel : poi.category.label;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PoiDetailPage(
                poi: poi,
                userLocation: userPos,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (isFirestore)
                              const Padding(
                                padding: EdgeInsets.only(right: 6),
                                child: Tooltip(
                                  message: 'Spot communautaire',
                                  child: Icon(
                                    Icons.home,
                                    size: 16,
                                    color: Colors.green,
                                  ),
                                ),
                              ),
                            Expanded(
                              child: Text(
                                poi.displayName,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: context.fontSize(14),
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              iconForSubCategory(
                                poi.subCategory,
                                poi.category,
                              ),
                              size: 14,
                              color: poi.category.color,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              categoryLabel,
                              style: TextStyle(
                                fontSize: context.fontSize(12),
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        distanceLabel,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                      if (rating != null)
                        Row(
                          children: [
                            const Icon(Icons.star, size: 12, color: Colors.amber),
                            const SizedBox(width: 2),
                            Text(
                              rating.toStringAsFixed(1),
                              style: TextStyle(fontSize: context.fontSize(11)),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                poi.shortDescription,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: context.fontSize(12),
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (photoCount > 0) ...[
                    Icon(
                      Icons.image,
                      size: 14,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$photoCount',
                      style: TextStyle(
                        fontSize: context.fontSize(12),
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  if (rating != null) ...[
                    const Icon(
                      Icons.star,
                      size: 14,
                      color: Colors.amber,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      rating.toStringAsFixed(1),
                      style: TextStyle(
                        fontSize: context.fontSize(12),
                        color: Colors.amber,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _SearchListItemType {
  header,
  poi,
  addSpot,
  spacer,
}

class _SearchListItem {
  final _SearchListItemType type;
  final String? label;
  final Poi? poi;
  final double? spacing;

  const _SearchListItem._(
    this.type, {
    this.label,
    this.poi,
    this.spacing,
  });

  const _SearchListItem.addSpot() : this._(_SearchListItemType.addSpot);

  const _SearchListItem.header(String label)
      : this._(_SearchListItemType.header, label: label);

  const _SearchListItem.poi(Poi poi)
      : this._(_SearchListItemType.poi, poi: poi);

  const _SearchListItem.spacer(double spacing)
      : this._(_SearchListItemType.spacer, spacing: spacing);
}
