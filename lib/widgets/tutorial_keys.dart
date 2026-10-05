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
}
