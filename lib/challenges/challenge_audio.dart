import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'challenge_engine.dart';

/// Sound + haptics for the sudden challenges.
///
///   started   -> siren (assets/audio/challenge_alarm.wav) + heavy buzz
///   succeeded -> victory jingle
///   failed    -> sad descending notes
///
/// Never throws. If the audio plugin is unavailable, or the browser blocks
/// autoplay (Flutter web), it falls back to the system alert sound and
/// vibration, so a challenge is never silent AND never crashes the run.
class ChallengeAudio {
  ChallengeAudio._();
  static final ChallengeAudio instance = ChallengeAudio._();

  // `AssetSource` paths are relative to the `assets/` folder.
  static const String alarmAsset = 'audio/challenge_alarm.wav';
  static const String successAsset = 'audio/challenge_success.wav';
  static const String failAsset = 'audio/challenge_fail.wav';

  AudioPlayer? _player;

  Future<void> onEvent(ChallengeEvent e) {
    switch (e.type) {
      case ChallengeEventType.started:
        HapticFeedback.heavyImpact();
        return _play(alarmAsset, alert: true);
      case ChallengeEventType.succeeded:
        HapticFeedback.mediumImpact();
        return _play(successAsset);
      case ChallengeEventType.failed:
        HapticFeedback.lightImpact();
        return _play(failAsset);
    }
  }

  Future<void> _play(String asset, {bool alert = false}) async {
    try {
      final p = _player ??= AudioPlayer();
      await p.stop();
      await p.setReleaseMode(ReleaseMode.stop);
      await p.play(AssetSource(asset));
    } catch (e) {
      if (kDebugMode) debugPrint('ChallengeAudio fallback: $e');
      if (alert) {
        try {
          await SystemSound.play(SystemSoundType.alert);
          await HapticFeedback.vibrate();
        } catch (_) {}
      }
    }
  }

  /// Silence everything (call when the run ends).
  Future<void> stop() async {
    try {
      await _player?.stop();
    } catch (_) {}
  }

  Future<void> dispose() async {
    try {
      await _player?.dispose();
    } catch (_) {}
    _player = null;
  }
}
