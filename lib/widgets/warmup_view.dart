import 'package:flutter/material.dart';

import '../constants/app_icons.dart';
import '../models/activity_model.dart' show ActivityType;
import '../models/warmup_exercise.dart';
import 'block_ui.dart';
import 'demo_window.dart';
import 'pixel_icon.dart';
import 'warmup_stage.dart';

const _yellow = Color(0xFFFFD21F);
const _yellowEdge = Color(0xFF8A6D00);
const _slate = Color(0xFF2F3640);
const _slateLight = Color(0xFF454B54);

/// Pre-Run Preparation: an animated mini-game phase.
///
///  * idle      – the randomized TRAINING QUEST list (with demo windows)
///  * running   – a scenic viewport (sky / clouds / trees / road scrolling
///                to the RIGHT) with the player's avatar, a picture-in-picture
///                demo of the current exercise, and an automatic step timer
///
/// When STEP n/n reaches 0, [onComplete] fires — the run screen then moves on
/// to the Active Tracking stage. [onSkip] fires when the player skips.
class WarmUpView extends StatefulWidget {
  final VoidCallback onComplete;
  final VoidCallback onSkip;

  /// What the player is prepping for; decides which exercises can appear.
  final ActivityType activityType;

  /// Seconds each exercise stays on screen (configurable, default 30).
  final int stepSeconds;

  /// How many exercises make up one warm-up (the 1-2-3-4 slots).
  final int stepCount;

  const WarmUpView({
    super.key,
    required this.onComplete,
    required this.onSkip,
    this.activityType = ActivityType.run,
    this.stepSeconds = 30,
    this.stepCount = 4,
  });

  @override
  State<WarmUpView> createState() => _WarmUpViewState();
}

class _WarmUpViewState extends State<WarmUpView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _stepCtrl; // 0 → 1 over one step
  late List<WarmUpEntry> _queue; // randomized exercises for THIS visit
  bool _started = false;
  bool _done = false;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _randomizeRoutine();
    _stepCtrl = AnimationController(
      vsync: this,
      duration: Duration(seconds: widget.stepSeconds),
    )..addStatusListener(_onStepStatus);
  }

  /// Shuffle the exercise database and fill the training slots. Runs every
  /// time the screen is entered, so each session launch is different.
  void _randomizeRoutine() {
    _queue = pickWarmUpRoutine(widget.activityType, count: widget.stepCount);
  }

  @override
  void dispose() {
    _stepCtrl.removeStatusListener(_onStepStatus);
    _stepCtrl.dispose();
    super.dispose();
  }

  // ── sequence engine ───────────────────────────────────────────────────

  void _startRoutine() {
    if (_queue.isEmpty) {
      _finish();
      return;
    }
    setState(() {
      _started = true;
      _index = 0;
    });
    _stepCtrl.forward(from: 0);
  }

  void _onStepStatus(AnimationStatus st) {
    if (st != AnimationStatus.completed || !mounted || _done) return;
    if (_index < _queue.length - 1) {
      setState(() => _index++); // slides the text out/in, bar resets below
      _stepCtrl.forward(from: 0);
    } else {
      _finish();
    }
  }

  void _finish() {
    if (_done) return;
    _done = true;
    _stepCtrl.stop();
    widget.onComplete(); // → Active Tracking stage
  }

  void _skip() {
    if (_done) return;
    _done = true;
    _stepCtrl.stop();
    widget.onSkip();
  }

  int get _secondsLeft =>
      (widget.stepSeconds * (1 - _stepCtrl.value))
          .ceil()
          .clamp(0, widget.stepSeconds)
          .toInt();

  // ── build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Rb.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
          child: Column(
            children: [
              _SlateBlock(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: Column(
                  children: [
                    const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: IconLabel(
                        iconPath: AppIcons.gearShield,
                        iconSize: 28,
                        label: BlockText('PRE-RUN PREPARATION',
                            size: 20, stroke: 4.5),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _started
                          ? 'Prepare your body before starting your adventure.'
                          : 'A short warm-up is recommended before every run.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFD7DADD),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              if (_started) _active() else _preview(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Idle: randomized quest list + big buttons ─────────────────────────
  Widget _preview() {
    final total = _queue.length * widget.stepSeconds;
    return Column(
      children: [
        Block(
          color: Rb.panel,
          edge: Rb.panelEdge,
          depth: 6,
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: BlockText('TRAINING QUEST', size: 14, stroke: 3.5),
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < _queue.length; i++)
                Padding(
                  padding:
                      EdgeInsets.only(bottom: i == _queue.length - 1 ? 0 : 10),
                  child: _stepRow(i + 1, _queue[i]),
                ),
              const SizedBox(height: 12),
              BlockText('ABOUT $total SECONDS',
                  size: 11, stroke: 3, color: const Color(0xFFB8BDC4)),
            ],
          ),
        ),
        const SizedBox(height: 20),
        PressBlock(
          color: _yellow,
          edge: _yellowEdge,
          depth: 10,
          radius: 18,
          padding: const EdgeInsets.symmetric(vertical: 20),
          onTap: _startRoutine,
          child: const SizedBox(
            width: double.infinity,
            child: Center(
              child: IconLabel(
                iconPath: AppIcons.runFire,
                iconSize: 30,
                gap: 8,
                label: BlockText('START WARM-UP', size: 22, stroke: 5),
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        _SlateButton(label: 'SKIP', onTap: _skip),
        const SizedBox(height: 10),
        const Text(
          'You can skip the warm-up. There is no XP penalty for skipping.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFFB8BDC4),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _stepRow(int n, WarmUpEntry e) {
    return Block(
      color: Rb.slot,
      edge: Rb.panelEdge,
      depth: 4,
      radius: 12,
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _yellow,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.black, width: 3),
            ),
            child: BlockText('$n', size: 20, stroke: 4, color: Colors.black),
          ),
          const SizedBox(width: 12),
          PixelIcon(e.exercise.iconPath, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: BlockText(e.exercise.name.toUpperCase(),
                  size: 15, stroke: 3.5),
            ),
          ),
          const SizedBox(width: 8),
          DemoWindow(path: e.exercise.demoPath, size: 64),
        ],
      ),
    );
  }

  // ── Running: the animated mini-game phase ─────────────────────────────
  Widget _active() {
    final entry = _queue[_index];

    return Column(
      children: [
        // STEP n/n  +  seconds score tile
        AnimatedBuilder(
          animation: _stepCtrl,
          builder: (_, __) => Row(
            children: [
              Expanded(
                child: _Chunk(
                  color: Rb.blue,
                  radius: 16,
                  depth: 7,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    alignment: Alignment.center,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: BlockText('STEP ${_index + 1}/${_queue.length}',
                          size: 30, stroke: 6),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _Chunk(
                color: _yellow,
                radius: 16,
                depth: 7,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 104),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  alignment: Alignment.center,
                  child: BlockText('${_secondsLeft}s',
                      size: 32, stroke: 7, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // chunky loading track
        AnimatedBuilder(
          animation: _stepCtrl,
          builder: (_, __) => _ChunkyTrack(value: _stepCtrl.value),
        ),
        const SizedBox(height: 18),

        // animated viewport (scenic stage + avatar + demo PiP)
        LayoutBuilder(builder: (context, c) {
          final side = c.maxWidth.clamp(0.0, 420.0).toDouble();
          return SizedBox(
            width: side,
            height: side * 0.92,
            child: Stack(
              children: [
                Positioned.fill(
                  child: WarmUpStage(demoPath: entry.exercise.demoPath),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 14),

        // exercise name + instruction, sliding in/out per step
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 380),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, anim) {
            final incoming = child.key == ValueKey<int>(_index);
            final tween = Tween<Offset>(
              begin: incoming ? const Offset(1.0, 0) : const Offset(-1.0, 0),
              end: Offset.zero,
            );
            return ClipRect(
              child: SlideTransition(
                position: tween.animate(anim),
                child: FadeTransition(opacity: anim, child: child),
              ),
            );
          },
          child: KeyedSubtree(
            key: ValueKey<int>(_index),
            child: _exerciseText(entry),
          ),
        ),
        const SizedBox(height: 22),
        _SlateButton(label: 'SKIP WARM-UP', onTap: _skip),
      ],
    );
  }

  Widget _exerciseText(WarmUpEntry e) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: BlockText(e.exercise.name.toUpperCase(),
                size: 28, stroke: 6, align: TextAlign.center),
          ),
        ),
        const SizedBox(height: 10),
        _SlateBlock(
          color: _slateLight,
          depth: 5,
          radius: 12,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: SizedBox(
            width: double.infinity,
            child: Text(
              e.description,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13.5,
                height: 1.35,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ───────────────────────── building blocks ─────────────────────────

/// A chunky colour block: 3px solid black border + hard bottom drop shadow.
class _Chunk extends StatelessWidget {
  final Color color;
  final double radius;
  final double depth;
  final Widget child;
  const _Chunk({
    required this.color,
    required this.child,
    this.radius = 14,
    this.depth = 6,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: depth),
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: Colors.black, width: 3),
          boxShadow: [
            BoxShadow(
              color: Colors.black,
              offset: Offset(0, depth),
              blurRadius: 0,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius - 3),
          child: Stack(
            children: [
              Positioned.fill(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: FractionallySizedBox(
                    heightFactor: 0.28,
                    widthFactor: 1,
                    child: ColoredBox(color: Colors.white.withValues(alpha: 0.18)),
                  ),
                ),
              ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// Dark slate card (header / description): 3px black border, hard shadow.
class _SlateBlock extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color color;
  final double depth;
  final double radius;
  const _SlateBlock({
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.color = _slate,
    this.depth = 6,
    this.radius = 16,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: depth),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: Colors.black, width: 3),
          boxShadow: [
            BoxShadow(
              color: Colors.black,
              offset: Offset(0, depth),
              blurRadius: 0,
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

/// Dark slate press button (SKIP / SKIP WARM-UP): sinks when pressed.
class _SlateButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _SlateButton({required this.label, required this.onTap});

  @override
  State<_SlateButton> createState() => _SlateButtonState();
}

class _SlateButtonState extends State<_SlateButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    const depth = 6.0;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: depth),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 70),
          transform: Matrix4.translationValues(0, _down ? depth - 1 : 0, 0),
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(
            color: _slate,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.black, width: 3),
            boxShadow: [
              BoxShadow(
                color: Colors.black,
                offset: Offset(0, _down ? 1 : depth),
                blurRadius: 0,
              ),
            ],
          ),
          child: Center(
            child: BlockText(widget.label,
                size: 16, stroke: 4, color: const Color(0xFFD7DADD)),
          ),
        ),
      ),
    );
  }
}

/// Thick segmented loading track inside a heavy black frame.
class _ChunkyTrack extends StatelessWidget {
  final double value; // 0..1
  const _ChunkyTrack({required this.value});

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(0.0, 1.0).toDouble();
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(color: Colors.black, offset: Offset(0, 5), blurRadius: 0),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 34,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Color(0xFF3A3D40)),
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: v,
                child: const ColoredBox(color: Rb.neon),
              ),
              Align(
                alignment: Alignment.topCenter,
                child: FractionallySizedBox(
                  heightFactor: 0.3,
                  widthFactor: 1,
                  child: ColoredBox(color: Colors.white.withValues(alpha: 0.22)),
                ),
              ),
              // chunk dividers (10 segments)
              CustomPaint(painter: _SegmentPainter()),
            ],
          ),
        ),
      ),
    );
  }
}

class _SegmentPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.black.withValues(alpha: 0.55)
      ..strokeWidth = 3;
    for (var i = 1; i < 10; i++) {
      final x = size.width * i / 10;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
