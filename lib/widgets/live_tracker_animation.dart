import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../models/character_profile.dart';
import '../models/outfit_catalog.dart';
import '../state/evolution_state.dart';
import 'avatar_layer_stack.dart';
import 'avatar_preview.dart';
import 'block_ui.dart';
import 'game_stage.dart' show SceneBackPainter;
import 'hero_sprite.dart' show kDefaultClothes;

// ───────────────────────── state machine ─────────────────────────

enum RunState { idle, walk, jog, run }

/// Speed -> stance.   0 = IDLE · (0,5] = WALK · (5,10] = JOG · >10 = RUN
RunState runStateForSpeed(double kmh) {
  if (kmh <= 0) return RunState.idle;
  if (kmh <= 5) return RunState.walk;
  if (kmh <= 10) return RunState.jog;
  return RunState.run;
}

/// Time each sprite frame stays on screen.
Duration frameIntervalFor(RunState s) {
  switch (s) {
    case RunState.idle:
      return const Duration(milliseconds: 600);
    case RunState.walk:
      return const Duration(milliseconds: 200);
    case RunState.jog:
      return const Duration(milliseconds: 120);
    case RunState.run:
      return const Duration(milliseconds: 70);
  }
}

/// While a sudden challenge is live the runner is forced into the RUN stance,
/// the sprite loop flips a frame every [kBoostFrameInterval] (about 25 fps,
/// the fastest the 8-frame loop can go), and the scenery scrolls as if at
/// least [kBoostSpeedKmh].
const Duration kBoostFrameInterval = Duration(milliseconds: 40);
const double kBoostSpeedKmh = 24;

extension on RunState {
  /// Asset sub-folder: assets/images/character/anim/<folder>/...
  String get folder => name; // idle | walk | jog | run
}

/// Optional extra scrolling image layer behind the character
/// (e.g. a far-mountains PNG). `speedFactor` 1.0 = same as the road.
class ParallaxImageLayer {
  final String asset;
  final double speedFactor;
  const ParallaxImageLayer(this.asset, {this.speedFactor = 1});
}

// ───────────────────────── widget ─────────────────────────

/// Loop-scrolling pixel-art running engine for the live tracker viewport.
///
/// SPRITE FRAMES (all 286x512, transparent PNG, frames 01..08):
///   assets/images/character/anim/<state>/body_<tier>/frame_01.png … frame_08.png
///   assets/images/character/anim/<state>/hair_<hairId>/frame_01.png …
///   assets/images/character/anim/<state>/gear_<outfitId>/frame_01.png …
///     <state>  = idle | walk | jog | run
///     <tier>   = normal | overweight | obese | underweight
///     <hairId> = warrior_spiky | classic_pompadour | wavy_mane | long_flowing | short_crop
///     <outfitId> = outfit_01 …
///   (Skin tone / hair colour are applied as tints, exactly like the static avatar.)
///
/// Any state whose body frames are missing falls back to the normal layered
/// avatar with a frame-stepped bob/lean, so the screen always works.
class LiveTrackerAnimation extends StatefulWidget {
  /// Real-world speed from GPS (km/h). 0 = standing still.
  final double currentUserSpeedKmh;

  /// Freezes the scenery and shows PAUSED (the runner idles).
  final bool paused;

  /// Frames per loop (frame_01 … frame_NN).
  final int frameCount;

  /// Folder that holds <state>/<layer>/frame_XX.png.
  final String animRoot;

  /// Background scroll in px/second for every 1 km/h.
  final double scrollPxPerKmh;

  /// Optional image layers drawn between the painted scenery and the runner.
  final List<ParallaxImageLayer> backgroundImages;

  /// Pass the user doc map to skip the built-in Firestore stream.
  final Map<String, dynamic>? avatarData;

  /// Sudden-challenge mode: max-velocity sprite loop + fast scenery.
  /// Ignored while [paused].
  final bool boost;

  const LiveTrackerAnimation({
    super.key,
    required this.currentUserSpeedKmh,
    this.paused = false,
    this.boost = false,
    this.frameCount = 8,
    this.animRoot = 'assets/images/character/anim',
    this.scrollPxPerKmh = 28,
    this.backgroundImages = const [],
    this.avatarData,
  });

  @override
  State<LiveTrackerAnimation> createState() => _LiveTrackerAnimationState();
}

class _LiveTrackerAnimationState extends State<LiveTrackerAnimation>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  // frame loop
  final ValueNotifier<int> _frame = ValueNotifier(0);
  int _frameIdx = 0;
  Duration _acc = Duration.zero;
  Duration _last = Duration.zero;
  RunState _state = RunState.idle;

  // scenery
  final ValueNotifier<double> _scroll = ValueNotifier(0);
  double _pxPerSec = 0;

  // assets
  Set<String> _assets = const {};
  final Map<String, List<String>> _frameCache = {};
  RunState? _precached;

  bool get _boosting => widget.boost && !widget.paused;

  /// Speed that drives the stance + scenery (boost lifts it to a sprint).
  double get _speed => widget.paused
      ? 0
      : _boosting
          ? math.max(widget.currentUserSpeedKmh, kBoostSpeedKmh)
          : widget.currentUserSpeedKmh;

  @override
  void initState() {
    super.initState();
    _state = runStateForSpeed(_speed);

    AssetManifest.loadFromAssetBundle(rootBundle).then((m) {
      if (!mounted) return;
      setState(() => _assets = m.listAssets().toSet());
    }).catchError((_) {});

    // The micro-timer: a Ticker fires every display frame and we advance the
    // sprite frame only when the current state's interval has elapsed.
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    var dt = elapsed - _last;
    _last = elapsed;
    if (dt <= Duration.zero || dt > const Duration(milliseconds: 250)) return;

    // 1) state machine
    final next = runStateForSpeed(_speed);
    if (next != _state) {
      _state = next;
      _acc = Duration.zero; // new stance starts on a fresh frame timer
    }

    // 2) sprite frame loop (fixed interval per state)
    final interval = _boosting ? kBoostFrameInterval : frameIntervalFor(_state);
    _acc += dt;
    var advanced = false;
    while (_acc >= interval) {
      _acc -= interval;
      _frameIdx = (_frameIdx + 1) % widget.frameCount;
      advanced = true;
    }
    if (advanced) _frame.value = _frameIdx;

    // 3) parallax scroll: px/s = speed(km/h) * scrollPxPerKmh, eased so the
    //    scenery accelerates / brakes smoothly with the runner.
    final secs = dt.inMicroseconds / 1e6;
    // Non-linear: a stroll crawls, a full run (11+ km/h) makes the world fly.
    // (Boost mode keeps its own fixed sprint speed.)
    final curve = _boosting
        ? 1.0
        : 1.0 + ((_speed - 5.0) / 10.0).clamp(0.0, 1.2).toDouble();
    final target = _speed * widget.scrollPxPerKmh * curve;
    _pxPerSec += (target - _pxPerSec) * math.min(1.0, secs * 6);
    if (_pxPerSec < 0.5 && target == 0) _pxPerSec = 0;
    if (_pxPerSec > 0) _scroll.value += _pxPerSec * secs;
  }

  // ── sprite frame lookup ──────────────────────────────────────────────

  List<String> _framesFor(RunState s, String layerFolder) {
    final key = '${s.folder}/$layerFolder';
    return _frameCache.putIfAbsent(key, () {
      final out = <String>[];
      for (var i = 1; i <= widget.frameCount; i++) {
        final p = '${widget.animRoot}/${s.folder}/$layerFolder/'
            'frame_${i.toString().padLeft(2, '0')}.png';
        if (!_assets.contains(p)) break;
        out.add(p);
      }
      return out;
    });
  }

  void _precache(RunState s, List<String> paths) {
    if (_precached == s) return;
    _precached = s;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final p in paths) {
        precacheImage(AssetImage(p), context);
      }
    });
  }

  // ── build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    Widget scene(Map<String, dynamic>? data) => _scene(context, data);

    final frame = Block(
      color: const Color(0xFF8FD3FF),
      edge: Rb.blueEdge,
      radius: 20,
      depth: 8,
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(17),
        child: widget.avatarData != null || uid == null
            ? scene(widget.avatarData)
            : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(uid)
                    .snapshots(),
                builder: (_, snap) => scene(snap.data?.data()),
              ),
      ),
    );
    return frame;
  }

  Widget _scene(BuildContext context, Map<String, dynamic>? data) {
    final d = data ?? const <String, dynamic>{};
    final p = CharacterProfile.fromFirestore(d);
    final stored = d['body_tier'] as String?;
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    // The tracker always shows the signed-in hero, so use the global form
    // (a fresh check-in applies instantly, before Firestore echoes back).
    final tier = EvolutionState.instance.isOwner(myUid)
        ? EvolutionState.instance.composition.value.tier
        : (p.heightCm == null || p.weightKg == null) && stored != null
            ? BodyTierExt.fromId(stored)
            : p.bodyTier;
    final rawClothes = d['equipped_clothes'];
    final clothes = rawClothes is List
        ? rawClothes.whereType<String>().toList()
        : kDefaultClothes;
    final gearId = clothes.isEmpty ? '' : animGearId(clothes.first);

    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth, h = c.maxHeight;
      final groundH = h * 0.22;
      final avatarH = math.min(h * 0.78, 300.0);
      final avatarW = avatarH * kSpriteWidth / (kSpriteHeight + 44);
      final feetY = groundH * 0.30;

      return Stack(
        children: [
          // ── background: painted parallax scenery ──
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(painter: SceneBackPainter(_scroll, groundH)),
            ),
          ),
          // ── background: optional image layers (scroll left, loop) ──
          for (final l in widget.backgroundImages)
            Positioned.fill(
              child: _ScrollingImage(
                asset: l.asset,
                scroll: _scroll,
                factor: l.speedFactor,
              ),
            ),

          // ── shadow ──
          Positioned(
            bottom: feetY,
            left: w / 2 - 38,
            child: Container(
              width: 76,
              height: 12,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),

          // ── the runner ──
          Positioned(
            bottom: feetY,
            left: (w - avatarW) / 2,
            width: avatarW,
            height: avatarH,
            child: ValueListenableBuilder<int>(
              valueListenable: _frame,
              builder: (_, idx, __) => _runner(
                idx: idx,
                tier: tier,
                p: p,
                gearId: gearId,
                data: d,
                height: avatarH,
              ),
            ),
          ),

          if (widget.paused)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.35),
                alignment: Alignment.center,
                child: const BlockText('⏸ PAUSED', size: 26, stroke: 6),
              ),
            ),
        ],
      );
    });
  }

  Widget _runner({
    required int idx,
    required BodyTier tier,
    required CharacterProfile p,
    required String gearId,
    required Map<String, dynamic> data,
    required double height,
  }) {
    final st = _state;
    final body = _framesFor(
        st, isFemaleGender(p.gender) ? 'body_female_${tier.id}' : 'body_${tier.id}');

    // ───── A) real sprite frames ─────
    if (body.isNotEmpty) {
      final hair = _framesFor(st, 'hair_${p.hairStyle.id}');
      final gear = gearId.isEmpty ? const <String>[] : _framesFor(st, 'gear_$gearId');
      _precache(st, [...body, ...hair, ...gear]);

      String pick(List<String> l) => l[idx % l.length];

      return FittedBox(
        fit: BoxFit.contain,
        clipBehavior: Clip.none,
        child: SizedBox(
          width: kSpriteWidth,
          height: kSpriteHeight + 44, // headroom for tall hair
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                top: 44,
                width: kSpriteWidth,
                height: kSpriteHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // body → hair → gear, every layer Positioned.fill
                    Positioned.fill(
                      child: PixelLayer(
                        path: pick(body),
                        tint: _tint(p.skinTone),
                        filterQuality: FilterQuality.none,
                      ),
                    ),
                    if (hair.isNotEmpty)
                      Positioned.fill(
                        child: PixelLayer(
                          path: pick(hair),
                          tint: _tint(p.hairColor),
                          grayscaleFirst: true,
                          filterQuality: FilterQuality.none,
                        ),
                      ),
                    if (gear.isNotEmpty)
                      Positioned.fill(
                        child: PixelLayer(
                          path: pick(gear),
                          filterQuality: FilterQuality.none,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ───── B) fallback: static layered avatar, frame-stepped motion ─────
    final phase = idx / widget.frameCount * 2 * math.pi;
    double dy = 0, rot = 0, sy = 1;
    switch (st) {
      case RunState.idle: // calm breathing
        sy = 1 + 0.012 * math.sin(phase);
        break;
      case RunState.walk:
        dy = -height * 0.012 * math.sin(phase * 2).abs();
        rot = 0.03;
        break;
      case RunState.jog:
        dy = -height * 0.028 * math.sin(phase * 2).abs();
        rot = 0.07;
        break;
      case RunState.run:
        dy = -height * 0.045 * math.sin(phase * 2).abs();
        rot = 0.12 + 0.02 * math.sin(phase * 2);
        break;
    }

    return Transform.translate(
      offset: Offset(0, dy),
      child: Transform(
        alignment: Alignment.bottomCenter,
        transform: Matrix4.identity()
          ..rotateZ(rot)
          ..scale(1.0, sy),
        child: FittedBox(
          fit: BoxFit.contain,
          clipBehavior: Clip.none,
          child: SizedBox(
            width: kSpriteWidth,
            height: kSpriteHeight + 44,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0,
                  top: 44,
                  width: kSpriteWidth,
                  height: kSpriteHeight,
                  child: AvatarPreview.fromData(
                    data,
                    filterQuality: FilterQuality.none, // never blur
                    ownerUid: FirebaseAuth.instance.currentUser?.uid,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  ColorFilter? _tint(String hex) => ColorFilter.mode(
        Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16)),
        BlendMode.modulate,
      );
}

/// Tiled PNG that scrolls to the LEFT forever (pixel-sharp).
class _ScrollingImage extends StatelessWidget {
  final String asset;
  final ValueNotifier<double> scroll;
  final double factor;

  const _ScrollingImage({
    required this.asset,
    required this.scroll,
    required this.factor,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      return ValueListenableBuilder<double>(
        valueListenable: scroll,
        builder: (_, s, __) {
          // one tile = full viewport height, aspect from the image itself
          return ClipRect(
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              minWidth: 0,
              maxWidth: double.infinity,
              child: _Tiles(
                asset: asset,
                height: c.maxHeight,
                viewWidth: c.maxWidth,
                offset: s * factor,
              ),
            ),
          );
        },
      );
    });
  }
}

class _Tiles extends StatelessWidget {
  final String asset;
  final double height, viewWidth, offset;
  const _Tiles({
    required this.asset,
    required this.height,
    required this.viewWidth,
    required this.offset,
  });

  @override
  Widget build(BuildContext context) {
    // assume square-ish tiles if size unknown: width = viewport width
    final tileW = viewWidth;
    final shift = -(offset % tileW);
    return Transform.translate(
      offset: Offset(shift, 0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Image.asset(
              asset,
              width: tileW,
              height: height,
              fit: BoxFit.fill,
              filterQuality: FilterQuality.none,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => SizedBox(width: tileW, height: height),
            ),
        ],
      ),
    );
  }
}
