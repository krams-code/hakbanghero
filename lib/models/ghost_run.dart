import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'activity_model.dart';

/// A replay of the player's own fastest run, used as the opponent in a
/// "ghost race". Stored sessions only keep totals (no per-point timestamps),
/// so the ghost moves at that run's constant average pace.
class GhostRun {
  final double distanceKm;
  final int durationSeconds;
  final DateTime date;

  const GhostRun({
    required this.distanceKm,
    required this.durationSeconds,
    required this.date,
  });

  double get speedKmh => distanceKm / (durationSeconds / 3600.0);
  double get secsPerKm => durationSeconds / distanceKm;

  /// Where the ghost is after [seconds] (stops at the finish).
  double distanceAt(int seconds) =>
      math.min(distanceKm, distanceKm * seconds / durationSeconds);

  String get paceText => _pace(secsPerKm);

  String get label =>
      'PB ${distanceKm.toStringAsFixed(2)} km @ $paceText/km';

  static String _pace(double secsPerKm) {
    if (secsPerKm.isNaN || secsPerKm.isInfinite) return "--'--\"";
    final m = secsPerKm ~/ 60;
    final s = (secsPerKm % 60).round().toString().padLeft(2, '0');
    return "$m'$s\"";
  }

  /// Fastest qualifying run (>= 0.5 km, >= 2 min, plausible speed).
  static GhostRun? best(Iterable<ActivitySession> sessions) {
    GhostRun? best;
    for (final s in sessions) {
      if (s.distanceKm < 0.5 || s.durationSeconds < 120) continue;
      final g = GhostRun(
        distanceKm: s.distanceKm,
        durationSeconds: s.durationSeconds,
        date: s.startTime,
      );
      if (g.speedKmh > 25) continue; // GPS glitch
      if (best == null || g.speedKmh > best.speedKmh) best = g;
    }
    return best;
  }

  static Future<GhostRun?> loadBest(String uid) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('activities')
          .orderBy('startTime', descending: true)
          .limit(120)
          .get();
      final list = <ActivitySession>[];
      for (final d in snap.docs) {
        try {
          list.add(ActivitySession.fromFirestore(d));
        } catch (_) {}
      }
      return best(list);
    } catch (_) {
      return null;
    }
  }
}

/// Outcome of a ghost race, computed when the run ends.
class GhostResult {
  final bool won;
  final double gapKm;      // + = you were ahead at the finish
  final double paceDelta;  // seconds per km faster (+) / slower (-) than ghost

  const GhostResult({
    required this.won,
    required this.gapKm,
    required this.paceDelta,
  });

  static const int winGems = 15;

  /// Null when the run was too short to judge.
  static GhostResult? judge(GhostRun? ghost, double km, int seconds) {
    if (ghost == null || km < 0.1 || seconds < 30) return null;
    final yourPace = seconds / km;
    final gap = km - ghost.distanceAt(seconds);
    final won = yourPace < ghost.secsPerKm && gap > 0;
    return GhostResult(
      won: won,
      gapKm: gap,
      paceDelta: ghost.secsPerKm - yourPace,
    );
  }

  Map<String, dynamic> toMap() => {
        'won': won,
        'gap_m': (gapKm * 1000).round(),
        'pace_delta_s': paceDelta.round(),
      };
}
