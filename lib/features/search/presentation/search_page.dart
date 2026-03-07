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
  static const Set<String> _stopWords = {
    'a',
    'au',
    'aux',
    'avec',
    'by',
    'd',
    'dans',
    'de',
    'des',
    'du',
    'en',
    'et',
    'for',
    'la',
    'le',
    'les',
    'of',
    'ou',
    'par',
    'pour',
    'sur',
    'the',
    'un',
    'une',
  };

  String? _selectedCountryCode;
  String? _selectedRegionCode;
  String? _selectedDepartmentCode;
  String _keywordQuery = '';
  List<String> _selectedKeywords = const <String>[];
  bool _nearbyOnly = false;
  bool _initialized = false;
  final int _itemsPerPage = 10;
  bool _searchPerformed = false;
  late PageController _pageController;
  late ValueNotifier<int> _pageNotifier;
  List<String> _dynamicKeywordSuggestions = const <String>[];
  String? _cachedResultsKey;
  List<Poi> _cachedResults = const <Poi>[];
  int? _cachedAllPoisIdentity;
  int? _cachedAllPoisLength;
  List<Poi> _cachedAllPois = const <Poi>[];
  String? _cachedDistanceAnchorKey;
  final Map<String, double> _cachedDistanceMetersByPoiKey = {};
  final Map<String, String> _cachedDistanceLabelByPoiKey = {};
  Set<String>? _cachedNormalizedSelectedCategories;
  String? _cachedNormalizedSelectedCategoriesKey;
  String? _cachedDepartmentStreamCode;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _cachedDepartmentStream;
  final Set<String> _favoriteToggleInFlight = {};
  final Map<String, DateTime> _favoriteTapLockUntilByPoiId = {};

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _pageNotifier = ValueNotifier<int>(0);

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
    _pageNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileStreamProvider);
    final profileCategories =
        (profile.value?.categories ?? const <String>[]).toSet();
    final normalizedProfileCategories =
        _normalizedSelectedCategories(profileCategories);
    final expandedHeight = 360.0;

    final userPos =
        ref.watch(mapControllerProvider.select((state) => state.userPosition));
    _ensureDistanceCacheAnchor(userPos);

    final selectedCountryLabel = _selectedCountryLabel();
    final selectedRegionLabel = _selectedRegionLabel();
    final selectedDepartmentLabel = _selectedDepartmentLabel();

    final hasRequiredGeoSelection = _selectedCountryCode != null &&
        _selectedRegionCode != null &&
        _selectedDepartmentCode != null;

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            expandedHeight: expandedHeight,
            floating: false,
            pinned: false,
            backgroundColor: Colors.white,
            elevation: 0,
            scrolledUnderElevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              background: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    padding: EdgeInsets.zero,
                    child: ConstrainedBox(
                      constraints:
                          BoxConstraints(minHeight: constraints.maxHeight),
                      child: Container(
                        color: Colors.white,
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _openGeoPicker,
                                icon: const Icon(Icons.public, size: 16),
                                label: Text('Pays: $selectedCountryLabel'),
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _openGeoPicker,
                                icon: const Icon(Icons.map_outlined, size: 16),
                                label: Text(
                                  selectedDepartmentLabel == null
                                      ? 'Région: $selectedRegionLabel'
                                      : 'Région: $selectedRegionLabel • Dép.: $selectedDepartmentLabel',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
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
                                        _selectedCountryCode = null;
                                        _selectedRegionCode = null;
                                        _selectedDepartmentCode = null;
                                        _nearbyOnly = false;
                                        _searchPerformed = false;
                                        _cachedResultsKey = null;
                                        _cachedResults = const <Poi>[];
                                      });
                                      _resetPage();
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
                                        _cachedResultsKey = null;
                                      });
                                    },
                                    icon: Icon(
                                      _nearbyOnly
                                          ? Icons.near_me
                                          : Icons.near_me_outlined,
                                      size: 16,
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      backgroundColor: _nearbyOnly
                                          ? Colors.blue.shade50
                                          : null,
                                    ),
                                    label:
                                        const Text('À proximité (0 - 20 km)'),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: hasRequiredGeoSelection
                                        ? () {
                                            setState(
                                                () => _searchPerformed = true);
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
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
        body: !_searchPerformed || !hasRequiredGeoSelection
            ? _buildInitialSearchState(context)
            : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _spotsStreamForCurrentSelection(),
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

                  final docs = snapshot.data!.docs;
                  final docsIdentity = identityHashCode(snapshot.data);
                  final docsLength = docs.length;

                  if (_cachedAllPoisIdentity != docsIdentity ||
                      _cachedAllPoisLength != docsLength) {
                    _cachedAllPois = docs
                        .map(_poiFromDoc)
                        .where(
                          (poi) =>
                              (poi.lat != 0 || poi.lng != 0) &&
                              !_isGenericSpot(poi),
                        )
                        .toList(growable: false);
                    _cachedAllPoisIdentity = docsIdentity;
                    _cachedAllPoisLength = docsLength;
                  }

                  final allPois = _cachedAllPois;

                  final dynamicSuggestions = _extractDynamicKeywordsFromPois(
                    allPois: allPois,
                    normalizedSelectedCategories: normalizedProfileCategories,
                    userPos: userPos,
                  );

                  final previousDynamicKey =
                      _dynamicKeywordSuggestions.join('|');
                  final nextDynamicKey = dynamicSuggestions.join('|');
                  if (previousDynamicKey != nextDynamicKey) {
                    _dynamicKeywordSuggestions = dynamicSuggestions;
                  }

                  final cacheKey = _buildResultsCacheKey(
                    docsIdentity: docsIdentity,
                    docsLength: docsLength,
                    profileCategories: profileCategories,
                    userPos: userPos,
                  );

                  if (_cachedResultsKey != cacheKey) {
                    _cachedResults = _computeFilteredResults(
                      allPois: allPois,
                      userPos: userPos,
                      normalizedSelectedCategories: normalizedProfileCategories,
                    );
                    _cachedResultsKey = cacheKey;
                  }

                  final results = _cachedResults;
                  final totalItems = results.length;
                  final totalPages = (totalItems / _itemsPerPage).ceil();
                  final currentPage = totalPages == 0
                      ? 0
                      : _pageNotifier.value.clamp(0, totalPages - 1);

                  if (_pageNotifier.value != currentPage) {
                    _pageNotifier.value = currentPage;
                  }

                  return Column(
                    children: [
                      Expanded(
                        child: PageView.builder(
                          controller: _pageController,
                          onPageChanged: (page) {
                            if (_pageNotifier.value != page) {
                              _pageNotifier.value = page;
                            }
                          },
                          itemCount: totalPages == 0 ? 1 : totalPages,
                          itemBuilder: (context, pageIndex) {
                            final startIdx = pageIndex * _itemsPerPage;
                            final endIdx =
                                (startIdx + _itemsPerPage).clamp(0, totalItems);
                            final pageResults =
                                results.sublist(startIdx, endIdx);

                            if (_nearbyOnly &&
                                userPos == null &&
                                pageIndex == 0) {
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

                            return _buildPageListWithAllSpotsRatings(
                              context: context,
                              pageIndex: pageIndex,
                              pageResults: pageResults,
                              items: items,
                              userPos: userPos,
                            );
                          },
                        ),
                      ),
                      if (totalItems > _itemsPerPage)
                        ValueListenableBuilder<int>(
                          valueListenable: _pageNotifier,
                          builder: (context, pageValue, _) {
                            final clampedPage =
                                pageValue.clamp(0, totalPages - 1);
                            final startIndex = clampedPage * _itemsPerPage;
                            final endIndex = (startIndex + _itemsPerPage)
                                .clamp(0, totalItems);

                            return Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  ElevatedButton.icon(
                                    onPressed: clampedPage > 0
                                        ? () {
                                            _pageController.previousPage(
                                              duration: const Duration(
                                                  milliseconds: 300),
                                              curve: Curves.easeInOut,
                                            );
                                          }
                                        : null,
                                    icon: const Icon(Icons.arrow_back),
                                    label: const Text('Précédent'),
                                  ),
                                  Text(
                                    '${startIndex + 1} - $endIndex sur $totalItems',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  ),
                                  ElevatedButton.icon(
                                    onPressed: clampedPage < totalPages - 1
                                        ? () {
                                            _pageController.nextPage(
                                              duration: const Duration(
                                                  milliseconds: 300),
                                              curve: Curves.easeInOut,
                                            );
                                          }
                                        : null,
                                    icon: const Icon(Icons.arrow_forward),
                                    label: const Text('Suivant'),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                    ],
                  );
                },
              ),
      ),
    );
  }

  Widget _buildInitialSearchState(BuildContext context) {
    final hasCountry = _selectedCountryCode != null;
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
            const SizedBox(height: 12),
            if (!hasCountry || !hasRegion || !hasDepartment)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  '⚠️ Pays, région et département sont obligatoires pour afficher les spots.',
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

  Stream<QuerySnapshot<Map<String, dynamic>>>
      _spotsStreamForCurrentSelection() {
    final selectedDepartment = _selectedDepartmentCode;
    if (selectedDepartment == null || selectedDepartment.isEmpty) {
      _cachedDepartmentStreamCode = null;
      _cachedDepartmentStream = null;
      return const Stream.empty();
    }

    if (_cachedDepartmentStreamCode == selectedDepartment &&
        _cachedDepartmentStream != null) {
      return _cachedDepartmentStream!;
    }

    final stream = FirebaseFirestore.instance
        .collection('spots')
        .where('isPublic', isEqualTo: true)
        .where('departmentCode', isEqualTo: selectedDepartment)
        .snapshots();

    _cachedDepartmentStreamCode = selectedDepartment;
    _cachedDepartmentStream = stream;
    return stream;
  }

  List<Poi> _sortedByDistance(
    List<Poi> pois,
    Position? pos,
  ) {
    final list = [...pois];
    if (pos != null) {
      list.sort((a, b) {
        final da = _distanceMeters(pos, a);
        final db = _distanceMeters(pos, b);
        return da.compareTo(db);
      });
    }
    return list;
  }

  String _poiDistanceKey(Poi poi) => '${poi.source}:${poi.id}';

  void _ensureDistanceCacheAnchor(Position? pos) {
    final anchor = pos == null
        ? 'null'
        : '${pos.latitude.toStringAsFixed(4)},${pos.longitude.toStringAsFixed(4)}';
    if (_cachedDistanceAnchorKey == anchor) return;

    _cachedDistanceAnchorKey = anchor;
    _cachedDistanceMetersByPoiKey.clear();
    _cachedDistanceLabelByPoiKey.clear();
  }

  double _distanceMeters(Position pos, Poi poi) {
    final key = _poiDistanceKey(poi);
    final cached = _cachedDistanceMetersByPoiKey[key];
    if (cached != null) return cached;

    final meters = GeoUtils.distanceMeters(
      lat1: pos.latitude,
      lon1: pos.longitude,
      lat2: poi.lat,
      lon2: poi.lng,
    );
    _cachedDistanceMetersByPoiKey[key] = meters;
    return meters;
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

  String _displayKeyword(String keyword) {
    final normalized = _normalizeFilterToken(keyword);
    if (normalized.isEmpty) return keyword;
    final words = normalized
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .toList(growable: false);
    return words.join(' ');
  }

  List<String> _keywordSuggestions(Set<String> profileCategories) {
    final tokens = profileCategories
        .map(_normalizeFilterToken)
        .where((v) => v.isNotEmpty)
        .toSet();

    final suggestions = <String>{};

    void addAll(List<String> values) {
      for (final value in values) {
        final normalized = _normalizeFilterToken(value);
        if (normalized.isNotEmpty) {
          suggestions.add(normalized);
        }
      }
    }

    final hasHistory = tokens.any((token) =>
        token.contains('histoire') ||
        token.contains('patrimoine') ||
        token.contains('chateau') ||
        token.contains('monument') ||
        token.contains('unesco') ||
        token.contains('abbaye') ||
        token.contains('religieux') ||
        token.contains('eglise') ||
        token.contains('cathedrale') ||
        token.contains('village') ||
        token.contains('archeologique'));
    final hasNature = tokens.any((token) =>
        token.contains('nature') ||
        token.contains('cascade') ||
        token.contains('gorge') ||
        token.contains('lac') ||
        token.contains('riviere') ||
        token.contains('foret') ||
        token.contains('plage') ||
        token.contains('reserve'));
    final hasCulture = tokens.any((token) =>
        token.contains('culture') ||
        token.contains('musee') ||
        token.contains('galerie') ||
        token.contains('theatre') ||
      token.contains('festival'));
    final hasFood = tokens.any((token) =>
        token.contains('gustative') ||
        token.contains('restaurant') ||
        token.contains('cafe') ||
        token.contains('bar') ||
        token.contains('viticole') ||
        token.contains('gastronom') ||
        token.contains('boulanger'));
    final hasActivities = tokens.any((token) =>
        token.contains('activite') ||
        token.contains('randonnee') ||
        token.contains('escalade') ||
        token.contains('velo') ||
        token.contains('ski') ||
        token.contains('nautique') ||
        token.contains('camping'));

    if (hasHistory) {
      addAll([
        'village de caractere',
        'chateau',
        'monument',
        'ruines',
        'abbaye',
        'site religieux',
        'site historique et archeologique',
        'unesco',
      ]);
    }
    if (hasNature) {
      addAll([
        'cascade',
        'point de vue',
        'lac',
        'riviere',
        'acces riviere',
        'parking',
        'foret',
        'grotte',
        'reserve naturelle',
      ]);
    }
    if (hasCulture) {
      addAll([
        'musee',
        'theatre',
        'galerie',
        'festival',
      ]);
    }
    if (hasFood) {
      addAll([
        'restaurant',
        'cafe',
        'bar',
        'degustation',
        'domaine viticole',
        'boulangerie',
      ]);
    }
    if (hasActivities) {
      addAll([
        'randonnee',
        'escalade',
        'velo',
        'sports nautiques',
        'camping',
      ]);
    }

    if (suggestions.isEmpty) {
      addAll([
        'musee',
        'chateau',
        'cascade',
        'restaurant',
        'randonnee',
        'point de vue',
      ]);
    }

    final orderedDynamic = _dynamicKeywordSuggestions
        .map(_normalizeFilterToken)
        .where((value) => value.isNotEmpty)
        .toList(growable: false);

    final contextTokens = <String>{
      ...tokens,
      ...orderedDynamic,
      ..._selectedKeywords
          .map(_normalizeFilterToken)
          .where((v) => v.isNotEmpty),
    };
    addAll(_relatedKeywordSuggestions(contextTokens));

    final mergedOrdered = <String>[];
    final seen = <String>{};

    for (final value in orderedDynamic) {
      if (seen.add(value)) {
        mergedOrdered.add(value);
      }
    }

    final orderedStatic = suggestions.toList()..sort();
    for (final value in orderedStatic) {
      if (seen.add(value)) {
        mergedOrdered.add(value);
      }
    }

    return mergedOrdered.take(28).toList(growable: false);
  }

  List<String> _relatedKeywordSuggestions(Set<String> contextTokens) {
    const relations = <String, List<String>>{
      'musee': ['exposition', 'art contemporain', 'centre culturel'],
      'galerie': ['art contemporain', 'vernissage', 'exposition'],
      'theatre': ['spectacle', 'opera', 'scene nationale'],
      'festival': ['evenement culturel', 'concert', 'programmation'],
      'village de caractere': [
        'village historique',
        'plus beau village de france',
        'patrimoine',
      ],
      'site religieux': ['eglise', 'abbaye', 'cathedrale', 'basilique'],
      'chateau': ['forteresse', 'citadelle', 'donjon'],
      'monument': [
        'patrimoine',
        'memorial',
        'site historique et archeologique',
      ],
      'abbaye': ['eglise', 'cathedrale', 'cloitre'],
      'ruine': ['vestiges', 'site historique et archeologique', 'fort'],
      'cascade': ['randonnee', 'point de vue', 'gorge'],
      'lac': ['base nautique', 'plage', 'balade'],
      'riviere': ['acces riviere', 'parking', 'baignade'],
      'grotte': ['site naturel', 'visite guidee', 'speleologie'],
      'foret': ['sentier', 'randonnee', 'reserve naturelle'],
      'point de vue': ['belvedere', 'panorama', 'coucher de soleil'],
      'restaurant': ['brasserie', 'bistronomique', 'table locale'],
      'cafe': ['salon de the', 'coffee shop', 'brunch'],
      'bar': ['bar a vins', 'cocktail', 'terrasse'],
      'domaine viticole': ['cave', 'degustation', 'oenotourisme'],
      'randonnee': ['sentier', 'trek', 'bivouac'],
      'velo': ['voie verte', 'piste cyclable', 'vtt'],
      'escalade': ['via ferrata', 'falaise', 'bloc'],
      'camping': ['aire naturelle', 'vanlife', 'camping sauvage'],
      'sports nautiques': ['canoe', 'kayak', 'paddle'],
    };

    final expanded = <String>{};

    for (final token in contextTokens) {
      for (final entry in relations.entries) {
        final key = entry.key;
        if (_tokenEquals(token, key) ||
            token.contains(key) ||
            key.contains(token)) {
          for (final value in entry.value) {
            final normalized = _normalizeFilterToken(value);
            if (_isUsefulKeyword(normalized)) {
              expanded.add(normalized);
            }
          }
        }
      }
    }

    final ordered = expanded.toList()..sort();
    return ordered;
  }

  CountryModel? _countryByCode(String? countryCode) {
    if (countryCode == null || countryCode.isEmpty) return null;
    final normalized = countryCode.toLowerCase();
    final matches = allCountries.where((country) => country.code == normalized);
    return matches.isEmpty ? null : matches.first;
  }

  List<RegionModel> _regionsForCountry(String? countryCode) {
    return _countryByCode(countryCode)?.regions ?? const <RegionModel>[];
  }

  Map<String, List<DepartmentModel>> _departmentsByRegionForCountry(
      String? countryCode) {
    final regions = _regionsForCountry(countryCode);
    return {
      for (final region in regions) region.code: region.departments,
    };
  }

  String _selectedCountryLabel() {
    final country = _countryByCode(_selectedCountryCode);
    return country?.name ?? 'Choisir';
  }

  String _selectedRegionLabel() {
    final regions = _regionsForCountry(_selectedCountryCode);
    final regionCode = _selectedRegionCode;
    if (regionCode == null) {
      return 'Choisir';
    }
    final matches = regions.where((region) => region.code == regionCode);
    if (matches.isEmpty) return 'Choisir';
    return matches.first.name;
  }

  String? _selectedDepartmentLabel() {
    final departmentsByRegion =
        _departmentsByRegionForCountry(_selectedCountryCode);
    final regionCode = _selectedRegionCode;
    final departmentCode = _selectedDepartmentCode;
    if (regionCode == null || departmentCode == null) {
      return null;
    }

    final departments =
        departmentsByRegion[regionCode] ?? const <DepartmentModel>[];
    final matches =
        departments.where((department) => department.code == departmentCode);
    if (matches.isEmpty) {
      return null;
    }

    final selected = matches.first;
    return '${selected.code} • ${selected.name}';
  }

  Future<void> _openGeoPicker() async {
    String? temporaryCountryCode = _selectedCountryCode;
    String? temporaryRegionCode = _selectedRegionCode;
    String? temporaryDepartmentCode = _selectedDepartmentCode;

    final selection = await showModalBottomSheet<_RegionDepartmentSelection>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final colorScheme = Theme.of(context).colorScheme;
            final countries = allCountries;
            final regions = _regionsForCountry(temporaryCountryCode);
            final departmentsByRegion =
                _departmentsByRegionForCountry(temporaryCountryCode);
            final departments = temporaryRegionCode == null
                ? const <DepartmentModel>[]
                : (departmentsByRegion[temporaryRegionCode!] ??
                    const <DepartmentModel>[]);
            final selectedCountry = _countryByCode(temporaryCountryCode);
            final selectedRegion = temporaryRegionCode == null
                ? null
                : regions
                    .where((region) => region.code == temporaryRegionCode)
                    .firstOrNull;

            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.62,
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        children: [
                          if (temporaryDepartmentCode != null)
                            IconButton(
                              onPressed: () {
                                setSheetState(() {
                                  temporaryDepartmentCode = null;
                                });
                              },
                              icon: const Icon(Icons.arrow_back),
                            )
                          else if (temporaryRegionCode != null)
                            IconButton(
                              onPressed: () {
                                setSheetState(() {
                                  temporaryRegionCode = null;
                                  temporaryDepartmentCode = null;
                                });
                              },
                              icon: const Icon(Icons.arrow_back),
                            )
                          else if (temporaryCountryCode != null)
                            IconButton(
                              onPressed: () {
                                setSheetState(() {
                                  temporaryCountryCode = null;
                                  temporaryRegionCode = null;
                                  temporaryDepartmentCode = null;
                                });
                              },
                              icon: const Icon(Icons.arrow_back),
                            )
                          else
                            const SizedBox(width: 48),
                          Expanded(
                            child: Text(
                              temporaryCountryCode == null
                                  ? 'Choisir un pays'
                                  : temporaryRegionCode == null
                                      ? 'Choisir une région'
                                      : 'Choisir un département',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w700,
                                fontSize: 18,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(sheetContext).pop(),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                    if (selectedCountry != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            selectedCountry.name,
                            style: TextStyle(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    if (selectedRegion != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            selectedRegion.name,
                            style: TextStyle(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                        itemCount: temporaryCountryCode == null
                            ? countries.length
                            : temporaryRegionCode == null
                                ? regions.length
                                : departments.length,
                        itemBuilder: (context, index) {
                          if (temporaryCountryCode == null) {
                            final country = countries[index];
                            return ListTile(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              title: Text(country.name),
                              trailing: Icon(
                                Icons.chevron_right,
                                color: colorScheme.primary,
                              ),
                              onTap: () {
                                setSheetState(() {
                                  temporaryCountryCode = country.code;
                                  temporaryRegionCode = null;
                                  temporaryDepartmentCode = null;
                                });
                              },
                            );
                          }

                          if (temporaryRegionCode == null) {
                            final region = regions[index];
                            final isSelected =
                                region.code == temporaryRegionCode;
                            return ListTile(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              title: Text(region.name),
                              trailing: Icon(
                                Icons.chevron_right,
                                color: colorScheme.primary,
                              ),
                              selected: isSelected,
                              onTap: () {
                                setSheetState(() {
                                  temporaryRegionCode = region.code;
                                  temporaryDepartmentCode = null;
                                });
                              },
                            );
                          }

                          final department = departments[index];
                          final isSelected =
                              department.code == temporaryDepartmentCode;
                          return ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            title:
                                Text('${department.code} • ${department.name}'),
                            trailing: isSelected
                                ? Icon(Icons.check_circle,
                                    color: colorScheme.primary)
                                : null,
                            selected: isSelected,
                            onTap: () {
                              Navigator.of(sheetContext).pop(
                                _RegionDepartmentSelection(
                                  countryCode: temporaryCountryCode!,
                                  regionCode: temporaryRegionCode!,
                                  departmentCode: department.code,
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (selection == null) return;

    setState(() {
      _selectedCountryCode = selection.countryCode;
      _selectedRegionCode = selection.regionCode;
      _selectedDepartmentCode = selection.departmentCode;
      _searchPerformed = false;
      _cachedResultsKey = null;
    });

    _resetPage();
  }

  // ignore: unused_element
  Future<void> _openKeywordPicker(Set<String> profileCategories) async {
    final options = _keywordSuggestions(profileCategories);
    final selected = _selectedKeywords.toSet();

    final appliedSelection = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final colorScheme = Theme.of(context).colorScheme;
            final primary = colorScheme.primary;
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.62,
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        children: [
                          const SizedBox(width: 48),
                          Expanded(
                            child: Text(
                              'Choisir des mots-clés',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: primary,
                                fontWeight: FontWeight.w700,
                                fontSize: 18,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(sheetContext).pop(),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final keyword in options)
                              SizedBox(
                                width: 156,
                                child: FilterChip(
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  selected: selected.contains(keyword),
                                  showCheckmark: false,
                                  selectedColor:
                                      primary.withValues(alpha: 0.16),
                                  backgroundColor:
                                      colorScheme.surfaceContainerHighest,
                                  side: BorderSide(
                                    color: selected.contains(keyword)
                                        ? primary.withValues(alpha: 0.55)
                                        : primary.withValues(alpha: 0.22),
                                  ),
                                  label: SizedBox(
                                    width: double.infinity,
                                    child: Text(
                                      _displayKeyword(keyword),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: selected.contains(keyword)
                                            ? primary
                                            : colorScheme.onSurface,
                                        fontWeight: selected.contains(keyword)
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  onSelected: (isSelected) {
                                    setSheetState(() {
                                      if (isSelected) {
                                        selected.add(keyword);
                                      } else {
                                        selected.remove(keyword);
                                      }
                                    });
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: Row(
                        children: [
                          TextButton(
                            style:
                                TextButton.styleFrom(foregroundColor: primary),
                            onPressed: () => Navigator.of(sheetContext).pop(),
                            child: const Text('Annuler'),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            style:
                                TextButton.styleFrom(foregroundColor: primary),
                            onPressed: () =>
                                setSheetState(() => selected.clear()),
                            child: const Text('Vider'),
                          ),
                          const Spacer(),
                          FilledButton(
                            onPressed: () => Navigator.of(sheetContext)
                                .pop(selected.toList(growable: false)),
                            child: const Text('Appliquer'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (appliedSelection == null) return;

    setState(() {
      _selectedKeywords = appliedSelection
          .map(_normalizeFilterToken)
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList(growable: false)
        ..sort();
      _keywordQuery = _selectedKeywords.join(' ');
      _cachedResultsKey = null;
      _searchPerformed = false;
    });

    _resetPage();
  }

  bool _isUsefulKeyword(String value) {
    if (value.isEmpty || value.length < 3) return false;
    if (_stopWords.contains(value)) return false;
    if (value == 'other' || value == 'autre' || value == 'poi') return false;
    if (value.contains('point d interet') || value.contains('sans nom')) {
      return false;
    }
    return true;
  }

  List<String> _extractDynamicKeywordsFromPois({
    required List<Poi> allPois,
    required Set<String> normalizedSelectedCategories,
    required Position? userPos,
  }) {
    final frequency = <String, double>{};

    for (final poi in allPois) {
      if (!_matchesCategoryFilterWithNormalized(
        poi,
        normalizedSelectedCategories,
      )) {
        continue;
      }

      if (_nearbyOnly) {
        if (userPos == null) continue;
        final distance = _distanceMeters(userPos, poi);
        if (distance > _nearbyMaxDistanceMeters) continue;
      }

      final candidateKeywords = <String>{
        _normalizeFilterToken(formatPoiSubCategory(poi.subCategory)),
        _normalizeFilterToken(poi.subCategory ?? ''),
        ..._meaningfulTokens(poi.displayName),
        ..._meaningfulTokens(poi.name),
        ..._meaningfulTokens(poi.shortDescription),
      };

      for (final keyword in candidateKeywords) {
        if (!_isUsefulKeyword(keyword)) continue;
        var weight = 1.0;
        if (_selectedKeywords
            .any((selected) => _tokenEquals(selected, keyword))) {
          weight += 1.1;
        }
        if (_nearbyOnly && userPos != null) {
          final distance = _distanceMeters(userPos, poi);
          if (distance <= 5000) {
            weight += 0.4;
          }
        }
        frequency.update(keyword, (value) => value + weight,
            ifAbsent: () => weight);
      }
    }

    final entries = frequency.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) return byCount;
        return a.key.compareTo(b.key);
      });

    return entries.take(12).map((entry) => entry.key).toList(growable: false);
  }

  bool _isGenericSpot(Poi poi) {
    final normalizedName = _normalizeFilterToken(poi.name);
    final normalizedDisplayName = _normalizeFilterToken(poi.displayName);
    final normalizedSubCategory =
        _normalizeFilterToken(formatPoiSubCategory(poi.subCategory));
    final normalizedRawSubCategory =
        _normalizeFilterToken(poi.subCategory ?? '');

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

  Set<String> _normalizedSelectedCategories(Set<String> selectedCategories) {
    if (selectedCategories.isEmpty) {
      _cachedNormalizedSelectedCategories = const <String>{};
      _cachedNormalizedSelectedCategoriesKey = '';
      return _cachedNormalizedSelectedCategories!;
    }

    final sorted = selectedCategories.toList(growable: false)..sort();
    final key = sorted.join('|');
    if (_cachedNormalizedSelectedCategoriesKey == key &&
        _cachedNormalizedSelectedCategories != null) {
      return _cachedNormalizedSelectedCategories!;
    }

    final normalized = selectedCategories
        .map(_normalizeFilterToken)
        .where((value) => value.isNotEmpty)
        .toSet();

    _cachedNormalizedSelectedCategories = normalized;
    _cachedNormalizedSelectedCategoriesKey = key;
    return normalized;
  }

  bool _matchesCategoryFilterWithNormalized(Poi poi, Set<String> wanted) {
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
            .where((t) => t.length >= 3 && !_stopWords.contains(t))
            .toSet();
        final interestTokens = interest
            .split(' ')
            .where((t) => t.isNotEmpty)
            .map(_canonicalToken)
            .where((t) => t.length >= 3 && !_stopWords.contains(t))
            .toSet();
        if (candidateTokens.isEmpty || interestTokens.isEmpty) {
          return false;
        }
        return candidateTokens.any(interestTokens.contains);
      });
    });

    if (matchesByText) return true;

    return _isWholeGroupSelected(poi.category, wanted);
  }

  bool _isWholeGroupSelected(PoiCategory category, Set<String> wanted) {
    final groupTitle = _groupTitleForCategory(category);
    final group =
        poiCategoryGroups.where((g) => g.title == groupTitle).firstOrNull;
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
        return {
          'patrimoine',
          'histoire',
          'village de caractere',
          'village historique',
          'plus beau village de france',
          'plus beaux villages de france',
          'monument',
          'chateau',
          'ruine',
          'site religieux',
          'religieux',
          'site historique et archeologique',
          'site historique',
          'site archeologique',
          'eglise',
          'abbaye',
          'fort',
          'citadelle',
          'unesco',
          'village',
          'memorial',
        };
      case PoiCategory.nature:
        return {
          'nature',
          'cascade',
          'gorge',
          'belvedere',
          'site naturel',
          'parc naturel',
          'lac',
          'riviere',
          'foret',
          'plage',
          'point de vue',
          'reserve',
          'grotte',
        };
      case PoiCategory.culture:
        return {
          'culture',
          'musee',
          'opera',
          'exposition',
          'festival',
          'theatre',
          'bibliotheque',
          'galerie',
          'marche',
        };
      case PoiCategory.experienceGustative:
        return {
          'gustative',
          'restaurant',
          'degustation',
          'viticole',
          'brasserie',
          'cafe',
          'bar',
          'pub',
          'boulangerie',
          'gastronomie',
          'distillerie',
        };
      case PoiCategory.activites:
        return {
          'activites',
          'randonnee',
          'sport',
          'familiale',
          'plein air',
          'escalade',
          'velo',
          'ski',
          'nautique',
          'camping',
          'loisirs',
        };
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
    if (_pageNotifier.value != 0) {
      _pageNotifier.value = 0;
    }
    if (_pageController.hasClients) {
      _pageController.jumpToPage(0);
    }
  }

  String _buildResultsCacheKey({
    required int docsIdentity,
    required int docsLength,
    required Set<String> profileCategories,
    required Position? userPos,
  }) {
    final sortedCategories = profileCategories.toList()..sort();
    final userKey = userPos == null
        ? 'null'
        : '${userPos.latitude.toStringAsFixed(4)},${userPos.longitude.toStringAsFixed(4)}';

    return [
      docsIdentity,
      docsLength,
      _selectedRegionCode ?? 'null',
      _selectedDepartmentCode ?? 'null',
      _nearbyOnly,
      userKey,
      sortedCategories.join('|'),
    ].join('::');
  }

  Set<String> _meaningfulTokens(String value) {
    return _normalizeFilterToken(value)
        .split(' ')
        .where((token) => token.length >= 3)
        .map(_canonicalToken)
        .where((token) => token.length >= 3 && !_stopWords.contains(token))
        .toSet();
  }

  String _searchableText(Poi poi) {
    return [
      poi.displayName,
      poi.name,
      poi.shortDescription,
      poi.category.label,
      formatPoiSubCategory(poi.subCategory),
      poi.subCategory ?? '',
      poi.departmentCode ?? '',
    ].join(' ');
  }

  int _keywordScore({
    required Poi poi,
    required String normalizedQuery,
    required Position? userPos,
  }) {
    if (normalizedQuery.isEmpty) {
      return 0;
    }

    final displayName = _normalizeFilterToken(poi.displayName);
    final searchable = _normalizeFilterToken(_searchableText(poi));
    final queryTokens = _meaningfulTokens(normalizedQuery);
    final searchableTokens = _meaningfulTokens(searchable);

    int score = 0;

    if (displayName == normalizedQuery) {
      score += 100;
    } else if (displayName.startsWith(normalizedQuery)) {
      score += 70;
    } else if (displayName.contains(normalizedQuery)) {
      score += 50;
    }

    if (searchable.contains(normalizedQuery)) {
      score += 25;
    }

    if (queryTokens.isNotEmpty && searchableTokens.isNotEmpty) {
      final overlap = queryTokens.where(searchableTokens.contains).length;
      score += overlap * 12;

      if (overlap == queryTokens.length) {
        score += 20;
      }
    }

    if (userPos != null) {
      final distance = _distanceMeters(userPos, poi);
      if (distance <= 2000) {
        score += 12;
      } else if (distance <= 7000) {
        score += 8;
      } else if (distance <= 15000) {
        score += 4;
      }
    }

    if (poi.googleRating != null) {
      score += poi.googleRating!.round();
    }

    return score;
  }

  // ignore: unused_element
  bool _matchesKeywordFilter(Poi poi) {
    final normalizedQuery = _normalizeFilterToken(_keywordQuery);
    if (normalizedQuery.isEmpty) {
      return true;
    }

    final searchable = _normalizeFilterToken(_searchableText(poi));
    if (searchable.contains(normalizedQuery)) {
      return true;
    }

    final queryTokens = _meaningfulTokens(normalizedQuery);
    final searchableTokens = _meaningfulTokens(searchable);
    if (queryTokens.isEmpty || searchableTokens.isEmpty) {
      return false;
    }

    final overlap = queryTokens.where(searchableTokens.contains).length;
    return overlap >= (queryTokens.length >= 3 ? 2 : 1);
  }

  // ignore: unused_element
  List<Poi> _sortByRelevance(List<Poi> pois, Position? userPos) {
    final normalizedQuery = _normalizeFilterToken(_keywordQuery);
    if (normalizedQuery.isEmpty) {
      return _sortedByDistance(pois, userPos);
    }

    final sorted = [...pois];
    sorted.sort((a, b) {
      final scoreA = _keywordScore(
        poi: a,
        normalizedQuery: normalizedQuery,
        userPos: userPos,
      );
      final scoreB = _keywordScore(
        poi: b,
        normalizedQuery: normalizedQuery,
        userPos: userPos,
      );
      if (scoreA != scoreB) {
        return scoreB.compareTo(scoreA);
      }

      final updatedCompare = b.updatedAt.compareTo(a.updatedAt);
      if (updatedCompare != 0) {
        return updatedCompare;
      }

      final da =
          userPos == null ? double.infinity : _distanceMeters(userPos, a);
      final db =
          userPos == null ? double.infinity : _distanceMeters(userPos, b);
      return da.compareTo(db);
    });

    return sorted;
  }

  List<Poi> _computeFilteredResults({
    required List<Poi> allPois,
    required Position? userPos,
    required Set<String> normalizedSelectedCategories,
  }) {
    final geoFiltered = allPois.where((poi) {
      if (_nearbyOnly) {
        if (userPos == null) return false;
        final distance = _distanceMeters(userPos, poi);
        return distance <= _nearbyMaxDistanceMeters;
      }
      return true;
    }).toList(growable: false);

    final categoryFiltered = geoFiltered
        .where(
          (poi) => _matchesCategoryFilterWithNormalized(
              poi, normalizedSelectedCategories),
        )
        .toList(growable: false);

    return _sortedByDistance(categoryFiltered, userPos);
  }

  Widget _buildPageListWithAllSpotsRatings({
    required BuildContext context,
    required int pageIndex,
    required List<Poi> pageResults,
    required List<_SearchListItem> items,
    required Position? userPos,
  }) {
    final poiIds =
        pageResults.map((poi) => poi.id).toSet().toList(growable: false);

    if (poiIds.isEmpty) {
      return _buildSearchItemsList(
        context: context,
        pageIndex: pageIndex,
        items: items,
        userPos: userPos,
        allSpotsRatingsByPoiId: const <String, double>{},
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('poi_ratings')
          .where('poiId', whereIn: poiIds)
          .snapshots(),
      builder: (context, snapshot) {
        final allSpotsRatingsByPoiId = _extractAllSpotsRatingsByPoi(
          snapshot.data?.docs,
        );

        return _buildSearchItemsList(
          context: context,
          pageIndex: pageIndex,
          items: items,
          userPos: userPos,
          allSpotsRatingsByPoiId: allSpotsRatingsByPoiId,
        );
      },
    );
  }

  Widget _buildSearchItemsList({
    required BuildContext context,
    required int pageIndex,
    required List<_SearchListItem> items,
    required Position? userPos,
    required Map<String, double> allSpotsRatingsByPoiId,
  }) {
    final favoritePoiIds =
        ref.watch(profileStreamProvider).value?.favoritePoiIds ??
            const <String>[];
    final favoritePoiIdSet = favoritePoiIds.toSet();

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
            final poi = item.poi!;
            final allSpotsRating = allSpotsRatingsByPoiId[poi.id] ?? 0;
            return _buildPoiCard(
              context,
              poi,
              userPos,
              allSpotsRating: allSpotsRating,
              isFavorite: favoritePoiIdSet.contains(poi.id),
              isFavoriteLoading: _favoriteToggleInFlight.contains(poi.id),
            );
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
  }

  Map<String, double> _extractAllSpotsRatingsByPoi(
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? docs,
  ) {
    if (docs == null || docs.isEmpty) {
      return const <String, double>{};
    }

    final sums = <String, double>{};
    final counts = <String, int>{};

    for (final doc in docs) {
      final data = doc.data();
      final poiId = (data['poiId'] as String?)?.trim();
      if (poiId == null || poiId.isEmpty) continue;

      final isGoogleRating = data['isGoogleRating'] == true;
      if (isGoogleRating) continue;

      final rating = (data['rating'] as num?)?.toDouble();
      if (rating == null) continue;

      sums.update(poiId, (value) => value + rating, ifAbsent: () => rating);
      counts.update(poiId, (value) => value + 1, ifAbsent: () => 1);
    }

    final averages = <String, double>{};
    for (final entry in sums.entries) {
      final count = counts[entry.key] ?? 0;
      if (count <= 0) continue;
      averages[entry.key] = entry.value / count;
    }

    return averages;
  }

  String _distanceLabel(Position? pos, Poi poi) {
    if (pos == null) return '-';
    final key = _poiDistanceKey(poi);
    final cached = _cachedDistanceLabelByPoiKey[key];
    if (cached != null) return cached;

    final meters = _distanceMeters(pos, poi);
    final km = meters / 1000;
    final label = '${km.toStringAsFixed(1)} km';
    _cachedDistanceLabelByPoiKey[key] = label;
    return label;
  }

  Widget _buildPoiCard(
    BuildContext context,
    Poi poi,
    Position? userPos, {
    required double allSpotsRating,
    required bool isFavorite,
    required bool isFavoriteLoading,
  }) {
    final distanceLabel = _distanceLabel(userPos, poi);
    final isFirestore = poi.source == 'firestore';
    final rating = poi.googleRating;
    final photoCount = poi.imageUrls.length;
    final subCategoryLabel = formatPoiSubCategory(poi.subCategory);
    final categoryLabel =
        subCategoryLabel.isNotEmpty ? subCategoryLabel : poi.category.label;
    final lockUntil = _favoriteTapLockUntilByPoiId[poi.id];
    final isTapLocked =
        lockUntil != null && DateTime.now().isBefore(lockUntil);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const rightActionZoneWidth = 96.0;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) {
              if (isTapLocked || isFavoriteLoading) {
                return;
              }
              // Ignore taps on the right-side actions area (favorite + distance).
              if (details.localPosition.dx >=
                  constraints.maxWidth - rightActionZoneWidth) {
                return;
              }
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
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapDown: (_) => _armFavoriteTapLock(poi.id),
                            onTap: isFavoriteLoading
                                ? null
                                : () => _toggleFavoriteFromSearchCard(
                                      context,
                                      poi,
                                      isFavorite,
                                    ),
                            child: Tooltip(
                              message: isFavorite
                                  ? 'Retirer des favoris'
                                  : 'Ajouter aux favoris',
                              child: SizedBox(
                                width: 36,
                                height: 36,
                                child: Center(
                                  child: isFavoriteLoading
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        )
                                      : Icon(
                                          isFavorite
                                              ? Icons.favorite
                                              : Icons.favorite_border,
                                          color: isFavorite
                                              ? Colors.red
                                              : Colors.grey,
                                          size: 20,
                                        ),
                                ),
                              ),
                            ),
                          ),
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
                                const Icon(Icons.star,
                                    size: 12, color: Colors.amber),
                                const SizedBox(width: 2),
                                Text(
                                  rating.toStringAsFixed(1),
                                  style:
                                      TextStyle(fontSize: context.fontSize(11)),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(
                        Icons.star,
                        size: 14,
                        color: Colors.amber,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Note AllSPOTS: ${allSpotsRating.toStringAsFixed(1)}/5',
                        style: TextStyle(
                          fontSize: context.fontSize(12),
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
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
          );
        },
      ),
    );
  }

  Future<void> _toggleFavoriteFromSearchCard(
    BuildContext context,
    Poi poi,
    bool isFavorite,
  ) async {
    if (_favoriteToggleInFlight.contains(poi.id)) return;

    final user = ref.read(authStateProvider).value;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connectez-vous pour gérer vos favoris.')),
      );
      return;
    }

    // Keep lock active while async update starts/completes.
    _armFavoriteTapLock(poi.id);

    setState(() {
      _favoriteToggleInFlight.add(poi.id);
    });

    try {
      final profileRef =
          FirebaseFirestore.instance.collection('profiles').doc(user.uid);

      if (isFavorite) {
        await profileRef.update({
          'favoritePoiIds': FieldValue.arrayRemove([poi.id]),
        });
        await profileRef.collection('favoritePois').doc(poi.id).delete();
      } else {
        await profileRef.update({
          'favoritePoiIds': FieldValue.arrayUnion([poi.id]),
        });
        await profileRef.collection('favoritePois').doc(poi.id).set({
          'name': poi.displayName,
          'imageUrls': poi.imageUrls,
          'googleRating': poi.googleRating,
          'googleRatingCount': poi.googleRatingCount,
          'description': poi.shortDescription,
          'lat': poi.lat,
          'lng': poi.lng,
          'category': poi.category.name,
          'subCategory': poi.subCategory,
          'source': poi.source,
          'updatedAt': Timestamp.now(),
        });
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Impossible de mettre a jour les favoris.')),
        );
      }
      debugPrint('Erreur toggle favori depuis recherche: $e');
    } finally {
      if (mounted) {
        setState(() {
          _favoriteToggleInFlight.remove(poi.id);
        });
      }
    }
  }

  void _armFavoriteTapLock(String poiId) {
    _favoriteTapLockUntilByPoiId[poiId] =
        DateTime.now().add(const Duration(milliseconds: 1200));
  }
}

class _RegionDepartmentSelection {
  final String countryCode;
  final String regionCode;
  final String departmentCode;

  const _RegionDepartmentSelection({
    required this.countryCode,
    required this.regionCode,
    required this.departmentCode,
  });
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
