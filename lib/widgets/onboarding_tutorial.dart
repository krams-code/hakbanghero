import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'block_ui.dart';
import 'tutorial_keys.dart';

/// Tutorial guide poses: coach_1 (thumbs up), coach_2 (open hand), coach_3 (clipboard).
const kCoachDir = 'assets/images/guide';

class _TutorialStep {
  final GlobalKey target;
  final String title;
  final String text;
  final String pose; // file in assets/images/guide/
  final double radius;
  const _TutorialStep(this.target, this.title, this.text, this.pose,
      {this.radius = 22});
}

final List<_TutorialStep> _steps = [
  _TutorialStep(
    TutorialKeys.hero,
    'YOUR HERO',
    'Welcome to your Fitness Dungeon! This is your Hero. As you move in '
        'real life, your hero levels up and changes form!',
    'coach_1.png',
  ),
  _TutorialStep(
    TutorialKeys.milestone,
    'MILESTONE PATH',
    'This is your Milestone Path. Every kilometer you run or walk unlocks '
        'legendary clothes and hair styles directly in the shop!',
    'coach_2.png',
    radius: 18,
  ),
  _TutorialStep(
    TutorialKeys.runButton,
    'START TRAINING',
    'Ready to train? Tap this central block anytime to pick your pace and '
        'enter your first fitness stage battle!',
    'coach_3.png',
    radius: 24,
  ),
];

/// Step-by-step spotlight tutorial with a pixel-art Fitness Coach.
///
///   OnboardingTutorial.show(context, onFinished: () { ...mark done... });
///
/// It is inserted into the ROOT overlay, so it covers the whole screen
/// including the bottom navigation bar (needed to spotlight the RUN button).
class OnboardingTutorial {
  static OverlayEntry? _entry;

  static void show(BuildContext context, {required VoidCallback onFinished}) {
    if (_entry != null) return;
    final overlay = Overlay.of(context, rootOverlay: true);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _TutorialOverlay(
        onClose: () {
          entry.remove();
          _entry = null;
          onFinished();
        },
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }
}

class _TutorialOverlay extends StatefulWidget {
  final VoidCallback onClose;
  const _TutorialOverlay({required this.onClose});

  @override
  State<_TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<_TutorialOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _move; // hole slides between targets
  late final AnimationController _pulse; // border glow + coach bob

  int _step = 0;
  Rect _from = Rect.zero;
  Rect _to = Rect.zero;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _move = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 380));
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus(0));
  }

  @override
  void dispose() {
    _move.dispose();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _focus(int i) async {
    final ctx = _steps[i].target.currentContext;
    if (ctx != null) {
      try {
        await Scrollable.ensureVisible(ctx,
            alignment: 0.35, duration: const Duration(milliseconds: 250));
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
    if (!mounted) return;

    final box = _steps[i].target.currentContext?.findRenderObject();
    Rect next;
    if (box is RenderBox && box.attached && box.hasSize) {
      final tl = box.localToGlobal(Offset.zero);
      next = (tl & box.size).inflate(8);
    } else {
      final s = MediaQuery.of(context).size;
      next = Rect.fromCenter(
          center: Offset(s.width / 2, s.height / 2), width: 200, height: 200);
    }

    setState(() {
      _from = _ready ? (Rect.lerp(_from, _to, _move.value) ?? next) : next;
      _to = next;
      _step = i;
      _ready = true;
    });
    _move.forward(from: 0);
  }

  void _next() {
    if (_step >= _steps.length - 1) {
      widget.onClose();
    } else {
      _focus(_step + 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final step = _steps[_step];
    final last = _step == _steps.length - 1;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // darkening mask with a spotlight hole (absorbs all taps)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: AnimatedBuilder(
                animation: Listenable.merge([_move, _pulse]),
                builder: (_, __) {
                  final t = Curves.easeOutCubic.transform(_move.value);
                  final rect = _ready
                      ? (Rect.lerp(_from, _to, t) ?? _to)
                      : Rect.zero;
                  return CustomPaint(
                    painter: SpotlightPainter(
                      rect: rect,
                      radius: step.radius,
                      glow: _pulse.value,
                      show: _ready,
                    ),
                  );
                },
              ),
            ),
          ),

          // skip (top-right)
          Positioned(
            top: mq.padding.top + 10,
            right: 14,
            child: PressBlock(
              color: const Color(0xFF6B7078),
              edge: const Color(0xFF1B1D20),
              depth: 3,
              radius: 10,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              onTap: widget.onClose,
              child: const BlockText('SKIP', size: 11, stroke: 3),
            ),
          ),

          // coach + speech box. Goes to the TOP when the spotlight is low
          // on the screen (step 3), otherwise sits at the bottom.
          if (_ready) _coachBox(context, step, last),
        ],
      ),
    );
  }

  Widget _coachBox(BuildContext context, _TutorialStep step, bool last) {
    final mq = MediaQuery.of(context);
    final holeLow = _to.center.dy > mq.size.height * 0.6;

    final box = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // floating coach
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, child) => Transform.translate(
              offset: Offset(0, -6 * math.sin(_pulse.value * 2 * math.pi)),
              child: child,
            ),
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
                        for (var i = 0; i < _steps.length; i++)
                          Container(
                            width: 12,
                            height: 12,
                            margin: const EdgeInsets.only(left: 4),
                            decoration: BoxDecoration(
                              color: i == _step
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
                    // typewriter text
                    TweenAnimationBuilder<int>(
                      key: ValueKey(_step),
                      tween: IntTween(begin: 0, end: step.text.length),
                      duration:
                          Duration(milliseconds: step.text.length * 16),
                      builder: (_, n, __) => Stack(
                        children: [
                          // invisible full text reserves the final height
                          Opacity(
                            opacity: 0,
                            child: Text(step.text, style: _bodyStyle),
                          ),
                          Text(step.text.substring(0, n), style: _bodyStyle),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: PressBlock(
                        color: Rb.neon,
                        edge: Rb.greenEdge,
                        depth: 5,
                        radius: 10,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 9),
                        onTap: _next,
                        child: BlockText(
                            last ? '[ LET\'S GO! ]' : '[ NEXT ]',
                            size: 13,
                            stroke: 3.5),
                      ),
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
      top: holeLow ? mq.padding.top + 56 : null,
      bottom: holeLow ? null : mq.padding.bottom + 12,
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

class SpotlightPainter extends CustomPainter {
  final Rect rect;
  final double radius;
  final double glow;
  final bool show;

  /// How dark the dimmed screen is (0..1).
  final double dim;

  SpotlightPainter({
    required this.rect,
    required this.radius,
    required this.glow,
    required this.show,
    this.dim = 0.82,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    final dimPaint = Paint()..color = Colors.black.withOpacity(dim);

    if (!show) {
      canvas.drawRect(full, dimPaint);
      return;
    }

    final hole = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final path = Path.combine(
      PathOperation.difference,
      Path()..addRect(full),
      Path()..addRRect(hole),
    );
    canvas.drawPath(path, dimPaint);

    // chunky border: black outline + pulsing gold ring
    canvas.drawRRect(
      hole.inflate(2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..color = Colors.black,
    );
    final k = 0.5 + 0.5 * math.sin(glow * 2 * math.pi);
    canvas.drawRRect(
      hole,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 + 2 * k
        ..color = Color.lerp(const Color(0xFFFFB800), Colors.white, k * 0.6)!,
    );
  }

  @override
  bool shouldRepaint(covariant SpotlightPainter old) => true;
}
