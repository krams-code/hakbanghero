import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../constants/asset_paths.dart';

/// Native canvas of every character layer.
const double kSpriteWidth = 286;
const double kSpriteHeight = 512;
const double kLayerAspect = kSpriteWidth / kSpriteHeight;

// ───────────────────────── Layer fitting ─────────────────────────
//
// The face / hair / outfit art was drawn for a different head and torso than
// body_*.png, so each layer is scaled + moved onto the body at runtime.
// All numbers are in the 286x512 canvas space.
//
// How to read it:  take the point (pivotX, pivotY) of the layer's art, scale
// the layer by `scale` around it, and place that point at (targetX, targetY).
//
// Calibrated against body_normal.png (head x106-180, y27-108):
//   face   : pivot = centre of the face features, target = middle of the head
//   hair   : pivot = top of the hair's face-opening (hairline), target = forehead
//   outfit : pivot = top of the tank straps, target = base of the neck
// To tweak: raise targetY to move a layer DOWN, lower it to move UP;
// raise `scale` to make it bigger.
class LayerFit {
  final double scale, pivotX, pivotY, targetX, targetY;
  const LayerFit({
    this.scale = 1,
    this.pivotX = 0,
    this.pivotY = 0,
    this.targetX = 0,
    this.targetY = 0,
  });

  static const LayerFit none = LayerFit();
  bool get isIdentity => scale == 1 && pivotX == targetX && pivotY == targetY;
}

const LayerFit kFaceFit =
    LayerFit(scale: 0.40, pivotX: 142.5, pivotY: 178, targetX: 142.5, targetY: 72);
const LayerFit kHairFit =
    LayerFit(scale: 0.55, pivotX: 142.5, pivotY: 165, targetX: 142.5, targetY: 48);
/// Per-hairstyle seating, calibrated on the male head template
/// (head box x106-180, y27-108 — identical in all four body PNGs).
/// Each hair PNG is a different size, so each gets its own scale + anchor:
///  * the hair's TOP (or hairline for the spiky style) is pinned to the crown
///  * the fringe lands just above the eyebrows (y ~ 55-60), never over the eyes
///  * long hair falls over the shoulders without being clipped by them
const Map<String, LayerFit> kHairFitByStyle = {
  'warrior_spiky':
      LayerFit(scale: 0.46, pivotX: 141, pivotY: 163, targetX: 143, targetY: 50),
  'classic_pompadour':
      LayerFit(scale: 0.44, pivotX: 142, pivotY: 48, targetX: 143, targetY: 13),
  'wavy_mane':
      LayerFit(scale: 0.54, pivotX: 142.5, pivotY: 59, targetX: 143, targetY: 20),
  'long_flowing':
      LayerFit(scale: 0.40, pivotX: 142.5, pivotY: 51, targetX: 143, targetY: 22),
  'short_crop':
      LayerFit(scale: 0.51, pivotX: 142.5, pivotY: 73, targetX: 143, targetY: 20),
};

/// Picks the calibrated fit from the hair asset's file name.
LayerFit hairFitFor(String hairPath) {
  for (final e in kHairFitByStyle.entries) {
    if (hairPath.contains(e.key)) return e.value;
  }
  return kHairFit;
}

const LayerFit kOutfitFit =
    LayerFit(scale: 0.80, pivotX: 142.5, pivotY: 68, targetX: 142.5, targetY: 116);

// ───────────────────────── Female sheet calibration ─────────────────────────
//
// The female bodies (assets/images/character/female/body_*.png) have a
// SMALLER, tier-dependent head than the male template (measured head box,
// 286x512 canvas):
//     tier          head x      width   height   (male: x106-180, 75 x 73)
//     underweight   113-174       62      66
//     normal        112-175       64      64
//     overweight    110-176       67      67
//     obese         109-177       69      70
// Their shoulders are narrower too. So when the body path is in the female
// folder, the face, hair and outfit are re-scaled per tier (head-width ratio
// for hair/face, shoulder-width for the outfit) and re-anchored. The crown
// stays at y=27 for every tier. Verified by compositing all 5 hairstyles on
// all 4 bodies (no spill past the skull, fringe above the brows, long hair
// falls over the shoulders, tank covers the torso without overhang).
class BodyFits {
  final double hairScale; // multiplier on the male per-style hair scale
  final LayerFit face;
  final LayerFit outfit;
  const BodyFits({required this.hairScale, required this.face, required this.outfit});
}

const Map<String, BodyFits> kFemaleFits = {
  'underweight': BodyFits(
    hairScale: 0.83,
    face: LayerFit(scale: 0.332, pivotX: 142.5, pivotY: 178, targetX: 143, targetY: 67.5),
    outfit: LayerFit(scale: 0.60, pivotX: 142.5, pivotY: 68, targetX: 143.5, targetY: 114),
  ),
  'normal': BodyFits(
    hairScale: 0.85,
    face: LayerFit(scale: 0.340, pivotX: 142.5, pivotY: 178, targetX: 143, targetY: 66.6),
    outfit: LayerFit(scale: 0.65, pivotX: 142.5, pivotY: 68, targetX: 143.5, targetY: 113),
  ),
  'overweight': BodyFits(
    hairScale: 0.89,
    face: LayerFit(scale: 0.356, pivotX: 142.5, pivotY: 178, targetX: 143, targetY: 68.4),
    outfit: LayerFit(scale: 0.70, pivotX: 142.5, pivotY: 68, targetX: 143.5, targetY: 111),
  ),
  'obese': BodyFits(
    hairScale: 0.92,
    face: LayerFit(scale: 0.368, pivotX: 142.5, pivotY: 178, targetX: 143, targetY: 70.2),
    outfit: LayerFit(scale: 0.73, pivotX: 142.5, pivotY: 68, targetX: 143.5, targetY: 109),
  ),
};

/// Female fits for `.../female/body_<tier>.png`, or null for the male sheet.
BodyFits? bodyFitsFor(String bodyPath) {
  if (!bodyPath.contains('/female/')) return null;
  for (final e in kFemaleFits.entries) {
    if (bodyPath.contains('body_${e.key}')) return e.value;
  }
  return null;
}

/// Hair fit re-scaled for a body (head 0.5px right of the male centre line).
LayerFit _hairFitForBody(String hairPath, BodyFits? bf) {
  final base = hairFitFor(hairPath);
  if (bf == null) return base;
  return LayerFit(
    scale: base.scale * bf.hairScale,
    pivotX: base.pivotX,
    pivotY: base.pivotY,
    targetX: base.targetX + 0.5,
    targetY: base.targetY,
  );
}


const ColorFilter _grayscale = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0,      0,      0,      1, 0,
]);

/// One full-canvas pixel-art layer.
class PixelLayer extends StatelessWidget {
  final String path;                 // ready-made asset key (single `assets/` prefix)
  final ColorFilter? tint;
  final bool grayscaleFirst;         // desaturate before tinting (for coloured art)
  final FilterQuality filterQuality; // none = crisp
  final Widget? fallback;

  const PixelLayer({
    super.key,
    required this.path,
    this.tint,
    this.grayscaleFirst = false,
    this.filterQuality = FilterQuality.none,
    this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    Widget img = Image.asset(
      path,
      fit: BoxFit.fill, // layers share one canvas, so fill == exact fit
      filterQuality: filterQuality,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) {
        if (kDebugMode) debugPrint('⚠️ Asset failed to load: $path');
        return fallback ?? const SizedBox.shrink();
      },
    );
    if (tint != null) {
      if (grayscaleFirst) img = ColorFiltered(colorFilter: _grayscale, child: img);
      img = ColorFiltered(colorFilter: tint!, child: img);
    }
    return img;
  }
}

/// Core layer renderer. Stack order (bottom -> top):
///   body -> expression -> hair -> outfit/gear -> overlays
/// Layers may paint OUTSIDE the 286x512 canvas (e.g. tall hair spikes above
/// the head) — leave some room above this widget and don't clip it.
class AvatarLayerStack extends StatelessWidget {
  final String bodyPath;
  final String facePath;
  final String hairPath;
  final List<String> gearPaths;

  /// Extra full-canvas widgets drawn last (SVG gear, helmets...).
  final List<Widget> overlays;

  final String? skinTone;  // '#RRGGBB' or null = untinted
  final String? hairColor; // '#RRGGBB' or null = untinted

  final LayerFit faceFit;
  /// null = use the calibrated per-style fit (see [kHairFitByStyle]).
  final LayerFit? hairFit;
  final LayerFit gearFit;

  /// none = crisp pixels (native/enlarged or small shrink).
  final FilterQuality filterQuality;

  const AvatarLayerStack({
    super.key,
    required this.bodyPath,
    required this.facePath,
    required this.hairPath,
    this.gearPaths = const [],
    this.overlays = const [],
    this.skinTone,
    this.hairColor,
    this.faceFit = kFaceFit,
    this.hairFit,
    this.gearFit = kOutfitFit,
    this.filterQuality = FilterQuality.none,
  });

  static Color _hex(String hex) =>
      Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16));

  ColorFilter? _tint(String? hex) =>
      hex == null ? null : ColorFilter.mode(_hex(hex), BlendMode.modulate);

  /// Scale `child` by f.scale around f.pivot, then put the pivot at f.target.
  Widget _fitted(Widget child, LayerFit f) {
    if (f.isIdentity) return child;
    return LayoutBuilder(builder: (context, c) {
      final k = c.maxWidth / kSpriteWidth; // canvas px -> logical px
      final m = Matrix4.translationValues(f.targetX * k, f.targetY * k, 0) *
          Matrix4.diagonal3Values(f.scale, f.scale, 1) *
          Matrix4.translationValues(-f.pivotX * k, -f.pivotY * k, 0);
      return Transform(transform: m, child: child);
    });
  }

  /// Body-matched clothing lives in .../female/clothes/<id>_<bodyType>.png
  static bool _isBodyMatched(String path) => path.contains('/female/clothes/');

  /// Shown only while a body-matched PNG is missing from the project: the old
  /// one-size outfit, fitted to the female body, so the hero is never naked.
  Widget? _legacyOutfit(String path, BodyFits? bf) {
    if (bf == null || !path.contains('/starter_set_')) return null;
    return _fitted(
      PixelLayer(
        path: '$kClothesDir/outfit_01.png',
        filterQuality: filterQuality,
      ),
      bf.outfit,
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget layer(String path,
            {ColorFilter? tint,
            bool gray = false,
            LayerFit fit = LayerFit.none,
            Widget? fallback}) =>
        Positioned.fill(
          child: _fitted(
            PixelLayer(
              path: path,
              tint: tint,
              grayscaleFirst: gray,
              filterQuality: filterQuality,
              fallback: fallback,
            ),
            fit,
          ),
        );

    // Female sheet: auto-pick calibrated fits unless the caller overrode them.
    final bf = bodyFitsFor(bodyPath);
    final face = bf != null && identical(faceFit, kFaceFit) ? bf.face : faceFit;
    final gearF = bf != null && identical(gearFit, kOutfitFit) ? bf.outfit : gearFit;
    final hairF = hairFit ?? _hairFitForBody(hairPath, bf);

    return AspectRatio(
      aspectRatio: kLayerAspect,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          layer(bodyPath,
              tint: _tint(skinTone),
              fallback: const Center(
                  child: Icon(Icons.person_outline, color: Colors.white24, size: 48))),
          layer(facePath, fit: face),
          layer(hairPath, tint: _tint(hairColor), gray: true, fit: hairF),
          for (final g in gearPaths)
            if (_isBodyMatched(g))
              // Made for exactly this body: drawn 1:1, never scaled.
              layer(g, fit: LayerFit.none, fallback: _legacyOutfit(g, bf))
            else
              layer(g, fit: gearF),
          for (final o in overlays) Positioned.fill(child: o),
        ],
      ),
    );
  }
}
