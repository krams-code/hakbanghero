import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../screens/friends/friends_screen.dart';
import '../services/friends_service.dart';
import '../utils/weekly.dart';
import 'block_ui.dart';
import 'hero_bust.dart';

/// "FRIENDS THIS WEEK" leaderboard for the RUN tab: you + your friends ranked
/// by km since Monday. Reads the `week_km` / `week_key` / `last_run_at` fields
/// that every saved run updates.
class FriendsWeekCard extends StatefulWidget {
  const FriendsWeekCard({super.key});

  @override
  State<FriendsWeekCard> createState() => _FriendsWeekCardState();
}

class _Row {
  final String uid;
  final String name;
  final Map<String, dynamic> data;
  final double km;
  final bool ranToday;
  final bool isMe;
  _Row(this.uid, this.name, this.data, this.km, this.ranToday, this.isMe);
}

class _FriendsWeekCardState extends State<FriendsWeekCard> {
  List<_Row>? _rows;
  int _friendCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null) return;
    try {
      final fs = await FriendsService.friends(me).get();
      final ids = [me, ...fs.docs.map((d) => d.id).take(15)];
      final key = Weekly.key(DateTime.now());
      final today = DateTime.now();
      final rows = <_Row>[];
      await Future.wait(ids.map((uid) async {
        try {
          final d = (await FriendsService.user(uid).get()).data();
          if (d == null) return;
          final km = d['week_key'] == key ? ((d['week_km'] as num?)?.toDouble() ?? 0) : 0.0;
          final last = (d['last_run_at'] as Timestamp?)?.toDate();
          final ranToday = last != null &&
              last.year == today.year &&
              last.month == today.month &&
              last.day == today.day;
          rows.add(_Row(uid, (d['username'] as String?) ?? 'Hero', d, km, ranToday, uid == me));
        } catch (_) {}
      }));
      rows.sort((a, b) => b.km.compareTo(a.km));
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _friendCount = fs.docs.length;
      });
    } catch (_) {
      if (mounted) setState(() => _rows = []);
    }
  }

  void _open() => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const FriendsScreen()))
      .then((_) => _load());

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    if (rows == null) return const SizedBox.shrink();

    return Block(
      color: const Color(0xFF1F5F4A),
      edge: const Color(0xFF0B2A20),
      depth: 6,
      radius: 18,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const BlockText('\u{1F465} FRIENDS THIS WEEK', size: 13, stroke: 3.5),
              const Spacer(),
              BlockText(Weekly.countdown(DateTime.now()), size: 9, stroke: 2.5),
            ],
          ),
          const SizedBox(height: 8),
          if (_friendCount == 0)
            Row(
              children: [
                const Expanded(
                  child: BlockText(
                    'Add a friend to see who is running this week — and challenge them to a live duel!',
                    size: 10.5,
                    stroke: 3,
                  ),
                ),
                const SizedBox(width: 8),
                PressBlock(
                  color: Rb.blue,
                  edge: Rb.blueEdge,
                  depth: 4,
                  radius: 10,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  onTap: _open,
                  child: const BlockText('ADD', size: 12, stroke: 3.5),
                ),
              ],
            )
          else ...[
            for (var i = 0; i < rows.length && i < 5; i++) _row(i, rows[i], rows.first.km),
            if (rows.length > 5)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: BlockText('+${rows.length - 5} more', size: 9.5, stroke: 2.5,
                    color: const Color(0xFFB8D4C8)),
              ),
            const SizedBox(height: 8),
            PressBlock(
              color: Rb.panel,
              edge: Rb.panelEdge,
              depth: 4,
              radius: 12,
              padding: const EdgeInsets.symmetric(vertical: 8),
              onTap: _open,
              child: const SizedBox(
                width: double.infinity,
                child: Center(child: BlockText('OPEN FRIENDS • CHAT • DUELS', size: 11, stroke: 3)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(int i, _Row r, double top) {
    final frac = top <= 0 ? 0.0 : (r.km / top).clamp(0.0, 1.0).toDouble();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: BlockText('${i + 1}', size: 12, stroke: 3,
                color: i == 0 ? Rb.gold : Colors.white),
          ),
          HeroBust(data: r.data, size: 34),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: BlockText(r.isMe ? 'YOU' : r.name, size: 11, stroke: 3, maxLines: 1,
                          color: r.isMe ? Rb.neon : Colors.white),
                    ),
                    if (r.ranToday)
                      const Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Text('\u{1F525}', style: TextStyle(fontSize: 11)),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                BlockBar(value: frac, height: 8, color: r.isMe ? Rb.neon : Rb.green),
              ],
            ),
          ),
          const SizedBox(width: 8),
          BlockText('${r.km.toStringAsFixed(1)} km', size: 11, stroke: 3),
        ],
      ),
    );
  }
}
