import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../screens/auth/login_screen.dart';
import '../utils/player_stats.dart';
import 'avatar_layer_stack.dart' show kSpriteWidth, kSpriteHeight;
import 'avatar_preview.dart';
import 'block_ui.dart';

/// Global top bar shown on every tab (hidden during a run).
/// Left: chunky Profile block + username/level. Right: currency chips.
/// Tapping the Profile block opens the player sheet (stat breakdown,
/// open full profile, 🚪 LOGOUT SESSION).
class GlobalTopBar extends StatelessWidget {
  /// Called when the player taps "OPEN FULL PROFILE".
  final VoidCallback onOpenProfile;

  const GlobalTopBar({super.key, required this.onOpenProfile});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final top = MediaQuery.of(context).padding.top;

    return Container(
      padding: EdgeInsets.fromLTRB(12, top + 8, 12, 10),
      decoration: const BoxDecoration(
        color: Rb.slate,
        border: Border(bottom: BorderSide(color: Colors.black, width: 3)),
      ),
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: uid == null
            ? null
            : FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
        builder: (context, snap) {
          final d = snap.data?.data() ?? <String, dynamic>{};
          final name = (d['username'] as String?)?.trim();
          final level = LevelProgress.fromXp((d['xp'] as num?)?.toInt() ?? 0).level;
          final gems = (d['gems'] as num?)?.toInt() ?? 0;
          final coins = (d['coins'] as num?)?.toInt() ?? 0;

          return Row(
            children: [
              // ── Profile action block ──
              PressBlock(
                color: Rb.gold,
                edge: Rb.goldEdge,
                depth: 5,
                radius: 14,
                padding: const EdgeInsets.all(3),
                onTap: () => _openSheet(context, d),
                child: SizedBox(
                  width: 46,
                  height: 46,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: ColoredBox(
                      color: const Color(0xFF8FD0FF),
                      child: FittedBox(
                        fit: BoxFit.cover,
                        alignment: const Alignment(0, -0.9),
                        child: SizedBox(
                          width: kSpriteWidth,
                          height: kSpriteHeight + 44,
                          child: Stack(children: [
                            Positioned(
                              left: 0,
                              top: 44,
                              width: kSpriteWidth,
                              height: kSpriteHeight,
                              child: AvatarPreview.fromData(d,
                                  filterQuality: FilterQuality.medium),
                            ),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: BlockText(
                          (name == null || name.isEmpty) ? 'HERO' : name,
                          size: 16,
                          stroke: 4),
                    ),
                    BlockText('LV $level  ▾ PROFILE',
                        size: 10, stroke: 2.5, color: Rb.gold),
                  ],
                ),
              ),
              _chip('💎 $gems', Rb.blue, Rb.blueEdge),
              const SizedBox(width: 6),
              _chip('🪙 $coins', Rb.orange, Rb.orangeEdge),
            ],
          );
        },
      ),
    );
  }

  Widget _chip(String text, Color c, Color e) => Block(
        color: c,
        edge: e,
        depth: 3,
        radius: 10,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: BlockText(text, size: 11, stroke: 3),
      );

  void _openSheet(BuildContext context, Map<String, dynamic> d) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) => _PlayerSheet(
        data: d,
        onOpenProfile: () {
          Navigator.pop(sheetCtx);
          onOpenProfile();
        },
      ),
    );
  }
}

/// Confirm dialog -> sign out -> back to the login screen.
Future<void> confirmLogout(BuildContext context) async {
  final nav = Navigator.of(context, rootNavigator: true);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Block(
        color: const Color(0xFF9A9EA3),
        edge: Colors.black,
        depth: 8,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BlockText('🚪 LOG OUT?', size: 22, stroke: 5),
            const SizedBox(height: 8),
            const BlockText('Your progress is saved.',
                size: 12, stroke: 3, align: TextAlign.center),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: PressBlock(
                  color: Rb.blue,
                  edge: Rb.blueEdge,
                  depth: 6,
                  radius: 12,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  onTap: () => Navigator.pop(ctx, false),
                  child: const Center(child: BlockText('STAY', size: 14, stroke: 3.5)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PressBlock(
                  color: Rb.red,
                  edge: Rb.redEdge,
                  depth: 6,
                  radius: 12,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  onTap: () => Navigator.pop(ctx, true),
                  child: const Center(child: BlockText('LOG OUT', size: 14, stroke: 3.5)),
                ),
              ),
            ]),
          ],
        ),
      ),
    ),
  );
  if (ok != true) return;

  await FirebaseAuth.instance.signOut();
  // MainShell may have been pushed with pushAndRemoveUntil (after sign-up /
  // character creation), so the auth gate isn't guaranteed to be underneath.
  nav.pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const LoginScreen()),
    (_) => false,
  );
}

class _PlayerSheet extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onOpenProfile;

  const _PlayerSheet({required this.data, required this.onOpenProfile});

  @override
  Widget build(BuildContext context) {
    final name = (data['username'] as String?)?.trim();
    final level = LevelProgress.fromXp((data['xp'] as num?)?.toInt() ?? 0).level;
    final xp = (data['xp'] as num?)?.toInt() ?? 0;
    final km = (data['total_km'] as num?)?.toDouble() ?? 0;
    final sessions = (data['total_sessions'] as num?)?.toInt() ?? 0;
    final coins = (data['coins'] as num?)?.toInt() ?? 0;
    final gems = (data['gems'] as num?)?.toInt() ?? 0;

    Widget stat(String emoji, String value, String label, Color c, Color e) =>
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Block(
              color: c,
              edge: e,
              depth: 4,
              radius: 12,
              padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
              child: Column(children: [
                Text(emoji, style: const TextStyle(fontSize: 18)),
                FittedBox(
                    fit: BoxFit.scaleDown,
                    child: BlockText(value, size: 16, stroke: 4)),
                FittedBox(
                    fit: BoxFit.scaleDown,
                    child: BlockText(label, size: 8, stroke: 2.5)),
              ]),
            ),
          ),
        );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: Block(
          color: const Color(0xFF9A9EA3),
          edge: Colors.black,
          depth: 8,
          radius: 22,
          padding: const EdgeInsets.all(14),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: BlockText(
                      '👤 ${(name == null || name.isEmpty) ? 'HERO' : name.toUpperCase()}',
                      size: 22,
                      stroke: 5),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  stat('⭐', '$level', 'LEVEL', Rb.gold, Rb.goldEdge),
                  stat('✨', '$xp', 'TOTAL XP', Rb.blue, Rb.blueEdge),
                  stat('📍', km.toStringAsFixed(1), 'TOTAL KM', Rb.green, Rb.greenEdge),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  stat('🎯', '$sessions', 'SESSIONS', Rb.orange, Rb.orangeEdge),
                  stat('🪙', '$coins', 'COINS', const Color(0xFFB8860B), const Color(0xFF5A4305)),
                  stat('💎', '$gems', 'CRYSTALS', const Color(0xFF2EC4FF), const Color(0xFF0A6C99)),
                ]),
                const SizedBox(height: 14),
                PressBlock(
                  color: Rb.blue,
                  edge: Rb.blueEdge,
                  depth: 7,
                  radius: 14,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  onTap: onOpenProfile,
                  child: const SizedBox(
                    width: double.infinity,
                    child: Center(
                        child: BlockText('👤 OPEN FULL PROFILE', size: 16, stroke: 4)),
                  ),
                ),
                const SizedBox(height: 12),
                PressBlock(
                  color: Rb.red,
                  edge: Rb.redEdge,
                  depth: 9,
                  radius: 16,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  onTap: () => confirmLogout(context),
                  child: const SizedBox(
                    width: double.infinity,
                    child: Center(
                        child: BlockText('🚪 LOGOUT SESSION', size: 19, stroke: 4.5)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
