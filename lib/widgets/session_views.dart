import 'package:flutter/material.dart';

import 'package:hakbanghero/models/activity_model.dart';
import 'package:hakbanghero/models/daily_quest_definitions.dart';

import 'block_ui.dart';
import 'game_stage.dart';
import 'session_avatar.dart';

const _yellow = Color(0xFFFFD21F);
const _yellowEdge = Color(0xFF8A6D00);

(Color, Color) _typeColors(ActivityType t) {
  switch (t) {
    case ActivityType.walk:
      return (const Color(0xFF7EE08A), const Color(0xFF2F7A3B));
    case ActivityType.jog:
      return (const Color(0xFF2EC4FF), const Color(0xFF0A6C99));
    case ActivityType.run:
      return (Rb.orange, Rb.orangeEdge);
  }
}

// ═════════════════════════════════════════════════════════════════════════
// SCREEN 2 — LIVE ACTIVE TRACKER
// ═════════════════════════════════════════════════════════════════════════
class TrackingView extends StatelessWidget {
  final ActivityType type;
  final String time;
  final double speedKmh;
  final bool moving;
  final bool paused;
  final double distanceKm;
  final String pace;
  final double maxSpeedKmh;
  final VoidCallback onPause;
  final VoidCallback onFinish;

  const TrackingView({
    super.key,
    required this.type,
    required this.time,
    required this.speedKmh,
    required this.moving,
    required this.paused,
    required this.distanceKm,
    required this.pace,
    required this.maxSpeedKmh,
    required this.onPause,
    required this.onFinish,
  });

  @override
  Widget build(BuildContext context) {
    final (tc, te) = _typeColors(type);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          children: [
            // Activity type + elapsed time
            Row(
              children: [
                Block(
                  color: tc,
                  edge: te,
                  depth: 4,
                  radius: 12,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: BlockText('${type.emoji} ${type.label.toUpperCase()}',
                      size: 13, stroke: 3.5),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Block(
                    color: Rb.panel,
                    edge: Rb.panelEdge,
                    depth: 4,
                    radius: 12,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        const BlockText('⏱', size: 16, stroke: 2),
                        const SizedBox(width: 8),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: BlockText(time, size: 30, stroke: 5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Animated game stage fills the (formerly empty) middle
            Expanded(
              child: GameStage(
                moving: moving,
                speedKmh: speedKmh,
                paused: paused,
              ),
            ),
            const SizedBox(height: 14),

            // Dashboard blocks
            Row(
              children: [
                _stat('DISTANCE', distanceKm.toStringAsFixed(2), 'km',
                    Rb.green, Rb.greenEdge),
                _stat('AVG PACE', pace, '/km', _yellow, _yellowEdge,
                    dark: true),
                _stat('MAX SPEED', maxSpeedKmh.toStringAsFixed(1), 'km/h',
                    Rb.orange, Rb.orangeEdge),
              ],
            ),
            const SizedBox(height: 16),

            // Action footer
            Row(
              children: [
                Expanded(
                  child: PressBlock(
                    color: _yellow,
                    edge: _yellowEdge,
                    depth: 8,
                    radius: 16,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    onTap: onPause,
                    child: Column(
                      children: [
                        Text(paused ? '▶' : '⏸',
                            style: const TextStyle(fontSize: 24)),
                        BlockText(paused ? 'RESUME' : 'PAUSE',
                            size: 12, stroke: 3.5, color: Colors.black),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  flex: 2,
                  child: PressBlock(
                    color: Rb.red,
                    edge: Rb.redEdge,
                    depth: 8,
                    radius: 16,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    onTap: onFinish,
                    child: const Column(
                      children: [
                        Text('🏁', style: TextStyle(fontSize: 24)),
                        BlockText('FINISH', size: 16, stroke: 4),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value, String unit, Color c, Color e,
      {bool dark = false}) {
    final fg = dark ? Colors.black : Colors.white;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Block(
          color: c,
          edge: e,
          depth: 6,
          radius: 14,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: Column(
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: BlockText(label, size: 10, stroke: 3, color: fg),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: BlockText(value, size: 28, stroke: 5, color: fg),
              ),
              BlockText(unit, size: 10, stroke: 2.5, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Finish confirmation
// ═════════════════════════════════════════════════════════════════════════
Future<void> showFinishDialog(
  BuildContext context, {
  required double distanceKm,
  required String time,
  required VoidCallback onFinish,
}) {
  return showDialog(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Block(
        color: const Color(0xFF9A9EA3),
        edge: Colors.black,
        depth: 8,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const FittedBox(
              fit: BoxFit.scaleDown,
              child: BlockText('🏁 FINISH SESSION?', size: 22, stroke: 5),
            ),
            const SizedBox(height: 10),
            Block(
              color: Rb.panel,
              edge: Rb.panelEdge,
              depth: 4,
              radius: 12,
              padding: const EdgeInsets.all(10),
              child: BlockText(
                'You covered ${distanceKm.toStringAsFixed(2)} km in $time.\nSave and end?',
                size: 13,
                stroke: 3,
                align: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: PressBlock(
                    color: Rb.blue,
                    edge: Rb.blueEdge,
                    depth: 6,
                    radius: 12,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    onTap: () => Navigator.pop(ctx),
                    child: const Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: BlockText('KEEP GOING', size: 13, stroke: 3.5),
                      ),
                    ),
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
                    onTap: () {
                      Navigator.pop(ctx);
                      onFinish();
                    },
                    child: const Center(
                      child: BlockText('FINISH', size: 13, stroke: 3.5),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

// ═════════════════════════════════════════════════════════════════════════
// SCREEN 3 — SESSION COMPLETE
// ═════════════════════════════════════════════════════════════════════════
class SessionSummarySheet extends StatelessWidget {
  final ActivitySession session;
  final bool isSaving;
  final List<DailyQuest> completedQuests;
  final VoidCallback onDone;

  const SessionSummarySheet({
    super.key,
    required this.session,
    required this.isSaving,
    required this.completedQuests,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final totalCrystals =
        completedQuests.fold<int>(0, (s, q) => s + q.crystalReward);
    final (tc, te) = _typeColors(session.type);

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
                const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: BlockText('🏆 SESSION COMPLETE!',
                      size: 24, stroke: 5, color: _yellow),
                ),
                const SizedBox(height: 12),

                // Victory stage — full avatar, hop + celebration
                Block(
                  color: const Color(0xFF8FD3FF),
                  edge: Rb.blueEdge,
                  depth: 6,
                  radius: 16,
                  padding: EdgeInsets.zero,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(13),
                    child: SizedBox(
                      width: 140,
                      height: 140,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned(
                              left: 8,
                              top: 8,
                              child: Text('✨', style: TextStyle(fontSize: 20))),
                          Positioned(
                              right: 8,
                              top: 14,
                              child: Text('🎉', style: TextStyle(fontSize: 20))),
                          Positioned(
                            bottom: 6,
                            child: const SessionAvatar(
                              height: 118,
                              stance: AvatarStance.victory,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                Block(
                  color: tc,
                  edge: te,
                  depth: 4,
                  radius: 10,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  child: BlockText(
                      '${session.type.emoji} ${session.type.label.toUpperCase()} • ${session.formattedDuration}',
                      size: 12,
                      stroke: 3),
                ),
                const SizedBox(height: 12),

                Row(children: [
                  _cell('DISTANCE',
                      '${session.distanceKm.toStringAsFixed(2)} km'),
                  _cell('AVG PACE', session.formattedPace),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  _cell('MAX SPEED',
                      '${session.maxSpeedKmh.toStringAsFixed(1)} km/h'),
                  _cell('AVG SPEED',
                      '${session.avgSpeedKmh.toStringAsFixed(1)} km/h'),
                ]),
                const SizedBox(height: 12),

                // Rewards — glossy gold inventory banner
                Block(
                  color: Rb.gold,
                  edge: Rb.goldEdge,
                  depth: 6,
                  radius: 14,
                  gloss: true,
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: BlockText('⭐ +${session.xpEarned} XP',
                              size: 17, stroke: 4.5),
                        ),
                      ),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: BlockText('🪙 +${session.coinsEarned} COINS',
                              size: 17, stroke: 4.5),
                        ),
                      ),
                    ],
                  ),
                ),

                if (completedQuests.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Block(
                    color: Rb.panel,
                    edge: Rb.panelEdge,
                    depth: 5,
                    radius: 12,
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        BlockText(
                          '💎 QUEST${completedQuests.length > 1 ? 'S' : ''} COMPLETED!',
                          size: 13,
                          stroke: 3.5,
                          color: Rb.neon,
                        ),
                        const SizedBox(height: 8),
                        for (final q in completedQuests)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(children: [
                              Icon(q.icon, color: q.color, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: BlockText(q.title,
                                    size: 12, stroke: 3, color: q.color),
                              ),
                              BlockText('+${q.crystalReward} 💎',
                                  size: 12, stroke: 3),
                            ]),
                          ),
                        if (completedQuests.length > 1)
                          Align(
                            alignment: Alignment.centerRight,
                            child: BlockText(
                                'TOTAL +$totalCrystals 💎 MANA CRYSTALS',
                                size: 12,
                                stroke: 3,
                                color: Rb.neon),
                          ),
                      ],
                    ),
                  ),
                ],

                if (session.userPick != session.type) ...[
                  const SizedBox(height: 12),
                  Block(
                    color: Rb.orange,
                    edge: Rb.orangeEdge,
                    depth: 4,
                    radius: 10,
                    padding: const EdgeInsets.all(8),
                    child: BlockText(
                      '⚡ You picked ${session.userPick.label} but GPS confirmed ${session.type.label}!',
                      size: 11,
                      stroke: 3,
                      align: TextAlign.center,
                    ),
                  ),
                ],

                const SizedBox(height: 16),
                PressBlock(
                  color: Rb.neon,
                  edge: Rb.greenEdge,
                  depth: 10,
                  radius: 18,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  onTap: isSaving ? null : onDone,
                  child: SizedBox(
                    width: double.infinity,
                    child: Center(
                      child: isSaving
                          ? const SizedBox(
                              width: 26,
                              height: 26,
                              child: CircularProgressIndicator(
                                  strokeWidth: 4, color: Colors.black),
                            )
                          : const BlockText('DONE',
                              size: 24, stroke: 5, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cell(String label, String value) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Block(
            color: Rb.panel,
            edge: Rb.panelEdge,
            depth: 4,
            radius: 10,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
            child: Column(children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: BlockText(value, size: 16, stroke: 4),
              ),
              BlockText(label,
                  size: 9, stroke: 2.5, color: const Color(0xFFB8BDC4)),
            ]),
          ),
        ),
      );
}
