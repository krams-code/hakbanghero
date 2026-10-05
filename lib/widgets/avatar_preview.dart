import 'package:flutter/material.dart';
import '../constants/asset_paths.dart';
import '../models/character_profile.dart';
import 'avatar_layer_stack.dart';
import 'hero_sprite.dart' show kClothingCatalog, kDefaultClothes;

/// Data-driven avatar. Feed it plain strings from your state / Firestore.
/// Layers (bottom -> top): body, expression, hair, outfit.
class AvatarPreview extends StatelessWidget {
  /// 'normal' | 'obese' | 'overweight' | 'underweight' (alias: 'skinny')
  final String bodySize;

  /// 'neutral'
  final String expression;

  /// 'warrior_spiky' | 'classic_pompadour' | 'wavy_mane' | 'long_flowing' | 'short_crop'
  final String hairStyle;

  /// 'outfit_01', a full asset key, or '' for no outfit.
  final String activeGear;

  final String? skinTone;
  final String? hairColor;
  final FilterQuality filterQuality;

  const AvatarPreview({
    super.key,
    required this.bodySize,
    required this.expression,
    required this.hairStyle,
    required this.activeGear,
    this.skinTone,
    this.hairColor,
    this.filterQuality = FilterQuality.none,
  });

  /// Build straight from a Firestore user document map (null-safe).
  factory AvatarPreview.fromData(
    Map<String, dynamic>? data, {
    Key? key,
    FilterQuality filterQuality = FilterQuality.none,
  }) {
    final d = data ?? const <String, dynamic>{};
    final p = CharacterProfile.fromFirestore(d);
    final stored = d['body_tier'] as String?;
    final tier = (p.heightCm == null || p.weightKg == null) && stored != null
        ? BodyTierExt.fromId(stored)
        : p.bodyTier;
    final raw = d['equipped_clothes'];
    final ids = raw is List ? raw.whereType<String>().toList() : kDefaultClothes;
    return AvatarPreview(
      key: key,
      bodySize: tier.id,
      expression: p.faceExpression.id,
      hairStyle: p.hairStyle.id,
      activeGear: ids.isEmpty ? '' : ids.first,
      skinTone: p.skinTone,
      hairColor: p.hairColor,
      filterQuality: filterQuality,
    );
  }

  static BodyTier _tier(String s) {
    switch (s.toLowerCase()) {
      case 'skinny':
      case 'underweight':
        return BodyTier.underweight;
      case 'overweight':
        return BodyTier.overweight;
      case 'obese':
        return BodyTier.obese;
      default:
        return BodyTier.normal;
    }
  }

  @override
  Widget build(BuildContext context) {
    final gear = kClothingCatalog[activeGear] ??
        (activeGear.startsWith('assets/') ? activeGear : null);

    return AvatarLayerStack(
      bodyPath: '$kCharacterDir/${_tier(bodySize).assetName}',
      facePath: FaceExpressionExt.fromId(expression).assetPath,
      hairPath: HairStyleExt.fromId(hairStyle).assetPath,
      gearPaths: [if (gear != null) gear],
      skinTone: skinTone,
      hairColor: hairColor,
      filterQuality: filterQuality,
    );
  }
}