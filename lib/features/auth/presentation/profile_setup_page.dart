import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/poi_categories.dart';
import '../../../core/widgets/glass_app_bar.dart';
import '../data/account_verification_service.dart';

class ProfileSetupPage extends StatefulWidget {
  const ProfileSetupPage({super.key, this.isEditMode = false});

  final bool isEditMode;

  @override
  State<ProfileSetupPage> createState() => _ProfileSetupPageState();
}

class _ProfileSetupPageState extends State<ProfileSetupPage> {
  final _nameController = TextEditingController();
  final Set<String> _selectedCategories = {};

  bool _isLoading = false;
  String? _error;
  int _currentStep = 0;

  @override
  void initState() {
    super.initState();
    _loadExistingProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadExistingProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('profiles')
          .doc(user.uid)
          .get();
      final data = doc.data();

      if (!mounted) return;

      if (data != null) {
        final displayName = (data['displayName'] as String?)?.trim() ?? '';
        final categoriesRaw = data['categories'];

        setState(() {
          _nameController.text = displayName;
          _selectedCategories
            ..clear()
            ..addAll(
              categoriesRaw is List
                  ? categoriesRaw.whereType<String>()
                  : const <String>[],
            );
        });
      }

      if (_nameController.text.trim().isEmpty) {
        _nameController.text = _defaultPseudoFromUser(user);
      }
    } catch (_) {
      if (!mounted) return;
      _error = 'Impossible de charger le profil.';
    }
  }

  String _defaultPseudoFromUser(User user) {
    final displayName = user.displayName?.trim() ?? '';
    if (displayName.isNotEmpty) return displayName;

    final email = user.email?.trim() ?? '';
    final localPart = email.contains('@') ? email.split('@').first : email;
    final cleaned = localPart
        .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '')
        .trim();

    if (cleaned.length >= 3) {
      return cleaned;
    }

    final millis = DateTime.now().millisecondsSinceEpoch % 9000 + 1000;
    return 'voyageur$millis';
  }

  List<String> _pseudoSuggestions() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const <String>[];

    final base = _defaultPseudoFromUser(user);
    final cleanedBase = base.replaceAll(RegExp(r'\s+'), '').trim();

    final options = <String>{
      cleanedBase,
      '${cleanedBase}_road',
      '${cleanedBase}_spots',
      '${cleanedBase}01',
    };

    return options
        .where((value) => value.trim().length >= 3)
        .take(4)
        .toList(growable: false);
  }

  bool get _isPseudoValid => _nameController.text.trim().length >= 3;

  bool get _canGoNext {
    if (_currentStep == 0) return _isPseudoValid;
    if (_currentStep == 1) return _selectedCategories.isNotEmpty;
    return true;
  }

  void _nextStep() {
    if (!_canGoNext) return;

    setState(() {
      _error = null;
      _currentStep = (_currentStep + 1).clamp(0, 2);
    });
  }

  void _prevStep() {
    setState(() {
      _error = null;
      _currentStep = (_currentStep - 1).clamp(0, 2);
    });
  }

  bool _isGroupSelected(PoiCategoryGroup group) {
    return group.items.every((item) => _selectedCategories.contains(item));
  }

  int _groupSelectedCount(PoiCategoryGroup group) {
    return group.items.where((item) => _selectedCategories.contains(item)).length;
  }

  IconData _iconForGroup(PoiCategoryGroup group) {
    if (group.title.contains('Patrimoine')) return Icons.account_balance_outlined;
    if (group.title.contains('Nature')) return Icons.park_outlined;
    if (group.title.contains('Culture')) return Icons.palette_outlined;
    return Icons.directions_walk_outlined;
  }

  Future<void> _saveProfileAndFinish() async {
    if (_isLoading) return;

    if (_nameController.text.trim().length < 3) {
      setState(() => _error = 'Choisissez un pseudo (min 3 caracteres).');
      return;
    }

    if (_selectedCategories.isEmpty) {
      setState(() => _error = 'Selectionnez au moins un centre d\'interet.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _error = 'Utilisateur non connecte.');
        return;
      }

      final docRef = FirebaseFirestore.instance.collection('profiles').doc(user.uid);
      final existing = await docRef.get();

      final data = <String, dynamic>{
        'displayName': _nameController.text.trim(),
        'categories': _selectedCategories.toList(growable: false),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (!existing.exists) {
        final verificationDeadline =
            AccountVerificationService.verificationDeadline(user);
        final accountCreatedAt =
            AccountVerificationService.accountCreationDate(user);

        data['createdAt'] = FieldValue.serverTimestamp();
        data['accountCreatedAt'] = accountCreatedAt != null
            ? Timestamp.fromDate(accountCreatedAt)
            : FieldValue.serverTimestamp();
        data['photoUrl'] = '';
        data['bio'] = '';
        data['location'] = '';
        data['locationLat'] = null;
        data['locationLng'] = null;
        data['xp'] = 0;
        data['totalVisits'] = 0;
        data['uniqueVisitedSpots'] = 0;
        data['isPhoneVerified'] =
            user.phoneNumber != null && user.phoneNumber!.trim().isNotEmpty;
        data['phoneVerificationStatus'] =
            data['isPhoneVerified'] == true ? 'verified' : 'pending';
        data['phoneVerificationDeadlineAt'] = verificationDeadline != null
            ? Timestamp.fromDate(verificationDeadline)
            : FieldValue.serverTimestamp();
        data['phoneNumber'] = user.phoneNumber;
        if (data['isPhoneVerified'] == true) {
          data['phoneVerifiedAt'] = FieldValue.serverTimestamp();
        }
      }

      await docRef.set(data, SetOptions(merge: true));

      if (!mounted) return;

      if (widget.isEditMode) {
        context.pop();
      } else {
        context.go('/home');
      }
    } on FirebaseException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message ?? 'Erreur lors de la sauvegarde.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Une erreur est survenue.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildStepHeader(BuildContext context) {
    final title = _currentStep == 0
        ? 'Choisis ton pseudo'
        : _currentStep == 1
            ? 'Tes centres d\'interet'
            : 'Pret a explorer';

    final subtitle = _currentStep == 0
        ? 'Comme Apple, choisis un pseudo simple et stylise.'
        : _currentStep == 1
            ? 'Selectionne ce qui te ressemble pour personnaliser la map.'
            : 'On a tout. Lance ton aventure maintenant.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: (_currentStep + 1) / 3,
            minHeight: 8,
            backgroundColor: Colors.grey.shade200,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }

  Widget _buildPseudoStep(BuildContext context) {
    final suggestions = _pseudoSuggestions();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _nameController,
          onChanged: (_) => setState(() {}),
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: 'Pseudo',
            hintText: 'Ex: roadtrip_marie',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final value in suggestions)
              ActionChip(
                label: Text(value),
                onPressed: () {
                  setState(() {
                    _nameController.text = value;
                  });
                },
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildInterestsStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${_selectedCategories.length} interets selectionnes',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        for (final group in poiCategoryGroups) ...[
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            elevation: 0,
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.38),
            child: ExpansionTile(
              leading: Icon(
                _iconForGroup(group),
                color: Theme.of(context).colorScheme.primary,
              ),
              title: Text(
                group.title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '${_groupSelectedCount(group)}/${group.items.length}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: _isGroupSelected(group),
                    onChanged: (selected) {
                      setState(() {
                        if (selected == true) {
                          _selectedCategories.addAll(group.items);
                        } else {
                          _selectedCategories.removeAll(group.items);
                        }
                      });
                    },
                  ),
                  const Icon(Icons.expand_more),
                ],
              ),
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final item in group.items)
                        FilterChip(
                          selected: _selectedCategories.contains(item),
                          showCheckmark: false,
                          label: Text(item),
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _selectedCategories.add(item);
                              } else {
                                _selectedCategories.remove(item);
                              }
                            });
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildReviewStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Recap',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text('Pseudo: ${_nameController.text.trim()}'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _selectedCategories
                      .map((item) => Chip(label: Text(item)))
                      .toList(growable: false),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCurrentStep(BuildContext context) {
    if (_currentStep == 0) return _buildPseudoStep(context);
    if (_currentStep == 1) return _buildInterestsStep(context);
    return _buildReviewStep(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GlassAppBar(
        title: widget.isEditMode ? 'Modifier votre profil' : 'Creer votre profil',
        showBackButton: widget.isEditMode || _currentStep > 0,
        onBackPressed: () {
          if (_currentStep > 0 && !widget.isEditMode) {
            _prevStep();
          } else {
            context.pop();
          }
        },
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildStepHeader(context),
                const SizedBox(height: 16),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: Container(
                    key: ValueKey<int>(_currentStep),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: _buildCurrentStep(context),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    if (_currentStep > 0 && !widget.isEditMode)
                      OutlinedButton(
                        onPressed: _isLoading ? null : _prevStep,
                        child: const Text('Retour'),
                      ),
                    const Spacer(),
                    if (_currentStep < 2)
                      FilledButton(
                        onPressed: _isLoading || !_canGoNext ? null : _nextStep,
                        child: const Text('Continuer'),
                      )
                    else
                      FilledButton.icon(
                        onPressed: _isLoading ? null : _saveProfileAndFinish,
                        icon: _isLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.explore),
                        label: Text(widget.isEditMode
                            ? 'Enregistrer'
                            : 'Commencer sur la map'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
