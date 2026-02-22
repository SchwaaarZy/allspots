import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../../core/utils/responsive_utils.dart';
import '../../map/presentation/map_page.dart';
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
  static const Duration _firstAdDelay = Duration(minutes: 2);
  static const Duration _recurringAdDelay = Duration(minutes: 10);

  Timer? _firstAdTimer;
  Timer? _recurringAdTimer;
  String? _scheduledForUid;
  bool _isShowingInterstitial = false;

  bool get _isAdsSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  @override
  void initState() {
    super.initState();
    _syncAdSchedule();
  }

  @override
  void dispose() {
    _cancelAdSchedule();
    super.dispose();
  }

  void _syncAdSchedule() {
    final user = FirebaseAuth.instance.currentUser;
    if (!_isAdsSupported || user == null) {
      _cancelAdSchedule();
      return;
    }

    if (_scheduledForUid == user.uid) {
      return;
    }

    _cancelAdSchedule();
    _scheduledForUid = user.uid;

    _firstAdTimer = Timer(_firstAdDelay, _onAdTimerTick);
    _recurringAdTimer = Timer.periodic(
      _recurringAdDelay,
      (_) => _onAdTimerTick(),
    );
  }

  void _cancelAdSchedule() {
    _firstAdTimer?.cancel();
    _recurringAdTimer?.cancel();
    _firstAdTimer = null;
    _recurringAdTimer = null;
    _scheduledForUid = null;
  }

  Future<void> _onAdTimerTick() async {
    if (!mounted || _isShowingInterstitial) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _cancelAdSchedule();
      return;
    }

    final shouldShowAd = await _shouldShowAds(user.uid);
    if (!shouldShowAd) return;

    await _showInterstitialAd();
  }

  Future<bool> _shouldShowAds(String uid) async {
    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = doc.data();
      if (data == null) return true;

      final isPremium = data['isPremium'] == true;
      final premiumExpiry = data['premiumExpiryDate'] as Timestamp?;
      if (isPremium && premiumExpiry != null) {
        final expiresAt = premiumExpiry.toDate();
        if (DateTime.now().isBefore(expiresAt)) {
          return false;
        }
      }

      final demoNoAdsExpiry = data['demoNoAdsExpiry'] as Timestamp?;
      if (demoNoAdsExpiry != null &&
          DateTime.now().isBefore(demoNoAdsExpiry.toDate())) {
        return false;
      }

      return true;
    } catch (_) {
      return true;
    }
  }

  Future<InterstitialAd?> _loadInterstitialAd() {
    final completer = Completer<InterstitialAd?>();

    InterstitialAd.load(
      adUnitId: 'ca-app-pub-3940256099942544/1033173712',
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => completer.complete(ad),
        onAdFailedToLoad: (_) => completer.complete(null),
      ),
    );

    return completer.future;
  }

  Future<void> _showInterstitialAd() async {
    if (_isShowingInterstitial) return;

    final ad = await _loadInterstitialAd();
    if (ad == null) return;

    _isShowingInterstitial = true;
    final done = Completer<void>();

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!done.isCompleted) done.complete();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        if (!done.isCompleted) done.complete();
      },
    );

    ad.show();
    await done.future;
    _isShowingInterstitial = false;
  }

  @override
  Widget build(BuildContext context) {
    _syncAdSchedule();
    final screenWidth = context.screenWidth;
    final compactNav = screenWidth < 375;
    final navIconSize = compactNav ? 20.0 : 24.0;
    final navFontSize = compactNav ? context.fontSize(9.5) : context.fontSize(11);

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
    return Scaffold(
      appBar: GlassAppBar(
        titleWidget: Image.asset(
          _index == 0
              ? 'assets/images/allspots_simple_logo.png'
              : titleLogos[_index],
          height: _index == 0
              ? (compactNav ? 44 : 55)
              : (compactNav ? 18 : 22),
          fit: BoxFit.contain,
        ),
        centerTitle: true,
      ) as PreferredSizeWidget,
      body: IndexedStack(
        index: _index,
        children: tabs,
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AdBanner(),
          Container(
            padding: EdgeInsets.symmetric(
              vertical: compactNav ? 8 : 10,
              horizontal: compactNav ? 2 : 4,
            ),
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
                    iconSize: navIconSize,
                    fontSize: navFontSize,
                    onTap: () {
                      setState(() => _index = 0);
                    },
                  ),
                  _buildNavItem(
                    icon: Icons.search,
                    label: 'Recherche',
                    selected: _index == 1,
                    iconSize: navIconSize,
                    fontSize: navFontSize,
                    onTap: () => setState(() => _index = 1),
                  ),
                  _buildNavItem(
                    icon: Icons.near_me,
                    label: 'Autour de moi',
                    selected: _index == 3,
                    iconSize: navIconSize,
                    fontSize: navFontSize,
                    onTap: () {
                      setState(() => _index = 3);
                    },
                  ),
                  // Satelite button disabled - using map only
                  const SizedBox(width: 8),
                  _buildNavItem(
                    icon: Icons.person_outline,
                    label: 'Profil',
                    selected: _index == 2,
                    iconSize: navIconSize,
                    fontSize: navFontSize,
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
    required double iconSize,
    required double fontSize,
    required VoidCallback onTap,
  }) {
    final color =
        selected ? Theme.of(context).colorScheme.primary : Colors.grey;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: iconSize),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(fontSize: fontSize, color: color),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
