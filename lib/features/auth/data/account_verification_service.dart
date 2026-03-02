import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AccountVerificationService {
  const AccountVerificationService._();

  static const Duration verificationGracePeriod = Duration(hours: 24);

  static DateTime? accountCreationDate(User user) {
    return user.metadata.creationTime;
  }

  static DateTime? verificationDeadline(User user) {
    final createdAt = accountCreationDate(user);
    if (createdAt == null) return null;
    return createdAt.add(verificationGracePeriod);
  }

  static Future<void> ensureVerificationMetadata(User user) async {
    final profileRef = FirebaseFirestore.instance.collection('profiles').doc(user.uid);

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final snap = await transaction.get(profileRef);
      final data = snap.data() ?? <String, dynamic>{};

      final createdAt = accountCreationDate(user);
      final deadline = verificationDeadline(user);
      final role = (data['role'] as String?)?.toLowerCase();
      final isAdmin = (data['isAdmin'] as bool?) == true || role == 'admin';
      final hasPhone = user.phoneNumber != null && user.phoneNumber!.trim().isNotEmpty;
      final isVerified = isAdmin || hasPhone;

      final updates = <String, dynamic>{
        'isPhoneVerified': data['isPhoneVerified'] ?? isVerified,
        'phoneVerificationStatus': data['phoneVerificationStatus'] ?? (isVerified ? 'verified' : 'pending'),
        'phoneVerificationDeadlineAt':
            data['phoneVerificationDeadlineAt'] ??
            (deadline != null ? Timestamp.fromDate(deadline) : FieldValue.serverTimestamp()),
        'accountCreatedAt':
            data['accountCreatedAt'] ??
            (createdAt != null ? Timestamp.fromDate(createdAt) : FieldValue.serverTimestamp()),
      };

      final existingPhoneRaw = data['phoneNumber'];
      final existingPhone = existingPhoneRaw is String ? existingPhoneRaw : '';
      if (existingPhone.isEmpty && user.phoneNumber != null) {
        updates['phoneNumber'] = user.phoneNumber;
      }

      if (isVerified) {
        updates['phoneVerifiedAt'] = data['phoneVerifiedAt'] ?? FieldValue.serverTimestamp();
      }

      transaction.set(profileRef, updates, SetOptions(merge: true));
    });
  }

  static Future<void> markCodeSent({
    required User user,
    required String phoneNumber,
  }) {
    return FirebaseFirestore.instance.collection('profiles').doc(user.uid).set(
      {
        'phoneNumber': phoneNumber,
        'phoneVerificationStatus': 'code_sent',
        'lastSmsSentAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  static Future<void> markPhoneVerified({
    required User user,
    required String phoneNumber,
  }) {
    return FirebaseFirestore.instance.collection('profiles').doc(user.uid).set(
      {
        'phoneNumber': phoneNumber,
        'isPhoneVerified': true,
        'phoneVerificationStatus': 'verified',
        'phoneVerifiedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }
}
