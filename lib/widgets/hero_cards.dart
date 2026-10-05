import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_colors.dart';
import 'hero_sprite.dart';
// TODO: adjust this path to wherever your creation screen lives.
import '../screens/character/character_creation_screen.dart';

/// ───────────────────────── PROFILE SCREEN ─────────────────────────
/// Replaces the grey placeholder icon. Streams the user's doc, so the hero
/// updates by itself right after they save changes in the editor.
class ProfileHeroCard extends StatelessWidget {
  final String uid;
  final double height;
  const ProfileHeroCard({super.key, required this.uid, this.height = 200});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream:
          FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const CharacterCreationScreen(isEditMode: true),
            ),
          ),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.borderDim),
            ),
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                HeroSprite.fromData(data, height: height),
                // small "edit" hint so it's obvious the card is tappable
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: AppColors.blue,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.edit, size: 14, color: Colors.white),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// ───────────────────────── LEADERBOARD ROW ─────────────────────────
/// `data` = that player's map. It must contain the appearance fields
/// (skin_tone, hair_style, hair_color, face_expression, body_tier or
/// height_cm/weight_kg, optional equipped_clothes).
class LeaderboardPlayerRow extends StatelessWidget {
  final int rank;
  final String name;
  final String trailing; // e.g. '1,240 XP'
  final Map<String, dynamic> data;

  const LeaderboardPlayerRow({
    super.key,
    required this.rank,
    required this.name,
    required this.trailing,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderDim),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text('#$rank',
                style: const TextStyle(
                    color: AppColors.gold, fontWeight: FontWeight.w900)),
          ),
          // 57 x 102 thumbnail: same 286:512 ratio, uniformly scaled.
          HeroSprite.fromData(data, height: 102),
          const SizedBox(width: 14),
          Expanded(
            child: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppColors.textMain, fontWeight: FontWeight.bold)),
          ),
          Text(trailing, style: const TextStyle(color: AppColors.textSub)),
        ],
      ),
    );
  }
}