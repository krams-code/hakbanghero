import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' hide ActivityType;
import 'package:geolocator/geolocator.dart' as geo show ActivityType;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/presence.dart';

import 'package:hakbanghero/models/activity_model.dart';
import 'package:hakbanghero/models/daily_quest_definitions.dart';
import 'package:hakbanghero/models/ghost_run.dart';
import '../models/run_mode.dart';
import '../services/run_saver.dart';
import '../services/sound.dart';
import '../utils/rewards.dart';

import '../challenges/challenge_audio.dart';
import '../challenges/challenge_engine.dart';
import '../models/tutorial_progress.dart';
import '../widgets/block_ui.dart';
import '../widgets/lottie_fx.dart';
import '../widgets/post_run_tutorial.dart';
import '../widgets/pre_run_view.dart';
import '../widgets/run_countdown.dart';
import '../widgets/session_views.dart';
import '../widgets/stage_briefing_view.dart';
import '../widgets/warmup_view.dart';

class RunTrackingScreen extends StatefulWidget {
  final VoidCallback? onExit;

  /// Called with `true` once the player leaves the pre-run screen
  /// (warm-up / live tracking / summary) and `false` when back on it.
  /// MainShell uses this to hide the bottom navigation bar mid-run.
  final ValueChanged<bool>? onActiveChanged;

  /// Switches the bottom-nav tab (0 SHOP, 3 RANKS, 4 ACTIVITY). Used by the
  /// post-run tutorial, which walks the player through those tabs.
  final ValueChanged<int>? onNavigate;

  const RunTrackingScreen({
    super.key,
    this.onExit,
    this.onActiveChanged,
    this.onNavigate,
  });

  @override
  State<RunTrackingScreen> createState() => _RunTrackingScreenState();
}

class _RunTrackingScreenState extends State<RunTrackingScreen>
    with TickerProviderStateMixin {

  // ── State machine ──────────────────────────────────────────────────────────
  _Phase _phase = _Phase.preRun;

  /// Warm-up difficulty follows the mode; the real type is detected from GPS.
  ActivityType _userPick = ActivityType.run;

  /// The mode chosen in the Mode Selection overlay (Stage rank or Endless).
  RunMode _mode = kNovice;

  /// Set once when the session is being ended (END SESSION, target reached or
  /// the stage clock ran out) so it can never be saved twice.
  bool _ending = false;
  String? _outcome; // "STAGE CLEARED!" / "TIME UP" / null
  bool _outcomeGood = false;

  // Stage record result of the run that just ended (shown on the summary)
  int _stageStars = 0;
  int _stageBonusCoins = 0;
  bool _stageFirstClear = false;
  RunMode? _unlockedRank; // next rank this clear just opened
  RunMode? _pendingNextRank; // set when NEXT RANK is tapped on the summary

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

  /// Wall-clock start of the run. Elapsed time is always now - start, so a
  /// locked screen / backgrounded browser (which slows timers) loses nothing.
  DateTime? _startedAt;

  /// Last GPS point that was COUNTED (distance is measured from here).
  Position? _anchor;

  /// Seconds of real movement, measured between counted GPS points.
  double _activeSec = 0;

  // ── Location check before the run (phase: locating) ──
  bool _useGps = true;
  bool _locBusy = false;
  String _locLabel = 'CHECKING LOCATION...';
  int _locTries = 0;
  Completer<void>? _firstFix;

  DateTime? _lastMoveAt;

  // ── Animations ─────────────────────────────────────────────────────────────
  late AnimationController _pulseCtrl;

  late AnimationController _fadeCtrl;
  late Animation<double> _fade;

  // ── Saving ─────────────────────────────────────────────────────────────────
  bool _isSaving = false;

  bool? _lastActive;

  // Quests completed during this save
  List<DailyQuest> _newlyCompletedQuests = [];

  // ── Sudden mid-run challenges (Sprint Blitz / Pace Keeper) ────────────────
  final ChallengeEngine _challenge = ChallengeEngine();
  List<ChallengeRecord> _summaryChallenges = [];

  // ── Ghost race (your own best run) ────────────────────────────────────────
  GhostRun? _ghost;          // personal best, loaded for the pre-run screen
  bool _ghostOn = true;      // player's opt-in
  GhostRun? _raceGhost;      // the ghost locked in when this run started
  GhostResult? _summaryGhost;

  Future<void> _loadGhost() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final g = await GhostRun.loadBest(uid);
    if (mounted) setState(() => _ghost = g);
  }

  @override
  void initState() {
    super.initState();
    Presence.I.holdActive(true); // a run in progress is never "idle"
    _loadGhost();

    _challenge.onEvent = (e) => ChallengeAudio.instance.onEvent(e);

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _fade = CurvedAnimation(
      parent: _fadeCtrl,
      curve: Curves.easeOut,
    );

    _fadeCtrl.forward();

    // Send any run that was saved on the phone while offline.
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) RunOutbox.flush(uid);
  }

  @override
  void dispose() {
    Presence.I.holdActive(false);
    _positionSub?.cancel();
    _timer?.cancel();

    _pulseCtrl.dispose();
    _fadeCtrl.dispose();

    _challenge.onEvent = null;
    _challenge.dispose();
    ChallengeAudio.instance.stop();

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

    return "$m'${s.toString().padLeft(2, '0')}\"";
  }

  /// Average speed while moving (distance / moving time), km/h.
  double get _avgSpeed {
    if (_activeSec >= 10 && _distanceKm > 0) {
      return _distanceKm / (_activeSec / 3600);
    }
    if (_speedSamples.isEmpty) return 0;
    return _speedSamples.reduce((a, b) => a + b) / _speedSamples.length;
  }

  // ── EXIT ───────────────────────────────────────────────────────────────────

  void _exitRunScreen() {
    _positionSub?.cancel();
    _timer?.cancel();
    ChallengeAudio.instance.stop();

    if (widget.onExit != null) {
      widget.onExit!();
    }
  }

  // ── PRE-RUN → WARM-UP ─────────────────────────────────────────────────────

  /// A mode was chosen in the overlay: remember it and head to the warm-up.
  void _onModePicked(RunMode mode) {
    setState(() {
      _applyMode(mode);
      // Stage ranks get a briefing card first; Endless goes straight on.
      _phase = mode.isStage ? _Phase.briefing : _Phase.warmUp;
    });
  }

  void _applyMode(RunMode mode) {
    _mode = mode;
    // warm-up intensity follows the rank (GPS decides the real type)
    _userPick = mode.id == kNovice.id
        ? ActivityType.walk
        : mode.id == kSlayer.id
            ? ActivityType.run
            : ActivityType.jog;
  }

  /// NEXT RANK on the summary: close it and land on the new rank's briefing.
  Future<void> _onNextRank() async {
    final next = _unlockedRank;
    if (next == null) return;
    _pendingNextRank = next;
    // the player already saw it unlocked: retire the NEW! badge
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      FirebaseFirestore.instance.collection('users').doc(uid).update({
        'stage_seen': FieldValue.arrayUnion([next.id]),
      }).catchError((_) {});
    }
    await _onSummaryDone();
  }

  void _skipWarmUp() {
    _beginCountdown();
  }

  /// Warm-up finished (or skipped): sort out location FIRST. Nothing runs
  /// (no timer, no countdown) until GPS is ready or the player picks
  /// RUN WITHOUT GPS. Then 3-2-1, then the run.
  void _beginCountdown() {
    if (_phase == _Phase.locating ||
        _phase == _Phase.countdown ||
        _phase == _Phase.tracking) {
      return;
    }
    setState(() {
      _phase = _Phase.locating;
      _permIssue = null;
      _locTries = 0;
    });
    _checkLocation();
  }

  /// Ask for location, start the GPS and wait (briefly) for a first fix.
  /// Shows a loading screen the whole time; TRY AGAIN runs this again.
  Future<void> _checkLocation() async {
    if (_locBusy) return;
    setState(() {
      _locBusy = true;
      _permIssue = null;
      _locLabel = 'CHECKING LOCATION...';
    });
    final shownAt = DateTime.now();
    final granted = await _requestPermission();
    if (granted && mounted && _phase == _Phase.locating) {
      setState(() => _locLabel = 'FINDING GPS SIGNAL...');
      _firstFix = Completer<void>();
      _startGpsStream();
      // a first fix gives the run its exact start point; never wait forever
      await _firstFix!.future
          .timeout(const Duration(seconds: 10), onTimeout: () {});
    }
    // keep the loader up long enough to be seen (no black flash)
    final shown = DateTime.now().difference(shownAt);
    const minShow = Duration(milliseconds: 900);
    if (shown < minShow) await Future<void>.delayed(minShow - shown);
    if (!mounted || _phase != _Phase.locating) return;
    setState(() {
      _locBusy = false;
      _locTries++;
      if (granted) {
        _useGps = true;
        _phase = _Phase.countdown;
      }
    });
  }

  /// Leave the location check / countdown without running.
  void _cancelStart() {
    _positionSub?.cancel();
    _positionSub = null;
    _anchor = null;
    setState(() {
      _locBusy = false;
      _phase = _mode.isStage ? _Phase.briefing : _Phase.preRun;
    });
  }

  // ── Permissions ────────────────────────────────────────────────────────────

  /// Why the last permission check failed: 'service' | 'denied' | 'forever'.
  String? _permIssue;

  // GPS chip: 0 timer-only, 1 searching, 2 weak, 3 good
  int _gpsStatus = 1;
  bool? _lastIntervalFast;

  /// Seconds you were actually moving (GPS saw you progress in the last 8 s).
  int _activeSeconds = 0;

  // Interval Run: km covered in each FAST block (index = round - 1)
  final List<double> _fastKm = List<double>.filled(RunMode.intervalRounds, 0.0);
  Map<String, dynamic>? _intervalStats;
  bool _intervalNewBest = false;

  Future<bool> _requestPermission() async {
    _permIssue = null;
    try {
      if (!await Geolocator.isLocationServiceEnabled()
          .timeout(const Duration(seconds: 6), onTimeout: () => true)) {
        _permIssue = 'service';
        return false;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission()
            .timeout(const Duration(seconds: 20),
                onTimeout: () => LocationPermission.denied);
      }
      if (permission == LocationPermission.deniedForever) {
        _permIssue = 'forever';
        return false;
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.unableToDetermine) {
        _permIssue = 'denied'; // prompt dismissed (X) or refused
        return false;
      }
      return true;
    } catch (_) {
      _permIssue = 'denied';
      return false;
    }
  }

  /// OPEN SETTINGS / HOW TO TURN ON.
  /// Phone app: jumps to the right settings page (iOS only allows the app's
  /// own page). Web (incl. iPhone Safari): a website can't open settings, so
  /// show step-by-step instructions instead of a button that does nothing.
  Future<void> _openLocationSettings(BuildContext ctx) async {
    if (!kIsWeb) {
      var opened = false;
      try {
        opened = (_permIssue == 'service' &&
                defaultTargetPlatform == TargetPlatform.android)
            ? await Geolocator.openLocationSettings()
            : await Geolocator.openAppSettings();
      } catch (_) {}
      if (opened) return;
    }
    if (!ctx.mounted) return;

    final ios = defaultTargetPlatform == TargetPlatform.iOS;
    final steps = _permIssue == 'service'
        ? (ios
            ? '1. Open the Settings app.\n'
                '2. Privacy & Security → Location Services.\n'
                '3. Turn Location Services ON.\n'
                '4. Come back and tap TRY AGAIN.'
            : '1. Swipe down from the top of the screen.\n'
                '2. Turn Location ON.\n'
                '3. Come back and tap TRY AGAIN.')
        : kIsWeb
            ? (ios
                ? '1. Open the Settings app.\n'
                    '2. Privacy & Security → Location Services.\n'
                    '3. Tap "Safari Websites" → choose "While Using the App".\n'
                    '4. In Safari, tap "aA" next to the address → Website '
                    'Settings → Location → Allow.\n'
                    '5. Come back and tap TRY AGAIN.'
                : '1. Tap the lock / settings icon next to the web address.\n'
                    '2. Permissions → Location → Allow.\n'
                    '3. Come back and tap TRY AGAIN.')
            : (ios
                ? '1. Open the Settings app.\n'
                    '2. Scroll down and tap HakbangHero.\n'
                    '3. Location → "While Using the App".\n'
                    '4. Come back and tap TRY AGAIN.'
                : '1. Open Settings → Apps → HakbangHero.\n'
                    '2. Permissions → Location → Allow.\n'
                    '3. Come back and tap TRY AGAIN.');

    await showDialog<void>(
      context: ctx,
      builder: (c) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Block(
          color: Rb.slate,
          edge: Rb.slateEdge,
          depth: 6,
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const BlockText('TURN ON LOCATION',
                  size: 18, stroke: 4, align: TextAlign.center),
              const SizedBox(height: 10),
              Text(
                steps,
                style: const TextStyle(
                  color: Color(0xFFD7DADD),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 12),
              PressBlock(
                color: Rb.blue,
                edge: Rb.blueEdge,
                depth: 5,
                radius: 12,
                padding: const EdgeInsets.symmetric(vertical: 12),
                onTap: () => Navigator.of(c).pop(),
                child: const SizedBox(
                  width: double.infinity,
                  child: Center(
                      child: BlockText('GOT IT', size: 14, stroke: 3.5)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Location check screen: a loader while checking, then (if blocked)
  /// the choices. Nothing is running yet.
  Widget _buildLocating() {
    if (_locBusy || _permIssue == null) {
      return SafeArea(child: LoadingRunner(label: _locLabel));
    }
    final forever = _permIssue == 'forever';
    final msg = _permIssue == 'service'
        ? 'Location services are turned off on this device.'
        : forever
            ? 'Location is blocked for HakbangHero. Turn it on in your '
                '${kIsWeb ? 'browser / phone' : 'phone'} settings, then tap TRY AGAIN.'
            : 'Location permission was not given.';

    Widget btn(String label, Color c, Color e, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: PressBlock(
            color: c,
            edge: e,
            depth: 5,
            radius: 12,
            padding: const EdgeInsets.symmetric(vertical: 13),
            onTap: onTap,
            child: SizedBox(
              width: double.infinity,
              child: Center(child: BlockText(label, size: 14, stroke: 3.5)),
            ),
          ),
        );

    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Block(
              color: Rb.slate,
              edge: Rb.slateEdge,
              depth: 6,
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const BlockText('LOCATION NEEDED',
                      size: 18, stroke: 4, align: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(
                    '$msg\n\nGPS measures your distance. The run has NOT '
                    'started yet: pick an option below.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFD7DADD),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                  if (_locTries > 1) ...[
                    const SizedBox(height: 6),
                    BlockText('STILL BLOCKED (TRIED $_locTries TIMES)',
                        size: 10.5,
                        stroke: 2.5,
                        color: const Color(0xFFFFB4A8),
                        align: TextAlign.center),
                  ],
                  const SizedBox(height: 6),
                  btn('TRY AGAIN', Rb.blue, Rb.blueEdge, _checkLocation),
                  if (forever || _permIssue == 'service')
                    btn(kIsWeb ? 'HOW TO TURN ON' : 'OPEN SETTINGS', Rb.gold,
                        Rb.goldEdge, () => _openLocationSettings(context)),
                  btn('RUN WITHOUT GPS (TIMER ONLY)', Rb.green, Rb.greenEdge, () {
                    setState(() {
                      _useGps = false;
                      _phase = _Phase.countdown;
                    });
                  }),
                  btn('BACK', const Color(0xFF6B7078), const Color(0xFF1B1D20),
                      _cancelStart),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── START TRACKING ─────────────────────────────────────────────────────────

  Future<void> _startTracking() async {
    final useGps = _useGps;
    if (!useGps) {
      _positionSub?.cancel();
      _positionSub = null;
    }
    _timer?.cancel();

    // Stage ranks fire their own events; Novice and Endless have none.
    _challenge.setup(_mode.challengeConfig);

    Sound.I.play(Sfx.go);
    final ph0 = _mode.isInterval ? RunMode.intervalAt(0) : null;
    Sound.I.music(ph0 != null && ph0.fast ? Bgm.sprint : Bgm.run);

    setState(() {
      _phase = _Phase.tracking;

      _distanceKm = 0;
      _currentSpeedKmh = 0;
      _maxSpeedKmh = 0;

      _elapsedSeconds = 0;

      _ending = false;
      _outcome = null;
      _outcomeGood = false;
      _stageStars = 0;
      _stageBonusCoins = 0;
      _stageFirstClear = false;
      _unlockedRank = null;

      _speedSamples.clear();
      _routePoints.clear();

      _lastPosition = null;
      _lastMoveAt = null;
      _activeSec = 0;
      // the warm-up fix is the start point of the route
      final a = _anchor;
      if (useGps && a != null) {
        _routePoints.add({'lat': a.latitude, 'lng': a.longitude});
      }
      _gpsStatus = !useGps ? 0 : (a == null ? 1 : (a.accuracy > 35 ? 2 : 3));
      _lastIntervalFast = null;
      _activeSeconds = 0;
      _fastKm.fillRange(0, _fastKm.length, 0.0);
      _intervalStats = null;
      _intervalNewBest = false;

      _newlyCompletedQuests = [];
      _summaryChallenges = [];
      _raceGhost = _ghostOn ? _ghost : null;
      _summaryGhost = null;
    });

    _startedAt = DateTime.now();
    _timer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) {
        if (!mounted || _startedAt == null) return;
        // wall clock: correct even after the screen was locked
        final e = DateTime.now().difference(_startedAt!).inSeconds;
        if (e == _elapsedSeconds) return;
        setState(() {
          _elapsedSeconds = e;
          _activeSeconds = math.min(_activeSec.round(), _elapsedSeconds);
          if (!_isMoving) _currentSpeedKmh = 0; // stopped: speed reads 0
        });
        _tickChallenge();
        _intervalCue();
        _checkStageLimits();
      },
    );
  }

  /// Best tracking settings per platform. Phone apps keep tracking with the
  /// screen off (Android: foreground notification; iPhone: background mode).
  LocationSettings _locationSettings() {
    if (kIsWeb) {
      return const LocationSettings(
          accuracy: LocationAccuracy.best, distanceFilter: 0);
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 1),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'HakbangHero is tracking your run',
          notificationText: 'Distance keeps counting with the screen off.',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        activityType: geo.ActivityType.fitness,
        distanceFilter: 0,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
      );
    }
    return const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 0);
  }

  /// Start listening to GPS (before the countdown, so the start point is
  /// known). Fixes only COUNT once the run is tracking.
  void _startGpsStream() {
    _positionSub?.cancel();
    _anchor = null;
    _positionSub = Geolocator.getPositionStream(
      locationSettings: _locationSettings(),
    ).listen(
      _onFix,
      onError: (Object _) {
        if (mounted && _phase == _Phase.tracking) {
          _showSnack('GPS signal lost. The timer keeps running.');
        }
      },
    );
  }

  /// One GPS reading.
  ///  * jitter: a point closer than ~half its accuracy to the last COUNTED
  ///    point is ignored, but the anchor stays put, so slow walking (1 m per
  ///    reading) still adds up instead of being thrown away bit by bit.
  ///  * gaps (screen locked): the whole gap counts if the speed was humanly
  ///    possible; impossible jumps are dropped.
  ///  * speed: the phone's value when it has one, else distance / time
  ///    (Safari usually reports none).
  void _onFix(Position pos) {
    if (!mounted) return;
    final ff = _firstFix;
    if (ff != null && !ff.isCompleted) ff.complete();

    final st = pos.accuracy > 35 ? 2 : 3;
    if (st != _gpsStatus && _phase == _Phase.tracking) {
      setState(() => _gpsStatus = st);
    }

    // Anti-cheat: mock-location points are ignored, and so are points too
    // inaccurate to trust (> 50 m).
    if (pos.isMocked || pos.accuracy > 50) return;

    final a = _anchor;
    if (a == null || _phase != _Phase.tracking || _ending) {
      _anchor = pos; // before the run: keep the freshest start point
      return;
    }

    final meters = Geolocator.distanceBetween(
        a.latitude, a.longitude, pos.latitude, pos.longitude);
    final minMove = (pos.accuracy * 0.5).clamp(3.0, 15.0);
    if (meters < minMove) return; // noise: keep the anchor

    final dt = pos.timestamp.difference(a.timestamp).inMilliseconds / 1000.0;
    final secs = dt > 0.5 ? dt : 1.0;
    final calcKmh = meters / secs * 3.6;
    if (calcKmh > RunRewards.maxKmh + 5) {
      _anchor = pos; // impossible on foot: a GPS jump, start again from here
      return;
    }
    final reported = pos.speed * 3.6;
    final speedKmh = (reported > 0.5 && reported <= RunRewards.maxKmh + 5
            ? reported
            : calcKmh)
        .clamp(0.0, RunRewards.maxKmh);
    final km = meters / 1000.0;

    setState(() {
      _distanceKm += km;
      _lastMoveAt = DateTime.now();
      _currentSpeedKmh = speedKmh;
      if (speedKmh > _maxSpeedKmh) _maxSpeedKmh = speedKmh;
      _speedSamples.add(speedKmh);
      // moving time = the time between two counted points while walking+
      if (calcKmh >= 1.5) _activeSec += secs;
      if (_mode.isInterval) {
        final ph = RunMode.intervalAt(_elapsedSeconds);
        if (ph != null && ph.fast) _fastKm[ph.round - 1] += km;
      }
      _routePoints.add({'lat': pos.latitude, 'lng': pos.longitude});
    });
    _anchor = pos;
    _lastPosition = pos;
    _tickChallenge();
    _checkStageLimits();
  }

  /// Feed the challenge engine: once a second and after each accepted GPS fix.
  void _tickChallenge() {
    if (_phase != _Phase.tracking) return;
    _challenge.update(
      elapsedSeconds: _elapsedSeconds,
      distanceKm: _distanceKm,
      moving: _isMoving,
    );
  }

  // ── STAGE LIMITS / END SESSION ─────────────────────────────────────────────

  /// Seconds left on the stage clock (null in Endless).
  int? get _clockLeftSeconds {
    final total = _mode.clockSeconds;
    if (total == null) return null;
    return math.max(0, total - _elapsedSeconds);
  }

  String? get _clockLeftLabel {
    final left = _clockLeftSeconds;
    if (left == null) return null;
    final h = left ~/ 3600;
    final m = (left % 3600) ~/ 60;
    final sec = left % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = sec.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  /// Interval Run: buzz + sound whenever FAST and EASY swap.
  void _intervalCue() {
    if (!_mode.isInterval || _phase != _Phase.tracking) return;
    final ph = RunMode.intervalAt(_elapsedSeconds);
    if (ph == null) return;
    if (_lastIntervalFast != null && _lastIntervalFast != ph.fast) {
      Sound.I.buzz(3);
      Sound.I.play(ph.fast ? Sfx.fast : Sfx.easy);
      Sound.I.music(ph.fast ? Bgm.sprint : Bgm.run);
    }
    _lastIntervalFast = ph.fast;
  }

  /// Stage target reached -> STAGE CLEARED. Clock at zero -> TIME UP.
  void _checkStageLimits() {
    if (_phase != _Phase.tracking || _ending) return;
    if (_mode.isInterval) {
      if (_clockLeftSeconds == 0) {
        _endSession(outcome: 'INTERVALS DONE!', good: true);
      }
      return;
    }
    if (!_mode.isStage) return;
    final target = _mode.targetKm;
    if (target != null && _distanceKm >= target) {
      _endSession(outcome: 'STAGE CLEARED!', good: true);
    } else if (_clockLeftSeconds == 0) {
      _endSession(outcome: 'TIME UP', good: false);
    }
  }

  /// The one way a run ends: END SESSION, target reached or time up.
  /// No confirmation step. It saves the run and opens the summary card.
  Future<void> _endSession({String? outcome, bool good = false}) async {
    if (_ending || _phase != _Phase.tracking) return;
    _ending = true;
    _outcome = outcome ?? (_mode.isStage ? 'ENDED EARLY' : null);
    _outcomeGood = good;
    await _stopAndSave();
  }

  // ── STOP & SAVE ────────────────────────────────────────────────────────────

  Future<void> _stopAndSave() async {
    _positionSub?.cancel();
    _positionSub = null;
    _timer?.cancel();
    final st = _startedAt;
    if (st != null) {
      _elapsedSeconds = DateTime.now().difference(st).inSeconds;
    }
    _activeSeconds = math.min(_activeSec.round(), _elapsedSeconds);
    _anchor = null;
    ChallengeAudio.instance.stop();

    // Sudden-quest rewards. A challenge still running when the player
    // finishes is simply abandoned (not counted).
    final challengeRecords = List<ChallengeRecord>.of(_challenge.records);
    final bonusXp = _challenge.bonusXp;
    final bonusCoins = _challenge.bonusCoins;
    final lootChests = _challenge.lootChests;
    _summaryChallenges = challengeRecords;

    // Ghost race result (null when not racing or the run was too short).
    final ghostResult =
        GhostResult.judge(_raceGhost, _distanceKm, _elapsedSeconds);
    _summaryGhost = ghostResult;
    final ghostCoins = ghostResult?.won == true ? GhostResult.winCoins : 0;

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

    // Mode multiplier: Novice 1.0x, Vanguard 1.5x, Slayer 2.5x, Endless 0.2x.
    final mult = _mode.rewardMult;

    // Reward = verified distance + MOVING time + pace bonus (utils/rewards.dart)
    final xp = RunRewards.xp(
      km: _distanceKm,
      activeSeconds: _activeSeconds,
      mult: mult,
      bonusXp: bonusXp.round(),
    );

    final coins = RunRewards.coins(km: _distanceKm, mult: mult);

    // Challenge bonus coins scale with the mode; the ghost prize stays fixed.
    final modeBonus = (bonusCoins * mult).round();

    final sessionStart =
        DateTime.now().subtract(
      Duration(seconds: _elapsedSeconds),
    );

    final session = ActivitySession(
      id: '',
      type: finalType,
      userPick: finalType,
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

    // Interval Run stats: only FAST blocks that were fully played count.
    Map<String, dynamic>? interval;
    if (_mode.isInterval) {
      var best = 0;
      var fastTotal = 0.0;
      for (var r = 0; r < RunMode.intervalRounds; r++) {
        fastTotal += _fastKm[r];
        final fastDone =
            _elapsedSeconds >= r * RunMode.intervalCycle + RunMode.intervalFastSeconds;
        if (fastDone && _fastKm[r] >= 0.03) {
          final pace = (RunMode.intervalFastSeconds / _fastKm[r]).round();
          if (best == 0 || pace < best) best = pace;
        }
      }
      interval = {
        'rounds': math.min(
            RunMode.intervalRounds, _elapsedSeconds ~/ RunMode.intervalCycle),
        'fast_km': double.parse(fastTotal.toStringAsFixed(3)),
        if (best > 0) 'best_fast_pace_s': best,
      };
      _intervalStats = interval;
    }

    _savedOffline = false;
    _saveError = null;
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final fields = session.toFirestore()
        ..['activeSeconds'] = _activeSeconds
        ..['startTime'] = session.startTime.millisecondsSinceEpoch
        ..['endTime'] = session.endTime.millisecondsSinceEpoch;
      final payload = RunPayload(
        id: '${session.startTime.millisecondsSinceEpoch}',
        uid: user.uid,
        modeId: _mode.id,
        outcome: _outcome,
        good: _outcomeGood,
        rewardMult: mult,
        fields: fields,
        challenges: challengeRecords.map((r) => r.toMap()).toList(),
        ghost: ghostResult?.toMap(),
        xp: xp,
        coins: coins,
        bonusCoins: modeBonus + ghostCoins,
        lootChests: lootChests,
        elapsedSeconds: _elapsedSeconds,
        interval: interval,
      );
      // cloud copy first: the run is safe on the account even if this
      // device never manages to finish the save
      RunCloud.stash(payload);
      try {
        final r = await RunSaver.save(payload).timeout(RunSaver.timeout);
        RunCloud.done(user.uid, payload.id);
        _newlyCompletedQuests = r.completedQuests;
        _stageStars = _mode.isTrial ? 0 : r.stars;
        _stageBonusCoins = r.bonusCoins;
        _stageFirstClear = r.firstClear;
        _unlockedRank = r.unlockedRank;
        _intervalNewBest = r.intervalNewBest;
        // connection is fine: also send any run that was waiting
        RunOutbox.flush(user.uid);
      } catch (e) {
        // Offline, too slow or refused: keep the run on the phone, send it
        // later, and SAY WHY on the summary (never fail silently).
        debugPrint('Run saved to outbox: $e');
        _savedOffline = true;
        _saveError = RunSaver.describe(e);
        RunOutbox.lastError.value = _saveError;
        await RunOutbox.enqueue(payload);
        if (_mode.isStage && _outcomeGood) {
          _stageStars = _mode.isTrial ? 0 : _mode.starsFor(_elapsedSeconds);
        }
      }
    }

    if (mounted) {
      setState(() {
        _isSaving = false;
      });
    }

    _playResultSounds();
    _showSummarySheet(session);
  }

  // ── SUMMARY ────────────────────────────────────────────────────────────────

  /// Jingle for the finished run, then little extras for what it earned.
  void _playResultSounds() {
    Sound.I.music(null); // quiet the track so the jingle is heard
    final won = _outcome == null || _outcomeGood;
    Sound.I.play(won ? Sfx.success : Sfx.fail);
    Future<void>.delayed(const Duration(milliseconds: 1300), () {
      if (_unlockedRank != null) {
        Sound.I.play(Sfx.unlock);
      } else if (_stageStars > 0) {
        Sound.I.play(Sfx.star);
      } else if (_newlyCompletedQuests.isNotEmpty || _stageBonusCoins > 0) {
        Sound.I.play(Sfx.gem);
      }
    });
  }

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
        queued: _savedOffline,
        saveError: _saveError,
        intervalStats: _intervalStats,
        intervalNewBest: _intervalNewBest,
        completedQuests:
            _newlyCompletedQuests,
        challenges: _summaryChallenges,
        ghostResult: _summaryGhost,
        mode: _mode,
        outcome: _outcome,
        outcomeGood: _outcomeGood,
        stars: _stageStars,
        stageBonusCoins: _stageBonusCoins,
        firstClear: _stageFirstClear,
        unlockedRank: _unlockedRank,
        onNextRank: _unlockedRank == null ? null : _onNextRank,
        onDone: _onSummaryDone,
      ),
    );
  }

  bool _tutorialLaunching = false;
  bool _savedOffline = false;
  String? _saveError;


  /// DONE on the Session Summary.
  ///
  /// First-ever run (hasCompletedFirstRunTutorial == false): the sheet is NOT
  /// closed. The Phase 2 tutorial takes over the screen, spotlights the
  /// rewards, and closes the summary itself when the player taps NEXT.
  Future<void> _onSummaryDone() async {
    if (_tutorialLaunching || PostRunTutorial.isActive) return;
    _tutorialLaunching = true;
    try {
      final pending = await TutorialProgress.loadFirstRunPending();
      if (!mounted) return;
      if (pending) {
        PostRunTutorial.show(
          context,
          hooks: PostRunTutorialHooks(
            closeSummary: () async => _closeSummary(),
            navigateTo: (i) => widget.onNavigate?.call(i),
            onFinished: TutorialProgress.markFirstRunDone,
          ),
        );
        return;
      }
      _closeSummary();
    } finally {
      _tutorialLaunching = false;
    }
  }

  /// Dismiss the summary sheet and return to the pre-run screen.
  void _closeSummary() {
    Navigator.of(context).pop();

    // Do NOT Navigator.pop() the RunTrackingScreen.
    // It lives inside MainShell's IndexedStack.
    if (mounted) {
      final next = _pendingNextRank;
      _pendingNextRank = null;
      setState(() {
        if (next != null) {
          _applyMode(next);
          _phase = _Phase.briefing;
        } else {
          _phase = _Phase.preRun;
        }
        _distanceKm = 0;
        _currentSpeedKmh = 0;
        _maxSpeedKmh = 0;
        _elapsedSeconds = 0;
        _ending = false;
        _lastPosition = null;
        _anchor = null;
        _startedAt = null;
        _activeSec = 0;
        _speedSamples.clear();
        _routePoints.clear();
      });
      _challenge.reset();
      _loadGhost(); // a new personal best becomes the next ghost
    }
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
          activityType: _userPick,
          onComplete: _beginCountdown,
          onSkip: _skipWarmUp,
          onBack: () => setState(() =>
              _phase = _mode.isStage ? _Phase.briefing : _Phase.preRun),
        );

      case _Phase.locating:
        return _buildLocating();

      case _Phase.countdown:
        return RunCountdown(
          modeName: _mode.name,
          onDone: () => _startTracking(),
          onCancel: _cancelStart,
        );

      case _Phase.briefing:
        return StageBriefingView(
          mode: _mode,
          onBegin: () => setState(() => _phase = _Phase.warmUp),
          onBack: () => setState(() => _phase = _Phase.preRun),
        );

      case _Phase.tracking:
        return _buildTracking();

      case _Phase.summary:
        // The hero runs on the spot while the run is being saved.
        return const LoadingRunner(label: 'SAVING YOUR RUN...');
    }
  }

  // ── PRE-RUN ────────────────────────────────────────────────────────────────

  Widget _buildPreRun() {
    return PreRunView(
      onBack: _exitRunScreen,
      onStart: _onModePicked,
      ghost: _ghost,
      ghostOn: _ghostOn,
      onGhostToggle: () => setState(() => _ghostOn = !_ghostOn),
    );
  }

  // ── ACTIVE TRACKING ────────────────────────────────────────────────────────

  Widget _buildTracking() {
    final left = _clockLeftSeconds;
    return TrackingView(
      type: _effectiveType,
      time: _formattedTime,
      speedKmh: _currentSpeedKmh,
      moving: _isMoving,
      distanceKm: _distanceKm,
      pace: _pace,
      maxSpeedKmh: _maxSpeedKmh,
      onFinish: () => _endSession(),
      mode: _mode,
      clockLeft: _clockLeftLabel,
      clockLow: left != null && left <= 60,
      // Novice and Endless have no sudden events at all
      challenge: _challenge.enabled ? _challenge : null,
      gpsStatus: _gpsStatus,
      ghost: _raceGhost,
      elapsedSeconds: _elapsedSeconds,
    );
  }
}

enum _Phase {
  preRun,
  briefing,
  warmUp,
  locating, // permission + first GPS fix, before anything starts
  countdown,
  tracking,
  summary,
}
