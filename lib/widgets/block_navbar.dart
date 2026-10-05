import 'package:flutter/material.dart';
import 'block_ui.dart';
import 'tutorial_keys.dart';

/// Roblox-style bottom navigation bar.
///
/// Indexes:
/// 0 = SHOP
/// 1 = GEAR
/// 2 = RUN
/// 3 = RANKS
/// 4 = ACTIVITY
///
/// The RUN button pops above the navigation bar.
class BlockNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const BlockNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  static const double _barHeight = 74;
  static const double _pop = 28;

  static const List<(int, String, String)> _side = [
    (0, '🛒', 'SHOP'),
    (1, '🛡️', 'GEAR'),
    (3, '🏆', 'RANKS'),
    (4, '⚡', 'ACTIVITY'),
  ];

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).padding.bottom;

    Widget slot((int, String, String) item) {
      final selected = currentIndex == item.$1;

      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: PressBlock(
            color: selected ? Rb.gold : Rb.panel,
            edge: selected ? Rb.goldEdge : Rb.panelEdge,
            depth: 5,
            radius: 12,
            forcePressed: selected,
            padding: EdgeInsets.zero,
            onTap: () => onTap(item.$1),
            child: SizedBox(
              height: 50,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    item.$2,
                    style: const TextStyle(fontSize: 20),
                  ),
                  const SizedBox(height: 1),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: BlockText(
                      item.$3,
                      size: 9,
                      stroke: 2.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: _barHeight + _pop + inset,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Main navigation bar
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: _barHeight + inset,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                8,
                10,
                8,
                6 + inset,
              ),
              decoration: const BoxDecoration(
                color: Rb.slate,
                border: Border(
                  top: BorderSide(
                    color: Colors.black,
                    width: 3,
                  ),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  slot(_side[0]),
                  slot(_side[1]),

                  // Space for RUN button
                  const SizedBox(width: 96),

                  slot(_side[2]),
                  slot(_side[3]),
                ],
              ),
            ),
          ),

          // Center RUN button
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Center(
              child: KeyedSubtree(
                key: TutorialKeys.runButton,
                child: PressBlock(
                color: Rb.blue,
                edge: Rb.blueEdge,
                depth: 9,
                radius: 18,
                padding: EdgeInsets.zero,
                onTap: () => onTap(2),
                child: SizedBox(
                  width: 84,
                  height: 76,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        '🏃',
                        style: TextStyle(fontSize: 28),
                      ),
                      const SizedBox(height: 2),
                      BlockText(
                        'RUN',
                        size: 14,
                        stroke: 4,
                        color: currentIndex == 2
                            ? Rb.gold
                            : Colors.white,
                      ),
                    ],
                  ),
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