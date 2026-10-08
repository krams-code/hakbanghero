/// Calendar-week helpers. A week runs Monday 00:00 -> Sunday 23:59 (device time).
/// Everything "weekly" (shop pick, streak rewards, weekly goal) keys off these so
/// they all reset at the same moment.
class Weekly {
  Weekly._();

  static DateTime monday(DateTime d) =>
      DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));

  /// "2026-10-05" – the Monday that starts [d]'s week. Stored in Firestore.
  static String key(DateTime d) {
    final m = monday(d);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${m.year}-${two(m.month)}-${two(m.day)}';
  }

  /// Whole weeks since 2024-01-01 (a Monday). Drives the rotation.
  static int index(DateTime d) {
    final m = monday(d);
    return DateTime.utc(m.year, m.month, m.day)
            .difference(DateTime.utc(2024, 1, 1))
            .inDays ~/
        7;
  }

  /// Time left until the next Monday 00:00.
  static Duration untilReset(DateTime now) =>
      monday(now).add(const Duration(days: 7)).difference(now);

  static String countdown(DateTime now) {
    final d = untilReset(now);
    if (d.inDays >= 1) return '${d.inDays}d ${d.inHours % 24}h left';
    return '${d.inHours}h ${d.inMinutes % 60}m left';
  }
}
