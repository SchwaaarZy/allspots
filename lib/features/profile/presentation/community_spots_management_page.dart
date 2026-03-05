import 'dart:async';

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
  static const int _queryBatchSize = 500;

  String _selectedCountry = _allValue;
  String _selectedRegion = _allValue;
  String _selectedDepartment = _allValue;
  String _selectedCategoryGroup = _allValue;
  String _searchQuery = '';
  bool _filtersExpanded = false;
  int _currentPage = 0;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _loadedSpotDocs = [];
  QueryDocumentSnapshot<Map<String, dynamic>>? _lastSpotDoc;
  bool _hasMoreSpots = true;
  bool _isLoadingInitial = true;
  bool _isLoadingMore = false;
  String? _spotLoadError;
  int _queryVersion = 0;

  late final Map<String, String> _countryCodeToName;
  late final Map<String, String> _regionCodeToName;
  late final Map<String, String> _departmentToRegionCode;

  @override
  void initState() {
    super.initState();
    _countryCodeToName = {
      for (final country in allCountries)
        country.code.toLowerCase(): country.name,
    };
    _regionCodeToName = {
      for (final country in allCountries)
        for (final region in country.regions) region.code: region.name,
    };
    _departmentToRegionCode = {
      for (final country in allCountries)
        for (final region in country.regions)
          for (final department in region.departments)
            department.code: region.code,
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reloadSpots();
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
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
        const SnackBar(
            content: Text('Erreur lors de la mise à jour du signalement.')),
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
      (value) =>
          value != null && value.toString().toLowerCase().contains(query),
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
      _FilterOption(
          value: _allValue, label: 'Tous les pays', count: docs.length),
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
      _FilterOption(
          value: _allValue, label: 'Toutes les régions', count: total),
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

  List<_FilterOption> _buildCategoryOptions(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final counts = <String, int>{};

    for (final doc in docs) {
      final rawCategory = (doc.data()['categoryGroup'] as String?)?.trim();
      final category =
          rawCategory == null || rawCategory.isEmpty ? 'Autres' : rawCategory;
      counts.update(category, (value) => value + 1, ifAbsent: () => 1);
    }

    final options = counts.entries
        .map(
          (entry) => _FilterOption(
            value: entry.key,
            label: entry.key,
            count: entry.value,
          ),
        )
        .toList()
      ..sort((a, b) => a.label.compareTo(b.label));

    return [
      _FilterOption(
        value: _allValue,
        label: 'Toutes les catégories',
        count: docs.length,
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
    if (_selectedDepartment != _allValue &&
        departmentCode != _selectedDepartment) {
      return false;
    }
    final rawCategory = (data['categoryGroup'] as String?)?.trim();
    final category =
        rawCategory == null || rawCategory.isEmpty ? 'Autres' : rawCategory;
    if (_selectedCategoryGroup != _allValue &&
        category != _selectedCategoryGroup) {
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
    if (_selectedCategoryGroup != _allValue) count++;
    return count;
  }

  Query<Map<String, dynamic>> _buildSpotsQuery() {
    Query<Map<String, dynamic>> query =
        FirebaseFirestore.instance.collection('spots');

    if (_selectedCountry != _allValue && _selectedCountry != 'unknown') {
      query = query.where('countryCode', isEqualTo: _selectedCountry);
    }
    if (_selectedRegion != _allValue && _selectedRegion != 'unknown') {
      query = query.where('regionCode', isEqualTo: _selectedRegion);
    }
    if (_selectedDepartment != _allValue && _selectedDepartment != 'unknown') {
      query = query.where('departmentCode', isEqualTo: _selectedDepartment);
    }
    if (_selectedCategoryGroup != _allValue &&
        _selectedCategoryGroup != 'unknown') {
      query = query.where('categoryGroup', isEqualTo: _selectedCategoryGroup);
    }

    return query.orderBy('updatedAt', descending: true);
  }

  String _buildFirestoreErrorMessage(Object error) {
    if (error is FirebaseException) {
      if (error.code == 'failed-precondition') {
        return 'Index Firestore manquant pour cette combinaison de filtres. '
            'Ouvrez le lien affiché dans les logs Firebase pour le créer, puis rechargez.';
      }
      if (error.code == 'permission-denied') {
        return 'Permission refusée pour lire les spots administrateur.';
      }
      return 'Erreur Firestore (${error.code}).';
    }
    return 'Erreur de chargement des spots.';
  }

  Future<void> _fetchSpotsPage({required bool reset}) async {
    if (_isLoadingMore) return;
    if (!reset && !_hasMoreSpots) return;

    final localVersion = _queryVersion;
    setState(() {
      if (reset) {
        _isLoadingInitial = true;
      } else {
        _isLoadingMore = true;
      }
      _spotLoadError = null;
    });

    try {
      Query<Map<String, dynamic>> query =
          _buildSpotsQuery().limit(_queryBatchSize);
      if (!reset && _lastSpotDoc != null) {
        query = query.startAfterDocument(_lastSpotDoc!);
      }

      final snapshot = await query.get();
      if (!mounted || localVersion != _queryVersion) return;

      setState(() {
        if (reset) {
          _loadedSpotDocs
            ..clear()
            ..addAll(snapshot.docs);
        } else {
          _loadedSpotDocs.addAll(snapshot.docs);
        }

        _lastSpotDoc =
            snapshot.docs.isNotEmpty ? snapshot.docs.last : _lastSpotDoc;
        _hasMoreSpots = snapshot.docs.length == _queryBatchSize;
        _isLoadingInitial = false;
        _isLoadingMore = false;
      });
    } catch (error) {
      if (!mounted || localVersion != _queryVersion) return;
      setState(() {
        _spotLoadError = _buildFirestoreErrorMessage(error);
        _isLoadingInitial = false;
        _isLoadingMore = false;
      });
    }
  }

  Future<void> _reloadSpots() async {
    _queryVersion++;
    _lastSpotDoc = null;
    _hasMoreSpots = true;
    _currentPage = 0;
    await _fetchSpotsPage(reset: true);
  }

  void _onServerFiltersUpdated(VoidCallback updateFilters) {
    setState(() {
      updateFilters();
      _currentPage = 0;
    });
    _reloadSpots();
  }

  void _clearFilters() {
    setState(() {
      _selectedCountry = _allValue;
      _selectedRegion = _allValue;
      _selectedDepartment = _allValue;
      _selectedCategoryGroup = _allValue;
      _searchQuery = '';
      _searchController.clear();
      _currentPage = 0;
    });
    _reloadSpots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GlassAppBar(
        title: 'Spots communauté',
        showBackButton: true,
      ),
      body: _isLoadingInitial
          ? const Center(child: CircularProgressIndicator())
          : (_loadedSpotDocs.isEmpty && _spotLoadError != null)
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            color: Colors.red, size: 36),
                        const SizedBox(height: 12),
                        Text(
                          _spotLoadError!,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: _reloadSpots,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Réessayer'),
                        ),
                      ],
                    ),
                  ),
                )
              : _buildBodyContent(),
    );
  }

  Widget _buildBodyContent() {
    final docs = _loadedSpotDocs;
    if (docs.isEmpty) {
      return const Center(
        child: Text('Aucun spot créé par la communauté.'),
      );
    }

    final countryOptions = _buildCountryOptions(docs);
    final regionOptions = _buildRegionOptions(docs);
    final departmentOptions = _buildDepartmentOptions(docs);
    final categoryOptions = _buildCategoryOptions(docs);

    _selectedCountry = _safeValue(_selectedCountry, countryOptions);
    _selectedRegion = _safeValue(_selectedRegion, regionOptions);
    _selectedDepartment = _safeValue(_selectedDepartment, departmentOptions);
    _selectedCategoryGroup =
        _safeValue(_selectedCategoryGroup, categoryOptions);

    final filteredDocs = docs
        .where((doc) => _matchesFilters(doc.data()))
        .toList(growable: false);

    final totalItems = filteredDocs.length;
    final totalPages =
        totalItems == 0 ? 0 : (totalItems / _itemsPerPage).ceil();
    final currentPage =
        totalPages == 0 ? 0 : _currentPage.clamp(0, totalPages - 1);
    final startIndex = totalItems == 0 ? 0 : currentPage * _itemsPerPage;
    final endIndex =
        totalItems == 0 ? 0 : (startIndex + _itemsPerPage).clamp(0, totalItems);
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

    return RefreshIndicator(
      onRefresh: _reloadSpots,
      child: ListView(
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
                    if (reportsSnapshot.connectionState ==
                        ConnectionState.waiting)
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
                            ((reportDoc.data()['spotName'] as String?)
                                        ?.trim()
                                        .isNotEmpty ??
                                    false)
                                ? (reportDoc.data()['spotName'] as String)
                                    .trim()
                                : (reportDoc.data()['spotId'] as String? ??
                                    'Spot inconnu'),
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
                      '${filteredDocs.length}/${docs.length} spots chargés • page ${currentPage + 1}/${totalPages == 0 ? 1 : totalPages} • ${categories.length} catégories affichées',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Rafraîchir',
                    onPressed: _reloadSpots,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            color: Colors.blueGrey.shade50,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Performance admin: les spots sont chargés par lots de 500 selon vos filtres serveur (pays/région/département/catégorie).',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ),
          if (_spotLoadError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _spotLoadError!,
                    style: const TextStyle(color: Colors.red),
                  ),
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
                        Row(
                          children: [
                            if (_activeFiltersCount() > 0)
                              Expanded(
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    if (_searchQuery.trim().isNotEmpty)
                                      InputChip(
                                        label: Text('Recherche: $_searchQuery'),
                                        onDeleted: () {
                                          setState(() {
                                            _searchQuery = '';
                                            _searchController.clear();
                                            _currentPage = 0;
                                          });
                                        },
                                      ),
                                    if (_selectedCountry != _allValue)
                                      InputChip(
                                        label: Text('Pays: $_selectedCountry'),
                                        onDeleted: () {
                                          _onServerFiltersUpdated(() {
                                            _selectedCountry = _allValue;
                                            _selectedRegion = _allValue;
                                            _selectedDepartment = _allValue;
                                          });
                                        },
                                      ),
                                    if (_selectedRegion != _allValue)
                                      InputChip(
                                        label: Text('Région: $_selectedRegion'),
                                        onDeleted: () {
                                          _onServerFiltersUpdated(() {
                                            _selectedRegion = _allValue;
                                            _selectedDepartment = _allValue;
                                          });
                                        },
                                      ),
                                    if (_selectedDepartment != _allValue)
                                      InputChip(
                                        label:
                                            Text('Dép.: $_selectedDepartment'),
                                        onDeleted: () {
                                          _onServerFiltersUpdated(() {
                                            _selectedDepartment = _allValue;
                                          });
                                        },
                                      ),
                                    if (_selectedCategoryGroup != _allValue)
                                      InputChip(
                                        label: Text(
                                          'Catégorie: $_selectedCategoryGroup',
                                        ),
                                        onDeleted: () {
                                          _onServerFiltersUpdated(() {
                                            _selectedCategoryGroup = _allValue;
                                          });
                                        },
                                      ),
                                  ],
                                ),
                              )
                            else
                              const Expanded(
                                child: Text(
                                    'Astuce: combinez région + catégorie pour cibler vite.'),
                              ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: _activeFiltersCount() > 0
                                  ? _clearFilters
                                  : null,
                              icon: const Icon(Icons.filter_alt_off),
                              label: const Text('Réinitialiser'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _searchController,
                          decoration: const InputDecoration(
                            labelText: 'Rechercher un spot',
                            prefixIcon: Icon(Icons.search),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (value) {
                            _searchDebounce?.cancel();
                            _searchDebounce = Timer(
                              const Duration(milliseconds: 300),
                              () {
                                if (!mounted) return;
                                setState(() {
                                  _searchQuery = value;
                                  _currentPage = 0;
                                });
                              },
                            );
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
                                child:
                                    Text('${option.label} (${option.count})'),
                              ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            _onServerFiltersUpdated(() {
                              _selectedCountry = value;
                              _selectedRegion = _allValue;
                              _selectedDepartment = _allValue;
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
                                child:
                                    Text('${option.label} (${option.count})'),
                              ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            _onServerFiltersUpdated(() {
                              _selectedRegion = value;
                              _selectedDepartment = _allValue;
                            });
                          },
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedCategoryGroup,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Catégorie',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: [
                            for (final option in categoryOptions)
                              DropdownMenuItem<String>(
                                value: option.value,
                                child:
                                    Text('${option.label} (${option.count})'),
                              ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            _onServerFiltersUpdated(() {
                              _selectedCategoryGroup = value;
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
                                child:
                                    Text('${option.label} (${option.count})'),
                              ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            _onServerFiltersUpdated(() {
                              _selectedDepartment = value;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (_hasMoreSpots)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isLoadingMore
                      ? null
                      : () => _fetchSpotsPage(reset: false),
                  icon: _isLoadingMore
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.expand_more),
                  label: Text(
                    _isLoadingMore
                        ? 'Chargement...'
                        : 'Charger 500 spots supplémentaires',
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          if (filteredDocs.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child:
                    Text('Aucun spot ne correspond aux filtres sélectionnés.'),
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
                        ((spotDoc.data()['name'] as String?)
                                    ?.trim()
                                    .isNotEmpty ??
                                false)
                            ? (spotDoc.data()['name'] as String).trim()
                            : (spotDoc.data()['category'] as String? ??
                                category),
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
                        icon:
                            const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () => _deleteSpot(context, spotDoc),
                      ),
                    ),
                ],
              ),
            ),
        ],
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
