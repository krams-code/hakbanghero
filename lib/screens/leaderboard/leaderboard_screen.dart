import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../theme/app_colors.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _timeTabCtrl;
  String _genderFilter = 'all';

  @override
  void initState() {
    super.initState();
    _timeTabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _timeTabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildTimeTabs(),
            _buildFilterChips(),
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
                        child: CircularProgressIndicator(color: AppColors.blue));
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Center(
                      child: Text('No heroes on the board yet.',
                          style: TextStyle(color: AppColors.textSub)),
                    );
                  }

                  var entries = snapshot.data!.docs
                      .map((d) => _LeaderboardEntry.fromDoc(d))
                      .toList();

                  if (_genderFilter != 'all') {
                    entries = entries
                        .where((e) => e.gender == _genderFilter)
                        .toList();
                  }

                  if (entries.isEmpty) {
                    return const Center(
                      child: Text('No heroes match this filter yet.',
                          style: TextStyle(color: AppColors.textSub)),
                    );
                  }

                  final top3 = entries.take(3).toList();
                  final rest =
                      entries.length > 3 ? entries.sublist(3) : <_LeaderboardEntry>[];

                  return ListView(
                    padding: const EdgeInsets.only(bottom: 16),
                    children: [
                      if (top3.isNotEmpty) _buildPodium(top3),
                      const SizedBox(height: 8),
                      ...List.generate(rest.length, (i) {
                        final rank = i + 4;
                        final entry = rest[i];
                        final isMe = entry.uid == myUid;
                        return _buildRow(rank, entry, isMe);
                      }),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: [
          const Icon(Icons.leaderboard, color: AppColors.blue, size: 20),
          const SizedBox(width: 8),
          const Text(
            'LEADERBOARD',
            style: TextStyle(
              color: AppColors.blue,
              fontSize: 15,
              fontWeight: FontWeight.w900,
              letterSpacing: 3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeTabs() {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          decoration: BoxDecoration(
            color: AppColors.bgPanel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderDim),
          ),
          child: TabBar(
            controller: _timeTabCtrl,
            indicator: BoxDecoration(
              color: AppColors.blue.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.blue.withOpacity(0.5)),
            ),
            labelColor: AppColors.blue,
            unselectedLabelColor: AppColors.textSub,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
            tabs: const [
              Tab(text: 'THIS WEEK'),
              Tab(text: 'THIS MONTH'),
              Tab(text: 'ALL TIME'),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Row(
            children: const [
              Icon(Icons.info_outline, color: AppColors.textSub, size: 12),
              SizedBox(width: 4),
              Text('Week/Month filtering coming soon — showing All Time',
                  style: TextStyle(color: AppColors.textSub, fontSize: 10)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChips() {
    Widget chip(String label, String value, {bool disabled = false}) {
      final selected = _genderFilter == value;
      return GestureDetector(
        onTap: disabled
            ? () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Local leaderboard coming soon!')),
                )
            : () => setState(() => _genderFilter = value),
        child: Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppColors.blue.withOpacity(0.15) : AppColors.bgCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: disabled
                  ? AppColors.borderDim.withOpacity(0.4)
                  : (selected ? AppColors.blue : AppColors.borderDim),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: disabled
                  ? AppColors.textSub.withOpacity(0.6)
                  : (selected ? AppColors.blue : AppColors.textSub),
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            chip('GLOBAL', 'all'),
            chip('BOYS', 'male'),
            chip('GIRLS', 'female'),
            chip('LOCAL 📍', 'local', disabled: true),
          ],
        ),
      ),
    );
  }

  Widget _buildPodium(List<_LeaderboardEntry> top3) {
    final first  = top3.isNotEmpty ? top3[0] : null;
    final second = top3.length > 1 ? top3[1] : null;
    final third  = top3.length > 2 ? top3[2] : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: second != null ? _podiumSlot(second, 2, AppColors.silver, 90) : const SizedBox()),
          Expanded(child: first != null ? _podiumSlot(first, 1, AppColors.gold, 120) : const SizedBox()),
          Expanded(child: third != null ? _podiumSlot(third, 3, AppColors.red, 74) : const SizedBox()),
        ],
      ),
    );
  }

  Widget _podiumSlot(_LeaderboardEntry entry, int rank, Color color, double height) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (rank == 1) const Icon(Icons.emoji_events, color: AppColors.gold, size: 26),
        const SizedBox(height: 4),
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2.5),
                boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 10)],
              ),
              child: CircleAvatar(
                radius: rank == 1 ? 32 : 26,
                backgroundColor: AppColors.bgCard,
                child: Text(
                  entry.username.isNotEmpty ? entry.username[0].toUpperCase() : '?',
                  style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: rank == 1 ? 24 : 18),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Text('$rank',
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 11)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(entry.username,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textMain, fontWeight: FontWeight.bold, fontSize: 12)),
        Text('LV ${entry.level}', style: const TextStyle(color: AppColors.textSub, fontSize: 10)),
        const SizedBox(height: 6),
        Container(
          height: height,
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [color.withOpacity(0.25), AppColors.bgCard],
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            border: Border.all(color: color.withOpacity(0.5)),
          ),
          alignment: Alignment.topCenter,
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            _formatXp(entry.xp),
            style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 15),
          ),
        ),
      ],
    );
  }

  Widget _buildRow(int rank, _LeaderboardEntry entry, bool isMe) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isMe ? AppColors.blue.withOpacity(0.08) : AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isMe ? AppColors.blue : AppColors.borderDim.withOpacity(0.4),
            width: isMe ? 1.5 : 1),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text('#$rank',
                style: TextStyle(
                    color: isMe ? AppColors.blue : AppColors.textSub,
                    fontWeight: FontWeight.bold,
                    fontSize: 13)),
          ),
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.bgPanel,
            child: Text(
              entry.username.isNotEmpty ? entry.username[0].toUpperCase() : '?',
              style: TextStyle(
                  color: isMe ? AppColors.blue : AppColors.textMain,
                  fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMe ? '${entry.username} (You)' : entry.username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: isMe ? AppColors.blue : AppColors.textMain,
                      fontWeight: FontWeight.bold,
                      fontSize: 13),
                ),
                Text('LV ${entry.level} · ${entry.totalKm.toStringAsFixed(1)} km',
                    style: const TextStyle(color: AppColors.textSub, fontSize: 10)),
              ],
            ),
          ),
          Text(_formatXp(entry.xp),
              style: TextStyle(
                  color: isMe ? AppColors.blue : AppColors.gold,
                  fontWeight: FontWeight.w900,
                  fontSize: 14)),
        ],
      ),
    );
  }

  String _formatXp(int xp) =>
      xp.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
}

class _LeaderboardEntry {
  final String uid;
  final String username;
  final int level;
  final int xp;
  final double totalKm;
  final String? gender;

  _LeaderboardEntry({
    required this.uid,
    required this.username,
    required this.level,
    required this.xp,
    required this.totalKm,
    this.gender,
  });

  factory _LeaderboardEntry.fromDoc(QueryDocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return _LeaderboardEntry(
      uid: doc.id,
      username: d['username'] ?? 'Hero',
      level: (d['level'] as num?)?.toInt() ?? 1,
      xp: (d['xp'] as num?)?.toInt() ?? 0,
      totalKm: (d['total_km'] as num?)?.toDouble() ?? 0.0,
      gender: d['gender'] as String?,
    );
  }
}