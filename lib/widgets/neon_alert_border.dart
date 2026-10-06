import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Thick pulsing neon-red border with crackling electric arcs.
///
/// Drop it in a Stack above the content it should frame. It ignores touches
/// and paints nothing while [active] is false.
class NeonAlertBorder extends StatefulWidget {
  final bool active;
  final double inset;
  final double radius;

  const NeonAlertBorder({
    super.key,
    required this.active,
    this.inset = 4,
    this.radius = 22,
  });

  @override
  State<NeonAlertBorder> createState() => _NeonAlertBorderState();
}

class _NeonAlertBorderState extends State<NeonAlertBorder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(covariant NeonAlertBorder old) {
    super.didUpdateWidget(old);
    if (widget.active && !_ctrl.isAnimating) {
      _ctrl.repeat();
    } else if (!widget.active && _ctrl.isAnimating) {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _NeonBorderPainter(_ctrl, widget.inset, widget.radius),
        ),
      ),
    );
  }
}

class _NeonBorderPainter extends CustomPainter {
  final Animation<double> t;
  final double inset;
  final double radius;

  _NeonBorderPainter(this.t, this.inset, this.radius) : super(repaint: t);

  static const Color _red = Color(0xFFFF2B4A);
  static const Color _hot = Color(0xFFFFB3BE);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(inset + 4);
    final rr = RRect.fromRectAndRadius(rect, Radius.circular(radius));

    // 2 pulses per second
    final pulse = 0.5 + 0.5 * math.sin(t.value * 2 * math.pi * 2);

    // 1) wide soft glow
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 20
        ..color = _red.withValues(alpha: 0.35 + 0.35 * pulse)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );

    // 2) thick neon line
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..color = Color.lerp(const Color(0xFFD9142F), _red, pulse)!,
    );

    // 3) hot core
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = _hot.withValues(alpha: 0.7 + 0.3 * pulse),
    );

    // 4) electric arcs: a jagged line that re-rolls 12x per second
    final frame = (t.value * 12).floor();
    _arc(canvas, rect, math.Random(frame * 7919 + 1), 7);
    _arc(canvas, rect, math.Random(frame * 104729 + 3), 5);
  }

  void _arc(Canvas canvas, Rect r, math.Random rnd, double jitter) {
    final perimeter = 2 * (r.width + r.height);
    const steps = 48;
    final start = rnd.nextDouble() * perimeter;
    final len = perimeter * (0.25 + rnd.nextDouble() * 0.25);

    final path = Path();
    for (var i = 0; i <= steps; i++) {
      final s = (start + len * i / steps) % perimeter;
      final p = _at(r, s) +
          Offset((rnd.nextDouble() - 0.5) * 2 * jitter,
              (rnd.nextDouble() - 0.5) * 2 * jitter);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeJoin = StrokeJoin.bevel
        ..color = _red.withValues(alpha: 0.8)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.bevel
        ..color = Colors.white,
    );
  }

  /// Point at distance [s] along the rectangle outline (clockwise).
  Offset _at(Rect r, double s) {
    final w = r.width, h = r.height;
    if (s < w) return Offset(r.left + s, r.top);
    s -= w;
    if (s < h) return Offset(r.right, r.top + s);
    s -= h;
    if (s < w) return Offset(r.right - s, r.bottom);
    s -= w;
    return Offset(r.left, r.bottom - s);
  }

  @override
  bool shouldRepaint(covariant _NeonBorderPainter old) =>
      old.t != t || old.inset != inset || old.radius != radius;
}
