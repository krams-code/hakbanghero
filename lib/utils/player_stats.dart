import 'package:hakbanghero/models/activity_model.dart';

/// Level maths. Matches the old Profile rule: leaving level L costs L * 500 XP.
class LevelProgress {
  final int level;
  final int xpIntoLevel;
  final int xpNeeded;
  const LevelProgress(this.level, this.xpIntoLevel, this.xpNeeded);

  double get fraction => xpNeeded == 0 ? 0 : (xpIntoLevel / xpNeeded).clamp(0.0, 1.0);

  static LevelProgress fromXp(int totalXp) {
    var level = 1;
    var rem = totalXp < 0 ? 0 : totalXp;
    while (rem >= level * 500) {
      rem -= level * 500;
      level++;
    }
    return LevelProgress(level, rem, level * 500);
  }
}

/// Fitness-driven profile modules computed from REAL session history.
///
///  * Pace / Agility     – average + best running speed
///  * Stamina Pool       – this week's estimated calorie burn; the pool
///                         expands with consecutive consistent weeks
///  * Recovery/Endurance – active-day streak + 30-day session frequency
class FitnessStats {
  // agility
  final double avgSpeedKmh; // last 10 sessions
  final double bestSpeedKmh;
  final double agilityFraction; // vs a 15 km/h target

  // stamina
  final int weeklyKcal;
  final int staminaMax;
  final int consistentWeeks;
  final int weeklyActiveDays;
  final double weeklyKm;

  // endurance
  final int streakDays;
  final int sessions30d;
  final double enduranceFraction;

  // records
  final double longestRunKm;
  final int bestPaceSecsPerKm; // 0 = none
  final int longestStreakDays;
  final int totalActiveSeconds;

  const FitnessStats({
    required this.avgSpeedKmh,
    required this.bestSpeedKmh,
    required this.agilityFraction,
    required this.weeklyKcal,
    required this.staminaMax,
    required this.consistentWeeks,
    required this.weeklyActiveDays,
    required this.weeklyKm,
    required this.streakDays,
    required this.sessions30d,
    required this.enduranceFraction,
    required this.longestRunKm,
    required this.bestPaceSecsPerKm,
    required this.longestStreakDays,
    required this.totalActiveSeconds,
  });

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// [sessions] may be in any order. [weightKg] falls back to 65.
  /// [enduranceBonus] = flat points from weight check-in evolutions
  /// (`endurance_bonus` on the user doc; each evolution is worth +10 of 100).
  static FitnessStats compute(
    List<ActivitySession> sessions, {
    double? weightKg,
    int enduranceBonus = 0,
  }) {
    final now = DateTime.now();
    final today = _day(now);
    final kg = (weightKg == null || weightKg <= 0) ? 65.0 : weightKg;
    final sorted = [...sessions]..sort((a, b) => b.startTime.compareTo(a.startTime));

    // ── agility ──
    final recent = sorted.where((s) => s.distanceKm >= 0.05).take(10).toList();
    final avg = recent.isEmpty
        ? 0.0
        : recent.map((s) => s.avgSpeedKmh).reduce((a, b) => a + b) / recent.length;
    final best = sorted.fold<double>(0, (m, s) => s.avgSpeedKmh > m ? s.avgSpeedKmh : m);

    // ── days with activity ──
    final days = <DateTime>{for (final s in sorted) _day(s.startTime)};
    bool active(DateTime d) => days.contains(d);

    // current streak: counts back from today (or yesterday if not run yet today)
    var streak = 0;
    var cursor = active(today) ? today : today.subtract(const Duration(days: 1));
    while (active(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    // longest streak overall
    var longest = 0, run = 0;
    DateTime? prev;
    for (final d in days.toList()..sort()) {
      if (prev != null && d.difference(prev).inDays == 1) {
        run++;
      } else {
        run = 1;
      }
      if (run > longest) longest = run;
      prev = d;
    }

    // ── rolling 7-day windows ──
    bool inWindow(ActivitySession s, int i) {
      final d = _day(s.startTime);
      final end = today.subtract(Duration(days: 7 * i));
      final start = end.subtract(const Duration(days: 6));
      return !d.isBefore(start) && !d.isAfter(end);
    }

    double factor(ActivityType t) {
      switch (t) {
        case ActivityType.walk:
          return 0.7;
        case ActivityType.jog:
          return 0.9;
        case ActivityType.run:
          return 1.0;
      }
    }

    final week0 = sorted.where((s) => inWindow(s, 0)).toList();
    // ≈ 1 kcal per kg per km (running); less for walking / jogging
    final kcal = week0.fold<double>(0, (a, s) => a + kg * s.distanceKm * factor(s.type)).round();
    final weekKm = week0.fold<double>(0, (a, s) => a + s.distanceKm);
    final weekDays = <DateTime>{for (final s in week0) _day(s.startTime)}.length;

    // consecutive "consistent" weeks (2+ sessions). The current week may
    // still be in progress, so it only breaks the chain if we start there.
    var weeks = 0;
    var startAt = sorted.where((s) => inWindow(s, 0)).length >= 2 ? 0 : 1;
    for (var i = startAt; i < 12; i++) {
      if (sorted.where((s) => inWindow(s, i)).length >= 2) {
        weeks++;
      } else {
        break;
      }
    }
    final poolMax = 1000 + 250 * weeks;

    // ── endurance ──
    final since30 = today.subtract(const Duration(days: 29));
    final s30 = sorted.where((s) => !_day(s.startTime).isBefore(since30)).length;
    final endurance =
        ((streak * 12 + s30 * 4 + enduranceBonus) / 100).clamp(0.0, 1.0);

    // ── records ──
    final longestRun = sorted.fold<double>(0, (m, s) => s.distanceKm > m ? s.distanceKm : m);
    var bestPace = 0;
    for (final s in sorted) {
      if (s.distanceKm >= 0.5 && s.durationSeconds > 0) {
        final p = (s.durationSeconds / s.distanceKm).round();
        if (bestPace == 0 || p < bestPace) bestPace = p;
      }
    }
    final totalSecs = sorted.fold<int>(0, (a, s) => a + s.durationSeconds);

    return FitnessStats(
      avgSpeedKmh: avg,
      bestSpeedKmh: best,
      agilityFraction: (avg / 15).clamp(0.0, 1.0),
      weeklyKcal: kcal,
      staminaMax: poolMax,
      consistentWeeks: weeks,
      weeklyActiveDays: weekDays,
      weeklyKm: weekKm,
      streakDays: streak,
      sessions30d: s30,
      enduranceFraction: endurance,
      longestRunKm: longestRun,
      bestPaceSecsPerKm: bestPace,
      longestStreakDays: longest,
      totalActiveSeconds: totalSecs,
    );
  }
}
