import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/models/region_model.dart';
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
  static const String _allValue = 'all';
  static const int _itemsPerPage = 50;

  String _selectedCountry = _allValue;
  String _selectedRegion = _allValue;
  String _selectedDepartment = _allValue;
  String _searchQuery = '';
  bool _filtersExpanded = false;
  int _currentPage = 0;

  late final Map<String, String> _countryCodeToName;
  late final Map<String, String> _regionCodeToName;
  late final Map<String, String> _departmentToRegionCode;

  @override
  void initState() {
    super.initState();
    _countryCodeToName = {
      for (final country in allCountries) country.code.toLowerCase(): country.name,
    };
    _regionCodeToName = {
      for (final country in allCountries)
        for (final region in country.regions) region.code: region.name,
    };
    _departmentToRegionCode = {
      for (final country in allCountries)
        for (final region in country.regions)
          for (final department in region.departments) department.code: region.code,
    };
  }

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

  Future<void> _resolveReport(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> reportDoc,
  ) async {
    try {
      await reportDoc.reference.update({
        'status': 'resolved',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Signalement marqué comme résolu')),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erreur lors de la mise à jour du signalement.')),
      );
    }
  }

  Future<void> _deleteSpotFromReport(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> reportDoc,
  ) async {
    final data = reportDoc.data();
    final spotId = (data['spotId'] as String?)?.trim();
    final spotName = (data['spotName'] as String?)?.trim();

    if (spotId == null || spotId.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Signalement invalide: spotId manquant.')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Supprimer ce spot ?'),
        content: Text(
          'Le spot "${spotName?.isNotEmpty == true ? spotName : spotId}" sera supprimé et le signalement sera clôturé.',
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
      await FirebaseFirestore.instance.collection('spots').doc(spotId).delete();
      await reportDoc.reference.update({
        'status': 'resolved',
        'adminAction': 'spot_deleted',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Spot supprimé et signalement traité')),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erreur lors de la suppression du spot.')),
      );
    }
  }

  String? _normalizeDepartmentCode(dynamic raw) {
    if (raw == null) return null;
    var code = raw.toString().trim().toUpperCase();
    if (code.isEmpty) return null;
    if (RegExp(r'^\d$').hasMatch(code)) {
      code = '0$code';
    }
    return code;
  }

  String? _extractDepartmentCode(Map<String, dynamic> data) {
    return _normalizeDepartmentCode(
      data['departmentCode'] ?? data['departementCode'] ?? data['dept'],
    );
  }

  String? _extractCountryCode(Map<String, dynamic> data) {
    final rawCountryCode = data['countryCode'];
    if (rawCountryCode is String && rawCountryCode.trim().isNotEmpty) {
      return rawCountryCode.trim().toLowerCase();
    }

    final rawCountry = data['country'];
    if (rawCountry is String && rawCountry.trim().isNotEmpty) {
      final normalized = rawCountry.trim().toLowerCase();
      if (normalized == 'france' || normalized == 'fr') {
        return 'fr';
      }
      return normalized;
    }

    if (_extractDepartmentCode(data) != null) {
      return 'fr';
    }
    return null;
  }

  String _extractCountryLabel(Map<String, dynamic> data) {
    final code = _extractCountryCode(data);
    if (code == null) {
      return 'Pays inconnu';
    }
    return _countryCodeToName[code] ?? code.toUpperCase();
  }

  String? _extractRegionCode(Map<String, dynamic> data) {
    final rawRegionCode = data['regionCode'];
    if (rawRegionCode is String && rawRegionCode.trim().isNotEmpty) {
      return rawRegionCode.trim();
    }

    final departmentCode = _extractDepartmentCode(data);
    if (departmentCode == null) return null;
    return _departmentToRegionCode[departmentCode];
  }

  String _extractRegionLabel(Map<String, dynamic> data) {
    final regionCode = _extractRegionCode(data);
    if (regionCode != null) {
      return _regionCodeToName[regionCode] ?? regionCode;
    }

    final rawRegion = data['region'];
    if (rawRegion is String && rawRegion.trim().isNotEmpty) {
      return rawRegion.trim();
    }
    return 'Région inconnue';
  }

  bool _matchesSearch(Map<String, dynamic> data) {
    if (_searchQuery.trim().isEmpty) return true;
    final query = _searchQuery.trim().toLowerCase();

    final values = [
      data['name'],
      data['description'],
      data['categoryGroup'],
      data['city'],
      data['country'],
      data['region'],
      _extractDepartmentCode(data),
      _extractRegionLabel(data),
      _extractCountryLabel(data),
    ];

    return values.any(
      (value) => value != null && value.toString().toLowerCase().contains(query),
    );
  }

  List<_FilterOption> _buildCountryOptions(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final counts = <String, int>{};
    for (final doc in docs) {
      final code = _extractCountryCode(doc.data()) ?? 'unknown';
      counts.update(code, (value) => value + 1, ifAbsent: () => 1);
    }

    final options = counts.entries
        .map(
          (entry) => _FilterOption(
            value: entry.key,
            label: entry.key == 'unknown'
                ? 'Pays inconnu'
                : (_countryCodeToName[entry.key] ?? entry.key.toUpperCase()),
            count: entry.value,
          ),
        )
        .toList()
      ..sort((a, b) => a.label.compareTo(b.label));

    return [
      _FilterOption(value: _allValue, label: 'Tous les pays', count: docs.length),
      ...options,
    ];
  }

  List<_FilterOption> _buildRegionOptions(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final counts = <String, int>{};
    for (final doc in docs) {
      final data = doc.data();
      final countryCode = _extractCountryCode(data) ?? 'unknown';

      if (_selectedCountry != _allValue && _selectedCountry != countryCode) {
        continue;
      }

      final regionCode = _extractRegionCode(data) ?? 'unknown';
      counts.update(regionCode, (value) => value + 1, ifAbsent: () => 1);
    }

    final options = counts.entries
        .map(
          (entry) => _FilterOption(
            value: entry.key,
            label: entry.key == 'unknown'
                ? 'Région inconnue'
                : (_regionCodeToName[entry.key] ?? entry.key),
            count: entry.value,
          ),
        )
        .toList()
      ..sort((a, b) => a.label.compareTo(b.label));

    final total = options.fold<int>(0, (acc, option) => acc + option.count);
    return [
      _FilterOption(value: _allValue, label: 'Toutes les régions', count: total),
      ...options,
    ];
  }

  List<_FilterOption> _buildDepartmentOptions(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final counts = <String, int>{};
    final labels = <String, String>{};

    for (final doc in docs) {
      final data = doc.data();
      final countryCode = _extractCountryCode(data) ?? 'unknown';
      final regionCode = _extractRegionCode(data) ?? 'unknown';

      if (_selectedCountry != _allValue && _selectedCountry != countryCode) {
        continue;
      }
      if (_selectedRegion != _allValue && _selectedRegion != regionCode) {
        continue;
      }

      final departmentCode = _extractDepartmentCode(data) ?? 'unknown';
      final city = (data['city'] as String?)?.trim();
      labels[departmentCode] = departmentCode == 'unknown'
          ? 'Département inconnu'
          : (city != null && city.isNotEmpty
              ? '$departmentCode • $city'
              : 'Département $departmentCode');
      counts.update(departmentCode, (value) => value + 1, ifAbsent: () => 1);
    }

    final options = counts.entries
        .map(
          (entry) => _FilterOption(
            value: entry.key,
            label: labels[entry.key] ?? entry.key,
            count: entry.value,
          ),
        )
        .toList()
      ..sort((a, b) => a.label.compareTo(b.label));

    final total = options.fold<int>(0, (acc, option) => acc + option.count);
    return [
      _FilterOption(
        value: _allValue,
        label: 'Tous les départements',
        count: total,
      ),
      ...options,
    ];
  }

  bool _matchesFilters(Map<String, dynamic> data) {
    final countryCode = _extractCountryCode(data) ?? 'unknown';
    final regionCode = _extractRegionCode(data) ?? 'unknown';
    final departmentCode = _extractDepartmentCode(data) ?? 'unknown';

    if (_selectedCountry != _allValue && countryCode != _selectedCountry) {
      return false;
    }
    if (_selectedRegion != _allValue && regionCode != _selectedRegion) {
      return false;
    }
    if (_selectedDepartment != _allValue && departmentCode != _selectedDepartment) {
      return false;
    }
    if (!_matchesSearch(data)) {
      return false;
    }
    return true;
  }

  String _safeValue(String current, List<_FilterOption> options) {
    final exists = options.any((option) => option.value == current);
    return exists ? current : _allValue;
  }

  int _activeFiltersCount() {
    var count = 0;
    if (_searchQuery.trim().isNotEmpty) count++;
    if (_selectedCountry != _allValue) count++;
    if (_selectedRegion != _allValue) count++;
    if (_selectedDepartment != _allValue) count++;
    return count;
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

          final countryOptions = _buildCountryOptions(docs);
          final regionOptions = _buildRegionOptions(docs);
          final departmentOptions = _buildDepartmentOptions(docs);

          _selectedCountry = _safeValue(_selectedCountry, countryOptions);
          _selectedRegion = _safeValue(_selectedRegion, regionOptions);
          _selectedDepartment = _safeValue(_selectedDepartment, departmentOptions);

          final filteredDocs = docs
              .where((doc) => _matchesFilters(doc.data()))
              .toList(growable: false);

            final totalItems = filteredDocs.length;
            final totalPages = totalItems == 0 ? 0 : (totalItems / _itemsPerPage).ceil();
            final currentPage = totalPages == 0
              ? 0
              : _currentPage.clamp(0, totalPages - 1);
            final startIndex = totalItems == 0 ? 0 : currentPage * _itemsPerPage;
            final endIndex = totalItems == 0
              ? 0
              : (startIndex + _itemsPerPage).clamp(0, totalItems);
            final pagedDocs = totalItems == 0
              ? const <QueryDocumentSnapshot<Map<String, dynamic>>>[]
              : filteredDocs.sublist(startIndex, endIndex);

          final grouped =
              <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
            for (final doc in pagedDocs) {
            final data = doc.data();
            final category = (data['categoryGroup'] as String?)?.trim();
            final key = (category == null || category.isEmpty) ? 'Autres' : category;
            grouped.putIfAbsent(key, () => []).add(doc);
          }

          final categories = grouped.keys.toList()..sort((a, b) => a.compareTo(b));

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('spot_reports')
                    .where('status', isEqualTo: 'open')
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
                builder: (context, reportsSnapshot) {
                  final reportDocs = reportsSnapshot.data?.docs ?? const [];
                  return Card(
                    child: ExpansionTile(
                      initiallyExpanded: reportDocs.isNotEmpty,
                      leading: Icon(
                        Icons.notification_important,
                        color: reportDocs.isNotEmpty ? Colors.red : Colors.grey,
                      ),
                      title: const Text('Signalements utilisateurs'),
                      subtitle: Text('${reportDocs.length} en attente'),
                      children: [
                        if (reportsSnapshot.connectionState == ConnectionState.waiting)
                          const Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(),
                          )
                        else if (reportDocs.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(12),
                            child: Text('Aucun signalement en attente.'),
                          )
                        else
                          for (final reportDoc in reportDocs)
                            ListTile(
                              dense: true,
                              title: Text(
                                ((reportDoc.data()['spotName'] as String?)?.trim().isNotEmpty ?? false)
                                    ? (reportDoc.data()['spotName'] as String).trim()
                                    : (reportDoc.data()['spotId'] as String? ?? 'Spot inconnu'),
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                'Motif: ${(reportDoc.data()['reason'] as String?) ?? 'Non précisé'}\n'
                                '${(reportDoc.data()['details'] as String?)?.trim().isNotEmpty == true ? (reportDoc.data()['details'] as String).trim() : 'Aucun détail'}',
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'resolve') {
                                    _resolveReport(context, reportDoc);
                                  } else if (value == 'delete_spot') {
                                    _deleteSpotFromReport(context, reportDoc);
                                  }
                                },
                                itemBuilder: (context) => const [
                                  PopupMenuItem(
                                    value: 'resolve',
                                    child: Text('Marquer résolu'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete_spot',
                                    child: Text('Supprimer le spot'),
                                  ),
                                ],
                              ),
                            ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.groups),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${filteredDocs.length}/${docs.length} spots • page ${currentPage + 1}/${totalPages == 0 ? 1 : totalPages} • ${categories.length} catégories affichées',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (totalItems > _itemsPerPage)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          OutlinedButton.icon(
                            onPressed: currentPage > 0
                                ? () {
                                    setState(() {
                                      _currentPage = currentPage - 1;
                                    });
                                  }
                                : null,
                            icon: const Icon(Icons.chevron_left),
                            label: const Text('Précédent'),
                          ),
                          Text(
                            '${startIndex + 1} - $endIndex sur $totalItems',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          OutlinedButton.icon(
                            onPressed: currentPage < totalPages - 1
                                ? () {
                                    setState(() {
                                      _currentPage = currentPage + 1;
                                    });
                                  }
                                : null,
                            icon: const Icon(Icons.chevron_right),
                            label: const Text('Suivant'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.tune),
                      title: const Text(
                        'Filtres administrateur',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        _activeFiltersCount() > 0
                            ? '${_activeFiltersCount()} filtre(s) actif(s)'
                            : 'Aucun filtre actif',
                      ),
                      trailing: Icon(
                        _filtersExpanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                      ),
                      onTap: () {
                        setState(() {
                          _filtersExpanded = !_filtersExpanded;
                        });
                      },
                    ),
                    if (_filtersExpanded)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                              decoration: const InputDecoration(
                                labelText: 'Rechercher un spot',
                                prefixIcon: Icon(Icons.search),
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              onChanged: (value) {
                                setState(() {
                                  _searchQuery = value;
                                  _currentPage = 0;
                                });
                              },
                            ),
                            const SizedBox(height: 10),
                            DropdownButtonFormField<String>(
                              initialValue: _selectedCountry,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Pays',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: [
                                for (final option in countryOptions)
                                  DropdownMenuItem<String>(
                                    value: option.value,
                                    child: Text('${option.label} (${option.count})'),
                                  ),
                              ],
                              onChanged: (value) {
                                if (value == null) return;
                                setState(() {
                                  _selectedCountry = value;
                                  _selectedRegion = _allValue;
                                  _selectedDepartment = _allValue;
                                  _currentPage = 0;
                                });
                              },
                            ),
                            const SizedBox(height: 10),
                            DropdownButtonFormField<String>(
                              initialValue: _selectedRegion,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Région',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: [
                                for (final option in regionOptions)
                                  DropdownMenuItem<String>(
                                    value: option.value,
                                    child: Text('${option.label} (${option.count})'),
                                  ),
                              ],
                              onChanged: (value) {
                                if (value == null) return;
                                setState(() {
                                  _selectedRegion = value;
                                  _selectedDepartment = _allValue;
                                  _currentPage = 0;
                                });
                              },
                            ),
                            const SizedBox(height: 10),
                            DropdownButtonFormField<String>(
                              initialValue: _selectedDepartment,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Département',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: [
                                for (final option in departmentOptions)
                                  DropdownMenuItem<String>(
                                    value: option.value,
                                    child: Text('${option.label} (${option.count})'),
                                  ),
                              ],
                              onChanged: (value) {
                                if (value == null) return;
                                setState(() {
                                  _selectedDepartment = value;
                                  _currentPage = 0;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              if (filteredDocs.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Aucun spot ne correspond aux filtres sélectionnés.'),
                  ),
                ),
              for (final category in categories)
                Card(
                  child: ExpansionTile(
                    initiallyExpanded: false,
                    leading: Icon(
                      poiCategoryFromString(category).icon,
                      color: poiCategoryFromString(category).color,
                    ),
                    title: Text(category),
                    subtitle: Text('${grouped[category]!.length} spots'),
                    children: [
                      for (final spotDoc in grouped[category]!)
                        ListTile(
                          dense: true,
                          title: Text(
                            ((spotDoc.data()['name'] as String?)?.trim().isNotEmpty ?? false)
                                ? (spotDoc.data()['name'] as String).trim()
                                : (spotDoc.data()['category'] as String? ?? category),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '${(spotDoc.data()['description'] as String?)?.trim().isNotEmpty == true ? (spotDoc.data()['description'] as String).trim() : 'Sans description'}\n'
                            '${_extractCountryLabel(spotDoc.data())} • ${_extractRegionLabel(spotDoc.data())} • Dép. ${_extractDepartmentCode(spotDoc.data()) ?? 'N/A'}',
                            maxLines: 2,
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

class _FilterOption {
  const _FilterOption({
    required this.value,
    required this.label,
    required this.count,
  });

  final String value;
  final String label;
  final int count;
}
