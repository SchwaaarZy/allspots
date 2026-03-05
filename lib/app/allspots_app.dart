import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'dart:async';
import '../features/auth/data/account_verification_service.dart';
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
  StreamSubscription<User?>? _authSub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncVerificationMetadata();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        AccountVerificationService.ensureVerificationMetadata(user);
      }
    });
    _setOnline(true);
  }

  @override
  void dispose() {
    _setOnline(false);
    _authSub?.cancel();
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
    try {
      await FirebaseFirestore.instance.collection('profiles').doc(user.uid).set(
        {
          'isOnline': isOnline,
          'lastSeen': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {
      // App en mode strictement en ligne: si réseau indisponible,
      // l'overlay global bloquera l'usage et cette mise à jour sera retentée plus tard.
    }
  }

  Future<void> _syncVerificationMetadata() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await AccountVerificationService.ensureVerificationMetadata(user);
    } catch (_) {
      // Evite de remonter des erreurs réseau au démarrage quand l'app est hors ligne.
    }
  }

  @override
  Widget build(BuildContext context) => _OnlineRequiredGate(child: widget.child);
}

class _OnlineRequiredGate extends StatefulWidget {
  const _OnlineRequiredGate({required this.child});

  final Widget child;

  @override
  State<_OnlineRequiredGate> createState() => _OnlineRequiredGateState();
}

class _OnlineRequiredGateState extends State<_OnlineRequiredGate> {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    _initConnectivity();
    _connectivitySub = _connectivity.onConnectivityChanged.listen((results) {
      _updateOnlineStatus(results);
    });
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  Future<void> _initConnectivity() async {
    final results = await _connectivity.checkConnectivity();
    if (!mounted) return;
    _updateOnlineStatus(results);
  }

  void _updateOnlineStatus(List<ConnectivityResult> results) {
    final online = results.any((result) => result != ConnectivityResult.none);
    if (_isOnline == online) return;
    setState(() {
      _isOnline = online;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (!_isOnline)
          Positioned.fill(
            child: Material(
              color: Colors.white,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.wifi_off,
                          size: 64,
                          color: Colors.red,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Connexion internet requise',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'AllSPOTS fonctionne uniquement en ligne.\n'
                          'Reconnectez-vous pour continuer.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: _initConnectivity,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Réessayer'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
