import 'package:flutter/material.dart';

import '../challenges/challenge_engine.dart';

/// The two core game loops.
enum RunLoop { stage, endless, interval }

/// Which mid-run events a mode triggers.
enum EventPlan { none, oneSprintQuest, paceTrials, intervals }

/// One selectable way to run: a Stage rank (Novice / Vanguard / Slayer) or
/// the casual Endless Run. Everything the run screen needs lives here, so
/// balancing a mode means editing ONE constant below.
class RunMode {
  final String id; // saved on the activity document
  final RunLoop loop;
  final String emoji;
  final String name; // "BEGINNER LEVEL"
  final String mapName; // "Park Loop"

  /// Distance to clear. Null = no target (Endless).
  final double? targetKm;

  /// Stage clock in minutes. Null = no clock (Endless).
  final int? clockMinutes;

  /// Multiplier on XP, coins and challenge coins.
  final double rewardMult;

  final EventPlan events;
  final Color color;
  final Color edge;

  /// Map picture used as the live-run background and on the mode cards.
  final String mapAsset;

  /// One-time bonus coins for the FIRST clear of this rank.
  final int firstClearCoins;

  /// Rank that must be cleared (>= 1 star) before this one opens. Null = open.
  final String? requiresId;

  /// Distance Trial: a fixed distance against a fixed time goal. Runs like a
  /// stage (target + clock + record) but is NOT one of the 3 campaign ranks.
  final bool isTrial;

  const RunMode({
    required this.id,
    required this.loop,
    required this.emoji,
    required this.name,
    required this.mapName,
    required this.targetKm,
    required this.clockMinutes,
    required this.rewardMult,
    required this.events,
    required this.color,
    required this.edge,
    required this.mapAsset,
    this.firstClearCoins = 0,
    this.requiresId,
    this.isTrial = false,
  });

  /// Every star you can collect across the three ranks.
  static const int maxStars = 9;

  /// Stars saved for [id] in the user's `stage_records` map.
  static int starsIn(Object? records, String id) {
    if (records is Map) {
      final r = records[id];
      if (r is Map) {
        final v = r['stars'];
        if (v is num) return v.toInt();
      }
    }
    return 0;
  }

  /// All stars earned so far (0..9).
  static int totalStars(Object? records) {
    var n = 0;
    for (final m in kStageModes) {
      n += starsIn(records, m.id);
    }
    return n;
  }

  /// Is [m] open? Only Novice is always open; Vanguard and Slayer need the
  /// rank before them cleared, and Endless needs Novice cleared once.
  static bool isUnlocked(RunMode m, Object? records) {
    final need = m.requiresId;
    return need == null || starsIn(records, need) > 0;
  }

  /// "Clear BEGINNER LEVEL to unlock" (null when already open / no requirement).
  String? get lockHint {
    final need = requiresId;
    if (need == null) return null;
    final r = byId(need);
    return r == null ? null : 'Clear ${r.name} to unlock';
  }

  /// Coins for every NEW star earned on a rank (after the first clear).
  static const int starCoins = 50;

  /// Stars for a cleared stage, by how much of the clock was left:
  /// ★ clear · ★★ clear with 1/3+ of the clock left · ★★★ with 1/2+ left.
  int starsFor(int secondsUsed) {
    final total = clockSeconds;
    if (total == null || total <= 0) return 0;
    if (isTrial) return 1; // a trial is simply cleared or not
    final used = secondsUsed / total;
    if (used <= starThree) return 3;
    if (used <= starTwo) return 2;
    return 1;
  }

  /// Share of the clock you may use for 3 / 2 stars. Realistic for a normal
  /// runner: Novice 2 km in 20 min -> 3 stars at 12:00 (10 km/h), 2 stars at
  /// 16:00 (7.5 km/h), 1 star by the clock (6 km/h brisk walk).
  static const double starThree = 0.6;
  static const double starTwo = 0.8;

  /// "Under 15:00" style goal for the 3-star / 2-star rows on the briefing.
  String starGoalLabel(int stars) {
    final total = clockSeconds ?? 0;
    final secs =
        (total * (stars == 3 ? starThree : starTwo)).round();
    final m = secs ~/ 60, s = secs % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  bool get isStage => loop == RunLoop.stage;
  bool get isEndless => loop == RunLoop.endless;
  bool get isInterval => loop == RunLoop.interval;

  // ── Interval Run: FAST / EASY rounds on a fixed clock ──────────────────
  static const int intervalRounds = 6;
  static const int intervalFastSeconds = 60;
  static const int intervalEasySeconds = 60;
  static const int intervalCycle = intervalFastSeconds + intervalEasySeconds;
  static const int intervalTotalSeconds = intervalRounds * intervalCycle;

  /// Where an Interval Run is after [elapsed] seconds (null once finished).
  static IntervalPhase? intervalAt(int elapsed) {
    if (elapsed < 0 || elapsed >= intervalTotalSeconds) return null;
    final within = elapsed % intervalCycle;
    final fast = within < intervalFastSeconds;
    return IntervalPhase(
      round: elapsed ~/ intervalCycle + 1,
      fast: fast,
      secondsLeft: fast ? intervalFastSeconds - within : intervalCycle - within,
    );
  }
  int? get clockSeconds => clockMinutes == null ? null : clockMinutes! * 60;

  String get multLabel => '${rewardMult.toStringAsFixed(1)}x';

  /// "1.0x XP & Coins" / "+0.8x XP & Coins per km"
  String get rewardLabel => isEndless
      ? '+$multLabel XP & Coins per km'
      : '$multLabel XP & Coins';

  String get eventLabel {
    switch (events) {
      case EventPlan.none:
        return isEndless ? 'No events. Just run.' : 'No sudden events';
      case EventPlan.oneSprintQuest:
        return '1 random Mid-Run Sprint Quest';
      case EventPlan.paceTrials:
        return 'Multiple high-velocity Pace Trials';
      case EventPlan.intervals:
        return '$intervalRounds rounds: 1 min FAST, 1 min EASY';
    }
  }

  /// Which events this mode fires, as an engine config.
  /// Returns null when the mode has no events (the engine stays off).
  ChallengeConfig? get challengeConfig {
    switch (events) {
      case EventPlan.none:
      case EventPlan.intervals: // paced by the run screen, not the engine
        return null;
      case EventPlan.oneSprintQuest:
        // exactly one Sprint Blitz, never a Pace Keeper
        // 100 m in 25 s = 14.4 km/h: a real sprint a fit runner can win.
        // (The old 300 m in 20 s needs 54 km/h, which nobody can do.)
        return const ChallengeConfig(
          sprintMinElapsedSeconds: 120,
          sprintChancePerSecond: 1 / 60,
          sprintMaxPerRun: 1,
          sprintTargetMeters: 100,
          sprintSeconds: 25,
          paceMaxPerRun: 0,
        );
      case EventPlan.paceTrials:
        // Pace Trials at 1.0 km and again 1 km after each trial ends;
        // no Sprint Blitz in this mode.
        return const ChallengeConfig(
          sprintMaxPerRun: 0,
          paceTriggerKm: 1.0,
          paceSectionKm: 1.0,
          paceSeconds: 360, // 6:00 per km = 10 km/h
          paceMaxPerRun: 2,
          paceRepeatGapKm: 1.0,
        );
    }
  }

  /// Plain-language heads-up lines for the Stage Briefing card.
  List<String> get briefingWarnings {
    final cfg = challengeConfig;
    switch (events) {
      case EventPlan.none:
        return const ['No sudden events. Just reach the target before the clock runs out.'];
      case EventPlan.oneSprintQuest:
        return [
          '\u26A1 1 random Sprint Quest will appear mid-run: cover '
              '${cfg!.sprintTargetMeters.round()} m in ${cfg.sprintSeconds} s '
              '(+${cfg.sprintBonusXp} XP, +${cfg.sprintBonusCoins} \u{1FA99}).',
        ];
      case EventPlan.intervals:
        return const [
          '6 rounds of 1 min FAST then 1 min EASY (12 min total).',
          'The screen and a buzz tell you when to switch. Finish all 6 rounds!',
        ];
      case EventPlan.paceTrials:
        final m = cfg!.paceSeconds ~/ 60, sec = cfg.paceSeconds % 60;
        return [
          '\u26A1 ${cfg.paceMaxPerRun} Pace Trials: run ${cfg.paceSectionKm.toStringAsFixed(1)} km '
              'in under $m:${sec.toString().padLeft(2, '0')} each.',
          'First one starts at ${cfg.paceTriggerKm.toStringAsFixed(1)} km. Beat it for a loot chest!',
        ];
    }
  }

  static RunMode? byId(String? id) {
    for (final m in kRunModes) {
      if (m.id == id) return m;
    }
    for (final m in kTrialModes) {
      if (m.id == id) return m;
    }
    return null;
  }
}

const RunMode kNovice = RunMode(
  id: 'stage_novice',
  loop: RunLoop.stage,
  emoji: '\u{1F7E2}',
  name: 'BEGINNER LEVEL',
  mapName: 'Park Loop',
  targetKm: 2.0,
  clockMinutes: 20,
  rewardMult: 1.0,
  events: EventPlan.none,
  color: Color(0xFF00B06F),
  edge: Color(0xFF006B44),
  mapAsset: 'assets/images/maps/verdant_vale.jpg',
  firstClearCoins: 100,
);

const RunMode kVanguard = RunMode(
  id: 'stage_vanguard',
  loop: RunLoop.stage,
  emoji: '\u{1F7E1}',
  name: 'INTERMEDIATE LEVEL',
  mapName: 'City Streets',
  targetKm: 3.5,
  clockMinutes: 30,
  rewardMult: 1.5,
  events: EventPlan.oneSprintQuest,
  color: Color(0xFFD98E00),
  edge: Color(0xFF7A4B00),
  mapAsset: 'assets/images/maps/ember_plains.jpg',
  firstClearCoins: 250,
  requiresId: 'stage_novice',
);

const RunMode kSlayer = RunMode(
  id: 'stage_slayer',
  loop: RunLoop.stage,
  emoji: '\u{1F534}',
  name: 'ADVANCED LEVEL',
  mapName: 'Hill Road',
  targetKm: 5.0,
  clockMinutes: 40,
  rewardMult: 2.5,
  events: EventPlan.paceTrials,
  color: Color(0xFFE5484D),
  edge: Color(0xFF7A1C20),
  mapAsset: 'assets/images/maps/abyss_citadel.jpg',
  firstClearCoins: 500,
  requiresId: 'stage_vanguard',
);

const RunMode kEndless = RunMode(
  id: 'endless',
  loop: RunLoop.endless,
  emoji: '♾️',
  name: 'FREE RUN',
  mapName: 'Open Road',
  targetKm: null,
  clockMinutes: null,
  // the everyday "just go for a run": almost full reward (ranks pay more)
  rewardMult: 0.8,
  events: EventPlan.none,
  color: Color(0xFF5B3A9E),
  edge: Color(0xFF2A1A52),
  mapAsset: 'assets/images/maps/open_road.jpg',
  // Endless opens with the first clear of BEGINNER LEVEL, so a brand-new hero
  // starts with exactly ONE choice: run BEGINNER to unlock the rest.
  requiresId: 'stage_novice',
);

const RunMode kInterval = RunMode(
  id: 'interval',
  loop: RunLoop.interval,
  emoji: '\u26A1',
  name: 'INTERVAL RUN',
  mapName: 'Track Intervals',
  targetKm: null,
  clockMinutes: 12,
  rewardMult: 1.3,
  events: EventPlan.intervals,
  color: Color(0xFF0097C4),
  edge: Color(0xFF005A75),
  mapAsset: 'assets/images/maps/open_road.jpg',
  // like Endless, it opens with the first clear of BEGINNER LEVEL
  requiresId: 'stage_novice',
);

// ═════════════════════════════════════════════════════════════════════════
// DISTANCE TRIALS: 2 km, 5 km, 10 km, Marathon. Each distance has 3 time
// goals that open one after another (clear 15:00 to open 12:00, then 10:00).
// Clearing a distance's last time opens the next distance.
// ═════════════════════════════════════════════════════════════════════════

class _TrialSpec {
  final String key; // '2k'
  final String label; // '2 KM'
  final double km;
  final List<int> minutes; // easiest first
  final double baseMult;
  final List<int> firstCoins; // first-clear coins per time goal
  final String mapName;
  final String mapAsset;
  final Color color;
  final Color edge;
  const _TrialSpec(this.key, this.label, this.km, this.minutes, this.baseMult,
      this.firstCoins, this.mapName, this.mapAsset, this.color, this.edge);
}

const List<_TrialSpec> _kTrialSpecs = [
  _TrialSpec('2k', '2 KM', 2.0, [15, 12, 10], 1.2, [100, 150, 200],
      'The Sprint Lane', 'assets/images/maps/verdant_vale.jpg',
      Color(0xFF1FA2A6), Color(0xFF0B5D60)),
  _TrialSpec('5k', '5 KM', 5.0, [40, 32, 27], 1.6, [200, 300, 400],
      'The Tempo Trail', 'assets/images/maps/ember_plains.jpg',
      Color(0xFF3B7DD8), Color(0xFF1B3F73)),
  _TrialSpec('10k', '10 KM', 10.0, [80, 65, 55], 2.0, [400, 600, 800],
      'The Endurance Ridge', 'assets/images/maps/abyss_citadel.jpg',
      Color(0xFF8A4FD8), Color(0xFF45247A)),
  _TrialSpec('42k', 'MARATHON', 42.195, [390, 330, 270], 2.8, [1000, 1500, 2500],
      'The Marathon Road', 'assets/images/maps/open_road.jpg',
      Color(0xFFC2332E), Color(0xFF6A1714)),
];

/// "15 MIN" / "1 H 20 MIN" / "6 H 30 MIN"
String _minLabel(int m) {
  if (m < 60) return '$m MIN';
  final h = m ~/ 60, r = m % 60;
  return r == 0 ? '$h H' : '$h H $r MIN';
}

List<RunMode> _buildTrials() {
  final out = <RunMode>[];
  String prev = kNovice.id;
  for (final sp in _kTrialSpecs) {
    for (var i = 0; i < sp.minutes.length; i++) {
      final id = 'trial_${sp.key}_${sp.minutes[i]}';
      out.add(RunMode(
        id: id,
        loop: RunLoop.stage,
        isTrial: true,
        emoji: '\u{1F3C1}',
        name: '${sp.label} IN ${_minLabel(sp.minutes[i])}',
        mapName: sp.mapName,
        targetKm: sp.km,
        clockMinutes: sp.minutes[i],
        rewardMult: double.parse((sp.baseMult + 0.1 * i).toStringAsFixed(1)),
        events: EventPlan.none,
        color: sp.color,
        edge: sp.edge,
        mapAsset: sp.mapAsset,
        firstClearCoins: sp.firstCoins[i],
        requiresId: prev,
      ));
      prev = id;
    }
  }
  return out;
}

/// All 12 trials in unlock order.
final List<RunMode> kTrialModes = _buildTrials();

/// Trials of one distance, e.g. 'DISTANCE' groups for the picker.
List<List<RunMode>> get kTrialGroups => [
      for (final sp in _kTrialSpecs)
        [for (final m in kTrialModes) if (m.targetKm == sp.km) m],
    ];

String trialGroupLabel(RunMode m) {
  for (final sp in _kTrialSpecs) {
    if (sp.km == m.targetKm) return sp.label;
  }
  return m.name;
}

/// Short time-goal label for a trial: "15 MIN".
String trialTimeLabel(RunMode m) => _minLabel(m.clockMinutes ?? 0);

const List<RunMode> kStageModes = [kNovice, kVanguard, kSlayer];
const List<RunMode> kRunModes = [kNovice, kVanguard, kSlayer, kEndless, kInterval];

/// One moment of an Interval Run.
class IntervalPhase {
  final int round; // 1..intervalRounds
  final bool fast; // true = FAST, false = EASY
  final int secondsLeft; // in this FAST / EASY block
  const IntervalPhase({
    required this.round,
    required this.fast,
    required this.secondsLeft,
  });
}
