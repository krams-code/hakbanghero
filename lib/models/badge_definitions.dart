// lib/models/badge_definitions.dart
//
// Achievement badges. Nothing is stored: every badge is worked out from data
// the app already keeps (user totals + run history), so there are no new
// Firestore fields or rules and a badge can never be "granted" by tampering.

import 'package:hakbanghero/models/activity_model.dart';
import 'package:hakbanghero/utils/player_stats.dart' show LevelProgress;

/// The numbers the badges are measured against.
class BadgeStats {
  final int sessions;
  final double totalKm;
  final int level;
  final double longestRunKm;
  final int bestPaceSecsPerKm; // 0 = no pace yet
  final int longestStreakDays;
  final bool earlyBird; // a run that started before 07:00
  final bool nightOwl; // a run that started at 20:00 or later

  const BadgeStats({
    this.sessions = 0,
    this.totalKm = 0,
    this.level = 1,
    this.longestRunKm = 0,
    this.bestPaceSecsPerKm = 0,
    this.longestStreakDays = 0,
    this.earlyBird = false,
    this.nightOwl = false,
  });

  /// Only what any player can see on someone else's card.
  factory BadgeStats.fromPublic(Map<String, dynamic> user) => BadgeStats(
        sessions: (user['total_sessions'] as num?)?.toInt() ?? 0,
        totalKm: (user['total_km'] as num?)?.toDouble() ?? 0,
        level: LevelProgress.fromXp((user['xp'] as num?)?.toInt() ?? 0).level,
      );

  factory BadgeStats.from({
    required Map<String, dynamic> user,
    required List<ActivitySession> runs,
    required double longestRunKm,
    required int bestPaceSecsPerKm,
    required int longestStreakDays,
  }) {
    return BadgeStats(
      sessions: (user['total_sessions'] as num?)?.toInt() ?? 0,
      totalKm: (user['total_km'] as num?)?.toDouble() ?? 0,
      level: LevelProgress.fromXp((user['xp'] as num?)?.toInt() ?? 0).level,
      longestRunKm: longestRunKm,
      bestPaceSecsPerKm: bestPaceSecsPerKm,
      longestStreakDays: longestStreakDays,
      earlyBird: runs.any((s) => s.startTime.hour < 7),
      nightOwl: runs.any((s) => s.startTime.hour >= 20),
    );
  }
}

class AppBadge {
  final String id;
  final String emoji;
  final String title;
  final String description;

  /// True when it can be worked out from the public user document alone
  /// (sessions, total km, level), so it can also be shown on other players' cards.
  final bool public;

  /// 0..1 progress toward the badge (1 = unlocked).
  final double Function(BadgeStats) progress;

  /// Short progress line shown under the bar, e.g. "3 / 5 runs".
  final String Function(BadgeStats) progressText;

  const AppBadge({
    required this.id,
    required this.emoji,
    required this.title,
    required this.description,
    required this.progress,
    required this.progressText,
    this.public = false,
  });

  /// Pixel-art picture for this badge.
  String get asset => 'assets/images/badges/$id.png';

  bool unlocked(BadgeStats s) => progress(s) >= 1.0;
}

double _ratio(num value, num target) =>
    target <= 0 ? 1.0 : (value / target).clamp(0.0, 1.0).toDouble();

String _km(double v) => v.toStringAsFixed(v >= 10 ? 0 : 1);

String _pace(int secs) =>
    "${secs ~/ 60}'${(secs % 60).toString().padLeft(2, '0')}\"";

AppBadge _runs(String id, String emoji, String title, int n) => AppBadge(
      id: id,
      emoji: emoji,
      title: title,
      description: 'Finish $n ${n == 1 ? 'session' : 'sessions'}',
      progress: (s) => _ratio(s.sessions, n),
      progressText: (s) => '${s.sessions.clamp(0, n)} / $n sessions',
      public: true,
    );

AppBadge _longest(String id, String emoji, String title, double km) => AppBadge(
      id: id,
      emoji: emoji,
      title: title,
      description: 'Cover ${_km(km)} km in one session',
      progress: (s) => _ratio(s.longestRunKm, km),
      progressText: (s) =>
          '${_km(s.longestRunKm.clamp(0, km).toDouble())} / ${_km(km)} km',
    );

AppBadge _total(String id, String emoji, String title, double km) => AppBadge(
      id: id,
      emoji: emoji,
      title: title,
      description: 'Reach ${_km(km)} km in total',
      progress: (s) => _ratio(s.totalKm, km),
      progressText: (s) =>
          '${_km(s.totalKm.clamp(0, km).toDouble())} / ${_km(km)} km',
      public: true,
    );

AppBadge _streak(String id, String emoji, String title, int days) => AppBadge(
      id: id,
      emoji: emoji,
      title: title,
      description: 'Be active $days days in a row',
      progress: (s) => _ratio(s.longestStreakDays, days),
      progressText: (s) => '${s.longestStreakDays.clamp(0, days)} / $days days',
    );

AppBadge _level(String id, String emoji, String title, int lv) => AppBadge(
      id: id,
      emoji: emoji,
      title: title,
      description: 'Reach level $lv',
      progress: (s) => _ratio(s.level, lv),
      progressText: (s) => 'LV ${s.level.clamp(1, lv)} / $lv',
      public: true,
    );

/// 13 badges, in the order they are shown.
final List<AppBadge> kBadges = [
  _runs('first_steps', '👟', 'FIRST STEPS', 1),
  _runs('warming_up', '🔥', 'WARMING UP', 5),
  _runs('regular', '📅', 'REGULAR', 25),
  _longest('five_k', '🥉', '5K CLUB', 5),
  _longest('ten_k', '🥇', '10K HERO', 10),
  _total('road_warrior', '🛣️', 'ROAD WARRIOR', 50),
  _total('centurion', '💯', 'CENTURION', 100),
  _streak('on_fire', '⚡', 'ON FIRE', 3),
  _streak('unstoppable', '🚀', 'UNSTOPPABLE', 7),
  AppBadge(
    id: 'speedster',
    emoji: '💨',
    title: 'SPEEDSTER',
    description: "Hit a best pace of 5'30\" per km or faster",
    progress: (s) => s.bestPaceSecsPerKm <= 0
        ? 0.0
        : (330 / s.bestPaceSecsPerKm).clamp(0.0, 1.0).toDouble(),
    progressText: (s) => s.bestPaceSecsPerKm <= 0
        ? 'No pace yet'
        : "Best ${_pace(s.bestPaceSecsPerKm)} / 5'30\"",
  ),
  AppBadge(
    id: 'early_bird',
    emoji: '🌅',
    title: 'EARLY BIRD',
    description: 'Start a session before 7 AM',
    progress: (s) => s.earlyBird ? 1.0 : 0.0,
    progressText: (s) => s.earlyBird ? 'Done!' : 'Not yet',
  ),
  AppBadge(
    id: 'night_owl',
    emoji: '🌙',
    title: 'NIGHT OWL',
    description: 'Start a session at 8 PM or later',
    progress: (s) => s.nightOwl ? 1.0 : 0.0,
    progressText: (s) => s.nightOwl ? 'Done!' : 'Not yet',
  ),
  _level('rising_hero', '⭐', 'RISING HERO', 5),
];
