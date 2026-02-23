import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../core/theme/app_theme.dart';
import '../core/l10n/app_localizations.dart';
import '../core/l10n/locale_provider.dart';
import 'router.dart';

class AllSpotsApp extends ConsumerWidget {
  const AllSpotsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final locale = ref.watch(localeProvider);

    return _PresenceTracker(
      child: MaterialApp.router(
        title: 'AllSPOTS',
        debugShowCheckedModeBanner: false,
        routerConfig: router,
        theme: AppTheme.light(),
        locale: locale,
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('fr'),
          Locale('en'),
        ],
        builder: (context, child) {
          final mediaQuery = MediaQuery.of(context);
          final clampedTextScaler = mediaQuery.textScaler.clamp(
            minScaleFactor: 0.9,
            maxScaleFactor: 1.2,
          );

          return MediaQuery(
            data: mediaQuery.copyWith(textScaler: clampedTextScaler),
            child: child ?? const SizedBox.shrink(),
          );
        },
      ),
    );
  }
}

class _PresenceTracker extends StatefulWidget {
  final Widget child;

  const _PresenceTracker({required this.child});

  @override
  State<_PresenceTracker> createState() => _PresenceTrackerState();
}

class _PresenceTrackerState extends State<_PresenceTracker>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setOnline(true);
  }

  @override
  void dispose() {
    _setOnline(false);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _setOnline(true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _setOnline(false);
    }
  }

  Future<void> _setOnline(bool isOnline) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance.collection('profiles').doc(user.uid).set(
      {
        'isOnline': isOnline,
        'lastSeen': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
