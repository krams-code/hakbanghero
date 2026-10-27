import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/block_ui.dart';

enum PresenceStatus { online, idle, offline }

/// Who is around right now.
///
///   presence/{uid}.presence     'online' | 'idle' | 'offline'
///   presence/{uid}.presence_at  server time of the last heartbeat
///
/// A small doc of its own (not the big user doc): heartbeats then don't make
/// every leaderboard / friend list re-download whole profiles.
///
/// The app writes a heartbeat every 60 s. A player is
///   * ONLINE  (green)  - app open and touched in the last 3 minutes
///                         (a run in progress always counts as online),
///   * IDLE    (orange) - app open but no touch for 3 minutes,
///   * OFFLINE (red)    - app closed / in the background / logged out, or no
///                         heartbeat for 100 s (crash, lost signal, closed tab).
/// Readers listen to the user document, so changes show up in real time.
class Presence with WidgetsBindingObserver {
  Presence._();
  static final Presence I = Presence._();

  static const Duration beat = Duration(seconds: 60);
  static const Duration idleAfter = Duration(minutes: 3);
  static const Duration staleAfter = Duration(seconds: 150);

  static DocumentReference<Map<String, dynamic>> doc(String uid) =>
      FirebaseFirestore.instance.collection('presence').doc(uid);

  /// Settings switch: toast when a friend comes online.
  final ValueNotifier<bool> friendAlerts = ValueNotifier<bool>(true);
  static const String _kAlerts = 'friend_online_alerts';

  bool get isHolding => _hold;

  Future<void> loadPrefs() async {
    try {
      final sp = await SharedPreferences.getInstance();
      friendAlerts.value = sp.getBool(_kAlerts) ?? true;
    } catch (_) {}
  }

  Future<void> setFriendAlerts(bool on) async {
    friendAlerts.value = on;
    try {
      (await SharedPreferences.getInstance()).setBool(_kAlerts, on);
    } catch (_) {}
  }

  String? _uid;
  Timer? _timer;
  DateTime _lastInput = DateTime.now();
  String _last = '';
  bool _hold = false;
  bool _fg = true;
  bool _observing = false;

  /// Call once the player is signed in (MainShell).
  void start(String uid) {
    if (_uid == uid && _timer != null) return;
    _uid = uid;
    loadPrefs();
    _fg = true;
    _lastInput = DateTime.now();
    _last = '';
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    _timer?.cancel();
    _timer = Timer.periodic(beat, (_) => _push());
    _push();
  }

  /// Log out: tell everyone right away instead of waiting for the timeout.
  Future<void> stop() async {
    final uid = _uid;
    _timer?.cancel();
    _timer = null;
    _uid = null;
    _last = '';
    if (uid == null) return;
    try {
      await _write(uid, 'offline').timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  /// Any tap / click / drag in the app.
  void touch() {
    _lastInput = DateTime.now();
    if (_last == 'idle') _push();
  }

  /// While a run is in progress the screen is not touched for a long time,
  /// but the player is clearly there.
  void holdActive(bool v) {
    _hold = v;
    if (v) touch();
  }

  String _current() {
    if (!_fg) return 'offline';
    if (_hold) return 'online';
    return DateTime.now().difference(_lastInput) >= idleAfter ? 'idle' : 'online';
  }

  void _push() {
    final uid = _uid;
    if (uid == null) return;
    final s = _current();
    if (s == 'offline' && _last == 'offline') return; // nothing new to say
    _last = s;
    _write(uid, s);
  }

  Future<void> _write(String uid, String s) async {
    try {
      await doc(uid).set({
        'presence': s,
        'presence_at': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _fg = true;
        _lastInput = DateTime.now();
        _last = '';
        _push();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _fg = false;
        _push();
        break;
      case AppLifecycleState.inactive:
        break; // short interruptions (a dialog, window focus) do not count
    }
  }

  /// Status as seen by someone reading [d] (a user document).
  static PresenceStatus statusOf(Map<String, dynamic>? d) {
    final p = d?['presence'];
    if (p != 'online' && p != 'idle') return PresenceStatus.offline;
    final at = d?['presence_at'];
    if (at is Timestamp && DateTime.now().difference(at.toDate()) > staleAfter) {
      return PresenceStatus.offline;
    }
    return p == 'idle' ? PresenceStatus.idle : PresenceStatus.online;
  }

  /// "just now", "5m ago", "3h ago", "2d ago" (null when never seen).
  static String? lastSeen(Map<String, dynamic>? d) {
    final at = d?['presence_at'];
    if (at is! Timestamp) return null;
    final diff = DateTime.now().difference(at.toDate());
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  static Color colorOf(PresenceStatus s) => switch (s) {
        PresenceStatus.online => const Color(0xFF2ECC40),
        PresenceStatus.idle => const Color(0xFFFF9F1A),
        PresenceStatus.offline => const Color(0xFFE53935),
      };

  static String labelOf(PresenceStatus s) => switch (s) {
        PresenceStatus.online => 'ONLINE',
        PresenceStatus.idle => 'IDLE',
        PresenceStatus.offline => 'OFFLINE',
      };
}

/// The little coloured dot (green / orange / red).
class PresenceDot extends StatelessWidget {
  final PresenceStatus status;
  final double size;
  const PresenceDot(this.status, {super.key, this.size = 14});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Presence.colorOf(status),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.black, width: size >= 14 ? 2.5 : 2),
        ),
      );
}

/// "● ONLINE" chip.
class PresenceLabel extends StatelessWidget {
  final PresenceStatus status;

  /// shown after OFFLINE, e.g. "3h ago"
  final String? lastSeen;
  const PresenceLabel(this.status, {super.key, this.lastSeen});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PresenceDot(status, size: 11),
          const SizedBox(width: 5),
          BlockText(
            status == PresenceStatus.offline && lastSeen != null
                ? 'OFFLINE \u00B7 LAST SEEN ${lastSeen!.toUpperCase()}'
                : Presence.labelOf(status),
            size: 10.5,
            stroke: 3,
          ),
        ],
      );
}

/// Real-time status of one player: listens to their user document and also
/// re-checks every 15 s so a missing heartbeat turns the dot red on its own.
class PresenceBuilder extends StatefulWidget {
  final String uid;
  final Widget Function(BuildContext, PresenceStatus)? builder;

  /// Same, plus the "last seen" text.
  final Widget Function(BuildContext, PresenceStatus, String? lastSeen)? infoBuilder;
  const PresenceBuilder(
      {super.key, required this.uid, this.builder, this.infoBuilder})
      : assert(builder != null || infoBuilder != null);

  @override
  State<PresenceBuilder> createState() => _PresenceBuilderState();
}

class _PresenceBuilderState extends State<PresenceBuilder> {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  Timer? _tick;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _listen();
    _tick = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  void _listen() {
    _sub?.cancel();
    _sub = Presence.doc(widget.uid).snapshots().listen((s) {
      if (mounted) setState(() => _data = s.data());
    }, onError: (_) {});
  }

  @override
  void didUpdateWidget(PresenceBuilder old) {
    super.didUpdateWidget(old);
    if (old.uid != widget.uid) {
      _data = null;
      _listen();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = Presence.statusOf(_data);
    return widget.infoBuilder != null
        ? widget.infoBuilder!(context, st, Presence.lastSeen(_data))
        : widget.builder!(context, st);
  }
}

/// Tells the app when one of MY friends comes online (offline -> online).
/// Started by MainShell; shows nothing for friends who were already online.
class FriendWatcher {
  final String uid;
  final void Function(String name) onOnline;
  FriendWatcher(this.uid, this.onOnline);

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _list;
  final Map<String, StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>> _subs = {};
  final Map<String, Map<String, dynamic>?> _data = {};
  final Map<String, PresenceStatus> _last = {};
  final Map<String, DateTime> _toastAt = {};
  final Map<String, String> _names = {};
  Timer? _tick;

  void start() {
    _list = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('friends')
        .snapshots()
        .listen((snap) {
      final ids = snap.docs.map((d) => d.id).toSet();
      for (final d in snap.docs) {
        _names[d.id] = (d.data()['name'] as String?) ?? 'A friend';
        if (_subs.containsKey(d.id)) continue;
        _subs[d.id] = Presence.doc(d.id).snapshots().listen((u) {
          _data[d.id] = u.data();
          _eval(d.id);
        }, onError: (_) {});
      }
      for (final gone in _subs.keys.where((k) => !ids.contains(k)).toList()) {
        _subs.remove(gone)?.cancel();
        _data.remove(gone);
        _last.remove(gone);
      }
    }, onError: (_) {});
    // a friend whose heartbeat just stops goes offline without a new snapshot
    _tick = Timer.periodic(const Duration(seconds: 20), (_) {
      for (final id in _subs.keys) {
        _eval(id);
      }
    });
  }

  void _eval(String id) {
    final st = Presence.statusOf(_data[id]);
    final prev = _last[id];
    _last[id] = st;
    if (prev != PresenceStatus.offline || st != PresenceStatus.online) return;
    if (!Presence.I.friendAlerts.value || Presence.I.isHolding) return;
    final last = _toastAt[id];
    if (last != null && DateTime.now().difference(last) < const Duration(minutes: 10)) {
      return;
    }
    _toastAt[id] = DateTime.now();
    onOnline((_data[id]?['username'] as String?) ?? _names[id] ?? 'A friend');
  }

  void dispose() {
    _list?.cancel();
    _tick?.cancel();
    for (final s in _subs.values) {
      s.cancel();
    }
    _subs.clear();
  }
}

/// Dot for a user document you already have (leaderboard rows). Re-checks the
/// heartbeat age every 15 s; the document itself updates through its stream.
class PresenceDotFromData extends StatefulWidget {
  final Map<String, dynamic> data;
  final double size;
  const PresenceDotFromData(this.data, {super.key, this.size = 14});

  @override
  State<PresenceDotFromData> createState() => _PresenceDotFromDataState();
}

class _PresenceDotFromDataState extends State<PresenceDotFromData> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      PresenceDot(Presence.statusOf(widget.data), size: widget.size);
}

/// Status dot read ONCE (cached ~1 min) - for long lists like the leaderboard,
/// where 100 live listeners would cost a lot of Firestore reads.
class PresenceDotOnce extends StatelessWidget {
  final String uid;
  final double size;
  const PresenceDotOnce(this.uid, {super.key, this.size = 14});

  static final Map<String, (DateTime, Future<Map<String, dynamic>?>)> _cache = {};

  static Future<Map<String, dynamic>?> _get(String uid) {
    final hit = _cache[uid];
    if (hit != null && DateTime.now().difference(hit.$1) < const Duration(minutes: 1)) {
      return hit.$2;
    }
    final f = Presence.doc(uid)
        .get()
        .then<Map<String, dynamic>?>((s) => s.data())
        .catchError((Object _) => null);
    _cache[uid] = (DateTime.now(), f);
    return f;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>?>(
        future: _get(uid),
        builder: (context, snap) =>
            PresenceDot(Presence.statusOf(snap.data), size: size),
      );
}
