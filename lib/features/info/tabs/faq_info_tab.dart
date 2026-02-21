import 'package:flutter/material.dart';

class FaqInfoTab extends StatelessWidget {
  const FaqInfoTab({super.key});

  @override
  Widget build(BuildContext context) {
    const items = <_FaqItem>[
      _FaqItem(
        q: 'Comment trouver des spots près de moi ?',
        a: 'Depuis la page carte, AllSpots affiche automatiquement les spots autour de votre position.',
      ),
      _FaqItem(
        q: 'Comment rechercher un spot précis ?',
        a: 'Allez dans l’onglet Recherche et utilisez les filtres par catégorie et proximité.',
      ),
      _FaqItem(
        q: 'Comment lancer la navigation vers un spot ?',
        a: 'Dans le détail du spot, appuyez sur "Voir la route" puis choisissez AllSpots Navigation ou une app externe.',
      ),
      _FaqItem(
        q: 'Puis-je utiliser une autre app de navigation ?',
        a: 'Oui, si Waze, Google Maps ou Apple Plans est installé, vous pouvez la sélectionner dans la bulle de choix.',
      ),
      _FaqItem(
        q: 'Comment ajouter un spot à mon road trip ?',
        a: 'Depuis la fiche d’un spot, appuyez sur "Ajouter au road trip".',
      ),
      _FaqItem(
        q: 'Comment enregistrer mes spots préférés ?',
        a: 'Utilisez l’icône favoris sur la page détail d’un spot.',
      ),
      _FaqItem(
        q: 'Comment laisser un avis AllSPOTS ?',
        a: 'Dans le détail du spot, utilisez la section "Avis AllSPOTS" pour noter et commenter.',
      ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      children: [
        const _TitleBlock(
          title: 'FAQ',
          subtitle: 'Questions fréquentes sur AllSpots.',
        ),
        const SizedBox(height: 10),
        ...items.map((it) => _FaqCard(item: it)),
        const SizedBox(height: 18),
        const _Footer(),
      ],
    );
  }
}

class _FaqItem {
  final String q;
  final String a;
  const _FaqItem({required this.q, required this.a});
}

class _FaqCard extends StatelessWidget {
  const _FaqCard({required this.item});
  final _FaqItem item;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          title: Text(
            item.q,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                item.a,
                style: TextStyle(color: Colors.grey[700], fontSize: 13, height: 1.25),
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
