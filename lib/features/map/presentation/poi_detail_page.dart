import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math' as math;
import '../../../core/utils/responsive_utils.dart';
import '../../../core/widgets/glass_app_bar.dart';
import '../../../core/widgets/optimized_image.dart';
import '../domain/poi.dart';
import '../domain/poi_category.dart';
import '../data/rating_provider.dart';
import '../../auth/data/auth_providers.dart';
import '../../profile/data/road_trip_service.dart';
import 'navigation_app_picker.dart';

class PoiDetailPage extends ConsumerStatefulWidget {
  final Poi poi;
  final Position? userLocation;

  const PoiDetailPage({
    super.key,
    required this.poi,
    required this.userLocation,
  });

  @override
  ConsumerState<PoiDetailPage> createState() => _PoiDetailPageState();
}

class _PoiDetailPageState extends ConsumerState<PoiDetailPage> {
  double _myRating = 0;
  final _commentController = TextEditingController();
  bool _isLoadingRating = false;
  bool _isTogglingFavorite = false;
  bool _isReportingSpot = false;
  Uint8List? _selectedPhotoBytes;
  String? _selectedPhotoBase64;

  static const int _maxPhotoBytes = 500 * 1024;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  double _calculateDistance() {
    if (widget.userLocation == null) return 0;

    final lat1 = widget.userLocation!.latitude;
    final lon1 = widget.userLocation!.longitude;
    final lat2 = widget.poi.lat;
    final lon2 = widget.poi.lng;

    const double earthRadius = 6371; // Rayon terrestre en km
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);

    final a = (math.sin(dLat / 2) * math.sin(dLat / 2)) +
        (math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2));
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRad(double degree) => degree * 3.14159 / 180;

  void _submitRating() async {
    if (_myRating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez sélectionner une note')),
      );
      return;
    }

    setState(() => _isLoadingRating = true);

    try {
      final repo = ref.read(ratingRepositoryProvider);
      await repo.addRating(
        poiId: widget.poi.id,
        rating: _myRating,
        comment:
            _commentController.text.isEmpty ? null : _commentController.text,
        photoBase64: _selectedPhotoBase64,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Votre note a été enregistrée')),
      );
      setState(() {
        _myRating = 0;
        _commentController.clear();
        _selectedPhotoBytes = null;
        _selectedPhotoBase64 = null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoadingRating = false);
    }
  }

  Future<void> _pickRatingPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 85,
    );
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    if (bytes.lengthInBytes > _maxPhotoBytes) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image trop lourde (max 500 Ko).')),
      );
      return;
    }

    setState(() {
      _selectedPhotoBytes = bytes;
      _selectedPhotoBase64 = base64Encode(bytes);
    });
  }

  Uint8List? _safeDecodeBase64(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      return base64Decode(value);
    } catch (_) {
      return null;
    }
  }

  Future<void> _openMapsNavigation() async {
    if (widget.userLocation == null) return;
    
    // Utiliser directement l'app picker de navigation
    // sans passer par NavigationPage (OSM migration)
    final dest = LatLng(widget.poi.lat, widget.poi.lng);
    await showNavigationAppPicker(
      context: context,
      destination: dest,
      destinationName: widget.poi.displayName,
      onAllSpotsNavigation: () async {
        if (!mounted) return;
        // Navigation simplicité: afficher un snackbar au lieu d'une page complète
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Navigation vers ${widget.poi.displayName}\nLat: ${dest.latitude.toStringAsFixed(4)}\nLng: ${dest.longitude.toStringAsFixed(4)}',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      },
    );
  }

  Future<void> _addToRoadTrip() async {
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
      widget.poi,
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
          SnackBar(
            content: Text('Limite de $maxItems spots atteinte'),
          ),
        );
        break;
    }
  }

  Future<void> _submitSpotReport({
    required String reason,
    required String details,
  }) async {
    if (_isReportingSpot) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connectez-vous pour signaler un spot.')),
      );
      return;
    }

    setState(() => _isReportingSpot = true);
    try {
      await FirebaseFirestore.instance.collection('spot_reports').add({
        'spotId': widget.poi.id,
        'spotName': widget.poi.displayName,
        'spotCategory': widget.poi.category.name,
        'departmentCode': widget.poi.departmentCode,
        'lat': widget.poi.lat,
        'lng': widget.poi.lng,
        'reason': reason,
        'details': details.trim(),
        'status': 'open',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'reporterId': user.uid,
        'reporterEmail': user.email,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Signalement envoyé à l\'administration.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur envoi signalement: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isReportingSpot = false);
      }
    }
  }

  Future<void> _showReportSpotDialog() async {
    final detailsController = TextEditingController();
    String selectedReason = 'Lieu inexistant';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Signaler ce spot'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedReason,
                  decoration: const InputDecoration(
                    labelText: 'Raison',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'Lieu inexistant',
                      child: Text('Lieu inexistant'),
                    ),
                    DropdownMenuItem(
                      value: 'Informations incorrectes',
                      child: Text('Informations incorrectes'),
                    ),
                    DropdownMenuItem(
                      value: 'Doublon',
                      child: Text('Doublon'),
                    ),
                    DropdownMenuItem(
                      value: 'Autre',
                      child: Text('Autre'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() {
                      selectedReason = value;
                    });
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: detailsController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Détails (optionnel)',
                    hintText: 'Ex: fermé définitivement, adresse erronée...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Annuler'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Envoyer'),
              ),
            ],
          ),
        );
      },
    );

    if (confirmed == true) {
      await _submitSpotReport(
        reason: selectedReason,
        details: detailsController.text,
      );
    }
    detailsController.dispose();
  }

  void _toggleFavorite(
      BuildContext context, WidgetRef ref, bool isFavorite) async {
    if (_isTogglingFavorite) return;

    final user = ref.read(authStateProvider).value;
    if (user == null) return;

    setState(() {
      _isTogglingFavorite = true;
    });

    try {
      if (isFavorite) {
        await FirebaseFirestore.instance
            .collection('profiles')
            .doc(user.uid)
            .update({
          'favoritePoiIds': FieldValue.arrayRemove([widget.poi.id]),
        });
        await FirebaseFirestore.instance
            .collection('profiles')
            .doc(user.uid)
            .collection('favoritePois')
            .doc(widget.poi.id)
            .delete();
      } else {
        await FirebaseFirestore.instance
            .collection('profiles')
            .doc(user.uid)
            .update({
          'favoritePoiIds': FieldValue.arrayUnion([widget.poi.id]),
        });
        await FirebaseFirestore.instance
            .collection('profiles')
            .doc(user.uid)
            .collection('favoritePois')
            .doc(widget.poi.id)
            .set({
          'name': widget.poi.displayName,
          'imageUrls': widget.poi.imageUrls,
          'googleRating': widget.poi.googleRating,
          'googleRatingCount': widget.poi.googleRatingCount,
          'description': widget.poi.shortDescription,
          'lat': widget.poi.lat,
          'lng': widget.poi.lng,
          'category': widget.poi.category.name,
          'subCategory': widget.poi.subCategory,
          'source': widget.poi.source,
          'updatedAt': Timestamp.now(),
        });
      }
    } catch (e) {
      debugPrint('Erreur: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isTogglingFavorite = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final distance = _calculateDistance();
    final ratingsAsync = ref.watch(ratingsForPoiProvider(widget.poi.id));
    final avgRatingsAsync = ref.watch(averageRatingsProvider(widget.poi.id));
    final profile = ref.watch(profileStreamProvider);
    final isFavorite =
        profile.value?.favoritePoiIds.contains(widget.poi.id) ?? false;
    final googleRating = widget.poi.googleRating ?? 0;
    final hasGoogleReviews = widget.poi.source == 'places';
    final subCategoryLabel = formatPoiSubCategory(widget.poi.subCategory);
    final headerTitle =
      subCategoryLabel.isNotEmpty ? subCategoryLabel : widget.poi.category.label;

    return Scaffold(
      appBar: GlassAppBar(
        titleWidget: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            headerTitle.toUpperCase(),
            maxLines: 1,
            softWrap: false,
          ),
        ),
        showBackButton: true,
        actions: [
          IconButton(
            icon: _isTogglingFavorite
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.grey,
                    ),
                  )
                : Icon(
                    isFavorite ? Icons.favorite : Icons.favorite_border,
                    color: isFavorite ? Colors.red : Colors.grey,
                  ),
            onPressed: _isTogglingFavorite
                ? null
                : () {
                    _toggleFavorite(context, ref, isFavorite);
                  },
          ),
        ],
      ),
      body: ListView(
        children: [
          // En-tête avec catégorie et distance
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.blue.shade50,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: widget.poi.category.color,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            iconForSubCategory(
                              widget.poi.subCategory,
                              widget.poi.category,
                            ),
                            size: 14,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            widget.poi.category.label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Icon(Icons.location_on, color: Colors.blue.shade700),
                    const SizedBox(width: 4),
                    Text(
                      '${distance.toStringAsFixed(1)} km',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  widget.poi.displayName,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.poi.shortDescription,
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          if (widget.poi.imageUrls.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Center(
                child: SizedBox(
                  height: context.imageHeight,
                  child: PageView.builder(
                    itemCount: widget.poi.imageUrls.length,
                    controller: PageController(viewportFraction: 0.9),
                    itemBuilder: (context, index) {
                      final url = widget.poi.imageUrls[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: OptimizedNetworkImage(
                            imageUrl: url,
                            height: context.imageHeight,
                            fit: BoxFit.cover,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: ratingsAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (err, _) => const SizedBox.shrink(),
                data: (ratings) {
                  final photoBytes = ratings
                      .map((r) => _safeDecodeBase64(r.photoBase64))
                      .whereType<Uint8List>()
                      .toList();
                  if (photoBytes.isEmpty) return const SizedBox.shrink();

                  return Center(
                    child: SizedBox(
                      height: context.imageHeight,
                      child: PageView.builder(
                        itemCount: photoBytes.length,
                        controller: PageController(viewportFraction: 0.9),
                        itemBuilder: (context, index) {
                          final bytes = photoBytes[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.memory(
                                bytes,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    color: Colors.grey.shade200,
                                    child: const Icon(Icons.broken_image),
                                  );
                                },
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),

          if (hasGoogleReviews)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Text(
                        'Note Google',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (googleRating > 0) ...[
                        _buildStarRating(googleRating, editable: false),
                        const SizedBox(height: 6),
                        Text(
                          '${googleRating.toStringAsFixed(1)}/5',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ] else
                        const Text(
                          'Aucun avis Google pour le moment',
                          style: TextStyle(color: Colors.grey),
                        ),
                    ],
                  ),
                ),
              ),
            ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: avgRatingsAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (err, _) => const Text('Erreur chargement notes'),
                  data: (avgRatings) {
                    final userRating = avgRatings['user'] ?? 0;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Text(
                          'Avis AllSPOTS',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (userRating > 0) ...[
                          _buildStarRating(userRating, editable: false),
                          const SizedBox(height: 6),
                          Text(
                            '${userRating.toStringAsFixed(1)}/5',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ] else
                          const Text(
                            'Aucun avis AllSPOTS pour le moment',
                            style: TextStyle(color: Colors.grey),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),

          // GPS et navigation
          if (widget.userLocation != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _openMapsNavigation,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.navigation),
                  label: const Text(
                    'Voir la route',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _addToRoadTrip,
                icon: const Icon(Icons.route),
                label: const Text('Ajouter au road trip'),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isReportingSpot ? null : _showReportSpotDialog,
                icon: _isReportingSpot
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.flag_outlined),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.orange.shade800,
                ),
                label: const Text('Signaler ce spot'),
              ),
            ),
          ),

          // Votre note
          if (profile.hasValue && profile.value != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Votre note',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildStarRating(_myRating, editable: true),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _pickRatingPhoto,
                              icon: const Icon(Icons.photo_camera),
                              label: Text(
                                _selectedPhotoBytes == null
                                    ? 'Ajouter une photo'
                                    : 'Changer la photo',
                              ),
                            ),
                          ),
                          if (_selectedPhotoBytes != null) ...[
                            const SizedBox(width: 12),
                            IconButton(
                              onPressed: () {
                                setState(() {
                                  _selectedPhotoBytes = null;
                                  _selectedPhotoBase64 = null;
                                });
                              },
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ],
                      ),
                      if (_selectedPhotoBytes != null) ...[
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            _selectedPhotoBytes!,
                            height: 160,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextField(
                        controller: _commentController,
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: 'Ajouter un commentaire...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoadingRating ? null : _submitRating,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                          ),
                          child: _isLoadingRating
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white),
                                  ),
                                )
                              : const Text(
                                  'Enregistrer ma note',
                                  style: TextStyle(color: Colors.white),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Avis des utilisateurs
          Padding(
            padding: const EdgeInsets.all(16),
            child: ratingsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => const SizedBox.shrink(),
              data: (ratings) {
                if (ratings.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: Text(
                        'Aucun avis pour le moment',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: ratings.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (_, idx) {
                    final rating = ratings[idx];
                    return _RatingTile(rating: rating);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStarRating(double rating, {required bool editable}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final starIndex = index + 1;
        final isFilled = starIndex <= rating;

        return GestureDetector(
          onTap: editable
              ? () => setState(() => _myRating = starIndex.toDouble())
              : null,
          child: Icon(
            isFilled ? Icons.star : Icons.star_border,
            color: Colors.amber,
            size: editable ? 28 : 20,
          ),
        );
      }),
    );
  }
}

class _RatingTile extends StatelessWidget {
  final RatingData rating;

  const _RatingTile({required this.rating});

  @override
  Widget build(BuildContext context) {
    final photoBytes = _safeDecodeBase64(rating.photoBase64);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(
                            5,
                            (i) => Icon(
                              i < rating.rating.toInt()
                                  ? Icons.star
                                  : Icons.star_border,
                              color: Colors.amber,
                              size: 16,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${rating.rating.toStringAsFixed(1)}/5',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (rating.isGoogleRating)
                      const Text(
                        'Note Google',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      )
                    else
                      InkWell(
                        onTap: () {
                          if (rating.userId.isEmpty) return;
                          context.push('/users/${rating.userId}');
                        },
                        child: Text(
                          'Voir le profil public',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                _formatDate(rating.timestamp),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          if (rating.comment != null && rating.comment!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              rating.comment!,
              style: const TextStyle(fontSize: 13),
            ),
          ],
          if (photoBytes != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                photoBytes,
                height: 140,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Uint8List? _safeDecodeBase64(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      return base64Decode(value);
    } catch (_) {
      return null;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 60) {
      return 'il y a ${diff.inMinutes}m';
    } else if (diff.inHours < 24) {
      return 'il y a ${diff.inHours}h';
    } else if (diff.inDays < 7) {
      return 'il y a ${diff.inDays}j';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}
