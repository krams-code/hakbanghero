import 'package:flutter/material.dart';
import 'home/home_screen.dart';
import 'activity/activity_screen.dart';
import 'leaderboard/leaderboard_screen.dart';
import 'profile/profile_screen.dart';
import 'package:hakbanghero/screens/character/equipment_screen.dart';
import 'package:hakbanghero/screens/gacha/gacha_screen.dart';
import '../theme/app_colors.dart';
import 'bosses/boss_map_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 2; // Start on Home (Run)

  void _navigateTo(int index) => setState(() => _currentIndex = index);

  List<Widget> get _screens => [
    const GachaScreen(),
    const EquipmentScreen(),
    HomeScreen(onProfileTap: () => _navigateTo(5)),
    const LeaderboardScreen(),
    const ActivityScreen(),
    ProfileScreen(onBackTap: () => _navigateTo(2)),
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
    Positioned(
      right: 12,
      bottom: 90, // sits above the bottom nav bar
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const BossMapScreen()),
        ),
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [AppColors.gold, AppColors.orange]),
            boxShadow: [BoxShadow(color: AppColors.gold.withOpacity(0.4), blurRadius: 12)],
          ),
          child: const Icon(Icons.map, color: Colors.black, size: 26),
        ),
      ),
    ),
  ],
),
      bottomNavigationBar: _HakbangBottomNav(
        currentIndex: _currentIndex == 5 ? -1 : _currentIndex,
        onTap: _navigateTo,
      ),
    );
  }
}

class _HakbangBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _HakbangBottomNav({
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const items = [
      _NavItem(icon: Icons.auto_awesome,   label: 'Gacha'),
      _NavItem(icon: Icons.shield,         label: 'Gear'),
      _NavItem(icon: Icons.directions_run, label: 'Run', isCenter: true),
      _NavItem(icon: Icons.leaderboard,    label: 'Ranks'),
      _NavItem(icon: Icons.bolt,           label: 'Activity'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgPanel,
        border: const Border(
          top: BorderSide(color: AppColors.borderDim, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.blue.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          height: 64,
          child: Row(
            children: List.generate(items.length, (i) {
              final item = items[i];
              final isSelected = currentIndex == i;

              if (item.isCenter) {
                return Expanded(
                  child: GestureDetector(
                    onTap: () => onTap(i),
                    child: Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isSelected
                              ? [AppColors.blue, AppColors.cyan]
                              : [AppColors.borderDim, AppColors.bgCard],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: AppColors.blue.withOpacity(0.4),
                                  blurRadius: 12,
                                  spreadRadius: 2,
                                ),
                              ]
                            : [],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            item.icon,
                            color: isSelected
                                ? Colors.white
                                : AppColors.textSub,
                            size: 22,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.label,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: isSelected
                                  ? Colors.white
                                  : AppColors.textSub,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              return Expanded(
                child: GestureDetector(
                  onTap: () => onTap(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        item.icon,
                        color: isSelected
                            ? AppColors.blue
                            : AppColors.textSub,
                        size: 20,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: isSelected
                              ? AppColors.blue
                              : AppColors.textSub,
                          letterSpacing: 0.5,
                        ),
                      ),
                      if (isSelected)
                        Container(
                          margin: const EdgeInsets.only(top: 3),
                          width: 4,
                          height: 4,
                          decoration: const BoxDecoration(
                            color: AppColors.blue,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final bool isCenter;
  const _NavItem(
      {required this.icon, required this.label, this.isCenter = false});
}