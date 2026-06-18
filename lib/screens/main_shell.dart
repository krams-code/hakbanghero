import 'package:flutter/material.dart';
import 'home/home_screen.dart';
import 'activity/activity_screen.dart';
import 'leaderboard/leaderboard_screen.dart';
import 'profile/profile_screen.dart';
import 'package:hakbanghero/screens/character/equipment_screen.dart';
import 'package:hakbanghero/screens/gacha/gacha_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 2; // Start on Home (Run)

  void _navigateTo(int index) => setState(() => _currentIndex = index);

  // Use a getter so _navigateTo is accessible when building the list
  List<Widget> get _screens => [
    const GachaScreen(),                                        // 0 — Gacha
    const EquipmentScreen(),                                    // 1 — Gear
    HomeScreen(onProfileTap: () => _navigateTo(5)),            // 2 — Run (center)
    const LeaderboardScreen(),                                  // 3 — Ranks
    const ActivityScreen(),                                     // 4 — Activity
    ProfileScreen(onBackTap: () => _navigateTo(2)),            // 5 — Profile
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0F0A),
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: _HakbangBottomNav(
        currentIndex: _currentIndex == 5 ? -1 : _currentIndex,
        onTap: _navigateTo,
      ),
    );
  }
}

// ── Bottom Navigation Bar — 5 items (no Profile) ─────────────────────────────
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
        color: const Color(0xFF0D1A0D),
        border: const Border(
          top: BorderSide(color: Color(0xFF1A4A1A), width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00FF41).withValues(alpha: 0.08),
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
                              ? [
                                  const Color(0xFF00FF41),
                                  const Color(0xFF00CC33),
                                ]
                              : [
                                  const Color(0xFF1A4A1A),
                                  const Color(0xFF0D2A0D),
                                ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: const Color(0xFF00FF41)
                                      .withValues(alpha: 0.4),
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
                                ? const Color(0xFF0A0F0A)
                                : const Color(0xFF4A8A4A),
                            size: 22,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.label,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: isSelected
                                  ? const Color(0xFF0A0F0A)
                                  : const Color(0xFF4A8A4A),
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
                            ? const Color(0xFF00FF41)
                            : const Color(0xFF3A5A3A),
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
                              ? const Color(0xFF00FF41)
                              : const Color(0xFF3A5A3A),
                          letterSpacing: 0.5,
                        ),
                      ),
                      if (isSelected)
                        Container(
                          margin: const EdgeInsets.only(top: 3),
                          width: 4,
                          height: 4,
                          decoration: const BoxDecoration(
                            color: Color(0xFF00FF41),
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