import 'package:cloud_firestore/cloud_firestore.dart';

import '../../map/domain/poi.dart';

class GradeProgress {
  const GradeProgress({
    required this.level,
    required this.grade,
    required this.currentLevelXp,
    required this.requiredXpForNextLevel,
    required this.progress,
  });

  final int level;
  final String grade;
  final int currentLevelXp;
  final int requiredXpForNextLevel;
  final double progress;
}

class VisitXpResult {
  const VisitXpResult({
    required this.awarded,
    required this.message,
    this.pointsAwarded = 0,
    this.totalXp = 0,
    this.totalVisits = 0,
    this.uniqueVisitedSpots = 0,
  });

  final bool awarded;
  final String message;
  final int pointsAwarded;
  final int totalXp;
  final int totalVisits;
  final int uniqueVisitedSpots;
}

class XpService {
  static const int pointsPerVisit = 10;
  static const Duration visitCooldown = Duration(minutes: 30);

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static GradeProgress gradeProgressForXp(int xp) {
    final safeXp = xp < 0 ? 0 : xp;
    final level = (safeXp ~/ 100) + 1;
    final currentLevelXp = safeXp % 100;

    return GradeProgress(
      level: level,
      grade: _gradeForXp(safeXp),
      currentLevelXp: currentLevelXp,
      requiredXpForNextLevel: 100,
      progress: currentLevelXp / 100,
    );
  }

  static String _gradeForXp(int xp) {
    if (xp >= 1500) return 'Légende';
    if (xp >= 900) return 'Maître explorateur';
    if (xp >= 500) return 'Expert';
    if (xp >= 250) return 'Aventurier';
    if (xp >= 100) return 'Explorateur';
    return 'Novice';
  }

  static Future<VisitXpResult> registerVisit({
    required String uid,
    required Poi poi,
  }) async {
    // ❌ Refuser l'XP si l'utilisateur visite son propre spot
    if (poi.createdBy != null && poi.createdBy == uid) {
      return const VisitXpResult(
        awarded: false,
        message: 'Impossible de gagner XP sur vos propres spots',
      );
    }

    final profileRef = _firestore.collection('profiles').doc(uid);
    final visitRef = profileRef.collection('visitedSpots').doc(poi.id);

    return _firestore.runTransaction((tx) async {
      final now = DateTime.now();
      final profileSnap = await tx.get(profileRef);
      final visitSnap = await tx.get(visitRef);

      DateTime? lastVisitAt;
      int previousVisitCount = 0;
      if (visitSnap.exists) {
        final data = visitSnap.data()!;
        final ts = data['lastVisitAt'];
        if (ts is Timestamp) {
          lastVisitAt = ts.toDate();
        }
        previousVisitCount = (data['visitCount'] as num?)?.toInt() ?? 0;
      }

      if (lastVisitAt != null && now.difference(lastVisitAt) < visitCooldown) {
        final remaining = visitCooldown - now.difference(lastVisitAt);
        final minutes = remaining.inMinutes.clamp(1, 999);
        return VisitXpResult(
          awarded: false,
          message: 'Patientez encore $minutes min avant de revalider ce spot.',
        );
      }

      final profileData = profileSnap.data() ?? <String, dynamic>{};
      final currentXp = (profileData['xp'] as num?)?.toInt() ?? 0;
      final currentVisits = (profileData['totalVisits'] as num?)?.toInt() ?? 0;
      final currentUnique =
          (profileData['uniqueVisitedSpots'] as num?)?.toInt() ?? 0;

      final isFirstVisitForSpot = !visitSnap.exists;
      final newXp = currentXp + pointsPerVisit;
      final newVisits = currentVisits + 1;
      final newUnique = currentUnique + (isFirstVisitForSpot ? 1 : 0);

      tx.set(
          profileRef,
          {
            'xp': newXp,
            'totalVisits': newVisits,
            'uniqueVisitedSpots': newUnique,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));

      tx.set(
          visitRef,
          {
            'poiId': poi.id,
            'poiName': poi.displayName,
            'lat': poi.lat,
            'lng': poi.lng,
            'source': poi.source,
            'category': poi.category.name,
            'subCategory': poi.subCategory,
            'visitCount': previousVisitCount + 1,
            'firstVisitAt': visitSnap.exists
                ? (visitSnap.data()!['firstVisitAt'] ?? Timestamp.fromDate(now))
                : Timestamp.fromDate(now),
            'lastVisitAt': Timestamp.fromDate(now),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));

      return VisitXpResult(
        awarded: true,
        message: '+$pointsPerVisit XP gagnés',
        pointsAwarded: pointsPerVisit,
        totalXp: newXp,
        totalVisits: newVisits,
        uniqueVisitedSpots: newUnique,
      );
    });
  }
}
