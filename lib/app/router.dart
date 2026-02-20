import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../features/auth/data/auth_providers.dart';
import '../features/auth/presentation/auth_page.dart';
import '../features/auth/presentation/profile_setup_page.dart';
import '../features/auth/presentation/splash_page.dart';
import '../features/home/presentation/home_shell.dart';
import '../features/map/presentation/map_page.dart';
import '../features/map/presentation/nearby_results_page.dart';
import '../features/spots/presentation/create_spot_page.dart';
import '../features/search/presentation/search_page.dart';
import '../features/profile/presentation/public_profile_page.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  ref.watch(authStateProvider);
  ref.watch(profileStreamProvider);

  return GoRouter(
    initialLocation: '/splash',
    routes: [
      GoRoute(
        path: '/',
        redirect: (_, __) => '/home',
      ),
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashPage(),
      ),
      GoRoute(
        path: '/auth',
        builder: (context, state) => const AuthPage(),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfileSetupPage(),
      ),
      GoRoute(
        path: '/profile/edit',
        builder: (context, state) => const ProfileSetupPage(),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => const HomeShell(),
      ),
      GoRoute(
        path: '/spots/new',
        builder: (context, state) => const CreateSpotPage(),
      ),
      GoRoute(
        path: '/map',
        builder: (context, state) => const MapPage(),
      ),
      GoRoute(
        path: '/search',
        builder: (context, state) => const SearchPage(),
      ),
      GoRoute(
        path: '/users/:uid',
        builder: (context, state) {
          final uid = state.pathParameters['uid'] ?? '';
          return PublicProfilePage(userId: uid);
        },
      ),
      GoRoute(
        path: '/nearby-results',
        pageBuilder: (context, state) => const CupertinoPage(
          child: NearbyResultsPage(),
        ),
      ),
    ],
    redirect: (context, state) {
      final authState = ref.read(authStateProvider);
      final isLoggingIn = state.matchedLocation == '/auth';
      final isOnProfile = state.matchedLocation == '/profile';
      final isOnProfileEdit = state.matchedLocation == '/profile/edit';
      final isOnSplash = state.matchedLocation == '/splash';

      if (authState.isLoading) {
        return isOnSplash ? null : '/splash';
      }

      final user = authState.value;
      if (user == null) {
        return isLoggingIn ? null : '/auth';
      }

      final profileState = ref.read(profileStreamProvider);
      if (profileState.isLoading) {
        return isOnSplash ? null : '/splash';
      }

      final profile = profileState.value;
      if (profile == null) {
        if (isOnProfileEdit) return '/profile';
        return isOnProfile ? null : '/profile';
      }

      if (isLoggingIn || isOnProfile || isOnSplash) {
        return '/home';
      }

      return null;
    },
  );
});
