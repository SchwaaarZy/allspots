import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class RatingData {
  final String id;
  final String userId;
  final String poiId;
  final double rating;
  final String? comment;
  final String? photoBase64;
  final DateTime timestamp;
  final bool isGoogleRating;

  RatingData({
    required this.id,
    required this.userId,
    required this.poiId,
    required this.rating,
    this.comment,
    this.photoBase64,
    required this.timestamp,
    this.isGoogleRating = false,
  });

  Map<String, dynamic> toMap() => {
    'userId': userId,
    'poiId': poiId,
    'rating': rating,
    'comment': comment,
    'photoBase64': photoBase64,
    'timestamp': Timestamp.fromDate(timestamp),
    'isGoogleRating': isGoogleRating,
  };

  factory RatingData.fromMap(String id, Map<String, dynamic> data) {
    return RatingData(
      id: id,
      userId: data['userId'] ?? '',
      poiId: data['poiId'] ?? '',
      rating: (data['rating'] as num?)?.toDouble() ?? 0,
      comment: data['comment'],
      photoBase64: data['photoBase64'],
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isGoogleRating: data['isGoogleRating'] ?? false,
    );
  }
}

class RatingRepository {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // Ajouter une note pour un lieu
  Future<void> addRating({
    required String poiId,
    required double rating,
    String? comment,
    String? photoBase64,
    bool isGoogleRating = false,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Non authentifié');

    await _firestore
        .collection('poi_ratings')
        .add({
          'userId': uid,
          'poiId': poiId,
          'rating': rating,
          'comment': comment,
          'photoBase64': photoBase64,
          'timestamp': Timestamp.now(),
          'isGoogleRating': isGoogleRating,
        });
  }

  // Obtenir les notes d'un lieu
  Stream<List<RatingData>> getRatingsForPoi(String poiId) {
    return _firestore
        .collection('poi_ratings')
        .where('poiId', isEqualTo: poiId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs
                .map((doc) => RatingData.fromMap(doc.id, doc.data()))
                .toList());
  }

  // Obtenir la note moyenne d'un lieu
  Future<double> getAverageRating(String poiId) async {
    final snapshot = await _firestore
        .collection('poi_ratings')
        .where('poiId', isEqualTo: poiId)
        .get();

    if (snapshot.docs.isEmpty) return 0;

    final avg = snapshot.docs
            .map((doc) => (doc.data()['rating'] as num?)?.toDouble() ?? 0)
            .reduce((a, b) => a + b) /
        snapshot.docs.length;

    return avg;
  }

  // Obtenir la note moyenne séparée (Google vs Utilisateurs)
  Future<Map<String, double>> getAverageRatings(String poiId) async {
    final snapshot = await _firestore
        .collection('poi_ratings')
        .where('poiId', isEqualTo: poiId)
        .get();

    double googleAvg = 0;
    double userAvg = 0;
    int googleCount = 0;
    int userCount = 0;

    for (final doc in snapshot.docs) {
      final isGoogle = doc.data()['isGoogleRating'] ?? false;
      final rating = (doc.data()['rating'] as num?)?.toDouble() ?? 0;

      if (isGoogle) {
        googleAvg += rating;
        googleCount++;
      } else {
        userAvg += rating;
        userCount++;
      }
    }

    return {
      'google': googleCount > 0 ? googleAvg / googleCount : 0,
      'user': userCount > 0 ? userAvg / userCount : 0,
    };
  }

  // Supprimer une note (si c'est sa propre note)
  Future<void> deleteRating(String ratingId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Non authentifié');

    await _firestore.collection('poi_ratings').doc(ratingId).delete();
  }
}

// Providers Riverpod
final ratingRepositoryProvider = Provider((ref) => RatingRepository());

final ratingsForPoiProvider =
    StreamProvider.family<List<RatingData>, String>((ref, poiId) {
  final repo = ref.watch(ratingRepositoryProvider);
  return repo.getRatingsForPoi(poiId);
});

final averageRatingProvider =
    FutureProvider.family<double, String>((ref, poiId) async {
  final repo = ref.watch(ratingRepositoryProvider);
  return repo.getAverageRating(poiId);
});

final averageRatingsProvider =
    FutureProvider.family<Map<String, double>, String>((ref, poiId) async {
  final repo = ref.watch(ratingRepositoryProvider);
  return repo.getAverageRatings(poiId);
});
