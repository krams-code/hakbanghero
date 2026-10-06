import 'package:flutter/material.dart';
import '../constants/asset_paths.dart';
import '../models/body_composition.dart';
import '../models/character_profile.dart';
import '../models/outfit_catalog.dart';
import '../state/evolution_state.dart';
import 'avatar_layer_stack.dart';
import 'hero_sprite.dart' show kDefaultClothes;

/// Data-driven avatar. Feed it plain strings from your state / Firestore.
/// Layers (bottom -> top): body, expression, hair, outfit.
class AvatarPreview extends StatelessWidget {
  /// 'normal' | 'obese' | 'overweight' | 'underweight' (alias: 'skinny')
  final String bodySize;

  /// 'neutral'
  final String expression;

  /// 'warrior_spiky' | 'classic_pompadour' | 'wavy_mane' | 'long_flowing' | 'short_crop'
  final String hairStyle;

  /// 'outfit_01_default_starter_set' (or the legacy 'outfit_01'), a full
  /// asset key, or '' for no outfit.
  final String activeGear;

  final String? skinTone;
  final String? hairColor;
  final FilterQuality filterQuality;

  /// uid of the player this avatar shows. When it is the signed-in hero, the
  /// body follows [EvolutionState.composition], so a check-in swaps the
  /// sprite in the same frame, with no wait for Firestore. Leave null (or
  /// pass another player's uid) and [bodySize] is used as-is.
  final String? ownerUid;

  /// 'male' | 'female' (null = male, e.g. accounts created before gender was
  /// collected). Chooses the body sheet:
  ///   female -> assets/images/character/female/body_<tier>.png
  ///   male   -> assets/images/character/body_<tier>.png
  /// Face / hair / outfit are re-fitted automatically for the female sheet.
  final String? gender;

  const AvatarPreview({
    super.key,
    required this.bodySize,
    required this.expression,
    required this.hairStyle,
    required this.activeGear,
    this.skinTone,
    this.hairColor,
    this.filterQuality = FilterQuality.none,
    this.ownerUid,
    this.gender,
  });

  /// Build straight from a Firestore user document map (null-safe).
  /// Pass [ownerUid] so the signed-in hero's avatar tracks live evolution.
  factory AvatarPreview.fromData(
    Map<String, dynamic>? data, {
    Key? key,
    FilterQuality filterQuality = FilterQuality.none,
    String? ownerUid,
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
      ownerUid: ownerUid,
      gender: p.gender,
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
    final owner = ownerUid;
    if (owner == null) return _stack(_tier(bodySize));

    // The signed-in hero: follow the global form (instant, pre-cached PNGs).
    return ValueListenableBuilder<BodyCompositionState>(
      valueListenable: EvolutionState.instance.composition,
      builder: (_, form, __) => _stack(
        EvolutionState.instance.isOwner(owner) ? form.tier : _tier(bodySize),
      ),
    );
  }

  /// Body type + outfit id -> the clothing PNG made for exactly that body.
  ///
  ///   female / 'obese'  / starter set -> assets/images/character/female/clothes/starter_set_obese.png
  ///   female / 'normal' / starter set -> assets/images/character/female/clothes/starter_set_normal.png
  ///
  /// Uses this widget's [gender]. Returns '' when there is no outfit.
  String getClothesPath(String bodyType, String outfitId) =>
      clothesAssetFor(bodyType, outfitId, gender: gender);

  Widget _stack(BodyTier tier) {
    // [tier] is already the live body (it follows EvolutionState), so when the
    // body evolves the matching clothes file is swapped in the same frame.
    final gear = getClothesPath(tier.id, activeGear);

    return AvatarLayerStack(
      // gender + body-mass state -> sprite file
      bodyPath: bodyAssetFor(tier, gender),
      facePath: FaceExpressionExt.fromId(expression).assetPath,
      hairPath: HairStyleExt.fromId(hairStyle).assetPath,
      gearPaths: [if (gear.isNotEmpty) gear],
      skinTone: skinTone,
      hairColor: hairColor,
      filterQuality: filterQuality,
    );
  }
}
