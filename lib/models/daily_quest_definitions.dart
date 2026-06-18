// lib/models/daily_quest_definitions.dart
//
// Single source of truth for all daily quests.
// Only GPS-distance-based quests are defined here since the app
// tracks distance via Geolocator (no step counter integration).

import 'package:flutter/material.dart';

class DailyQuest {
  final String id;          // Firestore key used in daily_quests_claimed map
  final String title;
  final String description;
  final double thresholdKm; // distance in km required to complete
  final int crystalReward;  // gems awarded on completion
  final IconData icon;
  final Color color;

  // Optional: only counts if the run started before this hour (24h).
  // null means any time of day is valid.
  final int? beforeHour;

  const DailyQuest({
    required this.id,
    required this.title,
    required this.description,
    required this.thresholdKm,
    required this.crystalReward,
    required this.icon,
    required this.color,
    this.beforeHour,
  });
}

/// All active daily quests. Add or remove quests here — the rest of the
/// system (run_tracking_screen + home_screen) adapts automatically.
const List<DailyQuest> kDailyQuests = [
  DailyQuest(
    id: 'morning_strider',
    title: 'Morning Strider',
    description: 'Run 3 km before 9 AM',
    thresholdKm: 3.0,
    crystalReward: 30,
    icon: Icons.wb_sunny,
    color: Color(0xFFFFD700),
    beforeHour: 9,
  ),
  DailyQuest(
    id: 'distance_warrior',
    title: 'Distance Warrior',
    description: 'Cover 5 km today',
    thresholdKm: 5.0,
    crystalReward: 75,
    icon: Icons.bolt,
    color: Color(0xFF00FF41),
  ),
  DailyQuest(
    id: 'elite_runner',
    title: 'Elite Runner',
    description: 'Cover 10 km today',
    thresholdKm: 10.0,
    crystalReward: 150,
    icon: Icons.emoji_events,
    color: Color(0xFFFF6B35),
  ),
];