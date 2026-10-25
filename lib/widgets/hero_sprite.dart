import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../models/body_composition.dart';
import '../models/character_profile.dart';
import '../models/outfit_catalog.dart';
import '../state/evolution_state.dart';
import '../theme/character_assets.dart';
import '../models/hero_items.dart';
import '../models/hero_roster.dart';
import 'avatar_layer_stack.dart';
import 'hero_rig.dart' show HeroStill;

/// Native canvas size shared by EVERY layer (body, face, clothes, hair).
const double kSpriteW = kSpriteWidth;
const double kSpriteH = kSpriteHeight;

/// Male clothing catalog: id -> 286x512 transparent PNG. (Female clothes are
/// body-matched files, resolved by [clothesAssetFor].)
const Map<String, String> kClothingCatalog = kMaleClothesCatalog;
const List<String> kDefaultClothes = [kStarterOutfitId];

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

  /// uid of the player shown. When it is the signed-in hero, [bodyType]
  /// follows [EvolutionState.composition] so a check-in swaps the body
  /// instantly (e.g. in the player's own leaderboard row). Null = static.
  final String? ownerUid;

  /// 'male' | 'female' | null (= male). Picks the body sheet, see [bodyAssetFor].
  final String? gender;

  /// New block hero (users/{uid}.hero_id). When set, the hero art replaces
  /// the layered classic avatar, in the same 286:512 box.
  final String? heroId;

  /// Worn items (slot name -> item id).
  final Map<String, String> outfit;

  /// Face crop mode for the round / square thumbnails that show only the head
  /// (leaderboard, friends, duel). Call sites keep their usual crop box
  /// (height = size * 2.4, shifted down size * 0.2); only the hero art is moved
  /// and enlarged so its head fills that box like the classic head does.
  final bool bust;

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
    this.ownerUid,
    this.gender,
    this.heroId,
    this.outfit = const <String, String>{},
    this.bust = false,
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
        gender: p.gender,
      );

  /// Build straight from a Firestore user/leaderboard map (null-safe).
  factory HeroSprite.fromData(
    Map<String, dynamic>? data, {
    Key? key,
    double height = 220,
    String? ownerUid,
    bool bust = false,
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
      ownerUid: ownerUid,
      gender: p.gender,
      heroId: heroIdOf(d),
      outfit: outfitOf(d),
      bust: bust,
    );
  }

  /// Girl SPROUT art for this player (null gender = the signed-in player's).
  /// (No gender saved = the classic boy SPROUT, never the viewer's own look.)
  bool get _girl => genderKey(gender) == 'female';

  /// Hero art in the same box as the classic sprite (or its face crop).
  Widget _hero(String hero, BodyTier tier) {
    final width = height * kSpriteW / kSpriteH;
    if (!bust) {
      return SizedBox(
        width: width,
        height: height,
        child: HeroStill(heroId: hero, tier: tier, outfit: outfit, girl: _girl),
      );
    }
    // face crop: the head is ~55% of the picture width, so show the picture
    // about 2.8x the crop size and slide it up until the head sits mid-box.
    final size = height / 2.4;
    return SizedBox(
      width: width,
      height: height,
      child: OverflowBox(
        alignment: Alignment.topCenter,
        minWidth: 0,
        maxWidth: double.infinity,
        minHeight: 0,
        maxHeight: double.infinity,
        child: Transform.translate(
          offset: Offset(0, -0.62 * size),
          child: SizedBox(
            height: 2.77 * size,
            child: HeroStill(heroId: hero, tier: tier, outfit: outfit, girl: _girl),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final owner = ownerUid;
    final hero = heroId;
    if (hero != null) {
      if (owner == null) return _hero(hero, bodyType);
      return ValueListenableBuilder<BodyCompositionState>(
        valueListenable: EvolutionState.instance.composition,
        builder: (_, form, __) => _hero(
            hero, EvolutionState.instance.isOwner(owner) ? form.tier : bodyType),
      );
    }
    if (owner == null) return _sprite(bodyType);

    // The signed-in hero: follow the global form (instant, pre-cached PNGs).
    return ValueListenableBuilder<BodyCompositionState>(
      valueListenable: EvolutionState.instance.composition,
      builder: (_, form, __) =>
          _sprite(EvolutionState.instance.isOwner(owner) ? form.tier : bodyType),
    );
  }

  Widget _sprite(BodyTier tier) {
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
              bodyPath: bodyAssetFor(tier, gender),
              facePath: face.assetPath,
              hairPath: hairStyle.assetPath,
              // body type + outfit -> the PNG drawn for exactly that body
              gearPaths: [
                for (final id in equippedClothes)
                  if (clothesAssetFor(tier.id, id, gender: gender).isNotEmpty)
                    clothesAssetFor(tier.id, id, gender: gender),
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
