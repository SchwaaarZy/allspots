import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/regions_selection_provider.dart';

class DestinationSelectorPage extends ConsumerStatefulWidget {
  final bool isOnboarding;

  const DestinationSelectorPage({
    super.key,
    this.isOnboarding = false,
  });

  @override
  ConsumerState<DestinationSelectorPage> createState() => _DestinationSelectorPageState();
}

class _DestinationSelectorPageState extends ConsumerState<DestinationSelectorPage> {
  int _step = 0; // 0: Europe, 1: France

  void _showCannotDismissSnackbar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Veuillez sélectionner une destination pour continuer'),
        backgroundColor: Colors.red.shade600,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final franceSelected = ref.watch(franceSelectedProvider);
    final notifier = ref.read(franceSelectedProvider.notifier);

    return PopScope(
      canPop: widget.isOnboarding && franceSelected,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && widget.isOnboarding) {
          _showCannotDismissSnackbar();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _step == 0
                ? '🌍 Europe'
                : '🇫🇷 France',
          ),
          centerTitle: true,
          elevation: 0,
          leading: _step > 0
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => setState(() => _step--),
                )
              : null,
        ),
        body: Column(
          children: [
            // Message explicatif
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.blue.shade50,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '⚠️ Important : Vous devez choisir une destination pour voir les spots',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.blue.shade900,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tous les spots disponibles en France s\'afficheront sur la carte à proximité de votre position.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.blue.shade700,
                        ),
                  ),
                ],
              ),
            ),
            // Contenu selon l'étape
            Expanded(
              child: _step == 0
                  ? _buildEuropeStep()
                  : _buildFranceStep(),
            ),
            // Boutons d'action
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  if (_step > 0) ...[
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey.shade300,
                        ),
                        onPressed: () => setState(() => _step--),
                        child: const Text('Retour'),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _step < 1
                          ? () => setState(() => _step++)
                          : (franceSelected
                              ? () async {
                                  await notifier.completeInitialSelection();
                                  if (context.mounted) {
                                    Navigator.pop(context, true);
                                  }
                                }
                              : null),
                      child: Text(
                        _step < 1
                            ? 'Suivant'
                            : 'Valider',
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

  Widget _buildEuropeStep() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: 2,
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: Text('🇫🇷', style: Theme.of(context).textTheme.displayMedium),
            title: Text(
              'France',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            subtitle: const Text('Accédez à tous les spots disponibles en France'),
            trailing: const Icon(Icons.arrow_forward, color: Colors.blue),
            onTap: () => setState(() => _step++),
          ),
        ),
      ],
    );
  }

  Widget _buildFranceStep() {
    final franceSelected = ref.watch(franceSelectedProvider);
    final notifier = ref.read(franceSelectedProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: franceSelected ? 4 : 0,
          color: franceSelected ? Colors.blue.shade50 : Colors.white,
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: Icon(
              franceSelected ? Icons.check_circle : Icons.radio_button_unchecked,
              color: franceSelected ? Colors.blue : Colors.grey,
              size: 28,
            ),
            title: Text(
              'Sélectionner toute la France',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: franceSelected ? Colors.black : Colors.grey,
                  ),
            ),
            subtitle: const Text(
              'Tous les spots disponibles en France seront visibles à proximité',
            ),
            onTap: () async {
              if (!franceSelected) {
                await notifier.selectFrance();
              } else {
                await notifier.deselectFrance();
              }
            },
          ),
        ),
        const SizedBox(height: 16),
        if (franceSelected)
          Card(
            color: Colors.green.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.check, color: Colors.green.shade700, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'France sélectionnée ✓',
                      style: TextStyle(
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
