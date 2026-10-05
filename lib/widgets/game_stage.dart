import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'block_ui.dart';
import 'session_avatar.dart';

/// Rounded-square game viewport for the live tracker.
///
/// Light-blue sky, with three loop-scrolling parallax layers (clouds, far
/// hills, blocky trees) plus a road. Layers scroll *backwards* while
/// [moving] is true, faster the higher [speedKmh] is, and ease to a stop
/// when you stop. The avatar switches to its running stance at the same time.
class GameStage extends StatefulWidget {
  final bool moving;
  final double speedKmh;
  final bool paused;

  const GameStage({
    super.key,
    required this.moving,
    required this.speedKmh,
    this.paused = false,
  });

  @override
  State<GameStage> createState() => _GameStageState();
}

class _GameStageState extends State<GameStage>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<double> _scroll = ValueNotifier(0);
  Duration _last = Duration.zero;
  double _speed = 0; // eased px/sec for the nearest layer

  double get _target {
    if (widget.paused || !widget.moving) return 0;
    // 3 km/h -> ~90 px/s, 12 km/h -> ~280 px/s
    return (60 + widget.speedKmh * 18).clamp(80.0, 340.0).toDouble();
  }

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      final dt = (elapsed - _last).inMicroseconds / 1e6;
      _last = elapsed;
      if (dt <= 0 || dt > 0.25) return;
      _speed += (_target - _speed) * math.min(1.0, dt * 4);
      if (_speed < 0.5 && _target == 0) _speed = 0;
      if (_speed > 0) _scroll.value += _speed * dt;
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final running = widget.moving && !widget.paused;
    final cadence = (0.7 + widget.speedKmh / 10).clamp(0.7, 1.8).toDouble();

    return Block(
      color: const Color(0xFF8FD3FF),
      edge: Rb.blueEdge,
      radius: 20,
      depth: 8,
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(17),
        child: LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth, h = c.maxHeight;
            final groundH = h * 0.22;
            final avatarH = math.min(h * 0.78, 300.0);

            return Stack(
              children: [
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _SceneBackPainter(_scroll, groundH),
                    ),
                  ),
                ),
                // shadow under the feet
                Positioned(
                  bottom: groundH * 0.30,
                  left: w / 2 - 38,
                  child: Container(
                    width: 76,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.28),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
                Positioned(
                  bottom: groundH * 0.30,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: SessionAvatar(
                      height: avatarH,
                      stance:
                          running ? AvatarStance.running : AvatarStance.idle,
                      cadence: cadence,
                    ),
                  ),
                ),
                if (widget.paused)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withOpacity(0.35),
                      alignment: Alignment.center,
                      child: const BlockText('⏸ PAUSED', size: 26, stroke: 6),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SceneBackPainter extends CustomPainter {
  final ValueNotifier<double> scroll;
  final double groundH;
  _SceneBackPainter(this.scroll, this.groundH) : super(repaint: scroll);

  final Paint _p = Paint()..isAntiAlias = false;

  // Draw `tile`-wide repeating content scrolling LEFT (world moves backward).
  void _loop(Canvas canvas, Size size, double offset, double tile,
      void Function(double x) draw) {
    final start = -(offset % tile);
    for (double x = start; x < size.width + tile; x += tile) {
      draw(x);
    }
  }

  void _rect(Canvas c, Rect r, Color color, {bool outline = false}) {
    c.drawRect(r, _p..color = color);
    if (outline) {
      c.drawRect(
        r,
        Paint()
          ..isAntiAlias = false
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = Colors.black,
      );
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = scroll.value;
    final groundTop = size.height - groundH;

    // sky
    _rect(canvas, Offset.zero & size, const Color(0xFF8FD3FF));
    _rect(canvas, Rect.fromLTWH(0, 0, size.width, size.height * 0.35),
        const Color(0xFF6CC3FF));

    // sun
    _rect(canvas, Rect.fromLTWH(size.width - 70, 22, 38, 38),
        const Color(0xFFFFE066),
        outline: true);

    // clouds (slowest)
    _loop(canvas, size, s * 0.15, 240, (x) {
      _cloud(canvas, Offset(x + 20, 40), 1);
      _cloud(canvas, Offset(x + 150, 86), 0.7);
    });

    // far hills
    _loop(canvas, size, s * 0.35, 160, (x) {
      _rect(canvas, Rect.fromLTWH(x, groundTop - 60, 100, 60),
          const Color(0xFF5BB36A));
      _rect(canvas, Rect.fromLTWH(x + 28, groundTop - 90, 46, 30),
          const Color(0xFF5BB36A));
    });

    // trees (blocky)
    _loop(canvas, size, s * 0.7, 190, (x) {
      _tree(canvas, Offset(x + 30, groundTop), 1);
      _tree(canvas, Offset(x + 120, groundTop), 0.75);
    });

    // grass strip + road
    _rect(canvas, Rect.fromLTWH(0, groundTop, size.width, groundH),
        const Color(0xFF3FA34D));
    _rect(canvas, Rect.fromLTWH(0, groundTop, size.width, 4), Colors.black);
    final roadTop = groundTop + groundH * 0.30;
    _rect(canvas,
        Rect.fromLTWH(0, roadTop, size.width, size.height - roadTop),
        const Color(0xFF4B5058));
    _rect(canvas, Rect.fromLTWH(0, roadTop, size.width, 3), Colors.black);

    // lane dashes (fastest)
    final laneY = roadTop + (size.height - roadTop) * 0.5 - 3;
    _loop(canvas, size, s * 1.0, 64, (x) {
      _rect(canvas, Rect.fromLTWH(x, laneY, 34, 6), const Color(0xFFFFE066));
    });
  }

  void _cloud(Canvas c, Offset o, double k) {
    final col = Colors.white;
    _rect(c, Rect.fromLTWH(o.dx, o.dy + 10 * k, 70 * k, 16 * k), col);
    _rect(c, Rect.fromLTWH(o.dx + 14 * k, o.dy, 38 * k, 14 * k), col);
  }

  void _tree(Canvas c, Offset base, double k) {
    _rect(c, Rect.fromLTWH(base.dx + 12 * k, base.dy - 34 * k, 12 * k, 34 * k),
        const Color(0xFF8A5A2B),
        outline: true);
    _rect(c, Rect.fromLTWH(base.dx - 2 * k, base.dy - 78 * k, 40 * k, 34 * k),
        const Color(0xFF2E9E4F),
        outline: true);
    _rect(c, Rect.fromLTWH(base.dx + 6 * k, base.dy - 98 * k, 24 * k, 24 * k),
        const Color(0xFF39B85C),
        outline: true);
  }

  @override
  bool shouldRepaint(covariant _SceneBackPainter old) =>
      old.groundH != groundH;
}
