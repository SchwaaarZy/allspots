import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class UserProfile {
  const UserProfile({
    required this.displayName,
    required this.photoUrl,
    required this.bio,
    required this.location,
    required this.categories,
    required this.locationLat,
    required this.locationLng,
    this.hasPremiumPass = false,
    this.favoritePoiIds = const [],
  });

  final String displayName;
  final String photoUrl;
  final String bio;
  final String location;
  final List<String> categories;
  final double? locationLat;
  final double? locationLng;
  final bool hasPremiumPass;
  final List<String> favoritePoiIds;

  factory UserProfile.fromMap(Map<String, dynamic> data) {
    final categoriesRaw = data['categories'];
    final categories = categoriesRaw is List
        ? categoriesRaw.whereType<String>().toList()
        : <String>[];
    final lat = data['locationLat'];
    final lng = data['locationLng'];
    final favoritesRaw = data['favoritePoiIds'];
    final favorites = favoritesRaw is List
        ? favoritesRaw.whereType<String>().toList()
        : <String>[];

    return UserProfile(
      displayName: (data['displayName'] as String?) ?? '',
      photoUrl: (data['photoUrl'] as String?) ?? '',
      bio: (data['bio'] as String?) ?? '',
      location: (data['location'] as String?) ?? '',
      categories: categories,
      locationLat: lat is num ? lat.toDouble() : null,
      locationLng: lng is num ? lng.toDouble() : null,
      hasPremiumPass: (data['hasPremiumPass'] as bool?) ?? false,
      favoritePoiIds: favorites,
    );
  }
}

final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

final profileStreamProvider = StreamProvider<UserProfile?>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) {
    return const Stream.empty();
  }

  return FirebaseFirestore.instance
      .collection('profiles')
      .doc(user.uid)
      .snapshots()
      .map((doc) {
    if (!doc.exists || doc.data() == null) {
      return null;
    }
    return UserProfile.fromMap(doc.data()!);
  });
});
