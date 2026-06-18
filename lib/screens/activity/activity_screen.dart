import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../models/activity_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Activity Screen — replaces StagesScreen
// ─────────────────────────────────────────────────────────────────────────────
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen>
    with TickerProviderStateMixin {
  late AnimationController _entryCtrl;
  late Animation<double> _entryFade;
  late Animation<Offset> _entrySlide;

  ActivityType? _filterType; // null = all

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600))
      ..forward();
    _entryFade = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    _entrySlide = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    super.dispose();
  }

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060C06),
      body: FadeTransition(
        opacity: _entryFade,
        child: SlideTransition(
          position: _entrySlide,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildHeader()),
              SliverToBoxAdapter(child: _buildFilterBar()),
              SliverToBoxAdapter(child: _buildStatsSummary()),
              _buildActivityList(),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 12,
        left: 16,
        right: 16,
        bottom: 12,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF0A1A0A),
            const Color(0xFF060C06).withOpacity(0),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.bolt, color: Color(0xFF00FF41), size: 22),
          const SizedBox(width: 10),
          const Text(
            'ACTIVITY LOG',
            style: TextStyle(
              color: Color(0xFFE8FFE8),
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF00FF41).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF00FF41).withOpacity(0.3)),
            ),
            child: const Text(
              'ALL TIME',
              style: TextStyle(
                color: Color(0xFF00FF41),
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _FilterChip(
              label: 'ALL',
              color: const Color(0xFF4A8A4A),
              isSelected: _filterType == null,
              onTap: () => setState(() => _filterType = null),
            ),
            const SizedBox(width: 8),
            ...ActivityType.values.map((t) {
              Color c;
              switch (t) {
                case ActivityType.walk: c = const Color(0xFF00CFFF); break;
                case ActivityType.jog:  c = const Color(0xFFFFD700); break;
                case ActivityType.run:  c = const Color(0xFF00FF41); break;
              }
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _FilterChip(
                  label: '${t.emoji} ${t.label.toUpperCase()}',
                  color: c,
                  isSelected: _filterType == t,
                  onTap: () => setState(() => _filterType = t),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsSummary() {
    if (_uid == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('activities')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox(height: 8);

        final sessions = snapshot.data!.docs
            .map((d) => ActivitySession.fromFirestore(d))
            .toList();

        final totalKm = sessions.fold<double>(
            0, (sum, s) => sum + s.distanceKm);
        final totalTime = sessions.fold<int>(
            0, (sum, s) => sum + s.durationSeconds);
        final totalRuns = sessions
            .where((s) => s.type == ActivityType.run)
            .length;
        final totalWalks = sessions
            .where((s) => s.type == ActivityType.walk)
            .length;
        final totalJogs = sessions
            .where((s) => s.type == ActivityType.jog)
            .length;

        final hours = totalTime ~/ 3600;
        final minutes = (totalTime % 3600) ~/ 60;
        final timeStr = hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            children: [
              Row(
                children: [
                  _SummaryCard(
                    label: 'TOTAL KM',
                    value: totalKm.toStringAsFixed(1),
                    unit: 'km',
                    color: const Color(0xFF00FF41),
                    icon: Icons.route,
                  ),
                  const SizedBox(width: 10),
                  _SummaryCard(
                    label: 'ACTIVE TIME',
                    value: timeStr,
                    unit: 'total',
                    color: const Color(0xFF00CFFF),
                    icon: Icons.timer,
                  ),
                  const SizedBox(width: 10),
                  _SummaryCard(
                    label: 'SESSIONS',
                    value: '${sessions.length}',
                    unit: 'total',
                    color: const Color(0xFFFFD700),
                    icon: Icons.flag,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Type breakdown
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1A0D),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF1A3A1A)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _TypeCount(emoji: '🚶', label: 'Walks', count: totalWalks,
                        color: const Color(0xFF00CFFF)),
                    _TypeCount(emoji: '🏃', label: 'Jogs', count: totalJogs,
                        color: const Color(0xFFFFD700)),
                    _TypeCount(emoji: '⚡', label: 'Runs', count: totalRuns,
                        color: const Color(0xFF00FF41)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActivityList() {
    if (_uid == null) {
      return const SliverToBoxAdapter(
        child: Center(
          child: Text('Not logged in',
              style: TextStyle(color: Color(0xFF3A5A3A))),
        ),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('activities')
          .orderBy('startTime', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFF00FF41)),
              ),
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return SliverToBoxAdapter(child: _buildEmpty());
        }

        var sessions = snapshot.data!.docs
            .map((d) => ActivitySession.fromFirestore(d))
            .toList();

        if (_filterType != null) {
          sessions = sessions
              .where((s) => s.type == _filterType)
              .toList();
        }

        if (sessions.isEmpty) {
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Center(
                child: Text(
                  'No ${_filterType?.label ?? ''} sessions yet.',
                  style: const TextStyle(color: Color(0xFF3A5A3A), fontSize: 13),
                ),
              ),
            ),
          );
        }

        // Group by date
        final grouped = <String, List<ActivitySession>>{};
        for (final s in sessions) {
          final key = DateFormat('MMMM d, yyyy').format(s.startTime);
          grouped.putIfAbsent(key, () => []).add(s);
        }

        return SliverList(
  delegate: SliverChildBuilderDelegate(
    (context, index) {
      final keys = grouped.keys.toList();

      // Build flat list: [header, card, card, header, card, ...]
      final items = <Widget>[];
      for (final key in keys) {
        items.add(_DateHeader(date: key));
        for (final session in grouped[key]!) {
          items.add(_ActivityCard(session: session));
        }
      }
      if (index >= items.length) return null;
      return items[index];
    },
    childCount: () {
      int count = 0;
      for (final key in grouped.keys) {
        count += 1 + grouped[key]!.length; // header + cards
      }
      return count;
    }(),
  ),
);
      },
    );
  }

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 0),
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1A0D),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF1A3A1A)),
        ),
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF1A3A1A),
                border: Border.all(color: const Color(0xFF2A5A2A)),
              ),
              child: const Icon(Icons.directions_run,
                  color: Color(0xFF3A6A3A), size: 32),
            ),
            const SizedBox(height: 16),
            const Text(
              'NO ACTIVITY YET',
              style: TextStyle(
                color: Color(0xFF4A8A4A),
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Hit START RUN on the home screen\nto log your first session!',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF3A5A3A), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Activity Card  — single session row (Strava-style)
// ─────────────────────────────────────────────────────────────────────────────
class _ActivityCard extends StatelessWidget {
  final ActivitySession session;

  const _ActivityCard({required this.session});

  Color get _typeColor {
    switch (session.type) {
      case ActivityType.walk: return const Color(0xFF00CFFF);
      case ActivityType.jog:  return const Color(0xFFFFD700);
      case ActivityType.run:  return const Color(0xFF00FF41);
    }
  }

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('h:mm a').format(session.startTime);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1A0D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _typeColor.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: _typeColor.withOpacity(0.04),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _typeColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _typeColor.withOpacity(0.3)),
                ),
                child: Center(
                  child: Text(session.type.emoji,
                      style: const TextStyle(fontSize: 18)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          session.type.label.toUpperCase(),
                          style: TextStyle(
                            color: _typeColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),
                        if (session.userPick != session.type) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFFCCCC44).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'GPS override',
                              style: const TextStyle(
                                color: Color(0xFFAAAA33),
                                fontSize: 8,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      time,
                      style: const TextStyle(
                        color: Color(0xFF4A7A4A),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              // XP badge
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD700).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '+${session.xpEarned} XP',
                      style: const TextStyle(
                        color: Color(0xFFFFD700),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '+${session.coinsEarned} 🪙',
                    style: const TextStyle(
                      color: Color(0xFF8A7A2A),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 12),
          const Divider(color: Color(0xFF1A3A1A), height: 1),
          const SizedBox(height: 12),

          // Stats
          Row(
            children: [
              _MiniStat(
                  label: 'DISTANCE',
                  value: '${session.distanceKm.toStringAsFixed(2)} km',
                  color: _typeColor),
              _MiniStat(
                  label: 'DURATION',
                  value: session.formattedDuration,
                  color: const Color(0xFFCCCCCC)),
              _MiniStat(
                  label: 'PACE',
                  value: session.formattedPace,
                  color: const Color(0xFFFFD700)),
              _MiniStat(
                  label: 'MAX SPD',
                  value: '${session.maxSpeedKmh.toStringAsFixed(1)} km/h',
                  color: const Color(0xFFFF6B35)),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF3A5A3A),
              fontSize: 8,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────
class _DateHeader extends StatelessWidget {
  final String date;
  const _DateHeader({required this.date});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Row(
        children: [
          Text(
            date.toUpperCase(),
            style: const TextStyle(
              color: Color(0xFF4A8A4A),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Divider(color: Color(0xFF1A3A1A), height: 1),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.15) : const Color(0xFF0D1A0D),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : const Color(0xFF1A3A1A),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? color : const Color(0xFF3A5A3A),
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color color;
  final IconData icon;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1A0D),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(height: 6),
            Text(value,
                style: TextStyle(
                    color: color,
                    fontSize: 16,
                    fontWeight: FontWeight.w800)),
            Text(unit,
                style: const TextStyle(
                    color: Color(0xFF3A5A3A), fontSize: 9)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(
                    color: Color(0xFF3A6A3A),
                    fontSize: 9,
                    letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }
}

class _TypeCount extends StatelessWidget {
  final String emoji;
  final String label;
  final int count;
  final Color color;

  const _TypeCount({
    required this.emoji,
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 20)),
        const SizedBox(height: 4),
        Text(
          '$count',
          style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w800),
        ),
        Text(
          label,
          style: const TextStyle(color: Color(0xFF3A5A3A), fontSize: 10),
        ),
      ],
    );
  }
}