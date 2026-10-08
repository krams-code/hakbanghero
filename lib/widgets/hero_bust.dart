import 'package:flutter/material.dart';
import 'block_ui.dart';
import 'hero_sprite.dart';

/// Framed face-crop of a player's hero (same trick as the leaderboard thumb).
/// [data] is the player's Firestore user doc.
class HeroBust extends StatelessWidget {
  final Map<String, dynamic>? data;
  final double size;
  final Color bg;
  const HeroBust({
    super.key,
    required this.data,
    this.size = 56,
    this.bg = const Color(0xFF8FD0FF),
  });

  @override
  Widget build(BuildContext context) {
    return Block(
      color: bg,
      edge: Colors.black,
      depth: 3,
      radius: 12,
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: SizedBox(
          width: size,
          height: size,
          child: data == null
              ? const SizedBox.shrink()
              : ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.topCenter,
                    minWidth: 0,
                    maxWidth: double.infinity,
                    minHeight: 0,
                    maxHeight: double.infinity,
                    child: Transform.translate(
                      offset: Offset(0, size * 0.2),
                      child: HeroSprite.fromData(data, height: size * 2.4),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
