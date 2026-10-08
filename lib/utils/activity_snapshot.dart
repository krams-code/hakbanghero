import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hakbanghero/models/activity_model.dart';
import 'weekly.dart';

/// The few numbers the shop needs from the player's run history.
class ActivitySnapshot {
  final int streakDays;        // consecutive active days (today or yesterday)
  final DateTime? streakStart; // first day of the current streak
  final double weekKm;         // km since this Monday 00:00

  const ActivitySnapshot({
    this.streakDays = 0,
    this.streakStart,
    this.weekKm = 0,
  });

  static Future<ActivitySnapshot> load(String uid) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('activities')
          .orderBy('startTime', descending: true)
          .limit(120)
          .get();

      final sessions = <ActivitySession>[];
      for (final d in snap.docs) {
        try {
          sessions.add(ActivitySession.fromFirestore(d));
        } catch (_) {}
      }
      return fromSessions(sessions);
    } catch (_) {
      return const ActivitySnapshot();
    }
  }

  static ActivitySnapshot fromSessions(List<ActivitySession> sessions) {
    DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
    final now = DateTime.now();
    final today = day(now);
    final days = <DateTime>{for (final s in sessions) day(s.startTime)};

    var streak = 0;
    var cursor = days.contains(today) ? today : today.subtract(const Duration(days: 1));
    while (days.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    final start = streak > 0 ? cursor.add(const Duration(days: 1)) : null;

    final monday = Weekly.monday(now);
    final weekKm = sessions
        .where((s) => !s.startTime.isBefore(monday))
        .fold<double>(0, (a, s) => a + s.distanceKm);

    return ActivitySnapshot(streakDays: streak, streakStart: start, weekKm: weekKm);
  }
}
