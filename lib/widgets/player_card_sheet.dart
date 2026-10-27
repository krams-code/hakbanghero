import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/friends_service.dart';
import '../services/presence.dart';
import 'block_ui.dart';
import 'hero_sprite.dart';
import '../models/badge_definitions.dart';
import '../models/hero_roster.dart';
import 'badges_panel.dart';
import '../utils/player_stats.dart' show LevelProgress;

/// Tap a player on the leaderboard -> a small "profile card" with their
/// summarized totals (read-only, built from the public user doc).
Future<void> showPlayerCard(
  BuildContext context, {
  required String uid,
  required Map<String, dynamic> data,
  required int rank,
  required bool isMe,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: _PlayerCard(uid: uid, d: data, rank: rank, isMe: isMe),
      ),
    ),
  );
}

num _n(dynamic v) => v is num ? v : 0;

class _PlayerCard extends StatefulWidget {
  final String uid;
  final Map<String, dynamic> d;
  final int rank;
  final bool isMe;
  const _PlayerCard(
      {required this.uid, required this.d, required this.rank, required this.isMe});

  @override
  State<_PlayerCard> createState() => _PlayerCardState();
}

class _PlayerCardState extends State<_PlayerCard> {
  Relation? _rel; // null = still checking
  bool _busy = false;
  String? _note;

  String get uid => widget.uid;
  Map<String, dynamic> get d => widget.d;
  int get rank => widget.rank;
  bool get isMe => widget.isMe;
  String? get _me => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    final me = _me;
    if (isMe || me == null) {
      _rel = Relation.error;
    } else {
      FriendsService.relation(me, uid).then((r) {
        if (mounted) setState(() => _rel = r);
      });
    }
  }

  Future<void> _add() async {
    final me = _me;
    if (me == null || _busy) return;
    setState(() => _busy = true);
    String myName = 'A hero';
    try {
      final m = await FriendsService.user(me).get();
      myName = (m.data()?['username'] as String?) ?? myName;
    } catch (_) {}
    final r = await FriendsService.requestTo(me: me, myName: myName, otherUid: uid);
    if (!mounted) return;
    setState(() {
      _busy = false;
      switch (r) {
        case AddResult.sent:
          _rel = Relation.sent;
          _note = 'Friend request sent!';
        case AddResult.accepted:
          _rel = Relation.friend;
          _note = 'You are friends now!';
        case AddResult.error:
          _note = 'Could not send the request. Try again.';
      }
    });
  }

  Widget _friendButton() {
    if (isMe || _rel == null || _rel == Relation.error) {
      return const SizedBox.shrink();
    }
    String label;
    Color c = Rb.green, e = Rb.greenEdge;
    VoidCallback? tap;
    switch (_rel!) {
      case Relation.friend:
        label = '\u2705 FRIENDS';
        c = Rb.slate;
        e = Rb.slateEdge;
      case Relation.sent:
        label = '\u23F3 REQUEST SENT';
        c = Rb.slate;
        e = Rb.slateEdge;
      case Relation.incoming:
        label = '\u2795 ACCEPT REQUEST';
        tap = _add;
      default:
        label = _busy ? '...' : '\u2795 ADD FRIEND';
        tap = _busy ? null : _add;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PressBlock(
        color: c,
        edge: e,
        depth: 6,
        radius: 14,
        padding: const EdgeInsets.symmetric(vertical: 12),
        onTap: tap,
        child: SizedBox(
          width: double.infinity,
          child: Center(child: BlockText(label, size: 15, stroke: 4)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = (d['username'] as String?) ?? 'Hero';
    final xp = _n(d['xp']).toInt();
    final level = LevelProgress.fromXp(xp).level;
    final km = _n(d['total_km']).toDouble();
    final runs = _n(d['total_sessions']).toInt();
    final intervals = _n(d['interval_runs']).toInt();
    final stages = d['stage_records'] is Map ? (d['stage_records'] as Map) : const {};
    var stars = 0;
    for (final v in stages.values) {
      if (v is num) stars += v.toInt();
    }
    final owned = d['owned_heroes'] is List ? (d['owned_heroes'] as List).length : 1;
    final hero = heroById(heroIdOf(d));
    final girl = genderKey(d['gender']) == 'female';
    final created = d['created_at'];
    final since = created is Timestamp ? _month(created.toDate()) : null;
    final avg = runs > 0 ? km / runs : 0.0;

    return Block(
      color: const Color(0xFF9A9EA3),
      edge: Colors.black,
      depth: 8,
      radius: 22,
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Block(
              color: const Color(0xFF8FD0FF),
              edge: Colors.black,
              depth: 4,
              radius: 14,
              padding: EdgeInsets.zero,
              child: SizedBox(
                width: 84,
                height: 104,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: HeroSprite.fromData(d, height: 100, ownerUid: uid),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BlockText(name, size: 19, stroke: 4.5, maxLines: 1),
                  const SizedBox(height: 4),
                  PresenceBuilder(
                    uid: uid,
                    infoBuilder: (_, st, seen) => PresenceLabel(
                        isMe ? PresenceStatus.online : st,
                        lastSeen: seen),
                  ),
                  const SizedBox(height: 3),
                  Text('RANK #$rank${isMe ? '  ·  YOU' : ''}',
                      style: const TextStyle(
                          color: Color(0xFF1F2327),
                          fontSize: 12,
                          fontWeight: FontWeight.w900)),
                  if (hero != null)
                    Text(
                        hero.costume
                            ? 'Costume: ${hero.name}'
                            : 'Hero: ${heroDisplayName(hero, girl: girl)}',
                        style: const TextStyle(
                            color: Color(0xFF3A4046),
                            fontSize: 12,
                            fontWeight: FontWeight.w800)),
                  if (since != null)
                    Text('Playing since $since',
                        style: const TextStyle(
                            color: Color(0xFF3A4046),
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            _stat('LEVEL', '$level', Rb.blue, Rb.blueEdge),
            const SizedBox(width: 8),
            _stat('TOTAL XP', _fmt(xp), Rb.orange, Rb.orangeEdge),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            _stat('DISTANCE', '${km.toStringAsFixed(1)} km', Rb.green, Rb.greenEdge),
            const SizedBox(width: 8),
            _stat('TOTAL RUNS', '$runs', Rb.green, Rb.greenEdge),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            _stat('AVG / RUN', '${avg.toStringAsFixed(2)} km', Rb.slate, Rb.slateEdge),
            const SizedBox(width: 8),
            _stat('STAGE STARS', '$stars ⭐', Rb.gold, Rb.goldEdge),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            _stat('INTERVAL RUNS', '$intervals', Rb.slate, Rb.slateEdge),
            const SizedBox(width: 8),
            _stat('HEROES', '$owned', Rb.slate, Rb.slateEdge),
          ]),
          const SizedBox(height: 12),
          _badgesRow(),
          const SizedBox(height: 14),
          _friendButton(),
          if (_note != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(_note!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Color(0xFF1F2327),
                      fontSize: 12,
                      fontWeight: FontWeight.w900)),
            ),
          PressBlock(
            color: Rb.blue,
            edge: Rb.blueEdge,
            depth: 6,
            radius: 14,
            padding: const EdgeInsets.symmetric(vertical: 12),
            onTap: () => Navigator.of(context).pop(),
            child: const SizedBox(
              width: double.infinity,
              child: Center(child: BlockText('CLOSE', size: 15, stroke: 4)),
            ),
          ),
        ],
      ),
    );
  }

  /// Badges anyone can verify from the public user doc (sessions, km, level).
  Widget _badgesRow() {
    final stats = BadgeStats.fromPublic(d);
    final earned =
        kBadges.where((b) => b.public && b.unlocked(stats)).toList();
    return Block(
      color: Rb.slate,
      edge: Rb.slateEdge,
      depth: 4,
      radius: 12,
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const BlockText('🎖️ BADGES', size: 12, stroke: 3),
            const Spacer(),
            BlockText('${earned.length}',
                size: 12, stroke: 3, color: Rb.gold),
          ]),
          const SizedBox(height: 8),
          if (earned.isEmpty)
            const BlockText('No badges yet.',
                size: 10, stroke: 2.5, color: Color(0xFFB8BDC4))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final b in earned)
                  BadgeMedal(badge: b, unlocked: true, size: 52),
              ],
            ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color c, Color e) => Expanded(
        child: Block(
          color: c,
          edge: e,
          depth: 4,
          radius: 12,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Column(children: [
            Text(label,
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6)),
            const SizedBox(height: 2),
            FittedBox(
                fit: BoxFit.scaleDown,
                child: BlockText(value, size: 15, stroke: 3.5, maxLines: 1)),
          ]),
        ),
      );

  static String _fmt(int v) => v >= 10000
      ? '${(v / 1000).toStringAsFixed(1)}k'
      : v.toString();

  static String _month(DateTime t) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${m[t.month - 1]} ${t.year}';
  }
}
