import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/constants/poi_categories.dart';
import '../../../core/utils/geo_utils.dart';
import '../../../core/widgets/radius_selector.dart';
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
  Set<String> _selectedCategories = {};
  bool _initialized = false;
  final int _itemsPerPage = 10;
  int _currentPage = 0;
  bool _searchPerformed = false;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
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
    // N'auto-charger les catégories que si elle est vide
    final profile = ref.watch(profileStreamProvider);

    final mapState = ref.watch(mapControllerProvider);
    final userPos = mapState.userPosition;
    final rawPois = mapState.nearbyPois;
    final results = _sortedByDistance(rawPois, userPos);
    final totalItems = results.length;
    final totalPages = (totalItems / _itemsPerPage).ceil();
    final pageIndex = totalPages == 0
      ? 0
      : _currentPage.clamp(0, totalPages - 1);
    final startIndex = pageIndex * _itemsPerPage;
    final endIndex = (startIndex + _itemsPerPage).clamp(0, totalItems);

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            expandedHeight: 280,
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
                    // Bouton Catégories
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _showCategoriesDialog(context),
                        icon: const Icon(Icons.category, size: 16),
                        label: const Text('Catégories'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Rayon ajustable - Remplacé par RadiusSelector
                    RadiusSelector(
                      currentRadius: mapState.radiusMeters,
                      radiusOptions: const [5000, 10000, 15000, 20000, 25000, 30000],
                      onRadiusChanged: (radius) {
                        _resetPage();
                        ref.read(mapControllerProvider.notifier).setRadiusMeters(radius);
                      },
                    ),
                    const SizedBox(height: 8),
                    // Boutons d'action
                    Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  if (profile.hasValue && profile.value != null) {
                                    setState(() {
                                      _selectedCategories = profile.value!.categories.toSet();
                                      _currentPage = 0;
                                      _searchPerformed = true;
                                      _pageController.jumpToPage(0);
                                    });
                                    ref
                                        .read(mapControllerProvider.notifier)
                                        .applyCategoryPreferences(_selectedCategories.toList());
                                    ref.read(mapControllerProvider.notifier).refreshNearby();
                                  }
                                },
                                icon: const Icon(Icons.favorite, size: 16),
                                label: const Text('Intérêt'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red.shade400,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _selectedCategories.clear();
                                    _currentPage = 0;
                                    _searchPerformed = false;
                                    _pageController.jumpToPage(0);
                                  });
                                  ref
                                      .read(mapControllerProvider.notifier)
                                      .applyCategoryPreferences(const []);
                                  ref
                                      .read(mapControllerProvider.notifier)
                                      .setRadiusMeters(5000);
                                  ref
                                      .read(mapControllerProvider.notifier)
                                      .setOpenNow(false);
                                },
                                icon: const Icon(Icons.refresh, size: 16),
                                label: const Text('Réinitialiser'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              setState(() => _searchPerformed = true);
                              _resetPage();
                              _pageController.jumpToPage(0);
                              ref.read(mapControllerProvider.notifier).refreshNearby();
                            },
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
        body: Column(
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
                  final pageFirestore = pageResults.where((poi) => poi.source == 'firestore').toList();
                  final pagePlaces = pageResults.where((poi) => poi.source == 'places').toList();

                  if (userPos == null && pageIndex == 0) {
                    return const Center(
                      child: Text(
                        '📍 Localisation indisponible.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    );
                  }

                  if (!mapState.isLoading && results.isEmpty && pageIndex == 0) {
                    if (!_searchPerformed) {
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
                              const Text(
                                'Commencez votre recherche',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 24),
                                child: Text(
                                  '1. Sélectionnez des catégories ou cliquez sur "Intérêt"\n2. Ajustez le rayon de recherche\n3. Cliquez sur "Rechercher"',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    return const Center(
                      child: Text(
                        '🔍 Aucun spot trouvé pour ces filtres.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    );
                  }

                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (mapState.isLoading && pageIndex == 0)
                          const LinearProgressIndicator(),
                        if (pageFirestore.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              '🏘️ Spots communautaires (${pageFirestore.length})',
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ),
                          for (final poi in pageFirestore)
                            _buildPoiCard(context, poi, userPos),
                          const SizedBox(height: 8),
                        ],
                        if (pagePlaces.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              '🗺️ Spots (${pagePlaces.length})',
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ),
                          for (final poi in pagePlaces)
                            _buildPoiCard(context, poi, userPos),
                        ],
                        if (pageIndex == totalPages - 1) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => context.push('/spots/new'),
                              icon: const Icon(Icons.add_location_alt),
                              label: const Text('➕ Ajouter un spot'),
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                      ],
                    ),
                  );
                },
              ),
            ),
            // Indicateur et boutons de pagination
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
                                poi.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
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
                              poi.category.icon,
                              size: 14,
                              color: poi.category.color,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              categoryLabel,
                              style: TextStyle(
                                fontSize: 12,
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
                              style: const TextStyle(fontSize: 11),
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
                  fontSize: 12,
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
                        fontSize: 12,
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
                      style: const TextStyle(
                        fontSize: 12,
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

  void _showCategoriesDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sélectionner les catégories', textAlign: TextAlign.center),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final group in poiCategoryGroups) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Text(
                      group.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: Colors.blue,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: Column(
                      children: [
                        for (final item in group.items)
                          CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              item,
                              style: const TextStyle(fontSize: 12),
                            ),
                            value: _selectedCategories.contains(item),
                            onChanged: (selected) {
                              setState(() {
                                if (selected == true) {
                                  _selectedCategories.add(item);
                                } else {
                                  _selectedCategories.remove(item);
                                }
                              });
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              setState(() {
                _currentPage = 0;
                _searchPerformed = true;
                _pageController.jumpToPage(0);
              });
              ref
                  .read(mapControllerProvider.notifier)
                  .applyCategoryPreferences(_selectedCategories.toList());
              _resetPage();
              _pageController.jumpToPage(0);
              ref.read(mapControllerProvider.notifier).refreshNearby();
            },
            child: const Text('Rechercher'),
          ),
        ],
      ),
    );
  }
}
