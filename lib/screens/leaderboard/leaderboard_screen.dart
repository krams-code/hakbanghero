import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../widgets/block_ui.dart';
import '../../widgets/hero_sprite.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  int _timeIdx = 2; // 0 week, 1 month, 2 all time (only all-time is live)
  String _genderFilter = 'all';

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: Rb.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                children: [
                  _buildHeader(),
                  const SizedBox(height: 4),
                  _buildTimeTabs(),
                  _buildFilterChips(),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .orderBy('xp', descending: true)
                    .limit(100)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                        child: CircularProgressIndicator(color: Rb.green));
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return _emptyNote('No heroes on the board yet.');
                  }

                  var entries = snapshot.data!.docs
                      .map((d) => _LeaderboardEntry.fromDoc(d))
                      .toList();

                  if (_genderFilter != 'all') {
                    entries =
                        entries.where((e) => e.gender == _genderFilter).toList();
                  }
                  if (entries.isEmpty) {
                    return _emptyNote('No heroes match this filter yet.');
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: entries.length,
                    itemBuilder: (context, i) =>
                        _buildRow(i + 1, entries[i], entries[i].uid == myUid),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyNote(String text) => Center(
        child: Block(
          color: Rb.slate,
          edge: Rb.slateEdge,
          padding: const EdgeInsets.all(18),
          child: Text(
            text,
            style: const TextStyle(
                color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w900),
          ),
        ),
      );

  // ───────────────────────── header + filters ─────────────────────────

  Widget _buildHeader() {
    return Block(
      color: Rb.gold,
      edge: Rb.goldEdge,
      depth: 6,
      gloss: true,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: const SizedBox(
        width: double.infinity,
        child: BlockText('🏆 LEADERBOARD', size: 22, stroke: 5),
      ),
    );
  }

  Widget _buildTimeTabs() {
    const labels = ['THIS WEEK', 'THIS MONTH', 'ALL TIME'];
    return Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < labels.length; i++) ...[
              Expanded(
                child: PressBlock(
                  color: _timeIdx == i ? Rb.blue : Rb.panel,
                  edge: _timeIdx == i ? Rb.blueEdge : Rb.panelEdge,
                  depth: 5,
                  radius: 12,
                  forcePressed: _timeIdx == i,
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                  onTap: () => setState(() => _timeIdx = i),
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: BlockText(labels[i], size: 11, stroke: 3),
                    ),
                  ),
                ),
              ),
              if (i != labels.length - 1) const SizedBox(width: 8),
            ],
          ],
        ),
        const Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: Text(
            'Week/Month filtering coming soon — showing All Time',
            style: TextStyle(
                color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChips() {
    Widget chip(String label, String value, {bool disabled = false}) {
      final selected = _genderFilter == value;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: PressBlock(
          color: disabled
              ? Rb.panel
              : selected
                  ? Rb.green
                  : Rb.slot,
          edge: disabled
              ? Rb.panelEdge
              : selected
                  ? Rb.greenEdge
                  : Rb.slateEdge,
          depth: 4,
          radius: 12,
          forcePressed: selected && !disabled,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          onTap: disabled
              ? () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Local leaderboard coming soon!')),
                  )
              : () => setState(() => _genderFilter = value),
          child: BlockText(label, size: 11, stroke: 3,
              color: disabled ? Colors.white54 : Colors.white),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip('GLOBAL', 'all'),
          chip('BOYS', 'male'),
          chip('GIRLS', 'female'),
          chip('LOCAL 📍', 'local', disabled: true),
        ],
      ),
    );
  }

  // ───────────────────────── player row ─────────────────────────

  Widget _buildRow(int rank, _LeaderboardEntry entry, bool isMe) {
    return Block(
      color: isMe ? const Color(0xFF1E4A66) : Rb.slate,
      edge: isMe ? Rb.blueEdge : Rb.slateEdge,
      depth: 6,
      radius: 16,
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          _RankTile(rank: rank),
          const SizedBox(width: 10),
          // framed bust thumbnail
          Block(
            color: const Color(0xFF8FD0FF),
            edge: Colors.black,
            depth: 3,
            radius: 12,
            padding: EdgeInsets.zero,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: _BustThumb(uid: entry.uid, data: entry.data, size: 66),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BlockText(entry.username, size: 14, stroke: 3.5, maxLines: 1),
                const SizedBox(height: 3),
                Text(
                  'LV ${entry.level} · ${entry.totalKm.toStringAsFixed(1)} km',
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w800),
                ),
                if (isMe)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Block(
                      color: Rb.blue,
                      edge: Rb.blueEdge,
                      depth: 2,
                      radius: 6,
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      child: const BlockText('YOU', size: 9, stroke: 2.5),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // massive score. Ranking is by XP; swap `score` for a steps field
          // (and the Firestore orderBy) if you want a steps board.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 104),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: BlockText(_formatNum(entry.score),
                      size: 26, stroke: 5, color: Rb.gold),
                ),
                const BlockText('XP', size: 10, stroke: 3),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatNum(int n) => n
      .toString()
      .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
}

// ───────────────────────── Rank trophy tile ─────────────────────────

class _RankTile extends StatelessWidget {
  final int rank;
  const _RankTile({required this.rank});

  static String _ordinal(int n) {
    if (n % 100 >= 11 && n % 100 <= 13) return 'TH';
    switch (n % 10) {
      case 1: return 'ST';
      case 2: return 'ND';
      case 3: return 'RD';
      default: return 'TH';
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color fill, edge;
    switch (rank) {
      case 1: fill = Rb.gold;   edge = Rb.goldEdge;   break;
      case 2: fill = Rb.silver; edge = Rb.silverEdge; break;
      case 3: fill = Rb.bronze; edge = Rb.bronzeEdge; break;
      default: fill = Rb.slot;  edge = Rb.slateEdge;
    }

    return Block(
      color: fill,
      edge: edge,
      depth: 4,
      radius: 12,
      gloss: rank <= 3,
      padding: EdgeInsets.zero,
      child: SizedBox(
        width: 50,
        height: 50,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BlockText('$rank', size: 22, stroke: 4.5),
              BlockText(_ordinal(rank), size: 9, stroke: 3),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── Bust thumbnail ─────────────────────────

/// Head-and-chest crop of the player's hero, so faces and hair stay readable
/// in a small square. (A full 286x512 body would be tiny at this size.)
class _BustThumb extends StatelessWidget {
  final Map<String, dynamic> data;
  final double size;
  /// Whose hero this is. If it is the signed-in player, the body follows the
  /// global evolution state (instant). Other players are shown as stored.
  final String uid;
  const _BustThumb({required this.uid, required this.data, required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topCenter,
          minWidth: 0,
          maxWidth: double.infinity,
          minHeight: 0,
          maxHeight: double.infinity,
          child: Transform.translate(
            offset: Offset(0, size * 0.2), // room for tall hair above the head
            child: HeroSprite.fromData(data, height: size * 2.4, ownerUid: uid),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── Data ─────────────────────────

class _LeaderboardEntry {
  final String uid;
  final String username;
  final int level;
  final int xp;
  final double totalKm;
  final String? gender;

  /// Full user doc, passed to HeroSprite.fromData for the appearance fields.
  final Map<String, dynamic> data;

  _LeaderboardEntry({
    required this.uid,
    required this.username,
    required this.level,
    required this.xp,
    required this.totalKm,
    required this.data,
    this.gender,
  });

  /// The number shown big on the right (the board is ranked by XP).
  int get score => xp;

  factory _LeaderboardEntry.fromDoc(QueryDocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return _LeaderboardEntry(
      uid: doc.id,
      username: d['username'] ?? 'Hero',
      level: (d['level'] as num?)?.toInt() ?? 1,
      xp: (d['xp'] as num?)?.toInt() ?? 0,
      totalKm: (d['total_km'] as num?)?.toDouble() ?? 0.0,
      gender: d['gender'] as String?,
      data: d,
    );
  }
}
