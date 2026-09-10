import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../models/character_profile.dart';
import '../theme/character_assets.dart';

/// Renders a layered character: body (skin/tier) + equipped gear +
/// hair + helm-on-top, in that visual stacking order.
class CharacterAvatarWidget extends StatelessWidget {
  final CharacterProfile profile;

  /// Pass your `_equipped` map directly: slot id -> item map (or null).
  /// Omit this to render just the base body + hair (e.g. in the
  /// character creation screen, before any gear exists).
  final Map<String, Map<String, dynamic>?>? equippedBySlot;

  final double width;
  final double height;

  const CharacterAvatarWidget({
    super.key,
    required this.profile,
    this.equippedBySlot,
    this.width = 140,
    this.height = 220,
  });

  // Rendering order, bottom to top. Helm is handled separately so it
  // always sits above hair.
  static const List<String> _slotZOrder = [
    'boots', 'chest', 'gloves', 'ring', 'amulet', 'weapon', 'offhand',
  ];

  @override
  Widget build(BuildContext context) {
    final bodySvg = CharacterAssets.renderBody(profile.bodyTier.id, profile.skinTone);
    final hairSvg = CharacterAssets.renderHair(profile.hairStyle.id, profile.hairColor);

    final gearLayers = <Widget>[];
    String? helmSvg;

    if (equippedBySlot != null) {
      for (final slot in _slotZOrder) {
        final item = equippedBySlot![slot];
        if (item == null) continue;
        final svg = CharacterAssets.gearSvg(item['name'] as String);
        if (svg != null) {
          gearLayers.add(
            SvgPicture.string(svg, width: width, height: height, fit: BoxFit.contain),
          );
        }
      }
      final helmItem = equippedBySlot!['helm'];
      if (helmItem != null) {
        helmSvg = CharacterAssets.gearSvg(helmItem['name'] as String);
      }
    }

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SvgPicture.string(bodySvg, width: width, height: height, fit: BoxFit.contain),
          ...gearLayers,
          SvgPicture.string(hairSvg, width: width, height: height, fit: BoxFit.contain),
          if (helmSvg != null)
            SvgPicture.string(helmSvg, width: width, height: height, fit: BoxFit.contain),
        ],
      ),
    );
  }
}