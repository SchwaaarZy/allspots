import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/poi_categories.dart';
import '../../../core/widgets/glass_app_bar.dart';
import '../../../core/utils/geo_utils.dart';

class CreateSpotPage extends StatefulWidget {
  const CreateSpotPage({super.key});

  @override
  State<CreateSpotPage> createState() => _CreateSpotPageState();
}

class _CreateSpotPageState extends State<CreateSpotPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _websiteController = TextEditingController();
  final _picker = ImagePicker();

  String _group = poiCategoryGroups.first.title;
  String _item = poiCategoryGroups.first.items.first;
  bool _isFree = false;
  bool _pmr = false;
  bool _kids = false;
  bool _openNow = false;
  bool _isSaving = false;

  Position? _position;
  Uint8List? _imageBytes;

  @override
  void initState() {
    super.initState();
    _refreshLocation();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _websiteController.dispose();
    super.dispose();
  }

  Future<void> _refreshLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (!mounted) return;
      setState(() => _position = position);
    } catch (_) {
      // No-op: location optional for now.
    }
  }

  Future<void> _pickImage() async {
    try {
      final image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (image == null) return;

      final bytes = await image.readAsBytes();
      if (!mounted) return;
      setState(() => _imageBytes = bytes);
    } catch (_) {
      // No-op: user can continue without image.
    }
  }

  Future<String?> _uploadImage(String spotId) async {
    return null;
  }

  Future<bool> _checkForNearbySpots(double lat, double lng) async {
    try {
      // Rayon: 50 mètres pour éviter doublons au même endroit
      const proximityThreshold = 50.0; // mètres
      
      final snapshot = await FirebaseFirestore.instance
          .collection('spots')
          .where('isPublic', isEqualTo: true)
          .limit(50)
          .get();

      for (final doc in snapshot.docs) {
        final spotLat = (doc['lat'] as num?)?.toDouble();
        final spotLng = (doc['lng'] as num?)?.toDouble();
        
        if (spotLat == null || spotLng == null) continue;
        
        final distance = GeoUtils.distanceMeters(
          lat1: lat,
          lon1: lng,
          lat2: spotLat,
          lon2: spotLng,
        );
        
        if (distance < proximityThreshold) {
          return true; // Un spot existe déjà à proximité
        }
      }
      return false; // Pas de spot à proximité
    } catch (e) {
      debugPrint('Erreur lors de la vérification: $e');
      return false;
    }
  }

  Future<void> _submit() async {
    if (_isSaving) return;
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;

    if (_position == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez obtenir votre localisation.')),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isSaving = true);

    try {
      // Vérifier s'il existe déjà un spot au même endroit
      final hasNearbySpot = await _checkForNearbySpots(
        _position!.latitude,
        _position!.longitude,
      );

      if (hasNearbySpot) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Un spot existe déjà à cet endroit.'),
            duration: Duration(seconds: 3),
          ),
        );
        setState(() => _isSaving = false);
        return;
      }

      final spotRef = FirebaseFirestore.instance.collection('spots').doc();
      final imageUrl = await _uploadImage(spotRef.id);

      final data = <String, dynamic>{
        'name': _nameController.text.trim(),
        'description': _descController.text.trim(),
        'categoryGroup': _group,
        'categoryItem': _item,
        'lat': _position?.latitude,
        'lng': _position?.longitude,
        'websiteUrl': _websiteController.text.trim().isEmpty
            ? null
            : _websiteController.text.trim(),
        'isFree': _isFree,
        'pmrAccessible': _pmr,
        'kidsFriendly': _kids,
        'openNow': _openNow,
        'imageUrls': imageUrl == null ? [] : [imageUrl],
        'createdBy': user.uid,
        'isPublic': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await spotRef.set(data);

      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erreur lors de la creation du spot.')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locationLabel = _position == null
        ? 'Localisation non detectee'
        : '${_position!.latitude.toStringAsFixed(5)}, '
            '${_position!.longitude.toStringAsFixed(5)}';

    return Scaffold(
      appBar: const GlassAppBar(title: 'Creer un spot', showBackButton: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Photo',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: CircleAvatar(
                        radius: 36,
                        backgroundImage: _imageBytes == null
                            ? null
                            : MemoryImage(_imageBytes!),
                        child: _imageBytes == null
                            ? const Icon(Icons.photo, size: 28)
                            : null,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _pickImage,
                        icon: const Icon(Icons.photo_library),
                        label: const Text('Ajouter une photo'),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Upload desactive (Storage payant).',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nom du spot',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Nom requis';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _descController,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _group,
                    decoration: const InputDecoration(
                      labelText: 'Categorie',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final group in poiCategoryGroups)
                        DropdownMenuItem(
                          value: group.title,
                          child: Text(group.title),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      final group = poiCategoryGroups
                          .firstWhere((g) => g.title == value);
                      setState(() {
                        _group = value;
                        _item = group.items.first;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _item,
                    decoration: const InputDecoration(
                      labelText: 'Sous-categorie',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final item in poiCategoryGroups
                          .firstWhere((g) => g.title == _group)
                          .items)
                        DropdownMenuItem(
                          value: item,
                          child: Text(item),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _item = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _websiteController,
                    decoration: const InputDecoration(
                      labelText: 'Site web (optionnel)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Localisation',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(locationLabel),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _refreshLocation,
                        child: const Text('Actualiser la localisation'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    SwitchListTile.adaptive(
                      title: const Text('Gratuit'),
                      value: _isFree,
                      onChanged: (value) => setState(() => _isFree = value),
                    ),
                    SwitchListTile.adaptive(
                      title: const Text('Accessible PMR'),
                      value: _pmr,
                      onChanged: (value) => setState(() => _pmr = value),
                    ),
                    SwitchListTile.adaptive(
                      title: const Text('Adapté aux enfants'),
                      value: _kids,
                      onChanged: (value) => setState(() => _kids = value),
                    ),
                    SwitchListTile.adaptive(
                      title: const Text('Ouvert maintenant'),
                      value: _openNow,
                      onChanged: (value) => setState(() => _openNow = value),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isSaving ? null : _submit,
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Publier le spot'),
            ),
          ],
        ),
      ),
    );
  }
}
