/// XP and coins for one finished run. ONE place, used by solo runs and duels,
/// and mirrored by the Firestore security rules (which cap what a run record
/// may claim), so balancing is done here and in tools/gen_economy_rules.py.
///
/// WHAT THE REWARD IS BASED ON
///  * Distance (GPS)   the main thing: 100 XP and 10 coins per km.
///  * Moving time      3 XP per minute you were actually MOVING. Standing
///                     still, or leaving the timer running, earns nothing.
///  * Pace             a small bonus for effort: x1.0 walking, x1.15 jogging
///                     (6+ km/h), x1.3 running (9+ km/h) on XP.
///  * Mode             Novice 1.0x ... Slayer 2.5x, Trials 1.2x ... 3.0x.
///  * Events / quests  Sprint and Pace Trial bonuses are added on top.
abstract final class RunRewards {
  static const double xpPerKm = 100;
  static const double xpPerActiveMinute = 3;
  static const double coinsPerKm = 10;

  /// Nobody sustains more than this on foot: faster GPS jumps are ignored.
  static const double maxKmh = 25;

  /// Highest mode multiplier in the game (rules use it as a ceiling).
  static const double maxMult = 3.5;

  /// Highest pace multiplier (see [intensity]).
  static const double maxIntensity = 1.3;

  static double intensity(double avgMovingKmh) {
    if (avgMovingKmh >= 9) return 1.3;
    if (avgMovingKmh >= 6) return 1.15;
    return 1.0;
  }

  /// Average speed while moving (km/h), 0 when there is too little data.
  static double movingKmh(double km, int activeSeconds) =>
      activeSeconds < 30 ? 0 : km / (activeSeconds / 3600);

  static int xp({
    required double km,
    required int activeSeconds,
    required double mult,
    int bonusXp = 0,
  }) {
    // moving time can't be more than the distance covered at a slow walk
    // (1.5 km/h) + 2 min: standing still never earns time XP (the security
    // rules use the same limit)
    final maxActive = (km / 1.5 * 3600).round() + 120;
    final active = activeSeconds < maxActive ? activeSeconds : maxActive;
    final avg = movingKmh(km, active);
    final base = km * xpPerKm + active / 60 * xpPerActiveMinute;
    return (base * intensity(avg) * mult).round() + (bonusXp * mult).round();
  }

  static int coins({required double km, required double mult}) =>
      (km * coinsPerKm * mult).round();
}
