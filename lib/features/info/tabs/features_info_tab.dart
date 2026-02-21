import 'package:flutter/material.dart';

class FeaturesInfoTab extends StatelessWidget {
  const FeaturesInfoTab({super.key});

  @override
  Widget build(BuildContext context) {
    const items = <_FeatureItem>[
      _FeatureItem(
        icon: Icons.place,
        title: 'Découvrir des spots',
        body: 'Explorez des spots proches de vous avec la carte interactive et la géolocalisation.',
      ),
      _FeatureItem(
        icon: Icons.search,
        title: 'Rechercher et filtrer',
        body: 'Filtrez les spots par catégorie, distance et type pour trouver rapidement ce qui vous intéresse.',
      ),
      _FeatureItem(
        icon: Icons.map,
        title: 'Navigation vers un spot',
        body: 'Lancez un itinéraire vers un spot avec AllSpots Navigation ou une app externe (Waze, Google Maps…).',
      ),
      _FeatureItem(
        icon: Icons.route,
        title: 'Road trip personnalisé',
        body: 'Ajoutez vos spots favoris dans votre road trip pour préparer vos sorties.',
      ),
      _FeatureItem(
        icon: Icons.rate_review,
        title: 'Avis et notes',
        body: 'Consultez les notes Google et laissez vos avis AllSPOTS sur les spots visités.',
      ),
      _FeatureItem(
        icon: Icons.favorite_border,
        title: 'Favoris',
        body: 'Enregistrez les spots que vous aimez pour les retrouver rapidement dans votre profil.',
      ),
      _FeatureItem(
        icon: Icons.groups,
        title: 'Spots communautaires',
        body: 'Participez à la communauté en consultant et publiant des spots utiles.',
      ),
      _FeatureItem(
        icon: Icons.workspace_premium,
        title: 'Pass Premium',
        body: 'Profitez d’avantages supplémentaires selon votre niveau d’accès.',
      ),
      _FeatureItem(
        icon: Icons.notifications_active_outlined,
        title: 'Notifications utiles',
        body: 'Restez informé des nouveautés et activités importantes liées à vos spots.',
      ),
      _FeatureItem(
        icon: Icons.star_outline,
        title: 'Progression utilisateur',
        body: 'Gagnez de l’XP au fil de vos découvertes et interactions.',
      ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      children: [
        const _TitleBlock(
          title: 'Fonctionnalités',
          subtitle: 'Voici les principales fonctionnalités de AllSpots.',
        ),
        const SizedBox(height: 10),
        ...items.map((it) => _FeatureCard(item: it)),
        const SizedBox(height: 18),
        const _Footer(),
      ],
    );
  }
}

class _FeatureItem {
  final IconData icon;
  final String title;
  final String body;

  const _FeatureItem({required this.icon, required this.title, required this.body});
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({required this.item});

  final _FeatureItem item;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(item.icon, color: Theme.of(context).colorScheme.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.body,
                    style: TextStyle(color: Colors.grey[700], fontSize: 13, height: 1.25),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(subtitle, style: TextStyle(color: Colors.grey[700], fontSize: 13)),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    final year = DateTime.now().year;
    return Center(
      child: Text(
        '© $year AllSpots',
        style: TextStyle(color: Colors.grey[600], fontSize: 12),
      ),
    );
  }
}
