import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' hide ActivityType;

import '../../models/activity_model.dart';
import '../../services/friends_service.dart';
import '../../widgets/block_ui.dart';
import '../../widgets/hero_bust.dart';

/// LIVE DUEL ROOM — both players are on this screen at the same time.
///
///   lobby      both press READY
///   countdown  synchronized 5-4-3-2-1-GO (both clients react to the same
///              Firestore status change)
///   active     GPS-only race, progress syncs every 3 s and doubles as a
///              heartbeat; first to the distance wins
///   done       winner / loser screens. The loser can KEEP RUNNING and still
///              save the run.
///
/// Anti-foul: the room needs GPS (no timer-only), ignores mock locations,
/// vehicle-speed jumps and poor fixes, has no pause button, leaving mid-race
/// is a forfeit, and a silent opponent can be timed out.
class DuelRoomScreen extends StatefulWidget {
  final String challengeId;
  const DuelRoomScreen({super.key, required this.challengeId});

  @override
  State<DuelRoomScreen> createState() => _DuelRoomScreenState();
}

class _DuelRoomScreenState extends State<DuelRoomScreen> {
  static const double _maxSpeedKmh = 28; // faster than this is not a person running
  static const double _maxAccuracyM = 50;
  static const int _offlineWarnSecs = 45;
  static const int _offlineClaimSecs = 90;

  late final String _me;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _chSub;
  Map<String, dynamic>? _ch;
  Map<String, dynamic>? _meData, _otherData;
  bool _profilesLoaded = false;

  // countdown
  int? _count; // 5..0 (0 = GO)
  Timer? _countTimer;

  // race
  bool _racing = false;   // local tracking is running
  bool _post = false;     // the race is decided
  bool _resultShown = false;
  bool _finishClaimed = false;
  bool _closing = false;
  bool _saving = false;
  bool _targetToastShown = false;
  StreamSubscription<Position>? _posSub;
  Timer? _tick;
  double _km = 0;
  int _secs = 0;
  double _topSpeed = 0;
  int _flags = 0;
  Position? _last;
  DateTime? _raceStart;
  final List<Map<String, double>> _route = [];
  String? _locError;

  @override
  void initState() {
    super.initState();
    _me = FirebaseAuth.instance.currentUser?.uid ?? '';
    _chSub = FriendsService.challenges
        .doc(widget.challengeId)
        .snapshots()
        .listen(_onChallenge, onError: (_) {});
  }

  @override
  void dispose() {
    _chSub?.cancel();
    _countTimer?.cancel();
    _tick?.cancel();
    _posSub?.cancel();
    super.dispose();
  }

  // ───────────────────────── derived ─────────────────────────

  String get _status => (_ch?['status'] as String?) ?? 'pending';
  double get _target => ((_ch?['distance_km'] as num?) ?? 1).toDouble();
  int get _reward => ((_ch?['reward'] as num?) ?? 0).toInt();
  String get _otherUid {
    final p = (_ch?['participants'] as List?)?.whereType<String>().toList() ?? const [];
    return p.firstWhere((u) => u != _me, orElse: () => '');
  }

  bool get _iAmSender => _ch != null && _ch!['from'] == _me;

  String _nameField(String key, String fallback) {
    final v = _ch == null ? null : _ch![key];
    return v is String && v.isNotEmpty ? v : fallback;
  }

  String get _otherName =>
      _iAmSender ? _nameField('to_name', 'Hero') : _nameField('from_name', 'Hero');
  String get _myName =>
      _iAmSender ? _nameField('from_name', 'You') : _nameField('to_name', 'You');

  double _progressOf(String uid) =>
      (((_ch?['progress'] as Map?)?[uid]) as num?)?.toDouble() ?? 0;
  bool _readyOf(String uid) => ((_ch?['ready'] as Map?)?[uid]) == true;

  // ───────────────────────── challenge stream ─────────────────────────

  Future<void> _loadProfiles() async {
    if (_profilesLoaded || _otherUid.isEmpty) return;
    _profilesLoaded = true;
    try {
      final a = await FriendsService.user(_me).get();
      final b = await FriendsService.user(_otherUid).get();
      if (mounted) setState(() {
        _meData = a.data();
        _otherData = b.data();
      });
    } catch (_) {}
  }

  void _onChallenge(DocumentSnapshot<Map<String, dynamic>> snap) {
    final d = snap.data();
    if (d == null) {
      _exit();
      return;
    }
    setState(() => _ch = d);
    _loadProfiles();

    switch (d['status']) {
      case 'lobby':
        _maybeStartCountdown();
      case 'countdown':
        _beginCountdown();
      case 'active':
        // joined late / came back: resume from my last synced distance
        // (while my own 5-4-3-2-1 is still running, wait for it: both start together)
        if (!_racing && !_post && _countTimer == null) _startRace(resume: true);
      case 'done':
        _onDone(d);
      case 'forfeit':
        if (d['forfeit_by'] != _me) {
          FriendsService.claimWin(widget.challengeId, _me).catchError((_) => false);
        }
      case 'cancelled':
      case 'declined':
      case 'expired':
        _onClosed(d['status'] as String);
    }
  }

  void _maybeStartCountdown() {
    final others = [_me, _otherUid];
    if (others.every(_readyOf)) {
      FriendsService.startCountdownIfReady(widget.challengeId).catchError((_) {});
    }
  }

  // ───────────────────────── countdown ─────────────────────────

  void _beginCountdown() {
    if (_countTimer != null || _racing) return;
    setState(() => _count = FriendsService.countdownSeconds);
    _countTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final next = (_count ?? 1) - 1;
      setState(() => _count = next);
      if (next <= 0) {
        t.cancel();
        _countTimer = null;
        FriendsService.goActive(widget.challengeId).catchError((_) {});
        _startRace();
        // hide "GO!" after a moment
        Future.delayed(const Duration(milliseconds: 900), () {
          if (mounted) setState(() => _count = null);
        });
      }
    });
  }

  // ───────────────────────── GPS ─────────────────────────

  Future<bool> _ensureLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _locError = 'Location services are turned off on this device.';
        return false;
      }
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      if (p == LocationPermission.denied ||
          p == LocationPermission.deniedForever ||
          p == LocationPermission.unableToDetermine) {
        _locError = 'Location permission is needed for live duels (GPS only).';
        return false;
      }
      _locError = null;
      return true;
    } catch (_) {
      _locError = 'Could not access location.';
      return false;
    }
  }

  Future<void> _toggleReady() async {
    final ready = _readyOf(_me);
    if (!ready) {
      final ok = await _ensureLocation();
      if (!ok) {
        if (mounted) {
          setState(() {});
          await _dialog('\u{1F4CD}', 'LOCATION NEEDED', _locError ?? 'GPS is required.',
              color: Rb.red);
        }
        return;
      }
    }
    try {
      await FriendsService.setReady(widget.challengeId, _me, !ready);
    } catch (_) {
      if (mounted) await _dialog('⚠️', 'COULD NOT UPDATE', 'Please try again.', color: Rb.red);
    }
  }

  void _startRace({bool resume = false}) {
    if (_racing) return;
    _racing = true;
    _count = null;
    _km = resume ? _progressOf(_me) : 0;
    _raceStart = DateTime.now();
    final started = (_ch?['started_at'] as Timestamp?)?.toDate();
    _secs = resume && started != null
        ? DateTime.now().difference(started).inSeconds.clamp(0, 86400).toInt()
        : 0;
    _last = null;

    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _secs++);
      if (_secs % 3 == 0 && !_post) {
        FriendsService.pushProgress(widget.challengeId, _me, _km).catchError((_) {});
      }
      _checkFinish();
    });

    _posSub?.cancel();
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 3,
      ),
    ).listen(_onPosition, onError: (_) {
      if (mounted) setState(() => _locError = 'GPS signal lost. Keep moving, it should come back.');
    });
    if (mounted) setState(() {});
  }

  void _onPosition(Position pos) {
    // ── anti-foul filters ──
    if (pos.isMocked) {
      _flag('Fake location detected');
      return;
    }
    if (pos.accuracy > _maxAccuracyM) return; // poor fix, just wait for a better one

    final prev = _last;
    _last = pos;
    if (prev == null) return;

    final deltaKm = Geolocator.distanceBetween(
            prev.latitude, prev.longitude, pos.latitude, pos.longitude) /
        1000.0;
    final dtH = pos.timestamp.difference(prev.timestamp).inMilliseconds / 3.6e6;
    if (deltaKm < 0.002) return; // standing still / noise
    if (dtH <= 0) return;
    final speed = deltaKm / dtH;
    if (speed > _maxSpeedKmh) {
      _flag('Moving too fast to be running');
      return;
    }

    setState(() {
      _locError = null;
      _km += deltaKm;
      if (speed > _topSpeed) _topSpeed = speed;
      _route.add({'lat': pos.latitude, 'lng': pos.longitude});
    });
    _checkFinish();
  }

  void _flag(String why) {
    _flags++;
    if (mounted) setState(() => _locError = '⚠ $why — that movement does not count.');
    FriendsService.challenges
        .doc(widget.challengeId)
        .update({'flags.$_me': _flags}).catchError((_) {});
  }

  Future<void> _checkFinish() async {
    if (_finishClaimed || _post || _status != 'active') return;
    if (_km >= _target) {
      _finishClaimed = true;
      try {
        await FriendsService.claimFinish(widget.challengeId, _me, _km);
      } catch (_) {
        _finishClaimed = false;
      }
    }
  }

  // ───────────────────────── results ─────────────────────────

  void _onDone(Map<String, dynamic> d) {
    if (_resultShown) return;
    _resultShown = true;
    _post = true;
    _countTimer?.cancel();
    final won = d['winner'] == _me;
    final byDefault = d['by_default'] == true;

    // tracking only runs if we were actually racing
    if (!_racing) {
      // never started (e.g. opened a finished duel): just show the result
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final keep = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(22),
          child: Block(
            color: won ? const Color(0xFF1E6B45) : Rb.slate,
            edge: won ? const Color(0xFF0B2E1D) : Colors.black,
            depth: 8,
            radius: 24,
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(won ? '\u{1F3C6}' : '\u{1F624}', style: const TextStyle(fontSize: 56)),
                const SizedBox(height: 6),
                BlockText(won ? 'YOU WON!' : '$_otherName WON!'.toUpperCase(),
                    size: 26, stroke: 5.5, color: won ? Rb.gold : Colors.white,
                    align: TextAlign.center),
                const SizedBox(height: 6),
                BlockText(
                  won
                      ? (byDefault
                          ? '$_otherName left the race — you win by default!'
                          : 'You reached ${_target.toStringAsFixed(0)} km first!')
                      : 'They reached ${_target.toStringAsFixed(0)} km first.\nYou are at ${_km.toStringAsFixed(2)} km — keep running, finish your distance!',
                  size: 12,
                  stroke: 3,
                  align: TextAlign.center,
                ),
                if (won) ...[
                  const SizedBox(height: 10),
                  BlockText('+\u{1F48E}$_reward', size: 22, stroke: 5, color: Rb.neon),
                ],
                const SizedBox(height: 16),
                if (!byDefault || !won)
                  PressBlock(
                    color: Rb.orange,
                    edge: Rb.orangeEdge,
                    depth: 6,
                    radius: 14,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    onTap: () => Navigator.of(ctx).pop(true),
                    child: SizedBox(
                      width: double.infinity,
                      child: Center(
                        child: BlockText(won ? 'KEEP RUNNING' : '\u{1F3C3} KEEP RUNNING',
                            size: 15, stroke: 4),
                      ),
                    ),
                  ),
                if (!byDefault || !won) const SizedBox(height: 8),
                PressBlock(
                  color: Rb.green,
                  edge: Rb.greenEdge,
                  depth: 6,
                  radius: 14,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  onTap: () => Navigator.of(ctx).pop(false),
                  child: const SizedBox(
                    width: double.infinity,
                    child: Center(child: BlockText('FINISH & SAVE RUN', size: 14, stroke: 3.5)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      if (!mounted) return;
      if (keep == false) await _finishAndSave();
      // keep == true: the tracker keeps going; the HUD shows a RACE OVER banner
    });
  }

  void _onClosed(String status) {
    if (_closing) return;
    _closing = true;
    final msg = status == 'declined'
        ? '$_otherName declined the duel.'
        : status == 'cancelled'
            ? 'The room was closed before the race started.'
            : 'This duel expired.';
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _dialog('\u{1F6AA}', 'ROOM CLOSED', msg);
      _exit();
    });
  }

  void _exit() {
    _countTimer?.cancel();
    _tick?.cancel();
    _posSub?.cancel();
    if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  /// Save what was run (also the loser's "keep running" distance).
  Future<void> _finishAndSave() async {
    if (_saving) return;
    setState(() => _saving = true);
    _tick?.cancel();
    _posSub?.cancel();

    String summary;
    if (_km >= 0.05 && _secs > 0) {
      try {
        final uid = _me;
        final avg = _km / (_secs / 3600.0);
        final xp = (_km * 100 + _secs / 60 * 5).toInt();
        final coins = (_km * 10).toInt();
        final start = _raceStart ?? DateTime.now().subtract(Duration(seconds: _secs));
        final session = ActivitySession(
          id: '',
          type: ActivityTypeExt.fromSpeed(avg),
          userPick: ActivityType.run,
          startTime: start,
          endTime: DateTime.now(),
          distanceKm: double.parse(_km.toStringAsFixed(3)),
          durationSeconds: _secs,
          avgSpeedKmh: double.parse(avg.toStringAsFixed(2)),
          maxSpeedKmh: double.parse(_topSpeed.toStringAsFixed(2)),
          xpEarned: xp,
          coinsEarned: coins,
          routePoints: _route,
        );
        final db = FirebaseFirestore.instance;
        final userRef = FriendsService.user(uid);
        await userRef.collection('activities').add({
          ...session.toFirestore(),
          'duel_id': widget.challengeId,
        });
        await db.runTransaction((txn) async {
          final snap = await txn.get(userRef);
          txn.update(userRef, {
            'total_km': FieldValue.increment(session.distanceKm),
            'total_sessions': FieldValue.increment(1),
            'xp': FieldValue.increment(xp),
            'coins': FieldValue.increment(coins),
            ...FriendsService.weekFields(snap.data() ?? {}, session.distanceKm),
          });
        });
        summary = '${_km.toStringAsFixed(2)} km saved  •  +$xp XP';
      } catch (_) {
        summary = 'Could not save this run. Check your connection.';
      }
    } else {
      summary = 'Too short to save (under 50 m).';
    }

    // If I leave the room before the race is decided, that is a forfeit.
    if (_status == 'active') {
      await FriendsService.leave(widget.challengeId, _me).catchError((_) {});
    }
    if (!mounted) return;
    await _dialog('\u{1F3C1}', 'RUN SAVED', summary, color: Rb.neon);
    _exit();
  }

  // ───────────────────────── leaving ─────────────────────────

  Future<void> _confirmLeave() async {
    final racing = _status == 'active' && !_post;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Block(
          color: Rb.slate,
          edge: Colors.black,
          depth: 6,
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BlockText(racing ? 'FORFEIT THE RACE?' : 'LEAVE THE ROOM?',
                  size: 16, stroke: 4, color: Rb.red, align: TextAlign.center),
              const SizedBox(height: 6),
              BlockText(
                racing
                    ? '$_otherName will win by default.'
                    : 'The duel will be cancelled.',
                size: 12, stroke: 3, align: TextAlign.center,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: PressBlock(
                      color: Rb.blue,
                      edge: Rb.blueEdge,
                      depth: 5,
                      radius: 12,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      onTap: () => Navigator.of(ctx).pop(false),
                      child: const Center(child: BlockText('STAY', size: 13, stroke: 3.5)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: PressBlock(
                      color: Rb.red,
                      edge: Rb.redEdge,
                      depth: 5,
                      radius: 12,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      onTap: () => Navigator.of(ctx).pop(true),
                      child: Center(child: BlockText(racing ? 'FORFEIT' : 'LEAVE', size: 13, stroke: 3.5)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true) return;
    await FriendsService.leave(widget.challengeId, _me).catchError((_) {});
    _exit();
  }

  Future<void> _dialog(String icon, String title, String body, {Color color = Rb.gold}) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: Block(
          color: Rb.slate,
          edge: Colors.black,
          depth: 8,
          radius: 22,
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(icon, style: const TextStyle(fontSize: 40)),
              const SizedBox(height: 6),
              BlockText(title, size: 18, stroke: 4.5, color: color, align: TextAlign.center),
              const SizedBox(height: 6),
              BlockText(body, size: 12, stroke: 3, align: TextAlign.center),
              const SizedBox(height: 16),
              PressBlock(
                color: Rb.green,
                edge: Rb.greenEdge,
                depth: 6,
                radius: 14,
                padding: const EdgeInsets.symmetric(vertical: 12),
                onTap: () => Navigator.of(ctx).pop(),
                child: const SizedBox(
                  width: double.infinity,
                  child: Center(child: BlockText('OK', size: 15, stroke: 4)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ───────────────────────── build ─────────────────────────

  String _clock(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final inRace = _racing && !_post;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_post && _racing) {
          _finishAndSave();
        } else {
          _confirmLeave();
        }
      },
      child: Scaffold(
        backgroundColor: Rb.bg,
        body: SafeArea(
          child: _ch == null
              ? const Center(child: CircularProgressIndicator(color: Rb.green))
              : Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                  child: Column(
                    children: [
                      _header(inRace),
                      const SizedBox(height: 10),
                      Expanded(child: _stage()),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _header(bool inRace) => Block(
        color: Rb.hud,
        edge: Rb.hudEdge,
        depth: 6,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            const Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: BlockText('⚔️ LIVE DUEL', size: 20, stroke: 4.5),
              ),
            ),
            Block(
              color: Rb.gold,
              edge: Rb.goldEdge,
              depth: 3,
              radius: 10,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: BlockText('${_target.toStringAsFixed(0)} KM • \u{1F48E}$_reward',
                  size: 11, stroke: 3, color: Colors.black),
            ),
            if (!_post) ...[
              const SizedBox(width: 8),
              PressBlock(
                color: Rb.red,
                edge: Rb.redEdge,
                depth: 4,
                radius: 10,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                onTap: _confirmLeave,
                child: BlockText(inRace ? 'FORFEIT' : 'LEAVE', size: 10, stroke: 3),
              ),
            ],
          ],
        ),
      );

  Widget _stage() {
    switch (_status) {
      case 'pending':
        return _center('Waiting for $_otherName to accept…');
      case 'lobby':
        return _lobby();
      case 'countdown':
        return _countdownView();
      case 'active':
      case 'done':
      case 'forfeit':
        return _raceView();
      default:
        return _center('This room is closed.');
    }
  }

  Widget _center(String t) => Center(
        child: BlockText(t, size: 14, stroke: 3.5, align: TextAlign.center),
      );

  // ── lobby ──

  Widget _playerCard(String name, Map<String, dynamic>? data, bool ready, bool isMe) {
    return Expanded(
      child: Block(
        color: ready ? const Color(0xFF1E6B45) : Rb.slate,
        edge: ready ? const Color(0xFF0B2E1D) : Rb.slateEdge,
        depth: 5,
        radius: 18,
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            HeroBust(data: data, size: 84),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: BlockText(isMe ? 'YOU' : name.toUpperCase(), size: 14, stroke: 3.5),
            ),
            const SizedBox(height: 6),
            Block(
              color: ready ? Rb.green : Rb.panel,
              edge: ready ? Rb.greenEdge : Rb.panelEdge,
              depth: 3,
              radius: 8,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: BlockText(ready ? 'READY ✔' : 'NOT READY', size: 10.5, stroke: 3),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lobby() {
    final myReady = _readyOf(_me);
    final bothIn = _readyOf(_me) && _readyOf(_otherUid);
    return SingleChildScrollView(
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _playerCard(_myName, _meData, _readyOf(_me), true),
              const SizedBox(width: 6),
              const Padding(
                padding: EdgeInsets.only(top: 50),
                child: BlockText('VS', size: 22, stroke: 5, color: Rb.gold),
              ),
              const SizedBox(width: 6),
              _playerCard(_otherName, _otherData, _readyOf(_otherUid), false),
            ],
          ),
          const SizedBox(height: 12),
          Block(
            color: Rb.panel,
            edge: Rb.panelEdge,
            depth: 4,
            radius: 14,
            padding: const EdgeInsets.all(12),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BlockText('FAIR PLAY RULES', size: 11, stroke: 3, color: Rb.gold),
                SizedBox(height: 6),
                BlockText('• Stay on this screen — leaving mid-race is a forfeit',
                    size: 10.5, stroke: 2.5),
                BlockText('• GPS only, no pausing, no timer-only runs', size: 10.5, stroke: 2.5),
                BlockText('• Fake locations and vehicle speeds do not count',
                    size: 10.5, stroke: 2.5),
                BlockText('• First to the distance wins the \u{1F48E}', size: 10.5, stroke: 2.5),
              ],
            ),
          ),
          const SizedBox(height: 12),
          BlockText(
            bothIn
                ? 'Starting…'
                : myReady
                    ? 'Waiting for $_otherName to press READY…'
                    : 'Press READY when you are at the start line.',
            size: 12,
            stroke: 3,
            align: TextAlign.center,
            color: bothIn ? Rb.neon : const Color(0xFFB8BDC4),
          ),
          const SizedBox(height: 10),
          PressBlock(
            color: myReady ? Rb.panel : Rb.green,
            edge: myReady ? Rb.panelEdge : Rb.greenEdge,
            depth: 7,
            radius: 18,
            padding: const EdgeInsets.symmetric(vertical: 14),
            onTap: bothIn ? null : _toggleReady,
            child: SizedBox(
              width: double.infinity,
              child: Center(
                child: BlockText(myReady ? 'CANCEL READY' : "I'M READY!", size: 18, stroke: 4.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── countdown ──

  Widget _countdownView() {
    final c = _count ?? FriendsService.countdownSeconds;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const BlockText('GET READY!', size: 22, stroke: 5, color: Rb.gold),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
            child: BlockText(
              c <= 0 ? 'GO!' : '$c',
              key: ValueKey(c),
              size: 130,
              stroke: 12,
              color: c <= 0 ? Rb.neon : Colors.white,
            ),
          ),
          const SizedBox(height: 14),
          BlockText('$_myName vs $_otherName', size: 13, stroke: 3.5),
          const SizedBox(height: 4),
          const BlockText('Both of you start at the same moment.',
              size: 11, stroke: 3, color: Color(0xFFB8BDC4)),
        ],
      ),
    );
  }

  // ── race ──

  Widget _lane(String name, Map<String, dynamic>? data, double km, Color c, bool isMe) {
    final frac = (km / _target).clamp(0.0, 1.0).toDouble();
    return Block(
      color: Rb.slate,
      edge: isMe ? c : Rb.slateEdge,
      depth: 4,
      radius: 14,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Column(
        children: [
          Row(
            children: [
              BlockText(isMe ? 'YOU' : name.toUpperCase(), size: 11, stroke: 3, maxLines: 1),
              const Spacer(),
              BlockText('${km.toStringAsFixed(2)} / ${_target.toStringAsFixed(0)} km',
                  size: 11, stroke: 3, color: c),
            ],
          ),
          const SizedBox(height: 6),
          LayoutBuilder(builder: (context, box) {
            const face = 40.0;
            final x = (box.maxWidth - face) * frac;
            return SizedBox(
              height: face + 6,
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: face / 2 - 3,
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: Rb.track,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: face / 2 - 3,
                    child: Container(
                      width: (box.maxWidth) * frac,
                      height: 8,
                      decoration: BoxDecoration(
                        color: c,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const Positioned(
                    right: 0,
                    top: 0,
                    child: Text('\u{1F3C1}', style: TextStyle(fontSize: 22)),
                  ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOut,
                    left: x,
                    top: 0,
                    child: HeroBust(data: data, size: face),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  /// Seconds the opponent has been silent, measured server-vs-server.
  int _opponentSilentSecs() {
    final seen = (_ch?['seen'] as Map?) ?? {};
    final mine = (seen[_me] as Timestamp?)?.toDate();
    final theirs = (seen[_otherUid] as Timestamp?)?.toDate();
    if (mine == null) return 0;
    if (theirs == null) {
      final started = (_ch?['started_at'] as Timestamp?)?.toDate();
      return started == null ? 0 : mine.difference(started).inSeconds;
    }
    final d = mine.difference(theirs).inSeconds;
    return d < 0 ? 0 : d;
  }

  Widget _raceView() {
    final myKm = _racing ? _km : _progressOf(_me);
    final theirKm = _progressOf(_otherUid);
    final pace = myKm > 0.02 ? _secs / myKm : 0.0;
    final paceText = pace <= 0
        ? "--'--\""
        : "${pace ~/ 60}'${(pace % 60).round().toString().padLeft(2, '0')}\"";
    final silent = (!_post && _status == 'active') ? _opponentSilentSecs() : 0;
    final targetReached = _post && _km >= _target;

    if (targetReached && !_targetToastShown && _post) {
      _targetToastShown = true;
    }

    return SingleChildScrollView(
      child: Column(
        children: [
          Block(
            color: Rb.panel,
            edge: Rb.panelEdge,
            depth: 5,
            radius: 16,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const BlockText('⏱', size: 20, stroke: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: BlockText(_clock(_secs), size: 38, stroke: 6),
                ),
                BlockText("$paceText/km", size: 12, stroke: 3, color: Rb.gold),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _lane(_myName, _meData, myKm, Rb.neon, true),
          const SizedBox(height: 8),
          _lane(_otherName, _otherData, theirKm, Rb.orange, false),
          const SizedBox(height: 10),
          if (_post)
            Block(
              color: _ch?['winner'] == _me ? const Color(0xFF1E6B45) : const Color(0xFF5B3A9E),
              edge: Colors.black,
              depth: 4,
              radius: 12,
              padding: const EdgeInsets.all(10),
              child: BlockText(
                _ch?['winner'] == _me
                    ? '\u{1F3C6} YOU WON — run as far as you like, then save.'
                    : targetReached
                        ? '\u{1F389} You finished ${_target.toStringAsFixed(0)} km too! Save your run.'
                        : '\u{1F3C3} $_otherName won — keep going, ${(_target - _km).clamp(0.0, 99.0).toStringAsFixed(2)} km to your goal!',
                size: 11.5,
                stroke: 3,
                align: TextAlign.center,
              ),
            ),
          if (!_post && silent >= _offlineWarnSecs)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Block(
                color: const Color(0xFF7A2A2A),
                edge: const Color(0xFF3A1010),
                depth: 4,
                radius: 12,
                padding: const EdgeInsets.all(10),
                child: Column(
                  children: [
                    BlockText(
                      silent >= _offlineClaimSecs
                          ? '$_otherName seems to have disconnected.'
                          : '$_otherName has gone quiet… (${_offlineClaimSecs - silent}s)',
                      size: 11.5,
                      stroke: 3,
                      align: TextAlign.center,
                    ),
                    if (silent >= _offlineClaimSecs) ...[
                      const SizedBox(height: 8),
                      PressBlock(
                        color: Rb.green,
                        edge: Rb.greenEdge,
                        depth: 4,
                        radius: 10,
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
                        onTap: () => FriendsService.claimWin(widget.challengeId, _me)
                            .catchError((_) => false),
                        child: const BlockText('CLAIM WIN', size: 13, stroke: 3.5),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          if (_locError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: BlockText(_locError!, size: 10.5, stroke: 3, align: TextAlign.center,
                  color: const Color(0xFFFFB3B3)),
            ),
          const SizedBox(height: 14),
          if (_post)
            PressBlock(
              color: Rb.green,
              edge: Rb.greenEdge,
              depth: 7,
              radius: 18,
              padding: const EdgeInsets.symmetric(vertical: 14),
              onTap: _saving ? null : _finishAndSave,
              child: SizedBox(
                width: double.infinity,
                child: Center(
                  child: BlockText(_saving ? 'SAVING…' : 'FINISH & SAVE RUN',
                      size: 16, stroke: 4),
                ),
              ),
            )
          else
            const BlockText('Keep moving — the race is live!',
                size: 11, stroke: 3, color: Color(0xFFB8BDC4)),
        ],
      ),
    );
  }
}
