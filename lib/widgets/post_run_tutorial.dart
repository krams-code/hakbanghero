import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'block_ui.dart';
import 'onboarding_tutorial.dart' show SpotlightPainter, kCoachDir;
import 'tutorial_keys.dart';

/// What the host app must provide for the Phase 2 walkthrough.
class PostRunTutorialHooks {
  /// Dismiss the Session Summary and go back to the pre-run screen (this
  /// also brings the bottom nav bar back).
  final Future<void> Function() closeSummary;

  /// Switch the bottom-nav tab (0 SHOP, 3 RANKS, 4 ACTIVITY).
  final ValueChanged<int> navigateTo;

  /// The player closed the tutorial: persist hasCompletedFirstRunTutorial.
  final VoidCallback onFinished;

  const PostRunTutorialHooks({
    required this.closeSummary,
    required this.navigateTo,
    required this.onFinished,
  });
}

enum _Kind {
  /// Guide text + button.
  info,

  /// The player must tap the spotlighted nav block (everything else is locked).
  tap,
}

class _Step {
  final int number; // 4..7 (Phase 1 had steps 1..3)
  final _Kind kind;
  final GlobalKey? target;
  final int tab; // tab opened by a `tap` step
  final String title;
  final String text;
  final String pose;
  final String button;
  final bool closeSummaryOnNext;
  final double radius;

  const _Step({
    required this.number,
    required this.kind,
    required this.title,
    required this.text,
    required this.pose,
    this.target,
    this.tab = 2,
    this.button = '[ NEXT ]',
    this.closeSummaryOnNext = false,
    this.radius = 16,
  });
}

final List<_Step> _steps = [
  // ── Step 4: Earning Rewards ──
  _Step(
    number: 4,
    kind: _Kind.info,
    target: TutorialKeys.rewards,
    title: 'EARNING REWARDS',
    text: 'Congratulations on completing your first stage battle, Hero! '
        'Look at that! Your physical effort earned you raw EXP and Mana '
        'Crystals. Let\'s see where that goes!',
    pose: 'coach_1.png',
    closeSummaryOnNext: true,
    radius: 16,
  ),

  // ── Step 5: Activity ──
  _Step(
    number: 5,
    kind: _Kind.tap,
    target: TutorialKeys.navActivity,
    tab: 4,
    title: 'ACTIVITY BLOCK',
    text: 'Tap on the Activity Block so I can show you how to track your '
        'long-term fitness evolution metrics!',
    pose: 'coach_3.png',
    radius: 14,
  ),
  _Step(
    number: 5,
    kind: _Kind.info,
    title: 'YOUR STATS',
    text: 'Excellent! This block tracks your weekly calories, heart health, '
        'and running speed statistics!',
    pose: 'coach_2.png',
  ),

  // ── Step 6: Ranks ──
  _Step(
    number: 6,
    kind: _Kind.tap,
    target: TutorialKeys.navRanks,
    tab: 3,
    title: 'RANKS BLOCK',
    text: 'Now, click on the Ranks block. Let\'s see where you stand against '
        'other running champions in the kingdom!',
    pose: 'coach_3.png',
    radius: 14,
  ),
  _Step(
    number: 6,
    kind: _Kind.info,
    title: 'GLOBAL SCOREBOARD',
    text: 'This is the Global Scoreboard! Your custom character row scales '
        'down and stands proudly right next to your username so everyone '
        'can see your current fitness form!',
    pose: 'coach_2.png',
  ),

  // ── Step 7: Shop ──
  _Step(
    number: 7,
    kind: _Kind.tap,
    target: TutorialKeys.navShop,
    tab: 0,
    title: 'SHOP BLOCK',
    text: 'Finally, let\'s head over to the Shop block. This is where the '
        'magic happens!',
    pose: 'coach_2.png',
    radius: 14,
  ),
  _Step(
    number: 7,
    kind: _Kind.info,
    title: 'THE SHOP',
    text: 'Use the crystals you earn from running to buy fresh hairstyles, '
        'expressions, and clothing sets! Remember, elite legendary gear '
        'requires you to break real-life kilometer milestones before you '
        'can buy them! Good luck on your journey, Hero!',
    pose: 'coach_1.png',
    button: '[ CLOSE TUTORIAL ]',
  ),
];

/// Phase 2 of the onboarding tutorial: the post-run walkthrough.
///
///   PostRunTutorial.show(context, hooks: ...);
///
/// Inserted into the ROOT overlay, so it covers the summary sheet, the
/// screens and the bottom nav bar. It absorbs every tap; during a `tap` step
/// only the spotlighted nav block responds. There is deliberately no SKIP.
class PostRunTutorial {
  PostRunTutorial._();
  static OverlayEntry? _entry;

  static bool get isActive => _entry != null;

  static void show(BuildContext context, {required PostRunTutorialHooks hooks}) {
    if (_entry != null) return;
    final overlay = Overlay.of(context, rootOverlay: true);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _PostRunOverlay(
        hooks: hooks,
        onClose: () {
          entry.remove();
          _entry = null;
          hooks.onFinished();
        },
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }
}

class _PostRunOverlay extends StatefulWidget {
  final PostRunTutorialHooks hooks;
  final VoidCallback onClose;
  const _PostRunOverlay({required this.hooks, required this.onClose});

  @override
  State<_PostRunOverlay> createState() => _PostRunOverlayState();
}

class _PostRunOverlayState extends State<_PostRunOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400))
    ..repeat();

  int _i = 0;
  bool _busy = false;
  bool _stuck = false; // safety: spotlight target never appeared
  Timer? _stuckTimer;
  Rect? _cur; // the spotlight hole (eased toward its live target)

  _Step get _step => _steps[_i];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _enter());
  }

  @override
  void dispose() {
    _stuckTimer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  /// Called whenever a step becomes current.
  Future<void> _enter() async {
    _stuck = false;
    _stuckTimer?.cancel();
    if (_step.kind == _Kind.tap) {
      // the nav bar may still be sliding open; only worry if it never shows up
      _stuckTimer = Timer(const Duration(seconds: 6), () {
        if (mounted && _cur == null) setState(() => _stuck = true);
      });
    }
    final ctx = _step.target?.currentContext;
    if (ctx != null && _step.kind == _Kind.info) {
      try {
        await Scrollable.ensureVisible(ctx,
            alignment: 0.4, duration: const Duration(milliseconds: 250));
      } catch (_) {}
    }
  }

  void _goNext() {
    if (!mounted) return;
    setState(() => _i++);
    _enter();
  }

  Future<void> _onNext() async {
    if (_busy) return;
    _busy = true;
    try {
      if (_step.closeSummaryOnNext) await widget.hooks.closeSummary();
      if (_i >= _steps.length - 1) {
        widget.onClose();
      } else {
        _goNext();
      }
    } finally {
      _busy = false;
    }
  }

  void _openTab() {
    widget.hooks.navigateTo(_step.tab);
    _goNext();
  }

  void _onMaskTap(TapUpDetails d) {
    if (_step.kind != _Kind.tap) return; // everything is locked
    final hole = _cur;
    if (hole != null && hole.contains(d.globalPosition)) _openTab();
  }

  /// Live rectangle of the current target, eased so it glides between steps
  /// and follows the nav bar while it slides open.
  Rect? _holeRect() {
    final box = _step.target?.currentContext?.findRenderObject();
    Rect? live;
    if (box is RenderBox && box.attached && box.hasSize) {
      live = (box.localToGlobal(Offset.zero) & box.size).inflate(8);
    }
    if (live == null) {
      _cur = null;
    } else {
      _cur = _cur == null ? live : (Rect.lerp(_cur, live, 0.25) ?? live);
    }
    return _cur;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) {
          final step = _step;
          final hole = _holeRect();
          return Stack(
            children: [
              // dimmed screen (absorbs every tap; only the hole of a `tap`
              // step reacts)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: _onMaskTap,
                  child: CustomPaint(
                    painter: SpotlightPainter(
                      rect: hole ?? Rect.zero,
                      radius: step.radius,
                      glow: _pulse.value,
                      show: hole != null,
                      dim: hole != null ? 0.82 : 0.6,
                    ),
                  ),
                ),
              ),
              _coachBox(context, step, hole),
            ],
          );
        },
      ),
    );
  }

  Widget _coachBox(BuildContext context, _Step step, Rect? hole) {
    final mq = MediaQuery.of(context);
    // Keep the guide clear of the spotlight: top when the hole is low (the
    // nav bar) or when we are waiting for it, bottom otherwise.
    final onTop = hole != null
        ? hole.center.dy > mq.size.height * 0.45
        : step.kind == _Kind.tap;

    final box = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Transform.translate(
            offset: Offset(0, -6 * math.sin(_pulse.value * 2 * math.pi)),
            child: Image.asset(
              '$kCoachDir/${step.pose}',
              height: 150,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, __, ___) => const SizedBox(
                height: 150,
                width: 90,
                child: Center(
                    child: Text('🧑‍🏫', style: TextStyle(fontSize: 64))),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Block(
                color: const Color(0xFFF2F3F5),
                edge: Colors.black,
                depth: 6,
                radius: 14,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Block(
                          color: Rb.gold,
                          edge: Rb.goldEdge,
                          depth: 3,
                          radius: 8,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          child: const BlockText('COACH HAKBANG',
                              size: 9, stroke: 2.5),
                        ),
                        const Spacer(),
                        for (var n = 4; n <= 7; n++)
                          Container(
                            width: 12,
                            height: 12,
                            margin: const EdgeInsets.only(left: 4),
                            decoration: BoxDecoration(
                              color: n <= step.number
                                  ? Rb.green
                                  : const Color(0xFFB9BDC2),
                              border:
                                  Border.all(color: Colors.black, width: 2),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    BlockText(step.title,
                        size: 14, stroke: 3.5, color: Rb.blue),
                    const SizedBox(height: 4),
                    TweenAnimationBuilder<int>(
                      key: ValueKey(_i),
                      tween: IntTween(begin: 0, end: step.text.length),
                      duration: Duration(milliseconds: step.text.length * 16),
                      builder: (_, n, __) => Stack(
                        children: [
                          Opacity(
                            opacity: 0,
                            child: Text(step.text, style: _bodyStyle),
                          ),
                          Text(step.text.substring(0, n), style: _bodyStyle),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (step.kind == _Kind.info)
                      Align(
                        alignment: Alignment.centerRight,
                        child: PressBlock(
                          color: Rb.neon,
                          edge: Rb.greenEdge,
                          depth: 5,
                          radius: 10,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 9),
                          onTap: _onNext,
                          child: BlockText(step.button, size: 13, stroke: 3.5),
                        ),
                      )
                    else if (_stuck)
                      // safety net: the nav block never appeared
                      Align(
                        alignment: Alignment.centerRight,
                        child: PressBlock(
                          color: Rb.neon,
                          edge: Rb.greenEdge,
                          depth: 5,
                          radius: 10,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 9),
                          onTap: _openTab,
                          child:
                              const BlockText('[ CONTINUE ]', size: 13, stroke: 3.5),
                        ),
                      )
                    else
                      const Align(
                        alignment: Alignment.centerRight,
                        child: BlockText('👆 TAP THE GLOWING BLOCK',
                            size: 11, stroke: 3, color: Rb.gold),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return Positioned(
      left: 0,
      right: 0,
      top: onTop ? mq.padding.top + 56 : null,
      bottom: onTop ? null : mq.padding.bottom + 12,
      child: box,
    );
  }

  static const _bodyStyle = TextStyle(
    color: Color(0xFF1B1D20),
    fontSize: 13,
    height: 1.35,
    fontWeight: FontWeight.w800,
  );
}
