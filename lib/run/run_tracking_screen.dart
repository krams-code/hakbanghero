import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' hide ActivityType;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/activity_model.dart';
import '../../models/daily_quest_definitions.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Pre-run: user picks activity type, then tracking begins
// ─────────────────────────────────────────────────────────────────────────────
class RunTrackingScreen extends StatefulWidget {
  const RunTrackingScreen({super.key});

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

  // ── Animations ─────────────────────────────────────────────────────────────
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;
  late AnimationController _fadeCtrl;
  late Animation<double> _fade;

  // ── Saving ─────────────────────────────────────────────────────────────────
  bool _isSaving = false;

  // Quests completed during this save (shown in summary)
  List<DailyQuest> _newlyCompletedQuests = [];

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.85, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
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
      _currentSpeedKmh > 0.5 ? _detectedType : _userPick;

  Color get _activityColor {
    switch (_effectiveType) {
      case ActivityType.walk: return const Color(0xFF00CFFF);
      case ActivityType.jog:  return const Color(0xFFFFD700);
      case ActivityType.run:  return const Color(0xFF00FF41);
    }
  }

  String get _formattedTime {
    final h = _elapsedSeconds ~/ 3600;
    final m = (_elapsedSeconds % 3600) ~/ 60;
    final s = _elapsedSeconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String get _pace {
    if (_distanceKm <= 0 || _elapsedSeconds <= 0) return '--:--';
    final secsPerKm = _elapsedSeconds / _distanceKm;
    final m = secsPerKm ~/ 60;
    final s = (secsPerKm % 60).toInt();
    return "${m}'${s.toString().padLeft(2, '0')}\"";
  }

  double get _avgSpeed {
    if (_speedSamples.isEmpty) return 0;
    return _speedSamples.reduce((a, b) => a + b) / _speedSamples.length;
  }

  // ── Permissions & Start ────────────────────────────────────────────────────
  Future<bool> _requestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) _showSnack('Please enable GPS/Location services on your device.');
      return false;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) _showSnack('Location permission denied.');
        return false;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      if (mounted) _showSnack('Location permission permanently denied. Enable it in settings.');
      return false;
    }
    return true;
  }

  Future<void> _startTracking() async {
    final granted = await _requestPermission();
    if (!granted) return;

    setState(() {
      _phase = _Phase.tracking;
      _distanceKm = 0;
      _currentSpeedKmh = 0;
      _maxSpeedKmh = 0;
      _elapsedSeconds = 0;
      _isPaused = false;
      _speedSamples.clear();
      _routePoints.clear();
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isPaused && mounted) setState(() => _elapsedSeconds++);
    });

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 5,
    );

    _positionSub = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position pos) {
      if (!mounted || _isPaused) return;
      final speedKmh = (pos.speed * 3.6).clamp(0.0, 60.0);

      if (_lastPosition != null) {
        final delta = Geolocator.distanceBetween(
          _lastPosition!.latitude,
          _lastPosition!.longitude,
          pos.latitude,
          pos.longitude,
        ) / 1000.0;

        if (delta > 0.002 && delta < 0.05) {
          setState(() {
            _distanceKm += delta;
            _currentSpeedKmh = speedKmh;
            if (speedKmh > _maxSpeedKmh) _maxSpeedKmh = speedKmh;
            _speedSamples.add(speedKmh);
            _routePoints.add({'lat': pos.latitude, 'lng': pos.longitude});
          });
        }
      }
      _lastPosition = pos;
    });
  }

  void _togglePause() {
    setState(() => _isPaused = !_isPaused);
    if (_isPaused) {
      _positionSub?.pause();
    } else {
      _positionSub?.resume();
    }
  }

  // ── Stop & Save (with daily quest transaction) ─────────────────────────────
  Future<void> _stopAndSave() async {
    _positionSub?.cancel();
    _timer?.cancel();

    // Determine final activity type by majority vote of speed samples
    ActivityType finalType = _userPick;
    if (_speedSamples.isNotEmpty) {
      int walkCount = 0, jogCount = 0, runCount = 0;
      for (final s in _speedSamples) {
        final t = ActivityTypeExt.fromSpeed(s);
        if (t == ActivityType.walk) walkCount++;
        else if (t == ActivityType.jog) jogCount++;
        else runCount++;
      }
      if (runCount >= jogCount && runCount >= walkCount) {
        finalType = ActivityType.run;
      } else if (jogCount >= walkCount) {
        finalType = ActivityType.jog;
      } else {
        finalType = ActivityType.walk;
      }
    }

    final xp    = (_distanceKm * 100 + _elapsedSeconds / 60 * 5).toInt();
    final coins = (_distanceKm * 10).toInt();
    final sessionStart = DateTime.now().subtract(Duration(seconds: _elapsedSeconds));

    final session = ActivitySession(
      id:              '',
      type:            finalType,
      userPick:        _userPick,
      startTime:       sessionStart,
      endTime:         DateTime.now(),
      distanceKm:      double.parse(_distanceKm.toStringAsFixed(3)),
      durationSeconds: _elapsedSeconds,
      avgSpeedKmh:     double.parse(_avgSpeed.toStringAsFixed(2)),
      maxSpeedKmh:     double.parse(_maxSpeedKmh.toStringAsFixed(2)),
      xpEarned:        xp,
      coinsEarned:     coins,
      routePoints:     _routePoints,
    );

    setState(() {
      _phase = _Phase.summary;
      _isSaving = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final db      = FirebaseFirestore.instance;
        final userRef = db.collection('users').doc(user.uid);
        final actRef  = userRef.collection('activities');

        // 1. Save the activity document
        await actRef.add(session.toFirestore());

        // 2. Update base user totals (xp, coins, km, sessions)
        await userRef.update({
          'total_km':       FieldValue.increment(session.distanceKm),
          'total_sessions': FieldValue.increment(1),
          'xp':             FieldValue.increment(xp),
          'coins':          FieldValue.increment(coins),
        });

        // 3. Daily quest progress transaction
        final todayStr = _todayDateString();
        final completedQuests = <DailyQuest>[];

        await db.runTransaction((txn) async {
          final snap = await txn.get(userRef);
          final data = snap.data() ?? {};

          // ── Read existing daily progress ──────────────────────────────────
          final storedDate = data['daily_progress_date'] as String? ?? '';
          double dailyKm   = (data['daily_progress_km'] as num?)?.toDouble() ?? 0.0;
          Map<String, dynamic> claimedMap =
              Map<String, dynamic>.from(data['daily_quests_claimed'] as Map? ?? {});

          // ── Reset if it's a new day ───────────────────────────────────────
          if (storedDate != todayStr) {
            dailyKm   = 0.0;
            claimedMap = {};
          }

          // ── Add this session's distance ───────────────────────────────────
          dailyKm += session.distanceKm;

          // ── Check quest thresholds ────────────────────────────────────────
          int crystalsToAdd = 0;
          for (final quest in kDailyQuests) {
            if (claimedMap[quest.id] == true) continue; // already claimed today

            // Time-gated quests (e.g. before 9 AM): check session start hour
            if (quest.beforeHour != null &&
                sessionStart.hour >= quest.beforeHour!) {
              continue; // session started too late for this quest
            }

            if (dailyKm >= quest.thresholdKm) {
              claimedMap[quest.id] = true;
              crystalsToAdd += quest.crystalReward;
              completedQuests.add(quest);
            }
          }

          // ── Write everything back in one transaction ──────────────────────
          final Map<String, dynamic> updates = {
            'daily_progress_km':     dailyKm,
            'daily_progress_date':   todayStr,
            'daily_quests_claimed':  claimedMap,
          };
          if (crystalsToAdd > 0) {
            updates['gems'] = FieldValue.increment(crystalsToAdd);
          }
          txn.update(userRef, updates);
        });

        _newlyCompletedQuests = completedQuests;
      }
    } catch (e) {
      debugPrint('Error saving activity: $e');
    }

    if (mounted) setState(() => _isSaving = false);
    _showSummarySheet(session);
  }

  /// Returns today's date as 'YYYY-MM-DD' in local time.
  String _todayDateString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  void _showSummarySheet(ActivitySession session) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      builder: (_) => _SummarySheet(
        session: session,
        isSaving: _isSaving,
        completedQuests: _newlyCompletedQuests,
        onDone: () {
          Navigator.of(context).pop();
          Navigator.of(context).pop();
        },
      ),
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: const Color(0xFF1A3A1A)),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060C06),
      body: FadeTransition(
        opacity: _fade,
        child: _phase == _Phase.preRun ? _buildPreRun() : _buildTracking(),
      ),
    );
  }

  // ── Pre-run picker ─────────────────────────────────────────────────────────
  Widget _buildPreRun() {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A2A1A),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF2A4A2A)),
                    ),
                    child: const Icon(Icons.arrow_back, color: Color(0xFF00FF41), size: 20),
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'START SESSION',
                  style: TextStyle(
                    color: Color(0xFFE8FFE8),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
          ScaleTransition(
            scale: _pulse,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  colors: [Color(0xFF1A4A1A), Color(0xFF060C06)],
                ),
                border: Border.all(color: const Color(0xFF00FF41), width: 2),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00FF41).withOpacity(0.3),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: const Icon(Icons.directions_run, color: Color(0xFF00FF41), size: 52),
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            'SELECT ACTIVITY',
            style: TextStyle(
              color: Color(0xFF4A8A4A),
              fontSize: 12,
              letterSpacing: 3,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: ActivityType.values
                  .map((t) => _ActivityTypeButton(
                        type: t,
                        isSelected: _userPick == t,
                        onTap: () => setState(() => _userPick = t),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1A0D),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF1A3A1A)),
              ),
              child: Column(
                children: const [
                  _SpeedInfo(label: '🚶 Walk', range: '< 6 km/h',    color: Color(0xFF00CFFF)),
                  SizedBox(height: 6),
                  _SpeedInfo(label: '🏃 Jog',  range: '6 – 10 km/h', color: Color(0xFFFFD700)),
                  SizedBox(height: 6),
                  _SpeedInfo(label: '⚡ Run',  range: '> 10 km/h',   color: Color(0xFF00FF41)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Your selection will be confirmed by GPS speed during the session.',
              textAlign: TextAlign.center,
              style: TextStyle(color: const Color(0xFF3A6A3A), fontSize: 11),
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            child: SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                onPressed: _startTracking,
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
                child: Ink(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00FF41), Color(0xFF00BB30)],
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Container(
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.play_arrow, color: Color(0xFF0A0F0A), size: 26),
                        const SizedBox(width: 8),
                        Text(
                          'BEGIN ${_userPick.label.toUpperCase()}',
                          style: const TextStyle(
                            color: Color(0xFF0A0F0A),
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Active tracking ────────────────────────────────────────────────────────
  Widget _buildTracking() {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _activityColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _activityColor.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Text(_effectiveType.emoji, style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 6),
                      Text(
                        _effectiveType.label.toUpperCase(),
                        style: TextStyle(
                          color: _activityColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (_isPaused)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6B35).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFF6B35).withOpacity(0.4)),
                    ),
                    child: const Text(
                      '⏸ PAUSED',
                      style: TextStyle(
                        color: Color(0xFFFF6B35),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            _formattedTime,
            style: const TextStyle(
              color: Color(0xFFE8FFE8),
              fontSize: 64,
              fontWeight: FontWeight.w200,
              letterSpacing: 4,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'ELAPSED TIME',
            style: TextStyle(color: Color(0xFF3A5A3A), fontSize: 10, letterSpacing: 3),
          ),
          const SizedBox(height: 32),
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, __) => _SpeedometerWidget(
              speedKmh: _currentSpeedKmh,
              activityColor: _activityColor,
              pulseValue: _isPaused ? 0.9 : _pulse.value,
            ),
          ),
          const SizedBox(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                _TrackStat(
                  label: 'DISTANCE',
                  value: _distanceKm.toStringAsFixed(2),
                  unit: 'km',
                  color: _activityColor,
                ),
                _TrackStat(
                  label: 'AVG PACE',
                  value: _pace,
                  unit: '/km',
                  color: const Color(0xFFFFD700),
                ),
                _TrackStat(
                  label: 'MAX SPEED',
                  value: _maxSpeedKmh.toStringAsFixed(1),
                  unit: 'km/h',
                  color: const Color(0xFFFF6B35),
                ),
              ],
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _togglePause,
                    child: Container(
                      height: 60,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D1A0D),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF1A3A1A)),
                      ),
                      child: Icon(
                        _isPaused ? Icons.play_arrow : Icons.pause,
                        color: _isPaused ? const Color(0xFF00FF41) : const Color(0xFFFFD700),
                        size: 30,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: _confirmStop,
                    child: Container(
                      height: 60,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFCC2200), Color(0xFF881100)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFCC2200).withOpacity(0.3),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.stop_circle_outlined, color: Colors.white, size: 24),
                          SizedBox(width: 8),
                          Text(
                            'FINISH',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _confirmStop() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D1A0D),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF1A4A1A)),
        ),
        title: const Text(
          'FINISH SESSION?',
          style: TextStyle(
            color: Color(0xFFE8FFE8),
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
        content: Text(
          'You\'ve covered ${_distanceKm.toStringAsFixed(2)} km in $_formattedTime. Save and end?',
          style: const TextStyle(color: Color(0xFF4A8A4A), fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('KEEP GOING', style: TextStyle(color: Color(0xFF00FF41))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _stopAndSave();
            },
            child: const Text('FINISH', style: TextStyle(color: Color(0xFFCC2200))),
          ),
        ],
      ),
    );
  }
}

enum _Phase { preRun, tracking, summary }

// ─────────────────────────────────────────────────────────────────────────────
//  Speedometer Widget
// ─────────────────────────────────────────────────────────────────────────────
class _SpeedometerWidget extends StatelessWidget {
  final double speedKmh;
  final Color activityColor;
  final double pulseValue;

  const _SpeedometerWidget({
    required this.speedKmh,
    required this.activityColor,
    required this.pulseValue,
  });

  @override
  Widget build(BuildContext context) {
    final fraction = (speedKmh / 20.0).clamp(0.0, 1.0);
    return SizedBox(
      width: 180,
      height: 180,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.scale(
            scale: pulseValue,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: activityColor.withOpacity(0.15),
                    blurRadius: 30,
                    spreadRadius: 10,
                  ),
                ],
              ),
            ),
          ),
          CustomPaint(
            size: const Size(170, 170),
            painter: _ArcPainter(fraction: fraction, color: activityColor),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                speedKmh.toStringAsFixed(1),
                style: TextStyle(
                  color: activityColor,
                  fontSize: 40,
                  fontWeight: FontWeight.w200,
                  letterSpacing: 2,
                ),
              ),
              Text(
                'km/h',
                style: TextStyle(
                  color: activityColor.withOpacity(0.6),
                  fontSize: 12,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  final double fraction;
  final Color color;
  const _ArcPainter({required this.fraction, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;
    const startAngle = math.pi * 0.75;
    const sweepMax  = math.pi * 1.5;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle, sweepMax, false,
      Paint()
        ..color = color.withOpacity(0.12)
        ..strokeWidth = 10
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    if (fraction > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle, sweepMax * fraction, false,
        Paint()
          ..color = color
          ..strokeWidth = 10
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.fraction != fraction || old.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Activity type picker button
// ─────────────────────────────────────────────────────────────────────────────
class _ActivityTypeButton extends StatelessWidget {
  final ActivityType type;
  final bool isSelected;
  final VoidCallback onTap;

  const _ActivityTypeButton({
    required this.type,
    required this.isSelected,
    required this.onTap,
  });

  Color get _color {
    switch (type) {
      case ActivityType.walk: return const Color(0xFF00CFFF);
      case ActivityType.jog:  return const Color(0xFFFFD700);
      case ActivityType.run:  return const Color(0xFF00FF41);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isSelected ? _color.withOpacity(0.15) : const Color(0xFF0D1A0D),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? _color : const Color(0xFF1A3A1A),
              width: isSelected ? 2 : 1,
            ),
            boxShadow: isSelected
                ? [BoxShadow(color: _color.withOpacity(0.2), blurRadius: 12)]
                : [],
          ),
          child: Column(
            children: [
              Text(type.emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(height: 6),
              Text(
                type.label.toUpperCase(),
                style: TextStyle(
                  color: isSelected ? _color : const Color(0xFF3A5A3A),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Tracking stat tile
// ─────────────────────────────────────────────────────────────────────────────
class _TrackStat extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color color;

  const _TrackStat({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1A0D),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w700)),
            Text(unit, style: const TextStyle(color: Color(0xFF3A5A3A), fontSize: 9)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(
                    color: Color(0xFF3A6A3A), fontSize: 8, letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Speed info row
// ─────────────────────────────────────────────────────────────────────────────
class _SpeedInfo extends StatelessWidget {
  final String label;
  final String range;
  final Color color;

  const _SpeedInfo({required this.label, required this.range, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        const Spacer(),
        Text(range, style: const TextStyle(color: Color(0xFF4A7A4A), fontSize: 12)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Summary bottom sheet  (now shows quest completions)
// ─────────────────────────────────────────────────────────────────────────────
class _SummarySheet extends StatelessWidget {
  final ActivitySession session;
  final bool isSaving;
  final List<DailyQuest> completedQuests;
  final VoidCallback onDone;

  const _SummarySheet({
    required this.session,
    required this.isSaving,
    required this.completedQuests,
    required this.onDone,
  });

  Color get _typeColor {
    switch (session.type) {
      case ActivityType.walk: return const Color(0xFF00CFFF);
      case ActivityType.jog:  return const Color(0xFFFFD700);
      case ActivityType.run:  return const Color(0xFF00FF41);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalCrystals =
        completedQuests.fold<int>(0, (sum, q) => sum + q.crystalReward);

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      decoration: const BoxDecoration(
        color: Color(0xFF0D1A0D),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF2A4A2A),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),

            // Trophy icon
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _typeColor.withOpacity(0.12),
                border: Border.all(color: _typeColor.withOpacity(0.4), width: 2),
              ),
              child: Center(
                child: Text(session.type.emoji, style: const TextStyle(fontSize: 32)),
              ),
            ),
            const SizedBox(height: 12),

            Text(
              'SESSION COMPLETE!',
              style: TextStyle(
                color: _typeColor, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${session.type.label} • ${session.formattedDuration}',
              style: const TextStyle(color: Color(0xFF4A8A4A), fontSize: 13),
            ),
            const SizedBox(height: 24),

            // Stats grid
            Row(
              children: [
                _SummaryStat(
                  label: 'DISTANCE',
                  value: '${session.distanceKm.toStringAsFixed(2)} km',
                  color: _typeColor,
                ),
                _SummaryStat(
                  label: 'AVG PACE',
                  value: session.formattedPace,
                  color: const Color(0xFFFFD700),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _SummaryStat(
                  label: 'MAX SPEED',
                  value: '${session.maxSpeedKmh.toStringAsFixed(1)} km/h',
                  color: const Color(0xFFFF6B35),
                ),
                _SummaryStat(
                  label: 'AVG SPEED',
                  value: '${session.avgSpeedKmh.toStringAsFixed(1)} km/h',
                  color: const Color(0xFF00CFFF),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // XP + Coins rewards
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0A1A0A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF1A4A1A)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.star, color: Color(0xFFFFD700), size: 16),
                  const SizedBox(width: 6),
                  Text('+${session.xpEarned} XP',
                      style: const TextStyle(
                          color: Color(0xFFFFD700), fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 20),
                  const Icon(Icons.monetization_on, color: Color(0xFFFFD700), size: 16),
                  const SizedBox(width: 6),
                  Text('+${session.coinsEarned} coins',
                      style: const TextStyle(
                          color: Color(0xFFFFD700), fontSize: 14, fontWeight: FontWeight.w700)),
                ],
              ),
            ),

            // ── Quest completion banner ──────────────────────────────────────
            if (completedQuests.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0D1A),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF00CFFF).withOpacity(0.5)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00CFFF).withOpacity(0.1),
                      blurRadius: 12,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('💎', style: TextStyle(fontSize: 16)),
                        const SizedBox(width: 8),
                        Text(
                          'QUEST${completedQuests.length > 1 ? 'S' : ''} COMPLETED!',
                          style: const TextStyle(
                            color: Color(0xFF00CFFF),
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ...completedQuests.map((q) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              Icon(q.icon, color: q.color, size: 16),
                              const SizedBox(width: 8),
                              Text(
                                q.title,
                                style: TextStyle(
                                  color: q.color,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '+${q.crystalReward} 💎',
                                style: const TextStyle(
                                  color: Color(0xFF00CFFF),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        )),
                    if (completedQuests.length > 1) ...[
                      const Divider(color: Color(0xFF1A2A3A), height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            'Total: +$totalCrystals 💎 Mana Crystals',
                            style: const TextStyle(
                              color: Color(0xFF00CFFF),
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],

            if (session.userPick != session.type) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A0A),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF3A3A1A)),
                ),
                child: Text(
                  '⚡ You selected ${session.userPick.label} but GPS confirmed ${session.type.label}!',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFFCCCC44), fontSize: 11),
                ),
              ),
            ],

            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: isSaving ? null : onDone,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _typeColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: isSaving
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                    : const Text(
                        'DONE',
                        style: TextStyle(
                          color: Color(0xFF0A0F0A),
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SummaryStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF0A1A0A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(
                    color: Color(0xFF3A5A3A), fontSize: 9, letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }
}