import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/utils/responsive_utils.dart';
import '../../auth/data/auth_providers.dart';
import '../../../core/widgets/app_header.dart';
import '../../../core/widgets/optimized_image.dart';
import '../../profile/data/road_trip_service.dart';
import '../../profile/data/xp_service.dart';
import '../domain/poi.dart';
import '../domain/poi_category.dart';
import 'map_controller.dart';
import 'poi_detail_page.dart';

class MapPage extends StatelessWidget {
  const MapPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppHeader(
        height: 96,
        backgroundImage: 'assets/images/bg_header_allspots.png',
        titleWidget: SizedBox(
          height: 44,
          child: Image.asset(
            'assets/images/allspots_simple_logo.png',
            fit: BoxFit.contain,
          ),
        ),
      ),
      body: const MapView(),
    );
  }
}

class MapView extends ConsumerStatefulWidget {
  const MapView({super.key});

  @override
  ConsumerState<MapView> createState() => _MapViewState();
}

class _MapViewState extends ConsumerState<MapView> {
  GoogleMapController? _mapController;
  bool _initialized = false;
  bool _centeredOnFirstLocation = false; // Track si déjà centré
  bool _lastIsSatellite = false;
  bool _isAutoXpRunning = false;
  Position? _lastAutoXpPosition;
  DateTime? _lastAutoXpRunAt;
  final Map<String, DateTime> _lastAutoAttemptBySpot = {};

  static const double _autoXpRadiusMeters = 10;
  static const double _autoXpMinMovementMeters = 20;
  static const Duration _autoXpMinInterval = Duration(seconds: 15);
  static const Duration _autoXpAttemptCooldown = Duration(minutes: 10);

  double _markerHueForCategory(PoiCategory category) {
    switch (category) {
      case PoiCategory.culture:
        return BitmapDescriptor.hueAzure;
      case PoiCategory.nature:
        return BitmapDescriptor.hueGreen;
      case PoiCategory.experienceGustative:
        return BitmapDescriptor.hueOrange;
      case PoiCategory.histoire:
        return BitmapDescriptor.hueViolet;
      case PoiCategory.activites:
        return BitmapDescriptor.hueRed;
    }
  }

  Color _legendColorForCategory(PoiCategory category) {
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

  @override
  void initState() {
    super.initState();
    // Initialize map controller only once
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_initialized) {
        _initialized = true;
        ref.read(mapControllerProvider.notifier).init();
      }
    });
  }

  Future<void> _ensureCenteredOnLocation() async {
    if (_centeredOnFirstLocation || _mapController == null) return;

    final state = ref.read(mapControllerProvider);
    final pos = state.userPosition;
    if (pos != null) {
      _centeredOnFirstLocation = true;
      await _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(pos.latitude, pos.longitude),
          15,
        ),
      );
    }
  }

  Future<void> _toggle3DView() async {
    if (_mapController == null) return;

    final isSatellite = ref.read(mapControllerProvider).isSatellite;
    if (!isSatellite) return;

    // Basculer l'état des bâtiments
    ref.read(mapControllerProvider.notifier).toggleBuildings();

    // Obtenir la position actuelle de la caméra
    final currentPosition = await _mapController!.getLatLng(
      const ScreenCoordinate(x: 0, y: 0),
    );

    // Si on active la 3D, incliner la caméra à 45°, sinon remettre à plat (0°)
    final newTilt =
        ref.read(mapControllerProvider).buildingsEnabled ? 45.0 : 0.0;

    // Animer la caméra avec le nouveau tilt
    await _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: currentPosition,
          zoom: await _mapController!.getZoomLevel(),
          tilt: newTilt,
          bearing: 0,
        ),
      ),
    );
  }

  Future<void> _resetTiltTo2D() async {
    if (_mapController == null) return;
    final currentPosition = await _mapController!.getLatLng(
      const ScreenCoordinate(x: 0, y: 0),
    );
    final zoom = await _mapController!.getZoomLevel();
    await _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: currentPosition,
          zoom: zoom,
          tilt: 0.0,
          bearing: 0,
        ),
      ),
    );
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
    final result = await RoadTripService.addPoi(
      user.uid,
      poi,
      maxItems: maxItems,
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
              content: Text('✅ +10 XP auto : ${poi.name}'),
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

  @override
  Widget build(BuildContext context) {
    // Apply category preferences from profile when it changes
    final profile = ref.watch(profileStreamProvider);
    if (profile.hasValue && profile.value != null) {
      final preferences = profile.value!.categories;
      Future.microtask(
        () => ref
            .read(mapControllerProvider.notifier)
            .applyCategoryPreferences(preferences),
      );
    }

    final state = ref.watch(mapControllerProvider);

    Future.microtask(() => _maybeAutoClaimXp(state));

    if (_lastIsSatellite != state.isSatellite) {
      _lastIsSatellite = state.isSatellite;
      if (!state.isSatellite) {
        if (state.buildingsEnabled) {
          ref.read(mapControllerProvider.notifier).toggleBuildings();
        }
        Future.microtask(_resetTiltTo2D);
      }
    }

    // Centrer automatiquement au premier chargement de la position
    if (!_centeredOnFirstLocation &&
        _mapController != null &&
        state.userPosition != null) {
      Future.microtask(_ensureCenteredOnLocation);
    }

    final userPos = state.userPosition;
    final initialCamera = CameraPosition(
      target: LatLng(
        userPos?.latitude ?? 48.8566, // fallback Paris
        userPos?.longitude ?? 2.3522,
      ),
      zoom: 15, // Zoom plus proche pour voir ~1km
    );

    final markers = <Marker>{
      ...state.nearbyPois.map(
        (p) => Marker(
          markerId: MarkerId(p.id),
          position: LatLng(p.lat, p.lng),
          infoWindow: InfoWindow(
            title: p.name,
            snippet: p.shortDescription,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            _markerHueForCategory(p.category),
          ),
          alpha: 1.0,
          onTap: () {
            _showPoiPopup(context, p, LatLng(p.lat, p.lng));
          },
        ),
      ),
    };

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: initialCamera,
          mapType: state.isSatellite ? MapType.satellite : MapType.normal,
          myLocationEnabled: state.userPosition != null,
          myLocationButtonEnabled: false,
          markers: markers,
          trafficEnabled: false,
          buildingsEnabled: state.isSatellite && state.buildingsEnabled,
          indoorViewEnabled: true,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          onMapCreated: (c) {
            _mapController = c;
            _ensureCenteredOnLocation();
          },
        ),
        Positioned(
          right: 12,
          bottom: 12,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _MapUsersCountBadge(),
              const SizedBox(height: 8),
              Material(
                color: Colors.white,
                elevation: 3,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: IconButton(
                  onPressed: () => _showLegend(context),
                  tooltip: 'Légende',
                  splashRadius: 22,
                  constraints: const BoxConstraints.tightFor(
                    width: 44,
                    height: 44,
                  ),
                  padding: EdgeInsets.zero,
                  icon: const Icon(
                    Icons.info_outline,
                    size: 22,
                    color: Colors.blue,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: IconButton(
                    onPressed: () async {
                      final pos = ref.read(mapControllerProvider).userPosition;
                      if (pos == null) return;
                      await _mapController?.animateCamera(
                        CameraUpdate.newLatLngZoom(
                          LatLng(pos.latitude, pos.longitude),
                          15,
                        ),
                      );
                    },
                    tooltip: 'Me centrer',
                    splashRadius: 22,
                    constraints: const BoxConstraints.tightFor(
                      width: 44,
                      height: 44,
                    ),
                    padding: EdgeInsets.zero,
                    icon: const Icon(
                      Icons.my_location,
                      size: 22,
                      color: Colors.blue,
                    ),
                  ),
                ),
              ),
              if (state.isSatellite) ...[
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _toggle3DView,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              state.buildingsEnabled
                                  ? Icons.view_in_ar
                                  : Icons.view_in_ar_outlined,
                              size: 22,
                              color: state.buildingsEnabled
                                  ? Colors.blue
                                  : Colors.grey,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '3D',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                color: state.buildingsEnabled
                                    ? Colors.blue
                                    : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  void _showLegend(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Legende des categories',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              for (final category in PoiCategory.values)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(
                        Icons.location_on,
                        color: _legendColorForCategory(category),
                      ),
                      const SizedBox(width: 8),
                      Text(category.label),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showPoiPopup(BuildContext context, Poi poi, LatLng position) {
    final subCategoryLabel = formatPoiSubCategory(poi.subCategory);
    final categoryLabel =
        subCategoryLabel.isNotEmpty ? subCategoryLabel : poi.category.label;
    final rating = poi.googleRating;
    final photoCount = poi.imageUrls.length;

    showDialog(
      context: context,
      builder: (dialogContext) {
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
                                    poi.name,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
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
                                      poi.category.icon,
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
        final totalUsers = snapshot.hasData ? snapshot.data!.docs.length : 0;
        final displayedUsers =
            currentUid != null && totalUsers == 0 ? 1 : totalUsers;
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
