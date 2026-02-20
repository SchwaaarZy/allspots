import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/widgets/glass_app_bar.dart';
import '../../map/domain/poi_category.dart';

class CommunitySpotsManagementPage extends StatefulWidget {
  const CommunitySpotsManagementPage({super.key});

  @override
  State<CommunitySpotsManagementPage> createState() =>
      _CommunitySpotsManagementPageState();
}

class _CommunitySpotsManagementPageState
    extends State<CommunitySpotsManagementPage> {
  Future<void> _deleteSpot(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> spotDoc,
  ) async {
    final data = spotDoc.data();
    final spotName = (data['name'] as String?)?.trim();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Supprimer ce spot ?'),
        content: Text(
          'Le spot "${spotName?.isNotEmpty == true ? spotName : 'Sans nom'}" sera supprimé définitivement.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await spotDoc.reference.delete();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Spot supprimé')),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erreur lors de la suppression du spot.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GlassAppBar(
        title: 'Spots communauté',
        showBackButton: true,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('spots')
            .orderBy('updatedAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const Center(
              child: Text('Aucun spot créé par la communauté.'),
            );
          }

          final grouped = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
          for (final doc in docs) {
            final data = doc.data();
            final category = (data['categoryGroup'] as String?)?.trim();
            final key = (category == null || category.isEmpty) ? 'Autres' : category;
            grouped.putIfAbsent(key, () => []).add(doc);
          }

          final categories = grouped.keys.toList()..sort((a, b) => a.compareTo(b));

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.groups),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${docs.length} spots • ${categories.length} catégories',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              for (final category in categories)
                Card(
                  child: ExpansionTile(
                    initiallyExpanded: true,
                    leading: Icon(
                      poiCategoryFromString(category).icon,
                      color: poiCategoryFromString(category).color,
                    ),
                    title: Text(category),
                    subtitle: Text('${grouped[category]!.length} spots'),
                    children: [
                      for (final spotDoc in grouped[category]!)
                        ListTile(
                          title: Text(
                            ((spotDoc.data()['name'] as String?)?.trim().isNotEmpty ?? false)
                                ? (spotDoc.data()['name'] as String).trim()
                                : 'Sans nom',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            (spotDoc.data()['description'] as String?)?.trim().isNotEmpty == true
                                ? (spotDoc.data()['description'] as String).trim()
                                : 'Sans description',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: IconButton(
                            tooltip: 'Supprimer',
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: () => _deleteSpot(context, spotDoc),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
