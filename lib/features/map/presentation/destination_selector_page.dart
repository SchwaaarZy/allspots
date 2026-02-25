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
  ConsumerState<DestinationSelectorPage> createState() =>
      _DestinationSelectorPageState();
}

class _DestinationSelectorPageState
    extends ConsumerState<DestinationSelectorPage> {
  void _showCannotDismissSnackbar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            const Text('Veuillez sélectionner une localisation pour continuer'),
        backgroundColor: Colors.red.shade600,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final franceSelected = ref.watch(franceSelectedProvider);
    final notifier = ref.read(franceSelectedProvider.notifier);
    final canCloseSelector = !widget.isOnboarding || franceSelected;

    return PopScope(
      canPop: canCloseSelector,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && widget.isOnboarding) {
          _showCannotDismissSnackbar();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('📍 Choisir une localisation'),
          centerTitle: true,
          elevation: 0,
        ),
        body: Column(
          children: [
            Expanded(
              child: _buildFranceStep(),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: franceSelected
                      ? () async {
                          await notifier.completeInitialSelection();
                          if (context.mounted) {
                            Navigator.pop(context, true);
                          }
                        }
                      : null,
                  child: const Text('Valider'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFranceStep() {
    final franceSelected = ref.watch(franceSelectedProvider);
    final notifier = ref.read(franceSelectedProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: franceSelected ? 2 : 0,
          color: franceSelected ? Colors.blue.shade50 : Colors.white,
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: Icon(
              franceSelected
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
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
      ],
    );
  }
}
