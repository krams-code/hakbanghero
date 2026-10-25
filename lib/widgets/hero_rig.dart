import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/character_profile.dart' show BodyTier;
import '../models/hero_items.dart';
import '../models/hero_roster.dart';

/// Native canvas of every hero layer (same 286x512 as the classic avatar).
const double kHeroW = 286;
const double kHeroH = 512;

/// How the hero moves. Same four stances as the run tracker.
enum RigPose { idle, walk, jog, run }

/// Where each limb pivots, as Alignments inside the 286x512 canvas.
/// (Computed from the art; the body width changes with the body form.)
class _Pivots {
  final Alignment hipBack, hipFront, shBack, shFront, neck;
  const _Pivots({
    required this.hipBack,
    required this.hipFront,
    required this.shBack,
    required this.shFront,
    required this.neck,
  });
}

const Map<BodyTier, _Pivots> _kPivots = {
  BodyTier.underweight: _Pivots(
    hipBack: Alignment(-0.0930, 0.4860),
    hipFront: Alignment(0.0930, 0.4860),
    shBack: Alignment(-0.2692, 0.1578),
    shFront: Alignment(0.2692, 0.1578),
    neck: Alignment(0.0000, -0.0062),
  ),
  BodyTier.normal: _Pivots(
    hipBack: Alignment(-0.1272, 0.4968),
    hipFront: Alignment(0.1272, 0.4968),
    shBack: Alignment(-0.3916, 0.1578),
    shFront: Alignment(0.3916, 0.1578),
    neck: Alignment(0.0000, -0.0062),
  ),
  BodyTier.overweight: _Pivots(
    hipBack: Alignment(-0.1518, 0.5188),
    hipFront: Alignment(0.1518, 0.5188),
    shBack: Alignment(-0.4944, 0.1578),
    shFront: Alignment(0.4944, 0.1578),
    neck: Alignment(0.0000, -0.0062),
  ),
  BodyTier.obese: _Pivots(
    hipBack: Alignment(-0.1762, 0.5516),
    hipFront: Alignment(0.1762, 0.5516),
    shBack: Alignment(-0.6070, 0.1578),
    shFront: Alignment(0.6070, 0.1578),
    neck: Alignment(0.0000, -0.0062),
  ),
};

class _Move {
  final double legLift; // fraction of height a stepping foot rises
  final double legRot; // radians
  final double armRot; // radians
  final double bob; // fraction of height the body bounces
  final double sway; // radians the whole hero rocks
  final int periodMs;
  const _Move(this.legLift, this.legRot, this.armRot, this.bob, this.sway, this.periodMs);
}

const Map<RigPose, _Move> _kMoves = {
  RigPose.idle: _Move(0, 0, 0.06, 0.004, 0.0, 2200),
  RigPose.walk: _Move(0.018, 0.10, 0.35, 0.010, 0.02, 900),
  RigPose.jog: _Move(0.034, 0.16, 0.60, 0.020, 0.04, 640),
  RigPose.run: _Move(0.052, 0.22, 0.85, 0.032, 0.06, 440),
};

/// Animated block hero. Free, no Rive file needed: the figure is cut into
/// head / body / 2 arms / 2 legs PNGs and moved with Flutter transforms.
///
/// The body form (underweight / normal / overweight / obese) picks which set
/// of PNGs is used, so the hero changes with the player's weight tier.
class HeroRig extends StatefulWidget {
  final String heroId;
  final BodyTier tier;
  final RigPose pose;

  /// Height in logical pixels. Width follows the 286:512 canvas ratio.
  final double height;

  /// Draw a soft ground shadow under the feet.
  final bool shadow;

  /// Worn items (slot name -> item id), see hero_items.dart.
  final Map<String, String> outfit;

  /// Girl SPROUT art (that player's gender). Null = the signed-in player's.
  final bool? girl;

  const HeroRig({
    super.key,
    required this.heroId,
    required this.tier,
    this.pose = RigPose.idle,
    this.height = 220,
    this.shadow = true,
    this.outfit = const <String, String>{},
    this.girl,
  });

  @override
  State<HeroRig> createState() => _HeroRigState();
}

class _HeroRigState extends State<HeroRig> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _kMoves[widget.pose]!.periodMs),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant HeroRig old) {
    super.didUpdateWidget(old);
    if (old.pose != widget.pose) {
      _c.duration = Duration(milliseconds: _kMoves[widget.pose]!.periodMs);
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.height;
    final w = h * kHeroW / kHeroH;
    if (heroIsCostume(widget.heroId)) {
      return SizedBox(
        width: w,
        height: h,
        child: _CostumeBody(
          anim: _c,
          heroId: widget.heroId,
          tier: widget.tier,
          pose: widget.pose,
          w: w,
          h: h,
          shadow: widget.shadow,
        ),
      );
    }
    return SizedBox(
      width: w,
      height: h,
      child: _RigBody(
        anim: _c,
        heroId: heroArtId(widget.heroId, girl: widget.girl),
        tier: widget.tier,
        pose: widget.pose,
        w: w,
        h: h,
        shadow: widget.shadow,
        outfit: widget.outfit,
      ),
    );
  }
}

/// A costume hero is ONE picture, so it moves like a cartoon: it hops on every
/// step, waddles side to side and squashes a little when it lands.
class _CostumeBody extends StatelessWidget {
  final Animation<double> anim;
  final String heroId;
  final BodyTier tier;
  final RigPose pose;
  final double w, h;
  final bool shadow;

  const _CostumeBody({
    required this.anim,
    required this.heroId,
    required this.tier,
    required this.pose,
    required this.w,
    required this.h,
    required this.shadow,
  });

  @override
  Widget build(BuildContext context) {
    final m = _kMoves[pose]!;
    final img = Image.asset(
      heroLayerAsset(heroId, tier, 'full'),
      width: w,
      height: h,
      fit: BoxFit.fill,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (_, child) {
        final t = anim.value * 2 * math.pi;
        final s = math.sin(t);
        final moving = pose != RigPose.idle;
        final hop = moving ? -s.abs() * m.bob * 2.4 * h : 0.0;
        final tilt = moving ? m.sway * 2.2 * s : 0.02 * s;
        final sy = moving ? 1 + 0.045 * math.cos(2 * t) : 1 + 0.015 * s;
        final sx = 1 - (sy - 1) * 0.7;
        final lift = hop.abs() / h;
        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            if (shadow)
              Positioned(
                left: w * (0.22 + lift),
                width: w * (0.56 - 2 * lift),
                top: h * 0.935,
                height: h * 0.045,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(h),
                  ),
                ),
              ),
            Positioned.fill(
              child: Transform.translate(
                offset: Offset(0, hop),
                child: Transform(
                  alignment: Alignment.bottomCenter,
                  transform: Matrix4.identity()
                    ..rotateZ(tilt)
                    ..scale(sx, sy),
                  child: child,
                ),
              ),
            ),
          ],
        );
      },
      child: img,
    );
  }
}

class _RigBody extends StatelessWidget {
  final Animation<double> anim;
  final String heroId;
  final BodyTier tier;
  final RigPose pose;
  final double w, h;
  final bool shadow;
  final Map<String, String> outfit;

  const _RigBody({
    required this.anim,
    required this.heroId,
    required this.tier,
    required this.pose,
    required this.w,
    required this.h,
    required this.shadow,
    required this.outfit,
  });

  Widget _img(String layer) => Image.asset(
        heroLayerAsset(heroId, tier, layer),
        width: w,
        height: h,
        fit: BoxFit.fill,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );

  Widget _svg(String svg) => SvgPicture.string(
        svg,
        width: w,
        height: h,
        fit: BoxFit.fill,
      );

  /// One body part: its picture plus the worn items drawn on it, moved
  /// together around the same pivot.
  Widget _part(
    String layer, {
    Offset off = Offset.zero,
    double rot = 0,
    Alignment pivot = Alignment.center,
  }) =>
      Positioned.fill(
        child: Transform.translate(
          offset: off,
          child: Transform.rotate(
            angle: rot,
            alignment: pivot,
            child: Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: [
                _img(layer),
                for (final svg in outfitSvgs(outfit, tier, layer)) _svg(svg),
              ],
            ),
          ),
        ),
      );

  /// Items worn BEHIND the hero (capes, wings, backpacks).
  Widget _behind(Offset off) {
    final list = outfitSvgs(outfit, tier, 'back');
    if (list.isEmpty) return const SizedBox.shrink();
    return Positioned.fill(
      child: Transform.translate(
        offset: off,
        child: Stack(
          clipBehavior: Clip.none,
          children: [for (final svg in list) _svg(svg)],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pv = _kPivots[tier]!;
    final m = _kMoves[pose]!;
    return AnimatedBuilder(
      animation: anim,
      builder: (_, __) {
        final t = anim.value * 2 * math.pi;
        final s = math.sin(t);

        // body bounce: up on every footfall (twice per cycle)
        final bob = -s.abs() * m.bob * h;
        final breathe = pose == RigPose.idle ? 1 + 0.012 * s : 1.0;
        final squash = pose == RigPose.idle ? 1.0 : 1 + 0.015 * math.cos(2 * t);

        // legs: the stepping foot lifts and tilts a little
        final liftFront = -math.max(0.0, s) * m.legLift * h;
        final liftBack = -math.max(0.0, -s) * m.legLift * h;
        final legFrontRot = s * m.legRot * 0.5;
        final legBackRot = -s * m.legRot * 0.5;

        // arms pump out (away from the body) in turn
        final armFront = -m.armRot * (0.4 + 0.6 * s);
        final armBack = m.armRot * (0.4 - 0.6 * s);

        // head nods a little behind the body
        final headRot = 0.04 * s * (pose == RigPose.idle ? 0.3 : 1);
        final headOff = Offset(0, bob * 0.6);

        final upper = Offset(0, bob);

        return Transform(
          alignment: Alignment.bottomCenter,
          transform: Matrix4.identity()
            ..rotateZ(m.sway * s)
            ..scale(1.0, breathe * squash),
          child: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              if (shadow)
                Positioned(
                  left: w * (0.22 + bob.abs() / h),
                  width: w * (0.56 - 2 * bob.abs() / h),
                  top: h * 0.935,
                  height: h * 0.045,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(h),
                    ),
                  ),
                ),
              _behind(upper),
              _part('leg_back',
                  off: Offset(0, liftBack), rot: legBackRot, pivot: pv.hipBack),
              _part('leg_front',
                  off: Offset(0, liftFront), rot: legFrontRot, pivot: pv.hipFront),
              _part('arm_back', off: upper, rot: armBack, pivot: pv.shBack),
              _part('body', off: upper),
              _part('arm_front', off: upper, rot: armFront, pivot: pv.shFront),
              _part('head', off: headOff, rot: headRot, pivot: pv.neck),
            ],
          ),
        );
      },
    );
  }
}

/// Still picture of a hero (list rows, top bar, profile...). Drops into the
/// same 286:512 box as the classic avatar.
class HeroStill extends StatelessWidget {
  final String heroId;
  final BodyTier tier;
  final FilterQuality filterQuality;
  final Map<String, String> outfit;

  /// Girl SPROUT art (that player's gender). Null = the signed-in player's.
  final bool? girl;

  const HeroStill({
    super.key,
    required this.heroId,
    required this.tier,
    this.filterQuality = FilterQuality.medium,
    this.outfit = const <String, String>{},
    this.girl,
  });

  @override
  Widget build(BuildContext context) {
    Widget svg(String s) => SvgPicture.string(s, fit: BoxFit.fill);
    if (heroIsCostume(heroId)) {
      // costume heroes wear their own outfit: no gear layers
      return AspectRatio(
        aspectRatio: kHeroW / kHeroH,
        child: Image.asset(
          heroLayerAsset(heroId, tier, 'full'),
          fit: BoxFit.fill,
          filterQuality: filterQuality,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      );
    }
    return AspectRatio(
      aspectRatio: kHeroW / kHeroH,
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          for (final s in outfitSvgs(outfit, tier, 'back')) svg(s),
          Image.asset(
            heroLayerAsset(heroArtId(heroId, girl: girl), tier, 'full'),
            fit: BoxFit.fill,
            filterQuality: filterQuality,
            gaplessPlayback: true,
          ),
          for (final layer in const [
            'leg_back',
            'leg_front',
            'arm_back',
            'body',
            'arm_front',
            'head',
          ])
            for (final s in outfitSvgs(outfit, tier, layer)) svg(s),
        ],
      ),
    );
  }
}

/// Decode a hero's pictures ahead of time so the first frame never pops in.
Future<void> precacheHero(BuildContext context, String heroId, BodyTier tier,
    {bool? girl}) async {
  if (heroIsCostume(heroId)) {
    await precacheImage(AssetImage(heroLayerAsset(heroId, tier, 'full')), context);
    return;
  }
  for (final l in const ['full', 'leg_back', 'leg_front', 'arm_back', 'body', 'arm_front', 'head']) {
    await precacheImage(
        AssetImage(heroLayerAsset(heroArtId(heroId, girl: girl), tier, l)), context);
  }
}
