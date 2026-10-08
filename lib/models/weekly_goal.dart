import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/weekly.dart';
import 'activity_model.dart';

enum GoalMode { adaptive, fixed }

/// Weekly distance goal.
///  * ADAPTIVE: average of the player's last (up to) 4 COMPLETED weeks + 10%,
///    rounded up to 0.5 km, never below [minKm].
///  * FIXED: the same [fixedKm] for everyone (control condition).
class WeeklyGoal {
  static const double minKm = 2.0;
  static const double fixedKm = 5.0;
  static const double growth = 0.10;
  static const int rewardGems = 50;

  final GoalMode mode;
  final double targetKm;
  final double baselineKm;   // 0 when there is no history yet
  final int weeksUsed;       // completed weeks the baseline came from
  final double weekKm;       // km so far this calendar week

  const WeeklyGoal({
    required this.mode,
    required this.targetKm,
    required this.baselineKm,
    required this.weeksUsed,
    required this.weekKm,
  });

  double get fraction => (weekKm / targetKm).clamp(0.0, 1.0).toDouble();
  bool get reached => weekKm >= targetKm;

  static GoalMode modeFrom(String? s) =>
      s == 'fixed' ? GoalMode.fixed : GoalMode.adaptive;

  static WeeklyGoal compute(
    List<ActivitySession> sessions,
    GoalMode mode, {
    DateTime? now,
  }) {
    final t = now ?? DateTime.now();
    final thisMonday = Weekly.monday(t);

    final weekKm = sessions
        .where((s) => !s.startTime.isBefore(thisMonday))
        .fold<double>(0, (a, s) => a + s.distanceKm);

    // km per completed week, newest first (1 = last week ... 4)
    final firstMonday = sessions.isEmpty
        ? null
        : Weekly.monday(
            sessions.map((s) => s.startTime).reduce((a, b) => a.isBefore(b) ? a : b));
    final weeks = <double>[];
    for (var w = 1; w <= 4; w++) {
      final start = thisMonday.subtract(Duration(days: 7 * w));
      final end = start.add(const Duration(days: 7));
      // don't count weeks from before the player started (would punish new users)
      if (firstMonday == null || start.isBefore(firstMonday)) continue;
      weeks.add(sessions
          .where((s) => !s.startTime.isBefore(start) && s.startTime.isBefore(end))
          .fold<double>(0, (a, s) => a + s.distanceKm));
    }
    final baseline =
        weeks.isEmpty ? 0.0 : weeks.reduce((a, b) => a + b) / weeks.length;

    double target;
    if (mode == GoalMode.fixed) {
      target = fixedKm;
    } else {
      final raw = baseline * (1 + growth);
      target = raw < minKm ? minKm : (raw * 2).ceil() / 2.0; // round UP to 0.5
    }
    return WeeklyGoal(
      mode: mode,
      targetKm: target,
      baselineKm: baseline,
      weeksUsed: weeks.length,
      weekKm: weekKm,
    );
  }

  static Future<List<ActivitySession>> loadSessions(String uid) async {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('activities')
        .orderBy('startTime', descending: true)
        .limit(150)
        .get();
    final out = <ActivitySession>[];
    for (final d in snap.docs) {
      try {
        out.add(ActivitySession.fromFirestore(d));
      } catch (_) {}
    }
    return out;
  }
}
