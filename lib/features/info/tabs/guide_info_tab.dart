import 'package:flutter/material.dart';

class GuideInfoTab extends StatelessWidget {
  const GuideInfoTab({super.key});

  @override
  Widget build(BuildContext context) {
    const sections = <_GuideSection>[
      _GuideSection(
        title: '1. Bien demarrer',
        icon: Icons.play_circle_outline,
        points: [
          'Activez la localisation pour afficher les spots proches.',
          'Completez votre profil pour profiter de toutes les fonctions.',
          'Depuis la carte, ajustez le rayon de recherche selon votre zone.',
        ],
      ),
      _GuideSection(
        title: '2. Trouver les meilleurs spots',
        icon: Icons.search,
        points: [
          'Utilisez Recherche pour filtrer par categorie et mots-cles.',
          'Ouvrez un spot pour voir les details, notes, photos et distance.',
          'Ajoutez en favoris les spots que vous voulez retrouver vite.',
        ],
      ),
      _GuideSection(
        title: '3. Construire vos road trips',
        icon: Icons.route,
        points: [
          'Version gratuite: 2 road trips max, 10 spots par road trip.',
          'Version premium: 5 road trips max, 10 spots par road trip.',
          'Vous pouvez selectionner les spots directement depuis la liste nearby.',
        ],
      ),
      _GuideSection(
        title: '4. Participer a la communaute',
        icon: Icons.groups,
        points: [
          'Laissez une note AllSPOTS et un commentaire apres votre visite.',
          'Ajoutez une photo a votre avis pour aider les autres utilisateurs.',
          'Signalez un spot incorrect ou un doublon depuis la fiche spot.',
        ],
      ),
      _GuideSection(
        title: '5. Conseils utiles',
        icon: Icons.lightbulb_outline,
        points: [
          'Si aucun spot ne s\'affiche: augmentez le rayon ou bougez la carte.',
          'Pensez a verifier votre connexion pour charger les donnees.',
          'Utilisez le bouton Terminer dans le mode selection road trip.',
        ],
      ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      children: [
        const _TitleBlock(
          title: 'Guide d\'utilisation',
          subtitle: 'Le parcours rapide pour bien utiliser AllSPOTS.',
        ),
        const SizedBox(height: 10),
        ...sections.map((section) => _GuideCard(section: section)),
        const SizedBox(height: 18),
        const _Footer(),
      ],
    );
  }
}

class _GuideSection {
  final String title;
  final IconData icon;
  final List<String> points;

  const _GuideSection({
    required this.title,
    required this.icon,
    required this.points,
  });
}

class _GuideCard extends StatelessWidget {
  const _GuideCard({required this.section});

  final _GuideSection section;

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
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                section.icon,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    section.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  ...section.points.map(
                    (point) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '- ',
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontSize: 13,
                              height: 1.25,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              point,
                              style: TextStyle(
                                color: Colors.grey[700],
                                fontSize: 13,
                                height: 1.25,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
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
        Text(title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
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
        '© $year AllSPOTS',
        style: TextStyle(color: Colors.grey[600], fontSize: 12),
      ),
    );
  }
}
