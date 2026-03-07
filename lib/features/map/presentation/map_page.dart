import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_map/flutter_map.dart' as flutter_map;
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/constants/poi_categories.dart';
import '../../../core/utils/responsive_utils.dart';
import '../../../core/widgets/radius_selector.dart';
import '../../../core/widgets/map_style_selector.dart';
import '../../auth/data/auth_providers.dart';
import '../../../core/widgets/optimized_image.dart';
import '../../home/presentation/home_shell.dart';
import '../../profile/data/road_trip_service.dart';
import '../../profile/data/xp_service.dart';
import '../domain/poi.dart';
import '../domain/poi_category.dart';
import '../domain/map_style.dart';
import 'map_controller.dart';
import 'poi_detail_page.dart';

class MapPage extends StatelessWidget {
  const MapPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: const MapView(),
    );
  }
}

class MapView extends ConsumerStatefulWidget {
  const MapView({super.key});

  @override
  ConsumerState<MapView> createState() => _MapViewState();
}

enum _MapOverlayPanel {
  none,
  radius,
  legend,
  style,
}

class _MapViewState extends ConsumerState<MapView> {
  static const double _mapCornerRadius = 18;
  late flutter_map.MapController _flutterMapController;
  bool _initialized = false;
  bool _centeredOnFirstLocation = false;
  bool _isAutoXpRunning = false;
  _MapOverlayPanel _activePanel = _MapOverlayPanel.none;
  bool _showNearbyList = false;
  Position? _lastAutoXpPosition;
  DateTime? _lastAutoXpRunAt;
  final Map<String, DateTime> _lastAutoAttemptBySpot = {};
  Timer? _spotsSyncTimer;
  bool _autoXpCheckQueued = false;
  Set<String> _selectedDetailedFilters = {};
  bool _filterPmrAccess = false;
  bool _filterCampingAccess = false;
  bool _filterParkingNearby = false;
  bool _isBrowsingMapArea = false;
  bool _showSearchHereButton = false;
  LatLng? _pendingMapSearchCenter;
  String _nearbySearchQuery = '';

  static const double _autoXpRadiusMeters = 10;
  static const double _autoXpMinMovementMeters = 20;
  static const Duration _autoXpMinInterval = Duration(seconds: 15);
  static const Duration _autoXpAttemptCooldown = Duration(minutes: 10);

  @override
  void initState() {
    super.initState();
    _flutterMapController = flutter_map.MapController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_initialized) {
        _initialized = true;
        ref.read(mapControllerProvider.notifier).init();
        _startSpotsSyncTimer();
      }
    });
  }

  void _startSpotsSyncTimer() {
    _spotsSyncTimer?.cancel();
    _spotsSyncTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (!mounted) return;
      final state = ref.read(mapControllerProvider);
      if (state.userPosition == null || state.isLoading) return;
      ref.read(mapControllerProvider.notifier).refreshNearby(
            forceRefresh: false,
            includeExistingPois: true,
            softUpdate: true,
          );
    });
  }

  void _scheduleAutoXpCheck(MapState state) {
    if (_autoXpCheckQueued) return;
    _autoXpCheckQueued = true;
    Future.microtask(() async {
      _autoXpCheckQueued = false;
      if (!mounted) return;
      await _maybeAutoClaimXp(state);
    });
  }

  @override
  void dispose() {
    _spotsSyncTimer?.cancel();
    _flutterMapController.dispose();
    super.dispose();
  }

  bool _matchesNearbySearch(Poi poi) {
    final query = _normalizeLabel(_nearbySearchQuery);
    if (query.isEmpty) return true;
    final haystack = _normalizeLabel(
      '${poi.displayName} ${poi.shortDescription} ${formatPoiSubCategory(poi.subCategory)}',
    );
    return haystack.contains(query);
  }

  void _onMapPositionChanged(LatLng center, bool hasGesture) {
    if (!hasGesture) return;
    _pendingMapSearchCenter = center;
    _isBrowsingMapArea = true;
    if (_showSearchHereButton) return;
    if (!mounted) return;
    setState(() {
      _showSearchHereButton = true;
    });
  }

  Future<void> _searchInCurrentMapArea() async {
    final center = _pendingMapSearchCenter;
    if (center == null) return;

    await ref.read(mapControllerProvider.notifier).refreshNearby(
          userLatOverride: center.latitude,
          userLngOverride: center.longitude,
          forceRefresh: true,
          includeExistingPois: true,
          softUpdate: true,
        );

    if (!mounted) return;
    setState(() {
      _showSearchHereButton = false;
    });
  }

  Color _getColorForCategory(PoiCategory category) {
    switch (category) {
      case PoiCategory.culture:
        return Colors.blue;
      case PoiCategory.nature:
        return Colors.green;
      case PoiCategory.experienceGustative:
        return Colors.orange;
      case PoiCategory.histoire:
        return Colors.brown;
      case PoiCategory.activites:
        return Colors.red;
    }
  }

  Color _legendColorForCategory(PoiCategory category) {
    return _getColorForCategory(category);
  }

  IconData _iconForCategory(PoiCategory category) {
    switch (category) {
      case PoiCategory.culture:
        return Icons.museum;
      case PoiCategory.nature:
        return Icons.park;
      case PoiCategory.experienceGustative:
        return Icons.restaurant;
      case PoiCategory.histoire:
        return Icons.account_balance;
      case PoiCategory.activites:
        return Icons.directions_run;
    }
  }

  Future<void> _ensureCenteredOnLocation() async {
    if (_centeredOnFirstLocation) return;

    final state = ref.read(mapControllerProvider);
    final pos = state.userPosition;
    if (pos != null) {
      _centeredOnFirstLocation = true;
      _flutterMapController.move(
        LatLng(pos.latitude, pos.longitude),
        15,
      );
    }
  }

  Future<void> _addToRoadTrip(Poi poi) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Connectez-vous pour creer un road trip.')),
      );
      return;
    }

    final hasPremiumPass =
        ref.read(profileStreamProvider).value?.hasPremiumPass ?? false;
    final maxItems = RoadTripService.maxItemsFor(hasPremiumPass);
    final maxTrips = RoadTripService.maxTripsFor(hasPremiumPass);
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

  Future<void> _maybeAutoClaimXp(MapState state) async {
    if (_isAutoXpRunning) return;

    final user = FirebaseAuth.instance.currentUser;
    final userPos = state.userPosition;
    if (user == null || userPos == null || state.nearbyPois.isEmpty) {
      return;
    }

    final now = DateTime.now();
    final lastRunAt = _lastAutoXpRunAt;
    final lastPos = _lastAutoXpPosition;

    if (lastRunAt != null && now.difference(lastRunAt) < _autoXpMinInterval) {
      if (lastPos != null) {
        final moved = Geolocator.distanceBetween(
          lastPos.latitude,
          lastPos.longitude,
          userPos.latitude,
          userPos.longitude,
        );
        if (moved < _autoXpMinMovementMeters) {
          return;
        }
      } else {
        return;
      }
    }

    final closePois = state.nearbyPois.where((poi) {
      final distance = Geolocator.distanceBetween(
        userPos.latitude,
        userPos.longitude,
        poi.lat,
        poi.lng,
      );
      return distance <= _autoXpRadiusMeters;
    }).toList();

    if (closePois.isEmpty) {
      _lastAutoXpRunAt = now;
      _lastAutoXpPosition = userPos;
      return;
    }

    _isAutoXpRunning = true;

    try {
      for (final poi in closePois) {
        final lastAttempt = _lastAutoAttemptBySpot[poi.id];
        if (lastAttempt != null &&
            now.difference(lastAttempt) < _autoXpAttemptCooldown) {
          continue;
        }

        _lastAutoAttemptBySpot[poi.id] = now;
        final result = await XpService.registerVisit(uid: user.uid, poi: poi);

        if (!mounted) return;
        if (result.awarded) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result.leveledUp
                    ? '🎉 Nouveau grade atteint : ${result.newGrade} (Niv. ${result.newLevel})'
                    : '✅ +10 XP auto : ${poi.displayName}',
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } finally {
      _lastAutoXpRunAt = now;
      _lastAutoXpPosition = userPos;
      _isAutoXpRunning = false;
    }
  }

  PoiCategory? _categoryForGroupTitle(String title) {
    switch (title) {
      case 'Patrimoine et Histoire':
        return PoiCategory.histoire;
      case 'Nature':
        return PoiCategory.nature;
      case 'Culture':
        return PoiCategory.culture;
      case 'Experience gustative':
        return PoiCategory.experienceGustative;
      case 'Activites plein air':
        return PoiCategory.activites;
      default:
        return null;
    }
  }

  Set<String> _itemsFromSelectedCategories(Set<PoiCategory> categories) {
    if (categories.isEmpty || categories.length == PoiCategory.values.length) {
      return {
        for (final group in poiCategoryGroups) ...group.items,
      };
    }

    final items = <String>{};
    for (final group in poiCategoryGroups) {
      final category = _categoryForGroupTitle(group.title);
      if (category != null && categories.contains(category)) {
        items.addAll(group.items);
      }
    }
    return items;
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
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _matchesDetailedCategoryFilter(Poi poi) {
    if (_selectedDetailedFilters.isEmpty) return true;

    final poiText = _normalizeLabel(
      '${poi.displayName} ${poi.shortDescription} ${formatPoiSubCategory(poi.subCategory)} ${poi.category.label}',
    );

    for (final item in _selectedDetailedFilters) {
      final normalizedItem = _normalizeLabel(item);
      if (normalizedItem.isEmpty) continue;

      if (poiText.contains(normalizedItem)) {
        return true;
      }

      final simplified = normalizedItem.split('(').first.trim();
      if (simplified.isNotEmpty && poiText.contains(simplified)) {
        return true;
      }

      final tokens = simplified
          .split(RegExp(r'[,/]'))
          .map((token) => token.trim())
          .where((token) => token.length >= 4);
      for (final token in tokens) {
        if (poiText.contains(token)) {
          return true;
        }
      }
    }

    return false;
  }

  bool _hasCampingAccess(Poi poi) {
    if (poi.vanAccessible == true || poi.camperPowerAvailable == true) {
      return true;
    }

    final text = _normalizeLabel(
      '${poi.displayName} ${poi.shortDescription} ${poi.subCategory ?? ''}',
    );
    return text.contains('camping') ||
        text.contains('campground') ||
        text.contains('camp') ||
        text.contains('aire camping car');
  }

  bool _hasParkingNearby(Poi poi) {
    final text = _normalizeLabel(
      '${poi.displayName} ${poi.shortDescription} ${poi.subCategory ?? ''}',
    );
    return text.contains('parking') ||
        text.contains('stationnement') ||
        text.contains('park and ride');
  }

  bool _matchesAdditionalFilters(Poi poi) {
    if (_filterPmrAccess && poi.pmrAccessible != true) {
      return false;
    }
    if (_filterCampingAccess && !_hasCampingAccess(poi)) {
      return false;
    }
    if (_filterParkingNearby && !_hasParkingNearby(poi)) {
      return false;
    }
    return true;
  }

  Future<void> _openMapFiltersSheet() async {
    final initialState = ref.read(mapControllerProvider);
    final selectedItems = _selectedDetailedFilters.isEmpty
        ? _itemsFromSelectedCategories(initialState.filters.categories)
        : _selectedDetailedFilters;
    var draftItems = <String>{...selectedItems};
    var draftOpenNow = initialState.filters.openNow;
    var draftPmrAccess = _filterPmrAccess;
    var draftCampingAccess = _filterCampingAccess;
    var draftParkingNearby = _filterParkingNearby;

    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SizedBox(
              height: MediaQuery.of(context).size.height * 0.82,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                    child: Column(
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 6,
                            decoration: BoxDecoration(
                              color: const Color(0xFFC3C8D9),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.filter_alt, size: 24, color: Color(0xFF2A3155)),
                            SizedBox(width: 10),
                            Text(
                              'Filtres',
                              style: TextStyle(
                                fontSize: 42 / 2,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF212846),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Filtres carte independants de vos interets profil',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF6A718D),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSheetSectionTitle('Filtrer les types de lieux :'),
                          for (final group in poiCategoryGroups)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 10, bottom: 4),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          group.title,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF4A5070),
                                          ),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          setSheetState(() {
                                            draftItems.addAll(group.items);
                                          });
                                        },
                                        style: TextButton.styleFrom(
                                          foregroundColor: const Color(0xFF2C5FC7),
                                          textStyle: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12,
                                          ),
                                          visualDensity: VisualDensity.compact,
                                          minimumSize: const Size(52, 30),
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        child: const Text('Tout'),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          setSheetState(() {
                                            draftItems.removeAll(group.items);
                                          });
                                        },
                                        style: TextButton.styleFrom(
                                          foregroundColor: const Color(0xFF7A819D),
                                          textStyle: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12,
                                          ),
                                          visualDensity: VisualDensity.compact,
                                          minimumSize: const Size(56, 30),
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        child: const Text('Aucun'),
                                      ),
                                    ],
                                  ),
                                ),
                                for (final item in group.items)
                                  _buildSheetOptionRow(
                                    icon: _iconForGroup(group.title),
                                    iconBackground: _iconColorForGroup(group.title),
                                    label: item,
                                    selected: draftItems.contains(item),
                                    onTap: () {
                                      setSheetState(() {
                                        if (draftItems.contains(item)) {
                                          draftItems.remove(item);
                                        } else {
                                          draftItems.add(item);
                                        }
                                      });
                                    },
                                  ),
                              ],
                            ),
                          const SizedBox(height: 20),
                          _buildSheetSectionTitle('Autres filtres'),
                          _buildSheetOptionRow(
                            icon: Icons.schedule,
                            iconBackground: const Color(0xFFE2B7AE),
                            label: 'Ouvert actuellement',
                            selected: draftOpenNow,
                            onTap: () => setSheetState(
                              () => draftOpenNow = !draftOpenNow,
                            ),
                          ),
                          _buildSheetOptionRow(
                            icon: Icons.accessible,
                            iconBackground: const Color(0xFF9AAED1),
                            label: 'Acces PMR',
                            selected: draftPmrAccess,
                            onTap: () => setSheetState(
                              () => draftPmrAccess = !draftPmrAccess,
                            ),
                          ),
                          _buildSheetOptionRow(
                            icon: Icons.rv_hookup,
                            iconBackground: const Color(0xFFB0AAA1),
                            label: 'Acces camping',
                            selected: draftCampingAccess,
                            onTap: () => setSheetState(
                              () => draftCampingAccess = !draftCampingAccess,
                            ),
                          ),
                          _buildSheetOptionRow(
                            icon: Icons.local_parking,
                            iconBackground: const Color(0xFF9DB4D3),
                            label: 'Parking a proximite',
                            selected: draftParkingNearby,
                            onTap: () => setSheetState(
                              () => draftParkingNearby = !draftParkingNearby,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        top: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
                    child: SizedBox(
                      height: 56,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF3FD0A0),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                        onPressed: () => Navigator.of(sheetContext).pop(true),
                        child: const Text(
                          'Appliquer les filtres',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (applied != true) return;

    final selectedPreferences = draftItems.toList(growable: false);

    final mapNotifier = ref.read(mapControllerProvider.notifier);
    await mapNotifier.applyCategoryPreferences(selectedPreferences);
    await mapNotifier.setOpenNow(draftOpenNow);
    if (!mounted) return;
    setState(() {
      _selectedDetailedFilters = draftItems;
      _filterPmrAccess = draftPmrAccess;
      _filterCampingAccess = draftCampingAccess;
      _filterParkingNearby = draftParkingNearby;
    });
  }

  Widget _buildSheetSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 24 / 1.4,
              fontWeight: FontWeight.w800,
              color: Color(0xFF343C62),
            ),
          ),
          const SizedBox(height: 8),
          Divider(height: 1, color: Colors.grey.shade300),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  IconData _iconForGroup(String title) {
    switch (title) {
      case 'Patrimoine et Histoire':
        return Icons.account_balance;
      case 'Nature':
        return Icons.park;
      case 'Culture':
        return Icons.palette;
      case 'Activites plein air':
        return Icons.directions_walk;
      default:
        return Icons.place;
    }
  }

  Color _iconColorForGroup(String title) {
    switch (title) {
      case 'Patrimoine et Histoire':
        return const Color(0xFFD6A9A9);
      case 'Nature':
        return const Color(0xFF8EC8A4);
      case 'Culture':
        return const Color(0xFF9BB8D9);
      case 'Activites plein air':
        return const Color(0xFFB0AAA1);
      default:
        return const Color(0xFF9DB4D3);
    }
  }

  Widget _buildSheetOptionRow({
    required IconData icon,
    required Color iconBackground,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: iconBackground,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 20 / 1.25,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF232A47),
                ),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: selected ? const Color(0xFF3FD0A0) : const Color(0xFFF3F4F7),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected ? const Color(0xFF3FD0A0) : const Color(0xFFB8BED3),
                  width: 2,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check, color: Colors.white, size: 22)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoundMapButton({
    required IconData icon,
    required VoidCallback onPressed,
    required String tooltip,
    Color iconColor = const Color(0xFF2C5FC7),
  }) {
    return ClipOval(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Material(
          color: Colors.white.withValues(alpha: 0.24),
          elevation: 0,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.42),
                width: 1.1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: IconButton(
              onPressed: onPressed,
              tooltip: tooltip,
              splashRadius: 26,
              constraints: const BoxConstraints.tightFor(width: 56, height: 56),
              icon: Icon(icon, size: 28, color: iconColor),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mapStyle = ref.watch(
      mapControllerProvider.select((state) => state.mapStyle),
    );
    final profile = ref.watch(profileStreamProvider).value;
    final hasSatelliteAccess = profile?.hasPremiumPass == true &&
        (profile?.premiumExpiryDate == null ||
            profile!.premiumExpiryDate!.isAfter(DateTime.now()));

    if (!hasSatelliteAccess && mapStyle == MapStyle.esriWorldImagery) {
      Future.microtask(
        () => ref
            .read(mapControllerProvider.notifier)
            .setMapStyle(MapStyle.openStreetMapFrance),
      );
    }
    final radiusMeters = ref.watch(
      mapControllerProvider.select((state) => state.radiusMeters),
    );

    // OPTIMISÉ: Utiliser .select() pour ne reconstruire QUE si displayedPois ou userPosition changent
    // Évite les rebuilds inutiles sur les changements de filters, isSatellite, etc.
    final displayedPois = ref.watch(
      mapControllerProvider.select((state) => state.displayedPois),
    );

    final userPosition = ref.watch(
      mapControllerProvider.select((state) => state.userPosition),
    );
    final isLoading = ref.watch(
      mapControllerProvider.select((state) => state.isLoading),
    );
    final error = ref.watch(
      mapControllerProvider.select((state) => state.error),
    );

    // Centrer automatiquement au premier chargement de la position
    if (!_centeredOnFirstLocation && userPosition != null) {
      Future.microtask(
        _ensureCenteredOnLocation,
      );
    }

    final userPos = userPosition;
    // Recréer l'état complet pour _maybeAutoClaimXp (il en a besoin)
    final fullState = ref.read(mapControllerProvider);
    final visiblePois = displayedPois
      .where(_matchesDetailedCategoryFilter)
      .where(_matchesAdditionalFilters)
      .toList();

    // Debug: afficher le statut du chargement
    if (kDebugMode) {
      debugPrint(
        '[MapView] displayed=${displayedPois.length}, visible=${visiblePois.length}, '
        'isLoading=$isLoading, error=$error, '
        'userPos=${userPos != null ? "OK" : "NULL"}',
      );
    }

    _scheduleAutoXpCheck(fullState.copyWith(nearbyPois: visiblePois));

    return Stack(
      children: [
        ClipRRect(
          borderRadius: const BorderRadius.vertical(
            top: Radius.zero,
            bottom: Radius.circular(_mapCornerRadius),
          ),
          child: flutter_map.FlutterMap(
            mapController: _flutterMapController,
            options: flutter_map.MapOptions(
              initialCenter: LatLng(
                userPos?.latitude ?? 48.8566,
                userPos?.longitude ?? 2.3522,
              ),
              initialZoom: 15,
              minZoom: 1,
              maxZoom: 18,
              onTap: (_, __) {
                if (_activePanel != _MapOverlayPanel.none || _showNearbyList) {
                  setState(() {
                    _activePanel = _MapOverlayPanel.none;
                    _showNearbyList = false;
                  });
                }
              },
              onPositionChanged: (camera, hasGesture) {
                final center = camera.center;
                _onMapPositionChanged(center, hasGesture);
              },
            ),
            children: [
              flutter_map.TileLayer(
                urlTemplate: mapStyle.urlTemplate,
                userAgentPackageName: 'com.allspots',
                subdomains: mapStyle.subdomains,
                maxZoom: mapStyle.maxZoom.toDouble(),
              ),
              flutter_map.MarkerLayer(
                markers: visiblePois.map((p) {
                  return flutter_map.Marker(
                    point: LatLng(p.lat, p.lng),
                    width: 50,
                    height: 50,
                    alignment: Alignment.center,
                    child: GestureDetector(
                      onTap: () {
                        _showPoiPopup(context, p, LatLng(p.lat, p.lng));
                      },
                      child: Center(
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _getColorForCategory(p.category),
                              width: 2.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.18),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            _iconForCategory(p.category),
                            color: _getColorForCategory(p.category),
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              if (userPos != null)
                flutter_map.MarkerLayer(
                  markers: [
                    flutter_map.Marker(
                      point: LatLng(userPos.latitude, userPos.longitude),
                      width: 12,
                      height: 12,
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        // Panneau flottant (Rayon / Légende / Style) avec animation harmonisée
        if (!_showNearbyList)
          Positioned(
            left: 12,
            bottom: 12,
            right: 90,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                final slide = Tween<Offset>(
                  begin: const Offset(0, 0.08),
                  end: Offset.zero,
                ).animate(animation);
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(position: slide, child: child),
                );
              },
              child: _buildOverlayPanel(
                radiusMeters: radiusMeters,
                mapStyle: mapStyle,
                hasSatelliteAccess: hasSatelliteAccess,
              ),
            ),
          ),
        // Actions principales (haut droit)
        Positioned(
          top: MediaQuery.paddingOf(context).top + 10,
          left: 12,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildRoundMapButton(
                icon: Icons.star,
                tooltip: 'Profil et favoris',
                onPressed: () {
                  ref.read(homeShellTabIndexProvider.notifier).state = 2;
                },
              ),
              const SizedBox(width: 10),
              _buildRoundMapButton(
                icon: _showNearbyList ? Icons.map : Icons.view_list,
                tooltip: _showNearbyList
                    ? 'Revenir sur la carte'
                    : 'Lister les spots proches',
                onPressed: () async {
                  if (!_showNearbyList) {
                    final mapNotifier = ref.read(mapControllerProvider.notifier);
                    if (radiusMeters != 20000) {
                      await mapNotifier.updateRadius(20000);
                    }

                    final currentUserPos = ref.read(mapControllerProvider).userPosition;
                    if (currentUserPos != null) {
                      await mapNotifier.refreshNearby(
                        userLatOverride: currentUserPos.latitude,
                        userLngOverride: currentUserPos.longitude,
                        forceRefresh: true,
                        includeExistingPois: true,
                        softUpdate: true,
                      );
                    }

                    _isBrowsingMapArea = false;
                    _showSearchHereButton = false;
                    _pendingMapSearchCenter = null;
                  }

                  setState(() {
                    _showNearbyList = !_showNearbyList;
                    if (!_showNearbyList) {
                      _nearbySearchQuery = '';
                    }
                    _activePanel = _MapOverlayPanel.none;
                  });
                },
              ),
            ],
          ),
        ),
        if (_showNearbyList)
          _buildNearbySpotsPanel(
            context: context,
            pois: visiblePois,
            userPos: userPos,
          ),
        Positioned(
          top: MediaQuery.paddingOf(context).top + 10,
          right: 12,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildRoundMapButton(
                icon: Icons.layers,
                tooltip: 'Style de carte',
                onPressed: () => _togglePanel(_MapOverlayPanel.style),
              ),
              const SizedBox(width: 8),
              _buildRoundMapButton(
                icon: Icons.filter_alt,
                tooltip: 'Filtres',
                onPressed: _openMapFiltersSheet,
              ),
            ],
          ),
        ),
        // Contrôles secondaires (bas droit)
        if (!_showNearbyList)
          Positioned(
            right: 12,
            bottom: 12,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _MapUsersCountBadge(),
                const SizedBox(height: 8),
                _buildRoundMapButton(
                  icon: Icons.info_outline,
                  tooltip: 'Legende',
                  onPressed: () => _togglePanel(_MapOverlayPanel.legend),
                ),
                const SizedBox(height: 8),
                _buildRoundMapButton(
                  icon: Icons.radio_button_checked,
                  tooltip: 'Rayon de recherche',
                  onPressed: () => _togglePanel(_MapOverlayPanel.radius),
                ),
                const SizedBox(height: 8),
                if (_showSearchHereButton) ...[
                  _buildRoundMapButton(
                    icon: Icons.travel_explore,
                    tooltip: 'Rechercher ici',
                    onPressed: _searchInCurrentMapArea,
                  ),
                  const SizedBox(height: 8),
                ],
                _buildRoundMapButton(
                  icon: Icons.my_location,
                  tooltip: 'Me centrer',
                  onPressed: () async {
                    final pos = ref.read(mapControllerProvider).userPosition;
                    if (pos == null) return;
                    _isBrowsingMapArea = false;
                    _showSearchHereButton = false;
                    _pendingMapSearchCenter = null;
                    _flutterMapController.move(
                      LatLng(pos.latitude, pos.longitude),
                      15,
                    );
                    await ref.read(mapControllerProvider.notifier).refreshNearby(
                          userLatOverride: pos.latitude,
                          userLngOverride: pos.longitude,
                          forceRefresh: true,
                          includeExistingPois: true,
                          softUpdate: true,
                        );
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildNearbySpotsPanel({
    required BuildContext context,
    required List<Poi> pois,
    required Position? userPos,
  }) {
    final topInset = MediaQuery.paddingOf(context).top + 86;
    final filteredPois = pois.where(_matchesNearbySearch).toList();

    return Positioned(
      top: topInset,
      left: 0,
      right: 0,
      bottom: 0,
      child: Material(
        color: Colors.white,
        elevation: 8,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 12, 10),
              child: Row(
                children: [
                  const Icon(Icons.view_list, color: Color(0xFF4E5575)),
                  const SizedBox(width: 10),
                  Text(
                    '${filteredPois.length} spot(s) a proximite',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF2E3557),
                    ),
                  ),
                  if (_isBrowsingMapArea) ...[
                    const SizedBox(width: 8),
                    const Flexible(
                      child: Text(
                        '(zone de carte)',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7290),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  IconButton(
                    tooltip: 'Revenir a la carte',
                    onPressed: () {
                      setState(() => _showNearbyList = false);
                    },
                    icon: const Icon(Icons.map, color: Color(0xFF6B7290)),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: Colors.grey.shade300),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: TextField(
                onChanged: (value) => setState(() => _nearbySearchQuery = value),
                style: const TextStyle(
                  fontSize: 15,
                  color: Color(0xFF2E3557),
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Rechercher un spot autour de moi',
                  hintStyle: const TextStyle(
                    color: Color(0xFF8A90A8),
                    fontWeight: FontWeight.w600,
                  ),
                  prefixIcon: const Icon(Icons.search, color: Color(0xFF6A7190)),
                  suffixIcon: _nearbySearchQuery.trim().isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Effacer',
                          onPressed: () => setState(() => _nearbySearchQuery = ''),
                          icon: const Icon(Icons.close, size: 18),
                        ),
                  filled: true,
                  fillColor: const Color(0xFFF2F4FA),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: filteredPois.isEmpty
                  ? const Center(
                      child: Text(
                        'Aucun spot avec ces filtres.',
                        style: TextStyle(
                          fontSize: 16,
                          color: Color(0xFF707892),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                      itemCount: filteredPois.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, index) {
                        final poi = filteredPois[index];
                        return _buildNearbySpotCard(
                          context: context,
                          poi: poi,
                          userPos: userPos,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNearbySpotCard({
    required BuildContext context,
    required Poi poi,
    required Position? userPos,
  }) {
    final subCategory = formatPoiSubCategory(poi.subCategory);
    final distanceMeters = userPos == null
        ? null
        : Geolocator.distanceBetween(
            userPos.latitude,
            userPos.longitude,
            poi.lat,
            poi.lng,
          );

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _showPoiDetails(context, poi, userPos),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: _getColorForCategory(poi.category),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      _iconForCategory(poi.category),
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          poi.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF245CC2),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subCategory.isNotEmpty
                              ? subCategory
                              : poi.category.localizationLabel(context),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF5A6384),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (distanceMeters != null)
                    Text(
                      distanceMeters >= 1000
                          ? '${(distanceMeters / 1000).toStringAsFixed(1)} km'
                          : '${distanceMeters.round()} m',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF6C7390),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                poi.shortDescription,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  color: Color(0xFF424B6D),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _togglePanel(_MapOverlayPanel panel) {
    setState(() {
      _activePanel = _activePanel == panel ? _MapOverlayPanel.none : panel;
    });
  }

  Widget _buildOverlayPanel({
    required double radiusMeters,
    required MapStyle mapStyle,
    required bool hasSatelliteAccess,
  }) {
    switch (_activePanel) {
      case _MapOverlayPanel.none:
        return const SizedBox.shrink(key: ValueKey('panel-none'));
      case _MapOverlayPanel.radius:
        return RadiusSelector(
          key: const ValueKey('panel-radius'),
          currentRadius: radiusMeters,
          radiusOptions: const [5000, 10000, 15000, 20000],
          onRadiusChanged: (radius) {
            ref.read(mapControllerProvider.notifier).updateRadius(radius);
            setState(() => _activePanel = _MapOverlayPanel.none);
          },
        );
      case _MapOverlayPanel.legend:
        return Container(
          key: const ValueKey('panel-legend'),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Legende des categories',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...PoiCategory.values.map(
                (category) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Icon(
                        _iconForCategory(category),
                        color: _legendColorForCategory(category),
                      ),
                      const SizedBox(width: 8),
                      Text(category.localizationLabel(context)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      case _MapOverlayPanel.style:
        return MapStyleSelector(
          key: const ValueKey('panel-style'),
          currentStyle: mapStyle,
          hasSatelliteAccess: hasSatelliteAccess,
          closeOnSelect: false,
          onStyleChanged: (style) {
            ref.read(mapControllerProvider.notifier).setMapStyle(style);
            setState(() => _activePanel = _MapOverlayPanel.none);
          },
        );
    }
  }

  void _showPoiPopup(BuildContext context, Poi poi, LatLng position) {
    final subCategoryLabel = formatPoiSubCategory(poi.subCategory);
    final rating = poi.googleRating;
    final photoCount = poi.imageUrls.length;

    showDialog(
      context: context,
      builder: (dialogContext) {
        // Utilise le context original pour la localisation
        final categoryLabel = subCategoryLabel.isNotEmpty
            ? subCategoryLabel
            : poi.category.localizationLabel(context);

        return Stack(
          children: [
            // Overlay semi-transparent
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.pop(dialogContext),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.3),
                ),
              ),
            ),
            // Bulle popup
            Center(
              child: GestureDetector(
                onTap: () {},
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    margin: const EdgeInsets.all(16),
                    constraints: BoxConstraints(
                      maxWidth: ResponsiveUtils.getDialogMaxWidth(
                        dialogContext.screenWidth,
                      ),
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // En-tête avec X
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: SizedBox(
                            width: double.infinity,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    poi.displayName,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close),
                                  onPressed: () => Navigator.pop(dialogContext),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Divider(height: 1),
                        // Contenu
                        SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (poi.imageUrls.isNotEmpty) ...[
                                  SizedBox(
                                    height: ResponsiveUtils.getImageHeight(
                                        dialogContext.screenWidth),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: OptimizedNetworkImage(
                                        imageUrl: poi.imageUrls.first,
                                        height: ResponsiveUtils.getImageHeight(
                                            dialogContext.screenWidth),
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                Text(
                                  poi.shortDescription,
                                  style: const TextStyle(fontSize: 13),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      iconForSubCategory(
                                        poi.subCategory,
                                        poi.category,
                                      ),
                                      size: 16,
                                      color: poi.category.color,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      categoryLabel,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (photoCount > 0) ...[
                                      const Icon(Icons.image, size: 14),
                                      const SizedBox(width: 4),
                                      Text(
                                        '$photoCount',
                                        style: const TextStyle(fontSize: 12),
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
                        // Bouton détails
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.pop(dialogContext);
                                _showPoiDetails(
                                    context,
                                    poi,
                                    ref
                                        .read(mapControllerProvider)
                                        .userPosition);
                              },
                              child: const Text('Voir détails'),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          child: SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => _addToRoadTrip(poi),
                              icon: const Icon(Icons.route),
                              label: const Text('Ajouter au road trip'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showPoiDetails(BuildContext context, Poi poi, [Position? userPos]) {
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => PoiDetailPage(
          poi: poi,
          userLocation: userPos,
        ),
      ),
    );
  }
}

class _MapUsersCountBadge extends StatelessWidget {
  const _MapUsersCountBadge();
  static const Duration _presenceFreshness = Duration(minutes: 3);

  String _formatCompactCount(int count) {
    if (count >= 1000000000) {
      return _formatCompactValue(count / 1000000000, 'B');
    }
    if (count >= 1000000) {
      return _formatCompactValue(count / 1000000, 'M');
    }
    if (count >= 1000) {
      return _formatCompactValue(count / 1000, 'K');
    }
    return '$count';
  }

  String _formatCompactValue(double value, String suffix) {
    final decimals = value >= 10 ? 0 : 1;
    final text = value.toStringAsFixed(decimals).replaceAll('.', ',');
    return '$text$suffix';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('profiles')
          .where('isOnline', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        final currentUid = FirebaseAuth.instance.currentUser?.uid;
        final now = DateTime.now();

        int activeUsers = 0;
        if (snapshot.hasData) {
          for (final doc in snapshot.data!.docs) {
            final data = doc.data();
            final isCurrentUser = currentUid != null && doc.id == currentUid;
            if (isCurrentUser) {
              activeUsers += 1;
              continue;
            }

            final lastSeenRaw = data['lastSeen'];
            DateTime? lastSeen;
            if (lastSeenRaw is Timestamp) {
              lastSeen = lastSeenRaw.toDate();
            } else if (lastSeenRaw is DateTime) {
              lastSeen = lastSeenRaw;
            }

            if (lastSeen == null) continue;
            final isFresh = now.difference(lastSeen) <= _presenceFreshness;
            if (isFresh) {
              activeUsers += 1;
            }
          }
        }

        final displayedUsers =
            currentUid != null && activeUsers == 0 ? 1 : activeUsers;
        final text = _formatCompactCount(displayedUsers);

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: scheme.primary,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                Icons.person,
                size: 14,
                color: scheme.onPrimary,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: scheme.primary.withValues(alpha: 0.35)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Text(
                text,
                style: TextStyle(
                  color: scheme.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
