import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/utils/geo_utils.dart';
import '../domain/poi.dart';
import '../domain/poi_category.dart';
import 'map_controller.dart';
import 'poi_detail_page.dart';

class NearbyResultsPage extends ConsumerStatefulWidget {
  const NearbyResultsPage({super.key});

  @override
  ConsumerState<NearbyResultsPage> createState() => _NearbyResultsPageState();
}

class _NearbyResultsPageState extends ConsumerState<NearbyResultsPage> {
  late PageController _pageController;
  final int _itemsPerPage = 10;
  int _currentPage = 0;
  String _sortBy = 'distance'; // 'distance', 'interest', 'category'

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    // Initialize map controller if needed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(mapControllerProvider.notifier).init();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mapState = ref.watch(mapControllerProvider);
    final userPos = mapState.userPosition;
    final allPois = mapState.nearbyPois;

    // Trier selon le critère sélectionné
    final sortedPois = _sortPois(allPois, userPos);

    // Calcul de la pagination
    final totalItems = sortedPois.length;
    final totalPages = (totalItems / _itemsPerPage).ceil();
    final safePage = totalPages == 0
        ? 0
        : _currentPage.clamp(0, totalPages - 1);
    if (safePage != _currentPage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() => _currentPage = safePage);
        if (_pageController.hasClients) {
          _pageController.jumpToPage(safePage);
        }
      });
    }
    final startIndex = safePage * _itemsPerPage;
    final endIndex = (startIndex + _itemsPerPage).clamp(0, totalItems);

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            expandedHeight: 110,
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
                    // Résumé
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total: $totalItems spot(s)',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        if (totalItems > 0)
                          Text(
                            'Page ${safePage + 1}/$totalPages',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Tri
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildSortButton('distance', '📍 Distance'),
                          const SizedBox(width: 6),
                          _buildSortButton('interest', '⭐ Intérêt'),
                          const SizedBox(width: 6),
                          _buildSortButton('category', '🏷️ Catégorie'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        body: Column(
          children: [
            // Liste des résultats avec pagination
            Expanded(
              child: totalItems == 0
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.location_off,
                            size: 48,
                            color: Colors.grey.shade300,
                          ),
                          const SizedBox(height: 16),
                          const Text('Aucun spot trouvé à proximité'),
                        ],
                      ),
                    )
                  : PageView.builder(
                      controller: _pageController,
                      onPageChanged: (page) {
                        setState(() => _currentPage = page);
                      },
                      itemCount: totalPages,
                      itemBuilder: (context, pageIndex) {
                        final pageStart = pageIndex * _itemsPerPage;
                        final pageEnd =
                            (pageStart + _itemsPerPage).clamp(0, totalItems);
                        final pagePois = sortedPois.sublist(
                          pageStart,
                          pageEnd.clamp(0, totalItems),
                        );
                        return ListView.builder(
                          key: PageStorageKey('nearby_page_$pageIndex'),
                          padding: const EdgeInsets.all(8),
                          itemCount: pagePois.length,
                          itemBuilder: (context, index) {
                            final poi = pagePois[index];
                            return _buildPoiCard(context, poi, userPos);
                          },
                        );
                      },
                    ),
            ),

            // Contrôles de pagination
            if (totalItems > _itemsPerPage)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _currentPage > 0
                          ? () => _pageController.previousPage(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeOut,
                              )
                          : null,
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Précédent'),
                    ),
                    Text(
                      '${startIndex + 1} - $endIndex sur $totalItems',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    ElevatedButton.icon(
                      onPressed: _currentPage < totalPages - 1
                          ? () => _pageController.nextPage(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeOut,
                              )
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

  Widget _buildSortButton(String value, String label) {
    final isSelected = _sortBy == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _sortBy = value;
          _currentPage = 0; // Reset to first page when changing sort
        });
        if (_pageController.hasClients) {
          _pageController.jumpToPage(0);
        }
      },
      backgroundColor: isSelected ? Colors.blue.shade100 : Colors.grey.shade100,
      selectedColor: Colors.blue.shade200,
    );
  }

  Widget _buildPoiCard(BuildContext context, Poi poi, Position? userPos) {
    final distance = userPos != null
        ? GeoUtils.distanceMeters(
            lat1: userPos.latitude,
            lon1: userPos.longitude,
            lat2: poi.lat,
            lon2: poi.lng,
          )
        : 0.0;
    final distanceLabel = distance > 1000
        ? '${(distance / 1000).toStringAsFixed(1)} km'
        : '${distance.toStringAsFixed(0)} m';

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
              // En-tête avec nom et distance
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
              // Description courte
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
              // Indicateurs
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

  List<Poi> _sortPois(List<Poi> pois, Position? userPos) {
    final list = [...pois];

    if (_sortBy == 'distance') {
      // Trier par distance
      if (userPos != null) {
        list.sort((a, b) {
          final da = GeoUtils.distanceMeters(
            lat1: userPos.latitude,
            lon1: userPos.longitude,
            lat2: a.lat,
            lon2: a.lng,
          );
          final db = GeoUtils.distanceMeters(
            lat1: userPos.latitude,
            lon1: userPos.longitude,
            lat2: b.lat,
            lon2: b.lng,
          );
          return da.compareTo(db);
        });
      }
    } else if (_sortBy == 'interest') {
      // Trier par intérêt (rating descendant, puis nombre de photos)
      list.sort((a, b) {
        // D'abord: rating (descendant)
        final ratingA = a.googleRating ?? 0;
        final ratingB = b.googleRating ?? 0;
        final ratingCompare = ratingB.compareTo(ratingA);
        if (ratingCompare != 0) return ratingCompare;

        // Ensuite: nombre de photos (descendant)
        return b.imageUrls.length.compareTo(a.imageUrls.length);
      });
    } else if (_sortBy == 'category') {
      // Trier par catégorie (groupes en priorité), puis par intérêt
      list.sort((a, b) {
        // D'abord: groupes de catégorie
        final categoryCompare = (a.category.label).compareTo(b.category.label);
        if (categoryCompare != 0) return categoryCompare;

        // Ensuite: rating (descendant)
        final ratingA = a.googleRating ?? 0;
        final ratingB = b.googleRating ?? 0;
        return ratingB.compareTo(ratingA);
      });
    }

    return list;
  }
}
