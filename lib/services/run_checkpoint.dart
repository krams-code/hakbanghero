import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// A snapshot of the run in progress, saved on the phone every few seconds.
///
/// If the app is closed, crashes, the phone dies, or Safari reloads the tab
/// mid-run, the next time the run screen opens the player can RESUME the run
/// or SAVE what was recorded, instead of losing it.
class RunCheckpoint {
  final String uid;
  final String modeId;
  final int startedAtMs;
  final int elapsedSeconds;
  final double distanceKm;
  final double activeSec;
  final double maxSpeedKmh;
  final bool useGps;
  final int userPick; // ActivityType index
  final List<Map<String, double>> route;
  final List<double> speeds;
  final int savedAtMs;

  const RunCheckpoint({
    required this.uid,
    required this.modeId,
    required this.startedAtMs,
    required this.elapsedSeconds,
    required this.distanceKm,
    required this.activeSec,
    required this.maxSpeedKmh,
    required this.useGps,
    required this.userPick,
    required this.route,
    required this.speeds,
    required this.savedAtMs,
  });

  DateTime get startedAt => DateTime.fromMillisecondsSinceEpoch(startedAtMs);
  DateTime get savedAt => DateTime.fromMillisecondsSinceEpoch(savedAtMs);

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'modeId': modeId,
        'startedAtMs': startedAtMs,
        'elapsedSeconds': elapsedSeconds,
        'distanceKm': distanceKm,
        'activeSec': activeSec,
        'maxSpeedKmh': maxSpeedKmh,
        'useGps': useGps,
        'userPick': userPick,
        'route': route,
        'speeds': speeds,
        'savedAtMs': savedAtMs,
      };

  factory RunCheckpoint.fromJson(Map<String, dynamic> j) => RunCheckpoint(
        uid: j['uid'] as String,
        modeId: j['modeId'] as String,
        startedAtMs: (j['startedAtMs'] as num).toInt(),
        elapsedSeconds: (j['elapsedSeconds'] as num).toInt(),
        distanceKm: (j['distanceKm'] as num).toDouble(),
        activeSec: (j['activeSec'] as num).toDouble(),
        maxSpeedKmh: (j['maxSpeedKmh'] as num).toDouble(),
        useGps: j['useGps'] as bool? ?? true,
        userPick: (j['userPick'] as num?)?.toInt() ?? 0,
        route: [
          for (final p in (j['route'] as List? ?? const []))
            Map<String, double>.from((p as Map).map(
                (k, v) => MapEntry(k.toString(), (v as num).toDouble()))),
        ],
        speeds: [
          for (final v in (j['speeds'] as List? ?? const []))
            (v as num).toDouble()
        ],
        savedAtMs: (j['savedAtMs'] as num).toInt(),
      );

  static const _key = 'run_checkpoint_v1';

  /// Older than this = not worth resuming (offered as SAVE only).
  static const Duration resumeWindow = Duration(hours: 3);

  /// Older than this = dropped silently.
  static const Duration keepFor = Duration(days: 3);

  static Future<void> save(RunCheckpoint c) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_key, jsonEncode(c.toJson()));
    } catch (e) {
      debugPrint('checkpoint save: $e');
    }
  }

  /// The unfinished run of [uid], if any.
  static Future<RunCheckpoint?> load(String uid) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_key);
      if (raw == null) return null;
      final c = RunCheckpoint.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      if (DateTime.now().difference(c.savedAt) > keepFor) {
        await clear();
        return null;
      }
      return c.uid == uid ? c : null;
    } catch (e) {
      debugPrint('checkpoint load: $e');
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_key);
    } catch (_) {}
  }
}

/// Keeps the screen on during a run. On the web (iPhone Safari) the GPS
/// stops when the screen locks, so this matters a lot there.
abstract final class ScreenAwake {
  static Future<void> on() async {
    try {
      await WakelockPlus.enable();
    } catch (e) {
      debugPrint('wakelock on: $e');
    }
  }

  static Future<void> off() async {
    try {
      await WakelockPlus.disable();
    } catch (e) {
      debugPrint('wakelock off: $e');
    }
  }
}
