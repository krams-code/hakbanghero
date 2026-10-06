import 'dart:math' as math;

import 'package:flutter/foundation.dart';

// ═════════════════════════════════════════════════════════════════════════
//  Sudden Mid-Run Challenges
//
//  A small state machine that the run screen feeds once per second (run
//  clock) and on every accepted GPS distance update. No Flutter UI in here.
//
//   ⚡ SPRINT BLITZ  random, after 5 min of running: cover N metres in S s
//   ⏱️ PACE KEEPER   at the 2.0 km mark: next 1.0 km in under 5 min
//
//  One challenge at a time. If the 2 km mark is crossed while a Sprint
//  Blitz is running, the Pace Keeper starts the moment the sprint ends (its
//  start distance is locked in THEN).
// ═════════════════════════════════════════════════════════════════════════

enum ChallengeKind { sprintBlitz, paceKeeper }

enum ChallengeEventType { started, succeeded, failed }

class ChallengeEvent {
  final ChallengeEventType type;
  final ChallengeKind kind;
  const ChallengeEvent(this.type, this.kind);
}

/// Every tunable number lives here.
///
/// ⚠️ Sprint Blitz at 300 m in 20 s is 15 m/s (54 km/h). The 100 m world
/// record averages ~10.4 m/s, so no human can finish it and, because of
/// [maxPlausibleSpeedMps], neither can a GPS glitch. Realistic values for a
/// fit runner mid-run: 100 m in 20 s (5 m/s, 18 km/h) or 60 m in 20 s.
class ChallengeConfig {
  // ── Sprint Blitz ──
  final int sprintMinElapsedSeconds; // run time before it may fire
  final double sprintTargetMeters;
  final int sprintSeconds;
  final int sprintBonusXp;
  final int sprintBonusGems; // "Mana Crystals" (the `gems` field)
  final double sprintChancePerSecond; // random trigger once eligible
  final int sprintMaxPerRun;

  // ── Pace Keeper ──
  final double paceTriggerKm; // fires when the run crosses this distance
  final double paceSectionKm; // distance to cover
  final int paceSeconds; // time allowed

  // ── GPS sanity ──
  /// Distance credited to a challenge is rate-limited to this speed, so a
  /// GPS jump (or a car ride) can't "complete" a quest. 12.5 m/s = 45 km/h,
  /// faster than any human sprinter.
  final double maxPlausibleSpeedMps;

  const ChallengeConfig({
    this.sprintMinElapsedSeconds = 300,
    this.sprintTargetMeters = 300,
    this.sprintSeconds = 20,
    this.sprintBonusXp = 50,
    this.sprintBonusGems = 5,
    this.sprintChancePerSecond = 1 / 90, // ~90 s on average after minute 5
    this.sprintMaxPerRun = 1,
    this.paceTriggerKm = 2.0,
    this.paceSectionKm = 1.0,
    this.paceSeconds = 300,
    this.maxPlausibleSpeedMps = 12.5,
  });
}

const ChallengeConfig kChallengeConfig = ChallengeConfig();

/// One finished challenge (shown in the post-run summary and saved).
class ChallengeRecord {
  final ChallengeKind kind;
  final bool success;
  final int bonusXp;
  final int bonusGems;
  final bool lootChest;
  final int atElapsedSeconds;

  const ChallengeRecord({
    required this.kind,
    required this.success,
    required this.bonusXp,
    required this.bonusGems,
    required this.lootChest,
    required this.atElapsedSeconds,
  });

  Map<String, dynamic> toMap() => {
        'kind': kind.name,
        'success': success,
        'bonusXp': bonusXp,
        'bonusGems': bonusGems,
        'lootChest': lootChest,
        'atSeconds': atElapsedSeconds,
      };
}

class ChallengeEngine extends ChangeNotifier {
  ChallengeEngine({
    this.config = kChallengeConfig,
    math.Random? random,
    this.onEvent,
  }) : _rng = random ?? math.Random();

  final ChallengeConfig config;
  final math.Random _rng;

  /// Called for started / succeeded / failed (the run screen plays the alarm
  /// and result sounds from here).
  void Function(ChallengeEvent event)? onEvent;

  // ── run-wide bookkeeping ──
  final List<ChallengeRecord> _records = [];
  int _sprintsFired = 0;
  bool _paceFired = false;
  bool _seeded = false;
  int _lastElapsed = 0;
  int _lastRollElapsed = 0;
  double _lastDistanceKm = 0;
  int _nowElapsed = 0;
  double _budgetKm = 0; // GPS rate-limit token bucket

  // ── the active challenge ──
  ChallengeKind? _kind;
  int _serial = 0; // bumps every time a challenge starts
  int _startElapsed = 0;
  double _startDistanceKm = 0;
  double _creditedKm = 0;

  // ── last result (drives the big result banner) ──
  ChallengeRecord? _lastResult;
  int _resultSerial = 0;

  // ───────────────────────── read-only state ─────────────────────────

  bool get isActive => _kind != null;
  ChallengeKind? get activeKind => _kind;

  /// Increments each time a challenge starts (lets the UI re-run its intro).
  int get serial => _serial;

  ChallengeRecord? get lastResult => _lastResult;
  int get resultSerial => _resultSerial;

  List<ChallengeRecord> get records => List.unmodifiable(_records);
  int get bonusXp => _records.fold(0, (s, r) => s + r.bonusXp);
  int get bonusGems => _records.fold(0, (s, r) => s + r.bonusGems);
  int get lootChests => _records.where((r) => r.lootChest).length;

  int get _limitSeconds => _kind == ChallengeKind.paceKeeper
      ? config.paceSeconds
      : config.sprintSeconds;

  double get _targetKm => _kind == ChallengeKind.paceKeeper
      ? config.paceSectionKm
      : config.sprintTargetMeters / 1000.0;

  /// Seconds the active challenge has been running.
  int get spentSeconds => isActive ? _nowElapsed - _startElapsed : 0;

  int get remainingSeconds =>
      isActive ? math.max(0, _limitSeconds - spentSeconds) : 0;

  double get targetMeters => _targetKm * 1000.0;
  double get progressMeters => _creditedKm * 1000.0;
  double get progressFraction =>
      isActive ? (_creditedKm / _targetKm).clamp(0.0, 1.0) : 0.0;

  /// Pace Keeper: the odometer reading locked in when the trial began.
  double get startMarkerKm => _startDistanceKm;
  double get finishMarkerKm => _startDistanceKm + config.paceSectionKm;

  /// Pace Keeper: live split pace over the trial so far (seconds per km),
  /// or null until there is enough distance to be meaningful.
  int? get splitPaceSecPerKm {
    if (_kind != ChallengeKind.paceKeeper || _creditedKm < 0.02) return null;
    return (spentSeconds / _creditedKm).round();
  }

  /// Pace Keeper: the average pace still needed to make the cut-off.
  int? get requiredPaceSecPerKm {
    if (_kind != ChallengeKind.paceKeeper) return null;
    final leftKm = config.paceSectionKm - _creditedKm;
    if (leftKm <= 0 || remainingSeconds <= 0) return null;
    return (remainingSeconds / leftKm).round();
  }

  /// Pace Keeper: at the current split pace, would 1.0 km finish in time?
  bool get onTrack {
    final split = splitPaceSecPerKm;
    if (split == null) return true;
    return split * config.paceSectionKm <= config.paceSeconds;
  }

  double get _burstKm => config.maxPlausibleSpeedMps * 3 / 1000.0;

  // ───────────────────────── control ─────────────────────────

  /// New run: forget everything.
  void reset() {
    _records.clear();
    _sprintsFired = 0;
    _paceFired = false;
    _seeded = false;
    _kind = null;
    _creditedKm = 0;
    _lastResult = null;
    _budgetKm = _burstKm;
    notifyListeners();
  }

  /// Hide the result banner.
  void dismissResult() {
    if (_lastResult == null) return;
    _lastResult = null;
    notifyListeners();
  }

  /// Debug helper: start a challenge right now (ignores the triggers).
  void forceStart(
    ChallengeKind kind, {
    required int elapsedSeconds,
    required double distanceKm,
  }) {
    if (isActive) return;
    _seedIfNeeded(elapsedSeconds, distanceKm);
    _nowElapsed = elapsedSeconds;
    _start(kind, elapsedSeconds, distanceKm);
  }

  /// Feed the engine. Call once per run-clock second AND after every
  /// accepted GPS distance update (extra calls are harmless).
  ///
  /// [elapsedSeconds] is the run's active time (it stops while paused, so
  /// countdowns freeze with it). [distanceKm] is the cumulative distance.
  void update({
    required int elapsedSeconds,
    required double distanceKm,
    required bool moving,
  }) {
    _seedIfNeeded(elapsedSeconds, distanceKm);

    // GPS rate limiter: credit at most maxPlausibleSpeed x time.
    final dt = elapsedSeconds - _lastElapsed;
    if (dt > 0) {
      _lastElapsed = elapsedSeconds;
      _budgetKm = math.min(
        _budgetKm + config.maxPlausibleSpeedMps * dt / 1000.0,
        _burstKm,
      );
    }
    final delta = math.max(0.0, distanceKm - _lastDistanceKm);
    _lastDistanceKm = distanceKm;
    final take = math.min(delta, _budgetKm);
    _budgetKm -= take;

    _nowElapsed = elapsedSeconds;

    if (isActive) {
      _creditedKm += take;
      _evaluate();
    } else {
      _maybeTrigger(elapsedSeconds, distanceKm, moving);
    }
  }

  // ───────────────────────── internals ─────────────────────────

  void _seedIfNeeded(int elapsed, double distanceKm) {
    if (_seeded) return;
    _seeded = true;
    _lastElapsed = elapsed;
    _lastRollElapsed = elapsed;
    _lastDistanceKm = distanceKm;
    _nowElapsed = elapsed;
    _budgetKm = _burstKm;
  }

  void _maybeTrigger(int elapsed, double distanceKm, bool moving) {
    // Pace Keeper: a fixed milestone, so it always wins over a random roll.
    if (!_paceFired && distanceKm >= config.paceTriggerKm) {
      _start(ChallengeKind.paceKeeper, elapsed, distanceKm);
      return;
    }

    // Sprint Blitz: random, once 5 min have been run.
    final eligible = _sprintsFired < config.sprintMaxPerRun &&
        elapsed >= config.sprintMinElapsedSeconds &&
        moving;
    if (!eligible) {
      _lastRollElapsed = elapsed; // don't bank rolls while ineligible
      return;
    }
    final dt = elapsed - _lastRollElapsed;
    if (dt <= 0) return;
    _lastRollElapsed = elapsed;
    // P(at least one hit in dt seconds) so the rate is frame-rate independent.
    final p = 1 - math.pow(1 - config.sprintChancePerSecond, dt);
    if (_rng.nextDouble() < p) {
      _start(ChallengeKind.sprintBlitz, elapsed, distanceKm);
    }
  }

  void _start(ChallengeKind kind, int elapsed, double distanceKm) {
    _kind = kind;
    _serial++;
    _startElapsed = elapsed;
    _startDistanceKm = distanceKm; // the locked-in starting marker
    _creditedKm = 0;
    _budgetKm = _burstKm;
    _lastResult = null;
    if (kind == ChallengeKind.sprintBlitz) {
      _sprintsFired++;
    } else {
      _paceFired = true;
    }
    onEvent?.call(ChallengeEvent(ChallengeEventType.started, kind));
    notifyListeners();
  }

  void _evaluate() {
    // success is checked first, so crossing the line in the very second the
    // countdown reaches zero still counts.
    if (_creditedKm >= _targetKm - 1e-9) {
      _finish(true);
    } else if (spentSeconds >= _limitSeconds) {
      _finish(false);
    } else {
      notifyListeners(); // countdown / progress changed
    }
  }

  void _finish(bool success) {
    final kind = _kind!;
    final record = ChallengeRecord(
      kind: kind,
      success: success,
      bonusXp: success && kind == ChallengeKind.sprintBlitz
          ? config.sprintBonusXp
          : 0,
      bonusGems: success && kind == ChallengeKind.sprintBlitz
          ? config.sprintBonusGems
          : 0,
      lootChest: success && kind == ChallengeKind.paceKeeper,
      atElapsedSeconds: _nowElapsed,
    );
    _records.add(record);
    _lastResult = record;
    _resultSerial++;
    _kind = null;
    _creditedKm = 0;
    onEvent?.call(ChallengeEvent(
      success ? ChallengeEventType.succeeded : ChallengeEventType.failed,
      kind,
    ));
    notifyListeners();
  }
}
