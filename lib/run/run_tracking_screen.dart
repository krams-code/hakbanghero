import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' hide ActivityType;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:hakbanghero/models/activity_model.dart';
import 'package:hakbanghero/models/daily_quest_definitions.dart';

import '../widgets/block_ui.dart';
import '../widgets/pre_run_view.dart';
import '../widgets/session_views.dart';
import '../widgets/warmup_view.dart';

class RunTrackingScreen extends StatefulWidget {
  final VoidCallback? onExit;

  /// Called with `true` once the player leaves the pre-run screen
  /// (warm-up / live tracking / summary) and `false` when back on it.
  /// MainShell uses this to hide the bottom navigation bar mid-run.
  final ValueChanged<bool>? onActiveChanged;

  const RunTrackingScreen({
    super.key,
    this.onExit,
    this.onActiveChanged,
  });

  @override
  State<RunTrackingScreen> createState() => _RunTrackingScreenState();
}

class _RunTrackingScreenState extends State<RunTrackingScreen>
    with TickerProviderStateMixin {

  // ── State machine ──────────────────────────────────────────────────────────
  _Phase _phase = _Phase.preRun;

  ActivityType _userPick = ActivityType.run;

  // ── GPS / tracking ─────────────────────────────────────────────────────────
  StreamSubscription<Position>? _positionSub;

  Position? _lastPosition;

  double _distanceKm = 0;
  double _currentSpeedKmh = 0;
  double _maxSpeedKmh = 0;

  final List<double> _speedSamples = [];
  final List<Map<String, double>> _routePoints = [];

  // ── Timer ──────────────────────────────────────────────────────────────────
  Timer? _timer;

  int _elapsedSeconds = 0;

  bool _isPaused = false;
  DateTime? _lastMoveAt;

  // ── Animations ─────────────────────────────────────────────────────────────
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;

  late AnimationController _fadeCtrl;
  late Animation<double> _fade;

  // ── Saving ─────────────────────────────────────────────────────────────────
  bool _isSaving = false;

  bool? _lastActive;

  // Quests completed during this save
  List<DailyQuest> _newlyCompletedQuests = [];

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulse = Tween<double>(
      begin: 0.85,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _pulseCtrl,
        curve: Curves.easeInOut,
      ),
    );

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _fade = CurvedAnimation(
      parent: _fadeCtrl,
      curve: Curves.easeOut,
    );

    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _timer?.cancel();

    _pulseCtrl.dispose();
    _fadeCtrl.dispose();

    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  ActivityType get _detectedType =>
      ActivityTypeExt.fromSpeed(_currentSpeedKmh);

  ActivityType get _effectiveType =>
      _currentSpeedKmh > 0.5
          ? _detectedType
          : _userPick;

  /// True while GPS reported real movement in the last few seconds.
  bool get _isMoving =>
      !_isPaused &&
      _lastMoveAt != null &&
      DateTime.now().difference(_lastMoveAt!).inSeconds < 4;

  String get _formattedTime {
    final h = _elapsedSeconds ~/ 3600;
    final m = (_elapsedSeconds % 3600) ~/ 60;
    final s = _elapsedSeconds % 60;

    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:'
          '${m.toString().padLeft(2, '0')}:'
          '${s.toString().padLeft(2, '0')}';
    }

    return '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }

  String get _pace {
    if (_distanceKm <= 0 || _elapsedSeconds <= 0) {
      return '--:--';
    }

    final secsPerKm = _elapsedSeconds / _distanceKm;

    final m = secsPerKm ~/ 60;
    final s = (secsPerKm % 60).toInt();

    return "${m}'${s.toString().padLeft(2, '0')}\"";
  }

  double get _avgSpeed {
    if (_speedSamples.isEmpty) {
      return 0;
    }

    return _speedSamples.reduce((a, b) => a + b) /
        _speedSamples.length;
  }

  // ── EXIT ───────────────────────────────────────────────────────────────────

  void _exitRunScreen() {
    _positionSub?.cancel();
    _timer?.cancel();

    if (widget.onExit != null) {
      widget.onExit!();
    }
  }

  // ── PRE-RUN → WARM-UP ─────────────────────────────────────────────────────

  void _startWarmUp() {
    setState(() {
      _phase = _Phase.warmUp;
    });
  }

  void _skipWarmUp() {
    _startTracking();
  }

  // ── Permissions ────────────────────────────────────────────────────────────

  Future<bool> _requestPermission() async {
    final serviceEnabled =
        await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      if (mounted) {
        _showSnack(
          'Please enable GPS/Location services on your device.',
        );
      }

      return false;
    }

    LocationPermission permission =
        await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission =
          await Geolocator.requestPermission();

      if (permission == LocationPermission.denied) {
        if (mounted) {
          _showSnack('Location permission denied.');
        }

        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        _showSnack(
          'Location permission permanently denied. '
          'Enable it in settings.',
        );
      }

      return false;
    }

    return true;
  }

  // ── START TRACKING ─────────────────────────────────────────────────────────

  Future<void> _startTracking() async {
    final granted = await _requestPermission();

    if (!granted) {
      return;
    }

    _positionSub?.cancel();
    _timer?.cancel();

    setState(() {
      _phase = _Phase.tracking;

      _distanceKm = 0;
      _currentSpeedKmh = 0;
      _maxSpeedKmh = 0;

      _elapsedSeconds = 0;

      _isPaused = false;

      _speedSamples.clear();
      _routePoints.clear();

      _lastPosition = null;
      _lastMoveAt = null;

      _newlyCompletedQuests = [];
    });

    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (!_isPaused && mounted) {
          setState(() {
            _elapsedSeconds++;
          });
        }
      },
    );

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 5,
    );

    _positionSub = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      (Position pos) {
        if (!mounted || _isPaused) {
          return;
        }

        final speedKmh =
            (pos.speed * 3.6).clamp(0.0, 60.0);

        if (_lastPosition != null) {
          final delta = Geolocator.distanceBetween(
                _lastPosition!.latitude,
                _lastPosition!.longitude,
                pos.latitude,
                pos.longitude,
              ) /
              1000.0;

          // Ignore GPS noise and impossible jumps.
          if (delta > 0.002 && delta < 0.05) {
            setState(() {
              _distanceKm += delta;
              _lastMoveAt = DateTime.now();

              _currentSpeedKmh = speedKmh;

              if (speedKmh > _maxSpeedKmh) {
                _maxSpeedKmh = speedKmh;
              }

              _speedSamples.add(speedKmh);

              _routePoints.add({
                'lat': pos.latitude,
                'lng': pos.longitude,
              });
            });
          }
        }

        _lastPosition = pos;
      },
    );
  }

  // ── PAUSE ──────────────────────────────────────────────────────────────────

  void _togglePause() {
    setState(() {
      _isPaused = !_isPaused;
    });

    if (_isPaused) {
      _positionSub?.pause();
    } else {
      _positionSub?.resume();
    }
  }

  // ── STOP & SAVE ────────────────────────────────────────────────────────────

  Future<void> _stopAndSave() async {
    _positionSub?.cancel();
    _timer?.cancel();

    // Determine final activity type by majority vote of speed samples.
    ActivityType finalType = _userPick;

    if (_speedSamples.isNotEmpty) {
      int walkCount = 0;
      int jogCount = 0;
      int runCount = 0;

      for (final speed in _speedSamples) {
        final type =
            ActivityTypeExt.fromSpeed(speed);

        if (type == ActivityType.walk) {
          walkCount++;
        } else if (type == ActivityType.jog) {
          jogCount++;
        } else {
          runCount++;
        }
      }

      if (runCount >= jogCount &&
          runCount >= walkCount) {
        finalType = ActivityType.run;
      } else if (jogCount >= walkCount) {
        finalType = ActivityType.jog;
      } else {
        finalType = ActivityType.walk;
      }
    }

    final xp =
        (_distanceKm * 100 +
                _elapsedSeconds / 60 * 5)
            .toInt();

    final coins =
        (_distanceKm * 10).toInt();

    final sessionStart =
        DateTime.now().subtract(
      Duration(seconds: _elapsedSeconds),
    );

    final session = ActivitySession(
      id: '',
      type: finalType,
      userPick: _userPick,
      startTime: sessionStart,
      endTime: DateTime.now(),
      distanceKm:
          double.parse(
        _distanceKm.toStringAsFixed(3),
      ),
      durationSeconds: _elapsedSeconds,
      avgSpeedKmh:
          double.parse(
        _avgSpeed.toStringAsFixed(2),
      ),
      maxSpeedKmh:
          double.parse(
        _maxSpeedKmh.toStringAsFixed(2),
      ),
      xpEarned: xp,
      coinsEarned: coins,
      routePoints: _routePoints,
    );

    setState(() {
      _phase = _Phase.summary;
      _isSaving = true;
    });

    try {
      final user =
          FirebaseAuth.instance.currentUser;

      if (user != null) {
        final db =
            FirebaseFirestore.instance;

        final userRef =
            db.collection('users').doc(user.uid);

        final actRef =
            userRef.collection('activities');

        // 1. Save activity document.
        await actRef.add(
          session.toFirestore(),
        );

        // 2. Update user totals.
        await userRef.update({
          'total_km':
              FieldValue.increment(
            session.distanceKm,
          ),
          'total_sessions':
              FieldValue.increment(1),
          'xp':
              FieldValue.increment(xp),
          'coins':
              FieldValue.increment(coins),
        });

        // 3. Daily quest transaction.
        final todayStr =
            _todayDateString();

        final completedQuests =
            <DailyQuest>[];

        await db.runTransaction(
          (txn) async {
            final snap =
                await txn.get(userRef);

            final data =
                snap.data() ?? {};

            final storedDate =
                data['daily_progress_date']
                        as String? ??
                    '';

            double dailyKm =
                (data['daily_progress_km']
                            as num?)
                        ?.toDouble() ??
                    0.0;

            Map<String, dynamic> claimedMap =
                Map<String, dynamic>.from(
              data['daily_quests_claimed']
                      as Map? ??
                  {},
            );

            // Reset daily progress.
            if (storedDate != todayStr) {
              dailyKm = 0.0;
              claimedMap = {};
            }

            // Add session distance.
            dailyKm +=
                session.distanceKm;

            int crystalsToAdd = 0;

            // Check quest thresholds.
            for (final quest
                in kDailyQuests) {
              if (claimedMap[quest.id] ==
                  true) {
                continue;
              }

              if (quest.beforeHour != null &&
                  sessionStart.hour >=
                      quest.beforeHour!) {
                continue;
              }

              if (dailyKm >=
                  quest.thresholdKm) {
                claimedMap[quest.id] =
                    true;

                crystalsToAdd +=
                    quest.crystalReward;

                completedQuests.add(
                  quest,
                );
              }
            }

            final Map<String, dynamic>
                updates = {
              'daily_progress_km':
                  dailyKm,
              'daily_progress_date':
                  todayStr,
              'daily_quests_claimed':
                  claimedMap,
            };

            if (crystalsToAdd > 0) {
              updates['gems'] =
                  FieldValue.increment(
                crystalsToAdd,
              );
            }

            txn.update(
              userRef,
              updates,
            );
          },
        );

        _newlyCompletedQuests =
            completedQuests;
      }
    } catch (e) {
      debugPrint(
        'Error saving activity: $e',
      );
    }

    if (mounted) {
      setState(() {
        _isSaving = false;
      });
    }

    _showSummarySheet(session);
  }

  String _todayDateString() {
    final now = DateTime.now();

    return '${now.year}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  // ── SUMMARY ────────────────────────────────────────────────────────────────

  void _showSummarySheet(
    ActivitySession session,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      builder: (_) => SessionSummarySheet(
        session: session,
        isSaving: _isSaving,
        completedQuests:
            _newlyCompletedQuests,
        onDone: () {
          Navigator.of(context).pop();

          // Do NOT Navigator.pop() the RunTrackingScreen.
          // It lives inside MainShell's IndexedStack.
          if (mounted) {
            setState(() {
              _phase = _Phase.preRun;
              _distanceKm = 0;
              _currentSpeedKmh = 0;
              _maxSpeedKmh = 0;
              _elapsedSeconds = 0;
              _isPaused = false;
              _lastPosition = null;
              _speedSamples.clear();
              _routePoints.clear();
            });
          }
        },
      ),
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Rb.panel,
      ),
    );
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Tell the shell whether a run is in progress (anything past pre-run).
    final active = _phase != _Phase.preRun;
    if (active != _lastActive) {
      _lastActive = active;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onActiveChanged?.call(active);
      });
    }

    return Scaffold(
      backgroundColor: Rb.bg,
      body: FadeTransition(
        opacity: _fade,
        child: _buildCurrentPhase(),
      ),
    );
  }

  Widget _buildCurrentPhase() {
    switch (_phase) {
      case _Phase.preRun:
        return _buildPreRun();

      case _Phase.warmUp:
        return WarmUpView(
          onComplete: _startTracking,
          onSkip: _skipWarmUp,
        );

      case _Phase.tracking:
        return _buildTracking();

      case _Phase.summary:
        return const SizedBox.shrink();
    }
  }

  // ── PRE-RUN ────────────────────────────────────────────────────────────────

  Widget _buildPreRun() {
    return PreRunView(
      selected: _userPick,
      onSelect: (type) {
        setState(() {
          _userPick = type;
        });
      },
      onBack: _exitRunScreen,
      onStart: _startWarmUp,
    );
  }

  // ── ACTIVE TRACKING ────────────────────────────────────────────────────────

  Widget _buildTracking() {
    return TrackingView(
      type: _effectiveType,
      time: _formattedTime,
      speedKmh: _currentSpeedKmh,
      moving: _isMoving,
      paused: _isPaused,
      distanceKm: _distanceKm,
      pace: _pace,
      maxSpeedKmh: _maxSpeedKmh,
      onPause: _togglePause,
      onFinish: _confirmStop,
    );
  }

  // ── CONFIRM STOP ───────────────────────────────────────────────────────────

  void _confirmStop() {
    showFinishDialog(
      context,
      distanceKm: _distanceKm,
      time: _formattedTime,
      onFinish: _stopAndSave,
    );
  }
}

enum _Phase {
  preRun,
  warmUp,
  tracking,
  summary,
}
