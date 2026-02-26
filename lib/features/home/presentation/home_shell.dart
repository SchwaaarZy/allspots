import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../../core/utils/responsive_utils.dart';
import '../../auth/data/auth_providers.dart';
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
    final profile = ref.read(profileStreamProvider).value;
    final premiumActive = profile?.hasPremiumPass == true &&
        (profile?.premiumExpiryDate?.isAfter(DateTime.now()) ?? false);
    if (profile?.isAdmin == true || premiumActive) {
      _cancelAdSchedule();
      return;
    }

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
      final profile = ref.read(profileStreamProvider).value;
      final premiumActive = profile?.hasPremiumPass == true &&
          (profile?.premiumExpiryDate?.isAfter(DateTime.now()) ?? false);
      if (profile?.isAdmin == true || premiumActive) {
        return false;
      }

      final usersDoc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final profilesDoc = await FirebaseFirestore.instance
          .collection('profiles')
          .doc(uid)
          .get();

      final usersData = usersDoc.data();
      final profileData = profilesDoc.data();

      final usersRole = (usersData?['role'] as String?)?.toLowerCase();
      final profileRole = (profileData?['role'] as String?)?.toLowerCase();
      final isAdmin = usersData?['isAdmin'] == true ||
          usersRole == 'admin' ||
          profileData?['isAdmin'] == true ||
          profileRole == 'admin';
      if (isAdmin) {
        return false;
      }

      final isPremium = usersData?['isPremium'] == true ||
          usersData?['hasPremiumPass'] == true ||
          profileData?['isPremium'] == true ||
          profileData?['hasPremiumPass'] == true;
      final premiumExpiryRaw =
          usersData?['premiumExpiryDate'] ?? profileData?['premiumExpiryDate'];
      DateTime? premiumExpiry;
      if (premiumExpiryRaw is Timestamp) {
        premiumExpiry = premiumExpiryRaw.toDate();
      } else if (premiumExpiryRaw is DateTime) {
        premiumExpiry = premiumExpiryRaw;
      }

      if (isPremium &&
          premiumExpiry != null &&
          DateTime.now().isBefore(premiumExpiry)) {
        return false;
      }

      final demoNoAdsExpiry = usersData?['demoNoAdsExpiry'] as Timestamp?;
      if (demoNoAdsExpiry != null &&
          DateTime.now().isBefore(demoNoAdsExpiry.toDate())) {
        return false;
      }

      return true;
    } catch (_) {
      return false;
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
    final colorScheme = Theme.of(context).colorScheme;
    final screenWidth = context.screenWidth;
    final compactNav = screenWidth < 375;
    const navCornerRadius = 18.0;
    const navBackgroundColor = Colors.white;
    final navHeight = compactNav ? 64.0 : 68.0;
    final navLabelTextStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          fontSize: compactNav ? context.fontSize(9.5) : context.fontSize(11),
        );

    final navSelectedIndex = switch (_index) {
      3 => 2,
      2 => 3,
      _ => _index,
    };

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
    final PreferredSizeWidget shellAppBar = GlassAppBar(
      titleWidget: Image.asset(
        _index == 0
            ? 'assets/images/allspots_simple_logo.png'
            : titleLogos[_index],
        height: _index == 0 ? (compactNav ? 44 : 55) : (compactNav ? 18 : 22),
        fit: BoxFit.contain,
      ),
      centerTitle: true,
    );

    return Scaffold(
      appBar: shellAppBar,
      body: _LazyIndexedStack(
        index: _index,
        children: tabs,
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AdBanner(),
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(navCornerRadius),
            ),
            child: ColoredBox(
              color: navBackgroundColor,
              child: SafeArea(
                top: false,
                left: false,
                right: false,
                child: NavigationBarTheme(
                  data: NavigationBarTheme.of(context).copyWith(
                    backgroundColor: navBackgroundColor,
                    labelTextStyle: WidgetStateProperty.resolveWith((states) {
                      final base = navLabelTextStyle ?? const TextStyle();
                      final selected = states.contains(WidgetState.selected);
                      return base.copyWith(
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w600,
                        color: selected
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                      );
                    }),
                  ),
                  child: NavigationBar(
                    backgroundColor: navBackgroundColor,
                    height: navHeight,
                    selectedIndex: navSelectedIndex,
                    onDestinationSelected: (destination) {
                      final mappedIndex = switch (destination) {
                        2 => 3,
                        3 => 2,
                        _ => destination,
                      };
                      setState(() => _index = mappedIndex);
                    },
                    destinations: const [
                      NavigationDestination(
                        icon: Icon(Icons.public),
                        selectedIcon: Icon(Icons.public),
                        label: 'Accueil',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.search),
                        selectedIcon: Icon(Icons.search),
                        label: 'Recherche',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.near_me),
                        selectedIcon: Icon(Icons.near_me),
                        label: 'Autour',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.person_outline),
                        selectedIcon: Icon(Icons.person),
                        label: 'Profil',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LazyIndexedStack extends StatefulWidget {
  const _LazyIndexedStack({
    required this.index,
    required this.children,
  });

  final int index;
  final List<Widget> children;

  @override
  State<_LazyIndexedStack> createState() => _LazyIndexedStackState();
}

class _LazyIndexedStackState extends State<_LazyIndexedStack> {
  late final List<bool> _activated;

  @override
  void initState() {
    super.initState();
    _activated = List<bool>.filled(widget.children.length, false);
    _activated[widget.index] = true;
  }

  @override
  void didUpdateWidget(covariant _LazyIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index >= 0 && widget.index < _activated.length) {
      _activated[widget.index] = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: widget.index,
      children: List<Widget>.generate(widget.children.length, (index) {
        if (!_activated[index]) {
          return const SizedBox.shrink();
        }
        return widget.children[index];
      }),
    );
  }
}
