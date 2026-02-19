import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../../auth/data/auth_providers.dart';
import '../../../core/widgets/app_header.dart';
import '../../../core/widgets/optimized_image.dart';
import '../../profile/data/road_trip_service.dart';
import '../domain/poi.dart';
import '../domain/poi_category.dart';
import 'map_controller.dart';
import 'poi_detail_page.dart';

class MapPage extends StatelessWidget {
  const MapPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      appBar: AppHeader(
        backgroundImage: 'assets/images/bg_header_allspots.png',
      ),
      body: MapView(),
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
    final newTilt = ref.read(mapControllerProvider).buildingsEnabled ? 45.0 : 0.0;
    
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
        const SnackBar(content: Text('Connectez-vous pour creer un road trip.')),
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
    if (!_centeredOnFirstLocation && _mapController != null && state.userPosition != null) {
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
      )
    };

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: initialCamera,
          mapType: state.isSatellite ? MapType.satellite : MapType.normal,
          myLocationEnabled: true,
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
          bottom: 12 + (2 * 48),
          child: Container(
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
                onTap: () async {
                  final pos = ref.read(mapControllerProvider).userPosition;
                  if (pos == null) return;
                  await _mapController?.animateCamera(
                    CameraUpdate.newLatLngZoom(
                      LatLng(pos.latitude, pos.longitude),
                      15,
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(
                    Icons.my_location,
                    size: 22,
                    color: Colors.blue,
                  ),
                ),
              ),
            ),
          ),
        ),
        if (state.isSatellite)
          Positioned(
            right: 12,
            bottom: 12,
            child: Container(
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
                          color:
                              state.buildingsEnabled ? Colors.blue : Colors.grey,
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
          ),
        Positioned(
          right: 12,
          bottom: 12 + (3 * 48),
          child: Container(
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
                onTap: () => _showLegend(context),
                borderRadius: BorderRadius.circular(12),
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(
                    Icons.info_outline,
                    size: 22,
                    color: Colors.blue,
                  ),
                ),
              ),
            ),
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
                                    height: 150,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: OptimizedNetworkImage(
                                        imageUrl: poi.imageUrls.first,
                                        height: 150,
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
                                _showPoiDetails(context, poi, ref.read(mapControllerProvider).userPosition);
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
