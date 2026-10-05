import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/activity_model.dart';
import 'avatar_layer_stack.dart' show kSpriteWidth, kSpriteHeight;
import 'avatar_preview.dart';


// ═════════════════════════════════════════════════════════════════
//  Roblox-style "Start Session" view
//  Chunky plastic blocks: solid colour, thick dark border, hard
//  (blur-free) drop shadow underneath, extra-bold outlined labels.
// ═════════════════════════════════════════════════════════════════

// ───────────────────────── Palette ─────────────────────────
const _bg         = Color(0xFF232527);
const _panel      = Color(0xFF393B3D);
const _panelEdge  = Color(0xFF0E0F10);
const _track      = Color(0xFF1A1B1C);
const _slate      = Color(0xFF2F3640);
const _slateEdge  = Color(0xFF0B0D10);

const _green      = Color(0xFF00B06F);
const _greenEdge  = Color(0xFF006B44);
const _gold       = Color(0xFFFFB800);
const _goldEdge   = Color(0xFF8A5A00);

const _walk       = Color(0xFF7EE08A); // pastel green
const _walkEdge   = Color(0xFF2F7A3B);
const _jog        = Color(0xFF2EC4FF); // electric sky blue
const _jogEdge    = Color(0xFF0A6C99);
const _run        = Color(0xFFFF7A00); // neon orange
const _runEdge    = Color(0xFF8F3F00);

const _sky        = Color(0xFF8FD0FF);
const _baseplate  = Color(0xFF5FA05A);

// ───────────────────────── Milestones (Trophy Road) ─────────────────────────

class Milestone {
  final double km;     // total km needed
  final String item;   // reward name
  final String emoji;  // placeholder icon until you have item art
  const Milestone(this.km, this.item, [this.emoji = '📦']);
}

/// TODO: replace with your real rewards. 10 entries = "MILESTONE n / 10".
const List<Milestone> kMilestones = [
  Milestone(1.0,   'Sprout Headband', '🎀'),
  Milestone(5.0,   'Trail Sneakers', '👟'),
  Milestone(10.0,  'Windrunner Gloves', '🧤'),
  Milestone(15.0,  'Slayer Iron Boots', '🥾'),
  Milestone(25.0,  'Obsidian Greaves', '📦'),
  Milestone(40.0,  'Dragon Scale Vest', '🧥'),
  Milestone(60.0,  'Storm Cape', '🧣'),
  Milestone(85.0,  'Phoenix Crown', '👑'),
  Milestone(120.0, 'Titan Gauntlets', '🥊'),
  Milestone(160.0, 'Legend Armor', '🛡️'),
];

// ───────────────────────── Typography ─────────────────────────

const _fontFallback = ['Arial Rounded MT Bold', 'Arial Black', 'Inter', 'Arial'];

/// Heavy label with a black outline + drop shadow (game-UI look).
class _BlockText extends StatelessWidget {
  final String text;
  final double size;
  final Color color;
  final double stroke;
  final TextAlign align;
  final int? maxLines;

  const _BlockText(
    this.text, {
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
      fontFamilyFallback: _fontFallback,
      fontSize: size,
      fontWeight: FontWeight.w900,
      height: 1.1,
    );
    return Stack(
      children: [
        Text(
          text,
          textAlign: align,
          maxLines: maxLines,
          overflow: maxLines == null ? null : TextOverflow.ellipsis,
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
          overflow: maxLines == null ? null : TextOverflow.ellipsis,
          style: base.copyWith(
            color: color,
            shadows: const [Shadow(offset: Offset(0, 2), color: Color(0x99000000))],
          ),
        ),
      ],
    );
  }
}

// ───────────────────────── Block primitives ─────────────────────────

/// Static plastic block: solid colour + thick edge + hard shadow below.
class _Block extends StatelessWidget {
  final Color color;
  final Color edge;
  final double radius;
  final double depth;
  final EdgeInsets padding;
  final bool gloss;
  final Widget child;

  const _Block({
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

/// Clickable block: sits raised, sinks when pressed (or when `pressed` is
/// forced, e.g. a selected tile).
class _PressBlock extends StatefulWidget {
  final Color color;
  final Color edge;
  final double radius;
  final double depth;
  final bool forcePressed;
  final EdgeInsets padding;
  final VoidCallback onTap;
  final Widget child;

  const _PressBlock({
    required this.color,
    required this.edge,
    required this.onTap,
    required this.child,
    this.radius = 16,
    this.depth = 6,
    this.forcePressed = false,
    this.padding = const EdgeInsets.all(12),
  });

  @override
  State<_PressBlock> createState() => _PressBlockState();
}

class _PressBlockState extends State<_PressBlock> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final pressed = _down || widget.forcePressed;
    final sink = pressed ? widget.depth - 1 : 0.0;

    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) {
        setState(() => _down = false);
        widget.onTap();
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

// ───────────────────────── Activity tiers ─────────────────────────

class _Tier {
  final ActivityType type;
  final String icon, label, range;
  final Color color, edge;
  const _Tier(this.type, this.icon, this.label, this.range, this.color, this.edge);
}

const List<_Tier> _tiers = [
  _Tier(ActivityType.walk, '🚶', 'WALK', '< 6 km/h',     _walk, _walkEdge),
  _Tier(ActivityType.jog,  '🏃', 'JOG',  '6-10 km/h',    _jog,  _jogEdge),
  _Tier(ActivityType.run,  '🔥', 'RUN',  '10+ km/h',     _run,  _runEdge),
];

_Tier _tierOf(ActivityType t) => _tiers.firstWhere((x) => x.type == t);

// ───────────────────────── The view ─────────────────────────

class PreRunView extends StatelessWidget {
  final ActivityType selected;
  final ValueChanged<ActivityType> onSelect;
  final VoidCallback onBack;
  final VoidCallback onStart;

  const PreRunView({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.onBack,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: uid == null
          ? null
          : FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        final totalKm = (data?['total_km'] as num?)?.toDouble() ?? 0.0;

        // Where is the player on the Trophy Road?
        var idx = kMilestones.indexWhere((m) => totalKm < m.km);
        final cleared = idx == -1;
        if (cleared) idx = kMilestones.length - 1;
        final next = kMilestones[idx];
        final prevKm = idx == 0 ? 0.0 : kMilestones[idx - 1].km;
        final progress = cleared
            ? 1.0
            : ((totalKm - prevKm) / (next.km - prevKm)).clamp(0.0, 1.0);
        final remaining = cleared ? 0.0 : next.km - totalKm;

        return ColoredBox(
          color: _bg,
          child: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Column(
                      children: [
                        _buildBanner(
                          milestone: idx + 1,
                          total: kMilestones.length,
                          cleared: cleared,
                          totalKm: totalKm,
                          targetKm: next.km,
                          progress: progress,
                        ),
                        const SizedBox(height: 16),
                        _buildViewport(data),
                        const SizedBox(height: 16),
                        _buildTiles(),
                        const SizedBox(height: 4),
                        const Text(
                          'GPS confirms your pace during the session',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 14),
                        _buildUnlockSlot(next, remaining, cleared),
                      ],
                    ),
                  ),
                ),
                _buildFooter(),
              ],
            ),
          ),
        );
      },
    );
  }

  // ───────────── top tracker banner ─────────────

  Widget _buildBanner({
    required int milestone,
    required int total,
    required bool cleared,
    required double totalKm,
    required double targetKm,
    required double progress,
  }) {
    return _Block(
      color: _panel,
      edge: _panelEdge,
      depth: 6,
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              _PressBlock(
                color: const Color(0xFFE2E2E2),
                edge: const Color(0xFF6B6B6B),
                depth: 4,
                radius: 12,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                onTap: onBack,
                child: const Text(
                  '◀',
                  style: TextStyle(
                    color: Color(0xFF232527),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: _BlockText('START SESSION', size: 20),
                ),
              ),
              const SizedBox(width: 8),
              // glossy reward box
              _Block(
                color: _gold,
                edge: _goldEdge,
                depth: 4,
                radius: 12,
                gloss: true,
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                child: _BlockText(
                  '🏆 MILESTONE $milestone / $total',
                  size: 11,
                  stroke: 3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: _BlockText(
              cleared
                  ? '🎉 ALL MILESTONES CLEARED!'
                  : '🏃‍♂️ ${totalKm.toStringAsFixed(1)} / ${targetKm.toStringAsFixed(1)} km to unlock next item',
              size: 12,
              stroke: 3,
            ),
          ),
          const SizedBox(height: 8),
          // chunky green loading bar in a thick dark track
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: _track,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _panelEdge, width: 3),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: SizedBox(
                height: 22,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: progress),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOut,
                  builder: (_, v, __) => Stack(
                    fit: StackFit.expand,
                    children: [
                      LinearProgressIndicator(
                        value: v,
                        minHeight: 22,
                        backgroundColor: const Color(0xFF3A3D40),
                        valueColor: const AlwaysStoppedAnimation<Color>(_green),
                      ),
                      Align(
                        alignment: Alignment.topCenter,
                        child: Container(
                          height: 7,
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────── avatar viewport ─────────────

  Widget _buildViewport(Map<String, dynamic>? data) {
    final tier = _tierOf(selected);

    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth.clamp(0.0, 340.0).toDouble();
      final h = w * 1.12;

      return Center(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            width: w,
            height: h,
            decoration: BoxDecoration(
              color: _sky,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: tier.edge, width: 4),
              boxShadow: [BoxShadow(color: tier.edge, offset: const Offset(0, 8))],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // baseplate
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: FractionallySizedBox(
                      heightFactor: 0.09,
                      widthFactor: 1,
                      child: Container(
                        decoration: const BoxDecoration(
                          color: _baseplate,
                          border: Border(
                            top: BorderSide(color: Color(0xFF3F7A3B), width: 4),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // blocky clouds
                  const Positioned(left: 18, top: 22, child: _Cloud(width: 64)),
                  const Positioned(right: 20, top: 52, child: _Cloud(width: 48)),

                  // the avatar model. World = 286x560: the 286x512 sprite sits
                  // 44px down so tall hair spikes have headroom above it.
                  Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 4),
                    child: FittedBox(
                      fit: BoxFit.contain,
                      clipBehavior: Clip.none,
                      child: SizedBox(
                        width: kSpriteWidth,
                        height: kSpriteHeight + 48,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned(
                              left: 0,
                              top: 44,
                              width: kSpriteWidth,
                              height: kSpriteHeight,
                              child: AvatarPreview.fromData(data),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // activity tag
                  Positioned(
                    left: 10,
                    top: 10,
                    child: _Block(
                      color: tier.color,
                      edge: tier.edge,
                      depth: 3,
                      radius: 10,
                      gloss: true,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      child: _BlockText('${tier.icon} ${tier.label}', size: 12, stroke: 3),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }

  // ───────────── choice tiles ─────────────

  Widget _buildTiles() {
    return Row(
      children: [
        for (var i = 0; i < _tiers.length; i++) ...[
          Expanded(child: _buildTile(_tiers[i])),
          if (i != _tiers.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }

  Widget _buildTile(_Tier t) {
    final isSel = selected == t.type;
    // unselected = muted + raised; selected = bright + pushed down
    final color = isSel ? t.color : Color.lerp(_panel, t.color, 0.22)!;
    final edge = isSel ? t.edge : _panelEdge;

    return _PressBlock(
      color: color,
      edge: edge,
      depth: 6,
      forcePressed: isSel,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      onTap: () => onSelect(t.type),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(t.icon, style: const TextStyle(fontSize: 26)),
          const SizedBox(height: 4),
          _BlockText(t.label, size: 15, stroke: 3.5, align: TextAlign.center),
          const SizedBox(height: 2),
          Text(
            t.range,
            style: TextStyle(
              color: Colors.white.withValues(alpha: isSel ? 0.95 : 0.55),
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  // ───────────── next item slot ─────────────

  Widget _buildUnlockSlot(Milestone next, double remaining, bool cleared) {
    return _Block(
      color: _slate,
      edge: _slateEdge,
      depth: 6,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          // item display square
          _Block(
            color: const Color(0xFF454B54),
            edge: _slateEdge,
            depth: 4,
            radius: 12,
            padding: EdgeInsets.zero,
            child: SizedBox(
              width: 54,
              height: 54,
              child: Center(
                child: Text(next.emoji, style: const TextStyle(fontSize: 28)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (cleared)
                  const _BlockText('All items unlocked! 🎉', size: 14, stroke: 3)
                else ...[
                  Text.rich(
                    TextSpan(
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        height: 1.3,
                      ),
                      children: [
                        const TextSpan(text: 'Next Item: '),
                        TextSpan(
                          text: '${next.item}!',
                          style: const TextStyle(color: _gold),
                        ),
                        TextSpan(text: ' 📦 Unlock at ${next.km.toStringAsFixed(1)} KM.'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${remaining.toStringAsFixed(1)} KM to go!',
                    style: const TextStyle(
                      color: _walk,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ───────────── giant action button ─────────────

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: _bg,
        border: Border(top: BorderSide(color: _panelEdge, width: 3)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          child: _PressBlock(
            color: _green,
            edge: _greenEdge,
            depth: 10,
            radius: 18,
            padding: const EdgeInsets.symmetric(vertical: 20),
            onTap: onStart,
            child: const Center(child: _BlockText('▶ PLAY STAGE', size: 26, stroke: 5)),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── Decor ─────────────────────────

/// Simple blocky cloud for the sky backdrop.
class _Cloud extends StatelessWidget {
  final double width;
  const _Cloud({required this.width});

  @override
  Widget build(BuildContext context) {
    final h = width * 0.32;
    return SizedBox(
      width: width,
      height: h * 1.6,
      child: Stack(
        children: [
          Positioned(
            left: width * 0.18,
            top: 0,
            child: Container(
              width: width * 0.5,
              height: h,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
          Positioned(
            left: 0,
            bottom: 0,
            child: Container(
              width: width,
              height: h,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}