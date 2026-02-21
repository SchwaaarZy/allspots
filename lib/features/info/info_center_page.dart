import 'package:flutter/material.dart';

import '../../core/widgets/glass_app_bar.dart';
import 'tabs/faq_info_tab.dart';
import 'tabs/features_info_tab.dart';
import 'tabs/installation_info_tab.dart';

/// Centre d'information de l'app (FAQ / fonctionnalités / installation).
///
/// Objectif : embarquer dans l'app ce qui existait en pages HTML.
class InfoCenterPage extends StatefulWidget {
  const InfoCenterPage({super.key});

  static const String routeName = '/info';

  @override
  State<InfoCenterPage> createState() => _InfoCenterPageState();
}

class _InfoCenterPageState extends State<InfoCenterPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GlassAppBar(
        title: 'Infos',
        showBackButton: true,
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.center,
              labelColor: Theme.of(context).colorScheme.primary,
              unselectedLabelColor: Colors.grey[600],
              indicatorColor: Theme.of(context).colorScheme.primary,
              indicatorWeight: 3,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                letterSpacing: 0.2,
              ),
              tabs: const [
                Tab(icon: Icon(Icons.auto_awesome), text: 'Fonctionnalités'),
                Tab(icon: Icon(Icons.download), text: 'Installation'),
                Tab(icon: Icon(Icons.help_outline), text: 'FAQ'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                FeaturesInfoTab(),
                InstallationInfoTab(),
                FaqInfoTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
