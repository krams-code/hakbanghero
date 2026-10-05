import 'package:flutter/material.dart';

import 'activity/activity_screen.dart';
import 'leaderboard/leaderboard_screen.dart';
import 'profile/profile_screen.dart';

import 'package:hakbanghero/screens/character/equipment_screen.dart';
import 'package:hakbanghero/screens/gacha/gacha_screen.dart';
import 'package:hakbanghero/screens/bosses/boss_map_screen.dart';
import 'package:hakbanghero/run/run_tracking_screen.dart';

import '../theme/app_colors.dart';
import '../widgets/block_navbar.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  // 0 = SHOP
  // 1 = GEAR
  // 2 = RUN
  // 3 = RANKS
  // 4 = ACTIVITY
  // 5 = PROFILE
  int _currentIndex = 2;

  void _navigateTo(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  List<Widget> get _screens => [
        const GachaScreen(),
        const EquipmentScreen(),
        RunTrackingScreen(
          onExit: () => _navigateTo(0),
        ),
        const LeaderboardScreen(),
        const ActivityScreen(),
        ProfileScreen(
          onBackTap: () => _navigateTo(2),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDeep,

      body: Stack(
        children: [
          IndexedStack(
            index: _currentIndex,
            children: _screens,
          ),

          // Boss Map floating button
          Positioned(
            right: 12,
            bottom: 90,
            child: GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const BossMapScreen(),
                  ),
                );
              },
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      AppColors.gold,
                      AppColors.orange,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.gold.withOpacity(0.4),
                      blurRadius: 12,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.map,
                  color: Colors.black,
                  size: 26,
                ),
              ),
            ),
          ),
        ],
      ),

      bottomNavigationBar: BlockNavBar(
        currentIndex: _currentIndex == 5 ? -1 : _currentIndex,
        onTap: _navigateTo,
      ),
    );
  }
}