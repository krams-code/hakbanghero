import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'activity/activity_screen.dart';
import 'leaderboard/leaderboard_screen.dart';
import 'profile/profile_screen.dart';

import 'package:hakbanghero/screens/character/equipment_screen.dart';
import 'package:hakbanghero/screens/shop/avatar_shop_screen.dart';
import 'package:hakbanghero/screens/bosses/boss_map_screen.dart';
import 'package:hakbanghero/run/run_tracking_screen.dart';

import '../widgets/block_navbar.dart';
import '../widgets/block_ui.dart';
import '../widgets/global_top_bar.dart';
import '../widgets/onboarding_tutorial.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  // 0 = SHOP, 1 = GEAR, 2 = RUN, 3 = RANKS, 4 = ACTIVITY, 5 = PROFILE
  int _currentIndex = 2;

  /// True from warm-up until the session summary is dismissed.
  /// While true the bottom nav bar is removed so a stray tap can't
  /// interrupt tracking.
  bool _isTrackingActive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeStartTutorial());
  }

  void _navigateTo(int index) {
    if (_isTrackingActive) return; // belt and braces
    setState(() => _currentIndex = index);
  }

  void _onTrackingChanged(bool active) {
    if (_isTrackingActive == active) return;
    setState(() {
      _isTrackingActive = active;
      if (active) _currentIndex = 2;
    });
  }

  // ── Onboarding ────────────────────────────────────────────────────────
  // CharacterCreationScreen writes `tutorial_done: false` for brand-new
  // players. Existing accounts have no such field, so they never see it.
  Future<void> _maybeStartTutorial() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final ref = FirebaseFirestore.instance.collection('users').doc(uid);
      final snap = await ref.get();
      if (snap.data()?['tutorial_done'] != false) return;
      if (!mounted) return;

      setState(() => _currentIndex = 2); // hero, milestone bar, RUN button
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;

      OnboardingTutorial.show(
        context,
        onFinished: () => ref.update({'tutorial_done': true}).catchError((_) {}),
      );
    } catch (_) {
      // never block the app on the tutorial
    }
  }

  List<Widget> get _screens => [
        const AvatarShopScreen(),
        const EquipmentScreen(),
        RunTrackingScreen(
          onExit: () => _navigateTo(0),
          onActiveChanged: _onTrackingChanged,
        ),
        const LeaderboardScreen(),
        const ActivityScreen(),
        ProfileScreen(onBackTap: () => _navigateTo(2)),
      ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Rb.bg,
      body: Column(
        children: [
          // Global header: profile block + username + logout tray.
          // Hidden mid-run so nothing can interrupt tracking.
          if (!_isTrackingActive)
            GlobalTopBar(onOpenProfile: () => _navigateTo(5)),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              // the top bar already covers the status-bar inset
              removeTop: !_isTrackingActive,
              child: Stack(
                children: [
                  IndexedStack(index: _currentIndex, children: _screens),

          // Boss Map block button — RUN tab only, never mid-run.
          if (_currentIndex == 2 && !_isTrackingActive)
            Positioned(
              right: 12,
              bottom: 16,
              child: PressBlock(
                color: Rb.gold,
                edge: Rb.goldEdge,
                depth: 5,
                radius: 12,
                padding: EdgeInsets.zero,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const BossMapScreen()),
                ),
                child: const SizedBox(
                  width: 52,
                  height: 52,
                  child: Center(
                    child: Text('🗺️', style: TextStyle(fontSize: 26)),
                  ),
                ),
              ),
            ),
                ],
              ),
            ),
          ),
        ],
      ),
      // Removed entirely during an active run.
      bottomNavigationBar: _isTrackingActive
          ? null
          : BlockNavBar(
              currentIndex: _currentIndex == 5 ? -1 : _currentIndex,
              onTap: _navigateTo,
            ),
    );
  }
}
