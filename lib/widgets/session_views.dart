import 'package:flutter/material.dart';

import 'package:hakbanghero/models/activity_model.dart';
import 'package:hakbanghero/models/daily_quest_definitions.dart';

import '../challenges/challenge_engine.dart';
import '../models/ghost_run.dart';
import 'block_ui.dart';
import 'challenge_overlay.dart';
import 'live_tracker_animation.dart';
import 'neon_alert_border.dart';
import 'session_avatar.dart';
import 'tutorial_keys.dart';

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

  /// Sudden-challenge engine. When it has a live challenge the sprite goes to
  /// max velocity, a neon-red electric border frames the dashboard and the
  /// pop-up / countdown overlay is drawn on top. Null = no challenges.
  final ChallengeEngine? challenge;

  /// Ghost race (your own best run). Null = not racing.
  final GhostRun? ghost;
  final int elapsedSeconds;

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
    this.challenge,
    this.ghost,
    this.elapsedSeconds = 0,
  });

  @override
  Widget build(BuildContext context) {
    final c = challenge;
    if (c == null) return _content(context, false);

    return ListenableBuilder(
      listenable: c,
      builder: (ctx, _) => Stack(
        children: [
          Positioned.fill(child: _content(ctx, c.isActive)),
          Positioned.fill(child: NeonAlertBorder(active: c.isActive)),
          Positioned.fill(child: ChallengeOverlay(engine: c)),
        ],
      ),
    );
  }

  Widget _content(BuildContext context, bool boost) {
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
            if (ghost != null) ...[
              const SizedBox(height: 10),
              _ghostBanner(ghost!),
            ],
            const SizedBox(height: 14),

            // Animated game stage fills the (formerly empty) middle
            Expanded(
              // Sprite-loop runner + parallax scenery. Speed 0 -> idle; the
              // stance and frame rate follow the real GPS speed.
              child: LiveTrackerAnimation(
                currentUserSpeedKmh: moving ? speedKmh : 0,
                paused: paused,
                boost: boost,
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

  /// You vs your ghost: a two-lane track over the ghost's full distance.
  Widget _ghostBanner(GhostRun g) {
    final ghostKm = g.distanceAt(elapsedSeconds);
    final gap = distanceKm - ghostKm; // + = you lead
    final ahead = gap >= 0;
    final lead = (gap.abs() * 1000).round();
    final span = g.distanceKm <= 0 ? 1.0 : g.distanceKm;
    double f(double km) => (km / span).clamp(0.0, 1.0).toDouble();

    Widget lane(Color c, String icon, double frac) => SizedBox(
          height: 18,
          child: LayoutBuilder(builder: (context, box) {
            final x = (box.maxWidth - 18) * frac;
            return Stack(
              children: [
                Positioned.fill(
                  child: Center(
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: Colors.black38,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: x,
                  top: 0,
                  child: Text(icon, style: const TextStyle(fontSize: 15)),
                ),
              ],
            );
          }),
        );

    return Block(
      color: ahead ? const Color(0xFF1E6B45) : const Color(0xFF7A2A2A),
      edge: ahead ? const Color(0xFF0B2E1D) : const Color(0xFF3A1010),
      depth: 4,
      radius: 12,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Column(
        children: [
          Row(
            children: [
              const BlockText('\u{1F47B} GHOST', size: 11, stroke: 3),
              const Spacer(),
              BlockText(
                lead < 5
                    ? 'NECK AND NECK'
                    : ahead
                        ? '$lead m AHEAD'
                        : '$lead m BEHIND',
                size: 12,
                stroke: 3.5,
                color: ahead ? Rb.neon : const Color(0xFFFFB3B3),
              ),
            ],
          ),
          const SizedBox(height: 2),
          lane(Rb.neon, '\u{1F3C3}', f(distanceKm)),
          lane(const Color(0xFFB79CFF), '\u{1F47B}', f(ghostKm)),
        ],
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

  /// Sudden challenges attempted during the run (won and lost).
  final List<ChallengeRecord> challenges;

  /// Result of the ghost race, if one was run.
  final GhostResult? ghostResult;

  /// Gem rewards of friend duels this run just won.
  final List<String> duelRewards;

  const SessionSummarySheet({
    super.key,
    required this.session,
    required this.isSaving,
    required this.completedQuests,
    required this.onDone,
    this.challenges = const [],
    this.ghostResult,
    this.duelRewards = const [],
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
                if (ghostResult != null) ...[
                  const SizedBox(height: 10),
                  _ghostResultRow(ghostResult!),
                ],
                for (final g in duelRewards) ...[
                  const SizedBox(height: 10),
                  Block(
                    color: const Color(0xFF7A3B0A),
                    edge: const Color(0xFF3A1B00),
                    depth: 4,
                    radius: 10,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    child: BlockText('\u2694\uFE0F DUEL WON! +\u{1F48E}$g',
                        size: 12, stroke: 3, align: TextAlign.center),
                  ),
                ],
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

                // Rewards area — spotlighted by the Phase 2 tutorial (step 4)
                KeyedSubtree(
                  key: TutorialKeys.rewards,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
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

                if (challenges.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _challengePanel(),
                ],

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

                    ],
                  ),
                ),

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

  /// Sudden-challenge results + the loot chest drop.
  Widget _challengePanel() {
    final chests = challenges.where((c) => c.lootChest).length;
    final xp = challenges.fold<int>(0, (s, c) => s + c.bonusXp);
    final gems = challenges.fold<int>(0, (s, c) => s + c.bonusGems);

    return Block(
      color: const Color(0xFF2A0A0E),
      edge: const Color(0xFFFF2B4A),
      depth: 5,
      radius: 12,
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BlockText('⚡ SUDDEN QUESTS',
              size: 13, stroke: 3.5, color: _yellow),
          const SizedBox(height: 8),
          for (final c in challenges)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                Expanded(
                  child: BlockText(
                    '${c.success ? '🏆' : '💥'} '
                    '${c.kind == ChallengeKind.sprintBlitz ? 'SPRINT BLITZ' : 'PACE KEEPER'}',
                    size: 12,
                    stroke: 3,
                    color: c.success ? Rb.neon : const Color(0xFFB8BDC4),
                  ),
                ),
                BlockText(
                  !c.success
                      ? 'FAILED'
                      : c.lootChest
                          ? '+📦'
                          : '+${c.bonusXp} EXP  +${c.bonusGems} 💎',
                  size: 12,
                  stroke: 3,
                ),
              ]),
            ),
          if (chests > 0) ...[
            const SizedBox(height: 4),
            Block(
              color: Rb.gold,
              edge: Rb.goldEdge,
              depth: 5,
              radius: 12,
              gloss: true,
              padding:
                  const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: BlockText(
                          chests > 1
                              ? '📦 LOOT CHEST DETECTED! x$chests'
                              : '📦 LOOT CHEST DETECTED!',
                          size: 18,
                          stroke: 4.5),
                    ),
                    const SizedBox(height: 2),
                    const BlockText('Rare drop for hitting the target pace!',
                        size: 10, stroke: 2.5, align: TextAlign.center),
                  ],
                ),
              ),
            ),
          ],
          if (xp > 0 || gems > 0) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: BlockText('BONUS +$xp EXP  +$gems 💎 MANA CRYSTALS',
                  size: 11, stroke: 3, color: Rb.neon),
            ),
          ],
        ],
      ),
    );
  }

  Widget _ghostResultRow(GhostResult r) {
    final secs = r.paceDelta.abs().round();
    final text = r.won
        ? '\u{1F47B} GHOST BEATEN! $secs s/km faster  +${GhostResult.winGems} \u{1F48E}'
        : '\u{1F47B} Ghost won this time \u2014 $secs s/km to find. Go again!';
    return Block(
      color: r.won ? const Color(0xFF1E6B45) : const Color(0xFF5B3A9E),
      edge: r.won ? const Color(0xFF0B2E1D) : const Color(0xFF2A1A52),
      depth: 4,
      radius: 10,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: BlockText(text, size: 11, stroke: 3, align: TextAlign.center),
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
