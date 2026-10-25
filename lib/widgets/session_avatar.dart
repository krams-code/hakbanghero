import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'avatar_layer_stack.dart';
import '../models/body_composition.dart';
import '../models/character_profile.dart';
import '../models/hero_items.dart';
import '../models/hero_roster.dart';
import '../state/evolution_state.dart';
import 'avatar_preview.dart';
import 'hero_rig.dart' show HeroStill;
import '../state/user_doc.dart';

enum AvatarStance { idle, running, victory }

/// The player's full custom avatar (body + face + hair + outfit) with a
/// procedural stance animation.
///
/// There are no run-cycle / victory sprite frames in assets yet, so the
/// stance is faked by transforming the whole layered sprite:
///  * idle    – slow breathing
///  * running – fast bounce + forward lean (cadence follows [cadence])
///  * victory – big hop + squash/stretch (the "hands raised" celebration)
/// When real frames exist, swap the body of [_sprite] per stance.
class SessionAvatar extends StatefulWidget {
  final AvatarStance stance;
  final double height;

  /// 1.0 = jog. Higher = faster footfalls (walk ~0.7, run ~1.4).
  final double cadence;

  const SessionAvatar({
    super.key,
    required this.height,
    this.stance = AvatarStance.idle,
    this.cadence = 1,
  });

  @override
  State<SessionAvatar> createState() => _SessionAvatarState();
}

class _SessionAvatarState extends State<SessionAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: _period)..repeat();
  }

  Duration get _period {
    switch (widget.stance) {
      case AvatarStance.running:
        return Duration(milliseconds: (560 / widget.cadence.clamp(0.5, 2.0)).round());
      case AvatarStance.victory:
        return const Duration(milliseconds: 800);
      case AvatarStance.idle:
        return const Duration(milliseconds: 1800);
    }
  }

  @override
  void didUpdateWidget(covariant SessionAvatar old) {
    super.didUpdateWidget(old);
    if (old.stance != widget.stance || old.cadence != widget.cadence) {
      _ctrl.duration = _period;
      _ctrl.repeat();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  Widget _sprite(Map<String, dynamic>? data) {
    final hero = heroIdOf(data);
    if (hero != null) {
      // hero art is 286x512; the stance animation below moves it as one piece
      return ValueListenableBuilder<BodyCompositionState>(
        valueListenable: EvolutionState.instance.composition,
        builder: (_, form, __) => FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: kSpriteWidth,
            height: kSpriteHeight + 44,
            child: Padding(
              padding: const EdgeInsets.only(top: 44),
              child: HeroStill(
                  heroId: hero,
                  tier: form.tier,
                  outfit: outfitOf(data),
                  girl: genderKey(data?['gender']) == 'female'),
            ),
          ),
        ),
      );
    }
    // 286x560 world: 44px headroom so tall hair is never clipped.
    return FittedBox(
      fit: BoxFit.contain,
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
                filterQuality: FilterQuality.medium,
                ownerUid: FirebaseAuth.instance.currentUser?.uid,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = _uid;
    final h = widget.height;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: uid == null ? null : UserDoc.instance.stream,
      initialData: UserDoc.instance.snapshotFor(uid),
      builder: (context, snap) {
        final sprite = _sprite(snap.data?.data());
        return SizedBox(
          height: h,
          width: h * kSpriteWidth / (kSpriteHeight + 44),
          child: AnimatedBuilder(
            animation: _ctrl,
            child: sprite,
            builder: (_, child) {
              final t = _ctrl.value * 2 * math.pi;
              double dy = 0, rot = 0, sx = 1, sy = 1;

              switch (widget.stance) {
                case AvatarStance.running:
                  dy = -h * 0.045 * math.sin(t).abs();
                  rot = 0.10 + 0.025 * math.sin(t);
                  sy = 1 + 0.02 * math.sin(t * 2);
                  break;
                case AvatarStance.victory:
                  final hop = math.sin(t).abs();
                  dy = -h * 0.10 * hop;
                  sx = 1 - 0.04 * hop;
                  sy = 1 + 0.06 * hop;
                  rot = 0.04 * math.sin(t);
                  break;
                case AvatarStance.idle:
                  sy = 1 + 0.012 * math.sin(t);
                  break;
              }

              return Transform.translate(
                offset: Offset(0, dy),
                child: Transform(
                  alignment: Alignment.bottomCenter,
                  transform: Matrix4.identity()
                    ..rotateZ(rot)
                    ..scale(sx, sy),
                  child: child,
                ),
              );
            },
          ),
        );
      },
    );
  }
}
