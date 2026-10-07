import 'package:flutter/material.dart';

/// A crisp pixel-art icon from a local asset path.
///
///   PixelIcon('assets/images/icons/icon_run_fire.png')   // 24 x 24
///
/// Always `FilterQuality.none` so the pixels stay sharp.
class PixelIcon extends StatelessWidget {
  final String path;
  final double size;
  const PixelIcon(this.path, {super.key, this.size = 24});

  @override
  Widget build(BuildContext context) => Image.asset(
        path,
        width: size,
        height: size,
        filterQuality: FilterQuality.none,
        errorBuilder: (_, __, ___) => SizedBox(width: size, height: size),
      );
}

/// Icon + label on one line (used for tabs / badges / headers).
class IconLabel extends StatelessWidget {
  final String iconPath;
  final Widget label;
  final double iconSize;
  final double gap;
  const IconLabel({
    super.key,
    required this.iconPath,
    required this.label,
    this.iconSize = 20,
    this.gap = 6,
  });

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PixelIcon(iconPath, size: iconSize),
          SizedBox(width: gap),
          label,
        ],
      );
}
