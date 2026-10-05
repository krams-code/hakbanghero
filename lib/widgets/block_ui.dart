import 'package:flutter/material.dart';

// ═════════════════════════════════════════════════════════════════
//  Roblox-style block UI kit
//  Solid colour • thick dark border • hard (blur-free) drop shadow
//  • extra-bold outlined labels. Used by Home, Leaderboard, Start Session.
// ═════════════════════════════════════════════════════════════════

/// Palette. Every colour has a matching dark `...Edge` for borders/shadows.
abstract final class Rb {
  static const bg        = Color(0xFF232527);
  static const panel     = Color(0xFF393B3D);
  static const panelEdge = Color(0xFF0E0F10);
  static const track     = Color(0xFF1A1B1C);

  static const slate     = Color(0xFF2F3640);
  static const slateEdge = Color(0xFF0B0D10);
  static const slot      = Color(0xFF454B54);

  static const hud       = Color(0xFFD3D5D7); // light-gray game header
  static const hudEdge   = Color(0xFF2B2D2F);

  static const green     = Color(0xFF00B06F);
  static const greenEdge = Color(0xFF006B44);
  static const neon      = Color(0xFF39FF88);

  static const gold      = Color(0xFFFFB800);
  static const goldEdge  = Color(0xFF8A5A00);

  static const blue      = Color(0xFF00A2FF);
  static const blueEdge  = Color(0xFF004F7A);

  static const orange    = Color(0xFFFF7A00);
  static const orangeEdge= Color(0xFF8F3F00);

  static const red       = Color(0xFFE5484D);
  static const redEdge   = Color(0xFF7A1C20);

  static const wood      = Color(0xFF9A6B3A);
  static const woodLight = Color(0xFFB98650);
  static const woodEdge  = Color(0xFF3E2610);

  static const silver    = Color(0xFFD0D5DB);
  static const silverEdge= Color(0xFF6B7280);
  static const bronze    = Color(0xFFCD7F32);
  static const bronzeEdge= Color(0xFF6B3E14);
}

const List<String> kBlockFontFallback = [
  'Arial Rounded MT Bold',
  'Arial Black',
  'Inter',
  'Arial',
];

/// Heavy label with a black outline + drop shadow (classic game-menu look).
class BlockText extends StatelessWidget {
  final String text;
  final double size;
  final Color color;
  final double stroke;
  final TextAlign align;
  final int? maxLines;

  const BlockText(
    this.text, {
    super.key,
    required this.size,
    this.color = Colors.white,
    this.stroke = 4,
    this.align = TextAlign.start,
    this.maxLines,
  });

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontFamily: 'Arial Rounded MT Bold',
      fontFamilyFallback: kBlockFontFallback,
      fontSize: size,
      fontWeight: FontWeight.w900,
      height: 1.1,
    );
    final overflow = maxLines == null ? null : TextOverflow.ellipsis;
    return Stack(
      children: [
        Text(
          text,
          textAlign: align,
          maxLines: maxLines,
          overflow: overflow,
          style: base.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = stroke
              ..strokeJoin = StrokeJoin.round
              ..color = Colors.black,
          ),
        ),
        Text(
          text,
          textAlign: align,
          maxLines: maxLines,
          overflow: overflow,
          style: base.copyWith(
            color: color,
            shadows: const [Shadow(offset: Offset(0, 2), color: Color(0x99000000))],
          ),
        ),
      ],
    );
  }
}

/// Static plastic block: solid colour + thick edge + hard shadow below.
/// (Reserves `depth` px below itself so the shadow never overlaps siblings.)
class Block extends StatelessWidget {
  final Color color;
  final Color edge;
  final double radius;
  final double depth;
  final EdgeInsets padding;
  final bool gloss;
  final Widget child;

  const Block({
    super.key,
    required this.color,
    required this.edge,
    required this.child,
    this.radius = 16,
    this.depth = 6,
    this.padding = const EdgeInsets.all(12),
    this.gloss = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: depth),
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: edge, width: 3),
          boxShadow: [BoxShadow(color: edge, offset: Offset(0, depth))],
        ),
        child: Stack(
          children: [
            if (gloss)
              Positioned(
                left: 3,
                right: 3,
                top: 3,
                height: 14,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(radius * 0.6),
                  ),
                ),
              ),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }
}

/// Clickable block: sits raised, sinks when pressed (or when `forcePressed`,
/// e.g. a selected tile).
class PressBlock extends StatefulWidget {
  final Color color;
  final Color edge;
  final double radius;
  final double depth;
  final bool forcePressed;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Widget child;

  const PressBlock({
    super.key,
    required this.color,
    required this.edge,
    required this.child,
    this.onTap,
    this.radius = 16,
    this.depth = 6,
    this.forcePressed = false,
    this.padding = const EdgeInsets.all(12),
  });

  @override
  State<PressBlock> createState() => _PressBlockState();
}

class _PressBlockState extends State<PressBlock> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final pressed = _down || widget.forcePressed;
    final sink = pressed ? widget.depth - 1 : 0.0;

    return GestureDetector(
      onTapDown: widget.onTap == null ? null : (_) => setState(() => _down = true),
      onTapUp: widget.onTap == null
          ? null
          : (_) {
              setState(() => _down = false);
              widget.onTap!();
            },
      onTapCancel: () => setState(() => _down = false),
      child: Padding(
        padding: EdgeInsets.only(bottom: widget.depth),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          transform: Matrix4.translationValues(0, sink, 0),
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.circular(widget.radius),
            border: Border.all(color: widget.edge, width: 3),
            boxShadow: [
              BoxShadow(color: widget.edge, offset: Offset(0, widget.depth - sink)),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                left: 3,
                right: 3,
                top: 3,
                height: 12,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: pressed ? 0.12 : 0.24),
                    borderRadius: BorderRadius.circular(widget.radius * 0.6),
                  ),
                ),
              ),
              Padding(padding: widget.padding, child: widget.child),
            ],
          ),
        ),
      ),
    );
  }
}

/// Chunky green loading bar inside a thick dark frame.
class BlockBar extends StatelessWidget {
  final double value; // 0..1
  final double height;
  final Color color;

  const BlockBar({
    super.key,
    required this.value,
    this.height = 20,
    this.color = Rb.green,
  });

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(0.0, 1.0).toDouble();
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Rb.track,
        borderRadius: BorderRadius.circular(height * 0.55),
        border: Border.all(color: Rb.panelEdge, width: 3),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height * 0.35),
        child: SizedBox(
          height: height,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: v),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOut,
            builder: (_, anim, __) => Stack(
              fit: StackFit.expand,
              children: [
                LinearProgressIndicator(
                  value: anim,
                  minHeight: height,
                  backgroundColor: const Color(0xFF3A3D40),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
                Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    height: height * 0.32,
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── Blocky landscape ─────────────────────────

class LandscapeTheme {
  final Color sky, skyLow, sun, hill, leaf, leafLight, trunk, grass, grassLight, dirt;
  const LandscapeTheme({
    required this.sky,
    required this.skyLow,
    required this.sun,
    required this.hill,
    required this.leaf,
    required this.leafLight,
    required this.trunk,
    required this.grass,
    required this.grassLight,
    required this.dirt,
  });

  static const valley = LandscapeTheme(
    sky: Color(0xFF8FD0FF), skyLow: Color(0xFFBBE4FF), sun: Color(0xFFFFE066),
    hill: Color(0xFF4E9B4A), leaf: Color(0xFF2E7D32), leafLight: Color(0xFF4CAF50),
    trunk: Color(0xFF6B4423), grass: Color(0xFF5FA05A), grassLight: Color(0xFF7CC26F),
    dirt: Color(0xFF7A4B22),
  );

  static const ashen = LandscapeTheme(
    sky: Color(0xFFD08A6A), skyLow: Color(0xFFE8B08A), sun: Color(0xFFFFD29A),
    hill: Color(0xFF6B5A5A), leaf: Color(0xFF4A3C3C), leafLight: Color(0xFF6E5A52),
    trunk: Color(0xFF3B2A22), grass: Color(0xFF7A6A5E), grassLight: Color(0xFF9A8878),
    dirt: Color(0xFF4A3A30),
  );

  static const frozen = LandscapeTheme(
    sky: Color(0xFFA9D8F5), skyLow: Color(0xFFD6EEFC), sun: Color(0xFFFFFFFF),
    hill: Color(0xFFBFD9EA), leaf: Color(0xFF6FA8C9), leafLight: Color(0xFFA7D3EA),
    trunk: Color(0xFF5B4636), grass: Color(0xFFE6F2F9), grassLight: Color(0xFFFFFFFF),
    dirt: Color(0xFF8AA7B8),
  );

  /// World 1 = valley, 2 = ashen, 3 = frozen.
  static LandscapeTheme forWorld(int world) {
    switch (world) {
      case 2:  return ashen;
      case 3:  return frozen;
      default: return valley;
    }
  }
}

/// Voxel-style level backdrop: sky, sun, clouds, hills, trees, studded ground.
class BlockLandscape extends StatelessWidget {
  final LandscapeTheme theme;
  const BlockLandscape({super.key, this.theme = LandscapeTheme.valley});

  @override
  Widget build(BuildContext context) =>
      SizedBox.expand(child: CustomPaint(painter: _LandscapePainter(theme)));
}

class _LandscapePainter extends CustomPainter {
  final LandscapeTheme t;
  const _LandscapePainter(this.t);

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()..isAntiAlias = false;
    void box(Color c, double l, double tp, double w, double h) {
      p.color = c;
      canvas.drawRect(Rect.fromLTWH(l, tp, w, h), p);
    }

    void rbox(Color c, double l, double tp, double w, double h, double r) {
      p.color = c;
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(l, tp, w, h), Radius.circular(r)), p);
    }

    final w = s.width, h = s.height;
    final u = w / 20;
    final hz = h * 0.88; // horizon / ground line

    box(t.sky, 0, 0, w, hz);
    box(t.skyLow, 0, hz * 0.58, w, hz * 0.42);
    box(t.sun, w * 0.74, h * 0.06, u * 2.4, u * 2.4);

    void cloud(double x, double y, double cw) {
      final ch = cw * 0.3;
      box(Colors.white, x + cw * 0.18, y, cw * 0.5, ch);
      box(Colors.white, x, y + ch, cw, ch);
    }

    cloud(w * 0.06, h * 0.07, u * 3.6);
    cloud(w * 0.58, h * 0.19, u * 2.8);

    // hills
    rbox(t.hill, -u * 2, hz - u * 4.2, w * 0.62, u * 9, u * 2.4);
    rbox(t.hill, w * 0.46, hz - u * 3.0, w * 0.7, u * 8, u * 2.4);

    // trees
    for (final fx in [0.07, 0.2, 0.8, 0.93]) {
      final x = w * fx;
      box(t.trunk, x - u * 0.3, hz - u * 2.4, u * 0.7, u * 2.4);
      box(t.leaf, x - u * 1.2, hz - u * 5.0, u * 2.6, u * 2.8);
      box(t.leafLight, x - u * 0.7, hz - u * 6.2, u * 1.6, u * 1.4);
    }

    // ground + studs
    box(t.grass, 0, hz, w, h * 0.07);
    box(t.grassLight, 0, hz, w, u * 0.5);
    for (double x = u * 0.8; x < w; x += u * 1.6) {
      box(t.grassLight, x, hz + u * 1.0, u * 0.6, u * 0.3);
    }
    box(t.dirt, 0, hz + h * 0.07, w, h);
  }

  @override
  bool shouldRepaint(covariant _LandscapePainter old) => old.t != t;
}

// ───────────────────────── Selectable level backgrounds ─────────────────────────

/// Asset key of the boss-map backdrop (assets/images/boss_map_bg.png).
const String kBossMapAsset = 'assets/images/boss_map_bg.png';

/// Resolves a saved `background_id` to a widget that fills its parent.
/// ids: 'valley' | 'ashen' | 'frozen' | 'boss_map'. Anything else -> [fallback].
class BlockBackground extends StatelessWidget {
  final String? id;
  final LandscapeTheme fallback;
  const BlockBackground({super.key, this.id, this.fallback = LandscapeTheme.valley});

  @override
  Widget build(BuildContext context) {
    switch (id) {
      case 'valley':
        return const BlockLandscape(theme: LandscapeTheme.valley);
      case 'ashen':
        return const BlockLandscape(theme: LandscapeTheme.ashen);
      case 'frozen':
        return const BlockLandscape(theme: LandscapeTheme.frozen);
      case 'boss_map':
        return SizedBox.expand(
          child: Image.asset(
            kBossMapAsset,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.none,
            errorBuilder: (_, __, ___) => BlockLandscape(theme: fallback),
          ),
        );
      default:
        return BlockLandscape(theme: fallback);
    }
  }
}