import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_theme.dart';
import 'router.dart';

class AllSpotsApp extends ConsumerWidget {
  const AllSpotsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'AllSpots',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: AppTheme.light(),
    );
  }
}
