import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../../core/utils/responsive_utils.dart';
import '../../../core/widgets/glass_app_bar.dart';
import '../../../core/widgets/optimized_image.dart';
import '../../auth/data/auth_providers.dart';
import '../../auth/presentation/profile_setup_page.dart';
import '../../info/info_center_page.dart';
import '../../map/domain/poi.dart';
import '../../map/domain/poi_category.dart';
import 'community_spots_management_page.dart';
import '../data/road_trip_service.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage>
    with SingleTickerProviderStateMixin {
  static const double _tabBarHeight = 74;
  static const double _actionsBarHeight = 56;
  late TabController _tabController;

  double _profileHeaderHeight(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isCompact = size.width < 390 || size.height < 760;
    final ratio = isCompact ? 0.47 : 0.42;
    final minHeight = isCompact ? 330.0 : 300.0;
    final maxHeight = isCompact ? 430.0 : 390.0;
    final height = size.height * ratio;
    return height.clamp(minHeight, maxHeight);
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profileState = ref.watch(profileStreamProvider);
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        appBar: GlassAppBar(title: 'Mon Profil'),
        body: Center(child: Text('Non connecté')),
      );
    }

    return profileState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _buildErrorScreen(context),
      data: (profile) {
        if (profile == null) {
          return _buildIncompleteProfile(context);
        }

        return Scaffold(
          body: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              
              SliverAppBar(
                expandedHeight: _profileHeaderHeight(context) +
                    _actionBarHeight(context),
                floating: false,
                pinned: true,
                toolbarHeight: 0,
                flexibleSpace: FlexibleSpaceBar(
                  background: _buildProfileHeader(profile),
                ),
                bottom: PreferredSize(
                  preferredSize:
                      Size.fromHeight(_tabBarHeight + _actionBarHeight(context)),
                  child: _buildTabAndActions(context),
                ),
              ),
            ],
            body: TabBarView(
              controller: _tabController,
              children: [
                _MyPoiTab(userId: user.uid),
                _FavoritesTab(userId: user.uid),
                const _RoadTripTab(),
                _PremiumTab(profile: profile, user: user),
              ],
            ),
          ),
        );
      },
    );
  }

  double _actionBarHeight(BuildContext context) {
    final tabIndex = _tabController.index;
    final isSpotsTab = tabIndex == 0;
    final isRoadTripTab = tabIndex == 2;
    return (isSpotsTab || isRoadTripTab) ? _actionsBarHeight : 0;
  }

  Widget _buildTabAndActions(BuildContext context) {
    final tabIndex = _tabController.index;
    final isSpotsTab = tabIndex == 0;
    final isRoadTripTab = tabIndex == 2;
    final showActions = isSpotsTab || isRoadTripTab;
    final isCompactWidth = MediaQuery.sizeOf(context).width < 390;

    final createButton = ElevatedButton.icon(
      onPressed: () =>
          context.push(isSpotsTab ? '/spots/new' : '/nearby-results'),
      style: ElevatedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      ),
      icon: Icon(isSpotsTab ? Icons.add_location_alt : Icons.route),
      label: Text(
        isSpotsTab
            ? (isCompactWidth ? 'Créer' : 'Créer un spot')
            : (isCompactWidth ? 'Créer' : 'Créer un Road Trip'),
      ),
    );

    return Material(
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTabBar(),
          if (showActions)
            SizedBox(
              height: _actionsBarHeight,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade200),
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Row(
                      children: [
                        Expanded(child: createButton),
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

  Widget _buildErrorScreen(BuildContext context) {
    return Scaffold(
      appBar: const GlassAppBar(title: 'Mon Profil'),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              const Text('Erreur',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => FirebaseAuth.instance.signOut(),
                child: const Text('Se déconnecter'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIncompleteProfile(BuildContext context) {
    return Scaffold(
      appBar: const GlassAppBar(title: 'Mon Profil'),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.person_add, size: 48, color: Colors.blue),
              const SizedBox(height: 16),
              Text(
                'Complétez votre profil',
                style: TextStyle(
                  fontSize: context.fontSize(18),
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => context.go('/profile'),
                  icon: const Icon(Icons.edit),
                  label: const Text('Créer mon profil'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await FirebaseAuth.instance.signOut();
                    if (!context.mounted) return;
                    context.go('/auth');
                  },
                  icon: const Icon(Icons.logout),
                  label: const Text('Se déconnecter'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileHeader(UserProfile profile) {
    final photoUrl = profile.photoUrl.trim();
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('spots')
          .where('createdBy', isEqualTo: uid)
          .snapshots(),
      builder: (context, spotsSnapshot) {
        final spotsCount = spotsSnapshot.data?.docs.length ?? 0;

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('profiles')
              .doc(uid)
              .collection('favoritePois')
              .snapshots(),
          builder: (context, favsSnapshot) {
            final favsCount = favsSnapshot.data?.docs.length ?? 0;
            final grade = profile.gradeProgress;
            final screenWidth = MediaQuery.sizeOf(context).width;
            final isCompact = screenWidth < 390;

            return SafeArea(
              bottom: false,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.blue.shade600,
                      Colors.blue.shade400,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  children: [
                    // Contenu principal
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        isCompact ? 10 : 14,
                        isCompact ? 10 : 14,
                        isCompact ? 10 : 14,
                        isCompact ? 40 : 48,
                      ),
                      child: Column(
                        children: [
                          // Photo et badges
                          Row(
                            children: [
                              // Photo de profil
                              Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 3,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.2),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: CircleAvatar(
                                  radius: isCompact ? 30 : 36,
                                  backgroundImage: photoUrl.isEmpty
                                      ? null
                                      : NetworkImage(photoUrl),
                                  child: photoUrl.isEmpty
                                      ? Icon(
                                          Icons.person,
                                          size: isCompact ? 30 : 36,
                                        )
                                      : null,
                                ),
                              ),
                              SizedBox(width: isCompact ? 10 : 12),
                              // Nom et localisation
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Nom avec badge premium
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            profile.displayName,
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: context.fontSize(16),
                                              fontWeight: FontWeight.bold,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (profile.hasPremiumPass) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.amber,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.workspace_premium,
                                                  size: 12,
                                                  color: Colors.white,
                                                ),
                                                SizedBox(width: 2),
                                                Text(
                                                  'PRO',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    // Localisation
                                    if (profile.location.isNotEmpty)
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.location_on,
                                            size: 14,
                                            color: Colors.white70,
                                          ),
                                          const SizedBox(width: 4),
                                          Flexible(
                                            child: Text(
                                              profile.location,
                                              style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 13,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    if (profile.categories.isNotEmpty ||
                                        spotsCount > 0 ||
                                        favsCount >= 5) ...[
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: isCompact ? 4 : 6,
                                        runSpacing: isCompact ? 4 : 6,
                                        children: [
                                          if (profile.categories.isNotEmpty)
                                            _buildBadge(
                                              icon: Icons.explore,
                                              label: 'Explorateur',
                                              color: Colors.green,
                                              compact: true,
                                            ),
                                          if (spotsCount > 0)
                                            _buildBadge(
                                              icon: Icons.add_location,
                                              label: 'Contributeur',
                                              color: Colors.orange,
                                              compact: true,
                                            ),
                                          if (favsCount >= 5)
                                            _buildBadge(
                                              icon: Icons.star,
                                              label: 'Collectionneur',
                                              color: Colors.purple,
                                              compact: true,
                                            ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: isCompact ? 8 : 12),
                          // Statistiques
                          Container(
                            padding: EdgeInsets.all(isCompact ? 8 : 10),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                // Spots créés
                                _buildStatItem(
                                  icon: Icons.location_on,
                                  label: 'Spots',
                                  value: spotsCount.toString(),
                                  compact: isCompact,
                                ),
                                // Séparateur
                                Container(
                                  width: 1,
                                  height: 30,
                                  color: Colors.white.withValues(alpha: 0.3),
                                ),
                                // Favoris
                                _buildStatItem(
                                  icon: Icons.favorite,
                                  label: 'Favoris',
                                  value: favsCount.toString(),
                                  compact: isCompact,
                                ),
                                // Séparateur
                                Container(
                                  width: 1,
                                  height: 30,
                                  color: Colors.white.withValues(alpha: 0.3),
                                ),
                                // XP
                                _buildStatItem(
                                  icon: Icons.auto_awesome,
                                  label: 'XP',
                                  value: profile.xp.toString(),
                                  compact: isCompact,
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: isCompact ? 6 : 8),
                          Container(
                            padding: EdgeInsets.all(isCompact ? 8 : 10),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.25),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.workspace_premium,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '${grade.grade} • Niveau ${grade.level}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '${profile.totalVisits} visites',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: isCompact ? 4 : 6),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(999),
                                  child: LinearProgressIndicator(
                                    value: grade.progress,
                                    minHeight: 7,
                                    backgroundColor:
                                        Colors.white.withValues(alpha: 0.25),
                                    valueColor:
                                        const AlwaysStoppedAnimation<Color>(
                                      Colors.amber,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${grade.currentLevelXp}/${grade.requiredXpForNextLevel} XP vers le niveau suivant',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: isCompact ? 10 : 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: isCompact ? 6 : 10),
                        ],
                      ),
                    ),
                    // Boutons infos + paramètres
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.info_outline,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const InfoCenterPage(),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            icon: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.settings,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (dialogContext) => AlertDialog(
                                  title: const Text(
                                    'Paramètres',
                                    textAlign: TextAlign.center,
                                  ),
                                  content: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Text(
                                        'Que voulez-vous faire?',
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 12),
                                      SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton.icon(
                                          onPressed: () {
                                            Navigator.pop(dialogContext);
                                            context.push('/users/$uid');
                                          },
                                          icon: const Icon(Icons.public),
                                          label: const Text('Voir profil public'),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton.icon(
                                          onPressed: () {
                                            Navigator.pop(dialogContext);
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) =>
                                                    const ProfileSetupPage(),
                                              ),
                                            );
                                          },
                                          icon: const Icon(Icons.edit),
                                          label: const Text('Modifier profil'),
                                        ),
                                      ),
                                      if (profile.isAdmin) ...[
                                        const SizedBox(height: 8),
                                        SizedBox(
                                          width: double.infinity,
                                          child: ElevatedButton.icon(
                                            onPressed: () {
                                              Navigator.pop(dialogContext);
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      const CommunitySpotsManagementPage(),
                                                ),
                                              );
                                            },
                                            icon: const Icon(Icons.admin_panel_settings),
                                            label: const Text('Admin'),
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 8),
                                      SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton.icon(
                                          onPressed: () {
                                            Navigator.pop(dialogContext);
                                            _showDeleteAccountDialog(context);
                                          },
                                          icon: const Icon(Icons.delete),
                                          label: const Text('Supprimer compte'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.red,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton.icon(
                                          onPressed: () async {
                                            final ctx = context;
                                            Navigator.pop(dialogContext);
                                            await FirebaseAuth.instance.signOut();
                                            if (ctx.mounted) ctx.go('/auth');
                                          },
                                          icon: const Icon(Icons.logout),
                                          label: const Text('Se déconnecter'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.orange,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(dialogContext),
                                        child: const Text('Annuler'),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    bool compact = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white, size: compact ? 18 : 24),
        SizedBox(height: compact ? 2 : 4),
        Text(
          value,
          style: TextStyle(
            color: Colors.white,
            fontSize: compact ? 14 : 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white70,
            fontSize: compact ? 9 : 11,
          ),
        ),
      ],
    );
  }

  Widget _buildBadge({
    required IconData icon,
    required String label,
    required Color color,
    bool compact = false,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: compact ? 12 : 14,
            color: Colors.white,
          ),
          SizedBox(width: compact ? 4 : 6),
          Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    final isCompact = MediaQuery.sizeOf(context).width < 390;

    return Container(
      color: Colors.white,
      child: TabBar(
        controller: _tabController,
        labelColor: Colors.blue,
        unselectedLabelColor: Colors.grey,
        indicatorColor: Colors.blue,
        indicatorWeight: 2,
        labelStyle: TextStyle(
          fontSize: isCompact ? 10 : 12,
          fontWeight: FontWeight.w600,
          height: 1.1,
        ),
        unselectedLabelStyle: TextStyle(
          fontSize: isCompact ? 10 : 12,
          fontWeight: FontWeight.w500,
          height: 1.1,
        ),
        labelPadding: const EdgeInsets.symmetric(horizontal: 8),
        tabs: [
          Tab(
            icon: Icon(Icons.location_on, size: isCompact ? 14 : 15),
            text: 'Spots',
          ),
          Tab(
            icon: Icon(Icons.favorite, size: isCompact ? 14 : 15),
            text: 'Favoris',
          ),
          Tab(
            icon: Icon(Icons.route, size: isCompact ? 14 : 15),
            text: 'Road Trip',
          ),
          Tab(
            icon: Icon(Icons.workspace_premium, size: isCompact ? 14 : 15),
            text: 'Premium',
          ),
        ],
      ),
    );
  }

  void _showDeleteAccountDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('⚠️ Supprimer le compte'),
        content: const Text(
          'Êtes-vous sûr? Cette action est irréversible. '
          'Toutes vos données seront supprimées.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () async {
              final ctx = context;
              try {
                final user = FirebaseAuth.instance.currentUser;
                if (user != null) {
                  // Supprimer les données Firestore
                  await FirebaseFirestore.instance
                      .collection('profiles')
                      .doc(user.uid)
                      .delete();

                  // Supprimer les spots créés
                  final spots = await FirebaseFirestore.instance
                      .collection('spots')
                      .where('createdBy', isEqualTo: user.uid)
                      .get();

                  for (var doc in spots.docs) {
                    await doc.reference.delete();
                  }

                  // Supprimer le compte Firebase
                  await user.delete();

                  if (ctx.mounted) {
                    Navigator.pop(dialogContext);
                    ctx.go('/auth');
                  }
                }
              } catch (e) {
                if (ctx.mounted) {
                  Navigator.pop(dialogContext);
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('Erreur: $e')),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Supprimer définitivement'),
          ),
        ],
      ),
    );
  }
}

class _MyPoiTab extends ConsumerStatefulWidget {
  final String userId;

  const _MyPoiTab({required this.userId});

  @override
  ConsumerState<_MyPoiTab> createState() => _MyPoiTabState();
}

class _MyPoiTabState extends ConsumerState<_MyPoiTab> {
  int _currentPage = 0;
  static const int _itemsPerPage = 5;

  @override
  Widget build(BuildContext context) {
    final firestore = FirebaseFirestore.instance;

    return StreamBuilder<QuerySnapshot>(
      stream: firestore
          .collection('spots')
          .where('createdBy', isEqualTo: widget.userId)
          .snapshots(),
      builder: (context, snapshot) {
        final allSpots = snapshot.data?.docs ?? [];

        if (allSpots.isEmpty) {
          final bottomInset = MediaQuery.paddingOf(context).bottom;
          return SafeArea(
            top: false,
            minimum: EdgeInsets.only(bottom: bottomInset > 0 ? 4 : 8),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.location_on, size: 48, color: Colors.blue),
                    const SizedBox(height: 12),
                    const Text(
                      'Vous n\'avez pas encore créé de spots.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final totalPages = (allSpots.length / _itemsPerPage).ceil();
        final startIndex = _currentPage * _itemsPerPage;
        final endIndex = (startIndex + _itemsPerPage).clamp(0, allSpots.length);
        final visibleSpots = allSpots.sublist(startIndex, endIndex);
        final bottomInset = MediaQuery.paddingOf(context).bottom;

        return SafeArea(
          top: false,
          minimum: EdgeInsets.only(bottom: bottomInset > 0 ? 4 : 8),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Spots: ${allSpots.length}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        if (totalPages > 1)
                          Text(
                            'Page ${_currentPage + 1} / $totalPages',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 12),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + bottomInset),
                  itemCount: visibleSpots.length,
                  itemBuilder: (context, index) {
                    final doc = visibleSpots[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final spot = Poi(
                      id: doc.id,
                      name: data['name'] ?? '',
                      category:
                          poiCategoryFromString(data['categoryGroup'] ?? ''),
                      subCategory: data['categoryItem'],
                      lat: data['lat'] ?? 0,
                      lng: data['lng'] ?? 0,
                      shortDescription: data['description'] ?? '',
                      imageUrls: [],
                      source: 'firestore',
                      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ??
                          DateTime.now(),
                    );

                    return _PoiTile(
                      poi: spot,
                      onEdit: () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Modification à implémenter')),
                      ),
                      onDelete: () => _deleteSpot(context, doc.id),
                      showActions: true,
                    );
                  },
                ),
              ),
              if (totalPages > 1)
                Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 4,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: _currentPage > 0
                            ? () => setState(() => _currentPage--)
                            : null,
                      ),
                      Text(
                        '${_currentPage + 1} / $totalPages',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.arrow_forward),
                        onPressed: _currentPage < totalPages - 1
                            ? () => setState(() => _currentPage++)
                            : null,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _deleteSpot(BuildContext context, String spotId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer ce spot?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () async {
              await FirebaseFirestore.instance
                  .collection('spots')
                  .doc(spotId)
                  .delete();
              if (!context.mounted) return;
              Navigator.pop(context);
              // Réinitialiser à la page 0 si on supprime le dernier élément de la dernière page
              setState(() {
                _currentPage = 0;
              });
            },
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
  }
}

class _FavoritesTab extends ConsumerStatefulWidget {
  final String userId;

  const _FavoritesTab({required this.userId});

  @override
  ConsumerState<_FavoritesTab> createState() => _FavoritesTabState();
}

class _FavoritesTabState extends ConsumerState<_FavoritesTab> {
  int _currentPage = 0;
  static const int _itemsPerPage = 5;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('profiles')
          .doc(widget.userId)
          .collection('favoritePois')
          .orderBy('updatedAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final allSpots = snapshot.data!.docs;
        if (allSpots.isEmpty) {
          final bottomInset = MediaQuery.paddingOf(context).bottom;
          return SafeArea(
            top: false,
            minimum: EdgeInsets.only(bottom: bottomInset > 0 ? 4 : 8),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.favorite, size: 48, color: Colors.red),
                    const SizedBox(height: 12),
                    const Text('Aucun favori pour le moment',
                        textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
          );
        }

        final totalPages = (allSpots.length / _itemsPerPage).ceil();
        final startIndex = _currentPage * _itemsPerPage;
        final endIndex = (startIndex + _itemsPerPage).clamp(0, allSpots.length);
        final visibleSpots = allSpots.sublist(startIndex, endIndex);

        final bottomInset = MediaQuery.paddingOf(context).bottom;

        return SafeArea(
          top: false,
          minimum: EdgeInsets.only(bottom: bottomInset > 0 ? 4 : 8),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Favoris: ${allSpots.length}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        if (totalPages > 1)
                          Text(
                            'Page ${_currentPage + 1} / $totalPages',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 12),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + bottomInset),
                  children: [
                    for (final doc in visibleSpots)
                      _FavoriteTile(
                        spotId: doc.id,
                        spotData: doc.data() as Map<String, dynamic>,
                        userId: widget.userId,
                      ),
                  ],
                ),
              ),
              if (totalPages > 1)
                Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 4,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: _currentPage > 0
                            ? () => setState(() => _currentPage--)
                            : null,
                      ),
                      Text(
                        '${_currentPage + 1} / $totalPages',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.arrow_forward),
                        onPressed: _currentPage < totalPages - 1
                            ? () => setState(() => _currentPage++)
                            : null,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _FavoriteTile extends ConsumerWidget {
  final String spotId;
  final Map<String, dynamic> spotData;
  final String userId;

  const _FavoriteTile({
    required this.spotId,
    required this.spotData,
    required this.userId,
  });

  void _removeFavorite(BuildContext context, WidgetRef ref) async {
    try {
      await FirebaseFirestore.instance
          .collection('profiles')
          .doc(userId)
          .update({
        'favoritePoiIds': FieldValue.arrayRemove([spotId]),
      });
      await FirebaseFirestore.instance
          .collection('profiles')
          .doc(userId)
          .collection('favoritePois')
          .doc(spotId)
          .delete();
    } catch (e) {
      debugPrint('Erreur suppression favori: $e');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final previewImageHeight =
      context.imageHeight.clamp(120.0, 180.0).toDouble();
    final categoryRaw = spotData['category'] as String?;
    final category = categoryRaw != null
        ? poiCategoryFromString(categoryRaw)
        : PoiCategory.culture;
    final subCategoryLabel =
        formatPoiSubCategory(spotData['subCategory'] as String?);
    final categoryLabel =
        subCategoryLabel.isNotEmpty ? subCategoryLabel : category.label;
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _FavoriteDetailPage(
            spotId: spotId,
            spotData: spotData,
          ),
        ),
      ),
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Photo d'aperçu
            if (spotData['imageUrls'] != null &&
                (spotData['imageUrls'] as List?)?.isNotEmpty == true)
              SizedBox(
                height: previewImageHeight,
                width: double.infinity,
                child: ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(4)),
                  child: OptimizedNetworkImage(
                    imageUrl: (spotData['imageUrls'] as List).first,
                    height: previewImageHeight,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              spotData['name'] ?? 'Spot',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: context.fontSize(14),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  category.icon,
                                  size: 14,
                                  color: category.color,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  categoryLabel,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                            if (spotData['googleRating'] != null) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.star,
                                      color: Colors.amber, size: 16),
                                  const SizedBox(width: 4),
                                  Text(
                                      '${(spotData['googleRating'] as num).toStringAsFixed(1)}/5',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600)),
                                ],
                              )
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.favorite, color: Colors.red),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => _removeFavorite(context, ref),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FavoriteDetailPage extends StatelessWidget {
  final String spotId;
  final Map<String, dynamic> spotData;

  const _FavoriteDetailPage({
    required this.spotId,
    required this.spotData,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrls = spotData['imageUrls'] as List? ?? [];
    final googleRating = spotData['googleRating'] as num?;
    final categoryRaw = spotData['category'] as String?;
    final category = categoryRaw != null
        ? poiCategoryFromString(categoryRaw)
        : PoiCategory.culture;
    final subCategoryLabel =
        formatPoiSubCategory(spotData['subCategory'] as String?);
    final categoryLabel =
        subCategoryLabel.isNotEmpty ? subCategoryLabel : category.label;

    return Scaffold(
      appBar: GlassAppBar(
          title: spotData['name'] ?? 'Détail', showBackButton: true),
      body: ListView(
        children: [
          // Photos
          if (imageUrls.isNotEmpty)
            SizedBox(
              height: context.imageHeight,
              child: PageView(
                children: [
                  for (final imageUrl in imageUrls)
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(8)),
                      child: OptimizedNetworkImage(
                        imageUrl: imageUrl,
                        height: context.imageHeight,
                        fit: BoxFit.cover,
                      ),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  spotData['name'] ?? 'Spot',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(category.icon, size: 16, color: category.color),
                    const SizedBox(width: 6),
                    Text(
                      categoryLabel,
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Note Google
                if (googleRating != null) ...[
                  Row(
                    children: [
                      const Icon(Icons.star, color: Colors.amber, size: 20),
                      const SizedBox(width: 6),
                      Text(
                        '$googleRating/5',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '(${spotData['googleRatingCount'] ?? 0} avis)',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12)
                ],
                Text(
                  spotData['description'] ?? 'Pas de description',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                if (spotData['lat'] != null && spotData['lng'] != null)
                  Text(
                    '📍 ${spotData['lat']}, ${spotData['lng']}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  children: [
                    if (spotData['isFree'] == true)
                      const Chip(
                          label: Text('Gratuit',
                              style: TextStyle(color: Colors.white)),
                          backgroundColor: Colors.green),
                    if (spotData['pmrAccessible'] == true)
                      const Chip(
                          label: Text('Accessible',
                              style: TextStyle(color: Colors.white)),
                          backgroundColor: Colors.blue),
                    if (spotData['kidsFriendly'] == true)
                      const Chip(
                          label: Text('Famille',
                              style: TextStyle(color: Colors.white)),
                          backgroundColor: Colors.orange),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoadTripTab extends ConsumerStatefulWidget {
  const _RoadTripTab();

  @override
  ConsumerState<_RoadTripTab> createState() => _RoadTripTabState();
}

class _RoadTripTabState extends ConsumerState<_RoadTripTab> {
  bool _loadingRoute = false;
  String? _routeError;
  double? _distanceMeters;
  double? _durationSeconds;
  String _lastRouteKey = '';

  Future<void> _fetchRoute(List<RoadTripItem> items) async {
    if (items.length < 2) {
      if (!mounted) return;
      setState(() {
        _distanceMeters = null;
        _durationSeconds = null;
        _routeError = null;
        _loadingRoute = false;
      });
      return;
    }

    setState(() {
      _loadingRoute = true;
      _routeError = null;
    });

    final coords = items.map((item) => '${item.lng},${item.lat}').join(';');
    final url = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/$coords'
      '?overview=false',
    );

    try {
      final res = await http.get(url);
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}');
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final routes = data['routes'] as List<dynamic>;
      if (routes.isEmpty) {
        throw Exception('Aucun itineraire');
      }
      final route = routes.first as Map<String, dynamic>;
      final distance = (route['distance'] as num?)?.toDouble();
      final duration = (route['duration'] as num?)?.toDouble();

      if (!mounted) return;
      setState(() {
        _distanceMeters = distance;
        _durationSeconds = duration;
        _loadingRoute = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _routeError = 'Impossible de calculer l\'itineraire';
        _loadingRoute = false;
      });
    }
  }

  void _scheduleRouteUpdate(List<RoadTripItem> items) {
    final key = items.map((i) => '${i.source}:${i.id}').join('|');
    if (key == _lastRouteKey) return;
    _lastRouteKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchRoute(items);
    });
  }

  String _formatDistance(double? meters) {
    if (meters == null) return '-';
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }
    return '${meters.toStringAsFixed(0)} m';
  }

  String _formatDuration(double? seconds) {
    if (seconds == null) return '-';
    final mins = (seconds / 60).round();
    if (mins < 60) return '$mins min';
    final hours = mins ~/ 60;
    final rem = mins % 60;
    return '${hours}h ${rem}m';
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(
          child: Text('Connectez-vous pour creer un road trip'));
    }

    final profile = ref.watch(profileStreamProvider).value;
    final hasPremiumPass = profile?.hasPremiumPass ?? false;
    final maxItems = RoadTripService.maxItemsFor(hasPremiumPass);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: RoadTripService.stream(user.uid),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final rawItems = (data?['items'] as List?) ?? [];
        final items = rawItems
            .whereType<Map>()
            .map((e) => RoadTripItem.fromMap(Map<String, dynamic>.from(e)))
            .toList();

        _scheduleRouteUpdate(items);

        if (items.isEmpty) {
          final bottomInset = MediaQuery.paddingOf(context).bottom;
          return SafeArea(
            top: false,
            minimum: EdgeInsets.only(bottom: bottomInset > 0 ? 4 : 8),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.route, size: 48, color: Colors.blue),
                    const SizedBox(height: 12),
                    Text(
                      'Creez votre road trip avec jusqu\'a $maxItems spots.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final bottomInset = MediaQuery.paddingOf(context).bottom;

        return SafeArea(
          top: false,
          minimum: EdgeInsets.only(bottom: bottomInset > 0 ? 4 : 8),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Spots: ${items.length}/$maxItems',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextButton(
                          onPressed: () => RoadTripService.clear(user.uid),
                          child: const Text('Vider'),
                        ),
                      ],
                    ),
                    if (_loadingRoute)
                      const LinearProgressIndicator(minHeight: 2)
                    else if (_routeError != null)
                      Text(
                        _routeError!,
                        style: const TextStyle(color: Colors.red),
                      )
                    else
                      Row(
                        children: [
                          const Icon(Icons.directions, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            'Distance: ${_formatDistance(_distanceMeters)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Duree: ${_formatDuration(_durationSeconds)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ReorderableListView.builder(
                  padding: EdgeInsets.only(bottom: 12 + bottomInset),
                  itemCount: items.length,
                  onReorder: (oldIndex, newIndex) {
                    if (newIndex > oldIndex) newIndex--;
                    final updated = [...items];
                    final moved = updated.removeAt(oldIndex);
                    updated.insert(newIndex, moved);
                    RoadTripService.saveItems(user.uid, updated);
                    _scheduleRouteUpdate(updated);
                  },
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final category = poiCategoryFromString(item.category);
                    final subLabel = formatPoiSubCategory(item.subCategory);
                    return ListTile(
                      key: ValueKey('${item.source}_${item.id}'),
                      leading: Icon(category.icon, color: category.color),
                      title: Text(
                        item.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        subLabel.isNotEmpty ? subLabel : category.label,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => RoadTripService.removeAt(
                              user.uid,
                              index,
                            ),
                          ),
                          ReorderableDragStartListener(
                            index: index,
                            child: const Icon(Icons.drag_handle),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PremiumTab extends ConsumerWidget {
  final UserProfile profile;
  final User user;

  const _PremiumTab({
    required this.profile,
    required this.user,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final premiumTitleSize = context.fontSize(28).clamp(22.0, 32.0).toDouble();
    final premiumPriceSize = context.fontSize(24).clamp(18.0, 28.0).toDouble();
    final sectionTitleSize = context.fontSize(20).clamp(16.0, 24.0).toDouble();
    final detailTitleSize = context.fontSize(16).clamp(14.0, 20.0).toDouble();
    final ctaSize = context.fontSize(18).clamp(15.0, 22.0).toDouble();
    final premiumBadgeTitleSize =
        context.fontSize(16).clamp(14.0, 20.0).toDouble();

    return SafeArea(
      top: false,
      minimum: EdgeInsets.only(bottom: bottomInset > 0 ? 4 : 8),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // En-tête Premium
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.blue.shade600,
                    Colors.blue.shade400,
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.workspace_premium,
                    size: 80,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Passez Premium',
                    style: TextStyle(
                      fontSize: premiumTitleSize,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '2.99€ pour 30 jours',
                    style: TextStyle(
                      fontSize: premiumPriceSize,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            // Avantages Premium
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Avantages Premium',
                      style: TextStyle(
                        fontSize: sectionTitleSize,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const ListTile(
                      leading:
                          Icon(Icons.check_circle, color: Colors.green, size: 32),
                      title: Text('Sans publicité'),
                      subtitle: Text('Profitez d\'une expérience fluide'),
                    ),
                    const ListTile(
                      leading:
                          Icon(Icons.check_circle, color: Colors.green, size: 32),
                      title: Text('Recherches illimitées'),
                      subtitle:
                          Text('Accès complet à toutes les fonctionnalités'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Détails de l'abonnement
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Détails:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: detailTitleSize,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildDetail('Durée', '30 jours'),
                  _buildDetail('Renouvellement', 'Automatique'),
                  _buildDetail('Annulation', 'Possible à tout moment'),
                ],
              ),
            ),
            const SizedBox(height: 32),
            if (profile.hasPremiumPass)
              Card(
                color: Colors.amber.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.verified,
                          color: Colors.amber.shade700, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Vous êtes Premium ✓',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: premiumBadgeTitleSize,
                              ),
                            ),
                            Text(
                              'Merci de votre soutien!',
                              style: TextStyle(
                                fontSize:
                                    context.fontSize(12).clamp(11.0, 14.0),
                                color: Colors.amber.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _buyPremium(context, user),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade600,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.shopping_cart),
                  label: Text(
                    'Activer Premium - 2.99€',
                    style: TextStyle(
                      fontSize: ctaSize,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value, style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  void _buyPremium(BuildContext context, User user) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('🎉 Sans pub'),
        content: const Text(
            'Accès illimité aux recherches et sans publicité pour seulement 2.99€.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              // Activer le pass premium dans Firestore
              await FirebaseFirestore.instance
                  .collection('profiles')
                  .doc(user.uid)
                  .update({'hasPremiumPass': true});

              final expiryDate = DateTime.now().add(const Duration(days: 30));
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .set({
                'isPremium': true,
                'premiumExpiryDate': Timestamp.fromDate(expiryDate),
                'premiumActivationDate': Timestamp.fromDate(DateTime.now()),
                'premiumPrice': 2.99,
                'premiumDuration': 30,
              }, SetOptions(merge: true));

              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('✅ Merci! Vous êtes passé en premium.'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: const Text('Confirmer (2.99€)'),
          ),
        ],
      ),
    );
  }
}

class _PoiTile extends StatelessWidget {
  final Poi poi;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final bool showActions;

  const _PoiTile({
    required this.poi,
    required this.onEdit,
    required this.onDelete,
    this.showActions = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        poi.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        poi.subCategory ?? poi.category.label,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                if (showActions)
                  PopupMenuButton(
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        onTap: onEdit,
                        child: const Text('✏️ Modifier'),
                      ),
                      PopupMenuItem(
                        onTap: onDelete,
                        child: const Text('🗑️ Supprimer'),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              poi.shortDescription,
              style: const TextStyle(fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
