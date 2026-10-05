import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
const LayerFit kOutfitFit =
    LayerFit(scale: 0.80, pivotX: 142.5, pivotY: 68, targetX: 142.5, targetY: 116);

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
  final LayerFit hairFit;
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
    this.hairFit = kHairFit,
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

    return AspectRatio(
      aspectRatio: kLayerAspect,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          layer(bodyPath,
              tint: _tint(skinTone),
              fallback: const Center(
                  child: Icon(Icons.person_outline, color: Colors.white24, size: 48))),
          layer(facePath, fit: faceFit),
          layer(hairPath, tint: _tint(hairColor), gray: true, fit: hairFit),
          for (final g in gearPaths) layer(g, fit: gearFit),
          for (final o in overlays) Positioned.fill(child: o),
        ],
      ),
    );
  }
}