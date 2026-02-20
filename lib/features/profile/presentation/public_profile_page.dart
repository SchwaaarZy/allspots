import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/glass_app_bar.dart';
import '../../auth/data/auth_providers.dart';

class PublicProfilePage extends ConsumerWidget {
  const PublicProfilePage({
    super.key,
    required this.userId,
  });

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(publicProfileProvider(userId));
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: const GlassAppBar(title: 'Profil public', showBackButton: true),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Erreur: $error')),
        data: (profile) {
          if (profile == null) {
            return const Center(child: Text('Profil introuvable'));
          }

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('spots')
                .where('createdBy', isEqualTo: userId)
                .snapshots(),
            builder: (context, spotsSnapshot) {
              final createdSpots = spotsSnapshot.data?.docs.length ?? 0;
              final grade = profile.gradeProgress;

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade600,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 42,
                          backgroundImage: profile.photoUrl.trim().isEmpty
                              ? null
                              : NetworkImage(profile.photoUrl.trim()),
                          child: profile.photoUrl.trim().isEmpty
                              ? const Icon(Icons.person, size: 42)
                              : null,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          profile.displayName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (profile.bio.trim().isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            profile.bio,
                            style: const TextStyle(color: Colors.white70),
                            textAlign: TextAlign.center,
                          ),
                        ],
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            'Niv. ${grade.level} • ${grade.grade}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (currentUid == userId) ...[
                          const SizedBox(height: 8),
                          const Text(
                            'C\'est votre profil public',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _PublicStatRow(
                            icon: Icons.auto_awesome,
                            label: 'XP total',
                            value: '${profile.xp}',
                          ),
                          const Divider(height: 20),
                          _PublicStatRow(
                            icon: Icons.flag,
                            label: 'Visites validées',
                            value: '${profile.totalVisits}',
                          ),
                          const Divider(height: 20),
                          _PublicStatRow(
                            icon: Icons.explore,
                            label: 'Spots uniques visités',
                            value: '${profile.uniqueVisitedSpots}',
                          ),
                          const Divider(height: 20),
                          _PublicStatRow(
                            icon: Icons.location_on,
                            label: 'Spots créés',
                            value: '$createdSpots',
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _PublicStatRow extends StatelessWidget {
  const _PublicStatRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.blue.shade700),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
