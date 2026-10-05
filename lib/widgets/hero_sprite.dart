import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../constants/asset_paths.dart';
import '../models/character_profile.dart';
import '../theme/character_assets.dart';
import 'avatar_layer_stack.dart';

/// Native canvas size shared by EVERY layer (body, face, clothes, hair).
const double kSpriteW = kSpriteWidth;
const double kSpriteH = kSpriteHeight;

/// Clothing catalog: id -> 286x512 transparent PNG.
const Map<String, String> kClothingCatalog = {
  'outfit_01': '$kClothesDir/outfit_01.png',
};
const List<String> kDefaultClothes = ['outfit_01'];

/// Reusable character sprite. Pass data in, pick a display height.
/// Scales the whole 286x512 stack as one unit (uniform aspect), so layers
/// stay aligned at any size, e.g. height 102 -> a 57x102 leaderboard thumb.
///
/// Layer order (bottom -> top): body, face, hair, outfit, then overlays.
class HeroSprite extends StatelessWidget {
  final BodyTier bodyType;
  final String skinTone;
  final HairStyle hairStyle;
  final String hairColor;
  final FaceExpression face;
  final List<String> equippedClothes;

  /// Optional extra full-canvas layers drawn above the outfit (SVG gear).
  final List<Widget> gearLayers;

  /// Optional full-canvas layer drawn on top (helmets).
  final Widget? helmLayer;

  final double height;

  const HeroSprite({
    super.key,
    required this.bodyType,
    required this.skinTone,
    required this.hairStyle,
    required this.hairColor,
    this.face = FaceExpression.neutral,
    this.equippedClothes = kDefaultClothes,
    this.gearLayers = const [],
    this.helmLayer,
    this.height = 220,
  });

  factory HeroSprite.fromProfile(
    CharacterProfile p, {
    Key? key,
    List<String> equippedClothes = kDefaultClothes,
    List<Widget> gearLayers = const [],
    Widget? helmLayer,
    double height = 220,
  }) =>
      HeroSprite(
        key: key,
        bodyType: p.bodyTier,
        skinTone: p.skinTone,
        hairStyle: p.hairStyle,
        hairColor: p.hairColor,
        face: p.faceExpression,
        equippedClothes: equippedClothes,
        gearLayers: gearLayers,
        helmLayer: helmLayer,
        height: height,
      );

  /// Build straight from a Firestore user/leaderboard map (null-safe).
  factory HeroSprite.fromData(
    Map<String, dynamic>? data, {
    Key? key,
    double height = 220,
  }) {
    final d = data ?? const <String, dynamic>{};
    final p = CharacterProfile.fromFirestore(d);
    final storedTier = d['body_tier'] as String?;
    final tier = (p.heightCm == null || p.weightKg == null) && storedTier != null
        ? BodyTierExt.fromId(storedTier)
        : p.bodyTier;
    final rawClothes = d['equipped_clothes'];
    return HeroSprite(
      key: key,
      bodyType: tier,
      skinTone: p.skinTone,
      hairStyle: p.hairStyle,
      hairColor: p.hairColor,
      face: p.faceExpression,
      equippedClothes: rawClothes is List
          ? rawClothes.whereType<String>().toList()
          : kDefaultClothes,
      height: height,
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = height * kSpriteW / kSpriteH;
    final scale = height / kSpriteH;

    // Pixel-art rule: enlarging -> nearest-neighbour (crisp blocks).
    // Shrinking a lot (tiny thumbnails) -> filtered, or pixels get dropped.
    final quality = scale >= 0.5 ? FilterQuality.none : FilterQuality.medium;

    return RepaintBoundary(
      child: SizedBox(
        width: width,
        height: height,
        child: FittedBox(
          fit: BoxFit.contain,
          clipBehavior: Clip.none, // tall hair may rise above the canvas
          child: SizedBox(
            width: kSpriteW,
            height: kSpriteH,
            child: AvatarLayerStack(
              bodyPath: '$kCharacterDir/${bodyType.assetName}',
              facePath: face.assetPath,
              hairPath: hairStyle.assetPath,
              gearPaths: [
                for (final id in equippedClothes)
                  if (kClothingCatalog[id] != null) kClothingCatalog[id]!,
              ],
              overlays: [...gearLayers, if (helmLayer != null) helmLayer!],
              skinTone: skinTone,
              hairColor: hairColor,
              filterQuality: quality,
            ),
          ),
        ),
      ),
    );
  }
}

/// Drop-in replacement for the old CharacterAvatarWidget, so existing
/// calls (equipment screen etc.) keep working. Height drives the size.
class CharacterAvatarWidget extends StatelessWidget {
  final CharacterProfile profile;
  final Map<String, Map<String, dynamic>?>? equippedBySlot;
  final double width; // kept for compatibility, ignored (aspect is fixed)
  final double height;
  final bool showOutfit;

  const CharacterAvatarWidget({
    super.key,
    required this.profile,
    this.equippedBySlot,
    this.width = 140,
    this.height = 220,
    this.showOutfit = true,
  });

  static const List<String> _slotZOrder = [
    'boots', 'chest', 'gloves', 'ring', 'amulet', 'weapon', 'offhand',
  ];

  Widget? _svg(Map<String, dynamic>? item) {
    if (item == null) return null;
    final svg = CharacterAssets.gearSvg(item['name'] as String);
    if (svg == null) return null;
    return SvgPicture.string(svg, fit: BoxFit.contain);
  }

  @override
  Widget build(BuildContext context) {
    final gear = <Widget>[];
    Widget? helm;
    if (equippedBySlot != null) {
      for (final slot in _slotZOrder) {
        final w = _svg(equippedBySlot![slot]);
        if (w != null) gear.add(w);
      }
      helm = _svg(equippedBySlot!['helm']);
    }
    return HeroSprite.fromProfile(
      profile,
      equippedClothes: showOutfit ? kDefaultClothes : const [],
      gearLayers: gear,
      helmLayer: helm,
      height: height,
    );
  }
}