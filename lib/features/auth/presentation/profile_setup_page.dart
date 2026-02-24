import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/poi_categories.dart';
import '../../../core/widgets/glass_app_bar.dart';

class ProfileSetupPage extends StatefulWidget {
  const ProfileSetupPage({super.key});

  @override
  State<ProfileSetupPage> createState() => _ProfileSetupPageState();
}

class _ProfileSetupPageState extends State<ProfileSetupPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  final Set<String> _selectedCategories = {};
  final _picker = ImagePicker();

  String _photoUrl = '';
  Uint8List? _pickedImageBytes;

  Position? _position;
  bool _isLocating = false;

  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadExistingProfile();
    _refreshLocation();
  }

  Future<void> _loadExistingProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('profiles')
          .doc(user.uid)
          .get();
      final data = doc.data();
      if (data == null) return;

      setState(() {
        _nameController.text = (data['displayName'] as String?) ?? '';
        _photoUrl = (data['photoUrl'] as String?) ?? '';
        _bioController.text = (data['bio'] as String?) ?? '';

        final categoriesRaw = data['categories'];
        if (categoriesRaw is List) {
          _selectedCategories
            ..clear()
            ..addAll(categoriesRaw.whereType<String>());
        }
      });
    } catch (_) {
      // No-op: keep empty form when fetch fails.
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
      setState(() => _pickedImageBytes = bytes);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Impossible de charger la photo.');
    }
  }

  Future<String> _uploadProfilePhoto(String uid) async {
    return _photoUrl;
  }

  Future<void> _refreshLocation() async {
    setState(() {
      _isLocating = true;
      _error = null;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _error = 'Localisation desactivee sur l\'appareil.');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() => _error = 'Autorisation de localisation refusee.');
        return;
      }

      const settings = LocationSettings(
        accuracy: LocationAccuracy.high,
      );
      final position = await Geolocator.getCurrentPosition(
        locationSettings: settings,
      );

      setState(() => _position = position);
    } catch (_) {
      setState(() => _error = 'Impossible de recuperer la localisation.');
    } finally {
      if (mounted) {
        setState(() => _isLocating = false);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;

    if (_position == null) {
      await _refreshLocation();
      if (_position == null) return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _error = 'Utilisateur non connecte.');
        return;
      }

      final docRef =
          FirebaseFirestore.instance.collection('profiles').doc(user.uid);
      final existing = await docRef.get();

      final photoUrl = await _uploadProfilePhoto(user.uid);

      final position = _position;
      final locationLabel = position == null
          ? ''
          : '${position.latitude.toStringAsFixed(5)}, '
              '${position.longitude.toStringAsFixed(5)}';

      final data = <String, dynamic>{
        'displayName': _nameController.text.trim(),
        'photoUrl': photoUrl,
        'bio': _bioController.text.trim(),
        'location': locationLabel,
        'locationLat': position?.latitude,
        'locationLng': position?.longitude,
        'categories': _selectedCategories.toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (!existing.exists) {
        data['createdAt'] = FieldValue.serverTimestamp();
        data['xp'] = 0;
        data['totalVisits'] = 0;
        data['uniqueVisitedSpots'] = 0;
      }

      await docRef.set(data, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      setState(() => _error = e.message ?? 'Erreur lors de la sauvegarde.');
    } catch (_) {
      setState(() => _error = 'Une erreur est survenue.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  bool _isGroupSelected(PoiCategoryGroup group) {
    return group.items.every((item) => _selectedCategories.contains(item));
  }

  @override
  Widget build(BuildContext context) {
    final photoUrl = _photoUrl.trim();
    final locationText = _position == null
        ? 'Localisation non detectee'
        : '${_position!.latitude.toStringAsFixed(5)}, '
            '${_position!.longitude.toStringAsFixed(5)}';
    final imageProvider = _pickedImageBytes != null
        ? MemoryImage(_pickedImageBytes!)
        : (photoUrl.isEmpty ? null : NetworkImage(photoUrl));

    return Scaffold(
      appBar:
          const GlassAppBar(title: 'Creer votre profil', showBackButton: true),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: CircleAvatar(
                    radius: 36,
                    backgroundImage: imageProvider as ImageProvider<Object>?,
                    child: imageProvider == null
                        ? const Icon(Icons.person, size: 36)
                        : null,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.photo_camera),
                    label: Text(
                      photoUrl.isEmpty && _pickedImageBytes == null
                          ? 'Ajouter une photo'
                          : 'Changer la photo',
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Upload desactive (Storage payant).',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 16),
                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Pseudo',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Pseudo requis';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _bioController,
                        minLines: 3,
                        maxLines: 5,
                        decoration: const InputDecoration(
                          labelText: 'Bio',
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
                          'Localisation automatique',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Text(locationText),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: _isLocating ? null : _refreshLocation,
                            child: Text(
                              _isLocating
                                  ? 'Detection en cours...'
                                  : 'Actualiser la localisation',
                            ),
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Preferences de spots',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 10),
                        for (final group in poiCategoryGroups) ...[
                          // En-tête du groupe avec checkbox
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Text(
                              group.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                            value: _isGroupSelected(group),
                            onChanged: (selected) {
                              setState(() {
                                if (selected == true) {
                                  // Ajouter tous les items du groupe
                                  _selectedCategories.addAll(group.items);
                                } else {
                                  // Retirer tous les items du groupe
                                  _selectedCategories.removeAll(group.items);
                                }
                              });
                            },
                          ),
                          // Sous-catégories du groupe (indentées)
                          Padding(
                            padding: const EdgeInsets.only(left: 16),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final isNarrow = constraints.maxWidth < 340;
                                final itemWidth = isNarrow
                                    ? constraints.maxWidth
                                    : (constraints.maxWidth - 12) / 2;

                                return Wrap(
                                  spacing: 12,
                                  runSpacing: 4,
                                  children: [
                                    for (final item in group.items)
                                      SizedBox(
                                        width: itemWidth,
                                        child: CheckboxListTile(
                                          contentPadding: EdgeInsets.zero,
                                          dense: true,
                                          visualDensity:
                                              VisualDensity.compact,
                                          title: Text(
                                            item,
                                            style:
                                                const TextStyle(fontSize: 11),
                                          ),
                                          value: _selectedCategories
                                              .contains(item),
                                          onChanged: (selected) {
                                            setState(() {
                                              if (selected == true) {
                                                _selectedCategories.add(item);
                                              } else {
                                                _selectedCategories
                                                    .remove(item);
                                              }
                                            });
                                          },
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        const SizedBox(height: 4),
                      ],
                    ),
                  ),
                ),
                if (_error != null) ...[
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                  const SizedBox(height: 8),
                ],
                ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Enregistrer'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
