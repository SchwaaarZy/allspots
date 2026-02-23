import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Service pour gérer les limites de création de spots
/// - Utilisateur normal: 2 spots max
/// - Premium: jusqu'à 10 spots
/// - Après expiration du premium: spots supplémentaires deviennent non-modifiables
class SpotCreationService {
  static const int normalUserLimit = 2;
  static const int premiumUserLimit = 10;

  /// Vérifie si l'utilisateur peut créer un nouveau spot
  static Future<SpotCreationResult> canCreateSpot({
    required String userId,
    required bool hasPremiumPass,
    required DateTime? premiumExpiryDate,
  }) async {
    try {
      // Compter les spots créés par cet utilisateur
      final userSpotsSnapshot = await FirebaseFirestore.instance
          .collection('spots')
          .where('createdBy', isEqualTo: userId)
          .get();

      final totalSpots = userSpotsSnapshot.docs.length;

      // Déterminer la limite applicable
      bool isPremiumActive = false;
      if (hasPremiumPass && premiumExpiryDate != null) {
        isPremiumActive = premiumExpiryDate.isAfter(DateTime.now());
      }

      final limit = isPremiumActive ? premiumUserLimit : normalUserLimit;

      debugPrint('[SpotCreation] User: $userId, Spots: $totalSpots, '
          'Limit: $limit, PremiumActive: $isPremiumActive');

      if (totalSpots >= limit) {
        final message = isPremiumActive
            ? 'Limite premium atteinte ($limit spots)'
            : 'Limite gratuite atteinte ($limit spots). Prenez le pass premium pour en créer plus!';
        
        return SpotCreationResult(
          canCreate: false,
          message: message,
          spotsCount: totalSpots,
          limit: limit,
          isPremiumActive: isPremiumActive,
        );
      }

      return SpotCreationResult(
        canCreate: true,
        message: 'Vous pouvez créer ce spot',
        spotsCount: totalSpots,
        limit: limit,
        isPremiumActive: isPremiumActive,
      );
    } catch (e) {
      debugPrint('[SpotCreation] Erreur: $e');
      return SpotCreationResult(
        canCreate: false,
        message: 'Erreur lors de la vérification',
        spotsCount: 0,
        limit: normalUserLimit,
        isPremiumActive: false,
      );
    }
  }

  /// Détermine si un spot peut être édité
  /// Les spots créés au-delà de la limite gratuite deviennent non-modifiables
  /// si le premium a expiré
  static Future<bool> canEditSpot({
    required String spotId,
    required String userId,
    required bool hasPremiumPass,
    required DateTime? premiumExpiryDate,
  }) async {
    try {
      final spotDoc = await FirebaseFirestore.instance
          .collection('spots')
          .doc(spotId)
          .get();

      if (!spotDoc.exists || spotDoc['createdBy'] != userId) {
        return false; // N'est pas le créateur
      }

      // Vérifier si premium est actif
      bool isPremiumActive = false;
      if (hasPremiumPass && premiumExpiryDate != null) {
        isPremiumActive = premiumExpiryDate.isAfter(DateTime.now());
      }

      // Compter quel numéro de spot c'est
      final userSpotsSnapshot = await FirebaseFirestore.instance
          .collection('spots')
          .where('createdBy', isEqualTo: userId)
          .orderBy('createdAt', descending: false)
          .get();

      final spotIndex = userSpotsSnapshot.docs.indexWhere((doc) => doc.id == spotId);

      // Si le spot est dans la limite gratuite (premiers 2), il peut toujours être édité
      if (spotIndex < normalUserLimit) {
        return true;
      }

      // Si le spot dépasse la limite gratuite, il ne peut être édité que si le
      // premium est actif
      return isPremiumActive;
    } catch (e) {
      debugPrint('[SpotEdit] Erreur: $e');
      return false;
    }
  }

  /// Obtient un message pour informer l'utilisateur
  static String getSpotEditMessage(bool canEdit, bool isPremiumActive) {
    if (!canEdit && !isPremiumActive) {
      return '⚠️ Ce spot a été créé avec votre pass premium. '
          'Renouvelez votre abonnement pour le modifier.';
    }
    return '';
  }
}

/// Résultat de la vérification de création de spot
class SpotCreationResult {
  final bool canCreate;
  final String message;
  final int spotsCount;
  final int limit;
  final bool isPremiumActive;

  SpotCreationResult({
    required this.canCreate,
    required this.message,
    required this.spotsCount,
    required this.limit,
    required this.isPremiumActive,
  });
}
