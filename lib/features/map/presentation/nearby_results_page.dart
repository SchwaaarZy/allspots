import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import '../../auth/data/auth_providers.dart';
import '../../profile/data/road_trip_service.dart';
import '../../../core/utils/geo_utils.dart';
import '../../../core/utils/responsive_utils.dart';
import '../../../core/widgets/radius_selector.dart';
import '../domain/poi.dart';
import '../domain/poi_category.dart';
import 'map_controller.dart';
import 'poi_detail_page.dart';

enum NearbySelectionMode {
  browse,
  roadTrip,
}

final roadTripItemsProvider = StreamProvider.family<List<RoadTripItem>, String>(
  (ref, uid) => RoadTripService.itemsStream(uid),
);

class NearbyResultsPage extends ConsumerStatefulWidget {
  const NearbyResultsPage({
    super.key,
    this.selectionMode = NearbySelectionMode.browse,
  });

  final NearbySelectionMode selectionMode;

  @override
  ConsumerState<NearbyResultsPage> createState() => _NearbyResultsPageState();
}

class _NearbyResultsPageState extends ConsumerState<NearbyResultsPage> {
  late PageController _pageController;
  final int _itemsPerPage = 10;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = ref.read(mapControllerProvider);
      if (state.userPosition == null || state.displayedPois.isEmpty) {
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
    final userPos =
        ref.watch(mapControllerProvider.select((state) => state.userPosition));
    final sortedPois = ref.watch(
      mapControllerProvider.select((state) => state.displayedPois),
    );
    final radiusMeters =
        ref.watch(mapControllerProvider.select((state) => state.radiusMeters));
    final user = FirebaseAuth.instance.currentUser;

    final roadTripItems =
        widget.selectionMode == NearbySelectionMode.roadTrip && user != null
            ? (ref.watch(roadTripItemsProvider(user.uid)).value ??
                const <RoadTripItem>[])
            : const <RoadTripItem>[];
    final selectedSpotKeys =
        roadTripItems.map((item) => _spotKey(item.id, item.source)).toSet();

    // Calcul de la pagination
    final totalItems = sortedPois.length;
    final totalPages = (totalItems / _itemsPerPage).ceil();
    final safePage =
        totalPages == 0 ? 0 : _currentPage.clamp(0, totalPages - 1);
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
      body: SafeArea(
        top: true,
        bottom: false,
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverAppBar(
              expandedHeight: 188,
              floating: false,
              pinned: false,
              automaticallyImplyLeading: false,
              toolbarHeight: 0,
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
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: context.fontSize(13),
                            ),
                          ),
                          if (widget.selectionMode ==
                              NearbySelectionMode.roadTrip)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Mode Road Trip',
                                style: TextStyle(
                                  fontSize: context.fontSize(11),
                                  color: Colors.blue.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            )
                          else if (totalItems > 0)
                            Text(
                              'Page ${safePage + 1}/$totalPages',
                              style: TextStyle(
                                fontSize: context.fontSize(11),
                                color: Colors.grey,
                              ),
                            ),
                        ],
                      ),
                      if (widget.selectionMode == NearbySelectionMode.roadTrip)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Touchez un spot pour l\'ajouter ou le retirer du road trip.',
                            style: TextStyle(
                              fontSize: context.fontSize(11),
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                      const SizedBox(height: 6),

                      RadiusSelector(
                        compact: true,
                        currentRadius: radiusMeters,
                        radiusOptions: const [5000, 10000, 15000, 20000],
                        onRadiusChanged: (radius) async {
                          if (_pageController.hasClients) {
                            _pageController.jumpToPage(0);
                          }
                          setState(() => _currentPage = 0);
                          await ref
                              .read(mapControllerProvider.notifier)
                              .updateRadius(radius);
                        },
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Rayon actif: ${(radiusMeters / 1000).toStringAsFixed(0)} km',
                        style: TextStyle(
                          fontSize: context.fontSize(11),
                          color: Colors.grey.shade600,
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
                              final isSelected = selectedSpotKeys.contains(
                                _spotKey(poi.id, poi.source),
                              );
                              return _buildPoiCard(
                                context,
                                poi,
                                userPos,
                                isSelected: isSelected,
                                onSelectToggle: () => _toggleRoadTripSelection(
                                  poi,
                                  isSelected: isSelected,
                                  currentItems: roadTripItems,
                                ),
                              );
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
              if (widget.selectionMode == NearbySelectionMode.roadTrip)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      top: BorderSide(color: Colors.grey.shade200),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${roadTripItems.length} spot(s) sélectionné(s)',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: context.fontSize(12),
                            ),
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: () => Navigator.maybePop(context),
                          icon: const Icon(Icons.check),
                          label: const Text('Terminer'),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _spotKey(String id, String source) => '$source::$id';

  Future<void> _toggleRoadTripSelection(
    Poi poi, {
    required bool isSelected,
    required List<RoadTripItem> currentItems,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connectez-vous pour creer un road trip.'),
        ),
      );
      return;
    }

    final hasPremiumPass =
        ref.read(profileStreamProvider).value?.hasPremiumPass ?? false;
    final maxItems = RoadTripService.maxItemsFor(hasPremiumPass);
    final maxTrips = RoadTripService.maxTripsFor(hasPremiumPass);
    final items = [...currentItems];
    final index = items.indexWhere(
      (item) => item.id == poi.id && item.source == poi.source,
    );

    if (index >= 0 || isSelected) {
      if (index < 0) return;
      items.removeAt(index);
      await RoadTripService.saveItems(user.uid, items);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Retire du road trip')),
      );
      return;
    }

    final result = await RoadTripService.addPoi(
      user.uid,
      poi,
      maxItems: maxItems,
      maxTrips: maxTrips,
    );
    if (!mounted) return;

    switch (result) {
      case RoadTripAddResult.added:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Ajoute au road trip')),
        );
        break;
      case RoadTripAddResult.alreadyExists:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Deja dans le road trip')),
        );
        break;
      case RoadTripAddResult.maxReached:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Limite de $maxItems spots atteinte')),
        );
        break;
      case RoadTripAddResult.maxTripsReached:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Limite de $maxTrips road trips atteinte')),
        );
        break;
    }
  }

  Widget _buildPoiCard(
    BuildContext context,
    Poi poi,
    Position? userPos, {
    required bool isSelected,
    required VoidCallback onSelectToggle,
  }) {
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
        onTap: widget.selectionMode == NearbySelectionMode.roadTrip
            ? onSelectToggle
            : () {
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
                            const Icon(Icons.star,
                                size: 12, color: Colors.amber),
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
              // Description courte
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
              if (widget.selectionMode == NearbySelectionMode.roadTrip) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: onSelectToggle,
                        icon: Icon(
                          isSelected
                              ? Icons.check_circle
                              : Icons.add_circle_outline,
                        ),
                        label: Text(
                          isSelected ? 'Sélectionné - retirer' : 'Sélectionner',
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              isSelected ? Colors.green.shade600 : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () {
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
                      child: const Text('Détails'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
