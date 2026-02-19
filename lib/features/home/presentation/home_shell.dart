import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../map/presentation/map_page.dart';
import '../../map/presentation/map_controller.dart';
import '../../map/presentation/nearby_results_page.dart';
import '../../search/presentation/search_page.dart';
import '../../profile/presentation/profile_page.dart';
import '../../../core/widgets/ad_banner.dart';
import '../../../core/widgets/glass_app_bar.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final tabs = [
      const MapView(),
      const SearchPage(),
      const ProfilePage(),
      const NearbyResultsPage(),
    ];

    final titleLogos = [
      'assets/images/accueil.png',
      'assets/images/recherche.png',
      'assets/images/monprofil.png',
      'assets/images/autourdemoi.png',
    ];
    final mapState = ref.watch(mapControllerProvider);

    return Scaffold(
      appBar: GlassAppBar(
              titleWidget: Image.asset(
                _index == 0
                    ? 'assets/images/allspots_simple_logo.png'
                    : titleLogos[_index],
                height: _index == 0 ? 55 : 22,
                fit: BoxFit.contain,
              ),
              centerTitle: true,
            )
          as PreferredSizeWidget,
      body: IndexedStack(
        index: _index,
        children: tabs,
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AdBanner(),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              left: false,
              right: false,
              child: Row(
                children: [
                  _buildNavItem(
                    icon: Icons.public,
                    label: 'Accueil',
                    selected: _index == 0,
                    onTap: () {
                      setState(() => _index = 0);
                    },
                  ),
                  _buildNavItem(
                    icon: Icons.search,
                    label: 'Recherche',
                    selected: _index == 1,
                    onTap: () => setState(() => _index = 1),
                  ),
                  _buildNavItem(
                    icon: Icons.near_me,
                    label: 'Autour de moi',
                    selected: _index == 3,
                    onTap: () {
                      setState(() => _index = 3);
                    },
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        setState(() => _index = 0);
                        ref.read(mapControllerProvider.notifier).toggleMapType();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              mapState.isSatellite
                                  ? Icons.map_outlined
                                  : Icons.satellite_alt,
                              color: _index == 0
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.grey,
                              size: 24,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              mapState.isSatellite ? 'Carte' : 'Satellite',
                              style: TextStyle(
                                fontSize: 11,
                                color: _index == 0
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.grey,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  _buildNavItem(
                    icon: Icons.person_outline,
                    label: 'Profil',
                    selected: _index == 2,
                    onTap: () => setState(() => _index = 2),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final color = selected
      ? Theme.of(context).colorScheme.primary
      : Colors.grey;
    
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(fontSize: 11, color: color),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

}
