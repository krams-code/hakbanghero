/// Single source of truth for Combat Power (CP) calculation.
/// Used by Profile, Equipment, and Boss Fight screens so "your CP"
/// always means the same number everywhere.
class CombatPower {
  CombatPower._();

  /// [level] from the user doc.
  /// [equippedStats] should be the summed atk/def/spd/hp across all
  /// equipped gear (pass 0s if you don't have gear data loaded).
  static int calculate({
    required int level,
    int totalAtk = 0,
    int totalDef = 0,
    int totalSpd = 0,
    int totalHp = 0,
  }) {
    final base = 1200 + (level * 42);
    final gearBonus = (totalAtk * 2) + totalDef + (totalSpd * 1.5).round() + (totalHp * 0.3).round();
    return base + gearBonus;
  }

  /// Win chance (0.0–1.0) for a fight against a boss of the given power.
  /// Clamped so no fight is ever a guaranteed win or guaranteed loss —
  /// keeps low-level players hopeful and high-level players honest.
  static double winChance(int playerCp, int bossPower) {
    final raw = playerCp / (playerCp + bossPower);
    return raw.clamp(0.05, 0.95);
  }
}