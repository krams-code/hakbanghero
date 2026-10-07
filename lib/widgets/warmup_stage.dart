import 'package:flutter/material.dart';

import 'demo_window.dart';

/// The warm-up viewport: a rounded-square Roblox-style frame holding a pixel
/// scenic stage (sky, clouds, hills, trees, road) that loop-scrolls from LEFT
/// TO RIGHT the whole time it is on screen, with the current exercise's demo
/// GIF ([demoPath]) in the middle.
///
/// The scroll is driven by its own repeating AnimationController (no GPS, no
/// speed input), so it can never stand still. Every layer completes a whole
/// number of tiles per loop, so the wrap-around is seamless.
class WarmUpStage extends StatefulWidget {
  final String demoPath;
  const WarmUpStage({super.key, required this.demoPath});

  @override
  State<WarmUpStage> createState() => _WarmUpStageState();
}

class _WarmUpStageState extends State<WarmUpStage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scroll;

  @override
  void initState() {
    super.initState();
    _scroll = AnimationController(vsync: this, duration: const Duration(seconds: 6))
      ..repeat();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const depth = 8.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: depth),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF8FD3FF),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.black, width: 4),
          boxShadow: const [
            BoxShadow(color: Colors.black, offset: Offset(0, depth), blurRadius: 0),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: LayoutBuilder(builder: (context, c) {
            final h = c.maxHeight;
            final w = c.maxWidth;
            final groundH = h * 0.22;
            final demoSize = (h * 0.74).clamp(0.0, w * 0.85).toDouble();
            return Stack(
              children: [
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _ScenePainter(_scroll, groundH),
                    ),
                  ),
                ),
                Positioned(
                  top: h * 0.06,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: DemoWindow(
                      key: ValueKey(widget.demoPath),
                      path: widget.demoPath,
                      size: demoSize,
                    ),
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

class _ScenePainter extends CustomPainter {
  final Animation<double> t; // 0 → 1, repeating
  final double groundH;
  _ScenePainter(this.t, this.groundH) : super(repaint: t);

  final Paint _p = Paint()..isAntiAlias = false;

  /// Content moves RIGHT. [laps] whole tiles are travelled per loop, so the
  /// last frame lines up exactly with the first one.
  void _loop(Canvas canvas, Size size, double tile, int laps,
      void Function(double x) draw) {
    final offset = t.value * tile * laps;
    for (double x = (offset % tile) - tile; x < size.width + tile; x += tile) {
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
    final groundTop = size.height - groundH;

    // sky
    _rect(canvas, Offset.zero & size, const Color(0xFF8FD3FF));
    _rect(canvas, Rect.fromLTWH(0, 0, size.width, size.height * 0.35),
        const Color(0xFF6CC3FF));
    _rect(canvas, Rect.fromLTWH(size.width - 70, 22, 38, 38),
        const Color(0xFFFFE066),
        outline: true);

    // clouds (slowest)       40 px/s
    _loop(canvas, size, 240, 1, (x) {
      _cloud(canvas, Offset(x + 20, 40), 1);
      _cloud(canvas, Offset(x + 150, 86), 0.7);
    });

    // far hills              ~53 px/s
    _loop(canvas, size, 160, 2, (x) {
      _rect(canvas, Rect.fromLTWH(x, groundTop - 60, 100, 60),
          const Color(0xFF5BB36A));
      _rect(canvas, Rect.fromLTWH(x + 28, groundTop - 90, 46, 30),
          const Color(0xFF5BB36A));
    });

    // trees                  ~95 px/s
    _loop(canvas, size, 190, 3, (x) {
      _tree(canvas, Offset(x + 30, groundTop), 1);
      _tree(canvas, Offset(x + 120, groundTop), 0.75);
    });

    // grass + road
    _rect(canvas, Rect.fromLTWH(0, groundTop, size.width, groundH),
        const Color(0xFF3FA34D));
    _rect(canvas, Rect.fromLTWH(0, groundTop, size.width, 4), Colors.black);
    final roadTop = groundTop + groundH * 0.30;
    _rect(canvas, Rect.fromLTWH(0, roadTop, size.width, size.height - roadTop),
        const Color(0xFF4B5058));
    _rect(canvas, Rect.fromLTWH(0, roadTop, size.width, 3), Colors.black);

    // lane dashes (fastest)  ~107 px/s
    final laneY = roadTop + (size.height - roadTop) * 0.5 - 3;
    _loop(canvas, size, 64, 10, (x) {
      _rect(canvas, Rect.fromLTWH(x, laneY, 34, 6), const Color(0xFFFFE066));
    });
  }

  void _cloud(Canvas c, Offset o, double k) {
    const col = Colors.white;
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
  bool shouldRepaint(covariant _ScenePainter old) => old.groundH != groundH;
}
