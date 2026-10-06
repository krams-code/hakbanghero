import 'package:flutter/widgets.dart';

/// GlobalKeys the onboarding tutorial uses to find (and spotlight) real
/// widgets on screen. Each key must be attached to exactly ONE widget.
abstract final class TutorialKeys {
  /// The avatar viewport on the RUN tab.
  static final GlobalKey hero = GlobalKey(debugLabel: 'tutorial-hero');

  /// The "Milestone x / y" banner with the progress bar (top of RUN tab).
  static final GlobalKey milestone = GlobalKey(debugLabel: 'tutorial-milestone');

  /// The big blue RUN block in the bottom nav bar.
  static final GlobalKey runButton = GlobalKey(debugLabel: 'tutorial-run');

  // ── Phase 2 (post-run) ──

  /// The rewards area of the Session Summary (XP / coins / quests / loot).
  static final GlobalKey rewards = GlobalKey(debugLabel: 'tutorial-rewards');

  /// Bottom-nav side blocks.
  static final GlobalKey navShop = GlobalKey(debugLabel: 'tutorial-nav-shop');
  static final GlobalKey navRanks = GlobalKey(debugLabel: 'tutorial-nav-ranks');
  static final GlobalKey navActivity =
      GlobalKey(debugLabel: 'tutorial-nav-activity');

  /// Key for a nav slot index (0 SHOP, 3 RANKS, 4 ACTIVITY), else null.
  static GlobalKey? forNav(int index) {
    switch (index) {
      case 0:
        return navShop;
      case 3:
        return navRanks;
      case 4:
        return navActivity;
    }
    return null;
  }
}
