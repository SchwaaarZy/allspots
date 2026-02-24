import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_map/flutter_map.dart' as flutter_map;
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/utils/responsive_utils.dart';
import '../../../core/widgets/radius_selector.dart';
import '../../../core/widgets/map_style_selector.dart';
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
  late flutter_map.MapController _flutterMapController;
  bool _initialized = false;
  bool _centeredOnFirstLocation = false;
  bool _isAutoXpRunning = false;
  bool _showRadiusSelector = false;
  Position? _lastAutoXpPosition;
  DateTime? _lastAutoXpRunAt;
  final Map<String, DateTime> _lastAutoAttemptBySpot = {};

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
      }
    });
  }

  @override
  void dispose() {
    _flutterMapController.dispose();
    super.dispose();
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
              content: Text('✅ +10 XP auto : ${poi.displayName}'),
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
      Future.microtask(_ensureCenteredOnLocation);
    }

    final userPos = userPosition;
    // Recréer l'état complet pour _maybeAutoClaimXp (il en a besoin)
    final fullState = ref.read(mapControllerProvider);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('spots').snapshots(),
      builder: (context, snapshot) {
        final activeFirestoreIds = snapshot.hasData
            ? snapshot.data!.docs
                .where((doc) => doc.data()['isPublic'] != false)
                .map((doc) => doc.id)
                .toSet()
            : <String>{};

        final visiblePois = snapshot.hasData
            ? displayedPois
                .where(
                  (poi) =>
                      poi.source != 'firestore' ||
                      activeFirestoreIds.contains(poi.id),
                )
                .toList()
            : displayedPois;

        // Debug: afficher le statut du chargement
        debugPrint(
          '[MapView] displayed=${displayedPois.length}, visible=${visiblePois.length}, '
          'isLoading=$isLoading, error=$error, '
          'userPos=${userPos != null ? "OK" : "NULL"}',
        );

        Future.microtask(
          () => _maybeAutoClaimXp(fullState.copyWith(nearbyPois: visiblePois)),
        );

        return Stack(
          children: [
            flutter_map.FlutterMap(
              mapController: _flutterMapController,
              options: flutter_map.MapOptions(
                initialCenter: LatLng(
                  userPos?.latitude ?? 48.8566,
                  userPos?.longitude ?? 2.3522,
                ),
                initialZoom: 15,
                minZoom: 1,
                maxZoom: 18,
              ),
              children: [
                flutter_map.TileLayer(
                  urlTemplate: ref.watch(mapControllerProvider).mapStyle.urlTemplate,
                  userAgentPackageName: 'com.allspots',
                  subdomains: ref.watch(mapControllerProvider).mapStyle.subdomains,
                  maxZoom: ref.watch(mapControllerProvider).mapStyle.maxZoom.toDouble(),
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
                          child: Icon(
                            Icons.location_on,
                            color: _getColorForCategory(p.category),
                            size: 30,
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
            // Aucun message d'erreur - les spots s'affichent par proximité automatiquement
            if (error != null)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  color: Colors.orange.shade600,
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    error,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            // Sélecteur de rayon (bas gauche)
            if (_showRadiusSelector)
              Positioned(
                left: 12,
                bottom: 12,
                right: 90,
                child: RadiusSelector(
                  currentRadius: ref.watch(mapControllerProvider).radiusMeters,
                  radiusOptions: const [5000, 10000, 15000, 20000],
                  onRadiusChanged: (radius) {
                    ref.read(mapControllerProvider.notifier).updateRadius(radius);
                  },
                ),
              ),
            // Contrôles secondaires (haut droit)
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
                      onPressed: () => _showMapStyleSelector(context),
                      tooltip: 'Style de carte',
                      splashRadius: 22,
                      constraints: const BoxConstraints.tightFor(
                        width: 44,
                        height: 44,
                      ),
                      padding: EdgeInsets.zero,
                      icon: const Icon(
                        Icons.layers,
                        size: 22,
                        color: Colors.blue,
                      ),
                    ),
                  ),
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
                        onPressed: () => setState(() => _showRadiusSelector = !_showRadiusSelector),
                        tooltip: 'Rayon de recherche',
                        splashRadius: 22,
                        constraints: const BoxConstraints.tightFor(
                          width: 44,
                          height: 44,
                        ),
                        padding: EdgeInsets.zero,
                        icon: const Icon(
                          Icons.radio_button_checked,
                          size: 22,
                          color: Colors.blue,
                        ),
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
                          _flutterMapController.move(
                            LatLng(pos.latitude, pos.longitude),
                            15,
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
                ],
              ),
            ),
          ],
        );
      },
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
                      Text(category.localizationLabel(context)),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showMapStyleSelector(BuildContext context) {
    final currentStyle = ref.read(mapControllerProvider).mapStyle;
    
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: MapStyleSelector(
            currentStyle: currentStyle,
            onStyleChanged: (style) {
              ref.read(mapControllerProvider.notifier).setMapStyle(style);
            },
          ),
        );
      },
    );
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
