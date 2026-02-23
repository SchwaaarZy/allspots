import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/data/xp_service.dart';

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
    this.premiumExpiryDate,
    this.favoritePoiIds = const [],
    this.xp = 0,
    this.totalVisits = 0,
    this.uniqueVisitedSpots = 0,
    this.isAdmin = false,
  });

  final String displayName;
  final String photoUrl;
  final String bio;
  final String location;
  final List<String> categories;
  final double? locationLat;
  final double? locationLng;
  final bool hasPremiumPass;
  final DateTime? premiumExpiryDate;
  final List<String> favoritePoiIds;
  final int xp;
  final int totalVisits;
  final int uniqueVisitedSpots;
  final bool isAdmin;

  GradeProgress get gradeProgress => XpService.gradeProgressForXp(xp);

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
    final xp = (data['xp'] as num?)?.toInt() ?? 0;
    final totalVisits = (data['totalVisits'] as num?)?.toInt() ?? 0;
    final uniqueVisitedSpots =
        (data['uniqueVisitedSpots'] as num?)?.toInt() ?? 0;
    
    // Extract premium expiry date
    DateTime? premiumExpiryDate;
    final expiryData = data['premiumExpiryDate'];
    if (expiryData is Timestamp) {
      premiumExpiryDate = expiryData.toDate();
    } else if (expiryData is DateTime) {
      premiumExpiryDate = expiryData;
    }

    return UserProfile(
      displayName: (data['displayName'] as String?) ?? '',
      photoUrl: (data['photoUrl'] as String?) ?? '',
      bio: (data['bio'] as String?) ?? '',
      location: (data['location'] as String?) ?? '',
      categories: categories,
      locationLat: lat is num ? lat.toDouble() : null,
      locationLng: lng is num ? lng.toDouble() : null,
      hasPremiumPass: (data['hasPremiumPass'] as bool?) ?? false,
      premiumExpiryDate: premiumExpiryDate,
      favoritePoiIds: favorites,
      xp: xp,
      totalVisits: totalVisits,
      uniqueVisitedSpots: uniqueVisitedSpots,
      isAdmin: (data['isAdmin'] as bool?) ?? false,
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

final publicProfileProvider =
    StreamProvider.family<UserProfile?, String>((ref, uid) {
  if (uid.isEmpty) {
    return const Stream.empty();
  }

  return FirebaseFirestore.instance
      .collection('profiles')
      .doc(uid)
      .snapshots()
      .map((doc) {
    if (!doc.exists || doc.data() == null) {
      return null;
    }
    return UserProfile.fromMap(doc.data()!);
  });
});
