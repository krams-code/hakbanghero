import 'package:flutter/material.dart';

import 'package:hakbanghero/models/activity_model.dart';
import 'package:hakbanghero/models/daily_quest_definitions.dart';

import '../challenges/challenge_engine.dart';
import '../models/ghost_run.dart';
import '../models/run_mode.dart';
import '../services/sound.dart';
import 'block_ui.dart';
import 'challenge_overlay.dart';
import 'live_tracker_animation.dart';
import 'neon_alert_border.dart';
import 'session_avatar.dart';
import 'tutorial_keys.dart';
import 'emoji_icons.dart';
import 'lottie_fx.dart';

const _yellow = Color(0xFFFFD21F);

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
  final double distanceKm;
  final String pace;
  final double maxSpeedKmh;
  /// END SESSION: ends tracking, saves the run and opens the summary card.
  final VoidCallback onFinish;

  /// The chosen game mode (Stage rank or Endless). Null = plain run.
  final RunMode? mode;

  /// Stage clock left, "MM:SS" (null in Endless).
  final String? clockLeft;

  /// True while the stage clock is under a minute (turns the timer red).
  final bool clockLow;

  /// Sudden-challenge engine. When it has a live challenge the sprite goes to
  /// max velocity, a neon-red electric border frames the dashboard and the
  /// pop-up / countdown overlay is drawn on top. Null = no challenges.
  final ChallengeEngine? challenge;

  /// GPS state: 0 timer-only, 1 searching, 2 weak signal, 3 good.
  final int gpsStatus;

  /// Ghost race (your own best run). Null = not racing.
  final GhostRun? ghost;
  final int elapsedSeconds;

  const TrackingView({
    super.key,
    required this.type,
    required this.time,
    required this.speedKmh,
    required this.moving,
    required this.distanceKm,
    required this.pace,
    required this.maxSpeedKmh,
    required this.onFinish,
    this.mode,
    this.clockLeft,
    this.clockLow = false,
    this.challenge,
    this.gpsStatus = 3,
    this.ghost,
    this.elapsedSeconds = 0,
  });

  Widget _gpsChip() {
    final (label, c) = switch (gpsStatus) {
      0 => ('NO GPS \u2022 TIMER ONLY', const Color(0xFF6B7078)),
      1 => ('SEARCHING GPS...', const Color(0xFFD98E00)),
      2 => ('WEAK GPS SIGNAL', const Color(0xFFE5784D)),
      _ => ('GPS READY', const Color(0xFF1E8F55)),
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.black, width: 2),
        ),
        child: BlockText('\u{1F4E1} $label', size: 10, stroke: 2.5),
      ),
    );
  }

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
        // On short screens the dashboard scrolls instead of overflowing.
        child: LayoutBuilder(builder: (context, box) {
        final col = Column(
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
            if (gpsStatus != 3) ...[
              const SizedBox(height: 8),
              _gpsChip(),
            ],
            if (ghost != null) ...[
              const SizedBox(height: 10),
              _ghostBanner(ghost!),
            ],
            if (mode != null) ...[
              const SizedBox(height: 10),
              _modeStrip(mode!),
            ],
            const SizedBox(height: 14),

            // Animated game stage fills the (formerly empty) middle
            Expanded(
              // Sprite-loop runner + parallax scenery. Speed 0 -> idle; the
              // stance and frame rate follow the real GPS speed.
              child: LiveTrackerAnimation(
                currentUserSpeedKmh: moving ? speedKmh : 0,
                boost: boost,
                mapAsset: mode?.mapAsset,
              ),
            ),
            const SizedBox(height: 14),

            // Dashboard blocks
            Row(
              children: [
                _stat('DISTANCE', distanceKm.toStringAsFixed(2), 'km',
                    Rb.green, Rb.greenEdge),
                _stat('AVG PACE', pace, '/km', Rb.blue, Rb.blueEdge),
                _stat('MAX SPEED', maxSpeedKmh.toStringAsFixed(1), 'km/h',
                    Rb.orange, Rb.orangeEdge),
              ],
            ),
            const SizedBox(height: 16),

            // Action footer: ONE full-width button (there is no pause).
            // Press and HOLD so a stray tap mid-run can't end the session.
            SizedBox(
              width: double.infinity,
              child: _HoldToEndButton(onComplete: onFinish),
            ),
          ],
        );
        const minH = 560.0;
        if (box.maxHeight >= minH) return col;
        return SingleChildScrollView(
          child: SizedBox(height: minH, child: col),
        );
        }),
      ),
    );
  }

  /// Mode banner under the header: Stage = rank + map + target bar + clock,
  /// Endless = a calm "just run" strip.
  Widget _modeStrip(RunMode m) {
    if (m.isInterval) {
      final ph = RunMode.intervalAt(elapsedSeconds);
      if (ph == null) {
        return Block(
          color: m.color,
          edge: m.edge,
          depth: 4,
          radius: 12,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: const BlockText('\u26A1 INTERVALS DONE!',
              size: 14, stroke: 3.5, align: TextAlign.center),
        );
      }
      final fast = ph.fast;
      return Block(
        color: fast ? Rb.orange : Rb.blue,
        edge: fast ? Rb.orangeEdge : Rb.blueEdge,
        depth: 4,
        radius: 12,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: BlockText(
                    fast ? '\u26A1 FAST! RUN HARD' : 'EASY \u2022 WALK / JOG',
                    size: 15,
                    stroke: 4),
              ),
            ),
            BlockText('R${ph.round}/${RunMode.intervalRounds}  0:${ph.secondsLeft.toString().padLeft(2, '0')}',
                size: 13, stroke: 3.5),
          ],
        ),
      );
    }
    if (m.isEndless) {
      return Block(
        color: m.color,
        edge: m.edge,
        depth: 4,
        radius: 12,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: const Row(
          children: [
            Expanded(
              child: BlockText('\u267E\uFE0F FREE RUN', size: 13, stroke: 3.5),
            ),
            BlockText('NO LIMITS', size: 11, stroke: 3, color: Color(0xFFD7C8FF)),
          ],
        ),
      );
    }

    final target = m.targetKm ?? 1.0;
    final frac = (distanceKm / target).clamp(0.0, 1.0).toDouble();
    return Block(
      color: m.color,
      edge: m.edge,
      depth: 4,
      radius: 12,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: BlockText('${m.emoji} ${m.name} \u2022 ${m.mapName}',
                    size: 11, stroke: 3, maxLines: 1),
              ),
              BlockText('\u23F3 ${clockLeft ?? '--:--'}',
                  size: 14,
                  stroke: 3.5,
                  color: clockLow ? const Color(0xFFFFE066) : Colors.white),
            ],
          ),
          const SizedBox(height: 6),
          BlockBar(value: frac, height: 12, color: Rb.neon),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: BlockText(
                '${distanceKm.toStringAsFixed(2)} / ${target.toStringAsFixed(1)} KM',
                size: 10.5,
                stroke: 3),
          ),
        ],
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
                  child: EmojiText(icon, style: const TextStyle(fontSize: 15)),
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

  /// True when the run could not be sent (offline) and waits on the phone.
  final bool queued;

  /// Why the save failed (shown when [queued]).
  final String? saveError;

  /// Interval Run results {rounds, fast_km, best_fast_pace_s?} (else null).
  final Map<String, dynamic>? intervalStats;
  final bool intervalNewBest;
  final List<DailyQuest> completedQuests;
  final VoidCallback onDone;

  /// Sudden challenges attempted during the run (won and lost).
  final List<ChallengeRecord> challenges;

  /// Result of the ghost race, if one was run.
  final GhostResult? ghostResult;

  /// Gem rewards of friend duels this run just won.
  final List<String> duelRewards;

  /// Game mode of this run + how it ended ("STAGE CLEARED!", "TIME UP", ...).
  final RunMode? mode;
  final String? outcome;
  final bool outcomeGood;

  /// Stage record: stars earned this run (0 = not cleared) and the coins
  /// that came with it (first-clear bonus + new-star bonus).
  final int stars;
  final int stageBonusCoins;
  final bool firstClear;

  /// The next rank this clear just opened (null = none) and the shortcut to
  /// its briefing.
  final RunMode? unlockedRank;
  final VoidCallback? onNextRank;

  const SessionSummarySheet({
    super.key,
    required this.session,
    required this.isSaving,
    this.queued = false,
    this.saveError,
    this.intervalStats,
    this.intervalNewBest = false,
    required this.completedQuests,
    required this.onDone,
    this.challenges = const [],
    this.ghostResult,
    this.duelRewards = const [],
    this.mode,
    this.outcome,
    this.outcomeGood = false,
    this.stars = 0,
    this.stageBonusCoins = 0,
    this.firstClear = false,
    this.unlockedRank,
    this.onNextRank,
  });

  @override
  Widget build(BuildContext context) {
    // Confetti + stars on a cleared stage or a finished Endless run.
    final celebrate = outcomeGood ||
        (mode?.isEndless ?? true) ||
        completedQuests.isNotEmpty ||
        unlockedRank != null;
    return Stack(
      children: [
        _sheet(context),
        if (celebrate)
          const Positioned.fill(
            child: FxOnce(Fx.confetti, fit: BoxFit.cover),
          ),
      ],
    );
  }

  /// A short, honest cheer line that matches how the run went.
  String _cheer() {
    if (unlockedRank != null) return 'NEW LEVEL OPEN! KEEP IT UP!';
    if (outcome != null && !outcomeGood) return 'GOOD TRY! EVERY RUN MAKES YOU STRONGER.';
    final km = session.distanceKm;
    if (km >= 10) return 'WOW, 10 KM+! THAT IS A REAL ACHIEVEMENT!';
    if (km >= 5) return 'GREAT RUN! YOU WENT THE DISTANCE!';
    if (km >= 2) return 'NICE WORK! YOU ARE BUILDING A HABIT!';
    return 'EVERY STEP COUNTS. SEE YOU AT THE NEXT RUN!';
  }

  Widget _sheet(BuildContext context) {
    final totalCoins =
        completedQuests.fold<int>(0, (s, q) => s + q.coinReward);
    final (tc, te) = _typeColors(session.type);

    return SafeArea(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeOutBack,
        builder: (context, t, child) => Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.scale(scale: 0.88 + 0.12 * t, child: child),
        ),
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
                const SizedBox(height: 6),
                BlockText(_cheer(), size: 12, stroke: 3, align: TextAlign.center),
                const SizedBox(height: 10),

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
                              child: EmojiText('✨', style: TextStyle(fontSize: 20))),
                          Positioned(
                              right: 8,
                              top: 14,
                              child: EmojiText('🎉', style: TextStyle(fontSize: 20))),
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
                if (mode != null) ...[
                  const SizedBox(height: 10),
                  _modeRow(mode!),
                ],
                if (intervalStats != null) ...[
                  const SizedBox(height: 10),
                  _intervalRow(intervalStats!),
                ],
                if (queued) ...[
                  const SizedBox(height: 10),
                  Block(
                    color: const Color(0xFF6B7078),
                    edge: const Color(0xFF1B1D20),
                    depth: 3,
                    radius: 10,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 7),
                    child: Column(
                      children: [
                        BlockText(
                            (saveError ?? '').startsWith('timeout') ||
                                    (saveError ?? '').startsWith('unavailable')
                                ? '\u{1F4E1} NO CONNECTION: run kept on your phone.\n'
                                    'It sends by itself when you are back online.'
                                : '\u26A0\uFE0F RUN NOT SAVED YET: kept on your phone.\n'
                                    'Tap the SYNC bar on the RUN screen to retry.',
                            size: 10.5,
                            stroke: 3,
                            align: TextAlign.center),
                        if (saveError != null) ...[
                          const SizedBox(height: 4),
                          SelectableText(
                            'Reason: $saveError',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Color(0xFFFFD7CF),
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                if (unlockedRank != null) ...[
                  const SizedBox(height: 10),
                  _unlockBanner(unlockedRank!),
                ],
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
                    child: BlockText('\u2694\uFE0F DUEL WON! +\u{1FA99}$g',
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
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                  width: 34,
                                  height: 34,
                                  child: FxLoop(Fx.coinSpin)),
                              const SizedBox(width: 2),
                              BlockText('+${session.coinsEarned} COINS',
                                  size: 17, stroke: 4.5),
                            ],
                          ),
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
                          '🪙 QUEST${completedQuests.length > 1 ? 'S' : ''} COMPLETED!',
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
                              BlockText('+${q.coinReward}',
                                  size: 12, stroke: 3),
                              const SizedBox(width: 2),
                              const SizedBox(
                                  width: 24, height: 24, child: FxOnce(Fx.gemPop)),
                            ]),
                          ),
                        if (completedQuests.length > 1)
                          Align(
                            alignment: Alignment.centerRight,
                            child: BlockText(
                                'TOTAL +$totalCoins 🪙 COINS',
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
                if (unlockedRank != null && onNextRank != null) ...[
                  PressBlock(
                    color: unlockedRank!.color,
                    edge: unlockedRank!.edge,
                    depth: 8,
                    radius: 16,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    onTap: isSaving ? null : onNextRank,
                    child: SizedBox(
                      width: double.infinity,
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: BlockText(
                              'NEXT ${unlockedRank!.isTrial ? 'TRIAL' : 'RANK'} \u25B6  ${unlockedRank!.name}',
                              size: 17,
                              stroke: 4.5),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                PressBlock(
                  color: Rb.green,
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
      ),
    );
  }

  /// Sudden-challenge results + the loot chest drop.
  Widget _challengePanel() {
    final chests = challenges.where((c) => c.lootChest).length;
    final xp = challenges.fold<int>(0, (s, c) => s + c.bonusXp);
    final gems = challenges.fold<int>(0, (s, c) => s + c.bonusCoins);

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
                          : '+${c.bonusXp} EXP  +${c.bonusCoins} 🪙',
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
              child: BlockText('BONUS +$xp EXP  +$gems 🪙 COINS',
                  size: 11, stroke: 3, color: Rb.neon),
            ),
          ],
        ],
      ),
    );
  }

  /// "INTERMEDIATE LEVEL UNLOCKED!" right after the clear that opened it.
  Widget _unlockBanner(RunMode r) {
    return Block(
      color: const Color(0xFF1E6B45),
      edge: const Color(0xFF0B2E1D),
      depth: 5,
      radius: 12,
      gloss: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Stack(children: [
        const Positioned.fill(
            child: FxOnce(Fx.unlockBurst, fit: BoxFit.cover)),
        SizedBox(
        width: double.infinity,
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: BlockText('\u{1F513} ${r.name} UNLOCKED!',
                  size: 17, stroke: 4.5, color: const Color(0xFFFFD21F)),
            ),
            const SizedBox(height: 2),
            BlockText('${r.mapName}  \u2022  ${r.multLabel} rewards',
                size: 10.5, stroke: 3, align: TextAlign.center),
            if (r.requiresId == kNovice.id) ...[
              const SizedBox(height: 2),
              BlockText('\u267E\uFE0F ENDLESS, \u26A1 INTERVAL & DISTANCE TRIALS are open too!',
                  size: 10.5, stroke: 3, align: TextAlign.center, color: Rb.neon),
            ],
          ],
        ),
      ),
      ]),
    );
  }

  static String _paceLabel(int secsPerKm) =>
      "${secsPerKm ~/ 60}'${(secsPerKm % 60).toString().padLeft(2, '0')}\"";

  Widget _intervalRow(Map<String, dynamic> st) {
    final rounds = (st['rounds'] as num?)?.toInt() ?? 0;
    final fastKm = (st['fast_km'] as num?)?.toDouble() ?? 0.0;
    final pace = (st['best_fast_pace_s'] as num?)?.toInt();
    Widget cell(String label, String value) => Expanded(
          child: Column(
            children: [
              BlockText(label,
                  size: 9.5,
                  stroke: 2.5,
                  align: TextAlign.center,
                  color: const Color(0xFFBDEBFF)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: BlockText(value, size: 16, stroke: 3.5),
              ),
            ],
          ),
        );
    return Block(
      color: const Color(0xFF0B6F8F),
      edge: const Color(0xFF053A4A),
      depth: 4,
      radius: 10,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              cell('ROUNDS', '$rounds/${RunMode.intervalRounds}'),
              cell('FAST KM', fastKm.toStringAsFixed(2)),
              cell('BEST FAST PACE', pace == null ? '--' : '${_paceLabel(pace)}/km'),
            ],
          ),
          if (intervalNewBest) ...[
            const SizedBox(height: 6),
            const BlockText('\u2B50 NEW PERSONAL BEST FAST PACE!',
                size: 11, stroke: 3, align: TextAlign.center, color: Rb.gold),
          ],
        ],
      ),
    );
  }

  Widget _modeRow(RunMode m) {
    final head = m.isEndless
        ? '\u267E\uFE0F FREE RUN'
        : m.isInterval
            ? '\u26A1 ${outcome ?? 'INTERVAL RUN'}'
            : (outcome ?? m.name);
    final sub = m.isEndless
        ? '+${m.multLabel} XP & Coins per km'
        : m.isInterval
            ? '${m.name} \u2022 ${m.multLabel} rewards'
            : '${m.emoji} ${m.name} \u2022 ${m.mapName} \u2022 ${m.multLabel} rewards';
    return Block(
      color: outcomeGood ? const Color(0xFF1E6B45) : m.color,
      edge: outcomeGood ? const Color(0xFF0B2E1D) : m.edge,
      depth: 4,
      radius: 10,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Column(
        children: [
          BlockText(head, size: 14, stroke: 4, align: TextAlign.center),
          if (stars > 0) ...[
            const SizedBox(height: 2),
            BlockText(
                '\u2605' * stars + '\u2606' * (3 - stars),
                size: 26,
                stroke: 4,
                color: const Color(0xFFFFD21F)),
          ],
          const SizedBox(height: 2),
          BlockText(sub, size: 10, stroke: 2.5, align: TextAlign.center),
          if (stageBonusCoins > 0) ...[
            const SizedBox(height: 4),
            BlockText(
                '${firstClear ? 'FIRST CLEAR BONUS' : 'NEW STAR BONUS'}  +$stageBonusCoins \u{1FA99}',
                size: 12,
                stroke: 3.5,
                color: Rb.neon,
                align: TextAlign.center),
          ],
        ],
      ),
    );
  }

  Widget _ghostResultRow(GhostResult r) {
    final secs = r.paceDelta.abs().round();
    final text = r.won
        ? '\u{1F47B} GHOST BEATEN! $secs s/km faster  +${GhostResult.winCoins} \u{1FA99}'
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


// ═════════════════════════════════════════════════════════════════════════
// END SESSION: press and hold
// ═════════════════════════════════════════════════════════════════════════
class _HoldToEndButton extends StatefulWidget {
  final VoidCallback onComplete;
  const _HoldToEndButton({required this.onComplete});

  @override
  State<_HoldToEndButton> createState() => _HoldToEndButtonState();
}

class _HoldToEndButtonState extends State<_HoldToEndButton>
    with SingleTickerProviderStateMixin {
  static const _holdTime = Duration(milliseconds: 1400);

  late final AnimationController _c;
  bool _fired = false;
  bool _hint = false; // "keep holding" nudge after a quick tap

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: _holdTime)
      ..addStatusListener((st) {
        if (st == AnimationStatus.completed && !_fired) {
          _fired = true;
          Sound.I.buzz(3);
          widget.onComplete();
        }
      });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _down() {
    if (_fired) return;
    setState(() => _hint = false);
    _c.forward(from: 0);
  }

  void _up() {
    if (_fired) return;
    final early = _c.value < 1;
    _c.animateBack(0, duration: const Duration(milliseconds: 180));
    if (early) setState(() => _hint = true);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _down(),
      onTapUp: (_) => _up(),
      onTapCancel: _up,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final holding = _c.isAnimating && _c.status == AnimationStatus.forward;
          return Block(
            color: Rb.red,
            edge: Rb.redEdge,
            depth: 10,
            radius: 18,
            padding: EdgeInsets.zero,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: _c.value.clamp(0.0, 1.0).toDouble(),
                        heightFactor: 1,
                        child: const ColoredBox(color: Color(0xFFB02A30)),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: BlockText('\u{1F6D1} END SESSION',
                                size: 24, stroke: 5),
                          ),
                          const SizedBox(height: 2),
                          BlockText(
                            holding
                                ? 'KEEP HOLDING...'
                                : _hint
                                    ? 'HOLD THE BUTTON TO END'
                                    : 'PRESS AND HOLD',
                            size: 10.5,
                            stroke: 3,
                            color: _hint
                                ? const Color(0xFFFFE066)
                                : const Color(0xFFFFD6D8),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
