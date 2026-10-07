import 'dart:math';

import 'activity_model.dart' show ActivityType;

/// One warm-up exercise: four strings, as specified.
class WarmUpExercise {
  final String id;
  final String name;

  /// Pixel icon shown on the left of the row.
  final String iconPath;

  /// Looping 16-bit demo (GIF) shown in the preview window on the right.
  final String demoPath;

  const WarmUpExercise({
    required this.id,
    required this.name,
    required this.iconPath,
    required this.demoPath,
  });
}

/// An exercise plus what the routine screen needs around it.
class WarmUpEntry {
  final WarmUpExercise exercise;
  final String description;
  final Set<ActivityType> forTypes;
  const WarmUpEntry(this.exercise, this.description, this.forTypes);
}

const String _demo = 'assets/images/warmup';
const String _ico = 'assets/images/icons';

const _w = ActivityType.walk;
const _j = ActivityType.jog;
const _r = ActivityType.run;

/// The whole exercise database (8 exercises, 7 shared mini-icons).
/// Add a line (+ a GIF) to add an exercise.
const List<WarmUpEntry> kWarmUpPool = [
  WarmUpEntry(
    WarmUpExercise(
        id: 'easy_march', name: 'Easy March',
        demoPath: '$_demo/demo_march.gif', iconPath: '$_ico/icon_shoe.png'),
    'March gently in place. Keep your movements relaxed.',
    {_w, _j},
  ),
  WarmUpEntry(
    WarmUpExercise(
        id: 'ankle_circles', name: 'Ankle Circles',
        demoPath: '$_demo/demo_ankle.gif', iconPath: '$_ico/icon_shoe.png'),
    'Slowly rotate each ankle. Switch direction halfway through.',
    {_w, _j, _r},
  ),
  WarmUpEntry(
    WarmUpExercise(
        id: 'leg_swings', name: 'Leg Swings',
        demoPath: '$_demo/demo_swings.gif', iconPath: '$_ico/icon_bolt.png'),
    'Hold on for balance and swing each leg out and across. Do not force it.',
    {_w, _j, _r},
  ),
  WarmUpEntry(
    WarmUpExercise(
        id: 'high_knees', name: 'High Knees',
        demoPath: '$_demo/demo_high_knees_v2.gif', iconPath: '$_ico/icon_fire.png'),
    'Drive your knees up to hip height, pumping your arms.',
    {_j, _r},
  ),
  WarmUpEntry(
    WarmUpExercise(
        id: 'butt_kicks', name: 'Butt Kicks',
        demoPath: '$_demo/demo_butt_kicks_v2.gif', iconPath: '$_ico/icon_fire.png'),
    'Flick each heel up toward your glutes, one leg after the other.',
    {_j, _r},
  ),
  WarmUpEntry(
    WarmUpExercise(
        id: 'calf_stretches', name: 'Calf Stretches',
        demoPath: '$_demo/demo_calf.gif', iconPath: '$_ico/icon_shield.png'),
    'Press into a wall with one leg back and heel down. Hold the stretch.',
    {_w, _j, _r},
  ),
  WarmUpEntry(
    WarmUpExercise(
        id: 'knee_hugs', name: 'Knee Hugs',
        demoPath: '$_demo/demo_hugs.gif', iconPath: '$_ico/icon_burst.png'),
    'Pull your knees toward your chest, then extend. Breathe steadily.',
    {_w, _j, _r},
  ),
  WarmUpEntry(
    WarmUpExercise(
        id: 'jog_in_place', name: 'Easy Jog-in-Place',
        demoPath: '$_demo/demo_jog.gif', iconPath: '$_ico/icon_shoe.png'),
    'Jog on the spot at a light pace and get ready to run.',
    {_j, _r},
  ),
];

/// Shuffles the pool and returns [count] UNIQUE exercises that suit [type].
/// Called every time the warm-up screen opens, so each session differs.
List<WarmUpEntry> pickWarmUpRoutine(
  ActivityType type, {
  int count = 4,
  Random? rng,
}) {
  final pool = kWarmUpPool.where((e) => e.forTypes.contains(type)).toList()
    ..shuffle(rng ?? Random());
  return pool.take(count).toList();
}
