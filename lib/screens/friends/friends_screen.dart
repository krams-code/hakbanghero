import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/friends_service.dart';
import '../../utils/player_stats.dart';
import '../../widgets/block_ui.dart';
import '../../widgets/hero_bust.dart';
import '../../widgets/hero_sprite.dart';
import 'duel_room_screen.dart';
import 'chat_screen.dart';

typedef _Doc = QueryDocumentSnapshot<Map<String, dynamic>>;

/// Friends hub: add by code, requests, friend list (stats, chat, challenge)
/// and friend challenges.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  late final String _me;
  String _myName = 'Hero';
  String _code = '';
  int _tab = 0; // 0 friends, 1 requests, 2 challenges
  bool _adding = false;
  final _addCtl = TextEditingController();

  List<_Doc> _friends = [];
  List<_Doc> _incomingRaw = [];
  Set<String> _blocked = {};

  /// Requests from people I blocked never show up.
  List<_Doc> get _incoming =>
      _incomingRaw.where((d) => !_blocked.contains(d.data()['from'])).toList();
  List<_Doc> _challenges = [];
  Map<String, Map<String, dynamic>> _chats = {}; // otherUid -> chat doc
  final Map<String, Future<Map<String, dynamic>?>> _profiles = {};
  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    _me = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (_me.isEmpty) return;

    FriendsService.user(_me).get().then((s) {
      if (!mounted) return;
      setState(() {
        _myName = s.data()?['username'] as String? ?? 'Hero';
        _blocked = ((s.data()?['blocked_uids'] as List?)?.whereType<String>() ?? const <String>[]).toSet();
      });
    });
    FriendsService.ensureCode(_me).then((c) {
      if (mounted) setState(() => _code = c);
    });

    _subs.add(FriendsService.friends(_me).snapshots().listen((s) {
      if (mounted) setState(() => _friends = s.docs);
    }, onError: (_) {}));
    _subs.add(FriendsService.requests.where('to', isEqualTo: _me).snapshots().listen((s) {
      if (mounted) {
        setState(() => _incomingRaw =
            s.docs.where((d) => d.data()['status'] == 'pending').toList());
      }
    }, onError: (_) {}));
    _subs.add(FriendsService.challenges
        .where('participants', arrayContains: _me)
        .snapshots()
        .listen((s) {
      if (mounted) setState(() => _challenges = s.docs);
    }, onError: (_) {}));
    _subs.add(FriendsService.chats
        .where('members', arrayContains: _me)
        .snapshots()
        .listen((s) {
      final m = <String, Map<String, dynamic>>{};
      for (final d in s.docs) {
        final members = (d.data()['members'] as List?)?.whereType<String>() ?? const [];
        for (final u in members) {
          if (u != _me) m[u] = d.data();
        }
      }
      if (mounted) setState(() => _chats = m);
    }, onError: (_) {}));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _addCtl.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>?> _profile(String uid) =>
      _profiles.putIfAbsent(uid, () async {
        try {
          return (await FriendsService.user(uid).get()).data();
        } catch (_) {
          return null;
        }
      });

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  bool _unread(String otherUid) {
    final c = _chats[otherUid];
    if (c == null) return false;
    if (c['last_from'] == _me || c['last_from'] == null) return false;
    final last = (c['last_at'] as Timestamp?)?.toDate();
    if (last == null) return false;
    final read = ((c['read'] as Map?)?[_me] as Timestamp?)?.toDate();
    return read == null || last.isAfter(read);
  }

  /// Duels that need me: invites to answer + rooms I can join.
  int get _incomingChallenges => _challenges.where((d) {
        final st = d.data()['status'];
        return (st == 'pending' && d.data()['to'] == _me) ||
            st == 'lobby' || st == 'countdown' || st == 'active';
      }).length;

  // ───────────────────────── actions ─────────────────────────

  /// Centered message box (used for add-friend results and duel notices).
  Future<void> _dialog({
    required String icon,
    required String title,
    required String body,
    Color color = Rb.gold,
    String button = 'OK',
  }) {
    return showDialog(
      context: context,
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
                child: SizedBox(
                  width: double.infinity,
                  child: Center(child: BlockText(button, size: 15, stroke: 4)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Step 1 of adding a friend: validate the code, then ask "is this who you mean?"
  Future<void> _add() async {
    final code = _addCtl.text.trim();
    if (_adding || code.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _adding = true);
    final r = await FriendsService.lookup(_me, code);
    if (!mounted) return;
    setState(() => _adding = false);

    final name = (r.data?['username'] as String?) ?? 'That hero';
    switch (r.status) {
      case LookupStatus.found:
        await _confirmAdd(r.uid!, r.data!);
      case LookupStatus.notFound:
        await _dialog(
          icon: '\u{1F575}️',
          title: 'NO USER FOUND',
          body: 'No hero has the code "${code.toUpperCase()}".\nCheck the code with your friend and try again.',
          color: Rb.red,
        );
      case LookupStatus.self:
        await _dialog(
          icon: '\u{1F604}',
          title: 'THAT IS YOU!',
          body: 'This is your own friend code. Share it with a friend instead.',
        );
      case LookupStatus.already:
        await _dialog(
          icon: '\u{1F91D}',
          title: 'ALREADY FRIENDS',
          body: 'You and $name are already friends.',
          color: Rb.neon,
        );
      case LookupStatus.pending:
        await _dialog(
          icon: '⏳',
          title: 'REQUEST PENDING',
          body: 'You already sent $name a request. Waiting for them to accept.',
        );
      case LookupStatus.error:
        await _dialog(
          icon: '⚠️',
          title: 'CONNECTION PROBLEM',
          body: 'Could not look that code up. Check your internet and try again.',
          color: Rb.red,
        );
    }
  }

  /// Validation card: shows the real profile before the request is sent.
  Future<void> _confirmAdd(String uid, Map<String, dynamic> data) async {
    final name = (data['username'] as String?) ?? 'Hero';
    final lp = LevelProgress.fromXp((data['xp'] as num?)?.toInt() ?? 0);
    final km = (data['total_km'] as num?)?.toDouble() ?? 0;

    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: Block(
          color: Rb.slate,
          edge: Colors.black,
          depth: 8,
          radius: 22,
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BlockText('✅ USER FOUND', size: 13, stroke: 3.5, color: Rb.neon),
              const SizedBox(height: 10),
              HeroBust(data: data, size: 96),
              const SizedBox(height: 10),
              BlockText(name, size: 20, stroke: 4.5, color: Rb.gold),
              const SizedBox(height: 2),
              BlockText('LEVEL ${lp.level}  •  ${km.toStringAsFixed(1)} km',
                  size: 12, stroke: 3),
              const SizedBox(height: 10),
              const BlockText('Send a friend request to this hero?',
                  size: 11.5, stroke: 3, align: TextAlign.center),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: PressBlock(
                      color: Rb.panel,
                      edge: Rb.panelEdge,
                      depth: 5,
                      radius: 12,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      onTap: () => Navigator.of(ctx).pop(false),
                      child: const Center(child: BlockText('CANCEL', size: 13, stroke: 3.5)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: PressBlock(
                      color: Rb.green,
                      edge: Rb.greenEdge,
                      depth: 5,
                      radius: 12,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      onTap: () => Navigator.of(ctx).pop(true),
                      child: const Center(child: BlockText('ADD FRIEND', size: 14, stroke: 4)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (yes != true || !mounted) return;

    final r = await FriendsService.requestTo(me: _me, myName: _myName, otherUid: uid);
    if (!mounted) return;
    _addCtl.clear();
    switch (r) {
      case AddResult.sent:
        await _dialog(
          icon: '\u{1F4E8}',
          title: 'REQUEST SENT!',
          body: '$name will see your request in their Friends screen. You will be friends once they accept.',
          color: Rb.neon,
        );
      case AddResult.accepted:
        await _dialog(
          icon: '\u{1F389}',
          title: 'YOU ARE NOW FRIENDS!',
          body: '$name had already asked to be your friend, so you are connected.',
          color: Rb.neon,
        );
      case AddResult.error:
        await _dialog(
          icon: '⚠️',
          title: 'COULD NOT SEND',
          body: 'Something went wrong. Please try again.',
          color: Rb.red,
        );
    }
  }

  Future<void> _challengeSheet(String friendUid, String friendName) async {
    var km = 3;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Block(
              color: Rb.slate,
              edge: Colors.black,
              depth: 8,
              radius: 22,
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BlockText('⚔️ CHALLENGE $friendName'.toUpperCase(),
                      size: 16, stroke: 4, color: Rb.gold, align: TextAlign.center),
                  const SizedBox(height: 4),
                  const BlockText('A LIVE race: you both join the same room,\nget a countdown, then run side by side.',
                      size: 10.5, stroke: 2.5, color: Color(0xFFB8BDC4), align: TextAlign.center),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      for (final k in FriendsService.rewardFor.keys) ...[
                        Expanded(
                          child: PressBlock(
                            color: km == k ? Rb.green : Rb.panel,
                            edge: km == k ? Rb.greenEdge : Rb.panelEdge,
                            depth: 4,
                            radius: 12,
                            forcePressed: km == k,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            onTap: () => setS(() => km = k),
                            child: Center(child: BlockText('$k KM', size: 13, stroke: 3.5)),
                          ),
                        ),
                        if (k != FriendsService.rewardFor.keys.last) const SizedBox(width: 6),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  BlockText('Winner gets \u{1F48E}${FriendsService.rewardFor[km]}  •  GPS only, no pausing',
                      size: 11, stroke: 3, color: Rb.neon),
                  const SizedBox(height: 14),
                  PressBlock(
                    color: Rb.orange,
                    edge: Rb.orangeEdge,
                    depth: 6,
                    radius: 16,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      try {
                        await FriendsService.sendChallenge(
                          me: _me,
                          myName: _myName,
                          otherUid: friendUid,
                          otherName: friendName,
                          km: km,
                        );
                        if (!mounted) return;
                        setState(() => _tab = 2);
                        await _dialog(
                          icon: '⚔️',
                          title: 'DUEL INVITE SENT!',
                          body: '$friendName must accept. When they do, tap ENTER ROOM on the DUELS tab and wait for them there.',
                          color: Rb.orange,
                        );
                      } catch (_) {
                        _snack('Could not send the challenge.');
                      }
                    },
                    child: const SizedBox(
                      width: double.infinity,
                      child: Center(child: BlockText('SEND CHALLENGE', size: 15, stroke: 4)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openChat(String uid, String name) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ChatScreen(friendUid: uid, friendName: name)),
      );

  Future<void> _confirmUnfriend(String uid, String name) async {
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
              BlockText('Remove $name?', size: 16, stroke: 4, align: TextAlign.center),
              const SizedBox(height: 6),
              const BlockText('You will no longer be able to chat or challenge each other.',
                  size: 11, stroke: 3, align: TextAlign.center),
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
                      child: const Center(child: BlockText('KEEP', size: 13, stroke: 3.5)),
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
                      child: const Center(child: BlockText('REMOVE', size: 13, stroke: 3.5)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (ok == true) {
      try {
        await FriendsService.unfriend(_me, uid);
        _snack('Removed $name.');
      } catch (_) {
        _snack('Could not remove. Try again.');
      }
    }
  }

  void _showProfile(String uid, String fallbackName) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: FutureBuilder<Map<String, dynamic>?>(
          future: _profile(uid),
          builder: (context, snap) {
            final d = snap.data;
            final name = (d?['username'] as String?) ?? fallbackName;
            final xp = (d?['xp'] as num?)?.toInt() ?? 0;
            final lp = LevelProgress.fromXp(xp);
            final km = (d?['total_km'] as num?)?.toDouble() ?? 0;
            final sessions = (d?['total_sessions'] as num?)?.toInt() ?? 0;

            Widget stat(String l, String v) => Expanded(
                  child: Block(
                    color: Rb.panel,
                    edge: Rb.panelEdge,
                    depth: 3,
                    radius: 10,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      children: [
                        BlockText(l, size: 8.5, stroke: 2.5, color: const Color(0xFFB8BDC4)),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: BlockText(v, size: 15, stroke: 3.5),
                        ),
                      ],
                    ),
                  ),
                );

            return Block(
              color: Rb.slate,
              edge: Colors.black,
              depth: 8,
              radius: 22,
              padding: const EdgeInsets.all(14),
              child: snap.connectionState != ConnectionState.done
                  ? const SizedBox(
                      height: 120,
                      child: Center(child: CircularProgressIndicator(color: Rb.green)))
                  : SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          BlockText(name, size: 20, stroke: 4.5, color: Rb.gold),
                          const SizedBox(height: 8),
                          Block(
                            color: const Color(0xFF8FD0FF),
                            edge: Colors.black,
                            depth: 4,
                            radius: 14,
                            padding: EdgeInsets.zero,
                            child: SizedBox(
                              height: 190,
                              width: 150,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(11),
                                child: FittedBox(
                                  fit: BoxFit.contain,
                                  child: HeroSprite.fromData(d, height: 220),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          BlockText('LEVEL ${lp.level}', size: 13, stroke: 3.5, color: Rb.neon),
                          const SizedBox(height: 4),
                          BlockBar(value: lp.fraction, height: 10, color: Rb.green),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              stat('TOTAL KM', km.toStringAsFixed(1)),
                              const SizedBox(width: 6),
                              stat('RUNS', '$sessions'),
                              const SizedBox(width: 6),
                              stat('XP', '$xp'),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: PressBlock(
                                  color: Rb.blue,
                                  edge: Rb.blueEdge,
                                  depth: 4,
                                  radius: 12,
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  onTap: () {
                                    Navigator.of(ctx).pop();
                                    _openChat(uid, name);
                                  },
                                  child: const Center(child: BlockText('\u{1F4AC} CHAT', size: 12, stroke: 3.5)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: PressBlock(
                                  color: Rb.orange,
                                  edge: Rb.orangeEdge,
                                  depth: 4,
                                  radius: 12,
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  onTap: () {
                                    Navigator.of(ctx).pop();
                                    _challengeSheet(uid, name);
                                  },
                                  child: const Center(child: BlockText('⚔️ DUEL', size: 12, stroke: 3.5)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: () {
                              Navigator.of(ctx).pop();
                              _confirmUnfriend(uid, name);
                            },
                            child: const Padding(
                              padding: EdgeInsets.all(6),
                              child: BlockText('Remove friend', size: 10.5, stroke: 2.5,
                                  color: Color(0xFFFF9A9A)),
                            ),
                          ),
                        ],
                      ),
                    ),
            );
          },
        ),
      ),
    );
  }

  // ───────────────────────── build ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Rb.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
          child: Column(
            children: [
              _header(),
              const SizedBox(height: 10),
              _codeCard(),
              const SizedBox(height: 10),
              _tabs(),
              const SizedBox(height: 10),
              Expanded(child: _body()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() => Block(
        color: Rb.hud,
        edge: Rb.hudEdge,
        depth: 6,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            PressBlock(
              color: Rb.red,
              edge: Rb.redEdge,
              depth: 4,
              radius: 10,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              onTap: () => Navigator.of(context).maybePop(),
              child: const BlockText('◀', size: 14, stroke: 3.5),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: BlockText('\u{1F465} FRIENDS', size: 20, stroke: 4.5),
              ),
            ),
          ],
        ),
      );

  Widget _codeCard() => Block(
        color: Rb.slate,
        edge: Rb.slateEdge,
        depth: 5,
        radius: 16,
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Row(
              children: [
                const BlockText('YOUR CODE', size: 10, stroke: 3, color: Color(0xFFB8BDC4)),
                const SizedBox(width: 10),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: BlockText(_code.isEmpty ? '...' : _code,
                        size: 22, stroke: 4.5, color: Rb.neon),
                  ),
                ),
                PressBlock(
                  color: Rb.blue,
                  edge: Rb.blueEdge,
                  depth: 4,
                  radius: 10,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  onTap: _code.isEmpty
                      ? null
                      : () {
                          Clipboard.setData(ClipboardData(text: _code));
                          _snack('Code copied!');
                        },
                  child: const BlockText('COPY', size: 11, stroke: 3),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Rb.panel,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.black, width: 3),
                    ),
                    child: TextField(
                      controller: _addCtl,
                      textCapitalization: TextCapitalization.characters,
                      onSubmitted: (_) => _add(),
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14),
                      cursorColor: Rb.neon,
                      decoration: const InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 11),
                        hintText: "Friend's code (HERO-XXXX)",
                        hintStyle: TextStyle(color: Colors.white38, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                PressBlock(
                  color: Rb.green,
                  edge: Rb.greenEdge,
                  depth: 4,
                  radius: 16,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  onTap: _adding ? null : _add,
                  child: BlockText(_adding ? '...' : 'ADD', size: 13, stroke: 3.5),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _tabs() {
    Widget pill(int i, String label, int badge) {
      final sel = _tab == i;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: PressBlock(
            color: sel ? Rb.gold : Rb.panel,
            edge: sel ? Rb.goldEdge : Rb.panelEdge,
            depth: 4,
            radius: 12,
            forcePressed: sel,
            padding: const EdgeInsets.symmetric(vertical: 9),
            onTap: () => setState(() => _tab = i),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: BlockText(badge > 0 ? '$label ($badge)' : label,
                    size: 11, stroke: 3.5),
              ),
            ),
          ),
        ),
      );
    }

    final unreadAny = _friends.any((f) => _unread(f.id));
    return Row(
      children: [
        pill(0, unreadAny ? 'FRIENDS \u{1F534}' : 'FRIENDS', 0),
        pill(1, 'REQUESTS', _incoming.length),
        pill(2, 'DUELS', _incomingChallenges),
      ],
    );
  }

  Widget _body() {
    switch (_tab) {
      case 1:
        return _requestsTab();
      case 2:
        return _challengesTab();
      default:
        return _friendsTab();
    }
  }

  Widget _empty(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: BlockText(text, size: 12, stroke: 3, align: TextAlign.center,
              color: const Color(0xFFB8BDC4)),
        ),
      );

  // ───────────────────────── friends ─────────────────────────

  Widget _friendsTab() {
    if (_friends.isEmpty) {
      return _empty('No friends yet.\nShare your code or enter a friend\'s code above!');
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 20),
      itemCount: _friends.length,
      itemBuilder: (_, i) {
        final f = _friends[i];
        final name = f.data()['name'] as String? ?? 'Hero';
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: PressBlock(
            color: Rb.slate,
            edge: Rb.slateEdge,
            depth: 5,
            radius: 16,
            padding: const EdgeInsets.all(8),
            onTap: () => _showProfile(f.id, name),
            child: Row(
              children: [
                _Bust(profile: _profile(f.id)),
                const SizedBox(width: 10),
                Expanded(
                  child: FutureBuilder<Map<String, dynamic>?>(
                    future: _profile(f.id),
                    builder: (_, s) {
                      final d = s.data;
                      final lv = LevelProgress.fromXp((d?['xp'] as num?)?.toInt() ?? 0).level;
                      final km = (d?['total_km'] as num?)?.toDouble() ?? 0;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          BlockText((d?['username'] as String?) ?? name,
                              size: 14, stroke: 3.5, maxLines: 1),
                          const SizedBox(height: 2),
                          Text('LV $lv · ${km.toStringAsFixed(1)} km',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w800)),
                        ],
                      );
                    },
                  ),
                ),
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    PressBlock(
                      color: Rb.blue,
                      edge: Rb.blueEdge,
                      depth: 4,
                      radius: 12,
                      padding: const EdgeInsets.all(10),
                      onTap: () => _openChat(f.id, name),
                      child: const Text('\u{1F4AC}', style: TextStyle(fontSize: 18)),
                    ),
                    if (_unread(f.id))
                      Positioned(
                        right: -4,
                        top: -4,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: Rb.red,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.black, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 8),
                PressBlock(
                  color: Rb.orange,
                  edge: Rb.orangeEdge,
                  depth: 4,
                  radius: 12,
                  padding: const EdgeInsets.all(10),
                  onTap: () => _challengeSheet(f.id, name),
                  child: const Text('⚔️', style: TextStyle(fontSize: 18)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ───────────────────────── requests ─────────────────────────

  Widget _requestsTab() {
    if (_incoming.isEmpty) return _empty('No pending requests.');
    return ListView(
      padding: const EdgeInsets.only(bottom: 20),
      children: [
        for (final r in _incoming)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Block(
              color: Rb.slate,
              edge: Rb.slateEdge,
              depth: 5,
              radius: 16,
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Expanded(
                    child: BlockText('${r.data()['from_name'] ?? 'A hero'} wants to be friends',
                        size: 12, stroke: 3, maxLines: 2),
                  ),
                  const SizedBox(width: 8),
                  PressBlock(
                    color: Rb.green,
                    edge: Rb.greenEdge,
                    depth: 4,
                    radius: 10,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    onTap: () async {
                      try {
                        await FriendsService.accept(
                            me: _me, myName: _myName, fromUid: r.data()['from'] as String);
                        _snack('\u{1F389} Friend added!');
                      } catch (_) {
                        _snack('Could not accept. Try again.');
                      }
                    },
                    child: const BlockText('ACCEPT', size: 11, stroke: 3),
                  ),
                  const SizedBox(width: 6),
                  PressBlock(
                    color: Rb.red,
                    edge: Rb.redEdge,
                    depth: 4,
                    radius: 10,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    onTap: () => FriendsService.decline(r.data()['from'] as String, _me)
                        .catchError((_) {}),
                    child: const BlockText('✕', size: 12, stroke: 3),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ───────────────────────── challenges ─────────────────────────

  void _enterRoom(String challengeId) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => DuelRoomScreen(challengeId: challengeId)),
      );

  Widget _challengesTab() {
    bool st(_Doc d, String s) => d.data()['status'] == s;
    final pendingIn =
        _challenges.where((d) => st(d, 'pending') && d.data()['to'] == _me).toList();
    final pendingOut =
        _challenges.where((d) => st(d, 'pending') && d.data()['from'] == _me).toList();
    final live = _challenges
        .where((d) => st(d, 'lobby') || st(d, 'countdown') || st(d, 'active'))
        .toList();
    final done = _challenges
        .where((d) => st(d, 'done') || st(d, 'forfeit'))
        .toList()
      ..sort((a, b) {
        final ta = (a.data()['finished_at'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
        final tb = (b.data()['finished_at'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
        return tb.compareTo(ta);
      });

    if (pendingIn.isEmpty && pendingOut.isEmpty && live.isEmpty && done.isEmpty) {
      return _empty('No duels yet.\nTap ⚔️ next to a friend to challenge them to a live race!');
    }

    String other(_Doc d) =>
        (d.data()['from'] == _me ? d.data()['to_name'] : d.data()['from_name']) as String? ??
        'Hero';

    Widget card(Color c, Color e, List<Widget> kids) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Block(
            color: c,
            edge: e,
            depth: 5,
            radius: 16,
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: kids),
          ),
        );

    return ListView(
      padding: const EdgeInsets.only(bottom: 20),
      children: [
        for (final d in pendingIn)
          card(const Color(0xFF7A3B0A), const Color(0xFF3A1B00), [
            BlockText('⚔️ ${other(d)} challenges you!', size: 13, stroke: 3.5),
            const SizedBox(height: 2),
            BlockText(
                'Live ${d.data()['distance_km']} km race  •  winner \u{1F48E}${d.data()['reward']}',
                size: 10.5, stroke: 3),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: PressBlock(
                    color: Rb.green,
                    edge: Rb.greenEdge,
                    depth: 4,
                    radius: 10,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    onTap: () async {
                      try {
                        await FriendsService.acceptChallenge(d.id);
                        _enterRoom(d.id);
                      } catch (_) {
                        _dialog(
                          icon: '⚠️',
                          title: 'COULD NOT ACCEPT',
                          body: 'Please try again.',
                          color: Rb.red,
                        );
                      }
                    },
                    child: const Center(child: BlockText('ACCEPT & ENTER', size: 11, stroke: 3.5)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: PressBlock(
                    color: Rb.red,
                    edge: Rb.redEdge,
                    depth: 4,
                    radius: 10,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    onTap: () =>
                        FriendsService.declineChallenge(d.id).catchError((_) {}),
                    child: const Center(child: BlockText('DECLINE', size: 12, stroke: 3.5)),
                  ),
                ),
              ],
            ),
          ]),
        for (final d in live)
          card(const Color(0xFF1E5F8F), const Color(0xFF0A2B45), [
            BlockText('\u{1F534} LIVE: YOU vs ${other(d).toUpperCase()}',
                size: 13, stroke: 3.5, maxLines: 1),
            BlockText(
              d.data()['status'] == 'active'
                  ? 'Race in progress — rejoin now!'
                  : d.data()['status'] == 'countdown'
                      ? 'Starting… get in the room!'
                      : 'Room is open — both players must press READY',
              size: 10.5,
              stroke: 3,
              color: const Color(0xFFB8D4EA),
            ),
            const SizedBox(height: 8),
            PressBlock(
              color: Rb.orange,
              edge: Rb.orangeEdge,
              depth: 5,
              radius: 12,
              padding: const EdgeInsets.symmetric(vertical: 10),
              onTap: () => _enterRoom(d.id),
              child: SizedBox(
                width: double.infinity,
                child: Center(
                  child: BlockText(
                      'ENTER ROOM • ${d.data()['distance_km']} KM • \u{1F48E}${d.data()['reward']}',
                      size: 12, stroke: 3.5),
                ),
              ),
            ),
          ]),
        for (final d in pendingOut)
          card(Rb.slate, Rb.slateEdge, [
            BlockText('Waiting for ${other(d)} to accept…', size: 12, stroke: 3),
            BlockText('${d.data()['distance_km']} km  •  \u{1F48E}${d.data()['reward']}',
                size: 10, stroke: 2.5, color: const Color(0xFFB8BDC4)),
          ]),
        if (done.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(2, 8, 0, 6),
            child: BlockText('HISTORY', size: 11, stroke: 3, color: Rb.gold),
          ),
          for (final d in done.take(8))
            card(Rb.slate, Rb.slateEdge, [
              BlockText(
                d.data()['winner'] == _me
                    ? '\u{1F3C6} You beat ${other(d)} — +\u{1F48E}${d.data()['reward']}'
                    : d.data()['status'] == 'forfeit'
                        ? '${other(d)} left the race'
                        : '${other(d)} won this duel (${d.data()['distance_km']} km)',
                size: 11.5,
                stroke: 3,
                color: d.data()['winner'] == _me ? Rb.neon : Colors.white,
              ),
            ]),
        ],
      ],
    );
  }
}

/// Small face crop for a friend (same trick as the leaderboard thumbnail).
class _Bust extends StatelessWidget {
  final Future<Map<String, dynamic>?> profile;
  const _Bust({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Block(
      color: const Color(0xFF8FD0FF),
      edge: Colors.black,
      depth: 3,
      radius: 12,
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: SizedBox(
          width: 56,
          height: 56,
          child: FutureBuilder<Map<String, dynamic>?>(
            future: profile,
            builder: (_, s) {
              if (s.data == null) return const SizedBox.shrink();
              return ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topCenter,
                  minWidth: 0,
                  maxWidth: double.infinity,
                  minHeight: 0,
                  maxHeight: double.infinity,
                  child: Transform.translate(
                    offset: const Offset(0, 56 * 0.2),
                    child: HeroSprite.fromData(s.data, height: 56 * 2.4),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
