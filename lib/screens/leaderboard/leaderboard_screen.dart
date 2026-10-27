import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../constants/app_icons.dart';
import '../../models/hero_roster.dart' show genderKey;
import '../../widgets/block_ui.dart';
import '../../widgets/pixel_icon.dart';
import '../../widgets/hero_sprite.dart';
import '../../services/friends_service.dart';
import '../friends/friends_screen.dart';
import '../../widgets/lottie_fx.dart';
import '../../widgets/player_card_sheet.dart';
import '../../utils/player_stats.dart' show LevelProgress;
import '../../utils/weekly.dart';
import '../../services/presence.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  // One-time reads (pull down to refresh), cached per tab. A live listener on
  // 100 full profiles re-downloaded them on every change and cost a lot of
  // Firestore reads.
  final Map<int, Future<QuerySnapshot<Map<String, dynamic>>>> _boards = {};
  Stream<QuerySnapshot<Map<String, dynamic>>>? _requests;

  int _timeIdx = 2; // 0 this week (km), 1 this month (km), 2 all time (XP)

  static String monthKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';

  Future<QuerySnapshot<Map<String, dynamic>>> _board(int idx,
      {bool refresh = false}) {
    if (!refresh && _boards[idx] != null) return _boards[idx]!;
    final users = FirebaseFirestore.instance.collection('users');
    final now = DateTime.now();
    final Query<Map<String, dynamic>> q = switch (idx) {
      0 => users
          .where('week_key', isEqualTo: Weekly.key(now))
          .orderBy('week_km', descending: true),
      1 => users
          .where('month_key', isEqualTo: monthKey(now))
          .orderBy('month_km', descending: true),
      _ => users.orderBy('xp', descending: true),
    };
    return _boards[idx] = q.limit(100).get();
  }
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
              child: FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                key: ValueKey(_timeIdx),
                future: _board(_timeIdx),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const LoadingRunner();
                  }
                  if (snapshot.hasError) {
                    return _refreshable(_emptyNote(
                        'Could not load the board. Pull down to try again.'));
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return _refreshable(_emptyNote(_timeIdx == 2
                        ? 'No heroes on the board yet.'
                        : 'Nobody has run ${_timeIdx == 0 ? 'this week' : 'this month'} yet. Be the first!'));
                  }

                  var entries = snapshot.data!.docs
                      .map((d) => _LeaderboardEntry.fromDoc(d, _timeIdx))
                      .toList();

                  // heroes who never picked BOY / GIRL (old or Google accounts)
                  final unknown =
                      entries.where((e) => genderKey(e.gender) == null).length;
                  if (_genderFilter != 'all') {
                    entries = entries
                        .where((e) => genderKey(e.gender) == _genderFilter)
                        .toList();
                  }
                  final note = _genderFilter != 'all' && unknown > 0
                      ? '$unknown hero${unknown == 1 ? '' : 'es'} on GLOBAL '
                          "haven't picked BOY or GIRL yet."
                      : null;
                  if (entries.isEmpty) {
                    return _refreshable(
                        _emptyNote(note ?? 'No heroes match this filter yet.'));
                  }

                  return RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: entries.length + (note == null ? 0 : 1),
                    itemBuilder: (context, i) {
                      if (note != null && i == entries.length) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(note,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800)),
                        );
                      }
                      return _buildRow(i + 1, entries[i], entries[i].uid == myUid);
                    },
                  ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _refresh() async {
    final f = _board(_timeIdx, refresh: true);
    setState(() {});
    try {
      await f;
    } catch (_) {}
  }

  /// Lets an empty / error message be pulled down to reload.
  Widget _refreshable(Widget child) => RefreshIndicator(
        onRefresh: _refresh,
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(height: box.maxHeight, child: child),
          ),
        ),
      );

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
      child: Row(
        children: [
          const Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: IconLabel(
                iconPath: AppIcons.ranksTrophy,
                iconSize: 32,
                gap: 8,
                label: BlockText('LEADERBOARD', size: 22, stroke: 5),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _friendsButton(),
        ],
      ),
    );
  }

  /// Opens the Friends hub; shows a red dot while friend requests wait.
  Widget _friendsButton() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: uid == null ? null : (_requests ??= FriendsService.requests.where('to', isEqualTo: uid).snapshots()),
      builder: (context, snap) {
        final pending = snap.data?.docs
                .where((d) => d.data()['status'] == 'pending')
                .length ??
            0;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            PressBlock(
              color: Rb.blue,
              edge: Rb.blueEdge,
              depth: 4,
              radius: 12,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const FriendsScreen()),
              ),
              child: const BlockText('\u{1F465} FRIENDS', size: 12, stroke: 3.5),
            ),
            if (pending > 0)
              Positioned(
                right: -5,
                top: -5,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: Rb.red,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.black, width: 2),
                  ),
                  child: Text('$pending',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)),
                ),
              ),
          ],
        );
      },
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
    Widget chip(String label, String value) {
      final selected = _genderFilter == value;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: PressBlock(
          color: selected ? Rb.green : Rb.slot,
          edge: selected ? Rb.greenEdge : Rb.slateEdge,
          depth: 4,
          radius: 12,
          forcePressed: selected,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          onTap: () => setState(() => _genderFilter = value),
          child: BlockText(label, size: 11, stroke: 3),
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
        ],
      ),
    );
  }

  // ───────────────────────── player row ─────────────────────────

  Widget _buildRow(int rank, _LeaderboardEntry entry, bool isMe) {
    return PressBlock(
      color: isMe ? const Color(0xFF1E4A66) : Rb.slate,
      edge: isMe ? Rb.blueEdge : Rb.slateEdge,
      depth: 6,
      radius: 16,
      padding: const EdgeInsets.all(10),
      onTap: () => showPlayerCard(context,
          uid: entry.uid, data: entry.data, rank: rank, isMe: isMe),
      child: Row(
        children: [
          _RankTile(rank: rank),
          const SizedBox(width: 10),
          // framed bust thumbnail (+ live online dot)
          Stack(
            clipBehavior: Clip.none,
            children: [
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
              Positioned(
                right: -4,
                bottom: -4,
                child: PresenceDotOnce(entry.uid, size: 15),
              ),
            ],
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
                  child: BlockText(
                      entry.byKm
                          ? entry.km.toStringAsFixed(1)
                          : _formatNum(entry.score),
                      size: 26,
                      stroke: 5,
                      color: Rb.gold),
                ),
                BlockText(entry.byKm ? 'KM' : 'XP', size: 10, stroke: 3),
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
            child: HeroSprite.fromData(data,
                height: size * 2.4, ownerUid: uid, bust: true),
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

  /// Week / month boards rank by km run in that period.
  final bool byKm;
  final double km;

  _LeaderboardEntry({
    this.byKm = false,
    this.km = 0,
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

  factory _LeaderboardEntry.fromDoc(QueryDocumentSnapshot doc, [int tab = 2]) {
    final d = doc.data() as Map<String, dynamic>;
    return _LeaderboardEntry(
      byKm: tab != 2,
      km: ((tab == 0 ? d['week_km'] : d['month_km']) as num?)?.toDouble() ?? 0,
      uid: doc.id,
      username: d['username'] ?? 'Hero',
      level: LevelProgress.fromXp((d['xp'] as num?)?.toInt() ?? 0).level,
      xp: (d['xp'] as num?)?.toInt() ?? 0,
      totalKm: (d['total_km'] as num?)?.toDouble() ?? 0.0,
      gender: d['gender'] as String?,
      data: d,
    );
  }
}
