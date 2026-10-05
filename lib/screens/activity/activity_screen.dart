import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../models/activity_model.dart';
import '../../widgets/block_ui.dart';

/// Roblox block-style Activity log.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  ActivityType? _filter;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  static (Color, Color) _colors(ActivityType t) {
    switch (t) {
      case ActivityType.walk:
        return (const Color(0xFF7EE08A), const Color(0xFF2F7A3B));
      case ActivityType.jog:
        return (const Color(0xFF2EC4FF), const Color(0xFF0A6C99));
      case ActivityType.run:
        return (Rb.orange, Rb.orangeEdge);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = _uid;
    return Scaffold(
      backgroundColor: Rb.bg,
      body: SafeArea(
        bottom: false,
        child: uid == null
            ? const Center(child: BlockText('SIGN IN TO SEE ACTIVITY', size: 16))
            : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(uid)
                    .collection('activities')
                    .orderBy('startTime', descending: true)
                    .snapshots(),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return _message('⚠️', 'COULD NOT LOAD ACTIVITY',
                        'Check your connection and try again.');
                  }
                  if (!snap.hasData) {
                    return const Center(
                        child: CircularProgressIndicator(color: Rb.gold));
                  }
                  final all = <ActivitySession>[];
                  for (final d in snap.data!.docs) {
                    try {
                      all.add(ActivitySession.fromFirestore(d));
                    } catch (_) {}
                  }
                  return _content(all);
                },
              ),
      ),
    );
  }

  Widget _content(List<ActivitySession> all) {
    final list =
        _filter == null ? all : all.where((s) => s.type == _filter).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
      children: [
        _header(all.length),
        const SizedBox(height: 14),
        _filters(),
        const SizedBox(height: 14),
        if (all.isEmpty)
          _message('🏃', 'NO RUNS YET', 'Hit RUN to log your first session!')
        else ...[
          _summary(list),
          const SizedBox(height: 14),
          _chart(list),
          const SizedBox(height: 14),
          if (list.isEmpty)
            _message('🔍', 'NOTHING HERE', 'No sessions match this filter.')
          else
            ..._history(list),
        ],
      ],
    );
  }

  // ── Header ────────────────────────────────────────────────────────────
  Widget _header(int count) => Block(
        color: Rb.hud,
        edge: Rb.hudEdge,
        depth: 6,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            const Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: BlockText('⚡ ACTIVITY LOG', size: 20, stroke: 4.5),
              ),
            ),
            const SizedBox(width: 8),
            Block(
              color: Rb.blue,
              edge: Rb.blueEdge,
              depth: 4,
              radius: 10,
              gloss: true,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: BlockText('$count ALL TIME', size: 11, stroke: 3),
            ),
          ],
        ),
      );

  // ── Filters ───────────────────────────────────────────────────────────
  Widget _filters() {
    Widget chip(String label, ActivityType? t, Color c, Color e) {
      final sel = _filter == t;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: PressBlock(
            color: sel ? c : Rb.panel,
            edge: sel ? e : Rb.panelEdge,
            depth: 5,
            radius: 12,
            forcePressed: sel,
            padding: const EdgeInsets.symmetric(vertical: 11),
            onTap: () => setState(() => _filter = t),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: BlockText(label, size: 12, stroke: 3),
              ),
            ),
          ),
        ),
      );
    }

    final w = _colors(ActivityType.walk);
    final j = _colors(ActivityType.jog);
    final r = _colors(ActivityType.run);
    return Row(children: [
      chip('ALL', null, Rb.gold, Rb.goldEdge),
      chip('🚶 WALK', ActivityType.walk, w.$1, w.$2),
      chip('⚡ JOG', ActivityType.jog, j.$1, j.$2),
      chip('🏃 RUN', ActivityType.run, r.$1, r.$2),
    ]);
  }

  // ── Summary ───────────────────────────────────────────────────────────
  Widget _summary(List<ActivitySession> list) {
    final km = list.fold<double>(0, (a, s) => a + s.distanceKm);
    final secs = list.fold<int>(0, (a, s) => a + s.durationSeconds);
    final h = secs ~/ 3600, m = (secs % 3600) ~/ 60;
    final time = h > 0 ? '${h}h ${m}m' : '${m}m';

    int count(ActivityType t) => list.where((s) => s.type == t).length;

    Widget stat(String emoji, String value, String label, Color c, Color e) =>
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Block(
              color: c,
              edge: e,
              depth: 5,
              radius: 12,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
              child: Column(children: [
                Text(emoji, style: const TextStyle(fontSize: 20)),
                FittedBox(
                    fit: BoxFit.scaleDown,
                    child: BlockText(value, size: 18, stroke: 4)),
                FittedBox(
                    fit: BoxFit.scaleDown,
                    child: BlockText(label, size: 9, stroke: 2.5)),
              ]),
            ),
          ),
        );

    return Column(children: [
      Row(children: [
        stat('📍', km.toStringAsFixed(1), 'TOTAL KM', Rb.green, Rb.greenEdge),
        stat('⏱️', time, 'ACTIVE TIME', Rb.blue, Rb.blueEdge),
        stat('🎯', '${list.length}', 'SESSIONS', Rb.orange, Rb.orangeEdge),
      ]),
      const SizedBox(height: 10),
      Block(
        color: Rb.panel,
        edge: Rb.panelEdge,
        depth: 5,
        radius: 12,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            for (final t in ActivityType.values)
              BlockText('${t.emoji} ${count(t)}', size: 14, stroke: 3.5),
          ],
        ),
      ),
    ]);
  }

  // ── 7-day distance chart ─────────────────────────────────────────────
  Widget _chart(List<ActivitySession> list) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = List.generate(7, (i) => today.subtract(Duration(days: 6 - i)));
    final totals = days.map((d) {
      return list
          .where((s) =>
              s.startTime.year == d.year &&
              s.startTime.month == d.month &&
              s.startTime.day == d.day)
          .fold<double>(0, (a, s) => a + s.distanceKm);
    }).toList();
    final maxV = totals.fold<double>(0, (a, b) => b > a ? b : a);
    const chartH = 110.0;

    return Block(
      color: Rb.panel,
      edge: Rb.panelEdge,
      depth: 6,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BlockText('📊 LAST 7 DAYS (KM)', size: 13, stroke: 3.5),
          const SizedBox(height: 10),
          SizedBox(
            height: chartH + 40,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: BlockText(
                              totals[i] > 0
                                  ? totals[i].toStringAsFixed(1)
                                  : '',
                              size: 9,
                              stroke: 2.5,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Container(
                            height: maxV <= 0
                                ? 4
                                : (totals[i] / maxV * chartH).clamp(4.0, chartH),
                            decoration: BoxDecoration(
                              color: i == 6 ? Rb.gold : Rb.green,
                              border:
                                  Border.all(color: Colors.black, width: 3),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          const SizedBox(height: 6),
                          BlockText(
                            DateFormat('E').format(days[i]).substring(0, 1),
                            size: 11,
                            stroke: 3,
                            color: i == 6 ? Rb.gold : Colors.white,
                          ),
                        ],
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

  // ── History ──────────────────────────────────────────────────────────
  List<Widget> _history(List<ActivitySession> list) {
    final out = <Widget>[];
    String? lastKey;
    for (final s in list) {
      final key = DateFormat('yyyyMMdd').format(s.startTime);
      if (key != lastKey) {
        lastKey = key;
        out.add(Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 10),
          child: Block(
            color: Rb.slate,
            edge: Rb.slateEdge,
            depth: 4,
            radius: 10,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: BlockText(
                '📅 ${DateFormat('MMMM d, yyyy').format(s.startTime).toUpperCase()}',
                size: 12,
                stroke: 3),
          ),
        ));
      }
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _sessionCard(s),
      ));
    }
    return out;
  }

  Widget _sessionCard(ActivitySession s) {
    final (c, e) = _colors(s.type);
    final overridden = s.userPick != s.type;

    Widget mini(String label, String value) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Block(
              color: Rb.slot,
              edge: Rb.panelEdge,
              depth: 3,
              radius: 8,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: Column(children: [
                FittedBox(
                    fit: BoxFit.scaleDown,
                    child: BlockText(value, size: 12, stroke: 3)),
                FittedBox(
                    fit: BoxFit.scaleDown,
                    child: BlockText(label, size: 8, stroke: 2)),
              ]),
            ),
          ),
        );

    return Block(
      color: Rb.panel,
      edge: Rb.panelEdge,
      depth: 6,
      padding: const EdgeInsets.all(10),
      child: Column(children: [
        Row(children: [
          Block(
            color: c,
            edge: e,
            depth: 4,
            radius: 10,
            padding: EdgeInsets.zero,
            child: SizedBox(
              width: 46,
              height: 46,
              child: Center(
                  child:
                      Text(s.type.emoji, style: const TextStyle(fontSize: 24))),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: BlockText(s.type.label.toUpperCase(),
                      size: 15, stroke: 3.5),
                ),
                BlockText(DateFormat('h:mm a').format(s.startTime),
                    size: 10, stroke: 2.5, color: const Color(0xFFB8BDC4)),
                if (overridden)
                  const BlockText('📡 GPS OVERRIDE',
                      size: 9, stroke: 2.5, color: Rb.neon),
              ],
            ),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Block(
              color: Rb.gold,
              edge: Rb.goldEdge,
              depth: 3,
              radius: 8,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: BlockText('+${s.xpEarned} XP', size: 11, stroke: 3),
            ),
            const SizedBox(height: 4),
            BlockText('🪙 ${s.coinsEarned}', size: 11, stroke: 3),
          ]),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          mini('KM', s.distanceKm.toStringAsFixed(2)),
          mini('TIME', s.formattedDuration),
          mini('PACE', s.formattedPace),
          mini('MAX', '${s.maxSpeedKmh.toStringAsFixed(1)}'),
        ]),
      ]),
    );
  }

  Widget _message(String emoji, String title, String sub) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Block(
          color: Rb.panel,
          edge: Rb.panelEdge,
          depth: 6,
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            Text(emoji, style: const TextStyle(fontSize: 40)),
            const SizedBox(height: 8),
            BlockText(title, size: 16, stroke: 4),
            const SizedBox(height: 4),
            BlockText(sub,
                size: 11,
                stroke: 2.5,
                color: const Color(0xFFB8BDC4),
                align: TextAlign.center),
          ]),
        ),
      );
}
